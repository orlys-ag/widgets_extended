---
paths:
  - "lib/sliver_tree/*.dart"
  - "lib/sliver_tree/**/*.dart"
  - "lib/sectioned_sliver_list/*.dart"
  - "lib/sectioned_sliver_list/**/*.dart"
  - "test/sliver_tree/*.dart"
  - "test/sliver_tree/**/*.dart"
  - "test/sectioned_sliver_list/*.dart"
  - "test/sectioned_sliver_list/**/*.dart"
---

# sliver_tree architecture

Loads when a file in either module is read, so the nid contract, the three
coordinate spaces, the animation-family rule and the carve-out accessor
inventory are in context before an edit rather than after a review.

@../../doc/agents/sliver-tree-architecture.md

The import is `../../` and not repository-root relative: an `@import` resolves
against the directory of the file containing it, so from `.claude/rules/` the
root is two levels up. If it did not expand, read
`doc/agents/sliver-tree-architecture.md` directly. That file is normative;
nothing here restates it.

## Why this is a rule and not part of AGENTS.md

It was part of `AGENTS.md` until 2026-08-29, where it was 19,690 of 29,026
bytes: 68% of a file loaded into every session, including every session that
never opens this code. Splitting it cut the always-on file to 7,369 bytes and
costs nothing when the code IS being edited, because the rule loads then.

`AGENTS.md` keeps a guidance-map row pointing here. That row is load-bearing,
not decoration: a path-scoped rule fires when a matching file is READ, so a
session that only writes a new file, or reasons about the architecture without
opening it, never triggers this rule and needs the map instead.

`sectioned_sliver_list` is covered by the same rule deliberately. It adapts the
sliver_tree stack rather than standing beside it, so editing it needs the
sliver_tree contract too.
