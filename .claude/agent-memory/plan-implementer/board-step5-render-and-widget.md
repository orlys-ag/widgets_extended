# Landing the board's L3 render object and L4 widget (step 5)

Facts that cost real time to find, all verified this session against the
Flutter SDK at `C:/flutter_sdk/flutter`.

## A parent rebuild does NOT rebuild a TwoDimensionalViewport's children

`_TwoDimensionalViewportElement.performRebuild`
(`widgets/two_dimensional_viewport.dart:277`) is what sets
`markNeedsLayout(withDelegateRebuild: true)`, and a parent-driven update
never calls it: `RenderObjectElement.update` calls the PRIVATE
`_performRebuild` (`widgets/framework.dart:6813`), not the overridable
`performRebuild` (`widgets/framework.dart:6825`). The render object's
`delegate` setter then early-returns on equality
(`widgets/two_dimensional_viewport.dart:670`).

So `setState` in the owning `State` reaches nothing: every cell keeps the
values it was built with. The only route from a `State` that holds a cached
delegate is to REPLACE the delegate instance;
`TwoDimensionalChildBuilderDelegate.shouldRebuild` is unconditionally true
(`widgets/scroll_delegate.dart:1131`), so the setter calls
`_handleDelegateNotification`. `ChangeNotifier.notifyListeners` is
`@protected`, so calling it directly is an analyzer warning rather than an
option.

This was caught by a throwaway smoke test, not by any named case in the
plan. Write one for any "a controller value change reaches the builders"
claim; it fails silently otherwise.

## `unused_field` constrains what a STAGED landing can hold

`flutter_lints` reports "The value of the field '_x' isn't used" for a
private field that is written and never read (confirmed with a two-line
probe). A plan that assigns a field to step N and its only reader to step
N+2 therefore cannot land the field at step N. Options, in order of
preference: give it a reader that belongs to the same step (the board's
`_admittedOffsetBound` got I18's branch-3 gate, which is the half step 5
owns), make the writer read it (`unpinItem` clears `_pinnedDragKey` only
when it matches, which is both correct and a read), or leave the field out
and record the deferral as a finding.

`unnecessary_overrides` bites the same way: an override whose only assigned
work lands later cannot be a bare `super.x()` call.

## The controller's dispose assert doubles as a detach check

`BoardController.dispose` asserts the three listener lists are empty, and a
mounted `Board` holds three. `addTearDown(controller.dispose)` therefore
PROVES the render object unsubscribed on unmount for every passing widget
test, because `_runTestBody` unmounts the tree with `runApp(Container(...))`
before tear-downs run (`flutter_test/src/binding.dart:1959`).

On a FAILING test that unmount is skipped ("we only try to clean up ... if
we didn't already fail"), so the dispose assert fires as a SECOND error
under the real one. Do not read it as the failure; the real `Expected:`
block is above it in the log.

## Mutation harness on Windows, encoding fix

The cp1252 decode crash noted in the sibling topic is avoidable without
leaving Python: pass `encoding="utf-8", errors="replace"` to
`subprocess.run`, and sanitize with `re.sub(r"[^\x20-\x7e]", "?", line)`
before printing, since `print` itself re-encodes to cp1252. Restore the
pristine copy in the same call that runs the test, before parsing output,
or an exception in the parser leaves the tree mutated.

## `dart format` rewrites the KEPT TRIAL PROBE

`dart format test/board` reformats `correction_trial_test.dart`, which is
committed evidence on the trial branch. Format only the files you wrote, or
`git checkout -- test/board/correction_trial_test.dart` afterwards and
confirm with `git status --porcelain` on that path.

## Reaching the render object from a widget test

`find.byType(Board<K, V>)` needs the exact generic arguments and returns the
scrollable's render object anyway. Use
`tester.allRenderObjects.whereType<RenderBoardViewport<String>>().single`.
