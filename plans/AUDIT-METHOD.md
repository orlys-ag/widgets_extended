# Plan audit method

How to write a plan that stays auditable, audit it, and close it. The method is
project-neutral: every project fact it uses comes from the project profile,
`doc/agents/method-profile.json` (section 11).

---

## 1. Angles

Before the first round, write the angle list, mark each angle unswept, and work
down it. Start from these and add the plan's own:

1. Mechanism: the components and their interactions.
2. Public surface: signatures, types, exports, naming.
3. Consumers and call sites: everything that must change (section 8).
4. Contracts with the documents the plan depends on, or that depend on it,
   including a documented contract the plan changes without saying so.
5. The test list: each test writable, failing on unfixed code, following the
   house conventions, and each new test seam justified against an existing one.
6. Citations and claims (section 3).
7. House conventions: the profile's convention documents and the module
   guidance of the code the plan touches.
8. Failure paths: what happens when a precondition is not met, empty and
   single-element inputs included.
9. Lifecycle: creation, teardown, every site that destroys the thing, and every
   path that recreates, detaches or re-attaches it without the change's own
   code running.
10. Performance bounds: what is O(what), and whether the stated bound is the
    one that can blow up.

Section 4 assigns the angles to lenses; section 6's stopping rule is defined
against the list.

---

## 2. Writing a plan

Apply these when writing. A violation found when auditing is a finding.

### 2.1 One site per fact

Exactly one place states each decision. Every other mention refers to it
("per 4.1") instead of restating it.

### 2.2 Summary sections go stale first

When a component section changes, re-read every section that paraphrases
decisions made elsewhere: the overview, the lifecycle walkthrough, the
contracts list, the decisions list, the costs summary and the test list.

### 2.3 Counts and universals carry their command

A count, or a claim with "every", "all", "only", "none", "the sole" or "always",
carries the command that established it, or is rewritten as an enumeration
(preferred when the list is short). A count of a code symbol's users comes from
code (section 8), not from a text search.

### 2.4 Declare every artifact the implementer creates

Its name, signature, where it lives, and whether it is exported.

### 2.5 Landing order

When the change spans components, files or public names, list the steps in
dependency order and mark each grouping that correctness forces. Each step names
the test that goes green when it lands, or is marked NOT INDEPENDENTLY
VERIFIABLE with the reason. A pure restructuring that makes the behaviour change
small lands first, in its own commit.

### 2.6 Write the design, not its history

A plan describes the feature as it will be built: its goals, its decisions, and
how to build and test it, as concisely as an answer to the owner. How it got
there belongs in its audit file (section 4), which the plan names at most once.

- Write the final state: never "previously", "round 2 changed", "an earlier
  draft said" or "the audit found". Today's code, which the change is made
  against, is the feature's problem and stays.
- A revision rewrites the sentence that was wrong; it never appends a note
  beside it.
- A rejected option is one table row with its reason, named for what it is,
  never for when it was tried. Its evidence may cite the audit file.
- No defensive prose: do not answer a critic in advance unless an implementer
  needs the constraint.
- The deletion test: a sentence whose removal changes nothing an implementer
  builds or a reviewer checks is removed.

### 2.7 Decisions are ranking tables

Each architecture, performance or algorithm choice is a subsection of the
plan's Decisions section, anchored `d<N>`: the decision; a problem statement
when it answers a defect in today's behaviour; its rules, a list giving for
each the rule, its code site and the test that pins it (section 9); and a table
with the columns Rank, Option, Gate, Evidence and Assessment. A rule is one
condition, branch or value whose change alters an observable outcome, so a
decision that adds two branches lists two rules.

- Gate: pass or fail, with the reason. An option passes when it is correct,
  meets the goals and requirements, preserves every documented invariant, is
  idiomatic for the language, the framework and the codebase, keeps the public
  API compatible unless a goal says otherwise, and removes no safeguard without
  a replacement. A failing option stays in the table, below every passing one.
- Evidence: each claim labelled, strongest first: measured (a timed or counted
  run, section 10), demonstrated (a recorded test, run or audit), traced (a
  code path or normative document read), computed (arithmetic from stated
  inputs), design-only. A rank-1 option resting on design-only evidence names
  the check that will produce evidence.
- Rank: passing options in the order of the profile's ranking criteria, a tie
  on one criterion going to the next. The hot-path performance criterion
  applies only on the profile's hot paths. A difference within measurement
  spread, or within one complexity class when computed, is a tie. A plan whose
  decisions are not code decisions declares its own criteria in the Decisions
  preamble.
- The top-ranked passing option is the decision. Rejected options stay in the
  table, so a re-rank (section 5) can choose one.

The owner may supply decisions with their evidence before the plan is written;
the architect adopts each as its starting table and may add options.

### 2.8 Guidance documents

A plan changes a guidance document only to state an invariant the change adds
or alters.

---

## 3. Citations and claims

Write each citation in backticks, `path:line` or `path:line-line`; the checker
reads no other form. Cite a repository file by its path from the root (a
filename alone only when exactly one file git tracks or would track has that
name), and an SDK file by its path under the profile's SDK root. A continuation,
`` `:123` ``, attaches to the last file cited in that form, even when another
file was named since in prose. A citation of a file whose extension the profile
does not list is read by hand.

`plans/check_citations.py` anchors a plan's citations to the tree they were read
on. It commits a snapshot of the working tree, with every file the plan cites,
under `refs/citations/` (on no branch), and writes the snapshot's id into the
plan's CITATIONS marker, which is never edited by hand:

    python plans/check_citations.py plans/<plan>.md             # verify
    python plans/check_citations.py plans/<plan>.md --stamp     # a new plan
    python plans/check_citations.py plans/<plan>.md --rebase [--accept <path:line> ...]
    python plans/check_citations.py --self-test

Verify reads the plan's live sections and maps each citation through `git diff`
from the snapshot to the files on disk. A citation passes as OK (its lines
unchanged, at their numbers) or MOVED (unchanged, at other numbers). It fails on
CHANGED, NEW, UNRESOLVED, PAST-END and DANGLING: a cited line edited or removed,
or a line inserted inside a cited range; a citation the snapshot does not
record; a name that matches no file or several; a line past the end of its
file; a continuation after a citation whose extension the profile does not
list.

Check a plan's citations when it is written or revised, at the start of each
round on it, and before it is implemented. Each failing citation is a finding:
re-read the code, correct the claim, and cite the line it now concerns. Then run
`--rebase`: it renumbers MOVED citations, keeps NEW ones and stamps the current
tree. Name with `--accept` each CHANGED citation re-read and kept at its number;
`--rebase` writes nothing while another is CHANGED. A plan whose run is done
keeps its marker.

The claim pass sweeps angle 6, at least once per plan:

1. Run the checker and re-read each citation it flags.
2. Run the command behind every count and universal (section 2.3).
3. Verify every framework-behaviour claim against the SDK source; recall is a
   hypothesis.

Steps 2 and 3 are where the defects are; budget the pass for them.

---

## 4. Rounds, lenses and findings

A round dispatches critics in parallel, each through one lens. A critic carries
no memory of an earlier round.

| Lens | Stage | Sweeps |
|---|---|---|
| `correctness` | standard | Angles 1, 8 and 9 |
| `performance` | standard | Angle 10, and whether each measured or computed evidence cell supports its rank |
| `design` | standard | Angles 2, 3, 4, 5, 6 and 7 at decision level; each acceptance criterion traced to a check that can fail in the direction it claims; scope; the option set; rule 2.8 |
| `interaction` | fresh | The feature crossed with every other component, layer and entry point, a space reading samples and never covers |
| `timing` | fresh | Behaviour under real timing (ordering, settle transitions, re-entrancy): which risks only running the code settles, and whether each is a named test rather than an argument |
| `consistency` | after a revision | The revision against its snapshot, the findings it received and its obligations (section 5) |

- The first round runs every standard lens, plus the consistency lens when a
  revision precedes it.
- After a failing standard round, the next round runs the lenses that raised a
  failing finding, plus the consistency lens, which guards the sections the
  others cleared. After a failing fresh angle, it runs the consistency lens
  alone.
- A fresh lens runs only after a clean standard round, and once per plan.
- The design critic receives the requirements; without them it reports
  `coverage`. The profile adds each lens's reading list and project addendum,
  and the addendum of the module the change touches.
- Every dispatched lens must report. A lens that returns nothing, or reports
  `coverage`, is dispatched once more in the same round. If it still cannot
  review, the run ends; the next run dispatches that round again with all its
  lenses, and the first attempt's findings are discarded.

### Each finding

1. Confirm it against the source. Tool output, a critic's report and earlier
   audit-file entries are leads.
2. Confirm it changes the plan: a true observation that changes nothing is not
   a finding.
3. Audit the fix as well as the problem. Check a fix to a decision against its
   table (section 2.7), and prefer a fix that removes the need for vigilance
   over one that adds a rule to remember.
4. Record the decision it concerns (`d<N>`, or none), its kind, its severity,
   and its defect class (one of the profile's, or other).

Kinds:

- `rank`: it changes which option ranks first in a decision table, adds a valid
  option the table lacks, or shows false a statement a ranking rests on (a
  citation or count included).
- `surface`: it changes the public surface, or breaks a format another
  component reads (a required section, an anchor, the status line).
- `consistency`: the plan disagrees with itself or with the code it describes,
  breaks a writing rule of section 2 (usually minor when nothing contradicts),
  or a revision did not do what section 5 required of it.
- `scope`: a requirement is missing, ambiguous, or in conflict with another.
- `implementation`: anything else: an edge case, a consumer, a rule no test
  pins, an inert assertion, a mutation survivor.
- `coverage`: the critic could not review; its lens counts as not reported.

Severity: `blocking` when following the plan builds broken code, or the plan
misstates the code or a documented invariant; `major` when it works with a
serious problem (significant cost, an untestable rule, fragile coupling, a
requirement not met); `minor` for a small improvement; `nit` for wording.

A finding FAILS when it is blocking or major and of kind `rank`, `surface`,
`consistency` or `scope`; severity alone never fails a round. A round is clean
when no finding fails.

Where findings go:

- A failing `scope` finding ends the run; the owner settles the requirement and
  resumes.
- Every finding raised since the last architect step (a revision or the
  approval) goes to the next one, which records each in the audit file with
  its outcome: fixed, re-ranked, rejected with evidence, carried, or, for a
  non-failing finding, left open with a reason.
- Every `implementation` finding also goes to the checklist, as an item whose
  acceptance is a test shown to fail first, a mutation, or the check section 8
  names; one that no longer applies is listed with the reason.
- A run that ends before an architect step carries those findings in its state
  to the next run's first one, except a round's findings discarded for
  coverage.

The audit file, `plans/<date>-<slug>-audit.md` beside the plan, holds the round
records, the trial log and the run records. A round record has one line per
finding: its id, lens, kind, severity, outcome and the section it touched, with
a reason only where the outcome needs one. The plan holds only what
implementation needs, plus its Approval block. The audit file and the revision
snapshots are history, and are never cite-checked.

---

## 5. Revisions and loop control

A revision:

1. Copies the plan to the first free `<plan>.r<N>`, and writes down the
   vocabulary it is about to replace.
2. Addresses every finding it received and every obligation below, rewriting
   rather than appending (rule 2.6).
3. Runs the consistency pass: diffs the plan against the snapshot and reads
   every section that used the replaced vocabulary. Each surviving use is a
   negation ("no longer X") or a defect; a search may locate the sections, and
   reading them is the check. Cross-references resolve and numbering stays
   contiguous.
4. Checks the citations (section 3), and reports the snapshot and the
   decisions it changed.

The next consistency lens receives the snapshot, every finding the revision
received, the decisions it changed and its obligations. An unmet obligation, or
a changed decision that no received finding named and that does not depend on
one that did, is a failing `consistency` finding. A revision that returns
nothing leaves no snapshot and no changed decisions; that lens reads the
revision's record instead.

After every round, standard or fresh:

- R1, re-rank. A decision with a failing `rank` finding is re-ranked when it
  had a failing `rank` finding in an earlier round or the previous revision
  changed it: the revision adds the findings to its table as evidence and
  re-applies the gate and the ranking, and the snapshot keeps the option it
  replaces. Keeping rank 1 is allowed when the record says why. Any other fix
  may patch the chosen option in place.
- R2, scope. A failing `scope` finding ends the run (section 4).
- R3, mechanize. A profile defect class found in two rounds, at any severity,
  obliges the next revision, or the checklist when no revision follows, to add
  a check for it, preferring a code check (section 8).

A run has a round budget, declared before it starts. A spent budget is reported,
not extended silently: each failing decision, the rounds it failed in, and
whether R1 re-ranked it.

These rules and section 6 hold across runs. A run that stops returns its state:
the round count, the fresh angles spent, the loop history and the findings in
flight; the next run resumes from it. A run killed before it returns resumes
from the last state an earlier run returned and repeats what it did since, and a
fresh angle it may have opened counts as spent: a second pass cannot approve
the plan.

A revision of an approved plan first sets it back to draft. A plan whose run is
done is not reopened: a later change is a successor plan, whose run starts from
code that contains the earlier change, once the owner has merged it.

---

## 6. Stopping and the verdict

Two clean passes within a round measure the lens, not the plan, and do not stop
the audit. Stop when either:

- Coverage: every angle on the list has been swept, a standard round came back
  clean, and a fresh angle then came back clean on its FIRST pass; or
- Yield: the last round produced only wording-level findings, with no
  consequence for implementation, testing or the public surface.

Interaction and timing risks are settled by running code, not by more rounds:
once the plan is stable, write its tests (as skipped stubs while the code is
blocked), and stop auditing when only these risks remain.

Never write an unqualified "fit to implement". Write:

    VERDICT: fit as far as ANGLE goes. Unswept: ANGLE, ANGLE.

---

## 7. Trials

A trial applies the plan's highest-risk section on a branch, runs the section's
repro against unfixed and fixed code, and runs the profile gates that apply. It
catches a section that reads correctly and builds wrong. A trial passes when its
repro fails before and passes after, each rule it lands fails its named test
when broken (section 9), every gate that applies passes, and it found no plan
defect. A named test that passes with its rule broken shows the plan's pin
claim wrong, which a revision corrects before approval.

A trial is kept, never reverted:

- It is committed only with the owner's authorization: in the workflow,
  confirming the run gives it; in a hand audit, ask, and without an answer save
  the diff as a patch where the plan names. It lives on a branch cut from the
  base commit the plan was audited against, one commit per section, with the
  repro promoted into the test tree in the same commit.
- A trial that fails on a plan defect changes the plan: the failure becomes
  evidence for a rejected option in its decision's table, or a corrective commit
  follows it. One that fails on an implementation slip is fixed and run again.
- Nothing is reverted without its diff saved. A later trial that needs unfixed
  code runs its "fails before" check against the earlier commit (a worktree),
  not by undoing work.
- The audit file's trial log records each trial. The branch or the patch is a
  deliverable of the audit, named in the verdict; merging it is the owner's
  decision, and a fix found after a trial lands as its own commit.

A plan whose sections have all been trialed has angle 1 swept by construction;
later rounds open other angles.

---

## 8. Consumers are verified in code

For each interface a change touches, a plan names the strongest check that
applies:

1. Derive: the consumers read one source in code, so they cannot disagree (a
   schema built from one item definition, a status set from one constant, a
   list read from the profile).
2. Check in code: the compiler or analyzer for code symbols, or a test that
   fails when a consumer disagrees with its source, which is how structured
   prose (tables, frontmatter, examples, headings) is checked.
3. Read: the code that uses the interface, in full; for a change to the method
   itself, every file in the profile's `methodFiles`.
4. Search: a text search only locates what to read. It never verifies, because
   a consumer that restates a rule in other words does not match.

---

## 9. Closing

The checklist's last phase opens with one item per rule the decisions list
(section 2.7). For a rule whose code site lies under the profile's code paths it
is a mutation: break the rule there, observe a named test fail, restore the
file, and record the test name and the file's SHA-256 before and after, which
must match. When the named test passes with a right rule broken, the implementer
adds a test that fails and records the plan's wrong claim without stopping; only
a wrong rule stops the work. For a rule that lands only in documents it is the
check section 8 names for it. Showing that each new assertion can fail does not
show that each rule is pinned; only a mutation of the rule does. The profile's
gates that apply follow, so the suite runs after the last restore.

A reviewer who never reads the plan closes the run. It receives the request and
the acceptance criteria verbatim, the commit the run started from and the branch
holding the change; reads every file the change touched in full; runs the tests
the criteria name; and writes the acceptance document: each criterion quoted
and marked met, partial or unmet with its evidence, then its findings.

The owner may also require implementation audits after the run. In each round
a critic who wrote none of the code reads the plan against the code on the
run's branch, sweeping angles no earlier round of the audit swept, and mutates
every rule the change lands, listed or not, on a scratch copy of the branch.
The owner states how many successive clean rounds close the work. An
acceptance gap or an audit finding goes one of two ways:

- The code or its tests fall short of the plan: it is fixed by hand on the
  run's branch, each new assertion shown to fail first, and the next round
  audits the fix with the rest. In the workflow, a queued finding fixed this
  way is passed to the next run as `resolved` (contracts section 13).
- The plan is wrong (a premise, a decision or a rule): it starts a successor
  plan (section 5), never a fix by hand, because a design change needs the
  rounds and the trial a hand fix skips.

---

## 10. Timed measurement

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

## 11. The profile

The profile is a JSON document the launcher passes to the workflow, which
cannot read files. Every key has a reader:

- `codePaths`: the directories holding the code and its tests.
- `conventionDocs`: the house convention documents an implementer reads.
- `methodFiles`: the files a change to the method re-reads (section 8).
- `gates`: each with `name`, `command`, `pass` (its pass condition) and `when`
  (when it applies; `always` for every change).
- `modules`: each with `paths` (regular expressions over repository paths),
  `guidance` (its architecture rules), `vocabulary`, and optionally
  `lensAddenda` (by lens key, text appended to the lens's focus when the change
  touches this module).
- `lenses`: one entry per lens of section 4, each with `reads` (the files the
  lens reads, where `moduleGuidance` and `conventionDocs` expand to those
  lists) and `addendum` (project text appended to the lens's focus).
- `defectClasses`: the classes R3 tracks (section 5).
- `ranking`: the ranking criteria, in order (section 2.7).
- `hotPaths`: where the hot-path performance criterion applies.
- `citations`: `sdkRoot`, and the `extensions` the checker reads.
- `planRules`: the project's own requirements for a plan, which the architect
  writes to and the design lens checks.

A project adopts the method by writing its own profile.
