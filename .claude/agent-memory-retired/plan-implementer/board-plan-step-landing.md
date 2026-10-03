# Landing a step of the board-view plan

Repo-local mechanics that cost time to rediscover. Plan:
`plans/2026-08-29-board-view-plan.md`.

## The stub accounting is checkable, and checking it is cheap

Every case named in the Testing Plan already exists as a SKIPPED stub under
`test/board/`. Landing a step REPLACES a stub body and drops the skip; it
never creates a file and never invents a name. Re-measure with:

    STUBS=$(grep -rl "STUBS for the board Testing Plan" test/board --include=*.dart)
    echo "$STUBS" | wc -l                                   # stub files left
    grep -hE '^ +(testWidgets|test)\($' $STUBS | wc -l       # stub cases left
    grep -cE '^  (testWidgets|test)\(' test/board/<landed>.dart

A landed file loses the "STUBS for the board" header line, so it leaves the
grep set entirely rather than showing zero skips. The invariant: stub cases
remaining plus live cases in landed files equals 111 (the tracked baseline)
plus whatever Round 15 and Round 16 added into already-landed files.

After step 3: 19 stub files, 94 stub cases, 20 live in five landed files.

## Keep the case name ONE string literal on ONE line

The plan's coverage-by-grep property feeds stub names back through the plan
with `grep -qF`. Splitting a long name across two adjacent literals to fit
80 columns breaks that silently. Use the stub's own shape instead, name on
its own line:

    testWidgets(
      "the whole name here",
      (tester) async { ... },
    );

`dart format` leaves that alone. `test/board/span_index_test.dart:190` has
the split form, so precedent exists both ways; the unsplit one is correct.

## Reddening assertions: one mutation per assertion, in order

`expect` throws, so only the FIRST failing assertion reports. To show
assertion N is not inert, pick a mutation that leaves 1..N-1 passing.
Restore from a scratchpad copy between mutations and diff to prove it.

Two traps hit while doing this:

- A heredoc into the Bash tool failed on a Dart file containing apostrophes
  even with a quoted delimiter. Use the Write tool for file creation and
  `python - <<PY` for targeted string replacement.
- `subprocess.run(..., capture_output=True, text=True)` on Windows decodes
  `flutter test` output as cp1252 and dies on its box-drawing bytes. Run the
  mutations from a shell loop, not from Python.
- Do NOT use `git stash -u -- <paths>` to measure an analyzer baseline for
  untracked files. It succeeds, and if the next command in the chain fails
  the files are gone from the tree. `mv` them to the scratchpad instead.

## Two more reddening traps (found adding cases to board_animation_style_test)

- `lib/board/*.dart` is CRLF. A Python patcher whose patterns use a bare
  `\n` matches nothing and reports a pattern count of 0. Normalize the
  PATTERN, not the file: replace `\n` with `\r\n` in both halves of the
  pair when the source read back contains `\r\n`.
- Isolate the case under mutation with
  `flutter test <file> --plain-name "<substring>"`, and identify WHICH
  assertion reported by grepping the failure block for `line [0-9]+$`. The
  Expected/Actual pair alone does not separate two assertions that pin the
  same value: an `effective` getter and `specFor` return the same spec, so
  their two mutations print identical text and only the line number tells
  them apart.
- Harness shape that worked: one `mutate.py` in the scratchpad holding a dict
  of (old, new) pairs keyed by mutation id, always applied against a pristine
  copy, plus a `restore` key, plus a `diff` against that copy after every
  batch. Dry-run every id once first; a pattern that is not unique aborts
  rather than silently mutating two sites.

## dart format reshapes SHORT case names

`testWidgets(` plus a name that fits on the line collapses to the
trailing-closure form, so cases in one file will not all share a shape. The
name stays ONE literal on ONE line, so the coverage-by-grep property survives.
Do not fight the formatter to restore the block form.

## A const-context property is pinned by COMPILATION, not by an expect

`BoardAnimationStyle.uniform` is a const constructor where the tree's is a
`factory`. Declaring the style `const` in the test pins that, and the
falsifier was run once to confirm the comment claiming it: rewriting the
constructor as a factory returns
`test/board/board_animation_style_test.dart:389:39: Error: Cannot invoke a
non-'const' factory where a const expression is expected.` before any test
runs. Do NOT dress this as `expect(identical(constA, constB), isTrue)`: no
lib mutation makes that go red while the file still compiles, so it is an
inert assertion by the testing-patterns rule.

## Under `uniform` both roots hold ONE spec, so values cannot separate them

Fourteen mutations, fourteen assertions, all reddened individually. The
useful shape: a wrong-root mutation (`_makeRoom ?? trackResize`) leaves
every `specFor` assertion GREEN on the uniform style, because both roots
carry the same spec, and reddens only the post-`copyWith` probe. That is
also why the case needs the restyle half at all.
