/// Internal: holds a structural diff while a drag is live and re-examines
/// it once the drag ends. Not exported from the package barrel.
///
/// Shared by `SyncedSliverTree` and the declarative `SectionedSliverList`,
/// which is why the gate carries no policy of its own: each owner decides
/// which input changes owe a diff, and each attaches at a different point
/// in its own `initState`.
///
/// None of the protocol's rules are checkable at a single call site, so
/// each is documented where it is enforced. The governing one is SCHEDULE,
/// DO NOT ACT: a drag-end transition may only queue work, never mutate
/// structure inline. See [_handleReorderChanged].
library;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import 'tree_reorder_controller.dart';

/// Defers one owner's structural diff across a live drag.
///
/// The gate answers two questions and nothing more: "may I sync now"
/// ([isDragging]) and "do I still owe one" ([isDeferred]). Deciding which
/// input changes owe a diff stays in the owner's `didUpdateWidget`.
class DeferredSyncGate<TKey> {
  DeferredSyncGate({
    required TreeReorderController<TKey> reorderController,
    required bool Function() isMounted,
    required VoidCallback onSync,
  }) : _reorderController = reorderController,
       _isMounted = isMounted,
       _onSync = onSync;

  final TreeReorderController<TKey> _reorderController;

  /// The owner's liveness question, asked at post-frame fire time because
  /// a scheduled callback can outlive the owning `State` (see [dispose]).
  /// A callback rather than a captured flag, so the question is answered
  /// when it is asked, by the object that can answer it.
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

  /// Clears the bit after the owner synced on its own route, meaning its
  /// `didUpdateWidget` reached its sync call. The gate clears the bit
  /// itself when it drives the sync instead, so a caller never has to
  /// pair the two routes.
  void markSynced() {
    _syncDeferred = false;
  }

  /// Starts watching drag-session transitions.
  ///
  /// Separate from the constructor because registration order is
  /// load-bearing and differs per owner: `SyncedSliverTree` attaches after
  /// its first sync and initial expansion pass, the sectioned widget
  /// before its first sync. Neither call should move.
  void attach() {
    _reorderController.addListener(_handleReorderChanged);
  }

  /// Detaches from the controller; call before disposing the reorder
  /// controller. A post-frame callback already scheduled is NOT cancelled,
  /// because the scheduler offers no way to cancel one; it is guarded
  /// instead by the liveness and drag-generation checks inside the
  /// callback itself.
  void dispose() {
    _reorderController.removeListener(_handleReorderChanged);
  }

  /// Re-examines a deferred diff on the drag-end edge.
  ///
  /// Schedules rather than acting, which is the protocol's governing rule:
  /// this listener runs AHEAD of the reorderable widget's own drag-UI
  /// teardown in the same dispatch, while a make-room release animation is
  /// still in flight. Syncing inline here would run removal animations
  /// under a row the drag UI still considers its own.
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
