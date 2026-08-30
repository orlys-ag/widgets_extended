---
name: feature-start
disable-model-invocation: true
description: "Start the feature-implementation workflow from a natural-language feature or bugfix description. Translates intent into structured {slug, requirements} args, validates specificity, and invokes the workflow after a confirmation gate that states the agent cost. Use when the user wants a full design and implementation cycle for widgets_extended."
---

You are the entry point for the `feature-implementation` workflow. You convert a
free-form description into a structured args object the workflow can consume,
then launch it after an explicit confirmation.

You run in the main loop with full conversation context and access to
`Workflow`, `AskUserQuestion`, `Grep`, `Glob`, `Read` and `Bash`. Use them.

## Inputs

One of:

1. `$ARGUMENTS`, a description passed inline with `/feature-start`.
2. The current conversation, when invoked with no arguments: the most recent
   user request describing a feature or a bug.

If neither yields a clear request, ask what the user wants to start.

## Step 1: decide whether this workflow is the right tool

**This workflow is not the default path.** A clean run is 11 agents, and a
revision adds 3 to 7. Do not launch it for work that does not need it.

| The work is | Do this |
|---|---|
| A one-line fix, a rename, a doc edit, a test tweak | Just do it. Say so and stop |
| A bug with a known cause and one obvious repro | Write the repro, fix it, run the gates. No workflow |
| A change that fits comfortably in one session | Write a plan by hand under `plans/`, audit it per `plans/AUDIT-METHOD.md`, implement |
| A change spanning controller, render object and element, with real interaction risk | `feature-implementation` |
| A change whose design is genuinely undecided | Settle the design with the user first, then come back |

Say which row you picked and why, in one sentence, before going further. If it
is not the last-but-one row, stop there.

## Step 2: check for a collision

Two concurrent runs against one slug are not supported.

```bash
ls plans/ | grep -i "<slug>"
```

If a plan for the slug exists, report it and ask whether to resume it (re-run
with `priorFindings`) or pick a different slug. Do not overwrite.

## Step 3: parse the request

Identify the verb, the subject, and any stated behaviour, constraints,
touchpoints and non-goals. Ground it in the codebase before asking the user
anything a grep would answer: `Grep` for the types and methods involved and read
the top hits. A question the repository can answer is a question you should not
ask.

If the description lacks a concrete behaviour, an acceptance signal, or a stated
touchpoint, go to step 4. Otherwise go to step 5.

## Step 4: specificity gate

Ask targeted questions via `AskUserQuestion`, aimed at structural gaps the
architect cannot resolve alone. Ask about intent, not mechanism.

Good questions here look like:

- "Should this apply while a reorder drag is in flight, or only when idle?"
- "When the animation family is set to zero, should this still fire?"
- "Does this change the public surface, or stay internal?"
- "Is the existing behaviour a bug to fix, or a contract to preserve?"

Bad questions ask the user to design: "should we cache this in an Int32List?"
is the architect's decision.

**Soft cap of three questions.** If more clarification is still needed after
three, pause and ask the user how to proceed rather than chaining further.

## Step 5: build the args

```json
{
  "slug": "kebab-case-name",
  "date": "YYYY-MM-DD",
  "requirements": {
    "summary": "One or two sentences. Non-empty string.",
    "user_visible_behavior": ["What an app developer or end user observes"],
    "acceptance_criteria": ["Each one must be able to FAIL on unfixed code"],
    "modules_touched": ["lib/sliver_tree/render_sliver_tree.dart", "..."],
    "constraints": ["Invariants that must survive, perf bounds, API stability"],
    "non_goals": ["Explicitly out of scope"],
    "open_questions": ["Genuinely undecided; the architect resolves these"]
  }
}
```

Every field is required. All but `summary` are arrays, and an empty array is
fine except for `acceptance_criteria`, which the workflow rejects when empty.

**The acceptance criteria are the part that matters.** Each one must name an
observation that would show it false, and that observation must fail at the
commit the implementer starts from. Three shapes to reject:

- A criterion already true today. It grades nothing.
- A criterion only another change could satisfy.
- A criterion that restates the request rather than deriving a check from it.

"Sticky headers work correctly" fails all three tests. "A sticky header whose
pinned band extends above the sliver's paint origin is clipped to the sliver,
verified by sampling the rendered image one pixel above the sliver top" is a
criterion.

`slug` must be kebab-case and match `^[a-z0-9]+(-[a-z0-9]+)*$`. The artifacts
land at `plans/<date>-<slug>-plan.md` and `plans/<date>-<slug>-checklist.md`.

**`date` is required and you supply it.** Workflow scripts run in a sandbox
where argless `new Date()` throws, so that scope cannot derive today; the
workflow rejects a missing or malformed `date` up front. You run in the main
loop, where `Date` works, so read today's date and pass it as `YYYY-MM-DD`.

`maxRounds` and `trial` are validated too, not coerced: pass a real integer and
a real boolean. `"5"` and `"false"` are rejected rather than silently read as 2
and true.

### Resuming instead of drafting

`priorFindings` is how a stalled run re-enters at the revision phase rather than
redrafting: `blocked-after-revisions`, `trial-failed` and `checklist-blocked` all
name it as the next step. Pass the same `{slug, requirements}` plus:

```json
{
  "priorFindings": [
    {
      "id": "checklist-missing-acceptance",
      "location": "invariants-pair-rules",
      "severity": "blocking",
      "title": "No acceptance signal for the prune/paint pair",
      "why": "The checklist could not derive a checkable signal from the section",
      "suggested_direction": "Name the debug counter or the test that pins both halves"
    }
  ]
}
```

All six fields are required strings and the workflow throws on a malformed one,
because the architect reads them as fields, not as prose. Translate each source
into that shape: a `Discovered` item's `Plan section:` becomes `location` and its
summary becomes `why`; a trial's `blocking_findings` already arrive in it and can
be passed through unchanged.

A resumed run still needs `requirements`, because the workflow validates them
before it looks at `priorFindings`. Pass the originals.

## Step 6: confirmation gate

Show the user, before launching:

- the slug and both artifact paths,
- the acceptance criteria, verbatim,
- the expected agent count and what it buys.

State the cost plainly:

> This runs 5 critic lenses, then 1 fresh angle once they come back clean, then
> a trial that applies the riskiest section on a branch and runs the gates. A
> clean run is 11 agents. A revision adds 3 to 7, because only the lenses that
> reported blocking are re-run, plus a consistency guard. Proceed?

Then ask for explicit confirmation via `AskUserQuestion`. Do not launch without
it. The user can set `maxRounds` (default 2) or `trial: false` to trade
thoroughness for cost.

## Step 7: launch

Invoke `Workflow` with `name: "feature-implementation"` and the args object.
Pass `args` as an actual JSON value, not a JSON-encoded string.

The workflow runs in the background and returns a task id. Tell the user they
can watch it with `/workflows`, and that you will report when it finishes.

## Possible outcomes

| `status` | Meaning | Next step |
|---|---|---|
| `implementation-attempted` | Ran end to end. Read `implementationReport` | Review the diff and the checklist's Discovered section |
| `blocked-after-revisions` | Blocking findings survived `maxRounds` | Read them; usually the requirements were underspecified |
| `trial-failed` | The plan read correctly and the code did not | Re-run with `priorFindings` set to the trial's `blocking_findings`. The trial branch is kept |
| `checklist-blocked` | The checklist could not derive every item from the plan | Read `blockingDiscoveries`; re-run with `priorFindings` built from them |
| `critique-aborted-insufficient-coverage` | Too few lenses reported to call a round clean | Re-run. This is an infrastructure failure, not a plan defect |
| `critique-incomplete-coverage` | No blocking findings, but a lens did not report, so an angle went unswept | Re-run. A clean round with an unswept angle cannot approve a plan |
| `fresh-angles-exhausted` | Both fresh angles have run on this plan, so none is left to come back empty on a FIRST pass | Open a new angle by hand, or accept the plan under `AUDIT-METHOD.md` section 6's yield rule |
| `checklist-failed` | The checklist agent returned nothing, so no checklist was written | Usually the approval stamp did not land. Check the plan's first line, then re-run |
| `checklist-malformed` | The checklist has no phase items, or fewer than the three mandatory Phase 4 gates | Re-run the cycle; the plan is approved and unchanged |
| `draft-failed` | The architect returned nothing, so the plan may be missing or partial | Re-run. If it repeats, the requirements are where to look |
| `draft-aborted` | A plan already exists at that path, so the architect refused rather than overwriting it | Pick a different slug or date, or resume with `priorFindings` |

Never report a workflow's results before the task notification arrives, and
never predict them.
