# A retention map and its flags have ONE clear site

Pattern that recurs whenever a render object holds explicit keep-alive
retention in a side map (`vicinity -> id`) while the framework holds the
flag on `parentData`.

## The rule

The map and the flags have the SAME lifetime and are torn down at the SAME
event, which is `dispose`. Every other event that "feels like" a reset is
not one:

- `detach`: the framework's detach only iterates its keep-alive bucket, so a
  detach-reattach (what a `GlobalKey` move performs) leaves children bucketed
  with the flag still true.
- A collaborator/controller SWAP: changes nothing about the bucket or the
  flags either.

Dropping the map at either leaves a child with a TRUE flag and NO entry. The
release sweep treats that as "outside the sweep" and never releases it, while
the framework re-buckets and reuses it on every later layout. That is a leak
for the life of the render object, not a one-frame residue.

`RenderTwoDimensionalViewport` specifics, verified: the bucket is written by
exactly four members (`_cacheKeepAlives`, `buildOrObtainChildFor`'s drain,
`_moveChild`, `_removeChild`); `attach` and `detach` only iterate. No property
setter is among them.

## What to write instead of a clear

State the RESIDUE and what bounds it. Stale entries name ids from the old
owner; the first layout after the swap releases them through the ordinary
"recorded id is no longer reported exiting" case, which the setter's own
`markNeedsLayout()` guarantees.

## The dependency that comes with it

That release feeds a per-id predicate an id the OLD owner allocated, so the
predicate must be TOTAL over `int`: false for an id with no record, including
one past a dense array's length. Declare it on the interface. Otherwise the
first layout after the swap throws.

## Plan-level symptom to look for

Three sites naming the reset differently: a state-table "Reset at" cell, the
invariant that owns the sweep, and the lifecycle invariant's setter script.
One normative site, two bare cross-references. Also check the landing step:
a swap step that asserts MEASUREMENTS catches none of this, so the case has
to assert CHILD COUNTS.
