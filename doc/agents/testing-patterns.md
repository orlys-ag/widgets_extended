# Testing patterns

Normative reference for `test/`. Loaded automatically by
`.claude/rules/testing.md` when a test file is read; reachable for other
agent tools from the guidance map in `AGENTS.md`.

## Testing Patterns

- Controller tests use `testWidgets` with `tester` as the `TickerProvider` and `animationStyle: TreeAnimationStyle.disabled` for synchronous behavior.
- **Pin family-flow, not literal timings.** Animation tests assert that a call consumes the CONFIGURED family's spec (set a distinctive spec, observe it govern), not hardcoded durations/curves; literal pins are reserved for tests whose subject IS a default value. This is why the 0.0.32 uniform-defaults flip broke zero tests.
- Widget tests wrap `SliverTree` in `MaterialApp > Scaffold > CustomScrollView`.
- Uses `flutter_test`; no third-party test dependencies.
- Perf contracts are pinned via debug counters on the render object / controller (`debugLastPaintIterationCount`, `debugLastParentDataCumulativeBuilds`, `debugPerformLayoutCount`, `debugOrderResetIndexAllCount`, ...).
- **Justify a new seam against an existing one.** Before adding a `debug*` counter or a `@visibleForTesting` member, name the seam you rejected and why. `lib/` already carries 71 distinct `debug*` identifiers (`grep -rhoE '\bdebug[A-Z][A-Za-z0-9_]*' lib --include=*.dart | sort -u | wc -l`, a few of which are Flutter's own) and 19 `@visibleForTesting` annotations (`grep -rn '@visibleForTesting' lib --include=*.dart | wc -l`), and a seam on a public render object is permanent. Prefer the highest seam that can observe the behaviour; the counters above exist because paint-iteration counts are genuinely not observable from the widget surface, which is the bar a new one has to clear.
- The invariant-heavy suites (fuzz/purge/zombie) enable `TreeController.debugFullConsistencyChecks = true`; everywhere else debug builds run only an O(changed-range) inline check per mutation.

### Repro-test methodology (house convention)

Bug fixes are test-driven with promoted repros: write a test that asserts the EXPECTED (correct) behavior so it FAILS on unfixed code (with setup sanity assertions proving the claimed path is genuinely exercised), land the fix, confirm the test passes, and keep it in `test/sliver_tree/` as the regression test. The 2026-07 audit's repro batch (`audit_repro_*_test.dart`) followed this flow end to end.

**Every new assertion must be shown to fail.** "The test fails on unfixed code" is not enough, because one assertion can carry the whole failure while its neighbours are inert. Construct the state each individual assertion is meant to reject and watch that assertion go red. An assertion that cannot fail in the direction it claims to check is a defect even when the test as a whole discriminates, and a setup sanity assertion that cannot fail is worse than none, because it reads as proof that the path was exercised.
