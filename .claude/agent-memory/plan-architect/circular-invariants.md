# Invariants whose antecedent is their subject's own definition

Read when an invariant reads "when X is P, X must Q" and P is how X was
defined two sentences earlier.

## The shape

A plan defines a role by a property ("the LANE axis is whichever axis
carries a non-null `laneExtent`"), then states a rule conditioned on that
role ("when the LANE axis is content-sized, `laneExtent` is REQUIRED").
The rule is vacuous: the antecedent already presupposes the consequent,
so nothing can violate it and no assert can be written for it.

It reads as a real constraint, and a critic who spots the circularity
usually proposes to fix the WORDING ("read it as constructor plus both
setters"). That resolution makes the rule vanish, which is worse than
leaving it circular, because the source requirement is usually BINDING
and the circular version at least still names it.

## What to do instead

1. **Go back to the source document's phrasing.** It is normally stated on
   the underlying PROPERTY, not on the derived role: "`laneExtent` is
   required exactly when THIS AXIS is content-sized and items contribute
   to it". Transcribe that. The role name is what introduced the circle.
2. **Check the qualifier for runtime data.** "items contribute to it" is
   not a function of the config. That decides where the assert lives.
3. **Decide the assert site by what the site can SEE, not by where the
   other asserts already are.** A config validator called from a
   constructor and two setters sees a config and never an item, so at
   construction there are no items and an item added after a setter runs
   escapes any check made there. The assert belongs at the CONSUMER that
   is about to use the missing value: intrinsic sizing, layout, the paint
   pass. That normally moves it to a later landing step, and the step it
   moves to has to be named.
4. **Record the absence at the earlier step**, so an implementer looking
   for a third assert beside the existing two does not add one. A config
   assert for a rule about items fires on every legal empty board.
5. **Never retire the requirement to fix its wording.** State the
   de-circularized rule, say which step carries the assert, and enumerate
   the case that pins it.

## Test-accounting cost, which is real

An assert with no case is a plan defect a critic will flag. If the plan's
Testing Plan carries a case-count invariant, moving an assert to a later
step usually adds one case, because a throwing fixture cannot ride inside
a positive-sizing case: that case SETS the value and asserts a result,
while this one needs it absent and expects a throw. Enumerate the new case
where the plan already enumerates additions beyond its stub baseline, and
move the count in the same edit. Everything else an audit round adds
normally rides as ASSERTIONS on existing cases and moves no count; the
throwing fixture is the exception worth budgeting for.
