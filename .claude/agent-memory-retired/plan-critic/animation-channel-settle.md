# Settle ticks on the single-VoidCallback animation channel

Recurring mechanism defect in plans for this repo. `addAnimationListener` is a
bare `VoidCallback` with no family and no payload, so a render/element listener
can only branch on LEVEL flags read off the controller
(`hasActiveAnimations`, `hasActiveSlides`, ...). Every layout-driving source in
this house clears its per-item record and its flags BEFORE notifying, so on the
settle tick every level flag already reads false and a level-only branch fires
nothing. The result is a lattice frozen at the last pre-settle animated value.

The tree solves it with prior-tick latches, not with levels:
`sliver_tree_element.dart:90` documents `_priorTickHadAnimations` ("so the
settle tick, where the controller has already cleared animation state before
notifying, still triggers markNeedsLayout"), and `_onAnimationTick` at
`sliver_tree_element.dart:316` branches on `active || _priorTickHadAnimations`
plus two more latches for the FLIP and composed slide transitions.

So: whenever a plan says "ticks of family X always call markNeedsLayout", ask
what the listener reads to know that, and check the settle frame specifically.
A plan that routes a layout-driving family through the COALESCED dispatch and
justifies it with "the settle is followed by a layout" is asserting the thing
that needs the latch.
