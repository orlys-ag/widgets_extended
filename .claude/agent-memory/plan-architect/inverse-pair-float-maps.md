# Inverse pairs over floating point (offset <-> index)

Any plan that declares a forward map and its inverse as SEPARATE members
(`offsetOf(track)` and `trackAt(offset)`; a prefix sum and a lower-bound
descent; a paint transform and its un-transform) has a defect class that
reads correct and fails on contact. Found in the board plan's L0 axis at
Round 20, after four steps of green.

## The mechanism

The two members are written as different EXPRESSIONS over the same inputs.
`track * extent` and `offset ~/ extent` are inverses in the reals and not in
IEEE doubles: when `extent` is not exactly representable, the quotient lands
one ulp below the integer and truncates, so `trackAt(offsetOf(t))` returns
`t - 1` at a LEADING EDGE. The same thing happens with a Fenwick tree whose
`prefixSum` accumulates in one association order and whose `lowerBound`
descent subtracts in another; floating-point addition is not associative, so
both are correct sums that disagree at the boundary.

A search that reads the very array the forward map indexes is immune, which
is why "two of the four modes satisfy it by construction" is the right way to
split the statement.

## What to write in the plan

State it as a POSTCONDITION, at one site, so it can be checked without
reading either implementation:

    trackAt(offset) returns the result for which
    offsetOf(result) <= offset < offsetOf(result + 1),
    both bounds evaluated through offsetOf ITSELF, not re-derived.

Then the correction: clamp the cheap candidate, step up while
`offsetOf(c + 1) <= offset`, step down while `offsetOf(c) > offset`. Write
both as LOOPS unless a one-step bound is proved, and say which half is
unproved. One shared module-private helper, both callers passing their own
approximation, keeps the rule to a single site in code as well as in prose.

Cost note worth pre-computing: on a log-time forward map the correction adds
up to two forward evaluations per call, so check the existing op-count budget
test BEFORE claiming the bound is unchanged.

## Why the tests were green, and what to require instead

Three independent blind spots, all of which have to be named:

- **Dyadic fixtures.** Every extent in the case was an integer (40, 12, 80),
  so every forward value was exact and the round trip could not fail. Require
  at least one NON-DYADIC value per mode.
- **A probe that is not the forward map.** The case accumulated its own
  running sum and probed that. On integers it coincides with the forward map;
  on anything else it is a third number neither side returns. Require the
  probe to be `inverse(forward(i))`.
- **Midpoint-probing oracles.** A fuzz that compares prefixes with a
  tolerance and probes the inverse at track MIDPOINTS cannot see a
  one-ulp boundary disagreement, by construction: no tolerance on a value can
  see an INDEX come back one low. Record the gap in the oracle's row; do not
  "fix" the oracle, whose tolerance is load-bearing because it sums in a
  different order.

Also record which of the new fixture entries actually DISCRIMINATE. Entries
for the immune modes are coverage against a future reimplementation, not a
fence; and a fixture can be inert by SIZE (a 6-track lazy axis at estimate
23.4 resolves every edge correctly pre-fix; 8 tracks fails at 6 and 7). Model
the pre-fix arithmetic and say which sizes redden, or someone shrinks the
fixture back.

## Reproduce the numbers yourself

An audit's count for this class is easy to get wrong and expensive to inherit,
because it lands in a code comment next. Round 20's finding reported 1040 of
2000 failing edges for the uniform axis; the real number is 200, and 1040 is
close to what the FENWICK descent gives on the same fixture (1010 in a model).
A 20-line Dart or Python probe settles it. Write the number you measured and
record the one you did not reproduce, with why it probably belongs elsewhere.
