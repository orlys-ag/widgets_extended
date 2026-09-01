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
