# RenderTwoDimensionalViewport facts a board/grid plan keeps getting wrong

Read from the stable 3.44.4 checkout at
`C:/flutter_sdk/flutter/packages/flutter/lib/src/`. Re-verify line numbers
against the tree in use; the FACTS below are what matter.

## `markNeedsLayout()` cannot be called from inside `layoutChildSequence`

`RenderTwoDimensionalViewport.performLayout` calls `layoutChildSequence()`
directly (`widgets/two_dimensional_viewport.dart:1336`), so anything the
subclass does there runs during layout.

- `markNeedsLayout` opens with `assert(_debugCanPerformMutations)`
  (`rendering/object.dart:2661`).
- `_debugCanPerformMutations` returns early ONLY when the owner is null or the
  owner is not doing layout (`rendering/object.dart:2327`); during layout it
  reaches the `activeLayoutRoot == this` branch (`rendering/object.dart:2382`)
  and throws "A RenderObject must not re-dirty itself while still being laid
  out" (`rendering/object.dart:2385`).
- With asserts off it is a no-op twice over: `_needsLayout` is already true so
  the call early-returns (`rendering/object.dart:2662`), and `layout()` clears
  the flag afterwards.

So "break out of the loop and re-run the frame" is not available. The
framework's own idiom is the answer: `RenderViewport.performLayout` loops
(`rendering/viewport.dart:1723` to `:1740`) and at the ceiling throws a
`FlutterError` INSIDE an assert block (`:1741`), i.e. debug-only, then paints
at the last attempted offset in release. A `false` return from
`applyContentDimensions` is just another round of the same loop (the `break`
at `:1736` is reached only on true).

A call from an animation tick, a setter, or a post-frame callback is fine:
those are outside layout.

## Keep-alive release does NOT require obtaining the vicinity

`_cacheKeepAlives` re-buckets and `_reuseChild`s only children whose
`keepAlive` is true (`widgets/two_dimensional_viewport.dart:1365`), and it
operates on `_children` minus `_activeChildrenForLayoutPass` (`:1361`), so a
flag left true on an ACTIVE child retains nothing.

To release: clear `keepAlive` and simply do not obtain. `_endLayout` (`:1343`)
unmounts every element not reused (`:393`), which reaches `_removeChild`
through `removeRenderObjectChild` (`:301`); `keptAlive` is
`keepAlive && !isVisible` (`:508`) and so false, taking the branch that drains
`_keepAliveBucket` (`:1723`) BEFORE the assert that no bucketed child has
`keepAlive` false (`:1348`).

The inverse is the trap: clearing `keepAlive` on a vicinity the pass DID
obtain can trip `:1348`, because with `_needsDelegateRebuild` set
`buildOrObtainChildFor` takes the rebuild branch (`:1489`) and never drains
the bucket (only the else branch at `:1495` does), leaving the child both
bucketed and active.

## `buildOrObtainChildFor` is not idempotent within a pass

For an already-built vicinity it routes to `_reuseChild`, which does
`_vicinityToChild.remove(vicinity)` and asserts the element was still there
(`:373` to `:378`). Serve repeats from `getChildFor` (`:901`) instead.

## An InheritedWidget scope must be non-generic to be findable

The inherited map is keyed on `widget.runtimeType` at insertion
(`widgets/framework.dart:6263`) and the lookup asks for exactly `T`
(`widgets/framework.dart:5083`), returning null silently otherwise (`:5088`).
So `Scope<String>` in the map is unreachable from a non-generic handle asking
for `Scope<dynamic>`. `tree_drag_handle.dart:68` states the house resolution:
pass a method TEAR-OFF closing over the typed key, so no key crosses the
boundary and the scope stays non-generic.

## `detach` does NOT clear `_keepAliveBucket`, so retention maps outlive it

`attach` and `detach` walk `_children.values` and then `_keepAliveBucket.values`
attaching/detaching each child (`widgets/two_dimensional_viewport.dart:912` and
`:926`); neither clears the bucket, and neither touches
`parentData.keepAlive`. A `GlobalKey` move is a detach followed by a reattach,
so any subclass-side map that mirrors the keep-alive flags (an
"exiting vicinity -> id" retention map, say) must NOT be dropped at `detach`:
that would leave live `keepAlive` flags with no entry to release them, and
`_cacheKeepAlives` re-buckets and `_reuseChild`s them forever (`:1365`).

Tear such a map down at `dispose` instead. `RenderTwoDimensionalViewport`
already overrides it (`:1811`), `RenderObject.dispose` is `@mustCallSuper`
(`rendering/object.dart:2065`) and documented "The object is no longer usable
after calling dispose" (`:2063`). Keep the controller subscription and any
port registration on `attach`/`detach`, which is where the base class puts its
own listeners; the two events have different lifetimes and belong in different
rows of a teardown table.

## The delegate has a lifetime, and both obvious answers cost something

`TwoDimensionalChildBuilderDelegate.builder` is FINAL
(`widgets/scroll_delegate.dart:1020`), so a widget rebuilt with a new builder
closure keeps rendering through the OLD one if the `State` caches the delegate
forever. And `TwoDimensionalChildDelegate extends ChangeNotifier`
(`widgets/scroll_delegate.dart:946`), so an unreplaced one is never disposed.

Constructing a fresh delegate per `build` is the other trap: the render
object's `delegate` setter early-returns only on IDENTITY
(`widgets/two_dimensional_viewport.dart:670`) and `shouldRebuild` returns
`true` unconditionally (`widgets/scroll_delegate.dart:1131`), so a fresh
instance runs `_handleDelegateNotification`
(`widgets/two_dimensional_viewport.dart:682`, body at `:866`), which is
`markNeedsLayout(withDelegateRebuild: true)` and rebuilds EVERY obtained child
(`:1489`) on every parent rebuild.

Correct shape: cache it, rebuild it only when one of its constructor inputs is
not `identical` to the old, dispose the old one in the same call. Disposing
before the render object drops its listener is safe: `removeListener`
"returns immediately if [dispose] has been called"
(`foundation/change_notifier.dart:330`).
