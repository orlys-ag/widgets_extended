# Plan audit method

How to write a design or implementation plan that stays auditable, how to
audit it, and how to close it. This is the project-neutral core. Every
project fact the method reads (code paths, gates, module documents, lens
addenda, defect classes, ranking criteria, hot paths, citation settings)
lives in the project's profile, which the project's agent instructions
name; this document refers to the profile and never restates it.

Derived from auditing two plans in one session (10 rounds and 5 rounds),
then from an 18-item review series and a 3-round audit of this method's own
revision. The numbers quoted below are from those audits and are the reason
each rule exists; treat them as evidence, not decoration.

Read this before starting an audit round, and again before writing a new
plan.

---

## 1. The two failure modes this exists to prevent

**A. The stopping rule lies.** Both plans repeatedly closed a round with
two consecutive clean passes, and the next round found defects on its
FIRST pass. The 10-round plan did this at rounds 8, 9 and 10; the 5-round
plan at rounds 2, 3, 4 and 5. The cause is not carelessness. A round
exhausts one LENS, and the second clean pass mostly confirms the lens is
exhausted, not the artifact. Findings cluster hard by angle: all eight of
the 5-round plan's round-3 findings were public surface, all three of
round 5's were unverified claims.

**B. The audit generates its own defects.** The single most common
defect class across both audits was not subtle design error. It was a
decision changing in one section while the summary sections kept
asserting the old one. That happened at least six times in the 5-round
plan alone, and in round 4 two of six findings were the round's own
earlier fixes going wrong. Any process that edits prose is also producing
defects, so it converges only if the fix rate beats the introduction rate.
The audit of this method's own revision showed the same loop at the level
of design: the blocking findings of its second round sat on mechanisms its
first revision had added, which is what section 14's re-rank rule answers.

Everything below is aimed at one of those two.

---

## 2. Before the first round: enumerate the angles

Do not discover angles one round at a time. Write the list first, mark
each unswept, and work down it. A usable default set:

1. Internal mechanism (the components and their interactions)
2. Public surface (signatures, types, exports, naming)
3. Consumers and call sites (everything that must change, verified per
   section 15)
4. Contracts with dependent or dependency documents
5. The test list as a deliverable (is each test writable, will it fail
   on unfixed code, does it follow house conventions, and is each new
   test seam justified against an existing one). Its execution half is
   swept by running the code (section 16); whether each named check can
   fail is a design question (section 13).
6. Citations and claims (section 4 below)
7. House-convention compliance (the profile's convention documents, and
   the module document of the code the plan touches)
8. Degradation and failure paths (what happens when a precondition is
   not met)
9. Lifecycle and disposal (creation, teardown, and every site that
   destroys the thing)
10. Performance bounds (what is O(what), and is the bound the one that
    can blow up)

Add angles specific to the plan's subject. The list is the audit's
coverage map, and section 6's stopping rule is defined against it.
Section 13 assigns the angles to critics.

---

## 3. Rules for the plan document itself

These make a plan auditable. Apply them when writing, and fix
violations when auditing.

### 3.1 One normative site per fact

Exactly one location states each decision. Every other mention is a
REFERENCE ("per 4.1"), never a restatement. A reference cannot go stale;
a paraphrase always can.

This is the structural cure for failure mode B. Before adding a sentence
that restates a decision, ask whether a cross-reference would do.

### 3.2 Summary sections are a known hazard

These sections attract stale text because they paraphrase decisions made
elsewhere: the one-paragraph architecture, the lifecycle walkthrough,
the contracts list, the decided-decisions list, the costs summary, and
the test list. When any component section changes, re-read exactly those
six. Treat it as a checklist item, not as something to remember.

### 3.3 Citations must be re-anchorable, by a ledger not by inline tokens

A line number alone rots silently when the file moves. Something has to
record WHAT the citation pointed at, so a checker can find where it went.

Inline `path:line :: token` works for a document with a handful of
citations. It does not scale: the 5-round plan has 170 citation
instances, and tokenising them inline would have added more noise than
the whole audit-narration cleanup removed, fighting rule 3.2 directly.

USE A GENERATED LEDGER INSTEAD. Keep prose citations bare (`path:line`),
and record the expected content in a sidecar that a script regenerates:

    python plans/check_citations.py plans/<plan>.md --update   # record
    python plans/check_citations.py plans/<plan>.md            # verify

The ledger is a DERIVED artifact, so it does not violate rule 3.1: only
the checker writes it, never a hand edit. `check_citations.py` reads only
the live sections, resolves repository and SDK paths with the profile's
citation settings, and sorts each citation: OK when its line still holds
the recorded content, MOVED when the content is elsewhere in the file,
GONE when it is nowhere in the file. It exits non-zero only on GONE, an
unrecorded or unresolved citation, or a DANGLING one (section 4), so it
can gate CI. `--self-test` runs its own cases.

Run it when the plan is about to be relied on (written, revised, audited,
implemented), not after every change to the project's code. A moved line
costs nothing until then, and a GONE citation is a claim to re-read at
that point, not bookkeeping.

SPELL EACH PATH ONE WAY. A file cited as both `proxy_box.dart` and
`rendering/proxy_box.dart` is one file to a reader and two to a
checker, which is how a verification script reports phantom misses or
silently skips a real one. Pick a form per source and hold it: repository
files by their bare filename, or by their path when the bare name is not
unique, and SDK files as `<subdir>/<file>`. This rule exists because the
5-round plan accumulated three files spelled two ways each over six
rounds, and nobody noticed until a count of "cited files" came back 24
against a true 21.

### 3.4 Counts and universal claims must carry their command

Any claim containing "every", "all", "only", "none", "the sole" or
"always" is a QUERY, not a statement. It must carry the command that
establishes it, or be downgraded to a specific enumeration.

NUMBERS ARE THE SAME PROBLEM. "Seven counters", "four call sites",
"three sites gate on this": each is a count somebody eyeballed once, and
plausible numbers are precisely the ones no later reader rechecks. The
5-round plan asserted "seven counters today" and "and four more" where a
grep returns six, in two places, both written from a glance at a list.
Run the command, quote the number it returns, and prefer an enumeration
to a total where the list is short. A count of a code symbol's users
comes from code (section 15), not from a text search.

This is not pedantry. Of four universal claims checked in the 5-round
plan's round 5, three were wrong or imprecise: "the sole `_dirtyKeys`
consumer" (three sites touch it), "already per-frame coalesced" (two
sources dispatch uncoalesced), and "every public builder in this package
is a typedef" (the counterexample was the very widget the feature
extends). All three read as checked facts. Each took one grep to
disprove.

### 3.5 Declare every public artifact the plan depends on

If the plan references a thing an implementer must create, the plan
declares it: name, signature, where it lives, and whether it is
exported. Three separate instances of this were missed in one plan: the
builder's signature was never declared at all, the reference widget was
referenced seven times and never named, and a typedef was specified
without noting that the package exports through explicit `show`
clauses, so it would have been unnameable by app code.

### 3.6 State the landing order when the work spans layers

If the change touches multiple widgets, files, or public names, say what
lands together and what can follow, and call out any grouping that is
forced by correctness rather than convenience.

Each step also names the test that goes green when it lands. A step that
cannot name one is marked NOT INDEPENDENTLY VERIFIABLE with the reason,
which is a real category: a paint change and its hit-test mirror must
land together or a row is unclickable for a commit. The point is not to
forbid the grouping, it is to make an unexamined one visible. Without
this rule a plan spanning controller, render object and element splits
by layer, and nothing is testable until the last step lands.

Where a plan contains a pure restructuring that makes the behaviour
change small, it lands first and in its own commit, so the behaviour
diff is reviewable on its own.

### 3.7 Write the design, not its history

A plan describes the feature as it will be built: its goals, its decisions,
and how to build and test it, as concisely as an answer to the owner. How the
plan reached that state belongs in its audit file (section 12), and the plan
points there at most once.

- Write the final state. A plan never says "previously", "round 2 changed",
  "an earlier draft said" or "the audit found". Today's code against the
  change is the feature's problem, not the plan's history, and stays.
- A revision rewrites; it never appends. A fix replaces the sentence that was
  wrong, and adds no note or clarification beside it.
- A rejected option is a design alternative: one table row with its reason,
  named for what it is, never for when it was tried. Its evidence may cite
  the audit file.
- No defensive prose: do not answer a critic in advance unless an implementer
  needs the constraint.
- The deletion test: a sentence whose removal changes nothing an implementer
  builds or a reviewer checks is removed.

Plans grow by accretion, not by design. In one review series, plans for
single fixes ran 13,000 to 25,000 words, and one needed a separate
32,000-word history file before it could be implemented.

---

## 4. The citation and claim pass

Run this as its own angle, at least once per plan, ideally scripted.

1. Run `check_citations.py` (rule 3.3). It handles extraction,
   resolution and verification for the whole document, and every GONE
   citation it reports is a claim to re-read.
2. Read what it flags. A BARE continuation citation (`` `:123` ``)
   attaches to the last file named in CITATION form. After a citation
   whose extension the profile lists, that is the file meant; after one
   whose extension it does not list, the checker reports the
   continuation as DANGLING. Naming a file in running prose and then
   citing bare lines still attributes them silently to the last cited
   file: the checker catches that only when the line is out of range,
   and a reader would not catch it at all.
3. Extract every universal quantifier and every count, and run its
   command (rule 3.4).
4. Verify every framework-behavior claim against the SDK source, not
   from memory. Recall of framework internals is a hypothesis.

Useful calibration from round 5: all 21 cited files were correct,
including two below a commit that had inserted 8 lines earlier in the
same session. Drift was not the problem. CLAIMS were. Budget accordingly:
the citation check is cheap and worth automating, but the claim check is
where the defects are.

---

## 5. What a pass is, and the consistency pass

A pass sweeps one angle and produces findings. For each finding:

1. **Confirm it against source** before treating it as real. Tool output
   and prior audit-file entries are leads, not findings.
2. **Confirm it affects the plan.** A true observation that changes
   nothing is not a finding.
3. **Audit the solution**, not just the problem. A fix to a decision is
   a re-ranking of its table (section 11): the alternatives are already
   there, with the evidence for and against each. Prefer a solution that
   removes the need for vigilance over one that adds a rule to remember.
4. **Record it** in the plan's audit file with its kind (section 12), its
   evidence and its outcome.

### The consistency pass is mandatory after any edit round

Before editing, write down the OLD vocabulary the change is replacing,
and save a snapshot of the plan. After editing, diff against the
snapshot, and read every section that used the old vocabulary. Every
surviving use is either a negation ("no longer X") or a defect. A search
for the old terms may locate those sections; reading them is the check.

This step catches what re-reading the whole plan does not. In round 4 it
found stale text four separate times, faster than reading each time.
Example vocabulary deltas from real rounds: "pushed" to "live getter",
"animating set" to "mounted set", "just-settled" to nothing, "poke set"
to nothing, "default builder" to a widget name.

---

## 6. Stopping rule

Do NOT stop on two consecutive clean passes within a round. That
measures the lens.

A round is clean when it has no failing finding (section 12). Stop when
either:

- **Coverage**: every angle on the section 2 list has been swept, a
  standard round came back clean, and a freshly opened angle then came
  back clean on its FIRST pass; or
- **Yield**: the last round produced only wording-level findings with no
  consequence to implementation, testing, or the public surface.

Track findings per round with severity and kind. Observed decay in the
5-round plan was 9, 8, 6, 3, with round 5's three being one test design
change, one justification replacement, and one phrasing fix. That is
roughly where a plan is done.

Declare a round budget in advance so the process terminates by design
rather than by exhaustion. A spent budget is reported with section 14's
diagnosis, not extended silently.

---

## 7. Verdict labeling

Never write an unqualified "fit to implement". Write:

    VERDICT: fit as far as ANGLE goes. Unswept: ANGLE, ANGLE.

The unqualified form is what made the pattern in section 1A invisible
for seven rounds. Scoping the label costs nothing and surfaces the
remaining risk in the one place a reader will look.

---

## 8. Move the unsettleable out of prose

Some classes cannot be closed by inspection at any number of rounds:

- **Interaction completeness.** The feature crossed with every other
  component, layer and entry point is a combinatorial space that reading
  samples and never covers.
- **Behavior under real timing.** Ordering, settle transitions, and
  re-entrancy.

Once the plan is stable, convert the test list into skipped test stubs
in the repository. Then "does the plan cover interaction X" is answered
by the stubs, and they begin failing usefully the moment implementation
starts. If a plan is blocked on a dependency and its remaining risk is
in these classes, say so and stop auditing; more rounds are the
expensive way to find what one test finds immediately.

---

## 9. Round checklist

- [ ] Angle chosen from the section 2 list; note which remain unswept
- [ ] Prior audit-file conclusions treated as leads and re-checked
- [ ] Each finding confirmed against source and given its kind
      (section 12) before being recorded
- [ ] Each fix made by re-ranking the decision's table (section 11)
- [ ] Each changed interface's consumers verified per section 15
- [ ] Each trialed solution kept (section 10)
- [ ] Snapshot saved and vocabulary delta recorded before editing
- [ ] Each fix a rewrite, not an addition; no history in the plan (rule 3.7)
- [ ] Consistency pass run after editing (section 5)
- [ ] The six summary sections of 3.2 re-read if a component changed
- [ ] Structure verified: contiguous numbering, cross-references
      resolve, style rules held (plain ASCII)
- [ ] Audit-file entry written with evidence and outcome for every
      finding
- [ ] Verdict scoped per section 7

---

## 10. Trials are kept, on a branch

Section 5 says to audit a solution against source. The strongest form
of that is a TRIAL: apply the chosen solution, run the section's repro
against unfixed and fixed code, run the gates. One review-fix audit
trialed 11 of 13 sections that way and found two whose text read
correctly and failed (a freshness claim and a guard that broke a
documented re-add path). Reading would not have caught either.

What that audit got wrong was what it did with the result: every trial
was reverted to keep the main branch clean, so 13 verified diffs were
thrown away and had to be reconstructed from the plan text. Do not do
that.

- A trial is committed only with the owner's authorization. In the
  workflow, confirming the run authorizes the trial commit on the branch
  the workflow creates. In a hand audit, ask; without an answer, save
  the trial's diff as a patch where the plan names, so nothing has to be
  reconstructed from prose.
- A committed trial lives on a branch cut from the audited baseline
  commit, one commit per section, with the repro promoted into the test
  tree in the same commit. A trial passes when its repro fails before
  and passes after, and every profile gate that applies passes. The
  plan's section records "TRIALED" with the commit sha.
- A trial that fails is also kept, as a commit that a follow-up commit
  corrects, or as a rejected option in its decision table with the
  failure as evidence (section 11). Either way the plan changes in the
  same edit (rule 3.1).
- Nothing is reverted to restore the baseline without its diff saved. If
  a later section's trial needs unfixed code for its "fails before" gate,
  run that gate against the previous commit (a worktree at the earlier
  sha), not by undoing landed work.
- The branch or the patch is the deliverable of the audit alongside the
  plan, and the verdict names it. Merging is a separate decision for the
  owner, and a fix found after a trial lands as its own commit.

One consequence for section 6's stopping rule: a trial is a pass of the
internal-mechanism angle, so a plan whose sections have all been
trialed has that angle swept by construction, and the remaining rounds
should open other angles rather than re-read the mechanism.

---

## 11. Decisions are ranking tables

Every architecture, performance or algorithm choice in a plan is a
subsection of its Decisions section, anchored `d<N>`: the decision, a
table of options, and a problem statement when the decision answers a
defect in today's behaviour. The table's columns are Rank, Option, Gate,
Evidence and Assessment.

- GATE, pass or fail with the reason: correct; meets the goals and
  requirements; preserves every documented invariant; idiomatic for the
  language, the framework and the codebase; keeps the public API
  compatible unless a goal says otherwise; removes no existing safeguard
  without a replacement. A failing option stays in the table, ranked
  below every passing one.
- EVIDENCE, each claim labelled, strongest first: measured (a timed or
  counted run, section 17), demonstrated (a recorded test, run or audit),
  traced (a code path or normative document read), computed (arithmetic
  from stated inputs), design-only (none of these). A rank-1 option that
  rests on design-only evidence names the check that will produce
  evidence.
- RANK: passing options in the order of the profile's ranking criteria, a
  tie on one criterion going to the next. A hot-path performance
  criterion applies only on the profile's hot paths. A difference within
  measurement spread, or within one complexity class when computed, is a
  tie. A plan whose decisions are not code decisions declares its own
  criteria in its Decisions preamble.
- The top-ranked passing option is the decision. A fix to a decision is
  a re-ranking of its table, so the rejected options stay available
  (section 14).

The architect lists and ranks the options. The owner may supply decisions
with their evidence before the plan is written, and the architect adopts
each as the starting table and may add options. The design critic
(section 13) reports a missing valid option, or an evidence cell that
does not support its rank, as a `rank` finding.

---

## 12. Finding kinds, what fails a round, and where each finding goes

Each finding has one KIND:

- `rank`: it changes which option ranks first in a decision table, or
  shows false a statement a ranking rests on (a citation or count
  included).
- `surface`: it changes the public surface, or breaks a format another
  component reads (a required section, an anchor, the status line).
- `consistency`: the plan disagrees with itself, breaks a writing rule of
  section 3 (a restated fact, history or defensive prose in the plan), or a
  revision did not do what the loop required of it (section 14). A writing
  rule broken without a contradiction is usually minor.
- `scope`: a requirement is missing, ambiguous, or in conflict with
  another.
- `implementation`: anything else: an edge case, a consumer, a rule no
  test pins, an inert assertion, a mutation survivor.
- `coverage`: the critic could not review (an unreadable plan, a missing
  input). Its lens counts as not reported.

A finding is FAILING when its severity is blocking or major and its kind
is `rank`, `surface`, `consistency` or `scope`. A round is clean when no
finding fails. Severity alone never fails a round: an implementation
finding cannot, whatever severity it was given, and minor documentation
or citation points do not.

Every finding has exactly one receiver, so none is dropped:

- A failing `scope` finding ends the run and goes to the owner, who
  settles the requirement and resumes.
- Every finding raised since the last architect step goes to the next
  one, a revision or the approval step, which records each in the audit
  file with its outcome: fixed, re-ranked, rejected with evidence,
  carried, or left open with a reason (a non-failing finding only).
- Every `implementation` finding goes to the checklist, as an item whose
  acceptance is a test shown to fail first, a mutation, or the code check
  section 15 names for a consumer; one that no longer applies to the
  approved plan is listed with the reason.
- A run that ends holding findings no architect step received returns
  them, and the launcher records them in the audit file.

The audit file is `plans/<date>-<slug>-audit.md`, beside the plan. It holds
every round record, the trial log and the run record (the commit the run
started from); the plan holds only what implementation needs, plus its
Approval block (rule 3.7). A round record is one line per finding: its id,
lens, kind, severity, outcome and the section it touched, with a reason only
where the outcome needs one. The audit file and the revision snapshots carry
no ledger: they are history.

---

## 13. Critics and lenses

Each round dispatches new critic agents, each through one lens, and no
critic carries memory from an earlier run: its value is a fresh look. The
standard lenses run in every first round; a fresh lens runs once,
after a clean standard round, and is spent; the consistency lens runs
after every revision.

| Lens | Stage | Sweeps |
|---|---|---|
| `correctness` | standard | Angles 1, 8 and 9 |
| `performance` | standard | Angle 10, and whether each measured or computed evidence cell supports its rank |
| `design` | standard | Angles 2, 3, 4, 6 and 7 at decision level; each acceptance criterion traced to a check, and whether each named check can fail in the direction it claims; scope; the option set; new test seams; the guidance rule of section 16 |
| `interaction` | fresh | Section 8's first class |
| `timing` | fresh | Section 8's second class |
| `consistency` | after a revision | The revision against its snapshot, the findings it received and the obligations it was given (section 14) |

The design critic also receives the requirements; a design critic
without them reports `coverage`. The profile adds each lens's project
addendum and reading list.

Every dispatched lens must report. A lens that returns nothing, or
reports `coverage`, is dispatched once more in the same round; a lens
that still cannot review ends the run, because a round cannot be called
clean on an angle nobody swept.

After a failing standard round, the next round runs the lenses that
raised a failing finding, plus the consistency lens; after a failing
fresh angle, the consistency lens alone. A lens that cleared a section
the revision did not touch has nothing new to say; the consistency lens
guards those sections.

---

## 14. Loop control

Every critic finding carries the decision it concerns (a `d<N>` anchor,
or none), its kind (section 12), and a defect class (one of the
profile's defect classes, or other).

Before editing, a revision copies the plan to the first free
`<plan>.r<N>` and reports that path with the decisions it changed. The
next consistency lens diffs the snapshot and receives every finding the
revision received, the decisions it changed and the obligations below.
An unmet obligation, or a changed decision that no received finding named
and that does not depend on one that did, is a failing `consistency`
finding.

After every round, standard or fresh:

- R1, re-rank. A decision with a failing `rank` finding is re-ranked, not
  patched, when it had a failing `rank` finding in an earlier round or the
  previous revision changed it. The revision adds the findings to the
  table as evidence and re-applies the gate and the criteria; the
  snapshot holds the option it replaces. Keeping rank 1 satisfies the
  obligation when the record says why. This is the self-healing rule: a
  fix that keeps producing findings is a sign the option is wrong, and
  the table already holds the alternatives.
- R2, scope. A failing `scope` finding ends the run (section 12).
- R3, mechanize. A profile defect class found in two rounds, at any
  severity, obliges the next revision, or the checklist when no revision
  follows, to add a check for it, preferring a code check (section 15).

A revision that returns nothing leaves no snapshot and no changed
decisions: the next consistency lens reads the revision's record instead,
and R1's second clause cannot fire.

The run has a round budget (the workflow's default is 4). A spent budget
reports each failing decision, the rounds it failed in, and whether R1
re-ranked it. For scale, the 18 plans of one review series took a median
of 3.5 rounds, and 8 of them more than 4, without these rules.

An approved plan can be reopened: a revision of a ready-to-implement plan
first sets it back to draft, and a regenerated checklist keeps the old
one as `<checklist>.superseded-<n>.md`. A plan whose ledger is retired has
landed, and a later change is a successor plan.

---

## 15. Consumers are verified in code

A change's consumers are verified in this order, and a plan names, for
each interface it changes, the strongest that applies:

1. DERIVE: the consumers read one source in code, so they cannot
   disagree (schemas built from one item definition, a status set from one
   constant, a list read from the profile).
2. CHECK IN CODE: the compiler or the analyzer for code symbols, or a test
   that fails when a consumer disagrees with its source, which is how
   structured prose (tables, frontmatter, examples, headings) is checked.
3. READ: the code that uses the interface, in full; for a change to the
   method itself, every file in the profile's method file list.
4. SEARCH: a text search only locates what to read. Its result is never
   the verification.

The evidence: every round of this method's own revision audit found
consumers its enumeration missed, first in hand-listed line ranges and
then in per-term search commands, which find only the wording they name.
The consumers the searches missed restated a changed rule in other words,
and reading the files found every one.

---

## 16. Closing: mutations, gates and acceptance

The checklist's last phase opens with one mutation item per decision
whose code site lies under the profile's code paths: break the rule
there, observe a named test fail, restore the file, and record the test
name and the file's SHA-256 before and after, which must match. A
decision that lands only in documents is checked by the code check or
read section 15 names for it. Then come the profile's gates that apply,
so the suite runs after the last restore, then the ledger retirement.
"Each new assertion is shown to fail" is not enough: in one review series
six of seven blocking findings in a round were rules of the plan that no
test pinned, each found by a mutation.

A reviewer who never reads the plan closes the run. It receives the
request verbatim, the acceptance criteria verbatim, the commit the run
started from, and the files the implementer reports it changed; it reads
each in full, diffs the tracked ones, runs the tests the criteria name,
and writes the acceptance document: each criterion quoted and marked met,
partial or unmet with its evidence, then its findings. Gaps go to the
owner, to fix by hand or through a successor plan.

A plan changes a guidance document only to state an invariant the change
adds or alters.

---

## 17. Timed measurement

Deterministic counters need no noise floor. A timed comparison, used
only when a ranking depends on one, follows this protocol:

- Expectations are declared before measuring, and carry no consequence.
- A noise floor comes from A/A runs.
- The verdict comes from a committed comparison script reading what the
  artifacts record (order, tree, settings, inputs).
- A rerun happens only when a verdict earns one.
- A rule change applies to a fresh series only, never to data already
  measured.
- Measured code is committed at exactly the hashes the verdict recorded,
  and a follow-up fix lands as its own commit.

The comparison script is built when the first ranking needs it.

---

## 18. The profile

The profile is a JSON document in the project, passed to the workflow by
its launcher, because a workflow script cannot read files. It holds the
project's code paths, convention documents, method file list, gates
(name, command, pass condition, when it applies), modules (path patterns,
module document, vocabulary), the lens addenda and reading lists, the
defect classes, the ranking criteria, the hot paths, and the citation
settings. Every key has a reader, and a project adopts the method by
writing its own.
