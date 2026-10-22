# Feature delivery method

How the `feature-delivery` workflow plans, critiques, builds and accepts a
change, and how to write a plan for it. The method is project-neutral: every
project fact comes from the project profile, `doc/agents/delivery-profile.json`
(section 12). The workflow script owns the mechanics; each block marked
generated below is produced from it by
`node .claude/workflows/feature-delivery.harness.mjs --write`, and the harness
fails while one is stale.

---

## 1. Files, branches and the checkout

| Artifact | Path |
|---|---|
| Plan | `<artifactsDir>/<date>-<slug>-plan.md` |
| Revision snapshot | `<plan>.r<N>`, `N` the revision's number |
| Audit file | `<artifactsDir>/<date>-<slug>-audit.md` (section 10) |
| Acceptance document | `<artifactsDir>/<date>-<slug>-acceptance.md` |
| Run record | `<artifactsDir>/<date>-<slug>-run.json` (section 10) |
| Build branch | `<slug>`, cut from the base commit |
| Probe branch | `<slug>-probe`, or the first free `-2`, `-3` |

`<artifactsDir>` is the profile's; `<date>` is `YYYY-MM-DD` and `<slug>` is
kebab-case. Branches named `<slug>` or `<slug>-...` belong to the run. The base
commit is the commit the slug's first launch started from.

With the profile's `isolation` set to `checkout`, every agent works in the
checkout the run was launched from:

- Before every launch, the start skill checks that the checkout is not on a run
  branch, that nothing under the profile's `codePaths` is uncommitted, and, on
  a resume, that `HEAD` is the base commit. The critics read the working tree,
  so these checks make what they read the base commit's code.
- From launch until the result arrives, nothing else edits the checkout or
  switches its branch. Two runs in one checkout are not supported.
- Every agent that switches branches commits its changes there, then switches
  back to the branch it started on before it reports. An agent that dies after
  switching cannot, and the start skill restores the checkout before the next
  launch.

With `isolation` set to `worktree`, the probe, the builder and the reviewer each
work in a git worktree of their own, and the run files stay in the main
checkout: from a worktree, the main checkout is the parent directory of
`git rev-parse --path-format=absolute --git-common-dir`.

In either isolation, the start skill launches only when every check of the
profile's `preflight` passes (section 12).

Confirming a run in the start skill authorizes the probe's scratch commits, the
build and fix commits on the build branch, and the commits a plan check makes
for its own records.

---

## 2. Writing a plan

Apply these when writing. A violation a critic finds is a finding.

### 2.1 Sections

Every H2 section of a plan is followed by its anchor: the heading in lower
case, each run of characters other than letters and digits replaced by one
hyphen, with no hyphen at either end.

```markdown
## Public Surface
<a id="public-surface"></a>
```

The sections, in order:

| # | Heading | Carries |
|---|---|---|
| 1 | `Overview` | Two or three sentences, the key decisions by reference, and every file created or modified |
| 2 | `Goals & Non-Goals` | The goals and the non-goals |
| 3 | `Decisions` | One subsection per architecture, performance or algorithm choice, anchored `d<N>` (section 3) |
| 4 | `Public Surface` | Each public artifact added or changed: name, signature, where it lives and how it is exported |
| 5 | `State & Lifecycle` | New state: its type, where it lives, who writes it, and how it grows and is torn down |
| 6 | `Invariants & Pair Rules` | Every invariant the change preserves, and every pair of sites that must change together |
| 7 | `Landing Order` | The numbered steps (section 2.7) |
| 8 | `Testing Plan` | The repros that fail on the base commit, and each named test: what it asserts and the seam it attaches at; a new seam names the existing one it rejected |
| 9 | `Premises` | Each premise (section 2.8), or one line saying there is none |
| 10 | `Risks` | Demonstrated risks; an undemonstrated one is labelled unverified |
| 11 | `Open Questions` | Only what is genuinely undecided |

A section with nothing to say holds one line saying so. The plan has no status
line, approval section or history: approval lives in the run state and the
audit file (section 10). The profile's `planRules` add the project's own
requirements.

### 2.2 One site per fact

Exactly one place states each decision. Every other mention refers to it ("per
d2") instead of restating it.

### 2.3 Summary sections go stale first

When a section changes, re-read every section that paraphrases decisions made
elsewhere: the overview, the landing order, the testing plan and the risks.

### 2.4 Counts and universals carry their command

A count, or a claim with "every", "all", "only", "none", "the sole" or "always",
carries the command that established it, or is rewritten as an enumeration
(preferred when the list is short). A count of a code symbol's users comes from
code (section 5), not from a text search.

### 2.5 Declare every artifact the builder creates

Its name, signature, where it lives, and whether it is exported.

### 2.6 Write the design, not its history

A plan describes the feature as it will be built: its goals, its decisions, and
how to build and test it, as concisely as an answer to the owner. How it got
there belongs in the audit file.

- Write the final state: never "previously", "round 2 changed", "an earlier
  draft said" or "the review found". Today's code, which the change is made
  against, is the feature's problem and stays.
- A revision rewrites the sentence that was wrong; it never appends a note
  beside it.
- A rejected option is one table row with its reason, named for what it is,
  never for when it was tried.
- No defensive prose: do not answer a critic in advance unless the builder
  needs the constraint.
- The deletion test: a sentence whose removal changes nothing the builder builds
  or a reviewer checks is removed.

### 2.7 Landing order

The Landing Order lists the steps in dependency order:

- Step 0 is the repros the Testing Plan names, committed first and shown
  failing on the base commit.
- Each step names the files it creates or changes, the decisions it
  implements, and its signal: the named test or exact command that passes once
  it lands and not before.
- Steps that correctness forces to land together are marked NOT INDEPENDENTLY
  VERIFIABLE, with the reason. Each still names a signal, which may be the
  group's last test.
- Each step's commit builds, passes the gates its files trigger, and leaves
  every document and comment it touches true at that commit.
- The decision whose failure is hardest to detect by reading lands as early as
  its dependencies allow. A pure restructuring that makes the behaviour change
  small lands first, in its own step.

### 2.8 Premises

A premise is a load-bearing claim about runtime or engine behaviour that a
decision's rank or a named test rests on, and that reading the source cannot
settle. Read the source first, and list a premise only when reading is not
enough: each has an id, its decision, the claim, and the smallest experiment
that settles it. The probe runs the experiments; section 8.2 gives each
outcome and what it does to the plan.

---

## 3. Decisions are ranking tables

Each architecture, performance or algorithm choice is a subsection of the
plan's Decisions section, anchored `d<N>`: the decision; a problem statement
when it answers a defect in today's behaviour; its code site and the test that
pins it (section 8.3); and a table with the columns Rank, Option, Gate,
Evidence and Assessment.

- Gate: pass or fail, with the reason. An option passes when it is correct,
  meets the goals and requirements, preserves every documented invariant, is
  idiomatic for the language, the framework and the codebase, keeps the public
  API compatible unless a goal says otherwise, and removes no safeguard without
  a replacement. A failing option stays in the table, below every passing one.
- Evidence: each claim labelled, strongest first: measured (a timed or counted
  run, section 11), demonstrated (a recorded test, run or probe), traced (a
  code path or normative document read), computed (arithmetic from stated
  inputs), design-only. A rank-1 option resting on design-only evidence names
  the check or the premise that will produce evidence.
- Rank: passing options in the order of the profile's `ranking` criteria, a tie
  on one criterion going to the next. A hot-path performance criterion applies
  only on the profile's `hotPaths`. A difference within measurement spread, or
  within one complexity class when computed, is a tie. A plan whose decisions
  are not code decisions declares its own criteria in the Decisions preamble.
- The top-ranked passing option is the decision. Rejected options stay in the
  table, so a re-rank (section 7) can choose one.

The owner may supply decisions with their evidence before the plan is written;
the planner adopts each as its starting table and may add options.

---

## 4. Claims and plan checks

Cite each claim about existing code where it is made, in the form the profile's
plan checks read. The profile's `planChecks` keep a plan's claims honest: the
draft runs each check's `stamp` command, a revision its `rebase` command, and
the evidence lens and the builder its `verify` command. A check that exits
non-zero is a finding, which its `note` says how to read.

The evidence lens sweeps the claims on every version of the plan:

1. Run the plan checks and re-read each citation they flag.
2. Run the command behind every count and universal (section 2.4).
3. Verify every framework or engine claim against its source; recall is a
   hypothesis.

Steps 2 and 3 are where the defects are; budget the sweep for them.

---

## 5. Consumers are verified in code

For each interface a change touches, a plan names the strongest check that
applies:

1. Derive: the consumers read one source in code, so they cannot disagree (a
   schema built from one item definition, a status set from one constant, a
   list read from the profile).
2. Check in code: the compiler or analyzer for code symbols, or a test that
   fails when a consumer disagrees with its source, which is how structured
   prose (tables, frontmatter, examples, headings) is checked.
3. Read: the code that uses the interface, in full.
4. Search: a text search only locates what to read. It never verifies, because
   a consumer that restates a rule in other words does not match.

---

## 6. Lenses, rounds and findings

### 6.1 Lenses

A round dispatches critics in parallel, each through one lens. A critic carries
no memory of an earlier round.

<!-- generated: lenses -->
| Lens | Sweeps |
|---|---|
| `runtime` | Mechanism, failure paths, lifecycle and re-entrancy; crossings with other components and timing risks; bounds, hot paths and the evidence behind each performance rank |
| `evidence` | Each decision table against the ranking rule and its missing options; every citation, count and framework claim against the source; the plan checks; each criterion traced to a named check that fails on the base commit; missing, ambiguous or conflicting requirements |
| `surface` | The public surface, every consumer verified in code, agreement with the documents the plan depends on, house conventions and the plan rules; each landing step done and committed from the base commit as written: its gates pass, its documents stay true, its commands run, its test seams exist |
| `consistency` | The last revision against its snapshot, the findings it received and their outcomes, and its obligations; runs only after a revision |
<!-- end generated -->

The profile's `lenses` add each lens's project addendum and reading list,
switch a core lens off, or add a project lens with its own focus.

### 6.2 Rounds

- Round 1 runs every lens of the pool except `consistency`, in parallel.
- After a revision, the next round runs each lens that raised a failing
  finding, the `consistency` lens, any lens that has not yet reported, and,
  when the revision changed a decision, the lenses that grade a decision's
  rank, `runtime` and `evidence`. A re-run lens receives the decisions the
  revision changed, the diff that shows every edit, and its own earlier
  findings with their recorded outcomes: it reviews the changed decisions, what
  depends on them and the sites of its findings, and may report anything else.
- Every critic receives the implementation findings already carried and the
  owner's decisions, and raises a finding that restates one only when the plan
  now contradicts it.
- Open premises are probed with the round: before it in a single checkout,
  since the critics read the working tree, and beside it in a worktree.
- A lens that reports `coverage` is dispatched once more in the same round,
  told the cause it gave. A lens that still cannot review, or that returns
  nothing, ends the run `failed` with that cause: a round is not clean on an
  angle nobody swept. The next launch runs the round again whole, and the
  first attempt's findings are discarded.

### 6.3 Findings

For each finding:

1. Confirm it against the source. Tool output, a critic's report and earlier
   audit records are leads.
2. Confirm it changes the plan: a true observation that changes nothing is not
   a finding.
3. Audit the fix as well as the problem. Check a fix to a decision against its
   table (section 3), and prefer a fix that removes the need for vigilance over
   one that adds a rule to remember.
4. Record the decision it concerns (`d<N>`, or `none`), its kind, its severity,
   and its defect class (one of the profile's, or `other`).

Kinds:

<!-- generated: kinds -->
- `rank`: It changes which option ranks first in a decision table, adds a valid option the table lacks, or shows false a statement a ranking rests on (a citation, a count or a premise included).
- `surface`: It changes the public surface, or breaks a format another component reads.
- `consistency`: The plan disagrees with itself or with the code it describes (a landing step that cannot be done or committed as written included), breaks a writing rule of section 2, or a revision did not do what section 7 requires of it.
- `scope`: A requirement is missing, ambiguous, or in conflict with another.
- `implementation`: Anything else: an edge case, a consumer, a rule no test pins, an inert assertion. It is carried to the step it lands in.
- `coverage`: The critic could not review; its lens counts as not reported.
<!-- end generated -->

Severity: `blocking` when following the plan builds broken code, or the plan
misstates the code or a documented invariant; `major` when it works with a
serious problem (significant cost, an untestable rule, fragile coupling, a
requirement not met); `minor` for a small improvement; `nit` for wording.

A finding fails when it is blocking or major and of kind `rank`, `surface`,
`consistency` or `scope`; severity alone never fails a round, and a round is
clean when no finding fails. A finding from the extractor, the builder or the
owner carries no kind, and fails when it is blocking or major; the probe's
findings are those of section 8.2. The script gives every
finding its id, by its source, its round and its position, so no two share
one.

- Every finding raised since the last revision goes to the next one, which
  records each in the audit file with its outcome: fixed, re-ranked, rejected
  with evidence, carried, or, for a finding that does not fail, left open with
  a reason.
- Every `implementation` finding is carried: the extractor places it in the
  step where it lands, and its signal there is a test shown to fail first, a
  mutation, or the check section 5 names.
- A failing `scope` finding ends the run `needs-scope`, with every scope finding
  of its round, so that the owner settles them together.

### 6.4 Approval

The script approves the plan when all of these hold:

1. The latest round raised no failing finding.
2. Every lens of the pool has reported on some version of the plan.
3. No premise is open.

The approval states its basis and claims nothing beyond the lenses that swept.
Each launch may spend the profile's `budget.rounds` critique revisions; a round
that still fails after that ends the run `budget-spent`, with the diagnosis:
each failing decision, the rounds it failed in, and whether a re-rank (section
7) was obliged. The owner resumes it with a fresh budget, or approves the plan
by stating the basis in `ownerApproval`. The Approval record (section 10) holds
the round, the basis, the premises and the findings since the last revision.

---

## 7. Revisions

A revision:

1. Copies the plan to its snapshot (section 1), and writes down the
   vocabulary it is about to replace. A snapshot that already exists was made
   by a dispatch of this revision that did not finish, and the revision
   finishes from it.
2. Addresses every finding it received and every obligation below, rewriting
   rather than appending (section 2.6).
3. Runs the consistency pass: diffs the plan against the snapshot and reads
   every section that used the replaced vocabulary. Each surviving use is a
   negation ("no longer X") or a defect; a search may locate the sections, and
   reading them is the check. Cross-references resolve and numbering stays
   contiguous.
4. Runs the plan checks' `rebase` commands, and appends a `Revision N` record
   to the audit file.
5. Reports the snapshot, the decisions it changed, every decision now in the
   plan, an outcome for each finding it received, any new premise, and any
   requirement conflict it cannot resolve, which ends the run `needs-scope`.

Re-rank: a decision with a failing `rank` finding is re-ranked when it had a
failing `rank` finding in an earlier round, or the previous revision changed
it. The revision adds the findings to its table as evidence and re-applies the
gate and the ranking, and the snapshot keeps the option it replaces. Keeping
rank 1 is allowed when the record says why. Any other fix may patch the chosen
option in place.

The next `consistency` lens receives the snapshot, every finding the revision
received with the outcome it recorded, the decisions it changed, its re-rank
obligations, and the lenses that did not re-run, whose cleared ground it
guards. A finding with no outcome, an unmet obligation, or a changed
decision that no received finding named and that depends on none that did, is a
failing `consistency` finding.

---

## 8. Building

### 8.1 Steps

The extractor reads the plan's Landing Order, Decisions and Testing Plan, and
returns:

- every decision the plan's Decisions section anchors;
- the repros, by test name;
- the steps, numbered from 1, each with its title, its anchor, its decisions,
  its files, its signal, and its group when the plan marks it NOT
  INDEPENDENTLY VERIFIABLE;
- one pin per decision: its code site and the test that pins it;
- each acceptance criterion, by its number, with the steps whose signals check
  it (step 0 for a repro);
- each carried finding with the step it lands in, or why it no longer applies;
- every gap: what it needs that the plan does not state.

The script checks the extraction: the decisions it reads are the ones the run
recorded, the steps are numbered without gaps, each has files, a signal and an
anchor, every decision has exactly one pin, every criterion is mapped once to
steps that exist, and every carried finding is placed. An extraction with a
problem or a gap is dispatched once more, told them; a problem or a gap that
survives it is a blocking finding for a revision (section 8.4). The next
extraction receives each of them with the outcome the revision recorded, and
reports one again only when the plan still lacks it, saying what the outcome's
note misses. There is no checklist file: the steps live in the run state, and
the commits on the build branch carry the trailer `Step: <n>`.

### 8.2 Probe

The builder, in probe mode, settles the open premises:

1. It stops, changing nothing, when anything under the profile's `codePaths` is
   uncommitted.
2. It cuts the probe branch from the base commit.
3. For each premise it writes the smallest code that settles it, never the
   feature, and runs only the commands the experiment needs.
4. It commits the scratch code, switches back, and appends a `Probe` record to
   the audit file: each premise's outcome, with what it observed.

The outcomes:

<!-- generated: premise-outcomes -->
- `held`: The experiment ran and its result shows the claim true.
- `not-held`: The experiment ran and its result shows the claim false: a major rank finding on its decision.
- `not-run`: The environment kept the experiment from producing a result (a gate that reports it could not run, a missing tool, a crashed process): the premise stays open, and the run ends failed with what was observed.
- `undecided`: The experiment ran, or cannot run as the plan writes it, and its result does not settle the claim (a difference within noise included): a major consistency finding on its decision.
<!-- end generated -->

### 8.3 Build

The builder works on the build branch:

1. It stops, changing nothing, when anything under the profile's `codePaths` is
   uncommitted on another branch; then it switches to the build branch, cutting
   it from the base commit when it does not exist, and appends the Approval
   record the script hands it to the audit file.
2. It runs the plan checks' `verify` commands. A failure on a line the branch's
   own commits changed is the plan being applied; any other whose claim no
   longer holds is a blocking finding.
3. Step 0: it commits the repros and records each one failing on the base
   commit. A repro that passes there is a blocking finding.
4. For each step, it makes the change, runs the step's signal, runs every gate
   of `step` scope whose `when` matches the files the step changed (the script
   lists those of its declared files), and commits the step's files, staging by
   path, with the trailer `Step: <n>`. Each carried finding is addressed in the
   step it lands in, and its evidence reported; one the extraction marks
   obsolete is confirmed against the plan and the code, or addressed when its
   reason does not hold. A step an earlier dispatch built is kept, not built
   again, only when the script lists it as verified under its title and its
   signal passes again; any other committed step is built, its signal and gates
   run again. The repros, mutations and carried findings an earlier dispatch
   settled are listed as done and not run again.
5. After the last step, one mutation per pin: it records the SHA-256 of the
   code site's file, breaks the rule there, runs the pin's test and observes it
   fail, restores the file and records the SHA-256 again, which must match.
   Only a mutation shows a rule is pinned; a test that stays green is a
   blocking finding.
6. It runs every gate of `final` scope whose `when` matches the files changed
   since the base commit.

The script checks the report: every step is reported; each step built in this
dispatch passed its signal and the gates its files trigger, which verifies it;
each step kept was verified by an earlier dispatch, under its title and the
same commit, and passed its signal again; every carried finding was addressed or confirmed
obsolete; every plan check was reported; every repro failed on the base
commit; every pin was mutated and restored; the final gates passed; and the
Approval record was appended. A report that breaks this is sent back once with
its problems, and a second breach ends the run `failed`. A builder whose
context is compacted hands over: a report that stops before the final gates
with no blocking finding, having verified a step or mutated a pin that no
earlier report of this build had, is no breach, and a fresh builder continues
the build.

The builder receives the profile's `hotPaths` and the `runtime` lens's
addendum as the project's runtime rules. On a hot path it adds none of
the costs they name unless the plan's decision for that code accepts it; a
step that cannot be built without one shows the plan wrong.

A failure that shows the plan wrong stops the builder, which reports a
blocking finding and its last committed step. A minor slip, such as a comment
that a step leaves false, is fixed within the step and reported as a discovery.

### 8.4 Implementation revisions

A blocking finding from the extractor or the builder starts a revision inside
the run, bounded by the profile's `budget.implementationRevisions` per launch:

1. The planner revises (section 7).
2. A round of the `consistency` and `surface` lenses, and of those
   section 6.2 adds after a revision, follows; the rounds continue as in
   section 6.2 until the plan is approved again.
3. The steps are extracted again.
4. The builder continues: it rebuilds, in new commits, each verified step that
   carries a changed decision, which is no longer verified, and addresses again
   each carried finding placed in such a step; keeps the others after checking
   their signals; and mutates each changed decision again. The
   revision may renumber the steps, so the builder is told the verified and the
   reworked steps by title and commit, never by number.

A spent budget ends the run `budget-spent`.

---

## 9. Acceptance

A reviewer who never reads the plan closes the run. It receives the request and
the acceptance criteria verbatim, the owner's user-visible behaviour,
constraints and non-goals, the base commit, the build branch, the files the
builder changed, and the hot paths and runtime rules the builder received;
reads every changed file in full; runs the tests the criteria name; and writes
the acceptance document: each criterion quoted and marked met, partial or unmet
with its evidence, then its findings about the code. A cost the performance
rules name, added on a hot path, that no constraint or criterion allows is a
major finding. A review that does not judge each criterion once, by its
number, is dispatched once more, told why; a second such review ends the run
`failed`.

The run is accepted when every criterion is met and the reviewer raised no
blocking or major finding. Otherwise a fix loop runs while the profile's
`budget.fixLoops` remains: the builder, in fix mode, fixes each gap at its root
cause in new commits with the trailer `Fix: <n>`, runs every gate its files
trigger, and reports every gap either fixed or needing the plan changed; a gap
whose fix needs the plan changed ends the run `acceptance-gaps`, as does one
that cannot be fixed without adding such a cost on a hot path. A fresh
reviewer, still blind to the plan, then judges every criterion again, given the
previous gaps to confirm.

A plan changes a guidance document only to state an invariant the change adds
or alters.

---

## 10. Statuses, records and resume

<!-- generated: statuses -->
| Status | Meaning | The next run starts at |
|---|---|---|
| `accepted` | Every acceptance criterion is met and the reviewer raised no blocking or major finding. | `done` |
| `acceptance-gaps` | After the fix budget a criterion is still not met or a blocking or major finding remains, or a fix needs the plan changed. | `done` |
| `needs-scope` | The draft or a revision returned scope questions, or a round raised a failing scope finding. | `revise` |
| `budget-spent` | The critique revisions or the implementation revisions of this launch are spent with failing findings open. | `revise` or `steps` |
| `failed` | An agent returned nothing (it was skipped or died), a result broke its contract twice, a precondition failed, or the probe could not run an experiment; `reason` says which. | the phase its state names |
<!-- end generated -->

The audit file, beside the plan, holds the run's history. Each writer creates
it with a one-line title when it is absent and appends; no record is rewritten.
The audit file and the revision snapshots are history, and no plan check reads
them.

| Record | Written by | Holds |
|---|---|---|
| `Run` | the start skill | The first launch's base commit and branch, then each result's status, the phase the next run starts at, and the time |
| `Revision N` | the planner | One line per finding received: its id, its source, kind, severity and outcome |
| `Probe` | the builder, in probe mode | Each premise's outcome (section 8.2), with what was observed |
| `Approval` | the builder, verbatim from the script | The round, the basis, the premises and the findings since the last revision |

Every result carries `state`: the phase the next run starts at, the base
commit, the rounds, the lenses swept, the decisions and premises, the findings
in flight and carried, the re-rank history, the approval, the steps, the build
progress and the metrics. The script is its only author, except for the
initial record, which the start skill writes at a slug's first launch:

<!-- generated: initial-record -->
```json
{"workflow":"feature-delivery","version":1,"phase":"draft","baseRef":"<the base commit>"}
```
<!-- end generated -->

After every result the start skill writes the result's `state` to the run
record. A resumed run receives the record as `resume` and starts at its phase,
or at `start`:

- `priorFindings` adds findings from outside the run to a run that starts at
  `revise`.
- `ownerApproval` states the owner's basis, and is required to start past the
  critique when no clean round approved this version of the plan, or past
  failing findings a revision has not received.
- `budget` overrides the profile's budget for one launch; every launch has the
  full budget otherwise.

A run killed before its result arrived wrote no new record. In the launching
session it resumes through the runtime's `resumeFromRunId`, which returns its
finished agents from cache. In another session it resumes from the run record
at the record's phase and repeats what the killed run did since: the plan as
the killed run left it is critiqued again, the extraction's decision check
catches a decision list the record no longer matches, and the builder builds
again, with its signal and gates, any step the killed run committed.

A revision that ends the run before any round checks it (for a scope question)
is chained into the next revision: the next consistency lens diffs from the
earlier snapshot and is told both revisions' changes and outcomes.

<!-- generated: cost -->
A clean run is 7 agents: the draft, the 3 lenses of round 1, the extractor, the builder and the reviewer.
<!-- end generated -->

A revision adds the planner, each lens that raised a failing finding and the
consistency lens, plus the `runtime` and `evidence` lenses when it changes a
decision; open premises add the probe; an agent dispatched again adds
one. The state's `round` and `revisions` count the rounds and revisions, and
its `metrics` count the launches, the statuses returned, the agents by role,
the implementation revisions, the fix loops, the builder handovers, the
failing findings by lens and the defect classes found. The `Run` records give the wall time.

---

## 11. Timed measurement

Deterministic counters need no noise floor. A timed comparison follows this
protocol:

- Expectations are declared before measuring, and carry no consequence.
- A noise floor comes from A/A runs.
- The verdict comes from a committed comparison script reading what the
  artifacts record (order, tree, settings, inputs), built when the first
  comparison needs it.
- A rerun happens only when a verdict earns one.
- A rule change applies to a fresh series only, never to data already measured.
- Measured code is committed at exactly the hashes the verdict recorded, and a
  follow-up fix lands as its own commit.

---

## 12. The profile

The profile is a JSON document the start skill passes to the workflow, which
cannot read files. Every key has a reader:

<!-- generated: profile -->
- `version` (required): The profile format: 1.
- `artifactsDir` (required): The directory, relative to the repository root, holding each run's plan, snapshots, audit file, acceptance document and run record.
- `codePaths` (required): The directories and files a run may change: every path a gate's `when` or a module's `paths` matches lies under one, and `.` is the whole tree. The probe and the builder stop when anything there is uncommitted.
- `isolation` (required): `checkout` runs every agent in the launching checkout; `worktree` runs the probe, the builder and the reviewer each in a git worktree of their own.
- `preflight` (optional): Each with `name`, `command` and `pass`: a check of the environment the start skill runs before every launch, which launches only when each passes.
- `conventionDocs` (optional): The house convention documents the planner, the builder and the reviewer read.
- `modules` (optional): Each with `paths` (regular expressions over repository paths), `guidance` (its architecture rules) and `vocabulary`. A run reads the guidance of every module its files match.
- `gates` (required): Each with `name`, `command` (in which `{base}` stands for the base commit), `pass` (its pass condition), `when` (`"always"`, or `{"paths": [...]}`, regular expressions matched against the changed files) and `scope` (`step`: at each step's commit; `final`: once, after the mutations).
- `lenses` (optional): Per lens, optional `reads` (the files it reads; `moduleGuidance` and `conventionDocs` expand to those lists; default `moduleGuidance`), `addendum` (project text appended to its focus) and `enabled` (false switches a core lens off; never `consistency`). Any other key adds a project lens, which needs a `focus`. The planner receives every enabled lens's reads and addendum, and a project lens's focus; the builder and the reviewer receive the `runtime` lens's addendum and the `hotPaths`.
- `ranking` (required): The ranking criteria, in order (section 3).
- `hotPaths` (optional): Where the hot-path performance criterion applies.
- `planRules` (optional): The project's own requirements for a plan: the planner writes to them and the surface lens checks them.
- `planChecks` (optional): Each with `name` and `verify`, a command that exits 0 when the plan passes, and optionally `stamp` (run on a new plan), `rebase` (run after a revision) and `note` (how to act on its output); `{plan}` stands for the plan path.
- `citations` (optional): An object of settings that a plan check reads from this file itself; the workflow accepts it unread.
- `defectClasses` (optional): The defect classes a finding may name; the result counts them per run.
- `roles` (optional): Per role (planner, critic, extractor, builder, reviewer), optional `model` and `effort` for its agents.
- `budget` (required): `rounds` (critique revisions per launch), `implementationRevisions` (revisions after approval per launch) and `fixLoops` (fix rounds after a review), all integers.
<!-- end generated -->

Whether a role's `model` resolves at run time is unverified until a run uses
it; each agent's transcript records its model. A project adopts the method by
writing its own profile.
