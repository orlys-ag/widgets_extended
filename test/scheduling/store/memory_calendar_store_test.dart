/// The in-memory store: always loaded, its reads in order, its ids, and
/// its writes applied within the call.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/scheduling.dart';

import '../zones.dart';
import 'zone_support.dart';

const Color taskColor = Color(0xFF3060C0);

/// An entry from [start] minutes after [day]'s midnight to [end] minutes
/// after the midnight of its [dayCount]th day, all-day where [isAllDay].
CalendarEntry<String> task(
  String? id,
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
  String title = "Task",
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: at(day, start),
    end: at(DateTime(day.year, day.month, day.day + dayCount - 1), end),
    title: title,
    color: taskColor,
    payload: "task",
    isAllDay: isAllDay,
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

  MemoryCalendarStore<String> store({
    List<CalendarEntry<String>> entries = const <CalendarEntry<String>>[],
    CalendarDayHours hours = CalendarDayHours.allDay,
  }) {
    final store = MemoryCalendarStore<String>(
      entries: entries,
      hours: hours,
      onChanged: (old, entry) {
        events.add("changed");
        changes.add((old, entry));
      },
    );
    store.addListener(() {
      events.add("notified");
    });
    return store;
  }
}

/// Listens to [call] at once, and completes with what it completed with:
/// its value, or the error it failed with.
Future<Object?> outcomeOf(Future<Object?> call) {
  return call.then<Object?>(
    (value) {
      return value;
    },
    onError: (Object error) {
      return error;
    },
  );
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

/// What MS12's [MemoryCalendarStore.onChanged] throws.
class HostFailure implements Exception {
  const HostFailure();
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
      "the change, and completes with the moved entry", () async {
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

    final moving = outcomeOf(store.requestMove(moved));
    expect(store.storedEntry("item-1"), moved);
    expect(recorder.events, <String>["notified", "changed"]);
    expect(recorder.changes, <(CalendarEntry<String>?, CalendarEntry<String>?)>[
      (item, moved),
    ]);
    expect(storedSeen, <CalendarEntry<String>?>[moved]);
    expect(pendingSeen, <bool>[false]);
    expect(store.isPending("item-1"), isFalse);
    expect(await moving, same(moved));
  });

  test("MS5 a refused write changes nothing", () async {
    final recorder = Recorder();
    final item = task("item-1", day, 600, 660);
    final other = task("item-2", day, 720, 780);
    final early = task("item-3", day, 420, 450);
    final store = recorder.store(
      entries: <CalendarEntry<String>>[item, other, early],
      hours: CalendarDayHours(480, 1080),
    );

    final moved = errorOf(
      store.requestMove(item.copyWith(start: at(day, 450), end: at(day, 510))),
    );
    await pumpEventQueue();
    expect(
      moved(),
      isA<CalendarHoursException>()
          .having((error) => error.startOutside, "startOutside", isTrue)
          .having((error) => error.endOutside, "endOutside", isFalse),
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
    final deleting = outcomeOf(store.requestDelete("item-1"));
    expect(recorder.events, <String>["notified", "changed"]);
    expect(recorder.changes.single, (renamed, null));
    expect(store.storedEntry("item-1"), isNull);
    expect(idsOf(store.entriesOn(day)), <String>[created.id!]);
    expect(await deleting, isNull);

    recorder.events.clear();
    final unknown = errorOf(store.update(task("item-9", day, 600, 660)));
    final moving = errorOf(store.requestMove(task("item-9", day, 600, 660)));
    final removing = errorOf(store.requestDelete("item-9"));
    await pumpEventQueue();
    expect(unknown(), isA<ArgumentError>());
    expect(moving(), isA<ArgumentError>());
    expect(removing(), isA<ArgumentError>());
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

  test("RC18 a shown entry throws an ArgumentError for an entry with no "
      "id", () {
    expect(() {
      return CalendarShownEntry<String>(
        task(null, day, 600, 660),
        pending: false,
      );
    }, throwsA(isArgumentError.having((error) => error.name, "name", "entry")));
    expect(
      CalendarShownEntry<String>(
        task("item-1", day, 600, 660),
        pending: false,
      ).id,
      "item-1",
    );
  });

  test(
    "MS10 invalidate and refresh change nothing and notify nothing",
    () async {
      final recorder = Recorder();
      final item = task("item-1", day, 600, 660);
      final store = recorder.store(entries: <CalendarEntry<String>>[item]);
      store.invalidate(day, day);
      var refreshed = false;
      store.refresh().then((_) {
        refreshed = true;
      });
      await pumpEventQueue();
      expect(refreshed, isTrue);
      expect(recorder.events, isEmpty);
      expect(idsOf(store.entriesOn(day)), <String>["item-1"]);
    },
  );

  test("MS11 a retry of a range changes nothing and notifies nothing, and "
      "one given one of first and last throws an ArgumentError", () {
    final recorder = Recorder();
    final item = task("item-1", day, 600, 660);
    final store = recorder.store(entries: <CalendarEntry<String>>[item]);
    final last = DateTime(2026, 4, 28);
    store.retry(day, last);
    expect(recorder.events, isEmpty);
    expect(store.entries, <CalendarEntry<String>>[item]);
    expect(() {
      store.retry(day);
    }, throwsArgumentError);
    expect(() {
      store.retry(null, last);
    }, throwsArgumentError);
  });

  test(
    "MS12 a create, an update, a move and a delete whose onChanged "
    "throws each apply their change and complete as they would without "
    "the throw, and the throw is reported after the store notifies",
    () async {
      final item = task("item-1", day, 600, 660);
      final draft = task(null, day, 840, 900);
      final created = draft.copyWith(id: "entry-1");
      final renamed = item.copyWith(title: "Renamed");
      final moved = item.copyWith(start: at(day, 720), end: at(day, 780));
      final writes =
          <
            String,
            (
              Future<Object?> Function(MemoryCalendarStore<String> store),
              Object?,
              List<CalendarEntry<String>>,
            )
          >{
            "create": (
              (store) {
                return store.create(draft);
              },
              created,
              <CalendarEntry<String>>[item, created],
            ),
            "update": (
              (store) {
                return store.update(renamed);
              },
              renamed,
              <CalendarEntry<String>>[renamed],
            ),
            "move": (
              (store) {
                return store.requestMove(moved);
              },
              moved,
              <CalendarEntry<String>>[moved],
            ),
            "delete": (
              (store) {
                return store.requestDelete("item-1");
              },
              null,
              <CalendarEntry<String>>[],
            ),
          };
      for (final MapEntry(key: name, value: (write, completed, held))
          in writes.entries) {
        const thrown = HostFailure();
        final events = <String>[];
        final reported = <Object>[];
        final store = MemoryCalendarStore<String>(
          entries: <CalendarEntry<String>>[item],
          onChanged: (old, entry) {
            events.add("changed");
            throw thrown;
          },
        );
        store.addListener(() {
          events.add("notified");
        });
        final onError = FlutterError.onError;
        FlutterError.onError = (details) {
          events.add("reported");
          reported.add(details.exception);
        };
        final Object? outcome;
        try {
          outcome = await outcomeOf(write(store));
        } finally {
          FlutterError.onError = onError;
        }
        expect(outcome, completed, reason: name);
        expect(store.entries, unorderedEquals(held), reason: name);
        expect(events, <String>[
          "notified",
          "changed",
          "reported",
        ], reason: name);
        expect(reported, <Object>[same(thrown)], reason: name);
      }
    },
  );

  test("MS13 under hours of 08:00 to 18:00 a create of a timed entry from "
      "Tuesday's start to Wednesday's is refused for both its times", () async {
    final recorder = Recorder();
    final store = recorder.store(hours: CalendarDayHours(480, 1080));
    final tuesday = DateTime(2026, 4, 21);
    final created = errorOf(
      store.create(task(null, tuesday, 0, 0, dayCount: 2)),
    );
    await pumpEventQueue();
    expect(
      created(),
      isA<CalendarHoursException>()
          .having((error) => error.startOutside, "startOutside", isTrue)
          .having((error) => error.endOutside, "endOutside", isTrue),
    );
    expect(store.entriesOn(tuesday), isEmpty);
  });

  test("MS14 under hours of 08:00 to 18:00 a create of an all-day entry "
      "over Tuesday is stored and answered all-day", () async {
    final recorder = Recorder();
    final store = recorder.store(hours: CalendarDayHours(480, 1080));
    final tuesday = DateTime(2026, 4, 21);
    final created = await store.create(
      task(null, tuesday, 0, 0, dayCount: 2, isAllDay: true),
    );
    expect(created.isAllDay, isTrue);
    expect(created.start, tuesday);
    expect(created.end, DateTime(2026, 4, 22));
    expect(store.storedEntry(created.id!), created);
  });

  group("time zones", () {
    setUpAll(ensureZones);

    final on = DateTime(2025, 7, 16, 10);
    final onDay = DateTime(2025, 7, 16);

    /// An entry of the given times.
    CalendarEntry<String> timesEntry(
      String? id,
      DateTime start,
      DateTime end, {
      bool isAllDay = false,
      String title = "Task",
    }) {
      return CalendarEntry<String>(
        id: id,
        start: start,
        end: end,
        title: title,
        color: taskColor,
        payload: "task",
        isAllDay: isAllDay,
      );
    }

    /// [time] as a plain local time, at its instant.
    DateTime plainOf(DateTime time) {
      return DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch);
    }

    void expectInZone(DateTime time, tz.Location zone, DateTime instant) {
      expect(time, isA<tz.TZDateTime>());
      expect((time as tz.TZDateTime).location, zone);
      expect(time.isAtSameMomentAs(instant), isTrue);
    }

    void expectEntryInZone(
      CalendarEntry<String> entry,
      tz.Location zone,
      DateTime start,
      DateTime end,
    ) {
      expectInZone(entry.start, zone, start);
      expectInZone(entry.end, zone, end);
    }

    Matcher argumentNamed(String name) {
      return throwsA(
        isA<ArgumentError>().having(
          (error) {
            return error.name;
          },
          "name",
          name,
        ),
      );
    }

    test("MZ1 tz.UTC and Etc/UTC can each be supplied", () {
      for (final zone in <tz.Location>[tz.UTC, tz.getLocation("Etc/UTC")]) {
        final entry = task("a", onDay, 600, 660);
        final store = memoryStoreIn<String>(
          zone,
          entries: <CalendarEntry<String>>[entry],
        );
        addTearDown(store.dispose);
        expect(zoneOfStore(store), zone);
        final stored = store.storedEntry("a")!;
        expectEntryInZone(stored, zone, entry.start, entry.end);
        expect(
          store
              .entriesOn(
                DateTime.utc(
                  stored.start.year,
                  stored.start.month,
                  stored.start.day,
                ),
              )
              .map((shown) {
                return shown.id;
              }),
          <String>["a"],
        );
      }
    });

    test("MZ2 the memory store files on the zone's civil day", () {
      final zone = zoneFarFromDevice(on);
      final entry = task("a", onDay, 600, 660);
      final store = memoryStoreIn<String>(
        zone,
        entries: <CalendarEntry<String>>[entry],
      );
      addTearDown(store.dispose);
      final zoned = tz.TZDateTime.from(on, zone);
      final zoneDay = DateTime(zoned.year, zoned.month, zoned.day);
      // Setup sanity: the zone's civil day is another than the device's.
      expect(
        CalendarDates.dayNumber(zoneDay),
        isNot(CalendarDates.dayNumber(onDay)),
      );
      expect(
        store.entriesOn(zoneDay).map((shown) {
          return shown.id;
        }),
        <String>["a"],
      );
      expect(store.entriesOn(onDay), isEmpty);
      expect(store.dayHasShownEntries(zoneDay), isTrue);
      expect(store.dayHasShownEntries(onDay), isFalse);
      expect(
        store.entriesBetween(zoneDay, zoneDay).map((shown) {
          return shown.id;
        }),
        <String>["a"],
      );
    });

    test("MZ3 timed entries read back on the zone's clock with their "
        "instants", () async {
      final zone = zoneFarFromDevice(on);
      final other = tz.getLocation("Asia/Tokyo");
      final start = on;
      final end = on.add(const Duration(hours: 1));
      final zoneDay = DateTime(
        tz.TZDateTime.from(on, zone).year,
        tz.TZDateTime.from(on, zone).month,
        tz.TZDateTime.from(on, zone).day,
      );
      final forms = <String, (DateTime, DateTime)>{
        "plain": (start, end),
        "same zone": (
          tz.TZDateTime.from(start, zone),
          tz.TZDateTime.from(end, zone),
        ),
        "other zone": (
          tz.TZDateTime.from(start, other),
          tz.TZDateTime.from(end, other),
        ),
      };
      for (final MapEntry(key: form, value: times) in forms.entries) {
        printOnFailure(form);
        final changes = <(CalendarEntry<String>?, CalendarEntry<String>?)>[];
        final store = memoryStoreIn<String>(
          zone,
          entries: <CalendarEntry<String>>[
            timesEntry("held", times.$1, times.$2),
          ],
          onChanged: (old, entry) {
            changes.add((old, entry));
          },
        );
        addTearDown(store.dispose);
        expectEntryInZone(store.storedEntry("held")!, zone, start, end);
        expectEntryInZone(
          store.entriesOn(zoneDay).single.entry,
          zone,
          start,
          end,
        );
        expectEntryInZone(
          store.entriesBetween(zoneDay, zoneDay).single.entry,
          zone,
          start,
          end,
        );
        expectEntryInZone(store.entries.single, zone, start, end);

        final created = await store.create(
          timesEntry("new", times.$1, times.$2),
        );
        expectEntryInZone(created, zone, start, end);
        expectEntryInZone(changes.last.$2!, zone, start, end);
        final updated = await store.update(
          timesEntry("held", times.$1, times.$2, title: "Updated"),
        );
        expectEntryInZone(updated, zone, start, end);
        expectEntryInZone(changes.last.$2!, zone, start, end);
        final moved = await store.requestMove(
          timesEntry("new", times.$1, times.$2, title: "Moved"),
        );
        expectEntryInZone(moved, zone, start, end);
        expectEntryInZone(changes.last.$2!, zone, start, end);
      }
    });

    test(
      "MZ4 an all-day entry over Havana's 2025-11-02 stays on that date",
      () {
        final havana = tz.getLocation("America/Havana");
        final far = zoneFarFromDevice(on);
        CalendarEntry<String> dayEntry(
          String id,
          DateTime first,
          DateTime end,
        ) {
          return timesEntry(id, first, end, isAllDay: true);
        }

        final november = dayEntry(
          "november",
          DateTime(2025, 11, 2),
          DateTime(2025, 11, 3),
        );
        final marchStart = dayEntry(
          "march-start",
          DateTime(2025, 3, 9),
          DateTime(2025, 3, 10),
        );
        final marchEnd = dayEntry(
          "march-end",
          DateTime(2025, 3, 8),
          DateTime(2025, 3, 9),
        );
        void expectDates(MemoryCalendarStore<String> store) {
          final held = store.storedEntry("november")!;
          expect(held.start.year, 2025);
          expect(held.start.month, 11);
          expect(held.start.day, 2);
          expect(held.isAllDay, isTrue);
          expect(
            store.entriesOn(DateTime(2025, 11, 2)).map((shown) {
              return shown.id;
            }),
            <String>["november"],
          );
          expect(store.entriesOn(DateTime(2025, 11, 3)), isEmpty);
          final startsOn = store.storedEntry("march-start")!;
          expect(startsOn.start.day, 9);
          expect(startsOn.start.month, 3);
          expect(startsOn.end.day, 10);
          final endsOn = store.storedEntry("march-end")!;
          expect(endsOn.start.day, 8);
          expect(endsOn.end.day, 9);
          expect(endsOn.end.month, 3);
          expect(
            store.entriesOn(DateTime(2025, 3, 8)).map((shown) {
              return shown.id;
            }),
            <String>["march-end"],
          );
          expect(
            store.entriesOn(DateTime(2025, 3, 9)).map((shown) {
              return shown.id;
            }),
            <String>["march-start"],
          );
        }

        for (final zone in <tz.Location?>[null, havana, far]) {
          final store = memoryStoreIn<String>(
            zone,
            entries: <CalendarEntry<String>>[november, marchStart, marchEnd],
          );
          addTearDown(store.dispose);
          expectDates(store);
          for (final next in <tz.Location?>[far, havana, null]) {
            if (next == zoneOfStore(store)) {
              continue;
            }
            setStoreZone(store, next);
            expectDates(store);
          }
        }
      },
    );

    test("MZ5 hours are on the zone's clock", () async {
      final zone = zoneFarFromDevice(on);
      final hours = CalendarDayHours(9 * 60, 17 * 60);
      final zoned = tz.TZDateTime.from(on, zone);
      tz.TZDateTime wall(int hour) {
        return tz.TZDateTime(zone, zoned.year, zoned.month, zoned.day, hour);
      }

      final held = timesEntry("held", wall(20), wall(21));
      final store = memoryStoreIn<String>(
        zone,
        entries: <CalendarEntry<String>>[held],
        hours: hours,
      );
      addTearDown(store.dispose);
      final accepted = await store.create(timesEntry("in", wall(10), wall(11)));
      expect(accepted.id, "in");
      await expectLater(
        store.create(timesEntry("out", wall(20), wall(21))),
        throwsA(isA<CalendarHoursException>()),
      );
      // A time the hours hold only as the zone's clock reads it: the device's
      // clock reads it outside them. (A device exactly 24 hours from the zone
      // reads the same hours, so no such time exists there.)
      final hoursOnlyInZone = <int>[
        for (var hour = 9; hour < 16; hour++)
          if (!hours.holdsTimes(
            plainOf(wall(hour)),
            plainOf(wall(hour + 1)),
            isAllDay: false,
          ))
            hour,
      ];
      if (hoursOnlyInZone.isNotEmpty) {
        final hour = hoursOnlyInZone.first;
        final created = await store.create(
          timesEntry("zone-only", wall(hour), wall(hour + 1)),
        );
        expect(created.id, "zone-only");
      }
      // The zone's clock reads no hours value at any other wall time: the
      // plain instants of the held entry keep its times, not refused.
      final updated = await store.update(
        timesEntry(
          "held",
          plainOf(wall(20)),
          plainOf(wall(21)),
          title: "Renamed",
        ),
      );
      expect(updated.title, "Renamed");
    });

    test("MZ6 a zone change notifies once and refiles; an == zone notifies "
        "nothing", () {
      final far = zoneFarFromDevice(on);
      final etc = tz.getLocation("Etc/UTC");
      // Setup sanity: the equal zone is another instance.
      expect(etc, tz.UTC);
      expect(identical(etc, tz.UTC), isFalse);
      final entry = task("a", onDay, 600, 660);
      final store = memoryStoreIn<String>(
        null,
        entries: <CalendarEntry<String>>[entry],
      );
      addTearDown(store.dispose);
      var notifies = 0;
      store.addListener(() {
        notifies++;
      });
      DateTime dayIn(tz.Location zone) {
        final time = tz.TZDateTime.from(entry.start, zone);
        return DateTime(time.year, time.month, time.day);
      }

      setStoreZone(store, far);
      expect(notifies, 1);
      expect(zoneOfStore(store), far);
      expect(
        store.entriesOn(dayIn(far)).map((shown) {
          return shown.id;
        }),
        <String>["a"],
      );
      expectEntryInZone(store.storedEntry("a")!, far, entry.start, entry.end);

      setStoreZone(store, tz.UTC);
      expect(notifies, 2);
      expectEntryInZone(
        store.storedEntry("a")!,
        tz.UTC,
        entry.start,
        entry.end,
      );

      setStoreZone(store, etc);
      expect(notifies, 2);

      setStoreZone(store, null);
      expect(notifies, 3);
      expect(zoneOfStore(store), isNull);
      final back = store.storedEntry("a")!;
      expect(back.start, isNot(isA<tz.TZDateTime>()));
      expect(back.start.isUtc, isFalse);
      expect(back.start.isAtSameMomentAs(entry.start), isTrue);
      expect(
        store.entriesOn(onDay).map((shown) {
          return shown.id;
        }),
        <String>["a"],
      );
    });

    test(
      "MZ7 a time the zone cannot represent fails only that operation",
      () async {
        final monrovia = tz.getLocation("Africa/Monrovia");
        final apia = tz.getLocation("Pacific/Apia");
        final plainTimed = task("bad", DateTime(1971, 6, 1), 600, 660);
        final zonedTimed = timesEntry(
          "bad",
          tz.TZDateTime(monrovia, 1971, 6, 1, 10),
          tz.TZDateTime(monrovia, 1971, 6, 1, 11),
        );
        final plainAllDay = timesEntry(
          "bad",
          DateTime(1971, 6, 1),
          DateTime(1971, 6, 2),
          isAllDay: true,
        );
        final zonedAllDay = timesEntry(
          "bad",
          tz.TZDateTime(monrovia, 1971, 6, 1),
          tz.TZDateTime(monrovia, 1971, 6, 2),
          isAllDay: true,
        );
        final startsOnSkip = timesEntry(
          "bad",
          DateTime(2011, 12, 30),
          DateTime(2011, 12, 31),
          isAllDay: true,
        );
        final endsOnSkip = timesEntry(
          "bad",
          DateTime(2011, 12, 29),
          DateTime(2011, 12, 30),
          isAllDay: true,
        );
        final cases = <(tz.Location, CalendarEntry<String>, String, bool)>[
          (monrovia, plainTimed, "start", true),
          (monrovia, zonedTimed, "start", false),
          (monrovia, plainAllDay, "start", true),
          (monrovia, zonedAllDay, "start", false),
          (apia, startsOnSkip, "start", true),
          (apia, endsOnSkip, "end", true),
        ];
        final good = task("good", DateTime(2020, 6, 1), 600, 660);
        for (final (zone, bad, name, plain) in cases) {
          expect(() {
            return memoryStoreIn<String>(
              zone,
              entries: <CalendarEntry<String>>[bad],
            );
          }, argumentNamed(name));

          final store = memoryStoreIn<String>(
            zone,
            entries: <CalendarEntry<String>>[good],
          );
          addTearDown(store.dispose);
          var notifies = 0;
          store.addListener(() {
            notifies++;
          });
          final before = store.storedEntry("good");
          expect(() {
            store.entries = <CalendarEntry<String>>[bad];
          }, argumentNamed(name));
          await expectLater(store.create(bad), argumentNamed(name));
          await expectLater(
            store.update(bad.copyWith(id: "good")),
            argumentNamed(name),
          );
          expect(store.storedEntry("bad"), isNull);
          expect(store.storedEntry("good"), before);
          expect(notifies, 0);

          // Only a plain form can be held by another store to change zone.
          if (plain) {
            final other = memoryStoreIn<String>(
              null,
              entries: <CalendarEntry<String>>[bad],
            );
            addTearDown(other.dispose);
            var otherNotifies = 0;
            other.addListener(() {
              otherNotifies++;
            });
            expect(() {
              setStoreZone(other, zone);
            }, argumentNamed(name));
            expect(zoneOfStore(other), isNull);
            expect(other.storedEntry("bad"), bad);
            expect(otherNotifies, 0);
          }
        }
      },
    );

    test("MZ8 filing and a zone change ask a fixed number per entry", () {
      List<CalendarEntry<String>> timed(int count) {
        return <CalendarEntry<String>>[
          for (var i = 0; i < count; i++)
            task(
              "t$i",
              DateTime(2025, 6, 1 + i % 60),
              600 + i % 120,
              720 + i % 120,
            ),
        ];
      }

      List<CalendarEntry<String>> allDay(int count) {
        return <CalendarEntry<String>>[
          for (var i = 0; i < count; i++)
            timesEntry(
              "d$i",
              DateTime(2025, 6, 1 + i % 60),
              DateTime(2025, 6, 2 + i % 60),
              isAllDay: true,
            ),
        ];
      }

      final zone = CountingLocation(tz.getLocation("America/Havana"));
      final next = CountingLocation(tz.getLocation("Asia/Tokyo"));
      for (final (entries, cost) in <(List<CalendarEntry<String>>, int)>[
        (timed(5000), 3),
        (allDay(5000), 7),
      ]) {
        zone.lookups = 0;
        final store = memoryStoreIn<String>(zone, entries: entries);
        addTearDown(store.dispose);
        expect(zone.lookups, cost * entries.length);

        zone.lookups = 0;
        store.entriesOn(DateTime(2025, 6, 10));
        store.entriesBetween(DateTime(2025, 6, 1), DateTime(2025, 7, 30));
        expect(zone.lookups, 0);

        next.lookups = 0;
        setStoreZone(store, next);
        expect(next.lookups, cost * entries.length);

        next.lookups = 0;
        store.entriesOn(DateTime(2025, 6, 10));
        store.entriesBetween(DateTime(2025, 6, 1), DateTime(2025, 7, 30));
        expect(next.lookups, 0);

        setStoreZone(store, zone);
      }
    });

    test("MZ9 a store with no zone keeps the device clock", () {
      final plain = task("plain", onDay, 600, 660);
      final zone = zoneFarFromDevice(on);
      final zonedInput = timesEntry(
        "zoned",
        tz.TZDateTime.from(plain.start, zone),
        tz.TZDateTime.from(plain.end, zone),
      );
      final store = memoryStoreIn<String>(
        null,
        entries: <CalendarEntry<String>>[plain, zonedInput],
      );
      addTearDown(store.dispose);
      expect(zoneOfStore(store), isNull);
      expect(identical(store.storedEntry("plain"), plain), isTrue);
      final held = store.storedEntry("zoned")!;
      expect(held.start, isNot(isA<tz.TZDateTime>()));
      expect(held.start.isUtc, isFalse);
      expect(held.start.isAtSameMomentAs(plain.start), isTrue);
      expect(held.end.isAtSameMomentAs(plain.end), isTrue);
      expect(
        store.entriesOn(onDay).map((shown) {
          return shown.id;
        }),
        <String>["plain", "zoned"],
      );
      final zoned = tz.TZDateTime.from(on, zone);
      expect(
        store.entriesOn(DateTime(zoned.year, zoned.month, zoned.day)),
        isEmpty,
      );
    });
  });
}
