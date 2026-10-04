---
name: feature-start
disable-model-invocation: true
description: "Start or resume the feature-implementation workflow from a natural-language feature or bugfix description. Translates intent into structured args (slug, requirements, the verbatim request, the base commit and the project profile), validates specificity, and launches the workflow after a confirmation gate that states the agent cost and authorizes its commits. Use when the user wants a full design and implementation cycle."
---

You are the entry point for the `feature-implementation` workflow: you turn a
request into the workflow's args and launch it after explicit confirmation. You
run in the main loop, with `Workflow`, `AskUserQuestion`, `Grep`, `Glob`, `Read`
and `Bash`. The workflow's files, statuses and cost are
`doc/agents/feature-workflow-contracts.md`.

The request is `$ARGUMENTS`, or, with no arguments, the most recent feature or
bug request in the conversation. If neither is clear, ask what to start.

## Step 1: decide whether this workflow fits

| The work is | Do this |
|---|---|
| A one-line fix, a rename, a doc edit, a test tweak | Just do it |
| A bug with a known cause and one obvious repro | Write the repro, fix it, run the gates |
| A change that fits comfortably in one session | Write and audit a plan by hand (`plans/AUDIT-METHOD.md`), then implement |
| A change spanning several layers or components, with real interaction risk | This workflow |
| A change whose design is genuinely undecided | Settle the design with the user first |

Say which row applies and why, in one sentence. Unless it is the workflow row,
stop there.

The workflow's agents start with the guidance this session loaded
(`.claude/rules/agent-config.md`). If `AGENTS.md`, `CLAUDE.md` or a file under
`.claude/` changed since this session started, ask the user to start a new
session before launching.

## Step 2: check for an existing run

```bash
ls plans/ | grep -i "<slug>"
```

If a plan for the slug exists, do not overwrite it: report it and ask whether to
resume it ("Resuming") or pick another slug.

A plan whose run record's phase is `done` is not resumed: propose a successor
plan under a new slug that cites it. Launch the successor only once the earlier
run's change is in the branch you are on. `git merge-base --is-ancestor <branch>
HEAD`, with the run record's `branch`, exits 0 after a merge; after a squash or
rebase merge, which it does not detect, ask the user to confirm the change is
merged. Merging is the user's decision.

## Step 3: ground the request

Identify the verb, the subject, and any stated behaviour, constraints,
touchpoints and non-goals. Grep for the types and methods involved and read the
top hits before asking anything the repository can answer.

If the request lacks a concrete behaviour, an acceptance signal or a touchpoint,
go to step 4; otherwise to step 5.

## Step 4: ask about intent

Ask with `AskUserQuestion`, at most three questions before pausing to ask how to
proceed. Ask about intent the architect cannot settle alone, never about
mechanism:

- whether the change applies while other operations are in flight;
- what it does when a feature it relies on is disabled;
- whether it changes the public surface;
- whether today's behaviour is a bug to fix or a contract to keep;
- whether the user already decided an architecture, performance or algorithm
  choice, and on what evidence. Each becomes an entry in
  `requirements.decisions`.

## Step 5: build the args

```json
{
  "slug": "kebab-case-name",
  "date": "YYYY-MM-DD",
  "request": "The user's request, verbatim",
  "baseRef": "The commit the first launch of this slug started from",
  "profile": {"...": "the parsed contents of doc/agents/method-profile.json"},
  "module": "Optional. A key of the profile's modules; required when modules_touched matches none or several",
  "requirements": {
    "summary": "One or two sentences. Non-empty string.",
    "user_visible_behavior": ["What an app developer or end user observes"],
    "acceptance_criteria": ["Each one must be able to FAIL on unfixed code"],
    "modules_touched": ["<repository path of each file the change touches>"],
    "constraints": ["Invariants that must survive, perf bounds, API stability"],
    "non_goals": ["Explicitly out of scope"],
    "open_questions": ["Genuinely undecided; the architect resolves these"],
    "decisions": ["Optional. A decision the user already made, with its evidence"]
  }
}
```

- Every requirements field but `decisions` is required; all but `summary` are
  arrays, and only `acceptance_criteria` must be non-empty.
- Each acceptance criterion names an observation that would show it false and
  that fails at the commit the implementer starts from. Reject a criterion that
  is already true, that only another change could satisfy, or that restates the
  request. "Export works correctly" grades nothing; "Exporting an empty list
  writes only the header row, verified by a test that reads the file back" is a
  criterion.
- `slug` matches `^[a-z0-9]+(-[a-z0-9]+)*$`.
- `date` is today's date, which you supply: a workflow script cannot call
  `new Date()`.
- `request` is verbatim: the acceptance reviewer judges the result against it
  without reading the plan.
- `profile` is the parsed contents of `doc/agents/method-profile.json`, which
  the workflow cannot read itself.
- `baseRef` is `git rev-parse HEAD` at the first launch (step 7); a resumed run
  passes the one its records hold.
- Optional: `maxRounds`, an integer (default in contracts section 10), and
  `trial`, a boolean. Quoted values are rejected.

## Step 6: confirm

Show the user the slug, the artifact paths, the acceptance criteria verbatim,
and the cost from contracts section 10, plainly:

> This runs the standard critics, a fresh angle once they come back clean, a
> trial of the riskiest section on a branch, the implementation, and a review by
> an agent that never reads the plan. A clean run is <N> agents; each revision
> round adds the architect, the consistency lens, the lenses that failed and a
> fresh angle. Confirming authorizes the trial commit and the implementation
> commits, on the branch the workflow creates from the base commit; the citation
> check also writes snapshot commits under `refs/citations/`, on no branch.
> Proceed?

Launch only on an explicit yes via `AskUserQuestion`. The user can set
`maxRounds` or `trial: false` to trade thoroughness for cost.

## Step 7: launch

1. Check the checkout (contracts section 8): `git branch --show-current` is not
   a workflow branch (`<slug>-...`), `git status --porcelain` over the profile's
   `codePaths` prints nothing, and, on a resume, `git rev-parse HEAD` prints the
   base commit. If a check fails, restore the checkout (below) or ask the user
   to, and do not launch until all three pass.
2. On the first launch, record the base commit: create
   `plans/<date>-<slug>-audit.md` with a one-line title if it does not exist,
   append a `## Run` record with `git rev-parse HEAD` and
   `git branch --show-current`, and write the initial run record (contracts
   section 13).
3. Invoke `Workflow` with `name: "feature-implementation"` and the args, as a
   JSON value rather than a string. Tell the user they can watch it with
   `/workflows`, and that until the result arrives neither of you edits files
   or switches branches in this checkout.
4. When the result arrives, write its `state` to the run record,
   `plans/<date>-<slug>-run.json`, and append a `## Run` record to the audit
   file with the status and the state's `phase`. Report the result; never
   report or predict it before it arrives.

## Resuming

Pass the run record's contents as `resume`, with the args of the first launch
and any requirement the user settled corrected. The run starts at the record's
`phase` (contracts section 13). `start`, `priorFindings`, `ownerApproval` and
`killed` change a resumed run as contracts section 13 says; a `priorFindings`
entry has these fields, all required strings:

```json
{
  "priorFindings": [
    {
      "id": "<short-kebab-id>",
      "location": "<plan section anchor, or path:line>",
      "severity": "blocking | major | minor | nit",
      "title": "<short>",
      "why": "<the evidence>",
      "suggested_direction": "<one sentence>"
    }
  ]
}
```

The workflow's own findings already travel in the state; do not pass them
again.

A run killed before its result arrived wrote no new record:

- In the session that launched it, relaunch `Workflow` with `scriptPath` set to
  the script path its launch returned, `resumeFromRunId` set to its run id, and
  the same args: the agents it finished return from cache.
- In any other session, restore the checkout (below), then resume from the run
  record with `killed: true`. Tell the user that every phase the killed run
  reached since that record runs again, and that a fresh angle it could have
  opened counts as spent. If the record's phase is `draft` and the plan exists,
  the killed run wrote it: ask the user whether it is complete, and resume with
  `start: "critique"` if so; otherwise delete it first.

## Restoring the checkout

An agent that dies, is skipped or is killed after switching branches leaves the
checkout on its branch, possibly with uncommitted changes. Run
`git branch --show-current` and `git status`:

- On a workflow branch (`<slug>-...`), uncommitted changes are the dead agent's
  unfinished step. With the user's agreement, commit them there by path, so the
  resumed agent continues from them; then switch back to the branch the `## Run`
  record names.
- Changes in the code paths on any other branch are not the run's to touch: ask
  the user to commit them elsewhere, stash or discard them.

## Possible outcomes

| `status` | Meaning | Next step |
|---|---|---|
| `accepted` | Every acceptance criterion is met and the reviewer raised no blocking or major finding | Review the branch's diff, the acceptance document and the checklist's Discovered section |
| `acceptance-gaps` | A criterion is unmet, partial or unquoted, or the reviewer raised a blocking or major finding | Read `acceptance`; fix by hand, or start a successor run with the gaps as its requirements once this branch is merged (step 2) |
| `acceptance-failed` | The acceptance reviewer returned nothing | Restore the checkout, then resume: the review runs again |
| `implementation-stopped` | The implementer stopped before the checklist was complete: on a blocking discovery, part-way (its `report` says where), or on a failed precondition such as a dirty tree, which changes nothing. Any work it did is committed on the branch | Clear a failed precondition, then resume: a blocking discovery is revised into the plan, otherwise the implementation continues |
| `implementation-failed` | The implementer returned nothing | Restore the checkout, then resume: the implementation continues on the same branch from the first unticked item |
| `needs-scope` | A requirement is missing, ambiguous or in conflict | Settle it with the user, correct `requirements`, then resume |
| `blocked-after-revisions` | Failing findings survived `maxRounds` | Read `diagnosis`; usually the requirements were underspecified. Resuming revises with a fresh budget |
| `trial-failed` | The trial did not pass, found a plan defect, or returned nothing | Restore the checkout if it returned nothing. A dirty code path means the checkout changed during the run: have the user move that work, then resume. A plan defect is revised into the plan; otherwise the trial runs again. A trial branch it made is kept |
| `approval-failed` | The approval step did not stamp the plan | Check the plan's status line, then resume |
| `checklist-blocked` | The checklist could not derive every item from the plan, or the plan failed a checklist precondition | Resume: the gaps are revised into the plan |
| `critique-aborted-insufficient-coverage` | A lens could not review on two attempts | Resume: the round runs again with all its lenses, and its first attempt's findings are discarded. This is an infrastructure failure or a missing input, not a plan defect |
| `fresh-angles-exhausted` | Both fresh angles have run on this plan, so none is left to come back clean on a first pass | Resume with `ownerApproval` stating the basis. Findings from an angle opened by hand go to a revision first, as `priorFindings` with `start: "revise"` |
| `checklist-failed` | The checklist agent returned nothing, or wrote its checklist at another path | Resume: the checklist runs again |
| `checklist-malformed` | The checklist has no phase items, or too few in Phase 4 | Resume: the checklist runs again; the plan is unchanged |
| `draft-failed` | The architect returned nothing, so the plan may be missing or partial | Delete a partial plan, then resume. If it repeats, look at the requirements |
| `draft-aborted` | A plan already exists at that path, so the architect refused to overwrite it | Pick another slug or date, or resume at the revision with `priorFindings` |
