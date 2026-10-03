# Dense-id (ECS) lifecycle facts for this repo

Stable patterns for any plan that introduces a `NodeIdRegistry`-style dense
integer id store with a LIFO free list. All verified from source.

## The registry states three obligations and owns none of the arrays

`_node_id_registry.dart` documents what a dense-array owner must do:
grow on `allocate(grew: true)` (`:14`), reset a recycled slot inside the
allocation path (`:16`), zero on `release` returning non-null (`:20`). The
closing line is the trap: "The registry does not own any per-nid arrays
itself" (`:22`). A plan that says "the store takes the registry's three
obligations" has therefore said nothing about collaborators that also key
state by the same id, which in this repo means every animation source.

## Clearing is TWO call sites, not one

`TreeController` implements both halves and a plan should cite both:

- allocation of a RECYCLED id: `_adoptKey` calls `_order.clearForNid` and
  `_anim.clearForNid` (`tree_controller.dart`) under the comment
  "Nids are recycled, so a freshly allocated one must have every per-nid
  array slot reset" (`tree_controller.dart`).
- release: `_releaseNid` calls the same pair
  (`tree_controller.dart`) under "Clears every per-nid dense array
  slot so a future [_adoptKey] that recycles the nid sees a clean state"
  (`tree_controller.dart`).

The fan-out lives in one place: `AnimationCoordinator.clearForNid`
(`_animation_coordinator.dart`) forwards to all five sub-animators and
then clears the shared per-nid state. Its doc block carries a generation
invariant worth copying: it does NOT bump the animation generation, so the
caller must guarantee a bump lands before any generation-keyed cache is read.

## The failure mode a plan must name

A mutation that installs a paint-only animation, followed inside the same
animation duration by a removal that releases the id, followed by an
allocation that LIFO hands the id straight back. Without a clear, the new
occupant paints at the dead one's residual delta and the union flags
(`hasActiveSlides` / `hasActiveOffsets`) and the bound
(`composedSlideAbsDeltaBound` / `composedOffsetBound`) still report it.

## Related: a key can outlive its liveness

Where a "pending deletion" or "exiting" bit exists, the key stays in the
key-to-id map for the whole exit while every read excludes it. Removing and
re-adding the same key inside one exit duration is therefore an ENTER against
a still-registered key, and a plan has to decide it explicitly. Two wrong
answers: allocating a second id (the old id's settle deletes the LIVE key's
map entry), and reclaiming the exiting record in place (a second site now
clears the bit, and a partially elapsed exit needs a reverse-to-enter path).
The safe answer is to force the old incarnation through its completion
handler synchronously at mutator entry, then perform an ordinary enter.

## The settle handler's duty list must END every "kept until settle" rule

A plan that writes "KEPT until settle" for N consumers has made N promises,
and the settle site is the only place any of them can be kept. Naming only
"clears the bit, releases the id" leaves the spatial index, the derived
per-item caches (lanes, counts) and the structural notification with no
writer, so the KEPT rules never end: the id returns to the LIFO free list
while live index entries still name it, and the next allocation recycles it
into a query that answers with the new key at the dead one's coordinates.

The order is load-bearing and a plan should state it as a numbered list:

1. de-register from every spatial-index bucket the span touched, and mark
   those buckets dirty in whatever derived-value set exists;
2. clear the flag bit;
3. compute the notification's affected-key set, which flushes those dirty
   buckets and so recomputes the neighbours' derived values, while the
   retiring id is STILL resolvable to its key;
4. release the id (which is `clearForNid`'s call site 2);
5. deliver the notification.

Step 4 after step 3, always. And the notification arm differs by caller: a
settle tick fires its own, a mutator-entry gate contributes to the one the
mutator already fires, and `dispose` fires none, because the listener lists
are dropped in the same script.

## A re-add door is a FIFTH caller, not one of the zero-family gates

The synchronous zero-family gates are conditioned on the family duration
being zero. The re-add-while-exiting retire is conditioned on the KEY being
re-added, under any duration. They cannot be merged, and a requirements
document that enumerates the handler's callers before considering re-add will
say "four" where the implementation needs five. Enumerate the fifth door and
raise the enumeration change; do not quietly route it through an existing gate.

## The MIRROR direction is a SIXTH caller, and it resolves the other way

The overlap window has two directions and a plan that defines only one leaves
the flag pair undefined. Removing a key whose ENTER is still in flight sets
the exit bit over a live enter bit, both predicates answer true, and the
completion handler has no branch; the natural "clear the enter bit and stop"
reading then never clears the exit bit, which is the same stranding the
re-add case produces.

Resolve it the opposite way from re-add, and say why:

- Re-add RELEASES the id, because the spatial-index registration, the lane and
  the sizing contribution are keyed by it and only the handler's step 1 ends
  them. The fresh enter is a new incarnation and starts at 0.
- Remove-mid-enter KEEPS the id, because the item is leaving and every one of
  those registrations must survive to the settle. The record slot is still the
  same item's, so the exit RE-BASES: read the ramp first, retire the enter
  through the handler (its ENTER branch), then install the exit from the
  captured value.

The tree does both halves and is the citable precedent:
`_startStandaloneExitAnimation` captures the current animated extent "BEFORE
removing" (`_tree_controller_animation.dart`, call at `:616`) because
"capturing the current extent is what keeps a row that is already
mid-animation from jumping before it starts shrinking" (`:602`), and it scales
the rate by how far the animation got, `_computeAnimationSpeedMultiplier`
(`:622`, comment "Compute speed multiplier for proportional timing" at `:620`).
The enter side resumes symmetrically (`:364`).

Two details a plan must state or an implementer invents: the ENTER branch of
the handler has to DROP the animator record (nothing else does, since only the
exit branch reaches the id release that clears all sources), and a ramp still
at 0, reachable from one `runBatch` doing an add and a remove, takes the
synchronous retire instead of installing a zero-length record.

## The synchronous door must SET the flag the handler branches on

The completion handler branches on the flag bit (exit bit set = EXIT branch).
The zero-duration/synchronous path installs nothing, so it is the one door
that reaches the handler with NO bit set, and it silently takes the ENTER
branch: nothing de-registers, nothing is released, and the item stays in the
key-to-id map with live index entries. Under the house test harness
(`*AnimationStyle.disabled` for controller tests) that is the COMMON path, not
an edge.

Two rules that close it, and a plan should carry both:

- The synchronous retire is ONE named method that sets the bit and calls the
  handler, in that order, so the pair cannot be split by a later edit. Zero
  duration means the install and the settle happen in one statement, so both
  flag events happen in one statement and the handler sees exactly the state a
  real settle hands it.
- The handler asserts EXACTLY ONE bit set, not merely "not both". "Not both"
  cannot catch the no-bit call, because the no-bit call is the one that falls
  into the default branch.

Rejected alternative worth recording: passing the direction as an ARGUMENT to
the handler. It creates a second expression of a fact whose one normative site
is the flag word, and a caller can pass one that disagrees with the bits,
running the EXIT branch on an entering id and releasing a live id.

The remove-mid-enter door (the sixth caller above) is the one door that must
call the handler DIRECTLY rather than through the synchronous retire method,
since that method would set the exit bit over the live enter bit and trip the
exactly-one assert.

## The scaled exit and the tick's zero guard are ONE formula

An exit re-based from a partial enter runs over `from * spec.duration`, so the
tick's denominator is the RECORD's own resolved duration, not the family
spec's. State it at whichever site claims to state how progress advances, or
an implementer divides by the unscaled duration and the item crawls. The
synchronous-retire branch for a ramp at ~0 is also what keeps that product
non-zero, which leaves a zero FAMILY as the only route to a zero denominator,
which is the case the infinite-delta guard exists for.
