# Citation ledger mechanics (plans/check_citations.py)

Read before adding or correcting citations in a plan.

## Path resolution, from `resolve()` at check_citations.py:69

- `.dart` with NO slash: globbed under `lib/**` only. Must resolve to
  exactly one file.
- `.dart` WITH a slash: routed to the Flutter SDK at `<sdk>/lib/src/<rel>`.
- `.md`: repository-relative when slashed; globbed repo-wide when bare.

**Consequence: a test file cannot carry a line number.**
`test/board/foo_test.dart:187` is treated as an SDK path and reports
SKIPPED / unresolved forever; `foo_test.dart:187` is not under `lib/`, so
it does not resolve either. Cite test files by NAME ONLY and identify the
construct in prose ("its `correctionsEnabled` constructor flag"). The
house plans already do this; a line number on a `test/` path is the
mistake to avoid.

## Modes

- `--record-new` (check_citations.py:307) adds rows ONLY for citations the
  ledger has never seen and never rewrites or drops an existing one. This
  is the correct mode after a REVISION that added citations, and it is
  strictly safer than `--update`, which re-anchors every entry to whatever
  now sits at its recorded line number.
- `--repoint` after any change under `lib/`. Moves a citation only when its
  recorded text is found at exactly one place; what it leaves drifted is a
  real finding.
- Verify BEFORE recording, so a pre-existing drift is not silently buried.

## Ordering that worked in the board-view revision

1. verify (establish the baseline: ok N, drifted 0)
2. edit the plan
3. verify again, read the NEW list
4. `--record-new`
5. verify (expect ok N', drifted 0, unrecorded 0)

## Amending a cited .md (an input document the plan cites by line)

Editing the requirements document a plan cites shifts every citation below
the edit. Two ledgers exist and only one is affected:

- The PLAN's ledger has rows keyed on `<requirements>.md:NNN`. All of them
  below the edit drift by the delta.
- The REQUIREMENTS' own ledger is keyed on dart files. Editing the .md moves
  no dart line, so it stays clean and needs nothing.

Order that works, and why each step is where it is:

1. Edit the cited .md first, so the plan can be written against final line
   numbers.
2. Keep the first line of any cited paragraph BYTE-IDENTICAL when you can.
   That one ledger row survives and gives the historical citations a stable
   anchor to be retargeted onto.
3. Update the plan's prose for citations into DELETED text BEFORE recording.
   `--repoint` reports those as DELETED and correctly refuses to guess.
4. **Pick new citation line numbers that are not already ledger rows.**
   `--record-new` never rewrites an existing row, so re-citing a line whose
   recorded token is the deleted text reports DRIFTED forever and there is no
   safe way out (`--update` is the unsafe one). Read the recorded line list
   first: `awk -F'\t' '$1=="<cited.md>" {print $2}' <plan>.md.citations.tsv`.
5. `--repoint` (moves the shifted ones, leaves the deleted ones), then
   `--record-new`, then verify.

A ledger row nobody cites any more is invisible to verify, which iterates the
citations found in the PLAN, not the rows in the ledger. So a deleted-text row
needs no cleanup once the prose stops naming its line.

## The end-of-live-document heading

POINTER ONLY. A plan may carry an optional heading that the checker treats as
the end of the live document, verifying nothing at or below it. The row is in
`doc/agents/feature-workflow-contracts.md`'s optional-sections table and the
hazard is stated there: the match is an unanchored substring split, so writing
that heading's text into a sentence in a live section truncates verification
silently and still exits 0. Two consequences follow for this file's subject.
Every citation that lives only below the heading becomes a permanent ledger
orphan, which is expected; and `--update` on such a plan deletes those rows and
then reports clean, so `--record-new` is the only safe recording mode there.

## `--repoint` rewrites line endings on Windows

POINTER ONLY. The normative site is `AGENTS.md`, "Plans and audits", where the
board-view plan's Round 14 moved it on 2026-08-30. It names the four
`write_text` call sites, the `newline=None` translation, why the `.bak` is not
evidence of the original bytes, and the LF restore step. Do not restate any of
that here: two copies is what Round 14 removed.

## When a design plan starts citing its own LANDED implementation

A greenfield plan normally cites only the requirements, the sibling
modules and the SDK, so `--repoint` after a `lib/` edit is a no-op for it
and a revision needs `--record-new` alone. The moment a landed step's code
becomes evidence the plan must cite (an audit round asking "what did step 4
actually do?"), that stops being true: every later edit under the module
shifts those line numbers, and `--repoint` after such an edit becomes
mandatory for that plan.

Record the flip explicitly in the revision section, with the count and the
files, because an earlier round may have written the OPPOSITE as a standing
fact ("no citation in it names a `lib/<module>/` path with a line number").
A reader who trusts that line will skip the repoint.

Two smaller consequences worth knowing before adding the first ones:

- A ledger that had zero rows for the module gets them all at once, so
  `--record-new` output is the full inventory and is worth reading as one.
- Duplicate recorded TEXT at two lines (`throw StateError(message);` twice
  in one helper) is harmless for verify, which is keyed on the line number,
  but `--repoint` will refuse to move either if they later drift. That is
  the correct refusal, not a bug.
