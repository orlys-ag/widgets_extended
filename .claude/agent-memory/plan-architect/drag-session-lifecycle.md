# A drag session whose recognizer lives on the dragged child's State

Pattern that recurs whenever a pointer session is owned by a controller but
DRIVEN by a gesture recognizer that a virtualized child's `State` owns. The
tree does this (`SliverReorderableTree` / `TreeReorderController`) and any
board / grid / list with the same shape inherits every hazard below.

## Three separate rules, and none of them substitutes for another

### 1. The recognizer's own disposal is at `dispose`, never `deactivate`

An element can be reactivated, and the drag it is driving would lose its
recognizer mid-flight (`sliver_reorderable_tree.dart:959`).

Its two replacement legs are separate again: leg one cancels a session this
`State` already owns BEFORE replacing, because
`MultiDragGestureRecognizer.dispose` "resolves its arena entries and never
calls `cancel()` or `end()` on its client" (`sliver_reorderable_tree.dart:1366`);
leg two disposes whatever is in hand UNCONDITIONALLY, not on a pointer-identity
test, because nested handles deliver two pointer-downs for the SAME pointer
and an identity guard leaks the inner recognizer.

### 2. The pin stops LAYOUT from evicting the dragged child

A render-object pin (`ReorderRenderPort.pinNode`/`unpinNode`,
`reorder_render_port.dart:124`) exists because "the drag gesture's recognizer
lives on the row's own `State`, so evicting the row would orphan the session"
(`reorder_render_port.dart:121`).

This is NOT optional on anything that autoscrolls during a drag: autoscroll
carries the dragged item's own structural position out of the built window as
a matter of course. On a TWO-axis viewport it is worse, because both axes
scroll.

An exiting-item retention map does not cover it: a dragged item is not
exiting, so its vicinity is not in that map.

### 3. The `deactivate` backstop covers every unmount the pin cannot

The pin only stops layout. It does not stop a parent rebuild that changes the
subtree's shape, an element move, or the whole scrollable unmounting. In all
of those the `State` that owns the recognizer goes away with the session live,
and rule 1 says the recognizer's `dispose` will NOT end the session. Result:
a permanently wedged session (the dragging flag set, the make-room gap held,
the per-session ticker running, no route left to `update`/`end`).

Shape, all four properties load-bearing
(`sliver_reorderable_tree.dart:998` and `:979`):

- Flip the local ownership flag SYNCHRONOUSLY, defer the teardown.
- Defer to a POST-FRAME callback, not a microtask: `deactivate` runs inside a
  `BuildOwner.buildScope`, where `notifyListeners` / `setState` throw
  "setState() or markNeedsBuild() called during build"
  (`sliver_reorderable_tree.dart:1011`); a microtask can still land inside
  this frame's build window (`:1014`).
- RE-VALIDATE session ownership inside the callback: a new session may have
  started, or the controller may have been disposed (`:1016`).
- CAPTURE everything the callback needs before `super.deactivate()`, because
  `widget` and `context` are unreadable after the `State` unmounts (`:1019`).

## Commit ordering, when a mutation-cancel rule exists

If the design says "a mutation touching the dragged key cancels the session at
the mutation" (the usual rule, because a key-only drag controller commits by
REPORTING and an unknown key throws), then the commit script's ORDER is part
of that rule and belongs at the same normative site:

1. resolve and validate, compute what to report;
2. TEAR THE SESSION DOWN (release the preview, unpin, clear the dragging flag
   and the cancel hook in one call);
3. THEN report.

Report-first makes every SUCCESSFUL drop cancel its own session from inside
its own commit script, and the second teardown "double-disposes the autoscroll
ticker and throws out of the `finally`" (`tree_reorder_controller.dart:523`).
The tree states the rule in source: "Report AFTER teardown, so a synchronous
setState in the handler cannot land mid-commit"
(`tree_reorder_controller.dart:643`).

## Port members a plan forgets to declare

An exported `RenderPort` interface that tests fake cannot gain members later
without breaking every fake, so declare them when the plan declares the
throw that needs them:

- `drivesController(Object controller)` (`reorder_render_port.dart:63`) is
  what makes `startDrag`'s cross-controller `ArgumentError` implementable at
  all (`tree_reorder_controller.dart:281`).
- `pinNode` / `unpinNode`, per rule 2.

## Collision check to do once

If the module ALSO has an exiting-item retention map, state why the pin and
that map never hold the same vicinity, both ways: same item (the
mutation-cancel unpins before the mutation marks it exiting) and different
items (a lane is exclusive within its cluster and an exiting item holds its
lane whole until settle). Without the second half the release sweep needs a
combination rule.

## The scroll subscription is a THIRD per-session resource, and plans forget it

A drag session that autoscrolls writes with `jumpTo`. `jumpTo` calls
`forcePixels` (`widgets/scroll_position_with_single_context.dart:201`), which
calls `notifyListeners()` synchronously (`widgets/scroll_position.dart:494`).
That is a write with NO READER unless the session subscribed. Without it,
`resolve()` runs on pointer events only, and THREE triggers move content under
a stationary finger: the autoscroll tick, a fling settling after the finger
stopped, and a programmatic scroll issued mid-drag. Replacing the subscription
with an explicit re-resolve call from the tick closes only the first.

It is a TRIPLE, not a pair, and the tree ships all three in its
pointer-to-scrollable component: `bindScroll` (`_drag_session.dart:88`),
`syncScrollSubscription` (`_drag_session.dart:97`), `unbindScroll`
(`_drag_session.dart:115`). Bind is in `startDrag` one line after the pin
(`tree_reorder_controller.dart:375`); unbind is in the single teardown beside
the unpin (`_drag_session.dart:429`).

**The re-point leg is not optional, and the usual justification understates
it.** The commonly cited arm is `didUpdateWidget` replacing the position when
the resolved physics `runtimeType` differs (`widgets/scrollable.dart:690`).
The bigger arm is `ScrollableState.didChangeDependencies`, which calls
`_updatePosition()` UNCONDITIONALLY (`widgets/scrollable.dart:673`); one of
its own dependencies is `ScrollConfiguration.of(context)`, registered inside
that method (`widgets/scrollable.dart:618`, a
`dependOnInheritedWidgetOfExactType` at
`widgets/scroll_configuration.dart:410`). Both arms end at
`createScrollPosition` (`widgets/scrollable.dart:633`), which returns a FRESH
instance every time, and the old one is disposed on a microtask
(`widgets/scrollable.dart:630`). A listener left behind never fires again.

Put the re-point in the once-per-event SAMPLE, so it is the correctness floor
with no widget layer required; a widget-level edge trigger only removes
latency (`_drag_session.dart:128`, `_drag_session.dart:131`).

Unbinding is safe on a disposed position (`foundation/change_notifier.dart:330`)
and during that position's own dispatch (`foundation/change_notifier.dart:349`),
and both are reachable, because the re-resolution runs app code that may end
the session (`tree_reorder_controller.dart:437`).

On a TWO-axis viewport, subscribe BOTH positions: `TwoDimensionalScrollable`
builds two `Scrollable` subclasses (`widgets/scrollable.dart:2171`,
`widgets/scrollable.dart:2438`), each with its own `ScrollableState`, so
either subscription can be lost independently.
