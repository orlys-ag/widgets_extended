/// A differential fuzz of [CachingCalendarStore] against the data source
/// [FuzzRun] models. Each configuration runs `FUZZ_RUNS` seeds from
/// `FUZZ_SEED`, which a long run raises with `--dart-define`, as
/// `--dart-define=FUZZ_RUNS=1500`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/scheduling.dart';

import 'caching_store_model.dart';

const int _runs = int.fromEnvironment("FUZZ_RUNS", defaultValue: 100);
const int _firstSeed = int.fromEnvironment("FUZZ_SEED", defaultValue: 1);

CalendarStore<String> _cachingStore(
  CalendarDataSource<String> source,
  Stream<CalendarSourceChange<String>> changes,
  Location? zone,
  int readAhead,
) {
  return CachingCalendarStore<String>(
    dataSource: source,
    changes: changes,
    zone: zone,
    readAhead: readAhead,
  );
}

/// The problems of the first divergent runs of [summary], for a failure's
/// reason.
String _divergence(FuzzSummary summary) {
  final buffer = StringBuffer(summary);
  for (final run in summary.divergent.values.take(3)) {
    buffer.writeln("seed ${run.seed}:");
    for (final problem in run.problems.take(4)) {
      buffer.writeln("  $problem");
    }
  }
  return buffer.toString();
}

FuzzSummary _fuzz(FuzzOptions options) {
  return runFuzz(
    _cachingStore,
    firstSeed: _firstSeed,
    runs: _runs,
    options: options,
    keepRuns: true,
  );
}

void main() {
  test("with every kind of announcement, the store agrees with the source "
      "on every seed", () {
    final summary = _fuzz(const FuzzOptions());
    expect(summary.problemSeeds.keys, isEmpty, reason: _divergence(summary));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test("with its own writes unannounced and writes racing reads, the store "
      "agrees with the source on every seed", () {
    final summary = _fuzz(const FuzzOptions(streamMode: 3, focus: true));
    expect(summary.problemSeeds.keys, isEmpty, reason: _divergence(summary));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test("with answers and announcements within the call, reads served late "
      "and zone changes, the store agrees with the source on every seed", () {
    final summary = _fuzz(
      const FuzzOptions(
        lateServe: true,
        announceWithin: true,
        zoneFocus: true,
        syncAnswers: true,
      ),
    );
    for (final path in <String>[
      "path:read-answered-within",
      "path:write-answered-within",
      "path:announced-within",
      "path:late-serve-changed",
      "path:zone-change-with-writes",
    ]) {
      expect(summary.counts[path], greaterThan(0), reason: path);
    }
    expect(summary.problemSeeds.keys, isEmpty, reason: _divergence(summary));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test("the model finds stale days in a store whose source announces "
      "nothing", () {
    final summary = runFuzz(
      _cachingStore,
      firstSeed: _firstSeed,
      runs: 20,
      options: const FuzzOptions(dropAnnouncements: true),
    );
    expect(summary.problemSeeds.keys, contains("stale-shown-fresh"));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
