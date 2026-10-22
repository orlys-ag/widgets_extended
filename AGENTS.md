# AGENTS.md

Instructions for every agent in this repository.

## Project Overview

A Flutter package (`widgets_extended`) providing rich utility widgets, in these modules:

- **sliver_tree**: a high-performance sliver-based tree widget with animated expand/collapse, FLIP reorder slides, node diffing, drag-and-drop reordering, and sticky headers.
- **sectioned_sliver_list**: a sectioned list (sections + items) built on top of the sliver_tree stack (`SectionedListController` wraps a `TreeController` + `TreeSyncController` with section/item-typed keys).
- **board**: a two-axis lattice viewport built on `RenderTwoDimensionalViewport`, with spanning items, overlap lanes, animated enter/exit and slides, drag-and-drop moves and resizes, cell and range selection, and frozen tracks.

The barrel file `lib/widgets_extended.dart` re-exports each of them.

A fourth module, calendar, is in progress in `lib/calendar/`: a calendar widget
(`CalendarView`) with Agenda, Day, Week and Month views on the board and
sliver_tree modules, whose rules are in `.claude/rules/calendar.md`. Its barrel
is `lib/calendar/calendar.dart`; `lib/widgets_extended.dart` does not export it
yet, and no package release ships while `lib/calendar/` exists and
`lib/widgets_extended.dart` does not export it.

`demos/workspace_calendar/` is a tracked demo app, a month, week and day
calendar on the board and the synced sliver tree. It depends on the library by
path and is not part of it: nothing under `lib/` imports it.

## Commands

```bash
flutter test                                              # all tests
flutter test test/sliver_tree/tree_controller_test.dart   # one file
flutter analyze lib test                                  # the package

# examples/: a separate package that uses the library through its barrel, as
# an app does. Git ignores it, so it exists only in a local checkout that
# holds examples/pubspec.yaml. The subshell keeps the shell at the root.
(cd examples && flutter test)
(cd examples && flutter analyze)

# demos/workspace_calendar/: the tracked demo app, on the library by path.
(cd demos/workspace_calendar && flutter test)
(cd demos/workspace_calendar && flutter analyze)
```

- After a behaviour change under `lib/`, also run the demo's tests and
  analyzer, and the examples' when `examples/pubspec.yaml` exists: they can
  fail where `test/` passes.
- `flutter analyze lib test` and the demo's `flutter analyze` report no issues;
  keep it that way. A plain `flutter analyze` at the root also analyzes
  `examples/`, where neither command reports zero problems, so there compare
  what each reports before and after your change.

## Code Quality

- Code and tests define current behaviour. A plan in `plans/` is proposed work
  until the code and tests agree with it; continuing an unbuilt one is a
  feature-delivery run whose requirements name it.
- Prefer correct, complete implementations over minimal ones. Use appropriate
  data structures and algorithms; do not brute-force what has a known better
  solution.
- Fix a bug at its root cause, not its symptom, and test-first: a repro test
  that fails on the unfixed code, with every new assertion shown to fail
  (`.claude/rules/testing.md`).
- When a diagnosis is uncertain, test one concrete hypothesis, then reassess
  from the evidence. Do not stack speculative fixes.
- A performance claim needs a measurement, such as a debug counter or a timed
  run, not only a plausible mechanism. A timed comparison follows
  `doc/agents/delivery-method.md` section 11.
- Preserve existing work. Change nothing outside the change you were asked to
  make; the working tree may hold uncommitted work that is not yours.
- When a requested change needs error handling or validation to work reliably,
  include it without asking.
- Work governed by an audit, issue or specification closes against that
  original source, never a paraphrase or a derived checklist: each of its
  criteria quoted and marked met, partial or unmet with its evidence, in the
  acceptance document format of `.claude/agents/delivery-reviewer.md`.
- Do not be biased: disagree with the user on any claim that is wrong, and be
  brutally honest at all times.

## Verify before asserting

Assert nothing about code, APIs or behaviour that you have not checked in this
session, in replies, documents, code comments and commit messages alike. Say
"unverified" in the sentence that carries anything you have not checked.

- Cite what you read beside the claim it supports: a `file:line` in replies
  and plans, a symbol in code comments (`.claude/rules/comments.md`). An
  explanation ("because") or an absolute ("always", "never") needs its own
  check.
- Take counts and lists of a symbol's users from a command or the analyzer,
  never from memory; a text search only finds what to read.
- Before changing a shared declaration, find every user, tests included, and
  let `flutter analyze` or a failing test confirm the list.
- Read Flutter and Dart behaviour in the SDK and package source before stating
  it: what a widget builds, what a recognizer fires on disposal, what a default
  resolves to. Recall is a hypothesis.
- Tool and subagent output is a lead until you confirm it in the source.
- Prefer running a check to reasoning toward an answer; a small change that
  the analyzer or a test would judge is made, not argued about.

## Response style

These rules apply to every answer given to the user.

- Be concise. Make each point once, and repeat a concept only when a new context
  makes it relevant again.
- Write in plain English. Use full sentences, in an order the reader can follow
  from start to finish.
- Keep the technical terms the answer needs. Do not replace a precise term with
  a vague one to make the answer sound simpler.
- Be precise rather than exhaustive. Answer what was asked, and leave out
  background the reader did not ask for and does not need.
- Keep write-ups short enough to verify: what changed, what was checked, and
  how.

## Code Style

- Always use double quotes `"` for string literals, except for imports; use single quotes `'` on imports.
- Always create braces for code blocks.
- Always use block bodies where possible.
- Write plain ASCII in code, comments, documents, changelogs, commit messages
  and chat replies: no em or en dashes, arrows, icons, emoji, bullets other
  than Markdown's `-`, or symbols such as trademark, copyright or degree signs.
  In place of a dash, use a colon, semicolon, comma, parentheses or a new
  sentence.
- Never add Claude, Claude Code, or Anthropic as a co-author, author, or attribution anywhere. No `Co-Authored-By` trailers, no "Generated with" lines in commit messages, PR descriptions, changelogs, or file headers.

## Guidance map

Read a row's files before the work its When column names, unless their contents
already appear in your context. A module rule lists its layer rules, and a
layer rule's `paths:` names the files it governs.

| Read | When |
|---|---|
| [sliver_tree architecture](.claude/rules/sliver-tree.md), and the `sliver-tree-*.md` layer rules naming the file | Editing `lib/sliver_tree/**`, `lib/sectioned_sliver_list/**` or their tests |
| [board architecture](.claude/rules/board.md), and the `board-*.md` layer rules naming the file | Editing `lib/board/**` or its tests |
| [calendar architecture](.claude/rules/calendar.md), and the `calendar-*.md` rule of the file's layer | Editing `lib/calendar/**` or its tests, or changing demo code so it can move into `lib/calendar/` |
| [Testing patterns](.claude/rules/testing.md) | Writing or changing tests under `test/**` |
| [Comments](.claude/rules/comments.md) | Adding or changing a comment in Dart source under `lib/`, `test/` or `examples/` |
| [Feature delivery method](doc/agents/delivery-method.md) | Writing a plan, or running, resuming or reading a feature-delivery run, whose files are under `plans/delivery/` |
| [Agent configuration](.claude/rules/agent-config.md) | Editing `AGENTS.md`, `CLAUDE.md`, `.claude/`, `doc/agents/` or `plans/check_citations.py` |
