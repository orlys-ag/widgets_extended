# Reddening 100+ assertions in one file

Done for board plan step 4 (`test/board/board_controller_test.dart`, 13 cases,
109 `expect` lines, 109 mutations). The mechanics scale; the design decisions
are what cost the time.

## Harness that worked

`mutate.py` in the scratchpad holding `M[id] = [(file, old, new), ...]`,
always applied against a `pristine/` copy, plus `restore`, plus `list`.
Then a `.sh` driver that maps an id prefix to a case name and runs
`flutter test <file> --plain-name "<case>"`.

- DRY-RUN every id first (`for id in $(list); do apply "$id"; done`), aborting
  on a pattern count that is not exactly 1. Catches typos and non-unique
  patterns before an hour of test runs.
- `python ... list` on Windows emits `\r`. Pipe through `tr -d '\r'` or the
  shell loop compares `m1_137\r` and finds nothing.
- Classifier trap: `grep -qE "Error:"` to detect a compile failure ALSO matches
  `threw RangeError:` and `threw _AssertionError:` in a genuine test failure.
  Four mutations were mis-reported as COMPILE-ERROR when they were red.
  Match `Failed to load|Compilation failed` instead.
- Extract the reddened line from `board_controller_test.dart:NNN` stack frames
  and take the set. The enclosing `runBatch(() {` line appears alongside the
  expect line, so a two-element set is normal, not a double failure.
- Cross-check at the end: `comm -23 all_expect_lines reddened_lines` must be
  empty. That is the only thing that proves no assertion was skipped.
- EDITING THE TEST FILE INVALIDATES THE LINE NUMBERS of every mutation below
  the edit. Re-run the affected subset rather than hand-shifting.

## Five reasons a mutation fails to isolate, all hit in one file

1. **A second source already supplies what the assertion was meant to pin.**
   `_notifyStructural`'s seed set looked pinned by "addItem names the key",
   but the lane-change DRAIN independently produced the same key, so zeroing
   the seed stayed green. Pin the seed by removing the DRAIN instead.
2. **A later branch repairs the mutation.** Setting `_lanes.laneAxis = null`
   inside the primary-swap branch was undone three lines later by the
   lane-swap branch, which re-derived it. Mutate the DERIVATION, not a write
   that a reconciliation step will overwrite.
3. **The fixture never reaches the state the mutation targets.** "Resolve only
   the first dirty bucket" was inert because every mutator's notification
   already flushes, so exactly one bucket is ever dirty. The isolating
   mutation was "dirty the WRONG bucket".
4. **A read filters the corruption out.** `BoardController.itemsIn` maps ids
   through `keyOfId` and skips a null, so a retire that skipped
   `SpanIndex.deregister` is INVISIBLE to every caller-facing read; only the
   render-facing `itemIdsInRectIncludingExiting`, which never maps through
   keys, can see it. Two assertions had to be rewritten onto that read.
5. **A blunt mutation kills an earlier assertion's fixture.** `_store.clear()`
   at the top of `setItems` reddened the addItem-duplicate assertion three
   lines earlier instead of the intended one. Retire ONE key, not all.

## Assertion ORDER inside a case is a design variable

`expect` throws, so only the first failure reports. When every mutation of one
mechanism reddens the same neighbour first, reorder the case. In the lane-only
case, every lane-resolve mutation killed `contains(relaidKey)` before it could
reach the lane VALUES, because a resolve that does not run also reports
nobody. Putting the model assertions (span, lane, laneCount) BEFORE the
notification assertions gave each of the six its own falsifier.

## Mutations that are the plan's own named defect are the best ones

Two here were verbatim from the plan: incrementing the resolve counter once
per CALL rather than per bucket (which is why the counter lives on the
resolver), and draining the lane accumulator BEFORE the flush rather than
after. Both isolated cleanly and both document themselves in the report.
