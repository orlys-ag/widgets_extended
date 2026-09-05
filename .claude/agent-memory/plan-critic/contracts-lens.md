# contracts lens gotchas (widgets_extended)

## check_citations.py: what it does NOT verify

- `live_text` splits the plan at the literal string `## Audit log`
  (`plans/check_citations.py:65`) and verifies nothing at or below it. Every
  `## Round N Revision` section sits below that split, so citations written in
  a revision log are NEVER checked. A ledger can carry rows for files that are
  only cited in history (leftovers from when the section was live), so
  `cut -f1 <ledger>` over-reports the live cited-file set.
- `resolve` maps a bare `.dart` name through `REPO.glob("lib/**/<name>")`
  (`plans/check_citations.py:93`). TEST files are therefore uncitable: a
  `foo_test.dart:120` citation resolves to nothing. Plans work around this by
  writing "`foo_test.dart` line 120" in prose, which means every claim about an
  existing test is UNVERIFIED by the ledger. Check those by hand; they are the
  cheapest place for a plan to be wrong.
- `.md` citations ARE resolved (repo-relative or unique glob,
  `plans/check_citations.py:81-89`), so `board-architecture.md:92-94` and
  `AUDIT-METHOD.md:267-269` are ledgered. `.py` citations are not parsed.

## Ordinal references into test files are ambiguous here

`test/board/track_resize_test.dart` labels one of its cases "the THIRD case"
in a comment (line 257) while it is the FIFTH `testWidgets` in the file: the
board test files number their DERIVED cases in a series separate from the
AC-derived ones. A plan that says "`<file>`'s third case" can therefore be
right under the file's own numbering and wrong under a reader's count. Resolve
it by grepping the case NAME, and flag the ordinal.

## The board plan's dependent-document set

A change under `lib/board/` normally has to update, and a plan that omits one
is a finding:
- `doc/agents/board-architecture.md` (the per-layer bullets; loaded via
  `.claude/rules/board.md`)
- `plans/2026-08-29-board-view-requirements.md:737-739`, which is the
  normative layout-driving vs paint-only family split (`makeRoom` is listed
  paint-only there)
- the in-code doc comments that enumerate arms:
  `render_board_viewport.dart:379-393` ("The four-branch routing") and
  `render_board_viewport.dart:823-829` ("Five arms per track"). These are
  normative in the same sense as the prose and go stale silently.
- `CHANGELOG.md` has NO board module entry yet
  (`grep -n -i board CHANGELOG.md` returns one unrelated line), so board plans
  correctly skip a changelog entry.

## One list, two owners

`BoardController._animationListeners` (`board_controller.dart:141`) is passed
BY REFERENCE into the coordinator's `listeners:` (`board_controller.dart:94`,
held at `_board_animation_coordinator.dart:137`). A plan citing the
coordinator's copy-per-dispatch (`_board_animation_coordinator.dart:341-348`)
to justify removing a listener added through `BoardController.addAnimationListener`
is CORRECT, not a mismatch. Verify before reporting it as one.
