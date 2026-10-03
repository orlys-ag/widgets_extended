# consistency lens, widgets_extended

## The revision snapshot is the diff

`.gitignore:41` is `/plans/*`, and only `AUDIT-METHOD.md` and
`check_citations.py` are tracked (`git ls-files plans/`), so git holds no
history of a plan. A workflow revision copies the plan to `<plan>.r<N>` before
editing and reports the path, and your prompt names it: run
`git diff --no-index <snapshot> <plan>`. A hunk outside the decisions the
revision reports it changed, and their dependents, is a finding, as is an
obligation the prompt lists that the diff does not show met. When the prompt
says no snapshot exists (the revision returned nothing), check scope by reading
the revision's record in the audit file, and say so in the summary rather than
implying scope was verified.

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

## A hand-revised plan may have only a partial diff: `plans/<plan>.md.bak`

A plan revised by hand, outside the workflow, may have no snapshot.
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

## Ordinal cross-references resolve against the FILE's own numbering

"`track_resize_test.dart`'s third case" is not the third `testWidgets` in
source order: that file numbers a SUBSET in its own comments
(`test/board/track_resize_test.dart:257` says "the THIRD case, which pins the
enter carve-out", above the fifth `testWidgets`). Read the comment block above
the candidate case before filing an ordinal cross-reference as broken; the
plan is usually citing the file's convention.

## The three cheap counted claims that go stale every round

- The baseline paragraph's "each of the N `lib/board/` files cited here":
  re-run `cut -f1 <plan>.md.citations.tsv | grep ".dart$" | sort -u | wc -l`
  and subtract the SDK rows. A round that cites one new module file falsifies
  N and nothing else in the plan notices.
- The Testing Plan's "the three demonstrated rows carry (demonstrated)":
  `grep -n "(demonstrated)"` and compare against the rows the paragraph names.
- Enumerations of "which scratch variants could not have been run": count the
  rows whose "Fails against" column names a scratch, not the rows the
  paragraph lists.

## Quoted old vocabulary re-registers its citations

The consistency paragraph each round appends quotes the replaced vocabulary,
so a replaced CITATION (`"render_board_viewport.dart:356"`) is still parsed as
a live citation, gets a ledger row, and verifies clean forever while the plan
asserts nothing about that line. Harmless, but it means a ledger row is not
evidence that any section still cites the line.

## "X gains N members" is a claim about EXISTING code

The Public Surface preamble in these plans says a class "gains six members",
then a component section cites the implementation of one of them as already
existing (`MakeRoomEngine` already has `deltaOf` at `_make_room_engine.dart:110`,
cited by the plan itself). Grep the class for each member name before
accepting the count: the reader interface and the engine behind it gain
DIFFERENT numbers, and the plan states one number for both.

## Neither a snapshot nor a .bak

`plans/<plan>.md.bak` exists only if a `--repoint`/`--update` ran since the
last cleanup. When a hand-revised plan has neither it nor a snapshot, there is
no diff at all, so say in the summary that revision scope was checked by
reading the revision's own record, not verified mechanically.

## A round's own consistency paragraph carries an arithmetic claim

"Ten returned nothing. Two returned one hit each" against a twelve-item
vocabulary list whose last three items the same paragraph then says DID
survive. Count the quoted items in the list and compare against the split;
the T-label items are usually counted twice.

## Two sorts in `_overlap_lanes.dart`, and rounds pick the wrong one

The committed resolve sorts at `_overlap_lanes.dart:245-257`; `resolveDryRun`
sorts at `_overlap_lanes.dart:414-426` AFTER `members.remove(draggedId)`
(`:407`). A fixture claim about the PRE-LIFT lanes of all three items is the
committed sort; a claim about what the preview lanes is the dry run. A test
row and its fixture recipe citing different ones for the same fact is the
usual shape.

## The session's `gitStatus` snapshot lies about the board branch

The system-prompt `gitStatus` block is a snapshot from session start and can be
several commits stale: on `board-view-correction-trial` it showed HEAD at
`6cce4c8` with `lib/board/` and every `test/board/*.dart` UNTRACKED, which would
falsify the board plans' baseline paragraph ("the module is committed at
`fde7b90`", "`git status --porcelain lib test` prints nothing") and read as a
blocking finding. `git log --oneline -3` showed HEAD is actually `bd52f7f` with
`git ls-files lib/board` returning 24 and a clean `git status --porcelain lib
test`. Always re-run the plan's own stated commands before filing a baseline or
clean-tree contradiction.

## "X is NOT modified by this plan" outlives the file list

A round that adds one member to a previously untouched file updates **Overview**'s
Files-modified list and **Public Surface** and leaves a component section's flat
"`<file>` is NOT modified by this plan" standing (seen: C5 vs `board_controller.dart`
after round 6 moved the lifecycle key onto `BoardController`). Grep every file in
the Files-modified list for "NOT modified" and for "gains no", not just the
sections the round's bullets name.
