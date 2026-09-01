# consistency lens, widgets_extended

## Plans are gitignored

`.gitignore:41` is `/plans/*`, and only `AUDIT-METHOD.md` and
`check_citations.py` are tracked (`git ls-files plans/`). There is NO diff
available for a revision round, so "did the revision touch a section outside
its findings" cannot be answered mechanically. Say so in the summary rather
than implying scope was verified. Read the revision section's own bullets
(each names the sections it changed) and check those sections against the
rest of the plan.

## Where staleness actually collects in these plans

The board-view plan carries a "Round N Revision" log at the END, one bullet
per finding, written in the PRESENT tense ("the handler has FOUR callers").
Those bullets are never updated by later rounds, so every enumerated count in
them goes stale the moment a later round changes the enumeration. Grep the
whole file for the count, not just the normative sections: a revision bullet
that says "the count now lives at X and Y and nowhere else" is routinely
falsified by an earlier revision bullet three hundred lines above it.

## Cheap mechanical checks that pay

- `python plans/check_citations.py plans/<plan>.md` (verify only). A clean
  ledger means the cited LINES exist, not that the plan's claim about them is
  true; spot-read the lines a revision newly cited.
- anchors: `grep -oE "\]\(#[a-z0-9-]+\)"` vs `grep -oE '<a id="[a-z0-9-]+">'`.
- numbering: `grep -oE "^\*\*I[0-9]+\."`, same for `R-`, `Q`, `AC`.
- exhaustive-enumeration claims ("reached from exactly SIX sites and no
  others", "four readers, and no fifth"): re-derive the count from the
  numbered STEPS elsewhere in the same invariant, not from the list itself.
  Multi-step procedures that call an enumerated method twice are the usual
  way a "six sites" list is really seven.

## The highest-yield grep: absolutes a revision just wrote

Every round here lands new bolded absolutes ("X only", "neither is in layout",
"exactly TWO consumers", "the only thing that releases it"). Each one is a
claim about a fact that already has a normative site somewhere else, so:
open the cross-reference the absolute names and read it. Two of the three
findings worth reporting in an average round come from this, because the
round's author wrote the absolute from the finding they were fixing and not
from the section that owns the fact. Two shapes seen repeatedly:

- a lifetime/"Reset at" column added to a state table lists one clear site
  while the lifecycle invariant's re-bind or swap script names a second one.
  Grep the field name across the whole plan; every mention is a clear site
  candidate.
- "neither/none is in layout" style claims, where the enumerated site is
  itself declared elsewhere as running inside `layoutChildSequence`.

## Newly NAMED classes need three things, not one

A revision that fixes "this behaviour has no driver" by naming a class
(`BoardAutoScroller`) usually names it only in prose. Check the plan's
"Files created" list and its "Not exported" list for the new name: the
Public Surface preamble in these plans says everything under it IS exported,
so a name added there and nowhere else silently joins the public API and the
barrel test that asserts the partition cannot be written.

## There IS a partial diff: `plans/<plan>.md.bak`

`check_citations.py --repoint/--update` backs the plan up before rewriting, so
`plans/<plan>.md.bak` exists even though `plans/` is gitignored. It is NOT
necessarily the previous round: check how many `^## Round` sections it carries
against the current file before attributing a hunk to the round under audit.
A Python `difflib.SequenceMatcher` over the two line lists gives the hunk list
in seconds and settles "was this sentence touched or is it pre-existing",
which is the question that separates revision damage from an older defect.

## The two-halves pattern, the most common revision damage here

A revision that adds a consumer, a use or a site widens the FIRST half of a
paragraph and leaves the trailing summary sentence behind: "the two consumers
read null DIFFERENTLY", "a member with one stated purpose and two callers",
"the last two rows". Read to the END of every paragraph the revision says it
edited, and grep the same count in the OTHER sections that quote it; the
sibling paragraph one section away is usually the one nobody re-read.

## Duplicated framework-mechanism claims

When a revision answers "this mechanism has no owner" by writing a new
normative site, it also tends to rewrite the ORIGINAL mention with a fresh SDK
citation instead of reducing it to a cross-reference. Two copies of the same
"the framework does X (`sdk/file.dart:NNN`)" sentence is a one-normative-site
violation even when they agree, and the copy left behind is usually the one
missing an intermediate hop.
