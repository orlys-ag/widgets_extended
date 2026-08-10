/// Holds a structural diff while a drag is live and re-examines it once
/// the drag ends. Not exported from the package barrel.
///
/// Extracted from two independent copies of the same protocol (in
/// `SyncedSliverTree` and the declarative `SectionedSliverList`) so its
/// invariants live in one place. The protocol carries four of them, none
/// locally checkable at a call site:
///
/// 1. Schedule, do not act. The drag-end listener is registered by the
///    owner's `initState` and so runs AHEAD of the reorderable widget's
///    own drag-UI teardown in the same dispatch, while a make-room
///    release animation is still in flight. Mutating structure
///    synchronously would run removal animations under a row the drag UI
///    still considers its own.
/// 2. `ensureVisualUpdate()` before `addPostFrameCallback`, because a
///    post-frame callback does not itself schedule a frame.
/// 3. Compare `dragGeneration`, not `isDragging`. Generations never
///    repeat, so an unchanged one proves no session was installed since.
/// 4. Recheck the deferred bit inside the callback, because a rebuild
///    usually consumes it first.
library;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import 'tree_reorder_controller.dart';

/// Holds a structural diff while a drag is live and re-examines it once
/// the drag ends.
///
/// The owner keeps its own policy: which prop changes owe a diff stays
/// in its `didUpdateWidget`. The gate answers "may I sync now"
/// ([isDragging]) and "do I still owe one" ([isDeferred]), nothing else.
class DeferredSyncGate<TKey> {
  DeferredSyncGate({
    required TreeReorderController<TKey> reorderController,
    required bool Function() isMounted,
    required VoidCallback onSync,
  }) : _reorderController = reorderController,
       _isMounted = isMounted,
       _onSync = onSync;

  final TreeReorderController<TKey> _reorderController;

  /// The owner's liveness question, asked at post-frame fire time.
  /// [dispose] removes the drag listener but CANNOT cancel a post-frame
  /// callback that is already scheduled, so one can still fire after the
  /// owning `State` is gone. Reading `mounted` from a dead `State` is
  /// safe; this stays a callback so the liveness question stays with the
  /// object that can answer it.
  final bool Function() _isMounted;

  /// Runs the owner's sync. Must read the owner's CURRENT input (for a
  /// widget, `widget` read fresh) so a deferred run always applies the
  /// LATEST state. Nothing is captured at deferral time.
  final VoidCallback _onSync;

  /// The current input has not been diffed yet. ONE idempotent bit:
  /// nothing is queued, because [_onSync] always applies the latest
  /// input.
  bool _syncDeferred = false;

  /// Edge detector for the drag-end transition.
  bool _wasDragging = false;

  /// Whether the current input still owes a diff.
  bool get isDeferred {
    return _syncDeferred;
  }

  /// Whether a diff must not run right now.
  bool get isDragging {
    return _reorderController.isDragging;
  }

  /// Records that the current input has not been diffed yet.
  void markDeferred() {
    _syncDeferred = true;
  }

  /// Clears the bit after the owner synced by its OWN route, which is
  /// `didUpdateWidget` reaching its sync call. The gate clears the bit
  /// itself on ITS route, after [_onSync] returns from the post-frame
  /// callback, so a caller never has to pair the two.
  void markSynced() {
    _syncDeferred = false;
  }

  /// Starts watching session transitions. Separate from the constructor
  /// because listener REGISTRATION ORDER is load-bearing and differs per
  /// owner: `SyncedSliverTree` attaches after its first sync and initial
  /// expansion pass, the sectioned widget before its first sync. Each
  /// owner must keep its current position.
  void attach() {
    _reorderController.addListener(_handleReorderChanged);
  }

  /// Detaches from the controller. Call before disposing the reorder
  /// controller. An already-scheduled post-frame callback is NOT
  /// cancelled (the scheduler has no API for that); it is guarded by
  /// [_isMounted] and the generation check instead.
  void dispose() {
    _reorderController.removeListener(_handleReorderChanged);
  }

  /// Watches session transitions so a deferred diff is re-examined once
  /// the drag ends. Deliberately schedules rather than acting: this
  /// listener runs AHEAD of the reorderable widget's own drag-UI
  /// teardown in the same dispatch, and a make-room release animation is
  /// in flight, so mutating structure synchronously here would run
  /// removal animations under a row the drag UI still considers its own.
  void _handleReorderChanged() {
    final reorder = _reorderController;
    final dragging = reorder.isDragging;
    if (_wasDragging && !dragging && _syncDeferred) {
      final generation = reorder.dragGeneration;
      // A post-frame callback does not itself schedule a frame.
      SchedulerBinding.instance.ensureVisualUpdate();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) {
          return;
        }
        // Generations are never reused, so an unchanged one means no
        // session was installed since. This SUBSUMES an `isDragging`
        // recheck, which alone would let a callback scheduled by drag 1
        // apply drag-1-era input against post-drag-2 truth.
        if (reorder.dragGeneration != generation) {
          return;
        }
        if (!_syncDeferred) {
          // A rebuild already consumed it, which is the common case when
          // the app records the move synchronously: its setState dirties
          // for the next frame, and that frame's build runs before this.
          return;
        }
        _onSync();
        _syncDeferred = false;
      });
    }
    _wasDragging = dragging;
  }
}
