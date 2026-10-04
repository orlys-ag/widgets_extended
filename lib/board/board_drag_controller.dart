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

import 'dart:async';
import 'dart:collection';

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
    required this.liftPointer,
    required this.liftCorner,
    required this.liftPointerLocal,
    required this.liftCornerLocal,
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
  /// PROXY, whose content-LEADING corner (`BoardRenderPort.leadingCornerOf`)
  /// is a move's resolved anchor, so a move resolves from where the item
  /// would start rather than from the finger. Paint space, and a top-left
  /// because that is what positions a widget; the anchor converts.
  final Offset grabOffset;

  /// The lift pointer's cell minus the item's start cell, per axis, both
  /// read in the lattice the item paints in: the whole-cell grab offset
  /// of the lane axis, so the grabbed cell stays under the pointer while
  /// within-cell grab detail is discarded.
  final int grabCellRow;
  final int grabCellCol;

  /// The pointer's sample at the lift, which a resize's displacement and
  /// a pointer-anchored axis's cell are measured from; `startDrag`
  /// refuses a resize without one. Rewritten only by the re-derive in
  /// `_resolve`, after an axis-config change.
  BoardLiftSamples? liftPointer;

  /// The proxy's content-leading corner's sample at the lift, which a
  /// move's displacement is measured from, computed by `_moveAnchorOf` as
  /// every later corner is; null for a resize. Rewritten only by the
  /// re-derive in `_resolve`, after an axis-config change.
  BoardLiftSamples? liftCorner;

  /// The paint-space points [liftPointer] and [liftCorner] were sampled
  /// at, which the re-derive samples again under new axis configs.
  final Offset liftPointerLocal;
  final Offset? liftCornerLocal;

  /// The session's captured values; the kill switch re-reads the live
  /// style at every install and dominates them.
  final Duration makeRoomDuration;
  final Curve makeRoomCurve;
  final Duration dropSettleDuration;
  final Curve dropSettleCurve;

  final BoardAutoScroller autoScroller;

  /// The target last queued for `onDragTargetChanged`.
  BoardDropTarget? reportedTarget;

  ScrollPosition? verticalSubscription;
  ScrollPosition? horizontalSubscription;
}

/// Whether [config] lets [key] start a drag: true with no predicate,
/// false for a refusal or a throw, which is reported through
/// [FlutterError.reportError]. A question that fails has a safe answer,
/// and a session in flight must never see an exception from one.
///
/// Every `canDrag` question the board asks goes through here. Not shown
/// by the module barrel.
@pragma("vm:notify-debugger-on-exception")
bool askCanDrag<TKey>(BoardDragConfig<TKey> config, TKey key) {
  final canDrag = config.canDrag;
  if (canDrag == null) {
    return true;
  }
  try {
    return canDrag(key);
  } catch (exception, stack) {
    _reportPolicyThrow("canDrag", exception, stack);
    return false;
  }
}

/// Whether [config] lets [key] land on [span]: true with no predicate,
/// false for a refusal, and null for a throw, which is reported through
/// [FlutterError.reportError]. Every caller treats null as a refusal;
/// the drag's resolution also skips the nudge for it.
///
/// Every `canDropAt` question the board asks goes through here. Not shown
/// by the module barrel.
@pragma("vm:notify-debugger-on-exception")
bool? askCanDropAt<TKey>(
  BoardDragConfig<TKey> config,
  TKey key,
  BoardSpan span,
) {
  final canDropAt = config.canDropAt;
  if (canDropAt == null) {
    return true;
  }
  try {
    return canDropAt(key, span);
  } catch (exception, stack) {
    _reportPolicyThrow("canDropAt", exception, stack);
    return null;
  }
}

void _reportPolicyThrow(String predicate, Object exception, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: exception,
      stack: stack,
      library: "widgets_extended board",
      context: ErrorDescription("while asking $predicate"),
    ),
  );
}

/// Drag-and-drop and drag-resize over a board.
///
/// Not exported from the module barrel: `Board` builds its own from
/// `Board.drag` and hands it to nothing an app holds. An app reaches a
/// session through `BoardDragConfig`'s `onDragStart`,
/// `onDragTargetChanged` and `onDragEnd`.
class BoardDragController<TKey> extends ChangeNotifier {
  BoardDragController({
    required this.boardController,
    required TickerProvider vsync,
    required BoardDragConfig<TKey> config,
  }) : _vsync = vsync,
       _config = config;

  /// Key-only: the drag layer never reads a payload.
  final BoardController<TKey, Object?> boardController;

  /// The policy every session is gated and resolved by.
  ///
  /// ASSIGNED IN PLACE: `Board` hands each new config instance to the
  /// controller it already has, so a config built inline in a parent's
  /// build costs no session and no rebuilt lattice. Assigning the
  /// identical instance does nothing. A different one takes effect at
  /// once for every later read, and a LIVE session is re-validated
  /// against it by the part of [startDrag]'s gate that describes a
  /// session rather than a lift: [BoardDragConfig.enabled], and for a
  /// resize a non-null [BoardDragConfig.onItemResized] and an axis policy
  /// that still admits the session's edge. A session that fails is
  /// cancelled exactly as `endDrag(cancel: true)` cancels one.
  /// [BoardDragConfig.canDrag] is not asked again: it decides whether a
  /// drag may START. A session that passes adopts the new autoscroll
  /// zone and velocity at once and re-resolves its target after the
  /// frame, so a new snap or `canDropAt` answers for the pointer where
  /// it already is.
  BoardDragConfig<TKey> get config {
    return _config;
  }

  set config(BoardDragConfig<TKey> value) {
    if (identical(value, _config)) {
      return;
    }
    _config = value;
    final session = _session;
    if (session == null) {
      return;
    }
    if (!_sessionAdmitted(session.kind)) {
      endDrag(cancel: true);
      return;
    }
    session.autoScroller
      ..edgeZone = value.autoScrollEdgeZone
      ..maxVelocity = value.autoScrollMaxVelocity;
    final pointer = _pointerPosition.value;
    if (pointer != null) {
      session.autoScroller.evaluate(pointer);
    }
    // The resolver's early-out compares against the last span it
    // returned; cleared, the post-frame resolve re-runs the gate and the
    // scan even when the pointer's placement has not moved.
    _lastResolvedSpan = null;
    _lastResolvedWindows = null;
    _scheduleResolve();
  }

  BoardDragConfig<TKey> _config;

  final TickerProvider _vsync;

  final ValueNotifier<Offset?> _pointerPosition = ValueNotifier<Offset?>(
    null,
  );

  /// Written at the two session EDGES only; see [movedItem].
  final ValueNotifier<TKey?> _movedItem = ValueNotifier<TKey?>(null);

  _DragSession<TKey>? _session;
  BoardDropTarget? _currentTarget;

  /// The span the RESOLVER last returned, which is not always what
  /// [_currentTarget] holds: a nudged target is a different span by
  /// construction. The early-out in [_resolve] compares against this so
  /// it compares like with like, and a pointer that has not left its
  /// resolved placement, under unchanged [_lastResolvedWindows], re-runs
  /// neither the gate nor the scan.
  BoardSpan? _lastResolvedSpan;

  /// The windows the resolver returned beside [_lastResolvedSpan], null
  /// for a resize. The early-out compares them too: a scroll can move a
  /// window by a grid step while the span stays the same, and a nudge
  /// chosen from the old window would otherwise stand.
  ({BoardStartWindow rows, BoardStartWindow cols})? _lastResolvedWindows;

  /// Whether a post-frame re-resolve is already scheduled for this
  /// frame, so a frame with several animation dispatches resolves once.
  bool _resolvePending = false;

  /// The lifecycle notifications not yet delivered, oldest first.
  final ListQueue<VoidCallback> _pendingNotifications =
      ListQueue<VoidCallback>();

  /// Whether a microtask that drains [_pendingNotifications] is pending.
  bool _drainScheduled = false;

  /// The pointer's viewport-paint position while a session is live, one
  /// write per move event; null between sessions.
  ValueListenable<Offset?> get pointerPosition {
    return _pointerPosition;
  }

  /// The key a live MOVE session holds; null between sessions, and null
  /// for a resize, which paints no proxy.
  ///
  /// Narrow on purpose, and the reason it exists beside this class's own
  /// `ChangeNotifier`: that one fires per pointer move, so an item-level
  /// listener on it would rebuild every mounted item every frame of a
  /// drag, while this one is written twice per session. It is what the
  /// item host watches for the left-behind dim, and what an app watches
  /// to give that item a treatment of its own. `BoardItemView.isDragging`
  /// cannot serve either: the lattice item is built by the viewport's
  /// delegate, and a session edge fires no structural notification, so
  /// nothing rebuilds it between the lift and the commit.
  ValueListenable<TKey?> get movedItem {
    return _movedItem;
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

  /// Whether the current config admits a session of [kind]: the part of
  /// [startDrag]'s gate that describes the SESSION rather than the lift,
  /// and the one test [config]'s setter re-runs on a live session. A move
  /// needs only [BoardDragConfig.enabled]; a resize also needs a report
  /// and an axis policy admitting its edge.
  bool _sessionAdmitted(BoardDragKind kind) {
    if (!config.enabled) {
      return false;
    }
    final Axis axis;
    final BoardResizeEdges edge;
    switch (kind) {
      case BoardDragKind.move:
        return true;
      case BoardDragKind.resizeRowStart:
        axis = Axis.vertical;
        edge = BoardResizeEdges.leading;
      case BoardDragKind.resizeRowEnd:
        axis = Axis.vertical;
        edge = BoardResizeEdges.trailing;
      case BoardDragKind.resizeColStart:
        axis = Axis.horizontal;
        edge = BoardResizeEdges.leading;
      case BoardDragKind.resizeColEnd:
        axis = Axis.horizontal;
        edge = BoardResizeEdges.trailing;
    }
    if (config.onItemResized == null) {
      return false;
    }
    final policy = axis == _spanAxis
        ? config.resizeEdges
        : config.primaryResizeEdges;
    return _edgeAccepted(policy, edge);
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
  /// move pixels and then vanish), a resize edge its axis's policy
  /// does not accept: `resizeEdges` on the span axis, which a null
  /// [axis] names, and `primaryResizeEdges` on the primary axis, or a
  /// resize on a lattice with no tracks, which gives it no lift sample to
  /// measure its displacement from. Throws
  /// [ArgumentError] only for cross-controller misuse: a [renderPort]
  /// not driven by [boardController].
  ///
  /// Returns true for a session that app code ended inside this call,
  /// through a predicate or an animation listener: its start and its end
  /// are both queued, in that order.
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
    if (_session != null || !renderPort.isLaidOut) {
      return false;
    }
    if (!boardController.contains(key)) {
      return false;
    }
    final kind = _kindFor(edge, axis);
    if (kind == null) {
      return false;
    }
    // The session half of the gate, shared with the config setter's
    // re-validation: `enabled`, and for a resize a report plus an axis
    // policy admitting the edge (each axis carries its own, so a config
    // that opens the span axis leaves the primary one closed).
    if (!_sessionAdmitted(kind)) {
      return false;
    }
    if (!askCanDrag(config, key)) {
      return false;
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
    final span = boardController.spanOf(key)!;
    // The lift pointer's sample, taken once and re-derived only after an
    // axis-config change: the lane axis's grab offset is in WHOLE cells,
    // and a resize's displacement is measured from it. Null only for a
    // lattice with no tracks, where a resize has nothing to measure
    // against and is refused.
    final liftCell = renderPort.trackSampleAt(local);
    if (liftCell == null && kind != BoardDragKind.move) {
      return false;
    }
    final grabOffset = kind == BoardDragKind.move
        ? local - rect.topLeft
        : Offset.zero;
    // The corner through the one expression [_resolve] reads every later
    // corner by, so the first resolve maps the bit-identical point and a
    // lift that does not move reads a displacement of exactly zero.
    final liftCornerLocal = kind == BoardDragKind.move
        ? _moveAnchorOf(renderPort, local, grabOffset, rect.size)
        : null;
    final liftCorner = liftCornerLocal == null
        ? null
        : renderPort.trackSampleAt(liftCornerLocal);
    // The grab cell is read in the lattice the item paints in at the
    // lift, so it counts the tracks the item's own lattice puts between
    // its start and the finger.
    final liftPins = liftCell == null ? null : _pinsAt(key, liftCell);
    int grabCellOn(Axis axis) {
      if (liftCell == null || liftPins == null) {
        return 0;
      }
      final vertical = axis == Axis.vertical;
      final coordinate = itemCoordinateOf(
        vertical ? liftPins.row : liftPins.col,
        vertical ? liftCell.row : liftCell.col,
      );
      return coordinate.floor() - trackIndexOf(span.startTrackOn(axis));
    }

    // The last policy check has passed: take the pin and the bit.
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
      grabOffset: grabOffset,
      grabCellRow: grabCellOn(Axis.vertical),
      grabCellCol: grabCellOn(Axis.horizontal),
      liftPointer: liftCell == null
          ? null
          : (row: liftCell.row, col: liftCell.col),
      liftCorner: liftCorner == null
          ? null
          : (row: liftCorner.row, col: liftCorner.col),
      liftPointerLocal: local,
      liftCornerLocal: liftCornerLocal,
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
    // One of this session's two writes to the narrow channel; the
    // teardown's null is the other. A resize writes the null it already
    // holds, which notifies nobody.
    _movedItem.value = kind == BoardDragKind.move ? key : null;
    _bindScrollSubscriptions(session);
    // The animation channel is the third route into the resolution core,
    // beside pointer events and scroll notifications: a track resizing
    // above a stationary pointer moves the cell under it, and nothing
    // else re-resolves for that. The structural channel is the fourth: a
    // board change under a parked pointer changes what the drop gate
    // answers for the same placement.
    boardController.addAnimationListener(_handleAnimationTick);
    boardController.addStructuralListener(_handleStructuralChange);
    if (config.hapticsOnDrag) {
      HapticFeedback.mediumImpact();
    }
    _pointerPosition.value = local;
    // Queued BEFORE the first resolve, so an end that the resolve's
    // synchronous work causes is queued after it, and the resolve queues
    // the first target after it too.
    _notifyStart(key, kind);
    _resolve(session, local);
    // App code the resolve reached synchronously, a predicate or an
    // animation listener, may have ended the session through the
    // mutation-cancel hook; its autoscroller is then disposed, and its
    // end is already queued.
    if (!identical(_session, session)) {
      return true;
    }
    // Evaluated at start too, not only per move: a finger that lifts an
    // item already inside an edge zone autoscrolls with no move event
    // ever arriving.
    session.autoScroller.evaluate(local);
    notifyListeners();
    return true;
  }

  /// Queues [_currentTarget] for `onDragTargetChanged` when it differs
  /// from the last one queued, and only for the live session.
  void _reportTarget(_DragSession<TKey> session) {
    if (!identical(_session, session)) {
      return;
    }
    final target = _currentTarget;
    if (target == session.reportedTarget) {
      return;
    }
    session.reportedTarget = target;
    final onDragTargetChanged = config.onDragTargetChanged;
    if (onDragTargetChanged != null) {
      final key = session.key;
      _notifyApp(() {
        onDragTargetChanged(key, target);
      });
    }
  }

  void _notifyStart(TKey key, BoardDragKind kind) {
    final onDragStart = config.onDragStart;
    if (onDragStart == null) {
      return;
    }
    _notifyApp(() {
      onDragStart(key, kind);
    });
  }

  void _notifyEnd(TKey key, {required bool committed}) {
    final onDragEnd = config.onDragEnd;
    if (onDragEnd == null) {
      return;
    }
    _notifyApp(() {
      onDragEnd(key, committed);
    });
  }

  /// Queues a lifecycle notification. Each caller captures its callback
  /// and arguments here, never at delivery, so a notification reports
  /// through the config current when it was queued, and a delivery after
  /// [dispose] reads nothing this controller disposed.
  ///
  /// Delivered in a microtask, which runs after the board call that
  /// queued it has returned and never inside a mutation, a build, a
  /// layout or the frame's finalize; or earlier, by the drain at the top
  /// of a pointer release in [endDrag].
  void _notifyApp(VoidCallback notification) {
    _pendingNotifications.add(notification);
    if (_drainScheduled) {
      return;
    }
    _drainScheduled = true;
    scheduleMicrotask(() {
      // Cleared AFTER the loop: an entry queued while it runs is delivered
      // by it, so it schedules no second microtask. In a `finally`, so a
      // throw that escapes the loop, which only `FlutterError.onError`
      // itself could raise, cannot leave the flag set and the queue stuck.
      try {
        _drainNotifications();
      } finally {
        _drainScheduled = false;
      }
    });
  }

  /// Delivers every queued notification, oldest first, including one a
  /// delivery queues. A throw is reported and the drain goes on, so one
  /// failing callback cannot strand the ones behind it.
  @pragma("vm:notify-debugger-on-exception")
  void _drainNotifications() {
    while (_pendingNotifications.isNotEmpty) {
      final notification = _pendingNotifications.removeFirst();
      try {
        notification();
      } catch (exception, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: "widgets_extended board",
            context: ErrorDescription("while delivering a drag notification"),
          ),
        );
      }
    }
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
    // As in [startDrag]: a session the resolve's app code ended has a
    // disposed autoscroller.
    if (!identical(_session, session)) {
      return;
    }
    session.autoScroller.evaluate(local);
  }

  /// Ends the session, in the order the mutation-cancel rule forces:
  /// resolve and validate FIRST (nothing reported), TEAR DOWN second
  /// (the same statements every other exit runs), REPORT third, so the
  /// dragging bit is already clear when an `onItemMoved` handler
  /// mutates the dragged key, and queue `onDragEnd` last, in a `finally`,
  /// so a report that throws still ends the drag for the app.
  ///
  /// A release ([cancel] false) first delivers every lifecycle
  /// notification still queued, so the app hears a target change that
  /// shared the release's task before the drop it precedes. A handler
  /// delivered there that ends the session leaves nothing to release.
  void endDrag({required bool cancel}) {
    if (!cancel) {
      _drainNotifications();
    }
    final session = _session;
    if (session == null) {
      return;
    }
    final target = _currentTarget;
    var report = !cancel && target != null;
    if (report && askCanDropAt(config, session.key, target.span) != true) {
      report = false;
    }
    // The drop-settle glide's FROM rect, captured before the snap and the
    // teardown, in PAINT space. A MOVE's content was at the PROXY, so it
    // is the proxy's rect at release, commit and cancel alike. A
    // committed RESIZE has no proxy: it is the item's painted rect, which
    // the port composes from the animation offset and the extent the
    // resize preview holds, so the glide starts where the preview left
    // it; the report's own FLIP starts from the old lane origin and the
    // glide corrects onto this. A cancelled resize glides from nothing:
    // teardown's animated release closes its preview.
    Rect? glideFrom;
    if (session.kind == BoardDragKind.move) {
      final pointer = _pointerPosition.value;
      final size = proxySize;
      if (pointer != null && size != null) {
        glideFrom = (pointer - session.grabOffset) & size;
      }
    } else if (report) {
      glideFrom = session.port.paintedRectOfItem(session.key);
    }
    Map<TKey, Rect>? paintedByKey;
    if (report) {
      // The COMMIT HAND-OFF's painted truth, captured BEFORE the snap:
      // where, and how large, every item the preview holds paints this
      // instant. The session's own key is the glide's below, not the
      // hand-off's.
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
    // The snap dispatches the animation channel synchronously, and an app
    // listener there may have ended the session through the
    // mutation-cancel hook, which tore it down and queued its uncommitted
    // end: nothing is left to tear down or report.
    if (!identical(_session, session)) {
      return;
    }
    _teardown(session);
    try {
      if (report && target != null) {
        // The report's mutation re-lanes exactly the neighbours the
        // preview displaced and re-sized, whose landing the hand-off
        // below owns, so their relane slides, LEAD and EXTENT, are
        // suppressed for its duration, in whatever door the app mutates
        // through. The widget's built-in semantics move action reports
        // outside any session and is deliberately not wrapped: nothing is
        // held there.
        boardController.withoutRelaneSlides(() {
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
      _installDropSettle(session, glideFrom);
    } finally {
      // After the report, so an app hears the drop, then the end; and
      // queued even when the report threw, which still propagates.
      // `committed` is whether the drop was reported, which a throwing
      // report was.
      _notifyEnd(session.key, committed: report && target != null);
    }
  }

  /// The hand-off's capture: the painted RECT of every item the make-room
  /// preview holds an offset or an extent for, except the session's own.
  /// Paint space, the corner composed with every animation offset and
  /// the size read through the geometry rule, which composes the held
  /// extent; that is what makes it painted truth rather than structure.
  Map<TKey, Rect> _capturePaintedByKey(_DragSession<TKey> session) {
    final painted = <TKey, Rect>{};
    for (final key in boardController.makeRoomHeldKeys) {
      if (key == session.key) {
        continue;
      }
      final rect = session.port.paintedRectOfItem(key);
      if (rect == null) {
        continue;
      }
      painted[key] = rect;
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
    Map<TKey, Rect> paintedByKey,
  ) {
    final handOff = boardController.anim.makeRoomHandOff;
    if (handOff == null) {
      return;
    }
    paintedByKey.forEach((key, painted) {
      if (!boardController.contains(key)) {
        return;
      }
      final rect = session.port.paintedRectOfItem(key);
      if (rect == null) {
        return;
      }
      // The correction from painted truth on both sides, exactly as the
      // glide's: the rect the preview held it at, minus the one it rests
      // at now. The neighbour's own relane extent was suppressed in the
      // report, so this composes onto no record and starts where the
      // preview left the item.
      final (:lead, :extent) = _correctionBetween(session.port, painted, rect);
      if (lead == Offset.zero && extent == Offset.zero) {
        return;
      }
      boardController.animateMakeRoomHandOff(
        key,
        lead,
        duration: handOff.remaining,
        curve: handOff.curve,
        extentDelta: extent,
      );
    });
  }

  /// The drop-settle glide, installed LAST so it overrides whatever
  /// slide the report's own mutator installed, from [from] to wherever
  /// the item now rests. A MOVE's [from] is the proxy's rect at release,
  /// commit and cancel alike; a committed RESIZE's is the rect the
  /// preview had it at, so the item never leaves what the preview showed.
  /// Null installs nothing, which is also the mutation-cancel path's
  /// case: there the mutation's own animation is the feedback.
  void _installDropSettle(_DragSession<TKey> session, Rect? from) {
    final key = session.key;
    if (from == null || !boardController.contains(key)) {
      return;
    }
    // Where the item paints NOW, every installed offset composed in paint
    // space.
    final rect = session.port.paintedRectOfItem(key);
    if (rect == null) {
      return;
    }
    final id = boardController.idOfKey(key);
    final (:lead, :extent) = _correctionBetween(session.port, from, rect);
    // A ZERO correction still composes when the item holds an extent
    // record: the compose is what carries that extent onto the
    // drop-settle clock, and a committed resize of an UNLANED item has a
    // zero correction by construction, there having been no de-lane hold
    // to correct off.
    if (lead == Offset.zero &&
        extent == Offset.zero &&
        boardController.anim.extentDeltaOf(id) == Offset.zero) {
      return;
    }
    boardController.animateDropSettle(
      key,
      lead,
      extentDelta: extent,
      duration: session.dropSettleDuration,
      curve: session.dropSettleCurve,
      // A RESIZE's correction is the de-lane hold's intra-track lead, so
      // the item stays a term of its own track; a MOVE's runs from the
      // proxy and is cross-track.
      relane: session.kind != BoardDragKind.move,
    );
  }

  /// The content-space correction that paints an item resting at [to]
  /// at [from] instead, both PAINT-space rects: the LEAD is the
  /// difference of their content-leading corners, converted by the one
  /// delta conversion, and the EXTENT the difference of their sizes,
  /// which is the same number in both spaces.
  ///
  /// Corners, not top-lefts: on a reversed axis a painted top-left is the
  /// content TRAILING corner, and a difference of trailing corners is the
  /// lead difference PLUS the extent difference, which the extent term
  /// then installs a second time.
  static ({Offset lead, Offset extent}) _correctionBetween(
    BoardRenderPort<Object?> port,
    Rect from,
    Rect to,
  ) {
    return (
      lead: port.contentDeltaFromPaint(
        port.leadingCornerOf(from) - port.leadingCornerOf(to),
      ),
      extent: Offset(from.width - to.width, from.height - to.height),
    );
  }

  /// The mutation-cancel hook: a span mutator touching the dragged key
  /// runs the ordinary cancel path BEFORE the mutation proceeds. No
  /// report, and no [BoardDragConfig] callback: the uncommitted end is
  /// QUEUED, so the mutator's ids stay valid across the hook and the app
  /// hears the end once the mutation has finished.
  void _handleMutationCancel() {
    final session = _session;
    if (session == null) {
      return;
    }
    _teardown(session);
    _notifyEnd(session.key, committed: false);
  }

  /// The single teardown site: every exit runs these same statements.
  void _teardown(_DragSession<TKey> session) {
    _session = null;
    // The gap closes on the clock the session opened it on: the pair
    // `startDrag` captured, which every preview passed, so a restyle
    // during the session reaches neither the gap nor its close. The live
    // family's zero still snaps it, the engine reading that itself.
    boardController.releaseMakeRoomPreview(
      duration: session.makeRoomDuration,
      curve: session.makeRoomCurve,
    );
    session.port.unpinItem(session.key);
    if (boardController.contains(session.key)) {
      // Drops the bit AND the mutation-cancel hook in one call.
      boardController.markDragging(session.key, dragging: false);
    }
    session.autoScroller.dispose();
    _unbindScrollSubscriptions(session);
    boardController.removeAnimationListener(_handleAnimationTick);
    boardController.removeStructuralListener(_handleStructuralChange);
    _currentTarget = null;
    _lastResolvedSpan = null;
    _lastResolvedWindows = null;
    _pointerPosition.value = null;
    _movedItem.value = null;
    notifyListeners();
  }

  /// The resolution core, run once per pointer event and once per scroll
  /// notification. Re-points the scroll subscriptions when either
  /// position was swapped under the session.
  ///
  /// Takes every sample the resolver reads, once per resolve: the
  /// pointer's, and for a move the proxy's content-leading corner's and
  /// its centre's. A null sample leaves the target unchanged. With the
  /// current samples in hand it RE-DERIVES a lift sample taken under
  /// other axis configs (a different track count or band bound on an
  /// axis): the sample the lift point gives at the lift's scroll offsets
  /// under the current configs, so the resolver never compares samples
  /// of two configs. The item's pin is read here on every call, through
  /// the pointer sample's band bounds.
  void _resolve(_DragSession<TKey> session, Offset local) {
    _repointScrollSubscriptions(session);
    final port = session.port;
    final pointer = port.trackSampleAt(local);
    if (pointer == null) {
      return;
    }
    final draggedSpan = boardController.spanOf(session.key)!;
    final BoardDropTarget resolved;
    ({BoardStartWindow rows, BoardStartWindow cols})? windows;
    if (session.kind == BoardDragKind.move) {
      // A move resolves from the proxy's content-LEADING corner, the
      // point its span starts at, which is the proxy's painted top-left
      // only where both axes run forward; the region under the proxy's
      // centre decides which lattice it lands in.
      final size = proxySize ?? Size.zero;
      final corner = port.trackSampleAt(
        _moveAnchorOf(port, local, session.grabOffset, size),
      );
      final centre = port.trackSampleAt(
        ((local - session.grabOffset) & size).center,
      );
      if (corner == null || centre == null) {
        return;
      }
      session.liftPointer = _rederived(
        port,
        session.liftPointer,
        session.liftPointerLocal,
        pointer,
      );
      session.liftCorner = _rederived(
        port,
        session.liftCorner,
        session.liftCornerLocal,
        corner,
      );
      final answer = BoardDropResolver.resolveMove(
        corner: corner,
        centre: centre,
        pointer: pointer,
        grabCellRow: session.grabCellRow,
        grabCellCol: session.grabCellCol,
        draggedSpan: draggedSpan,
        snap: config.snap,
        pointerAnchoredAxis: _pointerAnchoredAxis(session),
        liftCorner: session.liftCorner,
        liftPointer: session.liftPointer,
        pinned: _pinsAt(session.key, pointer),
      );
      resolved = answer.target;
      windows = (rows: answer.rows, cols: answer.cols);
    } else {
      // A resize resolves from the pointer's displacement since the
      // lift, in track space.
      session.liftPointer = _rederived(
        port,
        session.liftPointer,
        session.liftPointerLocal,
        pointer,
      );
      resolved = BoardDropResolver.resolveResize(
        pointer: pointer,
        kind: session.kind,
        draggedSpan: draggedSpan,
        snap: config.snap,
        liftPointer: session.liftPointer!,
        pinned: _pinsAt(session.key, pointer),
      );
    }
    if (resolved.span == _lastResolvedSpan &&
        windows == _lastResolvedWindows) {
      return;
    }
    // Recorded for every resolver answer, before the refusal branch and
    // whatever that branch decides: a pointer parked over a refused
    // placement resolves the same span on every move, and a field
    // written only on the accepted path would re-run the gate and the
    // scan for each of them.
    _lastResolvedSpan = resolved.span;
    _lastResolvedWindows = windows;
    var target = resolved;
    // A canDropAt refusal at RESOLUTION, not just at commit: a refused
    // target leaves currentTarget null and releases the gap, so nothing
    // previews a drop endDrag would refuse. The commit-side check stays
    // as re-validation against a predicate that changed its answer.
    //
    // A refusal is also where the NUDGE gets its one chance; a null
    // answer from it leaves the arm exactly as it was.
    final answer = askCanDropAt(config, session.key, target.span);
    if (answer != true) {
      // A throw, answered null, is a refusal with no nudge: the nudge is
      // for overlaps, and a throw says nothing about one.
      final fitted = answer == false
          ? _fitRefusal(session, target, windows)
          : null;
      if (fitted == null) {
        if (_currentTarget != null) {
          _currentTarget = null;
          boardController.releaseMakeRoomPreview(
            duration: session.makeRoomDuration,
            curve: session.makeRoomCurve,
          );
          notifyListeners();
          _reportTarget(session);
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
    _reportTarget(session);
  }

  /// The band [key] is pinned in on each axis, as [sample]'s bounds give
  /// the band `pinOfId` names, or null where it scrolls.
  BoardPins _pinsAt(TKey key, BoardPointSample sample) {
    final id = boardController.idOfKey(key);
    ({int start, int end})? pinOn(Axis axis, BoardAxisSample axisSample) {
      switch (boardController.pinOfId(id, axis)) {
        case BoardPin.leading:
          return (start: 0, end: axisSample.leadingBandEnd);
        case BoardPin.trailing:
          return (
            start: axisSample.trailingBandStart,
            end: axisSample.trackCount,
          );
        case BoardPin.none:
          return null;
      }
    }

    return (
      row: pinOn(Axis.vertical, sample.row),
      col: pinOn(Axis.horizontal, sample.col),
    );
  }

  /// [lift] with each axis whose [current] sample was taken under another
  /// track count or band bound RE-DERIVED: [liftLocal] sampled again
  /// under the current configs at the scroll offsets the lift's samples
  /// record, and that axis's component taken whole. The sample keeps
  /// those offsets, so a chain of config changes loses nothing of the
  /// lift. A null record or component stays null.
  static BoardLiftSamples? _rederived(
    BoardRenderPort<Object?> port,
    BoardLiftSamples? lift,
    Offset? liftLocal,
    BoardPointSample current,
  ) {
    if (lift == null || liftLocal == null) {
      return lift;
    }
    bool stale(BoardAxisSample? recorded, BoardAxisSample now) {
      return recorded != null &&
          (recorded.trackCount != now.trackCount ||
              recorded.leadingBandEnd != now.leadingBandEnd ||
              recorded.trailingBandStart != now.trailingBandStart);
    }

    final rowStale = stale(lift.row, current.row);
    final colStale = stale(lift.col, current.col);
    if (!rowStale && !colStale) {
      return lift;
    }
    final fresh = port.trackSampleAt(
      liftLocal,
      verticalPixels: lift.row?.scrollPixels,
      horizontalPixels: lift.col?.scrollPixels,
    );
    if (fresh == null) {
      return lift;
    }
    return (
      row: rowStale ? fresh.row : lift.row,
      col: colStale ? fresh.col : lift.col,
    );
  }

  /// A move's anchor: the content-leading corner of the proxy that the
  /// pointer at [local] places, [grabOffset] above and to the left of it
  /// with [size]. The ONE expression for it, at the lift and at every
  /// resolve, so both map the same point for the same pointer.
  static Offset _moveAnchorOf(
    BoardRenderPort<Object?> port,
    Offset local,
    Offset grabOffset,
    Size size,
  ) {
    return port.leadingCornerOf((local - grabOffset) & size);
  }

  /// The axis a whole-track move takes from the POINTER rather than
  /// from the item's painted corner: the LANE axis, and only while the
  /// dragged item is laned on it, whose painted lead is a lane origin
  /// inside one track rather than its span. Null everywhere else, which
  /// is every board with no lane axis and every unlaned item on one.
  /// The rule this feeds lives at `BoardDropResolver.resolveMove`.
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
  /// box and that the app admits; a box lying past the lattice's end is
  /// first moved onto it, into [windows], and taken there when the app
  /// admits it. Null leaves the refusal exactly as it was, which is what
  /// the policy's absence, a resize and a throw asking about the moved box
  /// produce, and, unless the moved box is admitted, a policy with no
  /// step, a closed gate and an empty search.
  ///
  /// [windows] are the windows the resolver placed each axis in, which a
  /// candidate is clamped into on an axis the scan steps, so a refused
  /// span in a band is nudged within the band and a scrolled one only to
  /// starts that show; null for a resize.
  BoardDropTarget? _fitRefusal(
    _DragSession<TKey> session,
    BoardDropTarget refused,
    ({BoardStartWindow rows, BoardStartWindow cols})? windows,
  ) {
    final policy = config.dropFit;
    final canDropAt = config.canDropAt;
    if (policy == null ||
        canDropAt == null ||
        windows == null ||
        session.kind != BoardDragKind.move) {
      return null;
    }
    final rowAxis = boardController.rows.axis;
    final colAxis = boardController.columns.axis;
    // A box lying wholly at or past the lattice's end on an axis, as a
    // kept span can once its tracks are removed, paints nowhere, and the
    // scan cannot search from it: past the end an axis gives the box's
    // start no offset to measure a candidate's distance from, and at the
    // end the region holds none of the box's tracks on an axis the search
    // does not widen. Such a box is moved first into its axis's window,
    // whose starts show beside a band where any does, so it is not pinned
    // in the band while a start shows; it is taken there when the app
    // admits it, and refused there, it is the box the nudge searches from.
    // A laned item steps by WHOLE tracks on its lane axis, the axis the
    // resolver anchors to the pointer, exactly as the resolver moves it.
    final wholeTrackAxis = _pointerAnchoredAxis(session);
    var box = refused.span;
    final onto = BoardDropFitter.ontoLattice(
      box,
      rowCount: rowAxis.trackCount,
      colCount: colAxis.trackCount,
      rowWindow: windows.rows,
      colWindow: windows.cols,
      snap: config.snap,
      wholeTrackAxis: wholeTrackAxis,
    );
    if (onto == null) {
      return null;
    }
    if (onto != box) {
      final admitted = askCanDropAt(config, session.key, onto);
      if (admitted == true) {
        return BoardDropTarget(span: onto, kind: refused.kind);
      }
      // A throw, answered null, says nothing about an overlap.
      if (admitted == null) {
        return null;
      }
      box = onto;
    }
    // THE STEP COUNTS COME FIRST. A policy that admits no step can
    // produce no candidate, so it must not pay a span-index query or the
    // gate to discover that.
    final steps = BoardDropFitter.stepsOf(
      policy: policy,
      snap: config.snap,
      wholeTrackAxis: wholeTrackAxis,
    );
    if (steps.rows == 0 && steps.cols == 0) {
      return null;
    }
    final region = _searchRegion(
      box,
      policy,
      rowWindow: windows.rows,
      colWindow: windows.cols,
      steps: steps,
    );
    final obstacles = _obstaclesIn(session, region);
    // BOTH gate terms, and they ask about DIFFERENT rectangles.
    //
    // The FIRST is about the BOX and keeps this feature to overlaps: a
    // box meeting no occupant was refused for a rule of the app's own
    // that the board cannot read, and sliding it would move the item for
    // a reason nothing here understands.
    if (!BoardDropFitter.meetsAny(box, obstacles)) {
      return null;
    }
    // The SECOND is about the REGION, and measuring it there rather than
    // on the box is what makes the threshold mean anything. A box on
    // whole tracks against occupants on whole tracks is either wholly
    // free or wholly covered, never in between, so a box-share gate is
    // unreachable for a single-cell item and the commonest board on
    // earth gets no help at all. The region asks the question the
    // feature is actually for: is the neighbourhood being dropped into
    // mostly empty.
    final free = BoardDropFitter.freeFractionOf(
      box: region,
      obstacles: obstacles,
      rowAxis: rowAxis,
      colAxis: colAxis,
    );
    if (free < policy.minFreeFraction) {
      return null;
    }
    final fitted = BoardDropFitter.nearestFit(
      box: box,
      policy: policy,
      snap: config.snap,
      rowAxis: rowAxis,
      colAxis: colAxis,
      obstacles: obstacles,
      accepts: (candidate) {
        return askCanDropAt(config, session.key, candidate) == true;
      },
      rowWindow: windows.rows,
      colWindow: windows.cols,
      wholeTrackAxis: wholeTrackAxis,
    );
    if (fitted == null) {
      return null;
    }
    return BoardDropTarget(span: fitted, kind: refused.kind);
  }

  /// The SEARCH REGION: on each axis, [BoardDropFitter.searchRangeOn] of
  /// the refused box, the policy's radius and the axis's window,
  /// [rowWindow] or [colWindow], the axis counting as stepped where
  /// [steps] gives it at least one step.
  ///
  /// One rectangle serving three purposes, which is why it is computed
  /// once and passed around: it bounds the obstacle query, it is what
  /// the gate's second term measures, and widening it on one side only
  /// would leave a candidate displaced toward the other tested against
  /// an incomplete set, free in the arithmetic while overlapping an item
  /// nobody fetched.
  BoardSpan _searchRegion(
    BoardSpan box,
    BoardDropFit policy, {
    required BoardStartWindow rowWindow,
    required BoardStartWindow colWindow,
    required ({int rows, int cols}) steps,
  }) {
    ({int start, int end}) reachOn(
      Axis axis,
      double radius,
      BoardStartWindow window,
      bool stepped,
      int count,
    ) {
      return BoardDropFitter.searchRangeOn(
        start: box.startTrackOn(axis),
        end: box.endTrackOn(axis),
        radius: radius,
        window: window,
        stepped: stepped,
        trackCount: count,
      );
    }

    final rows = reachOn(
      Axis.vertical,
      policy.rowRadius,
      rowWindow,
      steps.rows > 0,
      boardController.rows.axis.trackCount,
    );
    final cols = reachOn(
      Axis.horizontal,
      policy.colRadius,
      colWindow,
      steps.cols > 0,
      boardController.columns.axis.trackCount,
    );
    final rowStart = rows.start;
    final rowEnd = rows.end;
    final colStart = cols.start;
    final colEnd = cols.end;
    return BoardSpan(
      rowStart: rowStart,
      colStart: colStart,
      rowSpan: rowEnd - rowStart,
      colSpan: colEnd - colStart,
    );
  }

  /// Every live item meeting [region], MINUS the dragged one. ONE query,
  /// serving both the gate and the scan. The read excludes exiting items
  /// already; the dragged item it deliberately does not, so that
  /// exclusion is here.
  List<BoardSpan> _obstaclesIn(_DragSession<TKey> session, BoardSpan region) {
    final spans = <BoardSpan>[];
    for (final key in boardController.itemsIn(
      region.rowStart,
      region.rowStart + region.rowSpan,
      region.colStart,
      region.colStart + region.colSpan,
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
    _scheduleResolve();
  }

  /// A structural change: items arrived, left or moved, so the drop gate
  /// may answer differently for the placement the pointer rests on,
  /// which the early-out in [_resolve] would never put to it again.
  /// Clears that record and schedules the one post-frame resolve, the
  /// config setter's route, reading the board as the change lays it out:
  /// a freed placement is accepted and previewed, an occupied one
  /// withdrawn before the release rather than refused at it. The
  /// session's own writes notify no structural listener, so this cannot
  /// feed itself; the report runs after teardown has unbound it.
  void _handleStructuralChange(Set<TKey>? affectedKeys) {
    _lastResolvedSpan = null;
    _lastResolvedWindows = null;
    _scheduleResolve();
  }

  /// Schedules ONE post-frame re-resolve from the last pointer position,
  /// however many dispatches ask for it this frame. The animation route,
  /// the structural route and the config setter share it.
  ///
  /// A post-frame callback does not schedule a frame of its own. The
  /// animation route always calls from inside one; the setter can call
  /// from outside any, and then asks for the frame, which is the only
  /// case where a frame would not otherwise come.
  void _scheduleResolve() {
    if (_resolvePending) {
      return;
    }
    _resolvePending = true;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      _resolvePending = false;
      _resolveFromLastPointer();
    }, debugLabel: "BoardDragController.resolve");
    if (scheduler.schedulerPhase == SchedulerPhase.idle) {
      scheduler.scheduleFrame();
    }
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

  /// Tears the session down with no commit, then the notifier. Queues no
  /// lifecycle notification; one already queued is still delivered.
  @override
  void dispose() {
    final session = _session;
    if (session != null) {
      _teardown(session);
    }
    _pointerPosition.dispose();
    _movedItem.dispose();
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

  /// Mutable because the drag controller's config is: a new config
  /// updates a live session's zone and velocity in place.
  double edgeZone;
  double maxVelocity;

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
  ///
  /// The zones are measured from the SCROLLED REGION's edges, not the
  /// viewport's: a frozen band is where scrolled content disappears, so
  /// the zone sits just inside the band, and a finger over the band
  /// itself is choosing one of its frozen tracks and scrolls nothing on
  /// that axis. Past the viewport's own edge the finger drives at full
  /// speed, band or not.
  void evaluate(Offset local) {
    final vertical = _port.verticalPosition;
    final horizontal = _port.horizontalPosition;
    final region = _port.scrolledRegion;
    final size = _port.viewportDimension;
    _verticalVelocity = vertical == null
        ? 0.0
        : _axisVelocity(local.dy, region.top, region.bottom, size.height);
    _horizontalVelocity = horizontal == null
        ? 0.0
        : _axisVelocity(local.dx, region.left, region.right, size.width);
    // A zone whose scroll is already at its end in the direction it
    // drives starts nothing: the tick would clamp every step to where the
    // position is.
    final active = _canAdvance();
    if (active && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!active && _ticker.isActive) {
      // Reset the time base on every stop, so a later start does not
      // integrate the gap.
      _ticker.stop();
    }
  }

  /// The paint-space velocity for a finger at [position] on an axis
  /// whose scrolled region is `[start, end]` inside a viewport of
  /// [viewport]: negative toward the start, positive toward the end.
  double _axisVelocity(
    double position,
    double start,
    double end,
    double viewport,
  ) {
    // Over a band: choosing a frozen track, not scrolling.
    if ((position >= 0.0 && position < start) ||
        (position > end && position <= viewport)) {
      return 0.0;
    }
    if (position < start + edgeZone) {
      return -velocityAt(start + edgeZone - position, edgeZone, maxVelocity);
    }
    if (position > end - edgeZone) {
      return velocityAt(position - (end - edgeZone), edgeZone, maxVelocity);
    }
    return 0.0;
  }

  void _tick(Duration elapsed) {
    onTick?.call();
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // The velocities are PAINT-space: negative drives toward the painted
    // top or left edge. The scroll offset is content-space, so the step
    // passes through the one delta conversion, which negates it on a
    // reversed axis, where the content beyond the painted top edge lies at
    // GREATER offsets.
    final step = _port.contentDeltaFromPaint(
      Offset(_horizontalVelocity * dt, _verticalVelocity * dt),
    );
    // A null position mid-drag is a defunct scrollable: stop that axis
    // and keep the session; cancellation is the backstop's job.
    final vertical = _port.verticalPosition;
    if (_verticalVelocity != 0.0) {
      if (vertical == null) {
        _verticalVelocity = 0.0;
      } else {
        vertical.jumpTo(
          (vertical.pixels + step.dy).clamp(
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
          (horizontal.pixels + step.dx).clamp(
            horizontal.minScrollExtent,
            horizontal.maxScrollExtent,
          ),
        );
      }
    }
    // Stopped once no axis can move, a zero velocity or a position at its
    // end alike, rather than ticking a clamped step every frame. The
    // velocities stay: [evaluate], at start and on every pointer move,
    // is the restart door, as the pointer update is for Flutter's own
    // edge autoscroller (`widgets/scrollable_helpers.dart:282-303`).
    if (!_canAdvance()) {
      _ticker.stop();
    }
  }

  /// Whether a tick would move anything: some axis with a velocity whose
  /// position has room in the CONTENT direction that velocity drives,
  /// read through the one delta conversion so a reversed axis is judged
  /// by where its content lies.
  bool _canAdvance() {
    final step = _port.contentDeltaFromPaint(
      Offset(_horizontalVelocity, _verticalVelocity),
    );
    return _hasRoom(_port.verticalPosition, step.dy) ||
        _hasRoom(_port.horizontalPosition, step.dx);
  }

  static bool _hasRoom(ScrollPosition? position, double step) {
    if (position == null || step == 0.0) {
      return false;
    }
    return step > 0.0
        ? position.pixels < position.maxScrollExtent
        : position.pixels > position.minScrollExtent;
  }

  void dispose() {
    _ticker.dispose();
  }
}
