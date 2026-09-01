---
paths:
  - "lib/board/*.dart"
  - "lib/board/**/*.dart"
  - "test/board/*.dart"
  - "test/board/**/*.dart"
---

# board architecture

Loads when a file in the module is read, so the dense-id contract, the two
coordinate spaces, the animation-family kill-switch rule and the
obtain-to-retain retention rule are in context before an edit rather than
after a review.

@../../doc/agents/board-architecture.md

The import is `../../` and not repository-root relative: an `@import`
resolves against the directory of the file containing it, so from
`.claude/rules/` the root is two levels up. If it did not expand, read
`doc/agents/board-architecture.md` directly. That file is normative;
nothing here restates it.
