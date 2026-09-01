# plan-architect memory index

One line per topic. Detail lives in the sibling file named on each line.

- Citation ledger mechanics: path resolution rules, why test-file line numbers never resolve, `--record-new` versus `--update`, the order for amending a cited `.md` input document, and `--repoint`'s CRLF rewrite. See `citation-ledger.md`.
- `RenderTwoDimensionalViewport` facts: no in-layout `markNeedsLayout`, keep-alive release via the drain path, non-idempotent `buildOrObtainChildFor`, non-generic inherited scopes. See `two-dimensional-viewport.md`.
- Dense-id (ECS) lifecycle: the registry's three obligations cover no collaborator arrays, clearing is two call sites (recycled allocation and release), and re-adding a key mid-exit needs an explicit decision. See `ecs-nid-lifecycle.md`.
- Deferred work behind a dirty set: one set per flush, why sharing a dirty set silently ends the other consumer's work, the two flush arms, and the `finally` exit. See `deferred-flush-sets.md`.
- Animation-family zero rule: the three-way split, why "it inherits the root so the root's purge covers it" is false, held offsets versus in-flight motion, and the tick-time infinite-delta guard. See `animation-family-zero-rule.md`.
- Settle-tick latch: payload-free animation channels carry only LEVEL reads, every level is idle by the settle tick, so a layout-driving source needs prior-tick mirrors. See `settle-tick-latch.md`.
- Keep-alive retention maps: one clear site (`dispose`), why `detach` and a controller swap must not clear, the bounded stale-entry residue, and the totality the release predicate needs. See `retention-map-clear-sites.md`.
- Drag sessions driven by a recognizer on a virtualized child's `State`: the render-object pin, the deferred `deactivate` backstop, why neither substitutes for the other, and the tear-down-then-report commit order. See `drag-session-lifecycle.md`.
- Unexported-engine install routes: a caller across a library boundary needs a named controller forwarder, the defect recurs once per boundary, and the tree's precedent on both. See `unexported-engine-routes.md`.
- Counts and absolutes in a long plan: caller counts and where-it-runs absolutes go stale, named-role counts do not, and the fix is a bare cross-reference. See `plan-count-staleness.md`.
- Stated falsifications that leave the assertion green: the five recurring causes (defeater excludes the whole fixture, one-group fixture, two tolerance sites masking each other, a redundant guard its partner masks, a script that is a no-op under the plan's own diff rule) and what to write instead. See `falsification-that-does-not-falsify.md`.
- Inverse pairs over floating point (`offsetOf`/`trackAt`, prefix sum/descent): why the two expressions disagree by an ulp at boundaries, the postcondition form that fixes it, and the three reasons dyadic fixtures and midpoint oracles stay green. See `inverse-pair-float-maps.md`.
- Indices whose bucket key is derived from the record's own mutable geometry: the deregister-before-write ordering contract, where its one normative site goes, the three exceptions, and why an admission-time assert is the wrong assert. See `index-keys-derived-from-mutable-state.md`.
- Circular invariants ("when the lane axis is content-sized, laneExtent is required"): why fixing the wording deletes the rule, de-circularizing onto the property, choosing the assert site by what it can see, and the one-case test-accounting cost. See `circular-invariants.md`.
