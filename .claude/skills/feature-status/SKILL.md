---
name: feature-status
description: "Report the state of a feature-implementation cycle without running anything. Reads the plan, its audit file, checklist, run record and acceptance document for a slug, or lists every feature when given no slug, and reports plan status, checklist progress, discovered blockers, revisions, trial outcome, acceptance and citation drift. Read-only: never writes files, never invokes the workflow, never spawns agents."
---

You report where a feature stands. You never write a file, invoke a workflow or
spawn an agent; you use the read tools, and `Bash` only for the citation check.
The formats are `doc/agents/feature-workflow-contracts.md`, which wins where
this file disagrees with it.

## Step 1: resolve the target

`$ARGUMENTS` is a slug, a path to a plan or checklist, or empty.

- Empty: `Glob` for `plans/*-plan.md` and give the short form, one line per
  feature. Stop there.
- A path: take the slug and date from the file name.
- A slug: `Glob` for `plans/*-<slug>-plan.md`. Several matches are several
  dates: list them and ask which.

No plan: say so and suggest `/feature-start`. A plan without a checklist is
normal before the checklist phase.

## Step 2: read

- Plan: `PLAN-STATUS` from its first non-empty line (any value but `draft` or
  `ready-to-implement`, or none, is a contract violation to report); whether
  `## Approval` exists; how many open questions remain; the revision count,
  which is the number of `<plan>.r<N>` snapshots beside it.
- Audit file: the `## Round N` records (the findings each revision or approval
  step received, with their outcomes); the last `## Trial Log` record; the
  `## Run` records (the base commit and each run's status). A plan written
  outside the workflow keeps these under its own audit-log heading until the
  revision that adopts it moves them.
- Run record: the `phase` the next run starts at, `roundsRun`, `freshSpent` and
  `branch`.
- Acceptance document: each criterion's status.
- Checklist: whether `CHECKLIST-FOR` names the plan (if not, the pair is
  malformed: say so and report no progress from it); `CHECKLIST-STATUS`; the
  ticked and total items under Phase 1 to 4 only; the unticked Discovered
  items, split by `Blocking:` (a ticked one is resolved).

The trial passed when its Trial Log meets the pass condition of
`plans/AUDIT-METHOD.md` section 7.

## Step 3: check citation drift

Unless the run record's phase is `done`, run:

```bash
python plans/check_citations.py <plan path>
```

Report its tail line. Any status but OK and MOVED fails the citation angle
before any other angle is worth sweeping. A plan without a CITATIONS marker is
unstamped, not clean.

## Step 4: report

Write to the user; create no file.

```
<slug>  (<plan path>)

  Plan        <PLAN-STATUS>, <N> revisions, <approved or not>
  Next        <the run record's phase>, on branch <branch>
  Trial       <passed or failed> on <branch> at <sha>, or not run
  Checklist   <CHECKLIST-STATUS>, <ticked>/<total> phase items, per phase
  Discovered  <N> blocking, <N> non-blocking
  Acceptance  <each criterion's status>, or not yet reviewed
  Citations   <the check's tail line>
  Open        <N> open questions in the plan

  Blocking discoveries:
    - <title> (S <plan section>)
```

Short form:

```
<slug>   <PLAN-STATUS>   <ticked>/<total>   <N> blockers   <citation summary>
```

Report what the files show: no ticks means no item has passed its acceptance
signal, not that no work happened. `CHECKLIST-STATUS: complete` with an unticked
blocking discovery is a contract violation, not success. Close with the next
action: `/feature-start` for a new cycle, `/feature-start` on the slug to resume
when the run record's phase is not `done`, or nothing when the cycle is
finished.
