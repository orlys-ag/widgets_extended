# AGENTS.md

Canonical agent instructions for this repository. Other agent tools read
this file directly; Claude Code reaches it by importing it from
`CLAUDE.md`. Edit this file for anything that should apply to every agent,
and keep it self-contained: do not use import directives here, because not
every tool that reads this file expands them.

## Project Overview

A Flutter package (`widgets_extended`) providing rich utility widgets. Two modules:

- **sliver_tree**: a high-performance sliver-based tree widget with animated expand/collapse, FLIP reorder slides, node diffing, drag-and-drop reordering, and sticky headers.
- **sectioned_sliver_list**: a sectioned list (sections + items) built on top of the sliver_tree stack (`SectionedListController` wraps a `TreeController` + `TreeSyncController` with section/item-typed keys).

The barrel file `lib/widgets_extended.dart` re-exports both modules.

## Commands

```bash
# Run all tests
flutter test

# Run a single test file
flutter test test/sliver_tree/tree_controller_test.dart

# Analyze (lint)
flutter analyze
```

## Code Quality
- Always take a research-first approach: read the code before describing it. See "Verified claims".
- Prefer correct, complete implementations over minimal ones.
- Use appropriate data structures and algorithms; don't brute-force what has a known better solution.
- When fixing a bug, fix the root cause, not the symptom.
- If something I asked for requires error handling or validation to work reliably, include it without asking.
- Do not be biased. Disagree with the user on any claims that are wrong. Be brutally honest at all times.

## Verified claims

Never assert anything about code, APIs, or behavior that you have not checked in this session. This applies equally to chat replies, plans, design documents, audits, code comments, and commit messages.

- **Cite what you assert.** A claim about existing code carries the `file:line` you actually read. No citation means it was not verified, which means it does not get written.
- **Counts come from commands.** Files affected, tests affected, call sites, "N places do X", how much work something is: run the search and use its output. Never approximate a number you could have measured.
- **Framework behavior is read, not recalled.** What a widget builds, what a recognizer fires on disposal, what a default resolves to: verify against the Flutter or Dart source before stating it. Recall of framework internals is a hypothesis, not a fact.
- **Before changing a shared declaration, enumerate its users.** Interfaces, abstract classes, mixins, exported symbols: list every implementer and call site, including tests, before proposing or making the change.
- **Do not invent risks.** A regression, hazard, or failure mode is either demonstrated (a failing test, a traced code path) or labelled unverified. A plausible-sounding risk stated as a finding costs more time than it saves.
- **Tool and subagent output is a lead, not a finding.** Confirm it against the source yourself before repeating it as established.
- **Causal clauses carry their own citation.** A "because", "so", "therefore", or any statement of what the framework does is the highest-risk claim in a write-up, not the lowest. Observing an outcome does not license explaining it: cite the line that states the mechanism, or delete the clause. Absolutes ("never", "only", "exactly", "cannot", "every") get the same treatment. Put the citation immediately after the claim it supports rather than elsewhere in the sentence, so a reader can tell which claim it backs.
- **Do not claim a plan, an audit, or a colleague got something wrong until you have run their check.** If their statement was verified and yours is inferred, theirs stands. This is the one error that also destroys someone else's correct work, so it carries the strictest bar.
- **Keep write-ups short enough to verify.** A status note or summary says what changed, what was checked, and how it was checked. Every additional explanatory sentence is another claim that someone has to verify, so length is a cost, not a sign of rigor.

When something is unverified and still worth saying, mark it in the sentence that carries it: "unverified", "I have not checked this", "this needs a test". A stated gap is useful. A confident guess is a defect, and it is worse than saying nothing, because it reads exactly like a fact.

Prefer running the check to reasoning toward the answer. A grep, a test run, or `flutter analyze` settles a mechanical question faster and more reliably than argument does. When a change is small and its failure modes are compile errors or failing tests, implement it rather than reason further about it.

## Code Style

- Always use double quotes `"` for string literals, except for imports; use single quotes `'` on imports.
- Always create braces for code blocks.
- Always use block bodies where possible.
- Never use em-dashes, en-dashes, icons, emoji, or any other non-plain-text symbol (arrows, bullets beyond Markdown's own `-`, trademark, copyright, registered, degree, etc.) in code, comments, documentation, changelogs, commit messages, or chat replies. Use plain ASCII punctuation: a colon, semicolon, comma, parenthesis, or a separate sentence in place of a dash.
- Never add Claude, Claude Code, or Anthropic as a co-author, author, or attribution anywhere. No `Co-Authored-By` trailers, no "Generated with" lines in commit messages, PR descriptions, changelogs, or file headers.

## Guidance map

Loaded on demand. Claude Code also loads the first two automatically
via `.claude/rules/`, scoped to the paths they govern; other agent
tools should read them when the When column applies.

| Read | When |
|---|---|
| [sliver_tree architecture](doc/agents/sliver-tree-architecture.md) | Editing `lib/sliver_tree/**` or `lib/sectioned_sliver_list/**` |
| [Testing patterns](doc/agents/testing-patterns.md) | Writing or changing tests under `test/**` |
| [Audit method](plans/AUDIT-METHOD.md) | Writing or auditing a plan in `plans/` |
| [Feature workflow contracts](doc/agents/feature-workflow-contracts.md) | Producing or consuming a workflow plan or checklist |

## The feature workflow

`feature-implementation` (`.claude/workflows/`) runs the whole cycle as agents:
draft, five critic lenses in parallel, revise, a fresh angle, a kept trial,
approve, checklist, implement. The five lenses are the audit angle list from
`plans/AUDIT-METHOD.md` section 2, merged, and approval requires a clean
standard sweep AND a clean fresh angle, because section 6 rejects a single
clean pass as evidence. A revision re-runs the lenses that reported blocking
and any that failed to report, plus a consistency lens that guards the ones it
skipped.

Start it with `/feature-start`, which builds the args and gates on confirmation;
check on it with `/feature-status`. It is not the default path: a clean run is
11 agents, and a revision adds 3 to 7 depending on how many lenses reported
blocking. Use it for changes that span layers and carry real interaction risk,
and write the plan by hand for anything smaller. The skill's first step is a
table for that decision.

## Plans and audits

Design and implementation plans live in `plans/` as `YYYY-MM-DD-<topic>-plan.md`.

**Before writing OR auditing one, read `plans/AUDIT-METHOD.md` first.** It is
the house method, derived from two multi-round audits, and it is not
reconstructable by reasoning: it carries the angle list to sweep, the stopping
rule (two clean passes measure the lens, not the artifact), the one-normative-site
rule, the requirement that counts and universal claims carry the command that
establishes them, and the trial discipline (apply the fix, run the gates, keep
the diff). Auditing without it reliably produces a plan that reads correct and
fails on contact.

Plan citations are bare `path:line` and are verified by a generated ledger, not
by eye. The ledger records the TEXT at each cited line, so `--update` re-records
whatever currently sits at the line numbers the plan states. It does not follow
a construct that moved. That makes the order matter, and it differs by what
changed:

```bash
python plans/check_citations.py plans/<plan>.md            # verify, non-zero on a miss
python plans/check_citations.py plans/<plan>.md --repoint  # fix lines that moved
python plans/check_citations.py plans/<plan>.md --update   # (re)record
```

- **After any change under `lib/`**: `--repoint`. Your edit shifted every
  citation below it, and almost all of that is a stale NUMBER against text that
  still exists. `--repoint` rewrites those line numbers to where the recorded
  text actually is, and moves a citation ONLY when that text is found at exactly
  one place. It backs up the plan and the ledger first.
- **After adding citations to a plan**: `--update`, then verify.

What `--repoint` deliberately leaves behind is the point of the whole tool.
A citation whose recorded text is now GONE, or now appears at several lines,
keeps its old entry and keeps reporting as drifted. Those are the ones where
the plan may actually be wrong, and they need a human.

Never reach for `--update` to make a failing check pass. It re-records whatever
currently sits at the line numbers the plan states, so on drifted code it
anchors every citation to the wrong text and then reports a clean ledger,
including the ones `--repoint` refused to touch. That is unrecoverable without
going back through git history for the tree the ledger was recorded against.

A LANDED plan is a different case: its citations describe a tree that no longer
exists, so drift is expected forever and checking it is noise. Retire it by
renaming the ledger to `<plan>.md.citations.tsv.retired`, and say in the plan
which commit its citations are against. The `.retired` suffix is what stops
both the checker and the Stop hook from globbing it.

Spell each cited path one way: repo files by bare filename (`render_sliver_tree.dart:4215`),
Flutter SDK files as `<subdir>/<file>.dart:NNN` (`rendering/viewport.dart:973`). A
bare `` `:123` `` continuation attaches to the last file named in full, so naming a
file in prose and then citing bare lines silently misattributes them.
