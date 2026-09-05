# Widening a per-item slot into a BAND (origin plus size)

Applies whenever a plan turns "the item occupies slot k of n" into "the
item occupies slots k through k+s of n": lane spans on the board, and
any future analogue (a row occupying several sticky levels, a chip
covering several sub-tracks). Derived while planning board lane span
expansion.

## The decomposition is the pair rule, and it is asymmetric

A band is ORIGIN plus SIZE. The new count multiplies the SIZE at every
site that computes one and enters the ORIGIN at none.

Enumerate both lists before writing the plan, because they are usually
duplicated across the controller and the render object:

- The controller's settled extent rule (the FLIP capture's ruler).
- The render's geometry rule (paint's ruler, and layout's constraints).
- The prospective/preview extent rule, whose "now" and "next" sides are
  themselves a pair: one side reading the count and the other not
  yields a preview delta that is a pure artifact, HELD for a whole
  drag rather than decaying.
- Every origin site, which changes in none of the above.

The failure mode of splitting the two rulers is specific and worth
stating in the plan: the capture measures a rectangle nothing paints,
so every change of the new field installs a phantom size delta equal to
the difference between the two rules. The failure mode of leaking the
factor into an origin is that the item is displaced by `count - 1`
slots while its size is right, which reads as an assignment bug and
sends the reader to the wrong component.

## A model-side sizing term measures the BAND, not the paint

Where a content-sized axis sizes itself from its members, the term is
`origin + ramp * size`. Two decisions follow, and both need writing
down:

1. **The ramp multiplies the whole band.** Not doing so undershoots:
   a member that expanded into the top slot contributes one slot while
   painting several, and the axis passes under it whenever the member
   holding the top slot is ramping out.
2. **The term reads no in-flight animator delta on the SIZE**, even
   though it already reads the in-flight LEAD deltas. Adding it turns
   the term from a model measure into a painted-truth measure, which
   drags in every other source of an in-flight size (a preview that
   de-lanes an item, a FLIP from an unlaned rectangle) and changes
   behaviour the feature never asked about.

The consequence of (2) is a bounded transient overflow, and the honest
bound is worth deriving rather than hand-waving: with the size family
and the axis-resize family on the SAME spec, both sides are the same
interpolation between two pairs that each satisfy `band <= axis`, so
nothing overflows; they diverge only by the difference of the two eased
fractions when the specs differ.

## The invariant that keeps the settled total unchanged

`max over members of (slot + count) == slotCount` holds whenever slots
are handed out densely from 0 and every count is maximal. That single
corollary is what lets a plan promise "a settled track measures exactly
what it measures today" while every member's contribution changed. State
it as a named invariant; the sizing decision above rests on it and so
does the no-goal about totals.

## Acceptance criteria can name a reader that is blind to the change

An AC written as "the relane delta is non-zero mid-flight" assumes the
change moves the item's ORIGIN. A pure size change moves only the size,
so a lead-returning reader answers zero at every frame while the record
exists. Do not add a reader to satisfy the wording; substitute the
size-returning reader, state in the plan why the named one cannot carry
it (with the line that shows it returns the lead), and put the
substitution in Open Questions as an acknowledgement request rather
than a design decision.
