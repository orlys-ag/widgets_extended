---
name: delivery-start
disable-model-invocation: true
description: "Start or resume the feature-delivery workflow from a natural-language feature or bugfix description. Questions the owner on behaviour, scale, performance bounds and architectural limits, translates the answers into structured args (slug, requirements, the verbatim request, the base commit and the project profile), validates specificity, and launches the workflow after a confirmation gate that states the agent cost and authorizes its commits. Use when the user wants a full design, build and review cycle."
---

You are the entry point for the `feature-delivery` workflow: you turn a request
into the workflow's args and launch it after explicit confirmation. You run in
the main loop, with `Workflow`, `AskUserQuestion`, `Grep`, `Glob`, `Read` and
`Bash`. The method, the run files and the statuses are
`doc/agents/delivery-method.md`; the project profile is
`doc/agents/delivery-profile.json`, and `<artifactsDir>` below is its
`artifactsDir`.

The request is `$ARGUMENTS`, or, with no arguments, the most recent feature or
bug request in the conversation. If neither is clear, ask what to start.

## Step 1: decide whether this workflow fits

| The work is | Do this |
|---|---|
| A one-line fix, a rename, a doc edit, a test tweak | Just do it |
| A bug with a known cause and one obvious repro | Write the repro, fix it, run the gates |
| A change that fits comfortably in one session | Write a plan by hand to the method, then implement it |
| A change spanning several layers or components, with real interaction risk | This workflow |
| A change whose design is genuinely undecided | Settle the design with the user first |

Say which row applies and why, in one sentence. Unless it is the workflow row,
stop there.

The workflow's agents start with the guidance this session loaded. If
`AGENTS.md`, `CLAUDE.md` or a file under `.claude/` changed since this session
started, ask the user to start a new session before launching.

## Step 2: check for an existing run

```bash
ls <artifactsDir> | grep -i "<slug>"
git branch --list "<slug>" "<slug>-*"
```

If a run file for the slug exists, do not overwrite it: report it and ask
whether to resume it ("Resuming") or pick another slug. A branch with the
slug's name and no run files belongs to something else: pick another slug.

A run whose record's phase is `done` is not resumed: propose a successor under
a new slug whose requirements cite it. Launch the successor only once the
earlier run's branch is merged into the branch you are on:
`git merge-base --is-ancestor <slug> HEAD` exits 0 after a merge; after a
squash or rebase merge, which it does not detect, ask the user to confirm.
Merging is the user's decision.

## Step 3: ground the request

Identify the verb, the subject, and any stated behaviour, constraints,
touchpoints and non-goals. Grep for the types and methods involved and read the
top hits, the guidance of the profile's modules they match, and the profile's
`hotPaths`, `planRules` and `ranking`, before asking anything the repository
can answer.

## Step 4: question the owner

The acceptance reviewer judges the result against the requirements alone,
without the plan, so a limit the owner does not state here is never checked at
acceptance. Question the owner until no assumption is left, in as many rounds
as that takes. Ask about intent and limits the planner cannot settle alone,
never about a mechanism it can choose. Start from these topics:

- Behaviour: whether the change applies while other operations are in flight;
  what it does when a feature it relies on is disabled; whether today's
  behaviour is a bug to fix or a contract to keep.
- Scale: the typical and worst-case sizes it runs over, per call and per unit
  of time.
- Hot paths: which of the profile's `hotPaths` it touches, the counter that
  shows its cost there, and the bound that must hold.
- Memory: the footprint it may add, per item and in total.
- Architecture: the module that owns it; whether it may change the public
  surface, or anything the profile's `planRules` govern; the invariants that
  must survive.
- Decisions: any architecture, performance or algorithm choice the owner
  already made, and on what evidence.

Each round:

1. Draft the requirements of step 5 from what is settled, and list every
   assumption the draft rests on: anything it states or leaves out that
   neither the owner nor the code has settled. The list also holds each hot
   path, module boundary, consumer of a changed surface and subject of the
   profile's `planRules` that the change touches, until the owner answers it
   or the code settles it.
2. Settle each assumption the code can settle by reading it, and cite its
   `path:line` in the requirement it supports.
3. Ask about the rest with `AskUserQuestion`, up to four questions per call,
   each with the answer the code recommends as its first option, so the owner
   picks rather than writes.
4. Add to the list each assumption an answer or a code read raises: a new
   path, component, bound, invariant or ordering rule brings its own
   questions.

Stop when the list is empty, or when the owner says stop; each assumption left
then becomes an open question, which step 6 shows.

Record each answer where a stage reads it:

- A bound becomes an acceptance criterion that fails on the base commit,
  counted by a test where it can be: a count is deterministic, and a timing
  needs the protocol of method section 11.
- A limit or an invariant becomes a constraint.
- A choice becomes an entry in `requirements.decisions` with its evidence,
  labelled design-only when nothing measured it (method section 3), so the
  planner names the check that will test it.
- A question the owner leaves to the agents becomes an open question.

## Step 5: build the args

```json
{
  "slug": "kebab-case-name",
  "date": "YYYY-MM-DD",
  "request": "The user's request, verbatim",
  "baseRef": "The commit the first launch of this slug started from",
  "profile": {"...": "the parsed contents of the project profile"},
  "requirements": {
    "summary": "One or two sentences. Non-empty string.",
    "user_visible_behavior": ["What an app developer or end user observes"],
    "acceptance_criteria": ["Each one must be able to FAIL on the base commit"],
    "modules_touched": ["<repository path of each file the change touches>"],
    "constraints": ["Invariants that must survive, performance bounds, API stability"],
    "non_goals": ["Explicitly out of scope"],
    "open_questions": ["Genuinely undecided; the planner resolves these"],
    "decisions": ["Optional. A decision the user already made, with its evidence"]
  },
  "budget": {"rounds": "Optional integers overriding the profile's budget for this launch"}
}
```

- Every requirements field but `decisions` is required; all but `summary` are
  arrays of strings, and only `acceptance_criteria` must be non-empty.
- Each acceptance criterion names an observation that would show it false and
  that fails on the base commit. Reject a criterion that is already true, that
  only another change could satisfy, or that restates the request. "Export
  works correctly" grades nothing; "Exporting an empty list writes only the
  header row, verified by a test that reads the file back" is a criterion.
- `modules_touched` decides which module guidance the agents read: every module
  of the profile whose paths a file matches. A file no module matches, in a
  profile with modules, is a module to add to the profile first.
- `slug` matches `^[a-z0-9]+(-[a-z0-9]+)*$`.
- `date` is today's date, which you supply: a workflow script cannot call
  `new Date()`.
- `request` is verbatim: the reviewer judges the result against it without
  reading the plan.
- `profile` is the parsed project profile, which the workflow cannot read
  itself.
- `baseRef` is `git rev-parse HEAD` at the first launch (step 7); a resumed run
  passes the one its records hold.
- `budget` is optional, with integer values; quoted numbers are rejected.

## Step 6: confirm

Show the user the slug, the run file paths, the acceptance criteria, the
constraints, the decisions and the open questions verbatim, and the cost from
method section 10, plainly:

> This drafts a plan, probes any premise reading cannot settle, runs every
> critic lens at once, and revises until a round is clean; then it builds the
> plan step by step on the branch `<slug>`, running each step's gates, and
> closes with a review by an agent that never reads the plan, plus a bounded
> fix loop. A clean run is <N> agents; each revision adds the planner, the
> lenses that failed and the consistency lens, plus the performance and claims
> lenses when it changes a decision. Confirming authorizes the probe's scratch
> commits, the build and fix commits on `<slug>`, and the commits the plan
> checks make for their records. Proceed?

Launch only on an explicit yes via `AskUserQuestion`. The user can set
`budget` to trade thoroughness for cost.

## Step 7: launch

1. Check the checkout (method section 1): `git branch --show-current` is not a
   run branch, `git status --porcelain` over the profile's `codePaths` prints
   nothing, on a resume `git rev-parse HEAD` prints the base commit, and each
   command of the profile's `preflight` passes. If a check fails, restore the
   checkout (below) or ask the user to clear it, and do not launch until all of
   them pass.
2. On the first launch, record the base commit: create
   `<artifactsDir>/<date>-<slug>-audit.md` with a one-line title if it does not
   exist, append a `Run` record with `git rev-parse HEAD`,
   `git branch --show-current` and the time, and write the initial run record
   (method section 10) to `<artifactsDir>/<date>-<slug>-run.json`.
3. Invoke `Workflow` with `name: "feature-delivery"` and the args, as a JSON
   value rather than a string. Tell the user they can watch it with
   `/workflows`, and that until the result arrives neither of you edits files,
   switches branches in this checkout or undoes a `preflight` check.
4. When the result arrives, write its `state` to the run record and append a
   `Run` record to the audit file with the status, the state's `phase` and the
   time. Report the result: its status, its note, and what its fields name
   (scope questions, the diagnosis, the reason, the acceptance). Never report
   or predict it before it arrives.

## Resuming

Pass the run record's contents as `resume`, with the args of the first launch
and any requirement the user settled corrected. The run starts at the record's
`phase`. `start`, `priorFindings`, `ownerApproval` and `budget` change a
resumed run as method section 10 says; a `priorFindings` entry has these
fields, all required strings:

```json
{
  "priorFindings": [
    {
      "id": "<short-kebab-id>",
      "location": "<plan anchor, or path:line>",
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
  record at its phase, never past it, and tell the user that what the killed
  run did since that record runs again (method section 10). When the record's
  phase is `draft` and the plan exists, the killed run wrote it: ask the user
  whether to delete it and draft again, or to pick another slug.

## Restoring the checkout

An agent that dies, is skipped or is killed after switching branches leaves
the checkout on its branch, possibly with uncommitted changes. Run
`git branch --show-current` and `git status`:

- On a run branch, uncommitted changes are the dead agent's unfinished step.
  With the user's agreement, commit them there by path, with a message saying
  the step is unfinished, so the resumed agent continues from them; then switch
  back to the branch the first `Run` record names.
- Changes in the code paths on any other branch are not the run's to touch: ask
  the user to commit them elsewhere, stash or discard them.

## Possible outcomes

<!-- generated: outcomes -->
| `status` | Meaning | Next step |
|---|---|---|
| `accepted` | Every acceptance criterion is met and the reviewer raised no blocking or major finding. | Review the branch diff and the acceptance document. Merging is the owner's decision. |
| `acceptance-gaps` | After the fix budget a criterion is still not met or a blocking or major finding remains, or a fix needs the plan changed. | Read `acceptance`; fix by hand, or start a successor run with the gaps as its requirements once this branch is merged. |
| `needs-scope` | The draft or a revision returned scope questions, or a round raised a failing scope finding. | Settle every question and scope finding with the owner, correct `requirements`, then resume. |
| `budget-spent` | The critique revisions or the implementation revisions of this launch are spent with failing findings open. | Read `diagnosis`. Resume to revise with a fresh budget, or approve the plan with `ownerApproval` and `start: "steps"`. |
| `failed` | An agent returned nothing (it was skipped or died), a result broke its contract twice, a precondition failed, or the probe could not run an experiment; `reason` says which. | Clear the reason (restore the checkout when an agent died after switching branches), then resume: the run starts at the phase its state names. |
<!-- end generated -->
