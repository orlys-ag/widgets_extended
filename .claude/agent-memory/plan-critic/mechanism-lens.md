# Mechanism lens: recurring holes in plans for this repo

Three checks that have each caught a real defect and are cheap to run.

## 1. "Coalesced" notify is only coalesced in transientCallbacks

`AnimationCoordinator.notifyListeners` coalesces to a microtask ONLY when
`SchedulerBinding.instance.schedulerPhase == SchedulerPhase.transientCallbacks`
(`_animation_coordinator.dart:304`, rationale at `:299`). Layout runs in
persistentCallbacks, so any animation-channel notify issued from inside a
layout method dispatches SYNCHRONOUSLY to every listener. If the render
object's own listener can call `markNeedsLayout`, that is the
"must not re-dirty itself while still being laid out" throw
(`rendering/object.dart:2382` branch). Whenever a plan puts an animation
INSTALL inside layout, ask what the install notifies.

## 2. A gesture-owning row State that can unmount mid-drag needs a backstop

`MultiDragGestureRecognizer.dispose` resolves its arena entries and never
calls `cancel()`/`end()` on its client, so disposing it under a live session
orphans the session (ticker, flags, held preview offsets all survive). The
tree solves it in THREE places, not one: the two replacement legs in
`_startDragFromHandle` (`sliver_reorderable_tree.dart:1358`, `:1379`), a
render-object drag PIN that stops eviction of a live dragged row, and a
`deactivate()` lifecycle backstop that defers a cancel past the frame
(`sliver_reorderable_tree.dart:998`). A plan that copies only the handle trio
has copied one of the three.

## 3. Commit-by-callback plus "a mutation on the dragged key cancels the drag"

If a drag layer reports its commit to app code that then calls a mutator, and
the mutator cancels the session when the dragged flag is set, the ORDER of
"clear the flag" against "report" is load-bearing on the primary path, not an
edge case. The house rule is in source: report AFTER teardown
(`tree_reorder_controller.dart:643`), because a second teardown
double-disposes the autoscroll ticker (`tree_reorder_controller.dart:523`).
