---
name: feature-status
description: "Report the state of a feature-implementation cycle without running anything. Reads the plan and checklist for a slug, or lists every in-progress feature when given no slug, and reports plan status, checklist progress, discovered blockers, revision rounds, trial outcome and citation drift. Read-only: never writes files, never invokes the workflow, never spawns agents."
---

You report where a feature stands. You never write, never invoke a workflow, and
never spawn agents.

**Format source of truth:** `doc/agents/feature-workflow-contracts.md`. Where
anything below contradicts it, that document wins.

Read tools plus `Bash` for the citation check. Nothing else.

## Inputs

`$ARGUMENTS`, one of:

1. A slug, for example `sticky-band-clip`.
2. A path to a plan or checklist.
3. Empty: report on every feature found under `plans/`.

## Step 1: resolve the target

- Empty argument: `Glob` for `plans/*-plan.md`, derive each slug, and emit the
  short form (one line per feature). Stop there.
- A path: derive the slug and date from the filename.
- Otherwise treat it as a slug and `Glob` for `plans/*-<slug>-plan.md`. More
  than one match means more than one date; report all and ask which.

If no plan is found, say so and suggest `/feature-start`. If the plan exists but
the checklist does not, that is normal: the cycle has not reached the checklist
phase.

## Step 2: parse

From the plan:

- `PLAN-STATUS` from the first non-empty line: `draft` or `ready-to-implement`.
  Any other value, or a missing comment, is a contract violation worth
  reporting.
- The highest `## Round N Revision` heading, which gives the revision count.
- Whether `## Trial Log` exists, and what it records for each gate.
- Whether `## Approval` exists.
- The `## Open Questions` section: how many remain.

From the checklist, if present:

- `CHECKLIST-FOR` and whether it matches the plan path. A mismatch means the
  pair is malformed; say so rather than reporting progress from it.
- `CHECKLIST-STATUS`: `pending` or `complete`.
- Counts of `- [ ]` and `- [x]` **restricted to items under `## Phase 1`
  through `## Phase 4`**. Items under `## Discovered` are never counted toward
  progress.
- `## Discovered` items, split by `Blocking: yes` and `Blocking: no`.

## Step 3: check citation drift

```bash
python plans/check_citations.py <plan path>
```

Report the tail line. A drifted plan fails the citation angle before any other
angle is worth sweeping, so this belongs in the status rather than in a
follow-up. If no ledger exists yet, say the plan is unrecorded rather than
treating it as clean.

## Step 4: report

Write directly to the user. Do not create a file.

### Long form, one feature

```
sticky-band-clip  (plans/2026-08-29-sticky-band-clip-plan.md)

  Plan        ready-to-implement, 2 revision rounds, approved
  Trial       passed on sticky-band-clip-trial at a1b2c3d
  Checklist   pending, 7/11 phase items ticked
              Phase 1 3/3, Phase 2 3/4, Phase 3 1/2, Phase 4 0/2
  Discovered  1 blocking, 2 non-blocking
  Citations   ok 34, drifted 0, unrecorded 0
  Open        2 open questions remain in the plan

  Blocking discoveries:
    - Preview offset composed into the prune criterion (S invariants-pair-rules)
```

### Short form, one line per feature

```
sticky-band-clip     ready-to-implement   7/11   1 blocker    citations ok
row-transition       draft                 -     -            76 drifted
```

## What to say about state

Report what you read. Do not infer progress from the absence of evidence: a
checklist with no ticks means no item has passed its acceptance signal, which is
not the same as no work having happened, and you cannot tell which from the
files. Say the former.

If `CHECKLIST-STATUS` is `complete` but blocking discoveries exist, that is a
contract violation, because the implementer may only flip to complete when no
Discovered item is blocking. Report it as a violation rather than as success.

Close with the single next action: `/feature-start` for a new cycle, re-running
the workflow with `priorFindings` when blocking discoveries exist, or nothing
when the cycle is genuinely finished.
