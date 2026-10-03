# Citation ledger mechanics (plans/check_citations.py)

Read before adding or correcting citations in a plan.

## Path resolution, from `resolve()` at check_citations.py

- `.dart` with NO slash: globbed under `lib/**` only. Must resolve to
  exactly one file.
- `.dart` WITH a slash: routed to the Flutter SDK at `<sdk>/lib/src/<rel>`.
- Every other extension the profile's `citations` block lists (`.md`, `.js`,
  `.mjs`, `.py`): repository-relative when slashed, a leading dot allowed;
  globbed repo-wide when bare, skipping `.claude/worktrees/`.
- A bare `:N` after a citation of an unlisted extension is reported DANGLING.

**Consequence: a test file cannot carry a line number.**
`test/board/foo_test.dart` is treated as an SDK path and reports
SKIPPED / unresolved forever; `foo_test.dart` is not under `lib/`, so
it does not resolve either. Cite test files by NAME ONLY and identify the
construct in prose ("its `correctionsEnabled` constructor flag"). The
house plans already do this; a line number on a `test/` path is the
mistake to avoid.

## Modes

- Verify reports OK, MOVED (recorded text elsewhere in the file; passes) or
  GONE (text nowhere in the file; fails). Only GONE is a finding.
- `--update` records a plan that has NO ledger, and refuses an existing one.
- `--record-new` adds rows ONLY for citations the ledger has never seen and
  never rewrites or drops an existing one. The mode after a REVISION that
  added citations.
- `--accept <path:line> ...` re-records exactly the named citations, all or
  nothing. The way out of GONE once the claim was re-read and corrected,
  including a corrected citation whose line already had a row.
- `--repoint` is optional: it renumbers the MOVED citations of the plan in
  hand for a reader. Nothing requires it after a change under `lib/`.
- Verify BEFORE recording, so a GONE citation is read rather than buried.

## Ordering that worked in the board-view revision

1. verify (establish the baseline: ok N, gone 0)
2. edit the plan
3. verify again, read the NEW list
4. `--record-new`
5. verify (expect gone 0, unrecorded 0)

## Amending a cited .md (an input document the plan cites by line)

Editing the requirements document a plan cites shifts every citation below
the edit. Two ledgers exist and only one is affected:

- The PLAN's ledger has rows keyed on `<requirements>.md:NNN`. All of them
  below the edit move by the delta and report MOVED, which passes.
- The REQUIREMENTS' own ledger is keyed on dart files. Editing the .md moves
  no dart line, so it stays clean and needs nothing.

Order that works, and why each step is where it is:

1. Edit the cited .md first, so the plan can be written against final line
   numbers.
2. Keep the first line of any cited paragraph BYTE-IDENTICAL when you can.
   That one ledger row survives and gives the historical citations a stable
   anchor to be retargeted onto.
3. Update the plan's prose for citations into DELETED text BEFORE recording;
   verify reports those GONE.
4. `--record-new` for citations on lines that have no ledger row, and
   `--accept` for a re-cited line that already has one, since `--record-new`
   never rewrites an existing row.
5. Verify. `--repoint` only if you want the shifted numbers current.

A ledger row nobody cites any more is invisible to verify, which iterates the
citations found in the PLAN, not the rows in the ledger. So a deleted-text row
needs no cleanup once the prose stops naming its line.

## The end-of-live-document heading

POINTER ONLY. A plan written before the audit file may carry an audit-log heading that the
checker treats as the end of the live document, verifying nothing at or below
it. `doc/agents/feature-workflow-contracts.md` section 3 states the hazard: the match is an unanchored substring split, so writing
that heading's text into a sentence in a live section truncates verification
silently and still exits 0. Two consequences follow for this file's subject.
Every citation that lives only below the heading becomes a permanent ledger
orphan, which is expected; and `--update` on such a plan deletes those rows and
then reports clean, so `--record-new` is the only safe recording mode there.

## When a design plan starts citing its own LANDED implementation

A greenfield plan normally cites only the requirements, the sibling
modules and the SDK, so a `lib/` edit moves none of its citations and a
revision needs `--record-new` alone. The moment a landed step's code
becomes evidence the plan must cite (an audit round asking "what did step 4
actually do?"), every later edit under the module moves those lines. They
report MOVED, which passes, and GONE only where an edit rewrote a cited line,
which is a finding.

Two smaller consequences worth knowing before adding the first ones:

- A ledger that had zero rows for the module gets them all at once, so
  `--record-new` output is the full inventory and is worth reading as one.
- Duplicate recorded TEXT at two lines (`throw StateError(message);` twice
  in one helper) is harmless: verify reports it MOVED when it shifts, and
  `--repoint` refuses to move either, which is the correct refusal.
