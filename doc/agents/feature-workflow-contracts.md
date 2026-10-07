# Feature workflow contracts

The files, branches and run state of the `feature-implementation` workflow.
When an agent's behaviour contradicts this document, the agent is wrong; a
deliberate change to a format moves every producer and consumer in one edit.

## 1. Files and branches

| Artifact | Path |
|---|---|
| Plan | `plans/<date>-<slug>-plan.md` |
| Revision snapshot | `plans/<date>-<slug>-plan.md.r<N>`, the first free `N` |
| Audit file | `plans/<date>-<slug>-audit.md` (section 3) |
| Checklist | `plans/<date>-<slug>-checklist.md` |
| Superseded checklist | `plans/<date>-<slug>-checklist.superseded-<n>.md`, the first free `n` |
| Acceptance document | `plans/<date>-<slug>-acceptance.md` |
| Run record | `plans/<date>-<slug>-run.json` (section 13) |
| Citation snapshot | `refs/citations/<date>-<slug>-plan`, named by the plan's CITATIONS marker |
| Trial branch | `<slug>-trial`, or the first free `-2`, `-3` (section 9) |
| Implementation branch | `<slug>-impl`, or the first suffix no earlier version of the plan used, when no trial passed (section 9) |

`<date>` is `YYYY-MM-DD` and `<slug>` is kebab-case. Branches named `<slug>-...`
belong to the workflow. The project profile is `doc/agents/method-profile.json`.

## 2. Plan status

The plan's first non-empty line is `<!-- PLAN-STATUS: <value> -->`; the citation
checker writes the CITATIONS marker on the line after it.

| Value | Meaning |
|---|---|
| `draft` | Being written or revised. Critics may critique it; the checklist agent refuses it. |
| `ready-to-implement` | Approved: a standard round came back clean and a fresh angle then came back clean on its first pass, or the owner approved this version (`ownerApproval`, section 13). |

Only `plan-architect` changes it: the draft writes `draft`, the approval stamp
writes `ready-to-implement`, a revision of an approved plan sets it back to
`draft`, and a revision of a plan that has no status line adds it as `draft`.
A plan whose run is done is not reopened (`plans/AUDIT-METHOD.md` section 5).

## 3. Plan body and audit file

Every H2 section of a plan is followed by its anchor:

```markdown
## Public Surface
<a id="public-surface"></a>
```

The anchor is `heading.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")`,
not GitHub's algorithm; the checklist links to it.

Required sections, in order:

| # | Heading | Slug | Carries |
|---|---|---|---|
| 1 | `Overview` | `overview` | Two or three sentences, the key decisions by reference, and every file created or modified |
| 2 | `Goals & Non-Goals` | `goals-non-goals` | The goals and the non-goals |
| 3 | `Decisions` | `decisions` | One subsection per architecture, performance or algorithm choice, anchored `d<N>` (`plans/AUDIT-METHOD.md` section 2.7) |
| 4 | `Public Surface` | `public-surface` | Each public artifact added or changed: name, signature, where it lives and how it is exported |
| 5 | `Components & State` | `components-state` | New components and state: name, type, where each lives, who writes it, and how it grows and is torn down |
| 6 | `Invariants & Pair Rules` | `invariants-pair-rules` | Every invariant the change preserves, and every pair of sites that must change together |
| 7 | `Landing Order` | `landing-order` | Numbered, dependency-ordered steps (`plans/AUDIT-METHOD.md` section 2.5) |
| 8 | `Testing Plan` | `testing-plan` | Each test: its name, what it asserts and the seam it attaches at; a new seam names the existing one it rejected |
| 9 | `Risks & Pitfalls` | `risks-pitfalls` | Demonstrated risks; an undemonstrated one is labelled unverified |
| 10 | `Open Questions` | `open-questions` | Only what is genuinely undecided |

A section with nothing to say holds one line saying so. The profile's
`planRules` add the project's own requirements.

Optional, appended later:

| Heading | Slug |
|---|---|
| `Approval` | `approval` |

The audit file (`plans/AUDIT-METHOD.md` section 4) is never stamped and never
the checklist's source. Each writer creates it with a one-line title when it is
absent, and appends; no record is rewritten.

Audit file records:

| Heading | Written by | Holds |
|---|---|---|
| `Round N` | `plan-architect`, at each revision and approval step; N is the number of rounds run so far, so two records can share it | One line per finding received: its id, lens, kind, severity, outcome and the section it touched |
| `Trial Log` | `plan-implementer` in trial mode | The fields section 9 lists |
| `Run` | `feature-start` | The first launch's base commit and branch, then each result's status and the phase the next run starts at |

A plan written outside the workflow may keep these records in the plan under
`## Audit log`, where the citation checker's live text ends, until the revision
that adopts it moves them to the audit file.

## 4. Checklist status

The checklist's first two non-empty lines are:

```
<!-- CHECKLIST-FOR: plans/<date>-<slug>-plan.md -->
<!-- CHECKLIST-STATUS: <value> -->
```

The status is `pending` until every Phase 1 to 4 item is ticked and no
unticked Discovered item has `Blocking: yes`; then `plan-implementer` sets
`complete`.
CHECKLIST-FOR pairs the checklist with its plan: when it does not name the plan
path, the pair is malformed and the implementer stops without changing
anything. A regenerated checklist first renames the existing one to the
superseded path (section 1).

## 5. Checklist body

```markdown
<!-- CHECKLIST-FOR: <plan path> -->
<!-- CHECKLIST-STATUS: pending -->

# Implementation checklist: <slug>

Plan: [<plan file>](<plan file>)

## Phase 1 - Foundation
<a id="phase-1-foundation"></a>
- [ ] **<title>** - [S <Section Name>](<plan file>#<anchor>)
  - Files: `<paths>`, or (n/a)
  - Acceptance: <a named test, an exact command, or an observation and how to make it>

## Phase 2 - Core
<a id="phase-2-core"></a>

## Phase 3 - Integration
<a id="phase-3-integration"></a>

## Phase 4 - Verification
<a id="phase-4-verification"></a>
- [ ] **Mutation: dN, <the rule>** - [S dN](<plan file>#dN)
  - Files: `<the rule's code site>`
  - Acceptance: break the rule at its site; `<the named test>` fails; restore;
    the file's `sha256sum` before and after match
- [ ] **Gate: <gate name>** - [S Testing Plan](<plan file>#testing-plan)
  - Files: (n/a)
  - Acceptance: `<gate command>`, <its pass condition>

## Discovered
<a id="discovered"></a>
```

Every Phase 1 to 4 item has a bold title, a plan link
`[S <Section Name>](<plan path>#<anchor>)`, a `- Files:` line and an
`- Acceptance:` line with a checkable signal. An item that cannot have all four
goes under `## Discovered` with `Blocking: yes`.

Phase 4 holds, in order, one item per rule the plan's decisions list
(`plans/AUDIT-METHOD.md` section 9: a mutation when the rule's code site lies
under the profile's `codePaths`, otherwise the check that pins it), then one
`Gate:` item per profile gate that applies.
The workflow rejects a Phase 4 with fewer items than the gates whose `when` is
`always`.

Each carried implementation finding becomes an item in the phase its code lands
in; one that no longer applies goes under `## Discovered` with `Blocking: no`
and the reason.

## 6. Discovered items

```markdown
- [ ] **<short title>** - <one-line summary>
  - Plan section: S<anchor-slug>
  - Files: `<paths>` or `tbd`
  - Acceptance: `<signal>` or `tbd - plan revision needed`
  - Blocking: yes | no
```

`Plan section:` is parsed as the finding's location: the anchor goes on that
line only, or `unspecified`. `Blocking: yes` means implementation cannot
proceed; `Blocking: no` is nice-to-fix. An item is ticked once it is resolved,
with a `- Resolved:` line saying how, and a ticked item blocks nothing.

## 7. Counting

Progress counts the `- [ ]` and `- [x]` items under `## Phase 1` to `## Phase 4`
only. The blocker count is the unticked Discovered items with `Blocking: yes`.

## 8. The checkout

The workflow's agents work in the checkout the run was launched from.

- Before every launch, `feature-start` checks that the checkout is not on a
  workflow branch, that `git status --porcelain` over the profile's `codePaths`
  prints nothing, and, on a resume, that `git rev-parse HEAD` prints the base
  commit. The critics read the working tree and the trial branches from the
  base commit, so these checks make the two the same code.
- From launch until the result arrives, nothing else edits the checkout or
  switches its branch: not the session that launched the run, and not another
  run. Two runs on one slug are not supported.
- Every agent that switches branches commits any change it made on that branch,
  then switches back to the branch it started on before it reports. An agent
  that dies, is skipped or is killed after switching cannot, and
  `feature-start` restores the checkout before the next launch.
- Confirming a run in `feature-start` authorizes the trial commit and the
  implementation commits, all on the workflow branch. The only other commits
  are the citation checker's snapshots under `refs/citations/`, on no branch.

## 9. Trials and implementation

The trial is `plans/AUDIT-METHOD.md` section 7 applied by `plan-implementer`,
after the fresh angle clears and before the approval stamp.

- It first runs `git status --porcelain` over the `codePaths` and stops on any
  output, changing nothing and making no branch: that work is someone else's.
- It cuts `<slug>-trial` from the base commit, or `-2`, `-3` when the name is
  taken (`git switch -c` refuses an existing branch), and reports the name it
  used; every later phase reads that name.
- It mutates each rule it lands, as a `Mutation:` item does (section 5), and
  reports each with whether its named test failed. A named test that passed
  becomes a blocking finding.
- It commits on that branch whether or not it passes, staging by path.
- It checks the plan's citations on the branch without rebasing: a CHANGED
  citation on a line it edited is evidence about the plan, reported in its
  notes.
- It appends a `## Trial Log` record to the audit file with these fields of its
  result: `section`, `branch`, `commit`, `repro_failed_before`,
  `repro_passes_after`, `gates`, `mutations` and `blocking_findings`. It reports
  every profile gate by name; an unreported gate is one nobody ran.
- A plan defect is a blocking finding, and goes to a revision. A failed trial's
  branch is retired: no later phase builds on it or reads it as evidence, and
  the implementer is told its name to reuse what still matches the plan.

The implementer works on the passing trial's branch or, when none passed, on
the implementation branch the workflow names (section 1): it switches to it when
it exists, since it then holds this plan version's earlier work, and cuts it
from the base commit otherwise. It runs the same clean-tree check first, and on
dirt stops without changing anything. It commits each item's files when it
ticks the item, and any remaining change before it stops for any reason, so
every tick has its commit and the tree is clean when it switches back. A
revision retires the branch: the next trial or implementation starts from the
base commit, and the implementer is told the retired branches.

`plan-implementer` never writes the plan: its one write outside code, tests and
the checklist is the Trial Log.

## 10. Cost

A clean run is 10 agents: the draft, three critics, one fresh angle, the trial,
the approval stamp, the checklist, the implementer and the acceptance reviewer.
A revision round adds the architect, the consistency lens, each standard lens
that raised a failing finding and, when they all clear, a fresh angle; a lens
dispatched a second time adds one more. The default budget of 4 rounds bounds
the revision rounds.

## 11. Models

Each agent's model and effort are set in its frontmatter and nowhere else; the
harness checks the frontmatter against this table. The skills run on the
session's model.

| Agent | Model | Effort |
|---|---|---|
| `plan-architect` | `claude-opus-5-5[1m]` | `xhigh` |
| `plan-critic` | `claude-opus-5-5[1m]` | `xhigh` |
| `plan-implementer` | `claude-opus-5-5[1m]` | `xhigh` |
| `acceptance-reviewer` | `claude-opus-5-5[1m]` | `xhigh` |
| `plan-checklist` | `claude-sonnet-5-5` | `medium` |

Every agent that decides or reviews runs the frontier model. The checklist agent
decides nothing, and the script and the implementer check its output, so it
runs a smaller one.

## 12. Agent memory

No workflow agent keeps persistent memory: no agent file sets `memory:`, and
`.claude/agent-memory/` does not exist; the harness checks both. What an agent
needs comes from the maintained documents and the code.

## 13. Run record and resume

Every result carries a `note`, which says what to do next, and `state`: the
phase the next run starts at, the base commit, the round count, the fresh
angles spent, the owner's approval, the loop history that
`plans/AUDIT-METHOD.md` section 5 reads, the findings no architect step has
received, the findings queued for the next revision, the carried implementation
findings, and the workflow branch. The script is its only author, except for
the initial record: at the first launch `feature-start` writes

```json
{"version": 1, "phase": "draft", "baseRef": "<the base commit>"}
```

and after every result it writes the result's `state`. A resumed run receives
the record as `args.resume` and starts at its `phase`:

| Status | The next run starts at |
|---|---|
| `draft-failed` | `draft` |
| `draft-aborted` | `revise` |
| `critique-aborted-insufficient-coverage` | `critique`, the same round |
| `fresh-angles-exhausted` | `trial`, with `args.ownerApproval` |
| `needs-scope` | `revise` |
| `blocked-after-revisions` | `revise`, with a fresh budget |
| `trial-failed` | `revise` for a plan defect, otherwise `trial` |
| `approval-failed` | `approve` |
| `checklist-failed` | `checklist` |
| `checklist-malformed` | `checklist` |
| `checklist-blocked` | `revise` |
| `implementation-failed` | `implement` |
| `implementation-stopped` | `revise` for a blocking discovery, otherwise `implement` |
| `acceptance-failed` | `accept` |
| `accepted` | `done` |
| `acceptance-gaps` | `done` |

A revision that opens a resumed run is followed by a round of the standard
lenses and the consistency lens. These args change a resumed run:

- `start` overrides the phase. On a record whose phase is `done`, only
  `start: "accept"` runs, and it runs the acceptance review again after a fix
  by hand on the run's branch.
- `priorFindings` adds findings from outside the workflow to a run that starts
  at `revise`.
- `ownerApproval` is required to start past the critique when no fresh angle
  cleared this version of the plan. It states the owner's basis under
  `plans/AUDIT-METHOD.md` section 6: an angle opened by hand that came back
  clean on its first pass, or the yield rule. The record keeps it until a
  revision changes the plan.
- `resolved` lists queued findings the owner settled without a revision, each
  as `{id, resolution}`. They leave the queue, so the run may start past
  `revise`, and the result returns them as `resolvedFindings`. A finding that
  shows the plan wrong is not settled this way (`plans/AUDIT-METHOD.md`
  section 9).
- `killed` marks the record as older than a run that was killed before it
  returned. When the resumed run starts at or before the critique, the fresh
  angle the killed run could have opened counts as spent.
