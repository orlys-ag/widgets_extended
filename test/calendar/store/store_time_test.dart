/// Both stores on start and end: an overnight entry answered on each day
/// it covers, a set of the hours notifying where they change, the hours
/// rule on an entry's start and its last day's end,
/// the overlap rule on instants with all-day entries exempt, minutes off
/// the slot grid kept, and the local zone's DST days answered once.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';

import '../dst_days.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime sunday = DateTime(2026, 4, 19);

/// [day] at [hour] and [minute].
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

CalendarEntry<String> entryOf(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// A data source that answers each read within the call, through a
/// [SynchronousFuture], with every entry having any part in its days, and
/// stores each replace within the call. It records the days each read
/// asked for.
class OverlapSource implements CalendarDataSource<String> {
  OverlapSource(Iterable<CalendarEntry<String>> entries)
    : entries = <String, CalendarEntry<String>>{
        for (final entry in entries) entry.id!: entry,
      };

  final Map<String, CalendarEntry<String>> entries;

  final List<(DateTime, DateTime)> reads = <(DateTime, DateTime)>[];

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    reads.add((first, last));
    final from = dayNumber(first);
    final to = dayNumber(last);
    return SynchronousFuture<List<CalendarEntry<String>>>(
      <CalendarEntry<String>>[
        for (final entry in entries.values)
          if (dayNumber(entry.start) <= to &&
              lastDayNumberOf(entry.start, entry.end) >= from)
            entry,
      ],
    );
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    entries[entry.id!] = entry;
    return SynchronousFuture<CalendarEntry<String>>(entry);
  }

  @override
  Future<void> delete(String id) {
    entries.remove(id);
    return SynchronousFuture<void>(null);
  }
}

/// One store of each kind holding [entries], under [hours], reporting a
/// failed write to [failures]: an in-memory store, and a caching store
/// over an [OverlapSource] that has shown and read [first] to [last].
List<(String, CalendarStore<String>)> storesOf(
  List<CalendarEntry<String>> entries, {
  required DateTime first,
  required DateTime last,
  DayHours hours = DayHours.allDay,
  List<CalendarWriteFailure>? failures,
}) {
  final memory = MemoryCalendarStore<String>(
    entries: entries,
    hours: hours,
    onWriteFailed: failures?.add,
  );
  final caching = CachingCalendarStore<String>(
    dataSource: OverlapSource(entries),
    hours: hours,
    onWriteFailed: failures?.add,
  );
  addTearDown(memory.dispose);
  addTearDown(caching.dispose);
  caching.show(first, last);
  expect(caching.status, CalendarLoadStatus.ready);
  return <(String, CalendarStore<String>)>[
    ("memory", memory),
    ("caching", caching),
  ];
}

/// The ids of [shown], in order.
List<String> idsOf(List<CalendarShownEntry<String>> shown) {
  return <String>[for (final entry in shown) entry.id];
}

void main() {
  test("SM1 an overnight entry is answered on both days it covers and not "
      "on a day it ends at the start of, and a caching store's read of "
      "either day returns it", () {
    final night = entryOf("night", at(monday, 22), at(tuesday, 2));
    final toMidnight = entryOf("to-midnight", at(sunday, 22), monday);
    for (final (name, store) in storesOf(
      <CalendarEntry<String>>[night, toMidnight],
      first: sunday,
      last: wednesday,
    )) {
      expect(idsOf(store.entriesOn(monday)), <String>["night"], reason: name);
      expect(idsOf(store.entriesOn(tuesday)), <String>["night"], reason: name);
      expect(store.entriesOn(wednesday), isEmpty, reason: name);
      expect(idsOf(store.entriesOn(sunday)), <String>[
        "to-midnight",
      ], reason: name);
      expect(store.dayHasShownEntries(tuesday), isTrue, reason: name);
      expect(store.dayHasShownEntries(wednesday), isFalse, reason: name);
      expect(idsOf(store.entriesBetween(sunday, wednesday)), <String>[
        "to-midnight",
        "night",
      ], reason: name);
      expect(idsOf(store.entriesBetween(tuesday, wednesday)), <String>[
        "night",
      ], reason: name);
    }

    for (final day in <DateTime>[monday, tuesday]) {
      final source = OverlapSource(<CalendarEntry<String>>[night]);
      final caching = CachingCalendarStore<String>(dataSource: source);
      addTearDown(caching.dispose);
      caching.show(day, day);
      expect(source.reads, <(DateTime, DateTime)>[(day, day)]);
      expect(caching.isRead(day), isTrue);
      expect(idsOf(caching.entriesOn(day)), <String>["night"], reason: "$day");
    }
  });

  test("SM2 under 08:00-18:00 an overnight entry starting and ending inside "
      "the hours is accepted, one ending after them is refused, an all-day "
      "entry is accepted, and a write keeping the stored start and end "
      "skips the rule", () async {
    const office = DayHours(8 * 60, 18 * 60);
    final outside = entryOf("outside", at(monday, 6), at(monday, 7));
    final task = entryOf("task", at(monday, 9), at(monday, 10));
    final failures = <CalendarWriteFailure>[];
    for (final (name, store) in storesOf(
      <CalendarEntry<String>>[outside, task],
      first: monday,
      last: wednesday,
      hours: office,
      failures: failures,
    )) {
      failures.clear();
      store.requestMove(
        task.copyWith(start: at(monday, 17), end: at(tuesday, 9)),
      );
      expect(failures, isEmpty, reason: name);
      expect(store.storedEntry("task")!.end, at(tuesday, 9), reason: name);

      store.requestMove(
        task.copyWith(start: at(monday, 17), end: at(monday, 19)),
      );
      expect(failures, hasLength(1), reason: name);
      final refusal = failures.single.error;
      expect(refusal, isA<CalendarHoursException>(), reason: name);
      refusal as CalendarHoursException;
      expect(refusal.start, at(monday, 17), reason: name);
      expect(refusal.end, at(monday, 19), reason: name);
      expect(refusal.startOutside, isFalse, reason: name);
      expect(refusal.endOutside, isTrue, reason: name);
      expect(store.storedEntry("task")!.end, at(tuesday, 9), reason: name);

      failures.clear();
      store.requestMove(task.copyWith(start: tuesday, end: wednesday));
      expect(failures, isEmpty, reason: name);
      expect(store.storedEntry("task")!.isAllDay, isTrue, reason: name);

      // The entry outside the hours keeps its times through an update.
      final renamed = await store.update(outside.copyWith(title: "renamed"));
      expect(renamed.title, "renamed", reason: name);
      expect(store.storedEntry("outside")!.start, at(monday, 6), reason: name);
      await expectLater(
        store.update(outside.copyWith(end: at(monday, 7, 30))),
        throwsA(isA<CalendarHoursException>()),
        reason: name,
      );
    }
  });

  test("SM3 a move onto a timed entry's time is stored with no failure, and "
      "an all-day entry over a busy day is accepted", () {
    final busy = entryOf("busy", at(tuesday, 0, 30), at(tuesday, 1, 30));
    final task = entryOf("task", at(monday, 9), at(monday, 10));
    final failures = <CalendarWriteFailure>[];
    for (final (name, store) in storesOf(
      <CalendarEntry<String>>[busy, task],
      first: monday,
      last: wednesday,
      failures: failures,
    )) {
      failures.clear();
      final onto = task.copyWith(start: at(monday, 23), end: at(tuesday, 1));
      store.requestMove(onto);
      expect(failures, isEmpty, reason: name);
      expect(store.storedEntry("task"), onto, reason: name);

      failures.clear();
      store.requestMove(task.copyWith(start: tuesday, end: wednesday));
      expect(failures, isEmpty, reason: name);
      expect(store.storedEntry("task")!.start, tuesday, reason: name);
    }
  });

  test("SM4 an entry from 09:10 to 09:50 is answered with its start and end "
      "unchanged", () {
    final task = entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50));
    for (final (name, store) in storesOf(
      <CalendarEntry<String>>[task],
      first: monday,
      last: wednesday,
    )) {
      final shown = store.entriesOn(tuesday).single.entry;
      expect(shown.start, at(tuesday, 9, 10), reason: name);
      expect(shown.end, at(tuesday, 9, 50), reason: name);
      expect(store.storedEntry("task"), task, reason: name);
    }
  });

  test("SM8 a set of other hours notifies once, and a set of equal hours "
      "notifies nothing", () {
    const office = DayHours(8 * 60, 18 * 60);
    for (final (name, store) in storesOf(
      const <CalendarEntry<String>>[],
      first: monday,
      last: wednesday,
    )) {
      var notifications = 0;
      store.addListener(() {
        notifications++;
      });
      store.hours = office;
      expect(store.hours, office, reason: name);
      expect(notifications, 1, reason: name);
      // Equal hours in another instance.
      store.hours = DayHours(office.start, office.end);
      expect(notifications, 1, reason: name);
    }
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    test("SM6 the day's entries are answered for that day once", () {
      final day = shortDayStart;
      final next = addDays(day, 1);
      final allDay = entryOf("all-day", day, next);
      final early = entryOf("early", at(day, 1, 30), at(day, 3, 30));
      for (final (name, store) in storesOf(
        <CalendarEntry<String>>[allDay, early],
        first: addDays(day, -1),
        last: next,
      )) {
        expect(idsOf(store.entriesOn(day)), <String>[
          "all-day",
          "early",
        ], reason: name);
        expect(store.entriesOn(next), isEmpty, reason: name);
        expect(store.entriesOn(addDays(day, -1)), isEmpty, reason: name);
        expect(idsOf(store.entriesBetween(addDays(day, -1), next)), <String>[
          "all-day",
          "early",
        ], reason: name);
      }
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    test("SM6 the day's entries are answered for that day once", () {
      final day = longDayStart;
      final next = addDays(day, 1);
      final allDay = entryOf("all-day", day, next);
      final repeated = entryOf(
        "repeated",
        secondHalfPastOne,
        secondHalfPastOne.add(const Duration(minutes: 30)),
      );
      for (final (name, store) in storesOf(
        <CalendarEntry<String>>[allDay, repeated],
        first: addDays(day, -1),
        last: next,
      )) {
        expect(idsOf(store.entriesOn(day)), <String>[
          "all-day",
          "repeated",
        ], reason: name);
        expect(store.entriesOn(next), isEmpty, reason: name);
        expect(idsOf(store.entriesBetween(addDays(day, -1), next)), <String>[
          "all-day",
          "repeated",
        ], reason: name);
      }
    });
  });
}
