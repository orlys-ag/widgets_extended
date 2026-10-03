# AGENTS.md

Canonical agent instructions for this repository. Other agent tools read
this file directly; Claude Code reaches it by importing it from
`CLAUDE.md`. Edit this file for anything that should apply to every agent,
and keep it self-contained: do not use import directives here, because not
every tool that reads this file expands them.

## Project Overview

A Flutter package (`widgets_extended`) providing rich utility widgets. Three modules:

- **sliver_tree**: a high-performance sliver-based tree widget with animated expand/collapse, FLIP reorder slides, node diffing, drag-and-drop reordering, and sticky headers.
- **sectioned_sliver_list**: a sectioned list (sections + items) built on top of the sliver_tree stack (`SectionedListController` wraps a `TreeController` + `TreeSyncController` with section/item-typed keys).
- **board**: a two-axis lattice viewport built on `RenderTwoDimensionalViewport`, with spanning items, overlap lanes, animated enter/exit and slides, drag-and-drop moves and resizes, cell and range selection, and frozen tracks.

The barrel file `lib/widgets_extended.dart` re-exports all three modules.

## Commands

```bash
# Run all tests
flutter test

# Run a single test file
flutter test test/sliver_tree/tree_controller_test.dart

# Analyze (lint)
flutter analyze

# The examples app: a separate package that uses the library through its
# barrel, as an app does. Gitignored, so it exists only in a local checkout.
cd examples && flutter test && flutter analyze
```

Run the examples after any behavior change under `lib/` when they are
present: they can fail where `test/` passes. `flutter analyze` does not report
zero issues on the current tree, so compare the count before and after your
change rather than expecting none.

## Code Quality
- Always take a research-first approach: read the code before describing it. See "Verified claims".
- Code and tests define current behavior. A plan in `plans/` is proposed work until the code and tests agree with it.
- Prefer correct, complete implementations over minimal ones.
- Use appropriate data structures and algorithms; don't brute-force what has a known better solution.
- When fixing a bug, fix the root cause, not the symptom, and work test-first: a repro test that fails on the unfixed code, with every new assertion shown to fail (see Testing patterns in the guidance map).
- When a diagnosis is uncertain, test one concrete hypothesis, then reassess from the evidence. Do not stack speculative fixes.
- A performance claim needs a measurement, such as a debug counter or a timed run, not only a plausible mechanism. A timed comparison follows the protocol in `plans/AUDIT-METHOD.md` section 17.
- Preserve existing work. Do not discard or rewrite code outside the change you were asked to make; the working tree may hold uncommitted work that is not yours.
- If something I asked for requires error handling or validation to work reliably, include it without asking.
- Do not be biased. Disagree with the user on any claims that are wrong. Be brutally honest at all times.

## Verified claims

Never assert anything about code, APIs, or behavior that you have not checked in this session. This applies equally to chat replies, plans, design documents, audits, code comments, and commit messages.

- **Cite what you assert.** A claim about existing code carries the `file:line` you actually read. No citation means it was not verified, which means it does not get written. Source comments are verified the same way but carry no citations; see "Comments and doc comments".
- **Counts come from commands.** Files affected, tests affected, call sites, "N places do X", how much work something is: run the search and use its output. Never approximate a number you could have measured.
- **Framework behavior is read, not recalled.** What a widget builds, what a recognizer fires on disposal, what a default resolves to: verify against the Flutter or Dart source before stating it. Recall of framework internals is a hypothesis, not a fact.
- **Before changing a shared declaration, enumerate its users, and verify them in code.** Interfaces, abstract classes, mixins, exported symbols: list every implementer and call site, including tests, before proposing or making the change. Verify the list in code, not with tools: best, the users derive from one source and cannot disagree; next, `flutter analyze` or a test fails when a user disagrees; otherwise, read the code that uses the declaration. A text search only locates what to read and is never the verification (`plans/AUDIT-METHOD.md` section 15).
- **Do not invent risks.** A regression, hazard, or failure mode is either demonstrated (a failing test, a traced code path) or labelled unverified. A plausible-sounding risk stated as a finding costs more time than it saves.
- **Tool and subagent output is a lead, not a finding.** Confirm it against the source yourself before repeating it as established.
- **Causal clauses carry their own citation.** A "because", "so", "therefore", or any statement of what the framework does is the highest-risk claim in a write-up, not the lowest. Observing an outcome does not license explaining it: cite the line that states the mechanism, or delete the clause. Absolutes ("never", "only", "exactly", "cannot", "every") get the same treatment. Put the citation immediately after the claim it supports rather than elsewhere in the sentence, so a reader can tell which claim it backs.
- **Do not claim a plan, an audit, or a colleague got something wrong until you have run their check.** If their statement was verified and yours is inferred, theirs stands. This is the one error that also destroys someone else's correct work, so it carries the strictest bar.
- **Keep write-ups short enough to verify.** A status note or summary says what changed, what was checked, and how it was checked. Every additional explanatory sentence is another claim that someone has to verify, so length is a cost, not a sign of rigor.

When something is unverified and still worth saying, mark it in the sentence that carries it: "unverified", "I have not checked this", "this needs a test". A stated gap is useful. A confident guess is a defect, and it is worse than saying nothing, because it reads exactly like a fact.

Prefer running the check to reasoning toward the answer. A grep, a test run, or `flutter analyze` settles a mechanical question faster and more reliably than argument does. When a change is small and its failure modes are compile errors or failing tests, implement it rather than reason further about it.

Match the tool to the question. A text search tells you whether a string appears: use it to find what to read and to count text. What a symbol resolves to, and what a rename or deletion breaks, is decided by `flutter analyze`. Whether a guard fires is decided by changing it and watching a named test go red. A text match agrees with the real answer most of the time and diverges exactly where it matters, so when it gives a wrong answer, change tools rather than narrowing the pattern. Where code is concerned, verify with code over tools: a check that runs in code (the analyzer, a test, a value derived from one source) or a reading of the code itself; a search tool is the last resort, and only to find what to read.

## Response style

These rules apply to every answer given to the user.

- Be concise. Make each point once, and repeat a concept only when a new context makes it relevant again.
- Write in plain English. Use full sentences, in an order the reader can follow from start to finish.
- Keep the technical terms the answer needs. Do not replace a precise term with a vague one to make the answer sound simpler.
- Be precise rather than exhaustive. Answer what was asked, and leave out background the reader did not ask for and does not need.

## Code Style

- Always use double quotes `"` for string literals, except for imports; use single quotes `'` on imports.
- Always create braces for code blocks.
- Always use block bodies where possible.
- Never use em-dashes, en-dashes, icons, emoji, or any other non-plain-text symbol (arrows, bullets beyond Markdown's own `-`, trademark, copyright, registered, degree, etc.) in code, comments, documentation, changelogs, commit messages, or chat replies. Use plain ASCII punctuation: a colon, semicolon, comma, parenthesis, or a separate sentence in place of a dash.
- Never add Claude, Claude Code, or Anthropic as a co-author, author, or attribution anywhere. No `Co-Authored-By` trailers, no "Generated with" lines in commit messages, PR descriptions, changelogs, or file headers.

## Comments and doc comments

Applies to every comment added to Dart source under `lib/`, `test/`, and `examples/`.

- Document the public API with `///` doc comments: what the member does and its contract (parameters, return value, errors thrown, lifecycle, notifications fired). The public API is what `lib/widgets_extended.dart` exports; a name without an underscore that the barrels do not export is internal.
- Everywhere else, comment sparingly. Write a comment only where the code cannot say it itself: a non-obvious algorithm, an invariant, an ordering constraint, or a framework behavior the code depends on. Do not narrate what the next line does.
- A comment describes the code it sits beside, and the code that code calls or is called by, as it is now. It never references anything outside the source: plans, audits, reviews, finding IDs such as `(H5)`, issues, the changelog, other documents, dates, conversations, or the history of the change ("previously", "used to", "fixes the bug where"). History belongs in the commit message; a reason that must outlive the commit is stated as a property of the current code.
- Refer to other code by symbol, as a dartdoc link (`[TreeController.moveNode]`) or a backticked name, never by `file:line`. Name Flutter behavior by the framework symbol rather than an SDK line. Line numbers in source go stale, and nothing checks them.
- Existing comments that break these rules are not a precedent, including for how densely to comment.

## Guidance map

Loaded on demand. Claude Code also loads the first three automatically
via `.claude/rules/`, scoped to the paths they govern; other agent
tools should read them when the When column applies.

| Read | When |
|---|---|
| [sliver_tree architecture](doc/agents/sliver-tree-architecture.md) | Editing `lib/sliver_tree/**` or `lib/sectioned_sliver_list/**` |
| [board architecture](doc/agents/board-architecture.md) | Editing `lib/board/**` |
| [Testing patterns](doc/agents/testing-patterns.md) | Writing or changing tests under `test/**` |
| [Audit method](plans/AUDIT-METHOD.md) | Writing or auditing a plan in `plans/` |
| [Feature workflow contracts](doc/agents/feature-workflow-contracts.md) | Producing or consuming a workflow plan or checklist |
| [Method profile](doc/agents/method-profile.json) | Running the feature workflow or the citation checker: the project facts the audit method reads (code paths, gates, modules, lens addenda, ranking criteria, citation settings) |

## The feature workflow

`feature-implementation` (`.claude/workflows/`) runs the whole cycle as agents:
draft, the standard critic lenses in parallel at decision level, revise, a
fresh angle, a kept trial, approve, checklist, implement, and a review by an
agent that never reads the plan. The lenses, the finding kinds and the loop
rules are `plans/AUDIT-METHOD.md` sections 12 to 16; approval requires a clean
standard round AND a clean fresh angle, because section 6 rejects a single
clean pass as evidence. A revision re-runs the lenses that raised a failing
finding, plus a consistency lens that diffs the revision's snapshot. The
project's facts come from `doc/agents/method-profile.json`.

Start it with `/feature-start`, which builds the args and gates on confirmation;
check on it with `/feature-status`. It is not the default path: its agent cost
is stated in `doc/agents/feature-workflow-contracts.md` section 10. Use it for
changes that span layers and carry real interaction risk, and write the plan by
hand for anything smaller. The skill's first step is a table for that decision.
After any change to the workflow, its agents, its skills or its contracts, run
`node .claude/workflows/feature-implementation.harness.mjs`: it runs the script
against scripted agents and checks the documents that restate it.

## Plans and audits

Design and implementation plans live in `plans/` as `YYYY-MM-DD-<topic>-plan.md`.

**Before writing OR auditing one, read `plans/AUDIT-METHOD.md` first.** It is
the house method, derived from multi-round audits, and it is not
reconstructable by reasoning: it carries the angle list to sweep, the stopping
rule (two clean passes measure the lens, not the artifact), the one-normative-site
rule, the requirement that counts and universal claims carry the command that
establishes them, the trial discipline (apply the fix, run the gates, keep the
diff), decisions as ranking tables of alternatives, the finding kinds (only
design-level findings fail a round), the loop rules that re-rank a decision
whose fixes keep failing, and the rule that consumers are verified in code.
Auditing without it reliably produces a plan that reads correct and fails on
contact. It is project-neutral; this project's facts are in
`doc/agents/method-profile.json`.

A plan follows the same conciseness rules as an answer to the user ("Response
style" above): it describes the feature, its goals and its design as they will
be built, and nothing an implementer or reviewer does not need. Revision
history, earlier drafts and past mistakes belong in the plan's audit file, never
in the plan (`plans/AUDIT-METHOD.md` rule 3.7).

Plan citations are bare `path:line`. A generated ledger beside the plan records
the TEXT each cited line held when it was read, so a check can tell whether the
code under a claim has changed since. The line number is a pointer, correct as
of the plan's last audit; the recorded text is the anchor.

```bash
python plans/check_citations.py plans/<plan>.md               # verify
python plans/check_citations.py plans/<plan>.md --update      # record a new plan
python plans/check_citations.py plans/<plan>.md --record-new  # record added citations
python plans/check_citations.py plans/<plan>.md --accept <path:line> ...
```

Verify sorts each citation into OK, MOVED (the recorded text is elsewhere in
the file) or GONE (it is nowhere in the file), and fails only on GONE, an
unrecorded citation or an unresolved path. A MOVED citation needs nothing: the
code under its claim still exists.

Check a plan's citations when you are about to rely on it: when you write or
revise it, at the start of each audit round on it, and before implementing it.
Every GONE citation at that point is a finding: re-read the code, correct the
claim and its line number, then `--accept` it. Do not re-check or repoint other
plans after a change under `lib/`; a line number that drifts between landings
costs nothing until its plan is picked up. `--repoint` still renumbers the
MOVED citations of the plan in hand for a reader, and nothing requires it.

`--update` refuses a plan that already has a ledger: it re-records whatever
sits at the stated line numbers, so on drifted code it would anchor every moved
citation to the wrong text and then report clean. Never delete a ledger to get
past a failing check.

A LANDED plan's citations describe a tree that no longer exists. Retire its
ledger by renaming it to `<plan>.md.citations.tsv.retired`, and say in the plan
which tree its citations are against.

Spell each cited path one way: repo files by bare filename (`render_sliver_tree.dart:4215`),
or by repository path when the bare name is not unique or the path starts with a
dot (`.claude/agents/plan-critic.md:88`); Flutter SDK files as
`<subdir>/<file>.dart:NNN` (`rendering/viewport.dart:973`). The checker reads the
extensions the profile's `citations` block lists; an extensionless path such as
`.gitignore` is outside it, so read such a citation by hand. A bare `` `:123` ``
continuation attaches to the last file named in full. After a citation whose
extension the profile does not list, the checker reports it as DANGLING; after a
file named only in prose, it silently misattributes, so do not write one there.
