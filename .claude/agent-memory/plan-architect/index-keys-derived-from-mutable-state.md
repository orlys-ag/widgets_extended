# Indices whose bucket key is DERIVED from the record they index

Pattern: a store holds per-id mutable geometry, and one or more indices bucket
ids by a function of that geometry. Neither index stores the key it filed an id
under; both recompute it from the store on de-registration.

That creates an unstated ordering contract, and it is the single most likely
thing to be missing from a plan that describes both the store and the indices
correctly. **A mutator must de-register from EVERY index BEFORE writing the new
geometry, and re-register after.** Writing first de-registers from the buckets
the record is about to occupy, which strands an entry in every bucket the old
geometry touched and the new one does not.

## What the plan owes

- **One normative site, at the STORE**, because the store's section is the one
  that enumerates the mutators. The index sections cross-reference it. Putting
  it in one index section leaves the other index's readers without it.
- **The step order written out**, not implied: de-register from all indices,
  write the arrays, re-register in all indices.
- **The exceptions, enumerated.** An ADD has no de-register (no previous
  geometry). A diff-based bulk setter runs all three only for records whose
  geometry DIFFERS. A retire-at-settle has a de-register with no paired write,
  and it is correct for the same reason: the geometry is still in the store.
- **Which debug assert catches WHICH violation shape, and which shape nothing
  catches.** An index whose entry is single per record can assert that the
  removal found something. An index that files a record in a RANGE of buckets
  usually cannot afford the same assert on the hot single-mutation path, so
  state that as a residual hazard rather than implying symmetry.
- **A guard that early-returns before the assert catches nothing.** If
  `deregisterItem` starts with `if (!isLaned(id)) return;`, a write that made
  the record fall outside the index skips the assert entirely. Name the later
  guard that does catch it (a resolve-time membership assert over the bucket)
  or admit the hole.

## Related shape: the assert at admission versus at resolve

"Put a debug assert where the index ADMITS a record" is ambiguous and usually
wrong. Read as re-stating the admission criterion, it is vacuous. Read as
something stronger (e.g. "the fractions on this axis are zero"), it rejects
records the criterion admits. The assert that earns its place runs at RESOLVE
time over the bucket's EXISTING members and is NON-REJECTING by construction:
it re-states membership, so it admits exactly the criterion's set and only
fires on an entry that has gone stale.
