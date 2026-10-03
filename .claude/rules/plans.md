---
paths:
  - "plans/*.md"
  - "plans/**/*.md"
---

# Working in `plans/`

Loads when a file under `plans/` is read. The always-on pointer lives in
`AGENTS.md` ("Plans and audits"). `plans/AUDIT-METHOD.md` is the normative
method, and this file is only an index into it: it restates no rule, so read
the section named.

| When | Read in `plans/AUDIT-METHOD.md` |
|---|---|
| Before the first round | Section 2, the angle list: write it first and mark each angle unswept |
| Writing a plan | Section 3 (one normative site, summary sections, citations, counts, public artifacts, landing order) and section 11 (decisions are ranking tables) |
| Recording a finding | Section 5 (confirm it, audit the solution) and section 12 (its kind, whether it fails the round, where it goes) |
| Verifying a change's consumers | Section 15: derive, check in code, read; a search only locates what to read |
| After an edit round | Section 5's consistency pass |
| A fix that keeps failing | Section 14, the loop rules |
| Deciding to stop | Section 6, and section 7 for the verdict's form |
| Trials | Section 10 |
| Closing a plan | Section 16 |
| A timed comparison | Section 17 |

Citations: the rule is `AGENTS.md`'s ("Plans and audits"). Run
`python plans/check_citations.py plans/<plan>.md` when you are about to rely on
a plan. The project facts the method reads are in
`doc/agents/method-profile.json`.
