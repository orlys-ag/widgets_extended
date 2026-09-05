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
| Citation ledger | `plans/<date>-<slug>-plan.md.citations.tsv` |
| Trial branch | `<slug>-trial`, or the first free `-2`, `-3` suffix (section 9) |

`<date>` is `YYYY-MM-DD`. `<slug>` is kebab-case. `plans/` is gitignored except
`AUDIT-METHOD.md` and `check_citations.py`, so these artifacts stay local by
design; the trial branch is what leaves the machine.

## 2. PLAN-STATUS state machine

The first non-empty line of every plan MUST be:

```
<!-- PLAN-STATUS: <value> -->
```

| Value | Meaning |
|---|---|
| `draft` | Initial state, or post-revision pre-approval. Critics may critique; checklist generation refuses. |
| `ready-to-implement` | Every lens returned zero blocking findings in the standard round AND in the fresh-angle round. Checklist generation proceeds. |

| From | To | Trigger | Performed by |
|---|---|---|---|
| (none) | `draft` | Initial draft mode | `plan-architect` |
| `draft` | `draft` | Revision mode | `plan-architect` |
| `draft` | `ready-to-implement` | Approval-stamp mode | `plan-architect` |

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
| 1 | `Overview` | `overview` | 2 to 3 sentences, the key decisions with one-line rationale, and every file created or modified |
| 2 | `Goals & Non-Goals` | `goals-non-goals` | Non-goals prevent scope creep |
| 3 | `Public Surface` | `public-surface` | Per `AUDIT-METHOD.md` 3.5: name, signature, where it lives, and whether it is exported. This package exports through explicit `show` clauses, so an undeclared symbol is unnameable by app code |
| 4 | `Components & State` | `components-state` | New per-nid arrays (sliver_tree) or per-id store arrays (board), controller fields, parent-data fields: exact name, type, growth path (`onCapacityGrew` in sliver_tree; the store's lockstep growth in board), and who writes each |
| 5 | `Coordinate Spaces` | `coordinate-spaces` | Every geometric value the plan introduces, tagged with its space: in sliver_tree one of the three (sliver scroll, sliver paint, viewport scroll), in board content, viewport-paint, or track space. A plan that does not tag them is incomplete, not merely terse |
| 6 | `Invariants & Pair Rules` | `invariants-pair-rules` | Every invariant preserved, and every PAIR whose halves must read the same value (prune criterion and paint skip; paint gate and `applyPaintTransform`) |
| 7 | `Landing Order` | `landing-order` | Per `AUDIT-METHOD.md` 3.6: numbered, dependency-ordered. Each step names the test that goes green when it lands, or is marked NOT INDEPENDENTLY VERIFIABLE with the reason. Pure restructuring lands first, in its own commit |
| 8 | `Testing Plan` | `testing-plan` | Exact test names, what each asserts, and the seam each attaches at. A new seam names the existing seam it rejected and why |
| 9 | `Risks & Pitfalls` | `risks-pitfalls` | Demonstrated risks only. An undemonstrated one is labelled unverified, per `AGENTS.md` |
| 10 | `Open Questions` | `open-questions` | Genuinely undecided only. Empty is desirable |

Optional, appended later:

| Heading | Slug |
|---|---|
| `Audit log` | `audit-log` |
| `Round N Revision` | `round-2-revision` |
| `Trial Log` | `trial-log` |
| `Approval` | `approval` |

The first of those is not an ordinary section: `plans/check_citations.py`
treats that exact heading text as the end of the live document and verifies no
citation at or below it, so a plan that adds it puts its round records under it
and keeps every live rule above it. The match is an unanchored substring split,
so writing that heading text into a sentence above the section truncates
verification silently and still exits 0. Refer to the section in words when
prose has to mention it.

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
- [ ] **Analyzer clean** - [S Risks & Pitfalls](2026-08-29-example-plan.md#risks-pitfalls)
  - Files: (n/a)
  - Acceptance: `flutter analyze` reports no new issues in `lib/`
- [ ] **Full suite green** - [S Testing Plan](2026-08-29-example-plan.md#testing-plan)
  - Files: (n/a)
  - Acceptance: `flutter test`
- [ ] **Citations re-anchored** - [S Testing Plan](2026-08-29-example-plan.md#testing-plan)
  - Files: (n/a)
  - Acceptance: `python plans/check_citations.py plans/2026-08-29-example-plan.md --repoint`
    leaves no drifted citations; whatever it cannot place is a finding, and `--update`
    is never used to force it green

## Discovered
<a id="discovered"></a>
```

Every Phase 1 to 4 item MUST have a bolded title, a plan link of the form
`[S <Section Name>](<plan path>#<anchor>)`, a `- Files:` sub-bullet, and a
`- Acceptance:` sub-bullet carrying a concrete checkable signal. An item that
cannot meet all four does not go in a Phase; it goes in `## Discovered` with
`Blocking: yes`.

Phase 4 always ends with the three verification items above. They are the gates
`AUDIT-METHOD.md` section 10 names, and the checklist agent adds them whether or
not the plan mentions them.

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
stamp, on a branch named `<slug>-trial` cut from the current HEAD.

A trial is KEPT. Passing or failing, the diff is committed on that branch, and
the plan records the outcome in `## Trial Log`. Nothing is reverted to restore a
clean tree. The gates are the three from section 10 of the audit method: the
repro fails before and passes after, `flutter analyze` reports no new issues in
`lib/`, and `flutter test` is green.

A failed trial is a blocking finding routed back to the planner, because a plan
whose text reads correctly and whose code does not is the failure mode trials
exist to catch.

**The branch name is reported, not assumed.** Keeping a failed trial's branch
collides with the next run's `git switch -c <slug>-trial`, which refuses an
existing branch, so the trial falls back to `<slug>-trial-2`, then `-3`. Every
later phase reads the name from the trial's `branch` field. A phase that
hardcodes `<slug>-trial` points the implementer at a branch that may not exist.

**The trial requires a clean tree and branches from it.** `git switch` carries
uncommitted work onto the new branch, so a dirty `lib/` or `test/` lands inside
the trial commit and the diff stops being "exactly the plan section applied",
which is the only property that makes a trial evidence. The implementer checks
`git status --porcelain lib test` before branching and reports a dirty tree as a
blocking finding rather than stashing someone else's work. It stages by path,
because `git commit -a` would leave a new untracked repro test out of the commit
that must carry it.

**A trial drifts the plan's citations, and the approval stamp does not demand
zero.** The trial runs `--repoint`, which re-anchors what it can find and leaves
the rest reporting. What it leaves is evidence that the trial's change deleted or
duplicated cited code, so the approval step records it instead of clearing it.
Requiring `check_citations.py` to exit 0 at approval would push the architect
toward `--update`, which re-anchors every citation to whatever moved into place
and then reports clean.

**Appending `## Trial Log` is one of two plan writes `plan-implementer`
performs**, the other being the citation re-anchor above.
Its system prompt otherwise forbids modifying the plan, and this exception is
stated in both places: here, and in that agent's trial-mode section. Scoped to
appending that section, never to PLAN-STATUS, and never to another line.

## 10. Adaptations from the source implementation

Recorded so the differences are not mistaken for drift.

- **The lens set is the audit angle list.** The source used six Unity-specific
  lenses. Ours are five, and they are `AUDIT-METHOD.md` section 2's ten angles
  merged onto five agents. This is deliberate: a second taxonomy for "what to
  examine" would be a second normative site, which section 3.1 forbids.
- **The stopping rule is the audit method's, not the source's.** The source
  approved a plan on one clean round. `AUDIT-METHOD.md` section 6 rejects that
  shape outright, because consecutive clean passes measure the lens rather than
  the artifact. Ours requires a clean standard sweep AND a clean fresh angle,
  which is section 6's "a freshly opened angle came back empty on its first
  pass" mechanized. ONE fresh lens runs per round, because that clause is
  singular, and it is drawn from a POOL and spent after one use. FIRST is the
  load-bearing word: a lens that blocked, saw a revision, and then cleared has
  come back empty on its SECOND pass, which is the shape section 6 rejects. The
  pool is `AUDIT-METHOD.md` section 8's two named unsettleable classes,
  `interaction` then `timing`, in its order. A third entry would be invented
  rather than derived, so an exhausted pool returns `fresh-angles-exhausted`
  and leaves the plan in draft for a human to open a new angle or to accept it
  under section 6's yield rule.
- **A revision re-runs the lenses that reported blocking and the lenses that
  did not report**, plus a `consistency` lens. Re-running a lens that CLEARED a
  section the revision did not touch is spend without coverage. A lens that
  never reported is different: it swept nothing, so dropping it retires an
  angle, and the clean-round coverage guard cannot catch that because the round
  was not clean. The consistency lens is what makes the skip safe rather than a
  shortcut: it owns the revision's own damage, which
  `AUDIT-METHOD.md` names as the second most common defect class, and it reports
  a revision that edited a section outside the findings it was addressing,
  since that would invalidate a clean report from a lens not running.
- **Critics read only what their lens needs.** Five parallel critics each
  loading the 20KB architecture document is the largest avoidable cost in a
  run, so each lens declares its own reading list and the rest grep instead.
  Every agent runs on the same model (section 11), so the reading lists are the
  only thing holding critic context down.

- **The run is module-scoped.** `args.module` (`sliver_tree` or `board`),
  derived from `modules_touched` when omitted and required when those paths
  name both modules or neither, selects the architecture document every lens
  `reads` entry and every architect, trial and implementer prompt names, and
  adds one module-vocabulary line to each prompt. Before this, every lens read
  the sliver_tree document for a board plan, which is the wrong contract for
  the `contracts` lens and dead context for the rest.
- **A trial phase exists.** The source had none. See section 9.
- **Citations are ledgered, not eyeballed.** Critics verify `path:line`
  citations, and Phase 4 requires `check_citations.py` to exit 0. Implementation
  moves the lines the plan cites, so that gate is a re-anchor, not a no-op:
  `--repoint` fixes the moved line numbers and leaves the rest reporting, which
  is the signal. `--update` would pass the gate while destroying it.
- **`feature-resume` was not ported.** The source routes `Discovered` items back
  to the planner through a generated temporary workflow. Re-run
  `feature-implementation` with the `Discovered` items passed as
  `args.priorFindings` instead; the workflow accepts them and enters at the
  revision phase.

## 11. Model assignment

Set in each agent's frontmatter, so a run is reproducible when the session model
changes. All four agents declare `claude-opus-5[1m]`; reasoning effort is set
per agent with the `effort` frontmatter key.

**The workflow defers to the frontmatter and must keep doing so.** All seven
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
was `claude-fable-5-1`. The frontmatter wins there too. The paragraph below
is kept as the reasoning that predicted it. The authoring reference calls `agentType`
"resolved from the same registry as the Agent tool", which is the link; its
`opts.model` bullet separately says an agent omitting it "inherits the main-loop
model", written without an `agentType` caveat. Settle it by observation on the
first real run, not by argument: every subagent transcript records
`message.model` and a top-level `effort`, so reading
`~/.claude/projects/<project>/<session>/subagents/*.jsonl` afterwards says which
model and effort each of the eleven agents actually used. If frontmatter turns
out to lose there, the fix is to raise it as a harness bug, not to hardcode the
values here.

| Agent | Model | Effort | Why that effort |
|---|---|---|---|
| `plan-architect` | `claude-opus-5[1m]` | `xhigh` | Writes the design and every citation in it |
| `plan-critic` | `claude-opus-5[1m]` | `xhigh` | Adversarial review. A missed defect costs a revision round plus whatever it does downstream |
| `plan-implementer` | `claude-opus-5[1m]` | `xhigh` | Writes code and diagnoses failing gates |
| `plan-checklist` | `claude-opus-5[1m]` | `medium` | Mechanical transform of an already-approved plan into phased items. It decides nothing |

The `plan-checklist` exception follows Anthropic's own precedent: in the
`claude-security` plugin, six agents that research, generate or verify are set
to `effort: xhigh`, while `scan-inventory`, described as a "repository
cartographer" that partitions a tree and accounts for directories, is set to
`medium`. Our checklist agent is the same shape: it partitions an approved plan.
Raise it to `xhigh` if checklists start arriving with weak acceptance signals,
since that is the failure this would cause.

Setting `effort` explicitly also removes a dependency on inheritance. Without
the key an agent falls back to the session or `modelSettings` value, and whether
a subagent reads the user-level `effortLevel` was not verified when this was
written.

The two skills carry no `model` key: they run in the main loop, so they use
whatever the session is on.

A uniform tier was the owner's decision, taken after model tiering was proposed
and implemented. The trade it makes is explicit: a critic that misses a real
defect costs a revision round plus whatever the defect does downstream, which is
worth more than the difference in tier. The consequence to plan for is that
every one of the 11 agents in a clean run is a frontier call, and the five
parallel critics are simultaneous ones, so the per-lens reading lists in the
workflow are now the ONLY mechanism holding critic context down. Do not widen
a lens's `reads` array without a reason: at this tier it is paid five times in
the same round.
