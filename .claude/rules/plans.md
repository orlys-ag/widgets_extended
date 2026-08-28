---
paths:
  - "plans/*.md"
  - "plans/**/*.md"
---

# Working in `plans/`

Loads when a file under `plans/` is read. The always-on pointer lives in
`AGENTS.md` ("Plans and audits"); this file carries the operational detail so it
costs no launch context.

**`plans/AUDIT-METHOD.md` is the normative method. Read it before writing or
auditing a plan.** What follows is an index to it, not a replacement: every rule
below is stated fully there, and where the two disagree, that file wins.

## Before the first audit round

Write the angle list first and mark each unswept. Discovering angles one round
at a time is what makes the stopping rule lie. The default set, plus any angle
specific to the subject:

internal mechanism, public surface, consumers and call sites, contracts with
dependent documents, the test list as a deliverable, citations and claims,
house-convention compliance, degradation and failure paths, lifecycle and
disposal, performance bounds.

## Stopping rule

Do **not** stop on two consecutive clean passes within a round: that measures
the lens, not the artifact. Stop when either

- every angle on the list has been swept AND a freshly opened angle came back
  empty on its first pass, or
- the last round produced only wording-level findings with no consequence to
  implementation, testing, or the public surface.

Declare a round budget in advance. Track findings per round; a decaying count
is the signal.

## Writing a plan so it stays auditable

- **One normative site per fact.** Every other mention is a cross-reference
  ("per 4.1"), never a paraphrase. A reference cannot go stale.
- **Summary sections are where staleness collects**: the one-paragraph
  architecture, the lifecycle walkthrough, the contracts list, the decided-
  decisions list, the costs summary, the test list. Re-read exactly those after
  any component section changes.
- **Counts and universal claims carry their command.** "Every", "all", "only",
  "none", "always", and every number are queries, not statements. Run the
  command, quote what it returned, and prefer an enumeration to a total.
- **Declare every public artifact the plan depends on**: name, signature, where
  it lives, whether it is exported. This package exports through explicit
  `show` clauses, so an undeclared symbol can be unnameable by app code.
- **State the landing order** when the work spans layers, and call out any
  grouping forced by correctness rather than convenience.

## Citations

Bare `path:line`, verified by a generated ledger, never by eye:

```bash
python plans/check_citations.py plans/<plan>.md --update   # record
python plans/check_citations.py plans/<plan>.md            # verify
```

The ledger is derived: regenerate it, never hand-edit it. Repo files are cited
by bare filename, SDK files as `<subdir>/<file>.dart:NNN`. Spell each path one
way. A bare `` `:123` `` attaches to the last file named in full form, which is
how a compression pass silently reattributes a whole table to the wrong file.

## Auditing a round

For each finding: confirm it against source before treating it as real (tool and
subagent output is a lead); confirm it actually affects the plan; audit the
chosen solution against its alternatives, not just the problem; record it in the
audit log with its evidence and rejected alternatives.

**The consistency pass after any edit round is mandatory.** Write down the old
vocabulary before editing, then grep for it afterwards. Every hit is either an
explicit negation or a defect. This catches what re-reading does not, because
the second most common defect class is the audit's own earlier fixes going
wrong.

## Trials

The strongest form of auditing a solution is to apply it: repro fails before,
passes after; no new analyzer issues in `lib/`; full suite green. Reading does
not catch a plan whose text is correct and whose code is not.

Do not throw a passing trial away. Keep the diff, with its repro promoted into
the test tree, and record the section as TRIALED. If reverting to leave a clean
tree, save the patch somewhere the plan names, so nothing has to be
reconstructed from prose.

## Verdicts

Never write an unqualified "fit to implement". Scope it:

```
VERDICT: fit as far as ANGLE goes. Unswept: ANGLE, ANGLE.
```
