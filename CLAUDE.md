# CLAUDE.md

Claude Code reads this file; other agent tools read `AGENTS.md`. The shared
instructions live in `AGENTS.md` and are imported below, so there is one copy
and it cannot drift. Edit `AGENTS.md` for anything that should apply to every
agent, and add Claude-specific notes under the heading below.

@AGENTS.md

## Claude Code specific

- Directory-scoped `CLAUDE.md` files are loaded only when a file in that
  directory is read, not at session start. Never put a rule that must always
  apply into one; they suit reference material that is only needed while
  working in that directory.
- `.claude/rules/*.md` loads at launch and supports path scoping, which makes
  it the right home for a rule that applies to some paths but must not be
  missed.
