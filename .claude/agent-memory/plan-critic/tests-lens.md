# tests lens, widgets_extended

## The count-greps in these plans reproduce, but re-run them

Every command a plan quotes for a test count has matched so far: 256 test
files all importing `flutter_test`, 52 distinct `debug*` identifiers in
`lib/`, 19 `@visibleForTesting`, 10 test files importing
`package:widgets_extended/sliver_tree/_*.dart`. Run them anyway; they are one
shell line each and they are the cheapest finding to close.

## Debug seams promoted from a trial probe change name and meaning

`test/board/correction_trial_test.dart` holds `debugLastPassCount` and
`debugCorrectionCount`. A plan that says "both already exist in the trial
probe" under different names is close enough, but the SEMANTICS matter:
`debugLastPassCount` is the pass count of the LAST `layoutChildSequence`
(correction_trial_test.dart:189-193), so a single post-`pumpAndSettle` read
pinned with `==` is brittle in both directions, and it does not see a
mid-script climb toward the cap at all. The trial itself takes a MAX across a
scripted sweep and asserts `>= 2` and `< kMaxPasses`
(correction_trial_test.dart:538-561). Check any promoted counter's read
protocol against the probe's, not just its name.

## House routes a plan is likely to name wrongly

- Semantics actions: three test files drive them through
  `tester.binding.pipelineOwner.semanticsOwner!.performAction(...)` with a
  `CustomSemanticsAction` identifier. No test in the repo uses
  `tester.semantics`, and the package's move actions are custom, not built-in.
- Export partitions: there is no barrel/export test in the repo. A Dart test
  cannot assert that a symbol is NOT nameable through the barrel, because the
  reference would not compile; the only writable form reads the barrel's
  `show` clauses as text.

## After an AC list is renumbered, grep every `AC[0-9]+`

These plans repoint the references inside their own "Round N Revision"
sections and miss the ones in the Landing Order and the AC table, which then
name a criterion that has moved. `grep -noE "AC[0-9]+"` and check each hit
against the row it claims.

## "paint-only tick" assertions on the board: a GROWING offset relayouts

`debugPerformLayoutCount` flat across a mid-animation pump is only writable
when the composed offset SHRINKS. `_admittedOffsetBound` is re-recorded to the
current bound at every layout (render_board_viewport.dart:459) and the tick
router relayouts whenever the bound exceeds it
(render_board_viewport.dart:402-409). An itemSlide decays toward zero, so
animation_paint_only_test.dart:91 can pin flat; a makeRoom offset RAMPS UP
(_make_room_engine.dart:100-121), so every mid-gap tick with a displaced
neighbour lays out. A plan claiming "make-room ticks stay paint-only" is only
true for a hover that displaces nothing (no held offset at all, so
`hasActiveOffsets` is false). Check which direction the offset moves before
accepting any flat-count assertion.

## "no notification after dispose" is an inert assertion

`ChangeNotifier.dispose()` sets `_listeners = _emptyListeners; _count = 0`
(change_notifier.dart:391-392, documented at :372-373), and `notifyListeners()`
asserts not-disposed (change_notifier.dart:414). So for the module's notifiers
(`BoardDragController extends ChangeNotifier`, board_drag_controller.dart:69), a
plan that asserts "a stale callback after dispose fires no notifyListeners"
cannot be written to fail: a listener registered before dispose is dropped, one
registered after throws in `addListener`. The only writable observable of a
missed guard is the THROW from the disposed notifier during the next pump, or a
side effect on a still-live object (the board controller's state). Rewrite such
an assertion as "the pump after dispose does not throw", and check that the
script actually leaves a callback pending.

## `hasActiveTrackResize` is engine-wide, not per track

`controller.anim.hasActiveTrackResize` forwards `trackResize.hasActive`
(_board_animation_coordinator.dart:188-190), one flag over both axes and every
track. So "no resize is in flight" asserted after any MUTATION is only writable
when NO track's extent moved: on a content-sized lane axis an item leaving its
row drops that row's term from `lane*laneExtent + lanePadding` to the cells-only
measurement (one lane 22 vs empty 20 in the usual board fixture), which the
ordinary arm animates (render_board_viewport.dart:919-930; `minTrackExtent`
defaults to 1.0, _board_axis.dart:422, so nothing clamps a 2px shrink). Check
the SOURCE track of any commit before accepting such an assertion; the writable
substitute is per-track stillness through `rectOfCell(r, c)!.height` read on two
consecutive frames.

## Equal family durations make a mid-value pin ambiguous

A term recorded per tick on a 300ms makeRoom clock and a trackResize install of
the same span over 300ms read IDENTICALLY at every sample. Any board case that
asserts a mid-animation extent must set makeRoom and trackResize to different
durations (the house fix is 200ms vs 400ms) or add `hasActiveTrackResize` false
on the sampled frame, or it passes on the implementation that skipped the latch.

## Board drag tests: the pointer must clear the 48px autoscroll zone on BOTH axes

`BoardAutoScroller.evaluate` (board_drag_controller.dart:561-577) starts its ticker
whenever either axis's velocity is non-zero, and `_axisVelocity` (:581-592) fires on
`position < edgeZone` for the VERTICAL axis too. The ticker keeps running even when
`maxScrollExtent` is 0, because the clamped `jumpTo` changes no pixels and only a null
position stops it, so `pumpAndSettle` never settles. In the usual board fixture rows
are 20 to 58 tall, so rows 0 and 1 sit entirely inside the top 48px, and a track-snap
move targeting row 0 needs the POINTER there
(_board_drop_resolver.dart:142-148). The escape is `autoScrollEdgeZone: 0.0` on the
drag config (board_config.dart:79 and :100). Plans keep guarding only the x axis.

## A bare `tester.pump()` does not advance the fake clock

flutter_test `binding.dart:2248-2261`: `if (duration != null) { _currentFakeAsync!.elapse(duration); }`.
So a "still X one frame later" stillness assertion written as `await tester.pump()`
cannot fail against an in-flight animation; it needs an explicit frame duration. The
board suite's idiom for "one frame" is the bare pump, so the trap is live.

## A resize session needs config permission before its assertions mean anything

`startDrag(edge:)` returns false unless `config.onItemResized != null`
(board_drag_controller.dart:196) and `_edgeAccepted(config.resizeEdges, edge)`
(:199); `_kindFor(BoardResizeEdges.both)` returns null. A row that "starts a resize
session" on a fixture config carrying only `onItemMoved` gets false, no `previewGap`
runs, and every assertion after it passes vacuously on the fix and on the scratch.
