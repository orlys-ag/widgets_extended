/// Internal: the drag session's behavior collaborators.
///
/// Each collaborator owns ONE behavior's state and lifecycle:
/// [AutoScroller] (edge-zone scrolling, per-session ticker),
/// [DwellExpander] (hover-to-open collapsed parents), [MakeRoomDriver]
/// (the paint-only gap), and [DropSettler] (the proxy hand-off glides).
/// The session calls them directly rather than through an interface,
/// syncing all of them from its single `resolve()` site and tearing all
/// of them down from its single `detachAll(exit)` site, which dispatches
/// on [SessionExit]. Every `detach` therefore takes a [SessionExit], even
/// the ones that ignore it.
///
/// Class names are public despite the underscore-prefixed file:
/// internality comes from barrel non-export, and the headless unit tests
/// construct these classes directly.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '_drag_session.dart';
import '_drop_zone_resolver.dart';
import 'tree_controller.dart';

/// Edge-zone autoscroll. Owns its ticker per session, created here and
/// disposed in [detach], so no ticker state outlives a drag. Keys off the
/// FINGER's viewport position, never the probe, because an edge zone is
/// about where the hand is, not where the card is.
class AutoScroller<TKey> {
  AutoScroller({
    required TickerProvider vsync,
    required PointerSpace<TKey> space,
    required Offset Function() pointerGlobal,
    required double edgeZone,
    required double maxVelocity,
  }) : _space = space,
       _pointerGlobal = pointerGlobal,
       _edgeZone = edgeZone,
       _maxVelocity = maxVelocity {
    _ticker = vsync.createTicker(_onTick);
  }

  final PointerSpace<TKey> _space;
  final Offset Function() _pointerGlobal;
  final double _edgeZone;
  final double _maxVelocity;

  late final Ticker _ticker;
  Duration? _lastTick;

  /// Pure velocity ramp: 0 at the zone's inner edge, [maxVelocity] at the
  /// viewport edge, negative in the leading zone, and 0 between them.
  /// Static and side-effect-free so it can be exercised without a
  /// session.
  static double velocityAt({
    required double viewportDy,
    required double viewportHeight,
    required double edgeZone,
    required double maxVelocity,
  }) {
    if (viewportDy < edgeZone) {
      final t = 1 - (viewportDy / edgeZone).clamp(0.0, 1.0);
      return -maxVelocity * t;
    }
    if (viewportDy > viewportHeight - edgeZone) {
      final t = ((viewportDy - (viewportHeight - edgeZone)) / edgeZone).clamp(
        0.0,
        1.0,
      );
      return maxVelocity * t;
    }
    return 0.0;
  }

  /// Starts or stops the ticker for the pointer's current edge-zone
  /// membership. A null [sample] means the scrollable is gone: stop.
  void evaluate(PointerSample? sample) {
    if (sample == null) {
      _stop();
      return;
    }
    final inEdgeZone =
        sample.viewportDy < _edgeZone ||
        sample.viewportDy > sample.viewportHeight - _edgeZone;
    if (inEdgeZone) {
      if (!_ticker.isActive) {
        _lastTick = null;
        _ticker.start();
      }
    } else {
      _stop();
    }
  }

  /// Idles the ticker and forgets the last tick stamp, so a later start
  /// begins a fresh time base instead of integrating a stale gap.
  void _stop() {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _lastTick = null;
  }

  /// Integrates one frame of scroll velocity into the scroll position.
  /// The first tick assumes a 16ms step, having no previous stamp to
  /// difference against.
  void _onTick(Duration elapsed) {
    // Nullable-sample hardening: between the tree unmounting mid-drag
    // and the backstop's post-frame cancel, one tick can still fire.
    final sample = _space.sample(_pointerGlobal());
    final position = _space.position;
    if (sample == null || position == null) {
      _stop();
      return;
    }

    final velocity = velocityAt(
      viewportDy: sample.viewportDy,
      viewportHeight: sample.viewportHeight,
      edgeZone: _edgeZone,
      maxVelocity: _maxVelocity,
    );
    if (velocity == 0) {
      _stop();
      return;
    }

    final dt = _lastTick == null
        ? const Duration(milliseconds: 16)
        : elapsed - _lastTick!;
    _lastTick = elapsed;

    final newPixels = (position.pixels + velocity * dt.inMicroseconds / 1e6)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (newPixels != position.pixels) {
      // jumpTo synchronously notifies the session's scroll-position
      // listener, which re-resolves the target and coalesces the
      // notification: one re-resolution path for every scroll source.
      position.jumpTo(newPixels);
    }
  }

  /// Stops and disposes the ticker. The exit reason does not matter:
  /// autoscroll leaves no state behind to unwind differently.
  void detach(SessionExit exit) {
    _stop();
    _ticker.dispose();
  }
}

/// Hover-dwell auto-expand: dwelling on an `into` target that is
/// collapsed AND has live children expands it after the delay.
/// Re-resolving to the SAME candidate leaves the running timer alone;
/// anything else cancels it, so an abandoned hover never fires.
class DwellExpander<TKey> {
  DwellExpander({
    required TreeController<TKey, Object?> treeController,
    required Duration? delay,
    required bool Function() sessionLive,
    required VoidCallback requestResolve,
  }) : _treeController = treeController,
       _delay = delay,
       _sessionLive = sessionLive,
       _requestResolve = requestResolve;

  final TreeController<TKey, Object?> _treeController;
  final Duration? _delay;

  /// Fire-time identity check: the session may have been replaced while
  /// the timer ran. A callback, so this class never sees the controller.
  final bool Function() _sessionLive;

  /// The controller's resolve-and-notify wrapper: the one ASYNC re-entry
  /// into the session's resolve pipeline.
  final VoidCallback _requestResolve;

  Timer? _timer;
  TKey? _armedKey;

  /// Re-arms the dwell timer for the newly resolved [target].
  ///
  /// A target qualifies only as an `into` drop on a collapsed row that
  /// still has live children. Re-resolving to the same candidate is a
  /// no-op, so a steady hover keeps one timer running; anything else
  /// cancels it. A null or zero delay disables the behavior outright.
  void onTargetResolved(TreeDropTarget<TKey>? target) {
    final delay = _delay;
    if (delay == null || delay == Duration.zero) {
      return;
    }
    TKey? candidate;
    if (target != null &&
        target.zone == TreeDropZone.into &&
        !_treeController.isExpanded(target.targetKey) &&
        _treeController.hasLiveChildren(target.targetKey)) {
      candidate = target.targetKey;
    }
    if (candidate == _armedKey) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _armedKey = candidate;
    if (candidate == null) {
      return;
    }
    final armedFor = candidate;
    _timer = Timer(delay, () {
      // Fire-time revalidation: the session may have been replaced, the
      // dwell re-armed for another key, or the node removed/expanded by
      // an external mutation while the timer ran.
      if (!_sessionLive()) {
        return;
      }
      if (_armedKey != armedFor) {
        return;
      }
      _timer = null;
      _armedKey = null;
      if (_treeController.getNodeData(armedFor) == null ||
          _treeController.isPendingDeletion(armedFor) ||
          _treeController.isExpanded(armedFor)) {
        return;
      }
      _treeController.expand(key: armedFor);
      // The expansion changes layout under the stationary pointer;
      // re-resolve now instead of waiting for the next pointer/scroll
      // event (the expand animation refines it further via those paths).
      _requestResolve();
    });
  }

  /// Cancels any armed dwell. The exit reason does not matter: a timer
  /// that never fired has changed nothing to unwind.
  void detach(SessionExit exit) {
    _timer?.cancel();
    _timer = null;
    _armedKey = null;
  }
}

/// Make-room preview driver: opens/re-targets the paint-only gap at the
/// resolved slot, and HOLDS it across transient null targets. Releasing
/// mid-drag would shift rows under a stationary pointer and make the
/// resolution oscillate.
class MakeRoomDriver<TKey> {
  MakeRoomDriver({
    required TreeController<TKey, Object?> treeController,
    required TKey draggedKey,
    required Duration duration,
    required Curve curve,
  }) : _treeController = treeController,
       _draggedKey = draggedKey,
       _duration = duration,
       _curve = curve;

  final TreeController<TKey, Object?> _treeController;
  final TKey _draggedKey;
  final Duration _duration;
  final Curve _curve;

  /// Opens or re-targets the gap at the resolved slot. A null target is a
  /// transient dead spot and HOLDS the current gap; only the session's
  /// exit paths release it.
  void onTargetResolved(TreeDropTarget<TKey>? target) {
    if (target == null) {
      return;
    }
    // Deliberately unconditional: no driver-side debounce. The controller
    // memoizes identical geometry and timing mode inside
    // [setReorderPreviewAtIndex], so a same-slot re-send already early-
    // outs there, and that memo self-heals against extent and structure
    // changes in a way a driver-side one could not. Do not re-add one.
    //
    // The gap comes from the RESOLVED SLOT, not from the hovered row.
    // Deriving it from the row is only correct while the slot is
    // adjacent to it, which stops being true whenever a policy veto or a
    // cycle disables the below-on-expanded-parent rule over a row that
    // has a visible subtree. The gap then opens under the row while the
    // commit lands past that row's whole subtree.
    _treeController.setReorderPreviewAtIndex(
      draggedKey: _draggedKey,
      gapVisibleIndex: target.gapVisibleIndex,
      duration: _duration,
      curve: _curve,
    );
  }

  /// A named commit-script operation, not part of teardown: the snap must
  /// run BEFORE the mutation and AFTER the FLIP baseline captured the
  /// shifted painted positions, so it cannot live in [detach].
  void snapForCommit() {
    _treeController.clearReorderPreview(animate: false);
  }

  /// Releases the gap according to how the session ended: a commit has
  /// already snapped it through [snapForCommit], a cancel animates it
  /// closed, and a dispose drops it with no motion left to watch.
  void detach(SessionExit exit) {
    switch (exit) {
      case SessionExit.commit:
        break; // snapForCommit already ran inside the commit script.
      case SessionExit.cancel:
        _treeController.clearReorderPreview(
          animate: true,
          duration: _duration,
          curve: _curve,
        );
      case SessionExit.dispose:
        _treeController.clearReorderPreview(animate: false);
    }
  }
}

/// Drop-settle glides: the floating proxy hands off to the real rows
/// mid-flight, the dragged row AND its visible subtree alike. On
/// commit, [baselineOverrides] rewrites each subtree row's FLIP
/// baseline entry to its position in the proxy stack at release; on
/// cancel, [detach] installs the mirror glides back to the unchanged
/// slots. Grab geometry is read through a callback into the session's
/// [DragProbe], the single grab owner.
class DropSettler<TKey> {
  DropSettler({
    required TreeController<TKey, Object?> treeController,
    required PointerSpace<TKey> space,
    required Offset Function() pointerGlobal,
    required double Function() grabDy,
    required TKey draggedKey,
    required Duration duration,
    required Curve curve,
    double Function()? proxyCrossOffset,
  }) : _treeController = treeController,
       _space = space,
       _pointerGlobal = pointerGlobal,
       _grabDy = grabDy,
       _draggedKey = draggedKey,
       _duration = duration,
       _curve = curve,
       _proxyCrossOffset = proxyCrossOffset {
    _stack = _captureStack();
  }

  final TreeController<TKey, Object?> _treeController;
  final PointerSpace<TKey> _space;
  final Offset Function() _pointerGlobal;
  final double Function() _grabDy;
  final TKey _draggedKey;
  final Duration _duration;
  final Curve _curve;

  /// The dragged VISIBLE subtree's stack, captured at construction, which
  /// is `startDrag` time and the same reads the proxy's drawing capture
  /// uses: each row in visible order with its y offset within the stack
  /// (cumulative captured extents) and its indent RELATIVE to the dragged
  /// row. Entry 0 is the dragged row at (0, 0), so a leaf or collapsed
  /// drag reduces to one entry. Frozen per session; rows that leave the
  /// visible order mid-drag are skipped per entry at install time.
  late final List<({TKey key, double relativeY, double relativeIndent})>
  _stack;

  /// Snapshots the dragged row and its visible descendants into stack
  /// coordinates. Falls back to a lone dragged-row entry when the row
  /// sits outside the visible order (an imperative drag of a hidden row)
  /// or has no visible subtree.
  List<({TKey key, double relativeY, double relativeIndent})>
  _captureStack() {
    final tree = _treeController;
    final single = <({TKey key, double relativeY, double relativeIndent})>[
      (key: _draggedKey, relativeY: 0.0, relativeIndent: 0.0),
    ];
    final index = tree.getVisibleIndex(_draggedKey);
    if (index < 0) {
      // Imperative drag of a hidden row: no stack geometry to speak
      // of, keep the single-entry behavior.
      return single;
    }
    final size = tree.visibleSubtreeSize(_draggedKey);
    if (size <= 1) {
      return single;
    }
    final draggedDepth = tree.getDepth(_draggedKey);
    final indentWidth = tree.indentWidth;
    final rows = <({TKey key, double relativeY, double relativeIndent})>[];
    double y = 0.0;
    for (int i = index; i < index + size; i++) {
      final rowKey = tree.visibleNodes[i];
      final nid = tree.nidOf(rowKey);
      rows.add((
        key: rowKey,
        relativeY: y,
        relativeIndent: (tree.getDepth(rowKey) - draggedDepth) * indentWidth,
      ));
      y += nid >= 0 ? tree.getCurrentExtentNid(nid) : 0.0;
    }
    return rows;
  }

  /// The proxy's VISUAL cross offset in sliver cross space, sampled at
  /// glide-install time so a release mid-animation hands off exactly
  /// where the card visually is. Supplied by the presentation layer
  /// through `startDrag(proxyCrossOffset:)`, and null for sessions with
  /// no proxy (imperative callers, unit tests): their glides carry no x
  /// motion and their baseline override preserves each row's captured x.
  final double Function()? _proxyCrossOffset;

  /// The commit script's baseline override: each row's FLIP starts at its
  /// position in the proxy stack at release, which is the pointer minus
  /// the grab offset plus that row's stack offset. Null when the
  /// scrollable is gone, leaving the ordinary old-slot FLIP as the
  /// graceful fallback.
  Map<TKey, ({double y, double? x})>? baselineOverrides() {
    final release = _space.sample(_pointerGlobal());
    if (release == null) {
      return null;
    }
    // One entry per subtree row: y stacks below the release position by
    // the captured cumulative extents; x is the proxy's visual cross
    // offset plus the row's relative indent, or null (preserve that row's
    // captured x) when the session has no proxy presentation. Sessions
    // that opted into `settleFromRelease` without a proxy get the
    // multi-row y as well, so their subtree rows emerge stacked under the
    // release point.
    final baseY = release.sliverY - _grabDy();
    final crossOffset = _proxyCrossOffset?.call();
    final map = <TKey, ({double y, double? x})>{};
    for (final row in _stack) {
      map[row.key] = (
        y: baseY + row.relativeY,
        x: crossOffset == null ? null : crossOffset + row.relativeIndent,
      );
    }
    return map;
  }

  /// Installs the return glide, on cancel only. A commit carries its
  /// hand-off through the FLIP baseline override instead, and a dispose
  /// has no surface left to animate on.
  void detach(SessionExit exit) {
    if (exit != SessionExit.cancel) {
      return;
    }
    // Mirror of the commit settle: no mutation happened, so there is no
    // consume-time FLIP to override; install the return glide directly
    // toward the row's unchanged slot.
    _installReleaseGlide();
  }

  /// Named commit-script op for the DEAD-commit-slide fallback: the
  /// commit FLIP cannot carry the proxy handoff when its reorderSlide
  /// family is zeroed, so the glide from the release position into the
  /// row's NEW (post-mutation) slot is installed directly, through the
  /// drop-settle channel. Called by `endDrag` after the mutation and
  /// before teardown; NOT part of [detach].
  void glideIntoCommittedSlot() {
    _installReleaseGlide();
  }

  /// Shared glide install, from the proxy release position to each row's
  /// CURRENT structural slot: pre-mutation on the cancel path,
  /// post-mutation in the dead-commit fallback. One entry per subtree
  /// row.
  ///
  /// Rides the drop-settle channel, so the glide honors its OWN family's
  /// zero rule rather than `reorderSlide`'s.
  ///
  /// In x, each glide starts at the row's position in the proxy stack
  /// (the proxy's visual cross offset plus its relative indent) and
  /// settles at the row's structural indent. Without a proxy
  /// cross-offset source, prior and current x are equal per row, so the
  /// glide is y-only.
  ///
  /// Two skips, both silent because nothing would be visible to animate:
  /// a null sample means the scrollable is gone, which the cancel path
  /// can hit because it also runs from the deactivate backstop's
  /// POST-FRAME callback after a full tree swap-out; a null structural y
  /// means that row left the visible order, which the dead-commit
  /// fallback can hit when the subtree lands under a collapsed parent.
  void _installReleaseGlide() {
    final release = _space.sample(_pointerGlobal());
    if (release == null) {
      return;
    }
    final baseY = release.sliverY - _grabDy();
    final crossOffset = _proxyCrossOffset?.call();
    final prior = <TKey, ({double y, double x})>{};
    final current = <TKey, ({double y, double x})>{};
    for (final row in _stack) {
      final structuralY = _treeController.scrollOffsetOf(row.key);
      if (structuralY == null) {
        continue;
      }
      final structuralX = _treeController.getIndent(row.key);
      final releaseX = crossOffset == null
          ? structuralX
          : crossOffset + row.relativeIndent;
      prior[row.key] = (y: baseY + row.relativeY, x: releaseX);
      current[row.key] = (y: structuralY, x: structuralX);
    }
    if (prior.isEmpty) {
      return;
    }
    _treeController.animateDropSettleGlide(
      prior,
      current,
      duration: _duration,
      curve: _curve,
    );
  }
}
