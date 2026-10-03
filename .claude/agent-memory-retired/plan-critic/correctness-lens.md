# Correctness lens: two checks that broke a proposed design here

## 1. Greedy lane assignment REUSES a lane inside one cluster

`OverlapLaneResolver`'s step 3 is "the lowest lane whose last occupant has
already ended" (board plan, `OverlapLaneResolver` section). A cluster is a
CONNECTED COMPONENT, not a clique (the close test is "starts at or after the
maximum end of the active set"), so two non-overlapping items joined by a
third get the SAME lane. The requirements scope exclusivity to MUTUALLY
overlapping items (board requirements AC6).

Consequence: any uniqueness or injectivity argument phrased as "a lane is
exclusive within its cluster" is FALSE. Test it with the three-item connector
input: A [0,1), B [2,3), C [0,5) in one track. C takes lane 0, A and B both
take lane 1. A vicinity or key derived from `lane` (or from `base + lane`)
collides for A and B.

## 2. A new fractional accessor beside a surviving int one

When a plan adds `startTrackOn`/`endTrackOn` (double) while keeping
`startOn`/`spanOn` (int), grep EVERY sort key and EVERY comparison in the new
algorithm for the int spelling. The int one still compiles and is silently
wrong, and it degenerates completely where the algorithm has already filtered
on that same int value (e.g. a per-primary-track pass whose members all share
`startOn(primary) == p` sorts and compares on a constant).
