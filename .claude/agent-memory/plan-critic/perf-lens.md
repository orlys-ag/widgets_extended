# Perf lens: the house yardstick for per-item hot-path reads

Two checks that keep paying off on plans for this repo.

## 1. Every per-item read the render layer makes has a house shape

`tree_controller.dart:1160` is the reference: `double getSlideDeltaNid(int nid)`,
documented at `tree_controller.dart:1159` as "read every paint, hit-test, and
transform call for visible rows, so saving the key-to-nid hash matters". Three
properties, and a new module's reader interface should be checked against all
three rather than against the general "use nids" rule:

- **id-keyed, not key-keyed**: no hashing on the paint path.
- **scalar-returning**: the X axis gets its OWN accessor
  (`getSlideDeltaXNid`, `tree_controller.dart:1223`) rather than one
  `Offset`-returning call, so paint allocates no value object per item per
  frame.
- **one boolean guard when idle**: `if (!_preview.hasActive) return base;`
  (`tree_controller.dart:1165`) under the comment "One boolean guard keeps the
  non-drag hot path unchanged" (`tree_controller.dart:1162`).

A plan that declares level flags (`hasActive*`) on its reader but never says the
per-item read short-circuits on them, or that returns `Offset`/a record/a value
object per item, has dropped two of the three. Watch for the plan arguing the
scalar rule in one section (id-keyed span reads) and breaking it in the next
(an `Offset`-returning animated read).

Same yardstick applies to render-object side tables: a
`Map<SomeVicinity, int>` probed once per painted child hashes a key on the paint
path; a `List<int>` parallel to the paint-order list, built in the same sweep,
carries the same information.

## 2. A derived per-bucket cache needs its maintenance sites enumerated

Any plan that narrows a scan bound with a cached aggregate (a per-bucket
`max...Span`, a watermark, a cumulative prefix) has to name EVERY mutator that
maintains it, not just the one it was introduced for. The usual defect is that
the recompute is stated only inside a bulk/flush path, so the single-mutation
path leaves the aggregate stale. Both directions are bugs and only one is
testable by the oracle fuzz: too LOW misses items (the fuzz's set comparison
catches it), too HIGH silently degrades the bound to a full scan forever (sets
stay identical, so only a probe-count seam on a fixture that SHRINKS the
aggregate can see it). Check that the pinning fixture actually removes or
shrinks the extreme element.
