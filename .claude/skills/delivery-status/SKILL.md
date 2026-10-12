---
name: delivery-status
description: "Report the state of a feature-delivery run without running anything. Reads the run record, the audit file, the plan's snapshots, the acceptance document and the build branch's step commits for a slug, or lists every run when given no slug, and reports the phase, rounds, approval, build progress, acceptance and plan-check drift. Read-only: never writes files, never invokes the workflow, never spawns agents."
---

You report where a feature-delivery run stands. You never write a file, invoke
a workflow or spawn an agent; you use the read tools, and `Bash` only for
`git log` and the plan checks' `verify` commands. The method, the run files and
the statuses are `doc/agents/delivery-method.md`, which wins where this file
disagrees with it. `<artifactsDir>` is the `artifactsDir` of the project
profile, `doc/agents/delivery-profile.json`.

## Step 1: resolve the target

`$ARGUMENTS` is a slug, a path to a run file, or empty.

- Empty: `Glob` for `<artifactsDir>/*-run.json` and give the short form, one
  line per run. Stop there.
- A path: take the slug and date from the file name.
- A slug: `Glob` for `<artifactsDir>/*-<slug>-run.json`. Several matches are
  several dates: list them and ask which.

No run record: say so and suggest `/delivery-start`.

## Step 2: read

- Run record: `phase`, `round`, `revisions`, `approval` (its round and basis,
  and whether it is recorded), the open premises, the number of `steps` and
  `build` (`branch`, `lastStep`, `rework`, `discoveries`), and `metrics`.
- Audit file: the `Run` records (the base commit, each result's status and
  time), the `Revision N` records, the `Probe` records and the `Approval`
  records.
- Plan: whether it exists, and the number of `<plan>.r<N>` snapshots beside it.
- Build branch: the steps committed so far, from
  `git log <base commit>..<slug> --format=%B`, whose `Step:` trailers name
  them, and any commit saying a step is unfinished.
- Acceptance document: each criterion's status.

## Step 3: check plan drift

Unless the run record's phase is `done`, run each of the profile's
`planChecks` `verify` commands on the plan, and report each exit code and tail
line. A failing check means the code moved since the plan was checked.

## Step 4: report

Write to the user; create no file.

```
<slug>  (<plan path>)

  Next        <the run record's phase>
  Rounds      <round> rounds, <revisions> revisions
  Approval    round <N>, <basis>, or not approved
  Premises    <each open premise>, or none open
  Build       <last committed step>/<steps> on <branch>, <rework>, or not started
  Acceptance  <each criterion's status>, or not yet reviewed
  Checks      <each plan check's result>
  Metrics     <launches>, <agents by role>, <statuses returned>
```

Short form:

```
<slug>   <phase>   round <N>   <last step>/<steps>   <last status>
```

Report what the files show: a step without its `Step:` commit has not passed
its signal and gates. Close with the next action: `/delivery-start` for a new
run, `/delivery-start` on the slug to resume when the phase is not `done`, or
nothing when the run is finished.
