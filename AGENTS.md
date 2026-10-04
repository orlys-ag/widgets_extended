# AGENTS.md

Instructions for every agent in this repository. Claude Code reads this file
through `CLAUDE.md`; other agent tools read it directly. Keep it
self-contained, with no import directives: not every tool expands them.

## Project Overview

A Flutter package (`widgets_extended`) providing rich utility widgets, in these modules:

- **sliver_tree**: a high-performance sliver-based tree widget with animated expand/collapse, FLIP reorder slides, node diffing, drag-and-drop reordering, and sticky headers.
- **sectioned_sliver_list**: a sectioned list (sections + items) built on top of the sliver_tree stack (`SectionedListController` wraps a `TreeController` + `TreeSyncController` with section/item-typed keys).
- **board**: a two-axis lattice viewport built on `RenderTwoDimensionalViewport`, with spanning items, overlap lanes, animated enter/exit and slides, drag-and-drop moves and resizes, cell and range selection, and frozen tracks.

The barrel file `lib/widgets_extended.dart` re-exports each of them.

## Commands

```bash
flutter test                                              # all tests
flutter test test/sliver_tree/tree_controller_test.dart   # one file
flutter analyze

# examples/: a separate package that uses the library through its barrel, as
# an app does. Gitignored, so it exists only in a local checkout.
cd examples
flutter test
flutter analyze
```

After a behaviour change under `lib/`, also run the examples' tests and
analyzer when `examples/` exists: they can fail where `test/` passes.
`flutter analyze` does not report zero issues on this tree, so compare the
issue count before and after your change.

## Code Quality

- Research first: read the code before describing it ("Verified claims").
- Code and tests define current behaviour. A plan in `plans/` is proposed work
  until the code and tests agree with it.
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
  `plans/AUDIT-METHOD.md` section 10.
- Preserve existing work. Change nothing outside the change you were asked to
  make; the working tree may hold uncommitted work that is not yours.
- When a requested change needs error handling or validation to work reliably,
  include it without asking.
- Do not be biased: disagree with the user on any claim that is wrong, and be
  brutally honest at all times.

## Verified claims

Never assert anything about code, APIs or behaviour that you have not checked in
this session: in chat replies, plans, design documents, audits, code comments
and commit messages alike.

- Cite what you assert. A claim about existing code carries the `file:line` you
  read; a claim without one is not verified and is not written. Source comments
  are verified the same way but carry no citations (`.claude/rules/comments.md`).
- Put each citation immediately after the claim it supports. A causal clause
  ("because", "so", "therefore"), a statement of what the framework does, and
  an absolute ("never", "only", "exactly", "cannot", "every") each carry their
  own: observing an outcome does not license explaining it.
- Counts come from commands. Files affected, tests affected, "N places do X",
  how much work something is: run the command and use its output, and never
  approximate a number you could measure. A count of a code symbol's users comes
  from code, by the next rule, never from a text search.
- Before changing a shared declaration (an interface, abstract class, mixin or
  exported symbol), list every implementer and call site, tests included, and
  verify the list in code: best, the users derive from one source and cannot
  disagree; next, `flutter analyze` or a test fails when a user disagrees;
  otherwise, read the code that uses it. A text search only locates what to read
  (`plans/AUDIT-METHOD.md` section 8).
- Read framework behaviour in the Flutter or Dart source before stating it:
  what a widget builds, what a recognizer fires on disposal, what a default
  resolves to. Recall of framework internals is a hypothesis.
- A regression, hazard or failure mode is either demonstrated (a failing test,
  a traced code path) or labelled unverified.
- Tool and subagent output is a lead, not a finding: confirm it against the
  source before repeating it.
- Do not claim a plan, an audit or a colleague got something wrong until you
  have run their check. If their statement was verified and yours is inferred,
  theirs stands.
- Keep write-ups short enough to verify: what changed, what was checked, and
  how. Every extra sentence is another claim to verify.
- Mark anything unverified in the sentence that carries it ("unverified", "I
  have not checked this", "this needs a test"). A confident guess reads exactly
  like a fact, which makes it worse than saying nothing.

Prefer running a check to reasoning toward the answer, and match the tool to
the question. A text search tells you whether a string appears, so use it to
find what to read; `flutter analyze` decides what a symbol resolves to and what
a rename or deletion breaks; a named test going red decides whether a guard
fires. When a text search could give the wrong answer, change tools rather than
narrowing the pattern. When a change is small and fails by compile error or
failing test, implement it rather than reason further.

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

## Code Style

- Always use double quotes `"` for string literals, except for imports; use single quotes `'` on imports.
- Always create braces for code blocks.
- Always use block bodies where possible.
- Never use em-dashes, en-dashes, icons, emoji, or any other non-plain-text symbol (arrows, bullets beyond Markdown's own `-`, trademark, copyright, registered, degree, etc.) in code, comments, documentation, changelogs, commit messages, or chat replies. Use plain ASCII punctuation: a colon, semicolon, comma, parenthesis, or a separate sentence in place of a dash.
- Never add Claude, Claude Code, or Anthropic as a co-author, author, or attribution anywhere. No `Co-Authored-By` trailers, no "Generated with" lines in commit messages, PR descriptions, changelogs, or file headers.

## Guidance map

Read a row's files before the work its When column names. Claude Code also loads
a rule file by itself when it reads, writes or edits a file the rule's `paths:`
names, but not when a shell command touches it. A module rule lists its layer
rules, and a layer rule's `paths:` names the files it governs.

| Read | When |
|---|---|
| [sliver_tree architecture](.claude/rules/sliver-tree.md), and the `sliver-tree-*.md` layer rules naming the file | Editing `lib/sliver_tree/**`, `lib/sectioned_sliver_list/**` or their tests |
| [board architecture](.claude/rules/board.md), and the `board-*.md` layer rules naming the file | Editing `lib/board/**` or its tests |
| [Testing patterns](.claude/rules/testing.md) | Writing or changing tests under `test/**` |
| [Comments](.claude/rules/comments.md) | Adding or changing a comment in Dart source under `lib/`, `test/` or `examples/` |
| [Audit method](plans/AUDIT-METHOD.md) | Writing, auditing or revising a plan in `plans/` |
| [Feature workflow contracts](doc/agents/feature-workflow-contracts.md) | Running or resuming the feature workflow, or producing or reading its files |
| [Agent configuration](.claude/rules/agent-config.md) | Editing `AGENTS.md`, `CLAUDE.md`, `.claude/`, `doc/agents/`, `plans/AUDIT-METHOD.md` or `plans/check_citations.py` |

Before finishing a change to the agent configuration, `plans/AUDIT-METHOD.md` or
`plans/check_citations.py`, run every gate in `doc/agents/method-profile.json`
whose condition applies.

## The feature workflow

`/feature-start` decides whether a change warrants the `feature-implementation`
workflow (`.claude/workflows/`), then launches or resumes it; `/feature-status`
reports on one. The workflow drafts a plan, critiques and revises it, opens a
fresh angle, runs a kept trial, approves the plan, writes a checklist,
implements it, and closes with a review by an agent that never reads the plan.

## Plans and audits

Plans live in `plans/` as `YYYY-MM-DD-<topic>-plan.md`. Before writing or
auditing one, read `plans/AUDIT-METHOD.md`: its rules cannot be reconstructed
by reasoning. A plan states the feature, its goals and its design as they will
be built, never its history (`plans/AUDIT-METHOD.md` rule 2.6). Its citations
are checked by `plans/check_citations.py` against a snapshot of the tree they
were read on; the citation form and the procedure are `plans/AUDIT-METHOD.md`
section 3.
