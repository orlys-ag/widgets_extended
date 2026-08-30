---
paths:
  - "test/*.dart"
  - "test/**/*.dart"
---

# Testing patterns

Loads when a test file is read, so the house conventions are in context while
a test is being written rather than after it is reviewed.

@../../doc/agents/testing-patterns.md

The import is `../../` because an `@import` resolves against the directory of
the file containing it, not the repository root. If it did not expand, read
`doc/agents/testing-patterns.md` directly. That file is normative; nothing
here restates it.

## The one rule most often missed

Not a restatement, an emphasis: the repro-test methodology in `AGENTS.md`
requires every NEW ASSERTION to be shown to fail, not merely the test as a
whole. One assertion can carry the whole failure while its neighbours are
inert, and a setup sanity assertion that cannot fail is worse than none
because it reads as proof the path was exercised.

That rule stays in `AGENTS.md` rather than moving here, because it applies
when deciding HOW to fix a bug, which happens before any test file is opened
and therefore before this rule would load.
