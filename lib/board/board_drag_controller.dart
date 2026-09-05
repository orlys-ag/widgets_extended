/// The board's drag layer: the session controller, and the autoscroll
/// behaviour a session owns.
///
/// Key-only: layout and commit reporting never read an item's payload.
/// The controller talks to the render layer exclusively through
/// `BoardRenderPort` and owns policy, the coalesced notification channel,
/// the per-move `pointerPosition`, and the explicit commit script; drag
/// TIMING is not owned here, it is read off the board controller's
/// `animationStyle` once per session.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '_board_drop_fit.dart';
import '_board_drop_resolver.dart';
import '_board_span.dart';
import 'board_config.dart';
import 'board_controller.dart';
import 'board_render_port.dart';

export '_board_drop_resolver.dart' show BoardDragKind, BoardDropTarget;

/// Everything one drag owns. Torn down at exactly one site.
class _DragSession<TKey> {
  _DragSession({
    required this.key,
    required this.kind,
    required this.port,
    required this.grabOffset,
    required this.grabCellRow,
    required this.grabCellCol,
    required this.makeRoomDuration,
    required this.makeRoomCurve,
    required this.dropSettleDuration,
    required this.dropSettleCurve,
    required this.autoScroller,
  });

  final TKey key;
  final BoardDragKind kind;
  final BoardRenderPort<TKey> port;

  /// Pointer minus the item's painted top-left at lift: what places the
  /// PROXY, and, on the continuous snaps, what makes the resolved anchor
  /// the item's would-be corner rather than the finger.
  final Offset grabOffset;

  /// The lift pointer's cell minus the item's start cell, per axis: the
  /// track snap's whole-cell grab offset, so the grabbed cell stays
  /// under the pointer while within-cell grab detail is discarded.
  final int grabCellRow;
  final int grabCellCol;

  /// The session's captured values; the kill switch re-reads the live
  /// style at every install and dominates them.
  final Duration makeRoomDuration;
  final Curve makeRoomCurve;
  final Duration dropSettleDuration;
  final Curve dropSettleCurve;

  final BoardAutoScroller autoScroller;

  ScrollPosition? verticalSubscription;
  ScrollPosition? horizontalSubscription;
}

/// Drag-and-drop and drag-resize over a board.
class BoardDragController<TKey> extends ChangeNotifier {
  BoardDragController({
    required this.boardController,
    required TickerProvider vsync,
    required this.config,
  }) : _vsync = vsync;

  /// Key-only: the drag layer never reads a payload.
  final BoardController<TKey, Object?> boardController;

  final BoardDragConfig<TKey> config;

  final TickerProvider _vsync;

  final ValueNotifier<Offset?> _pointerPosition = ValueNotifier<Offset?>(
    null,
  );

  _DragSession<TKey>? _session;
  BoardDropTarget? _currentTarget;

  /// The span the RESOLVER last returned, which is not always what
  /// [_currentTarget] holds: a nudged target is a different span by
  /// construction. The early-out in [_resolve] compares against this so
  /// it compares like with like, and a pointer that has not left its
  /// resolved placement re-runs neither the gate nor the scan.
  BoardSpan? _lastResolvedSpan;

  /// Whether a post-frame re-resolve is already scheduled for this
  /// frame, so a frame with several animation dispatches resolves once.
  bool _resolvePending = false;

  /// The pointer's viewport-paint position while a session is live, one
  /// write per move event; null between sessions.
  ValueListenable<Offset?> get pointerPosition {
    return _pointerPosition;
  }

  /// What the drag currently resolves to: a whole prospective SPAN whose
  /// leading cell is derived, never stored.
  BoardDropTarget? get currentTarget {
    return _currentTarget;
  }

  TKey? get draggedKey {
    return _session?.key;
  }

  /// The live session's kind, or null between sessions. Non-null exactly
  /// when [draggedKey] is: both read the session and store nothing, which
  /// is what makes it the proxy's gate rather than [currentTarget], whose
  /// kind is unreadable over a canDropAt-refused cell by design.
  BoardDragKind? get draggedKind {
    return _session?.kind;
  }

  /// The proxy's would-be top-left in viewport-paint space: the pointer
  /// minus the session's grab offset. Null between sessions.
  Offset? get proxyTopLeft {
    final session = _session;
    final pointer = _pointerPosition.value;
    if (session == null || pointer == null) {
      return null;
    }
    return pointer - session.grabOffset;
  }

  /// The dragged item's painted size, for the proxy. Null between
  /// sessions or when the item has no rect.
  Size? get proxySize {
    final session = _session;
    if (session == null) {
      return null;
    }
    return session.port.rectOfItem(session.key)?.size;
  }

  /// Fixes the session's kind from the handle's [edge] and [axis]:
  /// `none` starts a move; `leading` and `trailing` start a resize on
  /// [axis], or on the SPAN axis (the non-primary one) when [axis] is
  /// null, which is the convention that lets an axis-less edge value
  /// name one of the four kinds. `both` is a set-valued policy,
  /// uninterpretable per session, and refuses.
  BoardDragKind? _kindFor(BoardResizeEdges edge, Axis? axis) {
    final vertical = (axis ?? _spanAxis) == Axis.vertical;
    switch (edge) {
      case BoardResizeEdges.none:
        return BoardDragKind.move;
      case BoardResizeEdges.leading:
        return vertical
            ? BoardDragKind.resizeRowStart
            : BoardDragKind.resizeColStart;
      case BoardResizeEdges.trailing:
        return vertical
            ? BoardDragKind.resizeRowEnd
            : BoardDragKind.resizeColEnd;
      case BoardResizeEdges.both:
        return null;
    }
  }

  /// The span axis: the one the controller's primary axis is not.
  Axis get _spanAxis {
    return boardController.primaryAxis == Axis.horizontal
        ? Axis.vertical
        : Axis.horizontal;
  }

  static bool _edgeAccepted(BoardResizeEdges policy, BoardResizeEdges edge) {
    switch (policy) {
      case BoardResizeEdges.none:
        return false;
      case BoardResizeEdges.leading:
        return edge == BoardResizeEdges.leading;
      case BoardResizeEdges.trailing:
        return edge == BoardResizeEdges.trailing;
      case BoardResizeEdges.both:
        return true;
    }
  }

  /// Starts a session. Returns false for a POLICY refusal: disabled
  /// config, unknown or refused key, a board that has not laid out, a
  /// resize this config could not report (a null `onItemResized` would
  /// move pixels and then vanish), or a resize edge its axis's policy
  /// does not accept: `resizeEdges` on the span axis, which a null
  /// [axis] names, and `primaryResizeEdges` on the primary axis. Throws
  /// [ArgumentError] only for cross-controller misuse: a [renderPort]
  /// not driven by [boardController].
  bool startDrag({
    required TKey key,
    required BoardRenderPort<TKey> renderPort,
    required Offset pointerGlobal,
    BoardResizeEdges edge = BoardResizeEdges.none,
    Axis? axis,
  }) {
    if (!renderPort.drivesController(boardController)) {
      throw ArgumentError(
        "BoardDragController.startDrag: the render port is not driven by "
        "this controller's boardController. One drag controller serves "
        "one board.",
      );
    }
    if (_session != null || !config.enabled || !renderPort.isLaidOut) {
      return false;
    }
    if (!boardController.contains(key)) {
      return false;
    }
    if (config.canDrag != null && !config.canDrag!(key)) {
      return false;
    }
    final kind = _kindFor(edge, axis);
    if (kind == null) {
      return false;
    }
    if (kind != BoardDragKind.move) {
      if (config.onItemResized == null) {
        return false;
      }
      // Each axis carries its own policy, so a config that opens the
      // span axis leaves the primary one closed and the reverse.
      final policy = (axis ?? _spanAxis) == _spanAxis
          ? config.resizeEdges
          : config.primaryResizeEdges;
      if (!_edgeAccepted(policy, edge)) {
        return false;
      }
    }
    final local = renderPort.globalToPaintLocal(pointerGlobal);
    final rect = renderPort.rectOfItem(key);
    if (rect == null) {
      return false;
    }
    // Timing resolved once per session; the kill switch re-reads the
    // live style at every install and dominates these values.
    final style = boardController.animationStyle;
    final makeRoom = style.effectiveMakeRoom;
    final dropSettle = boardController.animationStyle.effectiveDropSettle;
    // The last policy check has passed: take the pin and the bit.
    final span = boardController.spanOf(key)!;
    // The lift pointer's fractional cell, sampled once: the track snap's
    // grab offset is in WHOLE cells.
    final liftCell = renderPort.trackSpaceAt(local);
    renderPort.pinItem(key);
    boardController.markDragging(
      key,
      dragging: true,
      onMutationCancel: _handleMutationCancel,
    );
    final session = _DragSession<TKey>(
      key: key,
      kind: kind,
      port: renderPort,
      grabOffset: kind == BoardDragKind.move
          ? local - rect.topLeft
          : Offset.zero,
      grabCellRow: liftCell == null
          ? 0
          : liftCell.row.floor() - span.rowStart,
      grabCellCol: liftCell == null
          ? 0
          : liftCell.col.floor() - span.colStart,
      makeRoomDuration: makeRoom.duration,
      makeRoomCurve: makeRoom.curve,
      dropSettleDuration: dropSettle.duration,
      dropSettleCurve: dropSettle.curve,
      autoScroller: BoardAutoScroller(
        vsync: _vsync,
        port: renderPort,
        edgeZone: config.autoScrollEdgeZone,
        maxVelocity: config.autoScrollMaxVelocity,
        // The tick re-points the scroll subscriptions BEFORE its jumpTo:
        // a position swapped mid-hold leaves the listener on the dead
        // one, and with no pointer event coming, nothing else can move
        // it. The tick itself never resolves; the notification its
        // jumpTo fires into the re-pointed listener is the one route to
        // the resolution core.
        onTick: _repointForSession,
      ),
    );
    _session = session;
    _bindScrollSubscriptions(session);
    // The animation channel is the third route into the resolution core,
    // beside pointer events and scroll notifications: a track resizing
    // above a stationary pointer moves the cell under it, and nothing
    // else re-resolves for that.
    boardController.addAnimationListener(_handleAnimationTick);
    if (config.hapticsOnDrag) {
      HapticFeedback.mediumImpact();
    }
    _pointerPosition.value = local;
    _resolve(session, local);
    // Evaluated at start too, not only per move: a finger that lifts an
    // item already inside an edge zone autoscrolls with no move event
    // ever arriving.
    session.autoScroller.evaluate(local);
    notifyListeners();
    return true;
  }

  /// One pointer move. Also the autoscroll evaluation site: started and
  /// stopped from the FINGER's viewport position, never the proxy's.
  void updateDrag(Offset pointerGlobal) {
    final session = _session;
    if (session == null) {
      return;
    }
    final local = session.port.globalToPaintLocal(pointerGlobal);
    _pointerPosition.value = local;
    _resolve(session, local);
    session.autoScroller.evaluate(local);
  }

  /// Ends the session, in the order the mutation-cancel rule forces:
  /// resolve and validate FIRST (nothing reported), TEAR DOWN second
  /// (the same statements every other exit runs), REPORT last, so the
  /// dragging bit is already clear when an `onItemMoved` handler
  /// mutates the dragged key.
  void endDrag({required bool cancel}) {
    final session = _session;
    if (session == null) {
      return;
    }
    final target = _currentTarget;
    var report = !cancel && target != null;
    if (report &&
        config.canDropAt != null &&
        !config.canDropAt!(session.key, target.span)) {
      report = false;
    }
    // The RESIZED item's painted corner, captured before the snap
    // clears its de-lane hold: the commit's own FLIP slide starts from
    // its old lane origin, and the glide below corrects onto this.
    Offset? paintedBefore;
    Offset? paintedExtentBefore;
    if (report && session.kind != BoardDragKind.move) {
      final rect = session.port.rectOfItem(session.key);
      if (rect != null) {
        paintedBefore =
            rect.topLeft +
            boardController.anim.offsetOfItem(
              boardController.idOfKey(session.key),
            );
        // The PAINTED extent, which the resize preview has been holding:
        // `rectOfItem` already carries it, the geometry rule composing
        // the preview into the extent it reports. The glide continues
        // from here, and the report's own FLIP is suppressed for it.
        paintedExtentBefore = Offset(rect.width, rect.height);
      }
    }
    Map<TKey, Offset>? paintedByKey;
    if (report) {
      // The COMMIT HAND-OFF's painted truth, captured BEFORE the snap:
      // where every item the preview holds paints this instant. The
      // session's own key is the glide's below, not the hand-off's.
      paintedByKey = _capturePaintedByKey(session);
      // snapForCommit: the report's mutation reassigns the displaced
      // neighbours' structure by exactly the held amounts, so the
      // offsets must vanish in this same synchronous sequence; an
      // animated release would double-count against the reassignment
      // for its whole window and the neighbours would overshoot a lane
      // and glide back. What the snap discards MID-MOTION is handed on
      // below, from the painted truth captured above, so structure
      // lands now and nothing painted steps. A cancel keeps the
      // animated close in teardown.
      boardController.releaseMakeRoomPreview(duration: Duration.zero);
    }
    // Captured before teardown nulls the pointer: the glide's FROM is
    // the proxy's release position.
    final release = _pointerPosition.value;
    _teardown(session);
    if (report && target != null) {
      // The report's mutation re-lanes exactly the neighbours the
      // preview displaced, whose landing the hand-off below owns, so
      // their relane LEADS are suppressed for its duration, in whatever
      // door the app mutates through. Their extents install as
      // everywhere else, the preview having held none. The widget's
      // built-in semantics move action reports outside any session and
      // is deliberately not wrapped: nothing is held there.
      boardController.withoutRelaneLeads(() {
        if (target.kind == BoardDragKind.move) {
          config.onItemMoved(session.key, target.span);
        } else {
          config.onItemResized!(session.key, target.span);
        }
      });
    }
    if (paintedByKey != null) {
      _installMakeRoomHandOff(session, paintedByKey);
    }
    _installDropSettle(session, release, paintedBefore, paintedExtentBefore);
  }

  /// The hand-off's capture: the painted top-left corner of every item
  /// the make-room preview holds an offset for, except the session's
  /// own. Paint space, composed with every animation offset, which is
  /// what makes it painted truth rather than structure.
  Map<TKey, Offset> _capturePaintedByKey(_DragSession<TKey> session) {
    final painted = <TKey, Offset>{};
    for (final key in boardController.makeRoomHeldKeys) {
      if (key == session.key) {
        continue;
      }
      final rect = session.port.rectOfItem(key);
      if (rect == null) {
        continue;
      }
      painted[key] =
          rect.topLeft +
          boardController.anim.offsetOfItem(boardController.idOfKey(key));
    }
    return painted;
  }

  /// The hand-off's continuation, AFTER the report's mutation: every
  /// captured item that still exists gets a slide from where it painted
  /// to where it now rests, on the clock the snap published, whatever
  /// the app's mutation did (a declined report re-lands them where they
  /// came from, on the same clock). Nothing is installed when the snap
  /// discarded no motion, which is a settled gap or a zero family's
  /// instant one: the structure the report produced is then already
  /// where everything paints. The render's track-sizing hand-off arm
  /// continues each track's residue on this same published clock, so
  /// the row edge and the content inside it arrive together. Reads the
  /// port after teardown through the session's own reference.
  void _installMakeRoomHandOff(
    _DragSession<TKey> session,
    Map<TKey, Offset> paintedByKey,
  ) {
    final handOff = boardController.anim.makeRoomHandOff;
    if (handOff == null) {
      return;
    }
    paintedByKey.forEach((key, painted) {
      if (!boardController.contains(key)) {
        return;
      }
      final rect = session.port.rectOfItem(key);
      if (rect == null) {
        return;
      }
      final id = boardController.idOfKey(key);
      final delta =
          painted - (rect.topLeft + boardController.anim.offsetOfItem(id));
      if (delta == Offset.zero) {
        return;
      }
      boardController.animateMakeRoomHandOff(
        key,
        delta,
        duration: handOff.remaining,
        curve: handOff.curve,
      );
    });
  }

  /// The drop-settle glide, installed LAST so it overrides whatever
  /// slide the report's own mutator installed. A MOVE's content was at
  /// the PROXY, so its glide runs from the proxy's release position to
  /// wherever the item now rests, commit and cancel alike. A committed
  /// RESIZE has no proxy; its glide runs from the painted corner the
  /// de-lane hold had it at, so the item never leaves the position the
  /// preview showed. The mutation-cancel path installs nothing: there
  /// the mutation's own animation is the feedback.
  void _installDropSettle(
    _DragSession<TKey> session,
    Offset? release,
    Offset? paintedBefore, [
    Offset? paintedExtentBefore,
  ]) {
    final key = session.key;
    if (!boardController.contains(key)) {
      return;
    }
    final rect = session.port.rectOfItem(key);
    if (rect == null) {
      return;
    }
    final Offset desired;
    if (session.kind == BoardDragKind.move) {
      if (release == null) {
        return;
      }
      desired = (release - session.grabOffset) - rect.topLeft;
    } else {
      if (paintedBefore == null) {
        return;
      }
      desired = paintedBefore - rect.topLeft;
    }
    final id = boardController.idOfKey(key);
    final current = boardController.anim.offsetOfItem(id);
    final delta = desired - current;
    // The extent continuation: from the painted extent the preview held
    // to the one the report's mutation produced, zero when the app
    // committed exactly what was previewed and the preview had settled,
    // which is the quiet half of a continuous commit.
    final extentDelta = paintedExtentBefore == null
        ? Offset.zero
        : Offset(
            paintedExtentBefore.dx - rect.width,
            paintedExtentBefore.dy - rect.height,
          );
    // A ZERO correction still composes when the item holds an extent
    // record: the compose is what carries that extent onto the
    // drop-settle clock, and a committed resize of an UNLANED item has a
    // zero correction by construction, there having been no de-lane hold
    // to correct off.
    if (delta == Offset.zero &&
        extentDelta == Offset.zero &&
        boardController.anim.extentDeltaOf(id) == Offset.zero) {
      return;
    }
    boardController.animateDropSettle(
      key,
      delta,
      extentDelta: extentDelta,
      duration: session.dropSettleDuration,
      curve: session.dropSettleCurve,
      // A RESIZE's correction is the de-lane hold's intra-track lead, so
      // the item stays a term of its own track; a MOVE's runs from the
      // proxy and is cross-track.
      relane: session.kind != BoardDragKind.move,
    );
  }

  /// The mutation-cancel hook: a span mutator touching the dragged key
  /// runs the ordinary cancel path BEFORE the mutation proceeds. No
  /// report.
  void _handleMutationCancel() {
    final session = _session;
    if (session == null) {
      return;
    }
    _teardown(session);
  }

  /// The single teardown site: every exit runs these same statements.
  void _teardown(_DragSession<TKey> session) {
    _session = null;
    boardController.releaseMakeRoomPreview();
    session.port.unpinItem(session.key);
    if (boardController.contains(session.key)) {
      // Drops the bit AND the mutation-cancel hook in one call.
      boardController.markDragging(session.key, dragging: false);
    }
    session.autoScroller.dispose();
    _unbindScrollSubscriptions(session);
    boardController.removeAnimationListener(_handleAnimationTick);
    _currentTarget = null;
    _lastResolvedSpan = null;
    _pointerPosition.value = null;
    notifyListeners();
  }

  /// The resolution core, run once per pointer event and once per scroll
  /// notification. Re-points the scroll subscriptions when either
  /// position was swapped under the session.
  void _resolve(_DragSession<TKey> session, Offset local) {
    _repointScrollSubscriptions(session);
    final anchor = session.kind == BoardDragKind.move
        ? local - session.grabOffset
        : local;
    final resolved = BoardDropResolver.resolve(
      port: session.port,
      anchorLocal: anchor,
      pointerLocal: local,
      grabCellRow: session.grabCellRow,
      grabCellCol: session.grabCellCol,
      draggedSpan: boardController.spanOf(session.key)!,
      kind: session.kind,
      snap: config.snap,
      rowCount: boardController.rows.axis.trackCount,
      colCount: boardController.columns.axis.trackCount,
      pointerAnchoredAxis: _pointerAnchoredAxis(session),
    );
    if (resolved == null || resolved.span == _lastResolvedSpan) {
      return;
    }
    // Recorded for every NON-NULL resolver answer, before the refusal
    // branch and whatever that branch decides: a pointer parked over a
    // refused placement resolves the same span on every move, and a
    // field written only on the accepted path would re-run the gate and
    // the scan for each of them.
    _lastResolvedSpan = resolved.span;
    var target = resolved;
    // A canDropAt refusal at RESOLUTION, not just at commit: a refused
    // target leaves currentTarget null and releases the gap, so nothing
    // previews a drop endDrag would refuse. The commit-side check stays
    // as re-validation against a predicate that changed its answer.
    //
    // A refusal is also where the NUDGE gets its one chance; a null
    // answer from it leaves the arm exactly as it was.
    final canDropAt = config.canDropAt;
    if (canDropAt != null && !canDropAt(session.key, target.span)) {
      final fitted = _fitRefusal(session, target);
      if (fitted == null) {
        if (_currentTarget != null) {
          _currentTarget = null;
          boardController.releaseMakeRoomPreview();
          notifyListeners();
        }
        return;
      }
      target = fitted;
    }
    _currentTarget = target;
    boardController.previewMakeRoomGap(
      draggedKey: session.key,
      prospective: target.span,
      lifted: session.kind == BoardDragKind.move,
      duration: session.makeRoomDuration,
      curve: session.makeRoomCurve,
    );
    notifyListeners();
  }

  /// The axis a whole-track move takes from the POINTER rather than
  /// from the item's painted corner: the LANE axis, and only while the
  /// dragged item is laned on it, whose painted lead is a lane origin
  /// inside one track rather than its span. Null everywhere else, which
  /// is every board with no lane axis and every unlaned item on one.
  /// The rule this feeds lives at `BoardDropResolver.resolve`.
  Axis? _pointerAnchoredAxis(_DragSession<TKey> session) {
    final laneAxis = boardController.laneAxis;
    if (laneAxis == null) {
      return null;
    }
    final id = boardController.idOfKey(session.key);
    if (id < 0 || !boardController.isLanedId(id)) {
      return null;
    }
    return laneAxis;
  }

  /// The NUDGE: a refused MOVE whose box mostly misses the occupants it
  /// meets slides onto the nearest nearby placement that holds the whole
  /// box and that the app admits. Null leaves the refusal exactly as it
  /// was, which is what the policy's absence, a resize, a policy with no
  /// step, a closed gate and an empty search all produce.
  BoardDropTarget? _fitRefusal(
    _DragSession<TKey> session,
    BoardDropTarget refused,
  ) {
    final policy = config.dropFit;
    final canDropAt = config.canDropAt;
    if (policy == null ||
        canDropAt == null ||
        session.kind != BoardDragKind.move) {
      return null;
    }
    // THE STEP COUNTS COME FIRST. A policy that admits no step can
    // produce no candidate, so it must not pay a span-index query or the
    // gate to discover that.
    final steps = BoardDropFitter.stepsOf(policy: policy, snap: config.snap);
    if (steps.rows == 0 && steps.cols == 0) {
      return null;
    }
    final rowAxis = boardController.rows.axis;
    final colAxis = boardController.columns.axis;
    final obstacles = _obstaclesAround(session, refused.span, policy);
    final free = BoardDropFitter.freeFractionOf(
      box: refused.span,
      obstacles: obstacles,
      rowAxis: rowAxis,
      colAxis: colAxis,
    );
    // BOTH gate terms, and the first is the one that keeps this feature
    // to overlaps: exactly 1.0 means the box meets no occupant at all,
    // so the refusal came from a rule of the app's own that the board
    // cannot read, and sliding the item would move it for a reason
    // nothing here understands.
    if (free >= 1.0 || free < policy.minFreeFraction) {
      return null;
    }
    final fitted = BoardDropFitter.nearestFit(
      box: refused.span,
      policy: policy,
      snap: config.snap,
      rowAxis: rowAxis,
      colAxis: colAxis,
      obstacles: obstacles,
      accepts: (candidate) {
        return canDropAt(session.key, candidate);
      },
    );
    if (fitted == null) {
      return null;
    }
    return BoardDropTarget(span: fitted, kind: refused.kind);
  }

  /// Every live item meeting the search region, MINUS the dragged one.
  ///
  /// ONE query, serving both the gate and the scan, over the box widened
  /// by the policy's radius on BOTH sides of each axis. Widening one side
  /// only would leave a candidate displaced toward the other tested
  /// against an incomplete set, and it could then be declared free while
  /// overlapping an item nobody fetched. The read excludes exiting items
  /// already; the dragged item it deliberately does not, so that
  /// exclusion is here.
  List<BoardSpan> _obstaclesAround(
    _DragSession<TKey> session,
    BoardSpan box,
    BoardDropFit policy,
  ) {
    final rowCount = boardController.rows.axis.trackCount;
    final colCount = boardController.columns.axis.trackCount;
    final rowStart = (box.startTrackOn(Axis.vertical) - policy.rowRadius)
        .floor()
        .clamp(0, rowCount);
    final rowEnd = (box.endTrackOn(Axis.vertical) + policy.rowRadius)
        .ceil()
        .clamp(0, rowCount);
    final colStart = (box.startTrackOn(Axis.horizontal) - policy.colRadius)
        .floor()
        .clamp(0, colCount);
    final colEnd = (box.endTrackOn(Axis.horizontal) + policy.colRadius)
        .ceil()
        .clamp(0, colCount);
    final spans = <BoardSpan>[];
    for (final key in boardController.itemsIn(
      rowStart,
      rowEnd,
      colStart,
      colEnd,
    )) {
      if (key == session.key) {
        continue;
      }
      final span = boardController.spanOf(key);
      if (span != null) {
        spans.add(span);
      }
    }
    return spans;
  }

  // The scroll-subscription triple: BIND at startDrag, RE-POINT on every
  // resolve, UNBIND in the single teardown. It is what makes an
  // autoscroll tick's jumpTo reach a reader: content moving under a
  // stationary finger re-resolves the target.
  void _bindScrollSubscriptions(_DragSession<TKey> session) {
    session.verticalSubscription = session.port.verticalPosition
      ?..addListener(_handleScroll);
    session.horizontalSubscription = session.port.horizontalPosition
      ?..addListener(_handleScroll);
  }

  void _repointScrollSubscriptions(_DragSession<TKey> session) {
    final vertical = session.port.verticalPosition;
    if (!identical(vertical, session.verticalSubscription)) {
      session.verticalSubscription?.removeListener(_handleScroll);
      session.verticalSubscription = vertical?..addListener(_handleScroll);
    }
    final horizontal = session.port.horizontalPosition;
    if (!identical(horizontal, session.horizontalSubscription)) {
      session.horizontalSubscription?.removeListener(_handleScroll);
      session.horizontalSubscription = horizontal
        ?..addListener(_handleScroll);
    }
  }

  void _unbindScrollSubscriptions(_DragSession<TKey> session) {
    session.verticalSubscription?.removeListener(_handleScroll);
    session.horizontalSubscription?.removeListener(_handleScroll);
    session.verticalSubscription = null;
    session.horizontalSubscription = null;
  }

  void _repointForSession() {
    final session = _session;
    if (session != null) {
      _repointScrollSubscriptions(session);
    }
  }

  void _handleScroll() {
    _resolveFromLastPointer();
  }

  /// An animation dispatch: schedule ONE post-frame re-resolve. Post-frame
  /// and not in the tick, because a ticker's callback runs before this
  /// frame's layout re-records the axis a resize moved, so only a
  /// post-frame resolve reads the geometry that painted. Scheduling it
  /// also keeps `previewMakeRoomGap` out of the make-room engine's own
  /// tick dispatch.
  void _handleAnimationTick() {
    if (_resolvePending) {
      return;
    }
    _resolvePending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _resolvePending = false;
      _resolveFromLastPointer();
    }, debugLabel: "BoardDragController.resolve");
  }

  /// The shared body of the scroll and animation routes. `_session` is
  /// read FIRST and in the callback's own body, never captured: a
  /// post-frame resolve pending across `dispose` finds the session null
  /// and touches neither the disposed pointer notifier nor the port.
  void _resolveFromLastPointer() {
    final session = _session;
    if (session == null) {
      return;
    }
    final local = _pointerPosition.value;
    if (local == null) {
      return;
    }
    _resolve(session, local);
  }

  /// Tears the session down with no commit, then the notifier.
  @override
  void dispose() {
    final session = _session;
    if (session != null) {
      _teardown(session);
    }
    _pointerPosition.dispose();
    super.dispose();
  }
}

/// Two-axis edge autoscroll: one per-session ticker integrating a
/// velocity ramp into both positions.
class BoardAutoScroller {
  BoardAutoScroller({
    required TickerProvider vsync,
    required BoardRenderPort<Object?> port,
    required this.edgeZone,
    required this.maxVelocity,
    this.onTick,
  }) : _port = port {
    _ticker = vsync.createTicker(_tick);
  }

  /// Runs at the head of every tick, before the positions are driven.
  final VoidCallback? onTick;

  final BoardRenderPort<Object?> _port;
  final double edgeZone;
  final double maxVelocity;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  double _verticalVelocity = 0.0;
  double _horizontalVelocity = 0.0;

  /// The velocity for a finger [distanceIntoZone] pixels into an edge
  /// zone of [zone], ramping linearly to [max] at the edge itself.
  /// Static and side-effect-free so it is testable with no session.
  static double velocityAt(double distanceIntoZone, double zone, double max) {
    if (zone <= 0.0) {
      return 0.0;
    }
    final t = (distanceIntoZone / zone).clamp(0.0, 1.0);
    return max * t;
  }

  /// Starts or stops the ticker from the FINGER's viewport position:
  /// inside either axis's edge zone drives that axis toward the edge.
  void evaluate(Offset local) {
    final vertical = _port.verticalPosition;
    final horizontal = _port.horizontalPosition;
    _verticalVelocity = vertical == null
        ? 0.0
        : _axisVelocity(local.dy, vertical.viewportDimension);
    _horizontalVelocity = horizontal == null
        ? 0.0
        : _axisVelocity(local.dx, horizontal.viewportDimension);
    final active = _verticalVelocity != 0.0 || _horizontalVelocity != 0.0;
    if (active && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      // Reset the time base on every stop, so a later start does not
      // integrate the gap.
      _ticker.stop();
    }
  }

  double _axisVelocity(double position, double viewport) {
    if (position < edgeZone) {
      return -velocityAt(edgeZone - position, edgeZone, maxVelocity);
    }
    if (position > viewport - edgeZone) {
      return velocityAt(
        position - (viewport - edgeZone),
        edgeZone,
        maxVelocity,
      );
    }
    return 0.0;
  }

  void _tick(Duration elapsed) {
    onTick?.call();
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // A null position mid-drag is a defunct scrollable: stop that axis
    // and keep the session; cancellation is the backstop's job.
    final vertical = _port.verticalPosition;
    if (_verticalVelocity != 0.0) {
      if (vertical == null) {
        _verticalVelocity = 0.0;
      } else {
        vertical.jumpTo(
          (vertical.pixels + _verticalVelocity * dt).clamp(
            vertical.minScrollExtent,
            vertical.maxScrollExtent,
          ),
        );
      }
    }
    final horizontal = _port.horizontalPosition;
    if (_horizontalVelocity != 0.0) {
      if (horizontal == null) {
        _horizontalVelocity = 0.0;
      } else {
        horizontal.jumpTo(
          (horizontal.pixels + _horizontalVelocity * dt).clamp(
            horizontal.minScrollExtent,
            horizontal.maxScrollExtent,
          ),
        );
      }
    }
    if (_verticalVelocity == 0.0 && _horizontalVelocity == 0.0) {
      _ticker.stop();
    }
  }

  void dispose() {
    _ticker.dispose();
  }
}
