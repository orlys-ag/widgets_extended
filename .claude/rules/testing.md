---
paths:
  - "test/*.dart"
  - "test/**/*.dart"
---

# Testing patterns

Normative for `test/`.

- sliver_tree controller tests use `testWidgets` with `tester` as the `TickerProvider` and `animationStyle: TreeAnimationStyle.disabled` for synchronous behavior.
- **Pin family-flow, not literal timings.** Animation tests assert that a call consumes the CONFIGURED family's spec (set a distinctive spec, observe it govern), not hardcoded durations/curves; literal pins are reserved for tests whose subject IS a default value.
- sliver_tree widget tests wrap `SliverTree` in `MaterialApp > Scaffold > CustomScrollView`.
- Uses `flutter_test`; no third-party test dependencies.
- Perf contracts are pinned via debug counters on the render object / controller (`debugLastPaintIterationCount`, `debugLastParentDataCumulativeBuilds`, `debugPerformLayoutCount`, `debugOrderResetIndexAllCount`, ...).
- **Justify a new seam against an existing one.** Before adding a `debug*` counter or a `@visibleForTesting` member, name the seam you rejected and why. `lib/` already carries many of both (`grep -rhoE '\bdebug[A-Z][A-Za-z0-9_]*' lib --include=*.dart | sort -u`, `grep -rn '@visibleForTesting' lib --include=*.dart`), and a seam on a public render object is permanent. Prefer the highest seam that can observe the behaviour; the counters above exist because paint-iteration counts are genuinely not observable from the widget surface, which is the bar a new one has to clear.
- The sliver_tree invariant-heavy suites (fuzz/purge/zombie) enable `TreeController.debugFullConsistencyChecks = true`; everywhere else debug builds run only an O(changed-range) inline check per mutation.

## Repro-test methodology

Bug fixes are test-driven with promoted repros: write a test that asserts the EXPECTED (correct) behavior so it FAILS on unfixed code (with setup sanity assertions proving the claimed path is genuinely exercised), land the fix, confirm the test passes, and keep it in the module's `test/` directory as the regression test.

**Every new assertion must be shown to fail.** "The test fails on unfixed code" is not enough, because one assertion can carry the whole failure while its neighbours are inert. Construct the state each individual assertion is meant to reject and watch that assertion go red. An assertion that cannot fail in the direction it claims to check is a defect even when the test as a whole discriminates, and a setup sanity assertion that cannot fail is worse than none, because it reads as proof that the path was exercised.
