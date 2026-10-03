# Feature workflow file contracts

Source of truth for the file formats the `feature-implementation` workflow
produces and consumes. If an agent's behaviour contradicts this document, the
agent is wrong: change the agent, not this file, unless the change is a
deliberate contract evolution, in which case every consumer moves in the same
edit.

Ported from a working Unity implementation on 2026-08-29 and adapted. The
adaptations that matter are recorded in section 10, because a reader who knows
the original will otherwise assume the differences are drift.

## 1. File naming

House convention (`AGENTS.md`, "Plans and audits") is
`plans/YYYY-MM-DD-<topic>-plan.md`, so:

| Artifact | Path |
|---|---|
| Plan | `plans/<date>-<slug>-plan.md` |
| Checklist | `plans/<date>-<slug>-checklist.md` |
| Superseded checklist | `plans/<date>-<slug>-checklist.superseded-<n>.md`, the first free `n` (section 4) |
| Citation ledger | `plans/<date>-<slug>-plan.md.citations.tsv` |
| Audit file | `plans/<date>-<slug>-audit.md` (section 3) |
| Revision snapshot | `plans/<date>-<slug>-plan.md.r<N>`, the first free `N` |
| Acceptance document | `plans/<date>-<slug>-acceptance.md` (section 10) |
| Trial branch | `<slug>-trial`, or the first free `-2`, `-3` suffix (section 9) |

`<date>` is `YYYY-MM-DD`. `<slug>` is kebab-case. `plans/` is gitignored except
`AUDIT-METHOD.md` and `check_citations.py`, so these artifacts stay local by
design; the trial branch is what leaves the machine. The project profile the
workflow reads is `doc/agents/method-profile.json`.

## 2. PLAN-STATUS state machine

The first non-empty line of every plan MUST be:

```
<!-- PLAN-STATUS: <value> -->
```

| Value | Meaning |
|---|---|
| `draft` | Initial state, or post-revision pre-approval. Critics may critique; checklist generation refuses. |
| `ready-to-implement` | A standard round returned no failing finding AND the fresh angle then came back clean on its first pass (`plans/AUDIT-METHOD.md` sections 6 and 12). Checklist generation proceeds. |

| From | To | Trigger | Performed by |
|---|---|---|---|
| (none) | `draft` | Initial draft mode | `plan-architect` |
| `draft` | `draft` | Revision mode | `plan-architect` |
| `draft` | `ready-to-implement` | Approval-stamp mode | `plan-architect` |
| `ready-to-implement` | `draft` | Revision mode on an approved plan (a reopen, from `priorFindings`) | `plan-architect` |

A plan whose ledger is retired has landed and is not reopened: `feature-start`
refuses `priorFindings` on it, and a later change is a successor plan that
cites it.

No other agent changes PLAN-STATUS, and no other values are valid.

## 3. Plan body requirements

Every H2 section is followed immediately by an anchor:

```markdown
## Public Surface
<a id="public-surface"></a>
```

### Anchor slug algorithm (deterministic)

1. Lowercase the heading text.
2. Replace each run of one or more non-alphanumeric characters with a single
   hyphen.
3. Trim leading and trailing hyphens.

Regex form: `heading.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")`.

GitHub's own algorithm differs. Ours is the contract, because the checklist
links to these slugs and a mismatch breaks navigation silently.

### Required sections, in order

| # | Heading | Slug | Carries |
|---|---|---|---|
| 1 | `Overview` | `overview` | 2 to 3 sentences, a pointer to the key decisions, and every file created or modified |
| 2 | `Goals & Non-Goals` | `goals-non-goals` | Non-goals prevent scope creep |
| 3 | `Decisions` | `decisions` | One subsection per architecture, performance or algorithm choice, anchored `d<N>`: the decision and its ranking table, per `plans/AUDIT-METHOD.md` section 11 |
| 4 | `Public Surface` | `public-surface` | Per `AUDIT-METHOD.md` 3.5: name, signature, where it lives, and whether it is exported. This package exports through explicit `show` clauses, so an undeclared symbol is unnameable by app code |
| 5 | `Components & State` | `components-state` | New per-nid arrays (sliver_tree) or per-id store arrays (board), controller fields, parent-data fields: exact name, type, growth path (`onCapacityGrew` in sliver_tree; the store's lockstep growth in board), and who writes each |
| 6 | `Coordinate Spaces` | `coordinate-spaces` | Every geometric value the plan introduces, tagged with its space: in sliver_tree one of the three (sliver scroll, sliver paint, viewport scroll), in board content, viewport-paint, or track space. A plan that does not tag them is incomplete, not merely terse |
| 7 | `Invariants & Pair Rules` | `invariants-pair-rules` | Every invariant preserved, and every PAIR whose halves must read the same value (prune criterion and paint skip; paint gate and `applyPaintTransform`) |
| 8 | `Landing Order` | `landing-order` | Per `AUDIT-METHOD.md` 3.6: numbered, dependency-ordered. Each step names the test that goes green when it lands, or is marked NOT INDEPENDENTLY VERIFIABLE with the reason. Pure restructuring lands first, in its own commit |
| 9 | `Testing Plan` | `testing-plan` | Exact test names, what each asserts, and the seam each attaches at. A new seam names the existing seam it rejected and why |
| 10 | `Risks & Pitfalls` | `risks-pitfalls` | Demonstrated risks only. An undemonstrated one is labelled unverified, per `AGENTS.md` |
| 11 | `Open Questions` | `open-questions` | Genuinely undecided only. Empty is desirable |

Optional, appended later:

| Heading | Slug |
|---|---|
| `Approval` | `approval` |

The plan holds what implementation needs, written as the final design and
never as its history (`plans/AUDIT-METHOD.md` rule 3.7). The record of how it
got there lives in the plan's audit file, `plans/<date>-<slug>-audit.md`, which carries no
ledger and is never the checklist's source. Each writer creates the file when
it is absent.

Audit file records, appended in order:

| Heading | Slug | Written by |
|---|---|---|
| `Round N` | `round-n` | `plan-architect`: a revision or the approval step, one record per round it received, one line per finding giving its id, lens, kind, severity and outcome (`plans/AUDIT-METHOD.md` section 12) |
| `Trial Log` | `trial-log` | `plan-implementer` in trial mode: the section trialed, the branch, the commit, and each gate's outcome |
| `Run` | `run` | `feature-start`: the commit the first launch started from (`baseRef`), and the `unrecordedFindings` of a result |

Plans written before the audit file carry their records in the plan, under an
audit-log heading. `plans/check_citations.py` treats that exact heading text as
the end of a plan's live document, an unanchored substring split, so writing
the heading text into a sentence above the section truncates verification
silently. Refer to it in words.

Note that `&` is non-alphanumeric, so `Goals & Non-Goals` collapses to
`goals-non-goals`, not `goals--non-goals` and not `goals-and-non-goals`.

## 4. CHECKLIST-STATUS state machine

The first two non-empty lines of every checklist MUST be:

```
<!-- CHECKLIST-FOR: plans/<date>-<slug>-plan.md -->
<!-- CHECKLIST-STATUS: <value> -->
```

| Value | Meaning |
|---|---|
| `pending` | One or more `- [ ]` items remain under Phase sections, or Phase 4 has not passed |
| `complete` | Every Phase 1 to 4 item is ticked AND no Discovered item has `Blocking: yes` |

| From | To | Trigger | Performed by |
|---|---|---|---|
| (none) | `pending` | Initial generation | `plan-checklist` |
| `pending` | `complete` | Last Phase 4 item ticked, no blocking Discovered | `plan-implementer` |

The CHECKLIST-FOR comment is the authoritative pairing. If it does not match the
resolved plan path, the pair is malformed and the implementer aborts.

A regenerated checklist, after a reopen, first renames the existing one to the
first free `plans/<date>-<slug>-checklist.superseded-<n>.md`, which keeps the
record of what the last checklist ticked.

## 5. Checklist body structure

```markdown
<!-- CHECKLIST-FOR: plans/2026-08-29-example-plan.md -->
<!-- CHECKLIST-STATUS: pending -->

# Implementation checklist: example

Plan: [2026-08-29-example-plan.md](2026-08-29-example-plan.md)

## Phase 1 - Foundation
<a id="phase-1-foundation"></a>
- [ ] **Add the nid-indexed band cache** - [S Components & State](2026-08-29-example-plan.md#components-state)
  - Files: `lib/sliver_tree/_animation_coordinator.dart`
  - Acceptance: `flutter test test/sliver_tree/band_cache_test.dart`

## Phase 2 - Core
<a id="phase-2-core"></a>

## Phase 3 - Integration
<a id="phase-3-integration"></a>

## Phase 4 - Verification
<a id="phase-4-verification"></a>
- [ ] **Mutation: d2's rule** - [S d2](2026-08-29-example-plan.md#d2)
  - Files: `lib/sliver_tree/_animation_coordinator.dart`
  - Acceptance: break the rule at its site; `flutter test test/sliver_tree/band_cache_test.dart`
    fails; restore; the file's `sha256sum` before and after match
- [ ] **Gate: analyze** - [S Risks & Pitfalls](2026-08-29-example-plan.md#risks-pitfalls)
  - Files: (n/a)
  - Acceptance: `flutter analyze` reports no issue beyond the count before the change
- [ ] **Gate: test** - [S Testing Plan](2026-08-29-example-plan.md#testing-plan)
  - Files: (n/a)
  - Acceptance: `flutter test`, 0 failed
- [ ] **Ledger retired** - [S Testing Plan](2026-08-29-example-plan.md#testing-plan)
  - Files: (n/a)
  - Acceptance: `plans/2026-08-29-example-plan.md.citations.tsv` is renamed to
    `.citations.tsv.retired`, and the plan says which tree its citations are against

## Discovered
<a id="discovered"></a>
```

Every Phase 1 to 4 item MUST have a bolded title, a plan link of the form
`[S <Section Name>](<plan path>#<anchor>)`, a `- Files:` sub-bullet, and a
`- Acceptance:` sub-bullet carrying a concrete checkable signal. An item that
cannot meet all four does not go in a Phase; it goes in `## Discovered` with
`Blocking: yes`.

Phase 4 is built in this order, whether or not the plan mentions it
(`plans/AUDIT-METHOD.md` section 16): one mutation item per decision whose
Components & State entry names a file under the profile's `codePaths`; one
`Gate:` item per profile gate that applies, so the suite runs after the last
restore; then the ledger item. With this project's profile that is at least
three items, which the workflow checks.

Each implementation finding the audit carried (`plans/AUDIT-METHOD.md` section
12) becomes an item in the phase its code lands in, with a test shown to fail
first, a mutation, or a code check as its acceptance; one that no longer applies
to the approved plan goes to `## Discovered` with `Blocking: no` and the reason.

## 6. Discovered item format

`## Discovered` is the single routing channel back to `plan-architect` for any
defect surfaced during checklist generation or implementation.

```markdown
- [ ] **<short title>** - <one-line summary>
  - Plan section: S<anchor-slug>
  - Files: `<paths>` or `tbd`
  - Acceptance: `<signal>` or `tbd - plan revision needed`
  - Blocking: yes | no
```

`Plan section:` is a structured field on its own line, parsed directly as the
finding's `location`. Do not embed the anchor in the title or the prose. Use
`unspecified` when no section fits.

`Blocking: yes` means implementation cannot proceed. `Blocking: no` means
nice-to-fix, so the loop does not churn on it.

## 7. Counting rules

Phase progress counts only `- [ ]` and `- [x]` items under `## Phase 1` through
`## Phase 4`. Items under `## Discovered` are never counted toward progress.
The blocker count is `## Discovered` items with `Blocking: yes`.

## 8. Concurrency

Two concurrent runs against the same `<slug>` are not supported. The
`feature-start` skill is responsible for collision detection: it refuses when a
plan for that slug already exists.

## 9. Trials

A trial is `AUDIT-METHOD.md` section 10 applied by an agent rather than by hand.
It runs after the fresh-angle round comes back clean and before the approval
stamp, on a branch named `<slug>-trial` cut from the current HEAD. Confirming a
run in `feature-start` authorizes the trial commit; nothing else in the run
commits.

A trial is KEPT. Passing or failing, the diff is committed on that branch, and
the audit file records the outcome in its `Trial Log` record (section 3).
Nothing is reverted to restore a clean tree. A trial passes when its repro fails
before and passes after, and every profile gate that applies passes; it reports
every profile gate by name in the `gates` field of its result, and a gate it
does not report is a gate nobody ran.

A failed trial is a blocking finding routed back to the planner, because a plan
whose text reads correctly and whose code does not is the failure mode trials
exist to catch.

**The branch name is reported, not assumed.** Keeping a failed trial's branch
collides with the next run's `git switch -c <slug>-trial`, which refuses an
existing branch, so the trial falls back to `<slug>-trial-2`, then `-3`. Every
later phase reads the name from the trial's `branch` field. A phase that
hardcodes `<slug>-trial` points the implementer at a branch that may not exist.

**The trial requires a clean tree and branches from it.** `git switch` carries
uncommitted work onto the new branch, so a dirty code path lands inside the
trial commit and the diff stops being "exactly the plan section applied", which
is the only property that makes a trial evidence. The implementer runs
`git status --porcelain` over the profile's `codePaths` before branching and
reports a dirty tree as a blocking finding rather than stashing someone else's
work. It stages by path, because `git commit -a` would leave a new untracked
repro test out of the commit that must carry it.

**A trial leaves the plan's citations alone, and the approval stamp does not
demand a clean check.** The trial changes code on its branch, so the check run
at approval reads the trial's code: MOVED citations there are nothing, and a GONE
one is evidence that the trial changed code the plan cites, which the approval
step records rather than clears.

**`plan-implementer` never writes the plan.** Its one write outside code, tests
and the checklist is the trial's `Trial Log` record in the audit file.

## 10. Adaptations from the source implementation

Recorded so the differences are not mistaken for drift.

- **The lens set is the audit method's.** The source used six Unity-specific
  lenses. Ours are `AUDIT-METHOD.md` section 13's: three standard lenses that
  judge at decision level, two fresh angles, and the consistency lens, with the
  project's addendum and reading list for each in the profile. A second
  taxonomy for "what to examine" would be a second normative site, which
  section 3.1 forbids.
- **The stopping rule is the audit method's, not the source's.** The source
  approved a plan on one clean round. `AUDIT-METHOD.md` section 6 rejects that
  shape outright, because consecutive clean passes measure the lens rather than
  the artifact. Ours requires a clean standard round AND a clean fresh angle,
  which is section 6's "a freshly opened angle came back clean on its first
  pass" mechanized. ONE fresh lens runs per round, because that clause is
  singular, and it is drawn from a POOL and spent after one use. FIRST is the
  load-bearing word: a lens that failed a round, saw a revision, and then
  cleared has come back clean on its SECOND pass, which is the shape section 6
  rejects. The pool is `AUDIT-METHOD.md` section 8's two named unsettleable
  classes, `interaction` then `timing`, in its order. A third entry would be
  invented rather than derived, so an exhausted pool returns
  `fresh-angles-exhausted` and leaves the plan in draft for a human to open a
  new angle or to accept it under section 6's yield rule.
- **A revision re-runs the lenses that raised a failing finding**, plus the
  `consistency` lens. Re-running a lens that CLEARED a section the revision did
  not touch is spend without coverage. The consistency lens is what makes the
  skip safe rather than a shortcut: it owns the revision's own damage, which
  `AUDIT-METHOD.md` names as the second most common defect class, and it diffs
  the revision's snapshot against the findings and obligations the revision
  was given (`AUDIT-METHOD.md` section 14). A lens that does not report is
  dispatched once more, and one that still cannot review ends the run.
- **Critics read only what their lens needs.** Parallel critics each loading
  the 20KB architecture document is the largest avoidable cost in a run, so
  each lens's reading list comes from the profile, and a consumer is verified
  by reading the code that uses it rather than a whole document.
- **The run is module-scoped.** `args.module`, derived through the profile's
  module path patterns from `modules_touched` when omitted and required when
  those paths name more than one module or none, selects the architecture
  document every lens reading list and every architect, trial and implementer
  prompt names, and adds one module-vocabulary line to each prompt. Before
  this, every lens read the sliver_tree document for a board plan, which is the
  wrong contract for the design lens and dead context for the rest.
- **The project's facts live in the profile.** `feature-start` reads
  `doc/agents/method-profile.json` and passes it as `args.profile`, because the
  workflow scope has no file access; the script validates it and takes the
  modules, the lens addenda and reading lists, the gates, the code paths, the
  defect classes and the ranking criteria from it.
- **A trial phase exists.** The source had none. See section 9.
- **A blind acceptance review closes the run.** The source's Gate 4 is the
  `acceptance-reviewer` agent: it gets the request and the acceptance criteria
  verbatim, the commit the run started from and the files the implementer
  reports it changed, reads nothing else under `plans/`, and writes the
  acceptance document. Gaps go to the owner.
- **Citations are ledgered, not eyeballed.** Critics verify `path:line`
  citations against the code, the check fails only on a citation whose recorded
  text is gone from its file, and Phase 4 retires the ledger of the plan that
  just landed instead of re-anchoring it.
- **`feature-resume` was not ported.** The source routes `Discovered` items back
  to the planner through a generated temporary workflow. Re-run
  `feature-implementation` with the `Discovered` items passed as
  `args.priorFindings` instead; the workflow accepts them and enters at the
  revision phase, which reopens an approved plan (section 2).
- **The cost.** A clean run is 10 agents: the draft, three critics, one fresh
  angle, the trial, the approval stamp, the checklist, the implementer and the
  acceptance reviewer. A revision round adds 2 to 6: the architect, the
  consistency lens, the standard lenses that failed, and a fresh angle when
  they all clear. At the default budget of 4 rounds the critique phase spawns
  at most 20 agents, plus 5 to close, and each lens dispatched a second time
  adds 1. This is the one site of these numbers; `AGENTS.md` and
  `feature-start` refer here, and the workflow harness checks the clean-run
  count against the script.

## 11. Model assignment

Set in each agent's frontmatter, so a run is reproducible when the session model
changes. The table below is each agent's model and effort; the workflow harness
checks it against the frontmatter.

**The workflow defers to the frontmatter and must keep doing so.** All eight
`agent()` call sites pass only `agentType`, `label`, `phase` and `schema`, never
`opts.model` or `opts.effort`. Duplicating those into the script would make
retuning one agent an edit to the orchestrator, and would leave the frontmatter
as a decoy that no longer describes what runs. It is the second normative site
that 3.1 forbids, and it is not a hedge worth taking.

A definition's model does beat the session model on the Agent tool path, which
is what `agentType` resolves against. Across 222 subagent transcripts under
`~/.claude/projects/C--flutter-sdk-projects-widgets-extended`,
`claude-code-guide` ran on `claude-haiku-4-5-20251001` and `codex:codex-rescue`
on `claude-sonnet-5`, in the same sessions where every `general-purpose`,
`Explore` and `Plan` agent ran on the session's own model.

Observed on the workflow path on 2026-09-05 (run `wf_b478c79b-2fc`, the
lane span expansion feature): every agent transcript under
`subagents/` records `message.model` as `claude-opus-5` and the effort the
agent's frontmatter sets (`xhigh` for the architect, critics and
implementer, `medium` for the checklist agent), in a session whose own model
was `claude-fable-5-1`. The frontmatter wins there too. Whether the model IDs
in the table below resolve in frontmatter is unverified until the first run
under them: every subagent transcript records `message.model` and a top-level
`effort`, so reading `~/.claude/projects/<project>/<session>/subagents/*.jsonl`
afterwards says which model and effort each agent actually used. If
frontmatter turns out to lose, the fix is to raise it as a harness bug, not to
hardcode the values in the script.

| Agent | Model | Effort | Why that model and effort |
|---|---|---|---|
| `plan-architect` | `claude-opus-5-5[1m]` | `xhigh` | Writes the design and every citation in it |
| `plan-critic` | `claude-opus-5-5[1m]` | `xhigh` | Adversarial review. A missed defect costs a revision round plus whatever it does downstream |
| `plan-implementer` | `claude-opus-5-5[1m]` | `xhigh` | Writes code and diagnoses failing gates |
| `acceptance-reviewer` | `claude-opus-5-5[1m]` | `xhigh` | Judges the result against the request with no plan to lean on |
| `plan-checklist` | `claude-sonnet-5-5` | `medium` | Mechanical transform of an already-approved plan into phased items. It decides nothing |

The `plan-checklist` exception is the owner's decision, and three things bound
its risk: the agent decides nothing, the script rejects a malformed checklist,
and the implementer runs every acceptance signal before it ticks an item. Its
`medium` effort follows Anthropic's own precedent: in the `claude-security`
plugin, six agents that research, generate or verify are set to
`effort: xhigh`, while `scan-inventory`, described as a "repository
cartographer" that partitions a tree and accounts for directories, is set to
`medium`. Our checklist agent is the same shape: it partitions an approved plan.
Raise its model or effort if checklists start arriving with weak acceptance
signals, since that is the failure this would cause.

Setting `effort` explicitly also removes a dependency on inheritance. Without
the key an agent falls back to the session or `modelSettings` value, and whether
a subagent reads the user-level `effortLevel` was not verified when this was
written.

The two skills carry no `model` key: they run in the main loop, so they use
whatever the session is on.

Every agent that decides or reviews runs the frontier model, the owner's
decision: a critic that misses a real defect costs a revision round plus
whatever the defect does downstream, which is worth more than the difference in
tier. The consequence to plan for is that every critic in a round is a frontier
call, and the parallel critics are simultaneous ones, so the per-lens reading
lists in the profile are the ONLY mechanism holding critic context down. Do not
widen a lens's `reads` without a reason: it is paid once per critic in the same
round.

## 12. Agent memory

Only `plan-architect` and `plan-implementer` keep persistent memory
(`memory: project` in their frontmatter, under `.claude/agent-memory/<agent>/`).
The critics, the checklist agent and the acceptance reviewer keep none: a
critic's value is a fresh look each round, the reviewer's is independence from
everything before it, and the checklist agent performs a mechanical transform.

Memory holds only lessons that will help on a different feature: how to do the
job (method, tools, test technique), or a recurring trap in one module's code.

- Each index line in `MEMORY.md` starts with its scope: `[general]`, or
  `[<module>]` with a module key from the profile. An agent reads the
  `[general]` lines and those of the module its prompt names.
- Nothing about one feature, plan, round or commit is recorded: that belongs
  in the feature's audit file.
- Memory refers to code by symbol and file name, never by `file:line`, because
  nothing re-checks a line number in memory.
- An index has at most 30 lines.

The workflow harness checks these rules on every run, and checks that no
agent without memory has a memory directory.
