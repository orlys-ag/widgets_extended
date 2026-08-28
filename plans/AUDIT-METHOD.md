# Plan audit method

How to audit a design or implementation plan in this repository, and how
to write one that stays auditable. Derived from auditing
`2026-08-18-sliver-tree-presentation-ghosts-plan.md` (10 rounds) and
`2026-08-18-sliver-tree-row-transition-plan.md` (5 rounds) in one
session. The numbers quoted below are from those two audits and are the
reason each rule exists; treat them as evidence, not decoration.

Read this before starting an audit round, and again before writing a new
plan.

---

## 1. The two failure modes this exists to prevent

**A. The stopping rule lies.** Both plans repeatedly closed a round with
two consecutive clean passes, and the next round found defects on its
FIRST pass. The escape plan did this at rounds 8, 9 and 10; the
row-transition plan at rounds 2, 3, 4 and 5. The cause is not
carelessness. A round exhausts one LENS, and the second clean pass
mostly confirms the lens is exhausted, not the artifact. Findings
cluster hard by angle: all eight of the row-transition plan's round-3
findings were public surface, all three of round 5's were unverified
claims.

**B. The audit generates its own defects.** The single most common
defect class across both audits was not subtle design error. It was a
decision changing in one section while the summary sections kept
asserting the old one. That happened at least six times in the
row-transition plan alone, and in round 4 two of six findings were the
round's own earlier fixes going wrong. Any process that edits prose is
also producing defects, so it converges only if the fix rate beats the
introduction rate.

Everything below is aimed at one of those two.

---

## 2. Before the first round: enumerate the angles

Do not discover angles one round at a time. Write the list first, mark
each unswept, and work down it. A usable default set:

1. Internal mechanism (the components and their interactions)
2. Public surface (signatures, types, exports, naming)
3. Consumers and call sites (everything that must change, enumerated)
4. Contracts with dependent or dependency documents
5. The test list as a deliverable (is each test writable, will it fail
   on unfixed code, does it follow house conventions)
6. Citations and claims (section 4 below)
7. House-convention compliance (CLAUDE.md: style, testing patterns,
   naming, debug-counter conventions)
8. Degradation and failure paths (what happens when a precondition is
   not met)
9. Lifecycle and disposal (creation, teardown, and every site that
   destroys the thing)
10. Performance bounds (what is O(what), and is the bound the one that
    can blow up)

Add angles specific to the plan's subject. The list is the audit's
coverage map, and section 6's stopping rule is defined against it.

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
citations. It does not scale: the row-transition plan has 170 citation
instances, and tokenising them inline would have added more noise than
the whole audit-narration cleanup removed, fighting rule 3.2 directly.

USE A GENERATED LEDGER INSTEAD. Keep prose citations bare (`path:line`),
and record the expected content in a sidecar that a script regenerates:

    python plans/check_citations.py plans/<plan>.md --update   # record
    python plans/check_citations.py plans/<plan>.md            # verify

The ledger is a DERIVED artifact, so it does not violate rule 3.1: it is
regenerated, never hand-edited. `check_citations.py` reads only the live
sections, resolves repo and SDK paths, verifies each line still holds
its recorded content, and on a miss searches the file for that content
and reports the new line number. It exits non-zero, so it can gate CI.

Run it after any change under `lib/`.

SPELL EACH PATH ONE WAY. A file cited as both `proxy_box.dart` and
`rendering/proxy_box.dart` is one file to a reader and two to a
checker, which is how a verification script reports phantom misses or
silently skips a real one. Pick a form per source and hold it: repo
files by their bare filename, SDK files as `<subdir>/<file>.dart`. This
rule exists because the row-transition plan accumulated three files
spelled two ways each over six rounds, and nobody noticed until a count
of "cited files" came back 24 against a true 21.

### 3.4 Counts and universal claims must carry their command

Any claim containing "every", "all", "only", "none", "the sole" or
"always" is a QUERY, not a statement. It must carry the command that
establishes it, or be downgraded to a specific enumeration.

NUMBERS ARE THE SAME PROBLEM. "Seven counters", "four call sites",
"three sites gate on this": each is a count somebody eyeballed once, and
plausible numbers are precisely the ones no later reader rechecks. The
row-transition plan asserted "seven counters today" and "and four more"
where a grep returns six, in two places, both written from a glance at a
list. Run the command, quote the number it returns, and prefer an
enumeration to a total where the list is short.

This is not pedantry. Of four universal claims checked in the
row-transition plan's round 5, three were wrong or imprecise:
"the sole `_dirtyKeys` consumer" (three sites touch it), "already
per-frame coalesced" (two sources dispatch uncoalesced), and "every
public builder in this package is a typedef" (the counterexample was the
very widget the feature extends). All three read as checked facts. Each
took one grep to disprove.

### 3.5 Declare every public artifact the plan depends on

If the plan references a thing an implementer must create, the plan
declares it: name, signature, where it lives, and whether it is
exported. Three separate instances of this were missed in one plan: the
builder's signature was never declared at all, the reference widget was
referenced seven times and never named, and a typedef was specified
without noting that this package exports through explicit `show`
clauses, so it would have been unnameable by app code.

### 3.6 State the landing order when the work spans layers

If the change touches multiple widgets, files, or public names, say what
lands together and what can follow, and call out any grouping that is
forced by correctness rather than convenience.

---

## 4. The citation and claim pass

Run this as its own angle, at least once per plan, ideally scripted.

1. Run `check_citations.py` (rule 3.3). It handles extraction,
   resolution, verification and re-anchoring for the whole document.
2. Read what it flags. A BARE continuation citation (`` `:123` ``)
   attaches to the last file named in CITATION form, so naming a file in
   running prose and then citing bare lines silently attributes them to
   the wrong file. The checker catches this as an out-of-range line;
   a reader would not catch it at all.
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
   and prior audit-log entries are leads, not findings.
2. **Confirm it affects the plan.** A true observation that changes
   nothing is not a finding.
3. **Audit the solution**, not just the problem. State the alternatives
   considered and why the chosen one is better for long-term
   architecture and for performance. Prefer a solution that removes the
   need for vigilance over one that adds a rule to remember.
4. **Record it** in the audit log with its evidence and its rejected
   alternatives.

### The consistency pass is mandatory after any edit round

Before editing, write down the OLD vocabulary the change is replacing.
After editing, grep for those terms across the live sections. Every hit
is either a negation ("no longer X") or a defect.

This step catches what re-reading does not. In round 4 it found stale
text four separate times, faster than reading each time. Example
vocabulary deltas from real rounds: "pushed" to "live getter",
"animating set" to "mounted set", "just-settled" to nothing, "poke set"
to nothing, "default builder" to a widget name.

---

## 6. Stopping rule

Do NOT stop on two consecutive clean passes within a round. That
measures the lens.

Stop when either:

- **Coverage**: every angle on the section 2 list has been swept, and a
  freshly opened angle came back empty on its FIRST pass; or
- **Yield**: the last round produced only wording-level findings with no
  consequence to implementation, testing, or the public surface.

Track findings per round with severity. Observed decay in the
row-transition plan was 9, 8, 6, 3, with round 5's three being one test
design change, one justification replacement, and one phrasing fix. That
is roughly where a plan is done.

Declare a round budget in advance so the process terminates by design
rather than by exhaustion.

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

- **Interaction completeness.** The feature crossed with every animation
  source, paint pass, mutator, widget layer and entry point is a
  combinatorial space that reading samples and never covers.
- **Behavior under real timing.** Frame ordering, settle transitions,
  and re-entrancy.

Once the plan is stable, convert the test list into skipped test stubs
in the repository. Then "does the plan cover interaction X" becomes a
grep, and the stubs begin failing usefully the moment implementation
starts. If a plan is blocked on a dependency and its remaining risk is
in these classes, say so and stop auditing; more rounds are the
expensive way to find what one test finds immediately.

---

## 9. Round checklist

- [ ] Angle chosen from the section 2 list; note which remain unswept
- [ ] Prior audit-log conclusions treated as leads and re-checked
- [ ] Each finding confirmed against source before being recorded
- [ ] Each solution audited against alternatives, for architecture and
      performance
- [ ] Each trialed solution committed on the plan's branch with its
      repro, never reverted (section 10)
- [ ] Vocabulary delta recorded before editing
- [ ] Consistency pass run after editing (grep the old vocabulary)
- [ ] The six summary sections of 3.2 re-read if a component changed
- [ ] Structure verified: contiguous numbering, cross-references
      resolve, style rules held (no em-dashes, plain ASCII)
- [ ] Audit log entry written with evidence and rejected alternatives
- [ ] Verdict scoped per section 7

---

## 10. Trials are kept, on a branch

Section 5 says to audit a solution against source. The strongest form
of that is a TRIAL: apply the chosen solution, run the section's repro
against unfixed and fixed code, run the full suite. The 2026-08-21
review-fix audit trialed 11 of 13 sections that way and found two whose
text read correctly and failed (a sticky-offset freshness claim and a
sectioned-list guard that broke a documented re-add path). Reading
would not have caught either.

What that audit got wrong was what it did with the result: every trial
was reverted to keep `main` clean, so 13 verified diffs were thrown
away and had to be reconstructed from the plan text. Do not do that.

- Before the first trial, branch from the audited baseline commit
  (`git switch -c <plan-name>-fixes <sha>`). Trials happen there.
- A trial that passes its gates (repro fails before, passes after; no
  new analyzer issues in `lib/`; full suite green) is COMMITTED on the
  branch, one commit per section, with the repro promoted into the
  test tree in the same commit. The plan's section records "TRIALED"
  with the commit sha instead of a test count.
- A trial that fails is also kept, as a commit that is then corrected
  by a follow-up commit, or as a recorded rejection in the plan's
  "Considered solutions" with the failure's evidence. Either way the
  plan's section changes in the same commit (rule 3.1).
- Nothing is reverted to restore the baseline. If a later section's
  trial needs unfixed code for its "fails before" gate, run that gate
  against the previous commit (`git stash`, or a worktree at the
  earlier sha), not by undoing landed work.
- The branch is the deliverable of the audit alongside the plan. The
  verdict names it. Merging is a separate decision for the owner.

One consequence for section 6's stopping rule: a trial is a pass of the
internal-mechanism angle, so a plan whose sections have all been
trialed and committed has that angle swept by construction, and the
remaining rounds should open other angles rather than re-read the
mechanism.
