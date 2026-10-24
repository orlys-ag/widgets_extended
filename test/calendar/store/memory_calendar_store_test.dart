/// The in-memory store: always loaded, its reads in order, its ids, and
/// its writes applied within the call.
library;

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

const Color taskColor = Color(0xFF3060C0);

/// An entry from [start] minutes after [day]'s midnight to [end] minutes
/// after the midnight of its [dayCount]th day.
CalendarEntry<String> task(
  String? id,
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
  String title = "Task",
}) {
  return CalendarEntry<String>(
    id: id,
    start: at(day, start),
    end: at(DateTime(day.year, day.month, day.day + dayCount - 1), end),
    title: title,
    color: taskColor,
    payload: "task",
  );
}

/// [minute] minutes after [day]'s midnight.
DateTime at(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, 0, minute);
}

/// What a store reported: each notification and each `onChanged` call, in
/// the order they came.
class Recorder {
  final List<String> events = <String>[];
  final List<(CalendarEntry<String>?, CalendarEntry<String>?)> changes =
      <(CalendarEntry<String>?, CalendarEntry<String>?)>[];
  final List<CalendarWriteFailure> failures = <CalendarWriteFailure>[];

  MemoryCalendarStore<String> store({
    List<CalendarEntry<String>> entries = const <CalendarEntry<String>>[],
    DayHours hours = DayHours.allDay,
  }) {
    final store = MemoryCalendarStore<String>(
      entries: entries,
      hours: hours,
      onChanged: (old, entry) {
        events.add("changed");
        changes.add((old, entry));
      },
      onWriteFailed: (failure) {
        failures.add(failure);
      },
    );
    store.addListener(() {
      events.add("notified");
    });
    return store;
  }
}

/// Listens to [call] at once and returns what it failed with so far, null
/// while it has not failed.
Object? Function() errorOf(Future<Object?> call) {
  Object? error;
  call.then(
    (value) {},
    onError: (Object failure) {
      error = failure;
    },
  );
  return () {
    return error;
  };
}

List<String> idsOf(List<CalendarShownEntry<String>> shown) {
  return <String>[for (final entry in shown) entry.id];
}

final DateTime day = DateTime(2026, 4, 22);

void main() {
  test("MS1 the store is loaded before any show", () {
    final recorder = Recorder();
    final store = recorder.store();
    final first = DateTime(2026, 4, 1);
    final last = DateTime(2026, 6, 30);
    expect(store.status, CalendarLoadStatus.ready);
    expect(store.loadError, isNull);
    expect(store.isRead(first), isTrue);
    expect(store.readFailed(first), isFalse);
    expect(store.isShown(first, last), isTrue);
    expect(store.isWithinShown(first, last), isTrue);

    store.show(first, last);
    store.retry();
    store.prefetch(first, last);
    expect(recorder.events, isEmpty);
  });

  test("MS2 the reads answer in order, each entry once", () {
    final store = Recorder().store(
      entries: <CalendarEntry<String>>[
        task("id-1", day, 600, 660, title: "Gamma"),
        task("id-4", day, 600, 630, title: "Zed"),
        task("id-2", day, 600, 660, title: "Gamma"),
        task("id-5", day, 540, 600, title: "Zed"),
        task("id-3", day, 600, 660, title: "Beta"),
      ],
    );
    // By start, then end, then title, then id.
    expect(idsOf(store.entriesOn(day)), <String>[
      "id-5",
      "id-4",
      "id-3",
      "id-1",
      "id-2",
    ]);

    final first = DateTime(2026, 5, 5);
    final range = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        task("three", first, 660, 720, dayCount: 3, title: "Three"),
        task("ten", first, 600, 660, title: "Ten"),
        task("nine", DateTime(2026, 5, 7), 540, 570, title: "Nine"),
        task("late", DateTime(2026, 5, 8), 780, 840, title: "Late"),
        task("after", DateTime(2026, 5, 9), 480, 510, title: "After"),
      ],
    );
    for (final date in <int>[5, 6, 7]) {
      expect(
        idsOf(range.entriesOn(DateTime(2026, 5, date))),
        contains("three"),
        reason: "May $date",
      );
    }
    expect(idsOf(range.entriesOn(DateTime(2026, 5, 4))), isEmpty);
    expect(idsOf(range.entriesOn(DateTime(2026, 5, 8))), <String>["late"]);
    expect(idsOf(range.entriesBetween(first, DateTime(2026, 5, 8))), <String>[
      "ten",
      "three",
      "nine",
      "late",
    ]);
    expect(range.dayHasShownEntries(DateTime(2026, 5, 6)), isTrue);
    expect(range.dayHasShownEntries(DateTime(2026, 5, 10)), isFalse);
  });

  test("MS3 a create keeps a draft's own free id and otherwise gives the "
      "next free entry-<n>", () async {
    final recorder = Recorder();
    final store = recorder.store();
    final first = await store.create(task(null, day, 480, 540));
    expect(first.id, "entry-1");
    final own = await store.create(task("entry-2", day, 540, 600));
    expect(own.id, "entry-2");
    final third = await store.create(task(null, day, 600, 660));
    expect(third.id, "entry-3");
    expect(store.storedEntry("entry-2"), own);

    final events = recorder.events.length;
    final refused = errorOf(store.create(task("entry-1", day, 720, 780)));
    await pumpEventQueue();
    expect(refused(), isA<ArgumentError>());
    expect(store.storedEntry("entry-1"), first);
    expect(store.entries, hasLength(3));
    expect(recorder.events, hasLength(events));
  });

  test("MS4 a move applies within the call, notifying and then reporting "
      "the change", () {
    final recorder = Recorder();
    final item = task("item-1", day, 600, 660);
    final store = recorder.store(entries: <CalendarEntry<String>>[item]);
    final moved = item.copyWith(start: at(day, 720), end: at(day, 780));
    final pendingSeen = <bool>[];
    final storedSeen = <CalendarEntry<String>?>[];
    store.addListener(() {
      pendingSeen.add(store.isPending("item-1"));
      storedSeen.add(store.storedEntry("item-1"));
    });

    store.requestMove(moved);
    expect(store.storedEntry("item-1"), moved);
    expect(recorder.events, <String>["notified", "changed"]);
    expect(recorder.changes, <(CalendarEntry<String>?, CalendarEntry<String>?)>[
      (item, moved),
    ]);
    expect(storedSeen, <CalendarEntry<String>?>[moved]);
    expect(pendingSeen, <bool>[false]);
    expect(store.isPending("item-1"), isFalse);
  });

  test("MS5 a refused write changes nothing", () async {
    final recorder = Recorder();
    final item = task("item-1", day, 600, 660);
    final other = task("item-2", day, 720, 780);
    final early = task("item-3", day, 420, 450);
    final store = recorder.store(
      entries: <CalendarEntry<String>>[item, other, early],
      hours: const DayHours(480, 1080),
    );

    store.requestMove(item.copyWith(start: at(day, 450), end: at(day, 510)));
    store.requestMove(item.copyWith(start: at(day, 750), end: at(day, 810)));
    expect(recorder.failures, hasLength(2));
    expect(recorder.failures[0].id, "item-1");
    expect(
      recorder.failures[0].error,
      isA<CalendarHoursException>()
          .having((error) => error.startOutside, "startOutside", isTrue)
          .having((error) => error.endOutside, "endOutside", isFalse),
    );
    expect(recorder.failures[1].id, "item-1");
    expect(
      recorder.failures[1].error,
      isA<CalendarEntryOverlapException>().having(
        (error) => error.conflictingIds,
        "conflictingIds",
        <String>["item-2"],
      ),
    );
    expect(store.storedEntry("item-1"), item);
    expect(recorder.events, isEmpty);

    final created = errorOf(store.create(task(null, day, 1050, 1110)));
    await pumpEventQueue();
    expect(created(), isA<CalendarHoursException>());
    expect(store.entries, hasLength(3));
    expect(recorder.events, isEmpty);

    final renamed = early.copyWith(title: "Renamed");
    expect(await store.update(renamed), renamed);
    expect(store.storedEntry("item-3"), renamed);
  });

  test("MS6 each write notifies once and then reports its change", () async {
    final recorder = Recorder();
    final item = task("item-1", day, 600, 660);
    final store = recorder.store(entries: <CalendarEntry<String>>[item]);

    final creating = store.create(task(null, day, 720, 780));
    expect(recorder.events, <String>["notified", "changed"]);
    final created = await creating;
    expect(recorder.changes.single, (null, created));
    expect(store.entriesOn(day), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(item, pending: false),
      CalendarShownEntry<String>(created, pending: false),
    ]);

    recorder.events.clear();
    recorder.changes.clear();
    final renamed = item.copyWith(title: "Renamed");
    final updating = store.update(renamed);
    expect(recorder.events, <String>["notified", "changed"]);
    expect(recorder.changes.single, (item, renamed));
    expect(await updating, renamed);

    recorder.events.clear();
    recorder.changes.clear();
    store.requestDelete("item-1");
    expect(recorder.events, <String>["notified", "changed"]);
    expect(recorder.changes.single, (renamed, null));
    expect(store.storedEntry("item-1"), isNull);
    expect(idsOf(store.entriesOn(day)), <String>[created.id!]);

    recorder.events.clear();
    final unknown = errorOf(store.update(task("item-9", day, 600, 660)));
    store.requestMove(task("item-9", day, 600, 660));
    store.requestDelete("item-9");
    await pumpEventQueue();
    expect(unknown(), isA<ArgumentError>());
    expect(recorder.failures, hasLength(2));
    for (final failure in recorder.failures) {
      expect(failure.id, "item-9");
      expect(failure.error, isA<ArgumentError>());
    }
    expect(recorder.events, isEmpty);
  });

  test("MS7 the entries setter replaces every entry and checks the ids", () {
    final recorder = Recorder();
    final item = task("item-1", day, 600, 660);
    final store = recorder.store(entries: <CalendarEntry<String>>[item]);
    final other = task("item-2", day, 720, 780);

    store.entries = <CalendarEntry<String>>[other];
    expect(store.entries, <CalendarEntry<String>>[other]);
    expect(idsOf(store.entriesOn(day)), <String>["item-2"]);
    expect(recorder.events, <String>["notified"]);
    expect(recorder.changes, isEmpty);

    recorder.events.clear();
    expect(
      () => store.entries = <CalendarEntry<String>>[
        item,
        task(null, day, 480, 540),
      ],
      throwsArgumentError,
    );
    expect(
      () => store.entries = <CalendarEntry<String>>[
        item,
        task("item-1", day, 480, 540),
      ],
      throwsArgumentError,
    );
    expect(store.entries, <CalendarEntry<String>>[other]);
    expect(idsOf(store.entriesOn(day)), <String>["item-2"]);
    expect(recorder.events, isEmpty);

    expect(
      () => MemoryCalendarStore<String>(
        entries: <CalendarEntry<String>>[task(null, day, 480, 540)],
      ),
      throwsArgumentError,
    );
    expect(
      () => MemoryCalendarStore<String>(
        entries: <CalendarEntry<String>>[
          item,
          item.copyWith(title: "Again"),
        ],
      ),
      throwsArgumentError,
    );
  });

  test("MS8 the first free range is searched over the held entries", () {
    final first = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        task("item-1", day, 0, 60),
        task("item-2", day, 75, 120),
      ],
    );
    expect(first.firstFreeRange(day, slotMinutes: 15), (
      start: at(day, 60),
      end: at(day, 75),
    ));

    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        task("item-1", day, 480, 540),
        task("item-2", day, 900, 960),
      ],
      hours: const DayHours(480, 1200),
    );
    expect(store.firstFreeRange(day, slotMinutes: 15, from: 840), (
      start: at(day, 840),
      end: at(day, 855),
    ));
    expect(store.firstFreeRange(day, slotMinutes: 15, from: 850), (
      start: at(day, 855),
      end: at(day, 870),
    ));
    expect(store.firstFreeRange(day, slotMinutes: 15, from: 900), (
      start: at(day, 960),
      end: at(day, 975),
    ));
    expect(store.firstFreeRange(day, slotMinutes: 15, from: 300), (
      start: at(day, 540),
      end: at(day, 555),
    ));
    expect(store.firstFreeRange(day, slotMinutes: 15, from: 1200), (
      start: at(day, 540),
      end: at(day, 555),
    ));
  });

  test("MS9 a shown entry is a value of the entry and its flag", () {
    final item = task("item-1", day, 600, 660);
    final a = CalendarShownEntry<String>(item, pending: true);
    final b = CalendarShownEntry<String>(
      task("item-1", day, 600, 660),
      pending: true,
    );
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    expect(a == CalendarShownEntry<String>(item, pending: false), isFalse);
  });
}
