# Counts and absolutes in a long plan: which forms go stale

Observed on the board-view plan (6700 lines, twelve revision rounds). Every
consistency finding in Round 12 was one of these shapes. They recur because a
later round widens a mechanism and the count that summarised it sits in a
different section.

## The three stale shapes

1. **A count of CALLERS.** "A member with one stated purpose and two callers."
   Goes stale the moment any round adds a third caller, which is exactly what a
   round that declares a new subscription or a new forwarder does. This form
   should never appear away from the declaration site: reduce it to a bare
   cross-reference to the paragraph that enumerates the readers.
2. **A count of READINGS of a nullable/optional value.** "The two consumers
   read null DIFFERENTLY." A new lifecycle leg (a bind, a re-point) adds a
   third null rule without touching the getter, so nothing in the diff points
   at the sentence. Drop the number and let each site own its own rule.
3. **An absolute about WHERE something runs.** "Neither consumer is in layout."
   Dies the first time an install site moves into `layoutChildSequence`. What
   the author meant is almost always narrower: not "not in layout" but "not one
   of the two extent-scaling sites". Write the narrow form, which stays true.

## The one count form that survives

A count of LAYERS or of ROLES that also NAMES each one. "Two consumers: the
scroll orchestrator and the drag layer" survived twelve rounds while "two
callers" in the same paragraph pair did not, because adding a third caller
inside a named layer does not change the layer count. Prefer an enumeration of
named roles to a total of call sites.

## Fixing one without widening it

The fix is to say LESS. A second copy becomes a BARE cross-reference, not a
shorter paraphrase carrying its own citation: a paraphrase is a second
normative site with a smaller surface, and it goes stale on the same schedule.
When the duplicated copy holds citations, the copy that keeps them is the one
with the complete chain (the `jumpTo` copy that also had the `forcePixels`
hop), not the one that came first.

## Revision-section bullets are part of the artifact

A `## Round N Revision` bullet asserts what a section now says, so a later
round that changes that section makes the old bullet false. Do not rewrite it:
mark it SUPERSEDED in place, naming which HALF was superseded and stating that
the rest is unchanged. Grep the revision sections during the consistency pass,
not only the body.

## The pair-rule leg with no test

When a round declares a lifecycle as a TRIPLE (bind / re-point / unbind) and
adds test cases for two legs, the missing one is the teardown, every time. The
teardown leg is the one whose absence produces a listener outliving its session
and firing into torn-down state. If the testing plan says "two halves" against
a triple, that phrase is the defect marker.

## A count's TOOL goes stale too, not only its number

A plan that pins its test inventory with a quoted grep has made that grep part
of the artifact. Two shapes of it break the first time the counted files stop
being hand-written:

1. **An anchored opener.** `grep -E '^ +(testWidgets|test)\($'` counts a case
   only when the opening paren ENDS the line. Every hand-written stub has that
   shape; `dart format` does not preserve it, and puts a case whose name is long
   on the one-line form `testWidgets("...", (`. The anchored grep then
   undercounts a LANDED file, silently. Keep the anchored form for the stub set
   and the unanchored `^  (testWidgets|test)\(` for landed files, and say in the
   plan that the two are not interchangeable, or the next reader will "simplify"
   them to one.
2. **A pipeline reading the line AFTER the opener** (to extract case names for a
   coverage-by-grep check) fails on the same one-line form, because that line is
   body code. Same fix: mark it a stub-set tool.

Also: a plan that quotes case NAMES and claims they are greppable must keep each
name on ONE line. A wrapped name in the plan breaks the very property the
section is asserting, and the plan will not notice, because nothing greps the
plan against itself. Verify by extracting the names from the test file with a
regex and testing membership in the plan text; do it after every edit that adds
a name.

## The revision-round arithmetic that recurs

When rounds keep adding cases beyond a measured baseline, the invariant that
survives is a THREE-TERM sum, not a subtraction: cases remaining in the stub
set, PLUS cases live in the landed files, PLUS additions the plan has enumerated
but not yet written into any file. The third term is the one a subtraction-style
statement drops, and it is non-zero for as long as a round adds cases to a file
that has not landed yet.
