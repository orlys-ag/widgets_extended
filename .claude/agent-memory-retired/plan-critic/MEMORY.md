# plan-critic memory index

One line per topic. Detail lives in the sibling file named on the line.

- consistency lens: the revision snapshot `<plan>.r<N>` your prompt names is the diff; old revision logs hold stale counts; cheap mechanical checks -> `consistency-lens.md`
- animation-channel-settle.md: settle ticks vanish on the level-only VoidCallback animation channel; the house fix is a prior-tick latch (sliver_tree_element.dart:90).
- performance lens: house yardstick for per-item hot-path reads (id-keyed, scalar, one-bool idle guard), derived-cache maintenance sites, board tick-router already lays out on a GROWING offset bound -> `perf-lens.md`
- design lens: interfaces, contracts, citations and test seams, from three earlier lenses. Surface: underscore files can be exported (check requirements 9.7 table), cross-library install routes are the recurring hole -> `surface-lens.md`. Contracts: check_citations skips everything below the audit-log heading in old plans; board plans owe board-architecture.md, the requirements family split, and two in-code arm comments -> `contracts-lens.md`. Tests: promoted trial counters change name AND read protocol; semantics/barrel routes; drag pointers must clear the 48px autoscroll zone on BOTH axes; a bare pump advances no clock -> `tests-lens.md`
- correctness lens: greedy lane assignment reuses lanes inside a cluster (kills `lane` injectivity); new double accessor beside a surviving int one -> `correctness-lens.md`. From the earlier mechanism lens: in-layout notify is not coalesced, drag-session unmount backstops, commit-report ordering, dry-run lanes TWO buckets (source too), snap arm re-flags before it discards -> `mechanism-lens.md`
- interaction lens: copied config fields/teardown rows with no consumer; resolution-surface type vs the features riding it; frozen bands crossed with cells only -> `interaction-lens.md`
- timing lens: first tick advances 0, bare pump elapses no clock, animation channel has a zero-family hole, correction anchor reads settled geometry -> `timing-lens.md`
