/// Internal: the drag session's behavior collaborators.
///
/// Each collaborator owns ONE behavior's state and lifecycle:
/// [AutoScroller] (edge-zone scrolling, per-session ticker),
/// [DwellExpander] (hover-to-open collapsed parents), [MakeRoomDriver]
/// (the paint-only gap), and [DropSettler] (the proxy hand-off glides).
/// The session reaches them by direct calls — no interface — syncing
/// every one of them from its single `resolve()` site and tearing every
/// one of them down from its single `detachAll(exit)` site, dispatched
/// on [SessionExit].
///
/// Class names are public in this underscore-prefixed file: internality
/// is enforced by barrel non-export, and the headless unit tests
/// reference these classes directly.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '_drag_session.dart';
import '_drop_zone_resolver.dart';
import 'tree_controller.dart';

/// Edge-zone autoscroll. Owns its ticker per session — created here,
/// disposed in [detach], no controller-global ticker state. Keys off the
/// FINGER's viewport position, never the probe, because edge zones are
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

  /// Pure velocity ramp: 0 at the zone's inner edge, [maxVelocity] at
  /// the viewport edge, negative when scrolling up. Extracted for the
  /// headless unit tests.
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
      final t = ((viewportDy - (viewportHeight - edgeZone)) / edgeZone)
          .clamp(0.0, 1.0);
      return maxVelocity * t;
    }
    return 0.0;
  }

  /// Starts/stops the ticker for the pointer's current edge-zone
  /// membership. A null [sample] means the scrollable is gone — stop.
  void evaluate(PointerSample? sample) {
    if (sample == null) {
      _stop();
      return;
    }
    final inEdgeZone = sample.viewportDy < _edgeZone ||
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

  void _stop() {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _lastTick = null;
  }

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
      // notification — one re-resolution path for every scroll source.
      position.jumpTo(newPixels);
    }
  }

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

  /// The controller's resolve-and-notify wrapper — the one ASYNC re-entry
  /// into the session's resolve pipeline.
  final VoidCallback _requestResolve;

  Timer? _timer;
  TKey? _armedKey;

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

  void onTargetResolved(TreeDropTarget<TKey>? target) {
    if (target == null) {
      // Transient dead spot: HOLD the last gap. Released only by the
      // session's exit paths below.
      return;
    }
    // Deliberately unconditional — no driver-side debounce. The
    // controller memoizes identical geometry inside [setReorderPreview]
    // (all callers, self-healing against extent/structure changes), so a
    // same-slot re-send is already O(1) there. Do not re-add one here.
    _treeController.setReorderPreview(
      draggedKey: _draggedKey,
      targetKey: target.targetKey,
      gapBelowTarget: target.zone != TreeDropZone.above,
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

/// Drop-settle glides: the floating proxy hands off to the real row
/// mid-flight. On commit, [baselineOverrides] rewrites the dragged row's
/// FLIP baseline entry to the release position; on cancel, [detach]
/// installs the mirror glide back to the unchanged slot. Grab geometry is
/// read through a callback into the session's [DragProbe], the single
/// grab owner.
class DropSettler<TKey> {
  DropSettler({
    required TreeController<TKey, Object?> treeController,
    required PointerSpace<TKey> space,
    required Offset Function() pointerGlobal,
    required double Function() grabDy,
    required TKey draggedKey,
    required Duration duration,
    required Curve curve,
  }) : _treeController = treeController,
       _space = space,
       _pointerGlobal = pointerGlobal,
       _grabDy = grabDy,
       _draggedKey = draggedKey,
       _duration = duration,
       _curve = curve;

  final TreeController<TKey, Object?> _treeController;
  final PointerSpace<TKey> _space;
  final Offset Function() _pointerGlobal;
  final double Function() _grabDy;
  final TKey _draggedKey;
  final Duration _duration;
  final Curve _curve;

  /// The commit script's baseline override: the dragged row's FLIP
  /// starts at the proxy's release position (pointer − grab offset).
  /// Null when the scrollable is gone — the classic old-slot FLIP is the
  /// graceful fallback.
  Map<TKey, double>? baselineOverrides() {
    final release = _space.sample(_pointerGlobal());
    if (release == null) {
      return null;
    }
    return <TKey, double>{
      _draggedKey: release.sliverY - _grabDy(),
    };
  }

  void detach(SessionExit exit) {
    if (exit != SessionExit.cancel) {
      return;
    }
    // Mirror of the commit settle: no mutation happened, so there is no
    // consume-time FLIP to override — install the return glide directly
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

  /// Shared glide install: proxy release position → the row's CURRENT
  /// structural slot (pre-mutation on the cancel path, post-mutation in
  /// the dead-commit fallback).
  ///
  /// Rides the drop-settle channel, so the glide honors its OWN
  /// family's zero rule rather than `reorderSlide`'s. A null sample
  /// means the scrollable is gone (the cancel path also runs from the
  /// deactivate backstop's POST-FRAME callback after a full tree
  /// swap-out); a null structural y means the row left the visible
  /// order (dead-commit fallback into a collapsed parent). Both skip
  /// silently — nothing is visible to glide.
  void _installReleaseGlide() {
    final release = _space.sample(_pointerGlobal());
    final structuralY = _treeController.scrollOffsetOf(_draggedKey);
    if (release == null || structuralY == null) {
      return;
    }
    _treeController.animateDropSettleGlide(
      <TKey, ({double y, double x})>{
        _draggedKey: (y: release.sliverY - _grabDy(), x: 0.0),
      },
      <TKey, ({double y, double x})>{
        _draggedKey: (y: structuralY, x: 0.0),
      },
      duration: _duration,
      curve: _curve,
    );
  }
}
