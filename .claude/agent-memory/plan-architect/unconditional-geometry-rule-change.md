# Changing a settled geometry rule for every existing board

A plan that widens a geometry rule with no opt-out flag ("expansion is
the lane geometry, unconditionally") changes the measured output of every
existing fixture that meets the new condition. Four things it owes, each
of which a first draft reliably omits.

## 1. The existing suite is a landing gate, and "no test needs an edit" is a claim over a set no grep produces

A grep for the ACCESSOR names ("laneOf", "laneCountOf") answers a
different question from the one the plan is making. Assignment reads are
not the assertions at risk; painted-geometry reads are, and those come
through `tester.getRect` / `getSize`, which no accessor grep finds. In
this repo `grep -rln "laneOf\|laneCountOf" test` returned 13 files while
`grep -rln "laneExtent" test/board/` returned 17, and the two sets are
about different things.

Deciding a fixture's spans/slots means RUNNING the resolver over its item
set. That is not a grep, and the honest plan says so rather than
enumerating a subset. What it writes instead:

- The existing suite plus `flutter analyze` in the green list of the step
  that changes the rule, named as a gate rather than a formality.
- A RE-BASELINE RULE: which existing cases may legitimately change (those
  whose fixture meets the new condition), how to verify one
  mechanically (read the new per-item value, confirm the painted extent
  is the rule applied to it), and the statement that a fixture where the
  new value is the identity (span 1, `1 * slice == slice`) and whose
  numbers still moved is a regression by definition.
- The fixtures actually read, with their item sets, marked as a sample
  and not the enumeration.

## 2. The dominant per-frame cost is usually a RECLASSIFICATION, not the added read

The instinct is to price the new dense-array read. That is noise. The
real cost is that a class of event which installed NOTHING now installs
something that a union predicate classifies as layout-driving.

Trace it explicitly: the new value produces a non-zero delta, the delta
installs an animation, the animation's `hasExtentActive` /
`hasExtentMotion` is a term of `hasLayoutDrivingAnimations`, and the
render's tick router calls `markNeedsLayout()` on that union's first arm
on EVERY axis. A mutation that cost zero relayouts now costs one
`performLayout` per frame for the family's duration.

Name the axis where it is entirely new (here: the fixed lane axis, where
the router otherwise never classifies a gap or a relane as
layout-driving) and the existing event class it matches, so the reader
can tell a new cost from a widened one.

## 3. An idempotence gate downstream of an expensive computation does not bound it

"The engine's idempotence makes a re-entered install a no-op" is a claim
about the INSTALL LOOP. If the dry run / resolve runs before that loop,
the idempotence spares nothing. Check the call order in the source, not
the architecture doc's summary of it.

Then find the real upstream gate and characterise it per input mode. Here
it was `resolved.span == _lastResolvedSpan` in the drag controller: a
TRACK snap clears it once per cell crossing, a FRACTION snap on nearly
every motion frame. State the bound per CALL of the expensive thing, and
say which caller pays it per frame.

## 4. A dependent document sentence the plan falsifies must be RETRACTED by name

Adding to a bullet is not retracting the clause beside it. Two failure
shapes, both seen in one round:

- The cited range stops mid-parenthetical (`:107-111` when the
  parenthetical runs to `:112`), so the described edit leaves the false
  clause standing.
- The bullet cites the wrong sentence entirely: the claim being edited
  ("the ramp scales the whole band") lived 80 lines earlier, in a
  different component's bullet.

For each doc edit write: the sentence's line range INCLUDING its
parenthetical, what stays true, what is retracted, and what a later
reader would wrongly conclude if it were left (here: that a flag "can
never fire on a content-sized lane axis" and that a whole render arm is
dead). In this repo the board and sliver_tree architecture docs load into
every session through `.claude/rules/`, so a false clause is not inert.

## 5. Acceptance-criterion labels from a non-repo artifact

`(AC1)` through `(ACn)` labels are unresolvable when the requirements
live only in the workflow input. Declare that ONCE, with the command that
shows it (`grep -rln "<feature term>" --include=*.md .`, and the house
form `plans/YYYY-MM-DD-<topic>-requirements.md` when one does exist),
state that the labels are back-references for the requirements author,
and make each case's TARGET sentence the normative statement. Then
restate inline every criterion the body actually leans on: the fixture's
interval set, any disputed wording an Open Question turns on, and any
named defeater a falsification cites.
