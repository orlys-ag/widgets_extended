# plan-critic memory index

One line per topic. Detail lives in the sibling file named on the line.

- consistency lens: plans are gitignored (no diff), revision logs hold stale counts, cheap mechanical checks -> `consistency-lens.md`
- animation-channel-settle.md: settle ticks vanish on the level-only VoidCallback animation channel; the house fix is a prior-tick latch (sliver_tree_element.dart:90).
- perf lens: house yardstick for per-item hot-path reads (id-keyed, scalar, one-bool idle guard) and derived-cache maintenance sites -> `perf-lens.md`
- surface lens: underscore files can be exported (check requirements 9.7 table), cross-library install routes are the recurring hole -> `surface-lens.md`
- tests lens: count-greps reproduce; promoted trial counters change name AND read protocol; semantics/barrel routes; regrep `AC[0-9]+` after a renumber -> `tests-lens.md`
- mechanism lens: in-layout notify is not coalesced, drag-session unmount backstops, commit-report ordering -> `mechanism-lens.md`
- interaction lens: copied config fields/teardown rows with no consumer; resolution-surface type vs the features riding it; frozen bands crossed with cells only -> `interaction-lens.md`
- correctness lens: greedy lane assignment reuses lanes inside a cluster (kills `lane` injectivity); new double accessor beside a surviving int one -> `correctness-lens.md`
