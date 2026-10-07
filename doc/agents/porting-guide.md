# Porting the agent system

Instructions for an agent that installs this repository's agent system in
another repository: the house rules (`AGENTS.md`), the plan audit method and
the `feature-implementation` workflow. SRC is the root of the repository this
file is in; DST is the target's root. Follow the steps in order; step 7 decides
whether the port is done.

## The parts

| Part | Files | Holds |
|---|---|---|
| Guidance | `CLAUDE.md`, `AGENTS.md`, `.claude/rules/*.md` | The house rules, and path-scoped rules that load when a matching file is read or edited |
| Method | `plans/AUDIT-METHOD.md`, `plans/check_citations.py` | How plans are written and audited, and the git-based check of their citations |
| Workflow | `.claude/workflows/feature-implementation.js`, `.claude/agents/*.md`, `.claude/skills/feature-start/` and `feature-status/`, `doc/agents/feature-workflow-contracts.md` | The run, its five agents, its entry and status skills, and its file formats |
| Profile | `doc/agents/method-profile.json` | Every project fact the method and the workflow use |
| Checks | `.claude/workflows/feature-implementation.harness.mjs`, `.claude/hooks/*.py`, `.claude/settings.json` | The harness runs the script with stub agents and checks the documents against the script and the profile; one hook denies a commit or pull request that carries an attribution, the other flags non-ASCII text an agent just wrote |

DST needs git, Node, Claude Code with the `Workflow` tool (it runs a workflow by
name from `.claude/workflows/`), and a `python` command that runs Python 3: the
method files and the hooks call it by that name.

## 1. Survey DST

Before writing anything, record:

- the languages, and the build, test and lint or analyze commands, each run once
  for its current result (a nonzero issue count is a baseline, not a failure);
- the source and test directories;
- the modules: directories with their own architecture, each of which gets
  rules (step 3);
- where the framework or SDK source lives, if plans will cite it;
- any existing `CLAUDE.md`, `AGENTS.md`, `.claude/` and `.gitignore`. Preserve
  their content: move project facts from an old `CLAUDE.md` into `AGENTS.md` or
  a rule, and merge settings and ignore entries instead of overwriting them.

## 2. Copy the project-neutral files

Copy these from SRC's working tree unchanged. Do not edit them to fit DST: DST's
facts go in the profile (step 4).

- `CLAUDE.md`
- `plans/AUDIT-METHOD.md`, `plans/check_citations.py`
- `doc/agents/feature-workflow-contracts.md`
- `.claude/agents/`: `plan-architect.md`, `plan-critic.md`, `plan-checklist.md`,
  `plan-implementer.md`, `acceptance-reviewer.md`
- `.claude/skills/feature-start/SKILL.md`, `.claude/skills/feature-status/SKILL.md`
- `.claude/workflows/feature-implementation.js`
- `.claude/rules/plans.md`, `.claude/rules/agent-config.md`
- `.claude/hooks/forbid_attribution.py`

Also copy `.claude/workflows/feature-implementation.harness.mjs` and
`.claude/hooks/forbid_symbols.py`, which steps 5 and 6 adapt.

Copy none of SRC's other `plans/` files, module rules or
`settings.local.json`, and create no `.claude/agent-memory/` (harness T3i).

The agents' `model` and `effort` frontmatter must equal the contracts' section
11 table (harness T3e). If DST's account lacks those models, change both in one
edit.

## 3. Write the rules

Every path-scoped rule keeps its text in its body, with no `@` import
(harness T3j). List
each directory in both glob forms, `dir/*.ext` and `dir/**/*.ext`, as SRC's
rules do. Every claim about DST's code is checked against the code
(`AGENTS.md`, "Verified claims"), and a count that changes with the code is
written as the command that produces it (`agent-config.md`).

- `.claude/rules/testing.md`, with `paths:` over DST's tests: DST's test
  conventions, then SRC's "Repro-test methodology" section unchanged, since
  `AGENTS.md` points to it.
- `.claude/rules/comments.md`, with `paths:` over DST's source and tests: SRC's
  rules, with DST's doc-comment syntax, its definition of the public API and
  its form for referring to a symbol.
- Per module, an architecture rule `<module>.md`, with `paths:` over the
  module's source and tests. It holds the conventions every layer follows, and a
  `| Rule | Covers |` table of the module's layer rules.
- A module large enough to have layers gets one rule per layer,
  `<module>-<layer>.md`, whose `paths:` list the exact files it governs. Such a
  rule must not name a source file its paths omit (harness T3j; test files are
  exempt). A small module may have the architecture rule alone.

## 4. Write `doc/agents/method-profile.json`

Start from SRC's profile. The script's `validateProfile` rejects a profile
that lacks any of these keys or leaves a required list empty.

| Key | Write |
|---|---|
| `codePaths` | DST's source and test directories; non-empty. The launch, the trial and the implementer require them clean, and a rule's Phase 4 item is a mutation when its code site lies under them |
| `conventionDocs` | `.claude/rules/testing.md`, `.claude/rules/comments.md`, and any other house convention document DST has |
| `methodFiles` | SRC's list, unchanged |
| `gates` | Each of DST's checks as `name`, `command`, `pass` and `when`, with unique names, plus SRC's `workflow-harness` and `citations-self-test` entries unchanged. A check not at zero today passes on "no issue beyond the count before the change". `when` is `always` or a condition |
| `modules` | At least one, keyed by name: `paths` (regular expressions over repository paths, such as `^src/payments/`), `guidance` (exactly the step 3 rules whose `paths:` fall under it; harness T3j), `vocabulary` (one paragraph naming the module's central types and concepts, for the critics) and, optionally, `lensAddenda` (by lens key, the hazards of this module alone) |
| `lenses` | Exactly `correctness`, `performance`, `design`, `interaction`, `timing` and `consistency`. Copy SRC's `reads`. Each `addendum` says what the lens's hazards are across DST, or is `""`: re-entrancy, teardown, degraded modes and the lifecycle paths DST's framework drives without the change's code running, for correctness; hot-path anti-patterns and how DST pins performance; the components a change can cross, for interaction; ordering that is assumed but not tested, for timing. A hazard of one module goes in that module's `lensAddenda` |
| `defectClasses` | SRC's four, unchanged; never `other` |
| `ranking` | DST's decision criteria, most important first. Keep `hot-path-performance`: the script's ranking line names it |
| `hotPaths` | Where hot-path performance applies in DST, such as `per request`; non-empty |
| `citations` | `sdkRoot`: the absolute path of the framework source plans may cite, or `""`. `extensions`: DST's source extensions, plus `md`, `js`, `mjs` and `py` |
| `planRules` | DST's own requirements every plan meets, or `[]` |

Harness T3b fails when a neutral file names a profile term. These terms are
matched as whole words, ignoring case: module keys, each gate command's first
word after any leading `cd <dir> &&`, and every identifier in the
vocabularies, addenda and plan rules with a lower-case letter followed by a
capital (`BoardStore`, `idOfKey`). These are
matched as substrings: code paths with a trailing `/`, convention documents,
guidance paths, hot paths and `.<extension>`. A gate whose command names a
`methodFiles` path is exempt, and so is an extension a `methodFiles` path ends
with.

Ordinary words collide. The neutral files contain the words `core`, `api`,
`app`, `model`, `make`, `go` and `python`, so a module key or a gate command's
first word that is one of them fails T3b. Fix the profile, never the neutral
files: rename the module key, or call the tool directly (`pytest`, not
`python -m pytest`) or through a wrapper script. An extension that occurs inside
neutral text (`c` occurs in `.claude`) needs the harness change in step 6.

## 5. Write `AGENTS.md`, the settings, the hooks and the ignores

Build `AGENTS.md` from SRC's, section by section:

| Section | Action |
|---|---|
| Title and opening paragraph | Unchanged |
| Project Overview | DST's purpose and modules |
| Commands | DST's commands. Name each check not at zero today, and say to compare its count before and after a change |
| Code Quality | Unchanged |
| Verified claims | Unchanged, except: replace `flutter analyze` (both occurrences) with DST's analyzer or compiler, and "the Flutter or Dart source" and its examples with DST's framework |
| Response style | Unchanged |
| Code Style | Replace the first three bullets (Dart quoting, braces, block bodies) with DST's style rules. Keep the plain-ASCII and no-attribution bullets unchanged |
| Guidance map | The opening paragraph unchanged; one row per module, and the Testing and Comments rows with DST's paths; the Audit method, Feature workflow contracts and Agent configuration rows and the closing gates sentence unchanged |
| The feature workflow, Plans and audits | Unchanged |

In `.claude/hooks/forbid_symbols.py`:

- set the extension tuple in `main()` to DST's text files;
- point the string-literal exemption, `skip_strings = path.endswith(".dart")`,
  at DST's source extension if its string literals use the quotes `DELIMITERS`
  lists, otherwise set it to `False`;
- delete the docstring's character counts, which describe SRC.

In `.claude/settings.json`, copy SRC's `hooks` block unchanged. In
`permissions.allow`, keep the checker and `git` entries, and replace the
`flutter` entries with DST's gate commands.

In `.gitignore`, add SRC's entries, with their comments:

- `/plans/*`, with `!/plans/AUDIT-METHOD.md` and `!/plans/check_citations.py`;
- `/.claude/worktrees/` and `/.claude/settings.local.json`.

In `.gitattributes`, add SRC's `.claude/**` entry, with its comment.

`doc/agents/` stays tracked. If DST ignores `doc/`, re-include `doc/agents/`
the way SRC does.

## 6. Adapt the harness

In `.claude/workflows/feature-implementation.harness.mjs`, T3j names Dart in
two patterns: this one finds the source files a layer rule names, and
`_test\.dart$` exempts tests. Replace both with DST's source extension and its
test-file naming.

```js
/`([A-Za-z0-9_]+\.dart)`/g
```

Only if a `citations.extensions` entry occurs as `.<ext>` inside neutral text
(step 4), make the extension terms bounded on their right, so that `.c` inside
`.claude` passes while `main.c` still fails. In `profileTerms`:

```js
...extensions.map(e => ({ term: `.${e}`, tail: true })),
```

and in T3b's loop:

```js
for (const { term, word, tail } of terms) {
  const named = word ? new RegExp(`(^|[^A-Za-z0-9_])${escapeRe(term)}([^A-Za-z0-9_]|$)`, 'i').test(text)
    : tail ? new RegExp(`${escapeRe(term)}([^A-Za-z0-9_]|$)`, 'i').test(text)
    : text.toLowerCase().includes(term.toLowerCase())
```

## 7. Verify

Each check must give the stated result.

1. `node .claude/workflows/feature-implementation.harness.mjs` prints `0 failed`.
   A T3b failure names the file and the term: fix the profile (step 4).
2. `python plans/check_citations.py --self-test` prints `self-test: 0 failed`.
3. The attribution hook prints a `"permissionDecision": "deny"` object for the
   first command, and nothing for the second:

   ```bash
   printf '%s' '{"tool_input":{"command":"git commit -m \"x\n\nCo-Authored-By: x <x@x>\""}}' | python .claude/hooks/forbid_attribution.py
   printf '%s' '{"tool_input":{"command":"git commit -m \"plain\""}}' | python .claude/hooks/forbid_attribution.py
   ```

4. The symbol hook prints a `"decision": "block"` object:

   ```bash
   printf '%s' '{"tool_input":{"file_path":"x.md","content":"a \u2014 b"}}' | python .claude/hooks/forbid_symbols.py
   ```

5. This prints nothing when every file you wrote is ASCII:

   ```bash
   python -c "import sys; [print(f) for f in sys.argv[1:] if max(open(f, 'rb').read(), default=0) > 127]" <files>
   ```

6. Every gate in the profile meets its `pass` condition against the baselines
   from step 1.
7. Guidance loads at session start, so the session that did the port runs on
   the old guidance (`agent-config.md`). Start a new session in DST before any
   workflow run. A run costs agents and commits, so launching `/feature-start`
   is the owner's decision; its confirmation step states the cost first.
