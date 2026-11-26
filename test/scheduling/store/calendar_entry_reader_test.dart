/// The read model's own answers: the load state of a range of days walked
/// from what a reader answers of each day, no load error, the stale days
/// it reports to its listeners, every day it is asked about stale, and the
/// stale days' range check.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';

/// A reader that answers [isRead] and [readFailed] from the day numbers
/// [read] and [failed], and nothing of entries: it shows none, asks for
/// nothing and notifies no listener, so its [statusOf], [loadErrorOf],
/// stale-days listeners and [isStale] are the reader's own.
final class SetReader extends CalendarEntryReader<String> {
  SetReader({this.read = const <int>{}, this.failed = const <int>{}});

  final Set<int> read;

  final Set<int> failed;

  /// Reports [days] to the stale-days listeners.
  void report(CalendarStaleDays days) {
    notifyStaleDays(days);
  }

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  Location? get zone {
    return null;
  }

  @override
  List<CalendarShownEntry<String>> entriesOn(DateTime day) {
    return <CalendarShownEntry<String>>[];
  }

  @override
  List<CalendarShownEntry<String>> entriesBetween(
    DateTime first,
    DateTime last,
  ) {
    return <CalendarShownEntry<String>>[];
  }

  @override
  bool dayHasShownEntries(DateTime day) {
    return false;
  }

  @override
  bool isPending(String id) {
    return false;
  }

  @override
  CalendarEntry<String>? storedEntry(String id) {
    return null;
  }

  @override
  bool isRead(DateTime day) {
    return read.contains(CalendarDates.dayNumber(day));
  }

  @override
  bool readFailed(DateTime day) {
    return failed.contains(CalendarDates.dayNumber(day));
  }

  @override
  void prefetch(DateTime first, DateTime last) {}

  @override
  void retry([DateTime? first, DateTime? last]) {}
}

/// April [day] 2026.
DateTime april(int day) {
  return DateTime(2026, 4, day);
}

/// The day number of April [day] 2026.
int aprilDay(int day) {
  return CalendarDates.dayNumber(april(day));
}

void main() {
  test("RR1 a reader's load state of a range is failed where a day of it "
      "failed, loading where one is unread, and ready otherwise, also for "
      "a range of no day", () {
    final every = <int>{aprilDay(20), aprilDay(21), aprilDay(22)};
    expect(
      SetReader(read: every).statusOf(april(20), april(22)),
      CalendarLoadStatus.ready,
    );
    expect(
      SetReader(
        read: <int>{aprilDay(20), aprilDay(22)},
      ).statusOf(april(20), april(22)),
      CalendarLoadStatus.loading,
    );
    // April 22 is unread, and April 21 failed.
    expect(
      SetReader(
        read: <int>{aprilDay(20)},
        failed: <int>{aprilDay(21)},
      ).statusOf(april(20), april(22)),
      CalendarLoadStatus.failed,
    );
    expect(
      SetReader().statusOf(april(22), april(20)),
      CalendarLoadStatus.ready,
    );
  });

  test("RR2 a reader holds no load error by default", () {
    final reader = SetReader(failed: <int>{aprilDay(21)});
    // Setup sanity: the range is failed.
    expect(reader.statusOf(april(20), april(22)), CalendarLoadStatus.failed);
    expect(reader.loadErrorOf(april(20), april(22)), isNull);
  });

  test("RR3 a reader reports stale days to each listener once per "
      "registration, in order, past one that throws, to none removed before "
      "its turn, and takes every day it is asked about to be stale", () {
    final reader = SetReader();
    final calls = <(String, CalendarStaleDays)>[];
    ValueChanged<CalendarStaleDays> recording(String name) {
      return (days) {
        calls.add((name, days));
      };
    }

    final a = recording("a");
    final b = recording("b");
    reader.addStaleDaysListener(a);
    reader.addStaleDaysListener(b);
    reader.addStaleDaysListener(a);
    final days = CalendarStaleDays(april(20), april(22));
    reader.report(days);
    expect(
      <String>[for (final (name, _) in calls) name],
      <String>["a", "b", "a"],
    );
    for (final (_, given) in calls) {
      expect(given, same(days));
    }

    calls.clear();
    reader.removeStaleDaysListener(b);
    reader.removeStaleDaysListener(a);
    reader.report(days);
    expect(<String>[for (final (name, _) in calls) name], <String>["a"]);

    calls.clear();
    reader.removeStaleDaysListener(a);
    final errors = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      reader.addStaleDaysListener((days) {
        throw StateError("The listener failed.");
      });
      reader.addStaleDaysListener(recording("after the throw"));
      reader.report(days);
    } finally {
      FlutterError.onError = onError;
    }
    expect(errors, hasLength(1));
    expect(errors.single.exception, isStateError);
    expect(
      <String>[for (final (name, _) in calls) name],
      <String>["after the throw"],
    );

    final second = SetReader();
    calls.clear();
    final removed = recording("removed");
    second.addStaleDaysListener((days) {
      calls.add(("remover", days));
      second.removeStaleDaysListener(removed);
    });
    second.addStaleDaysListener(removed);
    second.report(days);
    expect(<String>[for (final (name, _) in calls) name], <String>["remover"]);

    expect(reader.isStale(april(21)), isTrue);
  });

  test("RR4 stale days hold one day or more, compared by their day "
      "numbers, and every day holds none", () {
    expect(() {
      return CalendarStaleDays(april(21), april(20));
    }, throwsA(isArgumentError.having((error) => error.name, "name", "last")));
    final oneDay = CalendarStaleDays(
      DateTime(2026, 4, 21, 10),
      DateTime(2026, 4, 21, 9),
    );
    expect(oneDay.first, DateTime(2026, 4, 21, 10));
    expect(oneDay.last, DateTime(2026, 4, 21, 9));
    const every = CalendarStaleDays.all();
    expect(every.first, isNull);
    expect(every.last, isNull);
  });
}
