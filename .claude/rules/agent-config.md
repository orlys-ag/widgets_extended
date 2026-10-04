---
paths:
  - "AGENTS.md"
  - "CLAUDE.md"
  - ".claude/**"
  - "doc/agents/**"
---

# Editing the agent configuration

How Claude Code loads these files, beyond the rule loading `AGENTS.md`'s
guidance map states:

- `CLAUDE.md` and its `@` imports load at launch, and a subagent starts with the
  copy its session loaded (observed), so a guidance edit reaches agents from the
  next session on. The built-in Explore and Plan agents start without it.
- A directory's `CLAUDE.md` loads only when a file in that directory is read, so
  a rule that must always apply never goes in one.
- A `.claude/rules/*.md` file without `paths:` loads at launch
  (code.claude.com/docs/en/memory). A rule that must apply before any file is
  touched belongs in `AGENTS.md`.
- An `@` import loads at launch even inside a path-scoped rule (observed), so a
  path-scoped rule keeps its text in its body; the workflow harness checks this.

The owner's requirements for these files:

1. The method and the workflow (the core, the contracts, the agents, the skills
   and the workflow script) are project-neutral. Project facts live only in
   `doc/agents/method-profile.json`; the paths of the method's own files, its
   `methodFiles`, are not project facts.
2. Every instruction is written for an AI reader: each fact once, no sentence
   the reader does not need, and no provenance (the design record keeps the
   evidence). An example appears only as the template of a file the reader
   parses, plus `feature-start`'s one contrast for acceptance criteria.
3. An agent file holds the role and the standing rules no loaded document
   states; a workflow prompt holds the run's data and steps; the profile holds
   the project's facts.

A count that changes with the code is written as the command that produces it,
never as a number: nothing re-checks guidance the way a plan's citations are
checked. The workflow harness catches a number in the same sentence as a
`wc -l` or `grep -c`, before or after it; only reading catches any other count.

`.claude/` is versioned except its agent worktrees and `settings.local.json`.
