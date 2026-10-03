# Stated falsifications that leave the assertion green

A plan's test list carries, per case, "red against IMPLEMENTATION X". That
sentence is a claim about a counterfactual and it is the least-checked kind of
claim in a plan, because reading it never exercises it. When the first
execution runs the mutations, a predictable fraction of them turn out not to
redden anything. `doc/agents/testing-patterns.md` makes that a defect on its
own, even when the case as a whole discriminates.

Five recurring causes, each found in one plan by running the mutations:

1. **The named defeater excludes the fixture's other members too.** "A
   criterion written on the primary axis admits F, so F takes lane 1 of 2."
   False: under that criterion the two items F would have collided with are
   also excluded, so F ends up alone and resolves to the same value a correct
   implementation gives. Test: apply the defeater to EVERY fixture member, not
   only to the one the assertion names.
2. **The fixture has only one group, so a per-group rule and a per-whole rule
   agree.** "A greedy first-fit that never closes clusters gives a chain a
   count equal to the chain's length." False: first-fit reuses a freed lane,
   so a lone chain reports the same number either way. Closing decides the
   UNIT the aggregate is taken over, which needs a SECOND group in the same
   bucket to be visible at all. Test: whenever a rule is "per cluster" rather
   than "per container", the fixture needs two clusters.
3. **Two tolerance sites mask each other.** A touch is read as non-overlapping
   by a cluster-close test AND by a lane-reuse test. Making either strict alone
   leaves the assertion green by the other route; only both at once redden it.
   The assertion pins them JOINTLY. If a plan wants each pinned alone it needs
   a fixture where only one of the two is reachable, which usually means a
   different case.
4. **A redundant guard is unobservable because its partner runs first.** A
   flush placed on both the exit of a bulk path (in a `finally`) and the entry
   of every query: no query can tell whether the exit arm ran, because the
   entry arm sorts anyway. The exit arm is a COST rule, not a correctness one.
   The honest resolution is to record it UNPINNED with what it actually buys,
   not to add a seam whose only consumer is its own assertion.
5. **The script is a no-op under the plan's own diff rule.** "Then `setItems`
   the survivors and assert the count drops." A diff that applies a span only
   when it differs re-registers nothing, so nothing recomputes; and a
   deregister-all-then-re-add reading empties the container, which resets the
   aggregate by a DIFFERENT rule, so the assertion passes against the
   implementation it claims to reject. Test: trace the script through the
   plan's own semantics for every call it names.

## What to write instead

- Name the defeater as an IMPLEMENTATION, then walk the whole fixture through
  it and say what each assertion reads under it. Half of these are caught by
  that walk alone.
- When a defeater turns out to redden a DIFFERENT assertion than the one it
  was filed under, say so explicitly and keep both mappings. Two defeaters can
  share an outcome on part of a fixture and differ on the rest.
- Prefer a per-defeater MAP at the end of a multi-assertion case ("defeater A
  reddens assertion 1 alone") over a prose sentence claiming independence.
- A fixture that appears in a component section as an ILLUSTRATION is not a
  test. Mark it, and name the assertion that actually pins the rule, or record
  the rule as unpinned.

## Sixth cause, found by running a landed step: the HARNESS zeroes the subject

A plan that prescribes one configuration constant for every test above some
layer ("controller tests use `Style.disabled`") has, by that sentence, made
every rule that resolves THROUGH the zeroed value unfalsifiable in those tests.
The board's case: a BINDING unset-to-root fallback table
(`itemEnterExit` inherits `trackResize`, not `itemSlide`) had no assertion
through every audit round up to the one that ran the code, and none of the
later steps would have grown one, because
`disabled` zeroes BOTH roots. A fallback rooted at the wrong family resolves to
zero either way, so every downstream case passes on wrong code.

General form: **a rule whose only witness is a non-default, non-zero value
cannot be pinned by any case running under the disabling harness.** It needs
its own case at the value-type layer, BELOW where the harness applies.

Two consequences for a plan:

- When the plan declares a harness constant, check what that constant FLATTENS,
  and give each flattened rule a case outside the harness. The check is
  mechanical: grep the test tree for the resolving members
  (`effective*`, `specFor`, `debugValidate`, the named constructors); zero hits
  on a member the plan calls BINDING is the finding.
- The neighbouring inheritance case does not cover it. Pinning one arm of a
  fallback table ("an unset `dropSettle` tracks `itemSlide`") touches neither
  root of another arm, so "inheritance is live" being green says nothing about
  whether the arms are rooted correctly.

A case that pins a fallback ROOT needs BOTH restyle probes: restyle the WRONG
root and assert nothing moved, restyle the RIGHT root and assert it carried
through. The two defeaters redden disjoint assertions, so a per-defeater map is
mandatory here: `_x ?? wrongRoot` reddens everything except the read-back-null,
while a resolve-by-copy implementation reddens ONLY the read-back-null and the
right-root probe.
