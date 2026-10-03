# The settle-tick latch (payload-free animation channels)

## The pattern

`addAnimationListener(VoidCallback l)` carries NO family and NO payload
(`tree_controller.dart`). A listener's only discriminators are LEVEL reads
on the reader interface (`hasActiveAnimations`, `hasActiveSlides`, ...). Every
animation source in this repo CLEARS its record before, or in the same frame
as, the notification that announces the settle. So on the settle tick every
level already reads idle, and a listener that branches only on levels routes
the settle tick to NO branch.

Consequence: the frame that should consume the FINAL animated value never lays
out. The row/item/track is stranded at its last pre-settle value until some
unrelated event dirties layout. This is invisible in most tests, because a test
that pumps anything afterwards supplies that unrelated dirtying.

## The fix, and where the tree states it

Prior-tick MIRRORS plus a disjunct, all in `sliver_tree_element.dart`:

- `_priorTickHadAnimations` (`sliver_tree_element.dart`), doc comment at
  `sliver_tree_element.dart` states the defect verbatim: "the settle tick
  (where the controller has already cleared animation state before notifying)
  still triggers markNeedsLayout. Without this, completed extent animations
  would never relayout and the render would remain at the partial animated
  value".
- `_priorTickHadSlides` (`sliver_tree_element.dart`) and
  `_priorTickHadFlipSlides` (`sliver_tree_element.dart`).
- The chain is `_onAnimationTick` (`sliver_tree_element.dart`): the
  layout-driving disjunct at `sliver_tree_element.dart`, the settle
  transition at `sliver_tree_element.dart` (an OR of two disjuncts,
  deliberately ONE branch), then the paint-only arm with its
  `composedSlideAbsDeltaBound > admittedSlideBound` gate. All mirrors are
  written UNCONDITIONALLY at the bottom (`sliver_tree_element.dart`), so a
  tick that matched no branch still advances them.

## Why coalescing does not save you

Even a source that notifies BEFORE clearing does not help a COALESCED channel:
coalescing defers the dispatch past the tick that retired the record. The
tree's carve-out (`_animation_coordinator.dart`, uncoalesced
`notifyListenersNow`) exists for the slide and preview engines' same-frame
zero-delta paint ordering, NOT for the latch. Two different problems; do not
let one be offered as the fix for the other.

## Writing this into a plan

Any plan that installs a layout-driving animation and routes it through a
payload-free listener owes:

1. A named routing rule (a branch chain), not a per-source sentence like
   "X ticks always call markNeedsLayout". That phrasing is a LEVEL read in
   disguise and is what makes the derivation circular.
2. One mirror per level the chain branches on, with the unconditional write.
3. A falsifiable case: the animation settling with NOTHING else dirtying the
   frame, asserting a layout counter beside the value. Asserting the value
   alone does not discriminate.
4. A PAIR note: if a new carve-out level is added later, the chain gains a
   mirror with it.

## Sibling gotcha

A settle handler that fires a structural notification (an EXIT) reaches layout
through the structural channel and is covered twice. An ENTER-style settle that
fires NO notification is covered by nothing. Enumerate which of the two each
branch is.

## The coalescing is PHASE-CONDITIONAL, so "coalesced" is not a safety net

`AnimationCoordinator.notifyListeners` defers to a microtask only when
`SchedulerBinding.instance.schedulerPhase == SchedulerPhase.transientCallbacks`
(`_animation_coordinator.dart`, the member at `:304`). Outside that phase
"there is nothing to coalesce" (`:303`) and it dispatches SYNCHRONOUSLY
(`:318`).

Consequence for any animation installed from INSIDE layout (a content-sized
track resize is the standing example): build/layout/paint runs in
`persistentCallbacks` (`scheduler/binding.dart`, documented as "the
build/layout/paint pipeline" at `scheduler/binding.dart`), so an
install-time notify reaches the render object's own listener in the same
statement, and a layout-driving branch there calls `markNeedsLayout` and hits
"A RenderObject must not re-dirty itself while still being laid out"
(`rendering/object.dart`).

So an in-layout install's forbidden list is THREE items, not two:
`markNeedsLayout`, a structural notification, AND the animation-channel
notify. State where the first legal dispatch happens instead: the first TICK,
which runs in `transientCallbacks`.
