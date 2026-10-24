/// The caching store's day cache, its shown range and the per-entry lock,
/// over a fake data source whose calls the tests complete by hand.
library;

import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

/// The error a test fails a data-source call with.
class SourceFailure implements Exception {
  const SourceFailure(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

enum SourceMethod { read, create, replace, delete }

/// One call the fake data source received, completed by the test.
class FakeCall {
  FakeCall(this.method, {this.id, this.first, this.last, this.entry});

  final SourceMethod method;
  final String? id;
  final DateTime? first;
  final DateTime? last;
  final CalendarEntry<String>? entry;
  final Completer<Object?> completer = Completer<Object?>();

  void succeed([Object? value]) {
    completer.complete(value);
  }

  /// Fails the call with a new [SourceFailure] and answers it.
  SourceFailure fail([String message = "Offline."]) {
    final failure = SourceFailure(message);
    completer.completeError(failure);
    return failure;
  }
}

class FakeDataSource implements CalendarDataSource<String> {
  final List<FakeCall> calls = <FakeCall>[];

  /// What `read`, `replace` and `delete` throw, instead of answering a
  /// future, while set.
  Object? thrown;

  Future<R> _add<R>(FakeCall call) {
    calls.add(call);
    return call.completer.future.then((value) {
      return value as R;
    });
  }

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final error = thrown;
    if (error != null) {
      throw error;
    }
    return _add(FakeCall(SourceMethod.read, first: first, last: last));
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    return _add(FakeCall(SourceMethod.create, entry: draft));
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    final error = thrown;
    if (error != null) {
      throw error;
    }
    return _add(FakeCall(SourceMethod.replace, id: entry.id, entry: entry));
  }

  @override
  Future<void> delete(String id) {
    final error = thrown;
    if (error != null) {
      throw error;
    }
    return _add(FakeCall(SourceMethod.delete, id: id));
  }
}

/// A store over a fake data source, recording what reaches
/// `onWriteFailed` and how often it notifies.
class Harness {
  Harness() {
    store = CachingCalendarStore<String>(
      dataSource: source,
      onWriteFailed: (failure) {
        failures.add(failure);
      },
    );
    store.addListener(() {
      notifications++;
    });
  }

  final FakeDataSource source = FakeDataSource();
  late final CachingCalendarStore<String> store;
  final List<CalendarWriteFailure> failures = <CalendarWriteFailure>[];
  int notifications = 0;

  FakeCall get lastCall {
    return source.calls.last;
  }
}

/// April 2026's grid, Monday first.
final DateTime aprilFirst = DateTime(2026, 3, 30);
final DateTime aprilLast = DateTime(2026, 5, 3);

/// May 2026's grid.
final DateTime mayFirst = DateTime(2026, 4, 27);
final DateTime mayLast = DateTime(2026, 5, 31);

/// The week of Monday 2026-04-20.
final DateTime weekFirst = DateTime(2026, 4, 20);
final DateTime weekLast = DateTime(2026, 4, 26);

const Color taskColor = Color(0xFF3060C0);

/// [minute] minutes after [day]'s midnight.
DateTime at(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, 0, minute);
}

/// An entry from [start] minutes after [day]'s midnight to [end] minutes
/// after the midnight of its [dayCount]th day.
CalendarEntry<String> task(
  String id,
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

/// An entry no store holds yet, from [start] minutes after [day]'s
/// midnight to [end] minutes after the midnight of its [dayCount]th day.
CalendarEntry<String> draft(
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
  String title = "Created",
}) {
  return CalendarEntry<String>(
    start: at(day, start),
    end: at(DateTime(day.year, day.month, day.day + dayCount - 1), end),
    title: title,
    color: taskColor,
    payload: "task",
  );
}

/// [entry] from [start] to [end] minutes after the midnight of the day it
/// starts on.
CalendarEntry<String> retimed(CalendarEntry<String> entry, int start, int end) {
  return entry.copyWith(
    start: at(entry.start, start),
    end: at(entry.start, end),
  );
}

/// [entry] moved to start on [day], keeping its times of day and the days
/// it covers.
CalendarEntry<String> onDay(CalendarEntry<String> entry, DateTime day) {
  final shift = dayNumber(day) - dayNumber(entry.start);
  DateTime shifted(DateTime time) {
    return DateTime(
      time.year,
      time.month,
      time.day + shift,
      time.hour,
      time.minute,
    );
  }

  return entry.copyWith(start: shifted(entry.start), end: shifted(entry.end));
}

/// Lets the futures the fake data source's completions resolve run.
Future<void> settle() {
  return pumpEventQueue();
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

List<String> idsOn(CalendarStore<String> store, DateTime day) {
  return <String>[for (final entry in store.entriesOn(day)) entry.id];
}

/// A failure of the write on [id] whose error [error] matches.
Matcher failureOf(String id, Object? error) {
  return isA<CalendarWriteFailure>()
      .having((failure) => failure.id, "id", id)
      .having((failure) => failure.error, "error", error);
}

Matcher pendingRefusal(String id) {
  return isA<CalendarWritePendingException>().having(
    (error) => error.id,
    "id",
    id,
  );
}

Matcher overlapRefusal(List<String> ids) {
  return isA<CalendarEntryOverlapException>().having(
    (error) => error.conflictingIds,
    "conflictingIds",
    ids,
  );
}

/// A refusal under the hours 08:00 to 18:00 with only the start, or only
/// the end, outside them.
Matcher hoursRefusal({required bool startOutside}) {
  return isA<CalendarHoursException>()
      .having((error) => error.hours, "hours", const DayHours(480, 1080))
      .having((error) => error.startOutside, "startOutside", startOutside)
      .having((error) => error.endOutside, "endOutside", !startOutside);
}

/// A data source that answers `read` and `replace` within the call, through
/// a [SynchronousFuture], or fails a read through an ordinary future while
/// [readError] is set.
class SyncSource implements CalendarDataSource<String> {
  List<CalendarEntry<String>> entries = <CalendarEntry<String>>[];

  Object? readError;

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final error = readError;
    if (error != null) {
      return Future<List<CalendarEntry<String>>>.error(error);
    }
    return SynchronousFuture<List<CalendarEntry<String>>>(
      List<CalendarEntry<String>>.of(entries),
    );
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    return SynchronousFuture<CalendarEntry<String>>(entry);
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}

void main() {
  test("M1 a read range sends nothing", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(aprilFirst, aprilLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    store.show(weekFirst, weekLast);
    expect(harness.source.calls, hasLength(1));
    expect(store.status, CalendarLoadStatus.ready);

    store.show(aprilFirst, aprilLast);
    expect(harness.source.calls, hasLength(1));
    expect(store.status, CalendarLoadStatus.ready);
  });

  test("M2 a late read fills only unread days, by the cached times", () async {
    final harness = Harness();
    final store = harness.store;
    final moving = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final multi = task(
      "item-2",
      DateTime(2026, 4, 25),
      1140,
      1200,
      dayCount: 3,
    );
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[moving, multi]);
    await settle();
    store.show(aprilFirst, aprilLast);
    expect(harness.source.calls, hasLength(2));
    final april = harness.lastCall;

    // Three writes the data source confirms before April's read answers.
    final moved = moving.copyWith(
      start: DateTime(2026, 4, 22, 14),
      end: DateTime(2026, 4, 22, 15),
    );
    store.requestMove(moved);
    harness.lastCall.succeed(moved);
    await settle();
    // Monday 19:00 to Wednesday 12:00, clear of the moved entry.
    final multiMoved = multi.copyWith(
      start: DateTime(2026, 4, 20, 19),
      end: DateTime(2026, 4, 22, 12),
    );
    store.requestMove(multiMoved);
    harness.lastCall.succeed(multiMoved);
    await settle();
    final created = draft(DateTime(2026, 4, 25), 1260, 1320, dayCount: 3);
    final creating = store.create(created);
    harness.lastCall.succeed(created.copyWith(id: "item-3"));
    await creating;

    // The read answers with the first two where they were when it was
    // sent, and without the third.
    april.succeed(<CalendarEntry<String>>[moving, multi]);
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
    final onWednesday = store.entriesOn(DateTime(2026, 4, 22));
    expect(
      <CalendarEntry<String>>[
        for (final entry in onWednesday)
          if (entry.id == "item-1") entry.entry,
      ],
      <CalendarEntry<String>>[moved],
    );
    expect(idsOn(store, DateTime(2026, 4, 21)), isNot(contains("item-1")));
    final onMonday = idsOn(store, DateTime(2026, 4, 27));
    expect(onMonday, isNot(contains("item-2")));
    expect(onMonday, contains("item-3"));
  });

  test(
    "M3 a read the shown range does not wait on changes no shown state",
    () async {
      final failing = Harness();
      failing.store.show(aprilFirst, aprilLast);
      final april = failing.lastCall;
      failing.store.show(mayFirst, mayLast);
      expect(failing.source.calls, hasLength(2));
      april.fail();
      await settle();
      expect(failing.store.status, CalendarLoadStatus.loading);
      expect(failing.store.loadError, isNull);

      final filling = Harness();
      filling.store.show(aprilFirst, aprilLast);
      final read = filling.lastCall;
      filling.store.show(mayFirst, mayLast);
      read.succeed(<CalendarEntry<String>>[
        task("item-1", DateTime(2026, 4, 27), 600, 660),
      ]);
      await settle();
      expect(filling.store.status, CalendarLoadStatus.loading);
      expect(filling.store.dayHasShownEntries(DateTime(2026, 4, 27)), isFalse);
    },
  );

  test("M4 writes update the cache and the lock", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final other = task("item-2", DateTime(2026, 4, 22), 900, 960);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item, other]);
    await settle();

    // A move that fails.
    final requested = onDay(item, DateTime(2026, 4, 23));
    store.requestMove(requested);
    final failing = harness.lastCall;
    expect(failing.method, SourceMethod.replace);
    expect(store.entriesOn(DateTime(2026, 4, 23)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(requested, pending: true),
    ]);
    expect(idsOn(store, DateTime(2026, 4, 21)), isEmpty);
    expect(store.isPending("item-1"), isTrue);

    // Every write on the locked id is refused without a call or a throw.
    final calls = harness.source.calls.length;
    store.requestMove(onDay(item, DateTime(2026, 4, 24)));
    expect(harness.failures, <Matcher>[
      failureOf("item-1", pendingRefusal("item-1")),
    ]);
    final refusal = errorOf(store.update(item.copyWith(title: "Renamed")));
    store.requestDelete("item-1");
    await settle();
    expect(refusal(), pendingRefusal("item-1"));
    expect(harness.failures, <Matcher>[
      failureOf("item-1", pendingRefusal("item-1")),
      failureOf("item-1", pendingRefusal("item-1")),
    ]);
    expect(harness.source.calls, hasLength(calls));

    final movingFailed = failing.fail("Moving failed.");
    await settle();
    expect(store.entriesOn(DateTime(2026, 4, 21)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(item, pending: false),
    ]);
    expect(store.isPending("item-1"), isFalse);
    expect(harness.failures.last, failureOf("item-1", same(movingFailed)));

    // A move that succeeds.
    store.requestMove(requested);
    harness.lastCall.succeed(requested);
    await settle();
    expect(store.storedEntry("item-1"), requested);
    expect(store.isPending("item-1"), isFalse);

    // A form edit shows the stored entry until the data source answers,
    // and its failure reaches the caller alone.
    final failuresBefore = harness.failures.length;
    final edit = errorOf(store.update(other.copyWith(title: "Renamed")));
    expect(store.entriesOn(DateTime(2026, 4, 22)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(other, pending: true),
    ]);
    final savingFailed = harness.lastCall.fail("Saving failed.");
    await settle();
    expect(edit(), same(savingFailed));
    expect(store.isPending("item-2"), isFalse);
    expect(harness.failures, hasLength(failuresBefore));

    // A confirmed create and delete add and remove.
    final created = draft(DateTime(2026, 4, 24), 600, 660);
    final creating = store.create(created);
    harness.lastCall.succeed(created.copyWith(id: "item-3"));
    await creating;
    expect(idsOn(store, DateTime(2026, 4, 24)), <String>["item-3"]);
    store.requestDelete("item-3");
    harness.lastCall.succeed();
    await settle();
    expect(idsOn(store, DateTime(2026, 4, 24)), isEmpty);
  });

  test("M4 a move that meets an entry on a read day sends nothing", () async {
    final harness = Harness();
    final store = harness.store;
    // From Saturday 19:00 to Sunday 01:00.
    final multi = task("item-1", DateTime(2026, 4, 25), 1140, 1500);
    final single = task("item-2", DateTime(2026, 4, 27), 1020, 1080);
    final morning = task("item-3", DateTime(2026, 4, 26), 600, 660);
    store.show(DateTime(2026, 4, 25), DateTime(2026, 4, 27));
    harness.lastCall.succeed(<CalendarEntry<String>>[multi, single, morning]);
    await settle();
    final calls = harness.source.calls.length;

    // Monday 13:00 to 19:00 meets Monday's entry from 17:00.
    store.requestMove(
      multi.copyWith(
        start: DateTime(2026, 4, 27, 13),
        end: DateTime(2026, 4, 27, 19),
      ),
    );
    expect(harness.source.calls, hasLength(calls));
    expect(store.isPending("item-1"), isFalse);
    expect(harness.failures, <Matcher>[
      failureOf("item-1", overlapRefusal(<String>["item-2"])),
    ]);

    // Sunday 19:00 to Monday 01:00 meets neither.
    final clear = multi.copyWith(
      start: DateTime(2026, 4, 26, 19),
      end: DateTime(2026, 4, 27, 1),
    );
    store.requestMove(clear);
    expect(harness.source.calls, hasLength(calls + 1));
    harness.lastCall.succeed(clear);
    await settle();

    // Two single-day entries are kept apart as well.
    final reported = harness.failures.length;
    store.requestMove(
      single.copyWith(
        start: DateTime(2026, 4, 26, 10, 30),
        end: DateTime(2026, 4, 26, 11, 30),
      ),
    );
    expect(harness.source.calls, hasLength(calls + 1));
    expect(store.isPending("item-2"), isFalse);
    expect(harness.failures.sublist(reported), <Matcher>[
      failureOf("item-2", overlapRefusal(<String>["item-3"])),
    ]);
  });

  test("M5 a multi-day entry shows on each day it covers", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(aprilFirst, aprilLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[
      task("item-1", DateTime(2026, 4, 28), 600, 660, dayCount: 3),
    ]);
    await settle();
    for (final day in <int>[28, 29, 30]) {
      expect(idsOn(store, DateTime(2026, 4, day)), <String>[
        "item-1",
      ], reason: "2026-04-$day");
      expect(
        store.dayHasShownEntries(DateTime(2026, 4, day)),
        isTrue,
        reason: "2026-04-$day",
      );
    }
    expect(idsOn(store, DateTime(2026, 4, 27)), isEmpty);
    expect(idsOn(store, DateTime(2026, 5, 1)), isEmpty);
  });

  test("M6 the shown range follows the read it waits on", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final week = harness.lastCall;
    store.show(aprilFirst, aprilLast);
    final april = harness.lastCall;
    expect(harness.source.calls, hasLength(2));
    store.show(weekFirst, weekLast);
    expect(harness.source.calls, hasLength(2));

    april.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.loading);
    week.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
    expect(store.loadError, isNull);
    store.retry();
    expect(harness.source.calls, hasLength(2));
    expect(store.status, CalendarLoadStatus.ready);

    final fresh = Harness();
    fresh.store.show(aprilFirst, aprilLast);
    fresh.lastCall.fail();
    await settle();
    expect(fresh.store.status, CalendarLoadStatus.failed);
    final notifications = fresh.notifications;
    fresh.store.show(aprilFirst, aprilLast);
    expect(fresh.source.calls, hasLength(1));
    expect(fresh.store.status, CalendarLoadStatus.failed);
    expect(fresh.notifications, notifications);
  });

  test("M7 a completion after dispose calls neither notifyListeners nor "
      "onWriteFailed", () async {
    // A notifyListeners after dispose throws in debug, from the callback
    // that completes the call, so it lands here.
    final errors = <Object>[];
    final done = Completer<Harness>();
    runZonedGuarded(
      () async {
        final harness = Harness();
        final store = harness.store;
        final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
        store.show(weekFirst, weekLast);
        harness.lastCall.succeed(<CalendarEntry<String>>[item]);
        await settle();
        store.show(aprilFirst, aprilLast);
        final read = harness.lastCall;
        store.requestMove(onDay(item, DateTime(2026, 4, 22)));
        final write = harness.lastCall;

        store.dispose();
        read.succeed(<CalendarEntry<String>>[]);
        write.fail();
        await settle();
        done.complete(harness);
      },
      (error, stackTrace) {
        errors.add(error);
      },
    );
    final harness = await done.future;
    expect(errors, isEmpty);
    expect(harness.failures, isEmpty);
  });

  test("M8 the hours hold a new entry and a change of an entry's days or "
      "minutes", () async {
    final harness = Harness();
    final store = harness.store;
    final early = task("item-1", DateTime(2026, 4, 21), 420, 540);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[early]);
    await settle();
    store.hours = const DayHours(480, 1080);
    final calls = harness.source.calls.length;

    final created = errorOf(
      store.create(draft(DateTime(2026, 4, 22), 1050, 1110, title: "Late")),
    );
    final moved = errorOf(
      store.update(
        early.copyWith(start: at(weekLast, 420), end: at(weekLast, 540)),
      ),
    );
    await settle();
    expect(created(), hoursRefusal(startOutside: false));
    expect(moved(), hoursRefusal(startOutside: true));
    expect(store.isPending("item-1"), isFalse);

    store.requestMove(retimed(early, 450, 510));
    expect(harness.failures, <Matcher>[
      failureOf("item-1", hoursRefusal(startOutside: true)),
    ]);
    expect(store.isPending("item-1"), isFalse);
    expect(harness.source.calls, hasLength(calls));

    // A write that keeps the stored days and minutes is not held to them.
    final renamed = store.update(early.copyWith(title: "Renamed"));
    expect(harness.source.calls, hasLength(calls + 1));
    harness.lastCall.succeed(early.copyWith(title: "Renamed"));
    await renamed;
    store.requestMove(retimed(early, 480, 600));
    expect(harness.source.calls, hasLength(calls + 2));
    expect(harness.lastCall.entry!.start, DateTime(2026, 4, 21, 8));
  });

  test("M9 isWithinShown holds for the days inside the shown range", () {
    final store = Harness().store;
    expect(store.isWithinShown(weekFirst, weekFirst), isFalse);

    store.show(weekFirst, weekLast);
    expect(store.isWithinShown(weekFirst, weekLast), isTrue);
    expect(
      store.isWithinShown(DateTime(2026, 4, 22), DateTime(2026, 4, 22)),
      isTrue,
    );
    expect(
      store.isWithinShown(DateTime(2026, 4, 19), DateTime(2026, 4, 21)),
      isFalse,
    );
    expect(
      store.isWithinShown(DateTime(2026, 4, 25), DateTime(2026, 4, 27)),
      isFalse,
    );
  });

  test("M10 a prefetch reads only the unread days, keeps the shown range "
      "and its status, and notifies once it marks days read", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    final notifications = harness.notifications;

    store.prefetch(weekFirst, weekLast);
    expect(harness.source.calls, hasLength(1));

    // Of April 23 to May 3, April 27 on are unread.
    store.prefetch(DateTime(2026, 4, 23), aprilLast);
    expect(harness.source.calls, hasLength(2));
    final read = harness.lastCall;
    expect((read.first, read.last), (DateTime(2026, 4, 27), aprilLast));
    // The read in flight covers these.
    store.prefetch(DateTime(2026, 4, 28), DateTime(2026, 4, 29));
    expect(harness.source.calls, hasLength(2));
    expect(store.status, CalendarLoadStatus.ready);
    expect(store.isShown(weekFirst, weekLast), isTrue);
    expect(harness.notifications, notifications);

    read.succeed(<CalendarEntry<String>>[
      task("item-1", DateTime(2026, 4, 28), 540, 600),
    ]);
    await settle();
    expect(harness.notifications, notifications + 1);
    expect(store.dayHasShownEntries(DateTime(2026, 4, 28)), isTrue);
    expect(store.dayHasShownEntries(DateTime(2026, 4, 29)), isFalse);

    // A failed one leaves its days unread and marks them failed, so the
    // next one sends again, which clears the mark.
    store.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    harness.lastCall.fail();
    await settle();
    expect(harness.notifications, notifications + 2);
    expect(store.isRead(DateTime(2026, 5, 4)), isFalse);
    expect(store.readFailed(DateTime(2026, 5, 4)), isTrue);
    expect(store.readFailed(DateTime(2026, 4, 28)), isFalse);
    store.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    expect(harness.source.calls, hasLength(4));
    expect(store.readFailed(DateTime(2026, 5, 4)), isFalse);
  });

  test("M11 a day is read once a read fills it, and a failed read of the "
      "shown range marks its days failed too", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    expect(store.isRead(weekFirst), isFalse);
    harness.lastCall.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    expect(store.readFailed(weekFirst), isTrue);

    store.retry();
    expect(store.readFailed(weekFirst), isFalse);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.isRead(weekFirst), isTrue);
    expect(store.readFailed(weekFirst), isFalse);
  });

  group("first free", () {
    final day = DateTime(2026, 4, 22);

    /// Shows [day] and completes its read with [entries].
    Future<CachingCalendarStore<String>> readDay(
      Harness harness,
      List<CalendarEntry<String>> entries,
    ) async {
      final store = harness.store;
      store.show(day, day);
      harness.lastCall.succeed(entries);
      await settle();
      expect(store.status, CalendarLoadStatus.ready);
      return store;
    }

    test("FF1 the first free range is the earliest slot that meets no shown "
        "entry", () async {
      final store = await readDay(Harness(), <CalendarEntry<String>>[
        task("item-1", day, 0, 60),
        task("item-2", day, 75, 120),
      ]);
      expect(store.firstFreeRange(day, slotMinutes: 15), (
        start: at(day, 60),
        end: at(day, 75),
      ));
    });

    test(
      "FF2 a day free only in the hours' last slot gets that slot",
      () async {
        final store = await readDay(Harness(), <CalendarEntry<String>>[
          task("item-1", day, 540, 705),
        ]);
        store.hours = const DayHours(540, 720);
        expect(store.firstFreeRange(day, slotMinutes: 15), (
          start: at(day, 705),
          end: at(day, 720),
        ));
      },
    );

    test("FF3 with no free start the range is the hours' first slot", () async {
      final store = await readDay(Harness(), <CalendarEntry<String>>[
        task("item-1", day, 0, 1439),
      ]);
      expect(store.firstFreeRange(day, slotMinutes: 15), (
        start: at(day, 0),
        end: at(day, 15),
      ));
    });

    test("FF4 a pending move counts where it shows", () async {
      final harness = Harness();
      final item = task("item-1", day, 60, 120);
      final store = await readDay(harness, <CalendarEntry<String>>[item]);
      // Sanity: the stored entry leaves the first slot free.
      expect(store.firstFreeRange(day, slotMinutes: 15), (
        start: at(day, 0),
        end: at(day, 15),
      ));

      final calls = harness.source.calls.length;
      store.requestMove(retimed(item, 0, 60));
      expect(harness.source.calls, hasLength(calls + 1));
      expect(store.isPending("item-1"), isTrue);
      expect(store.firstFreeRange(day, slotMinutes: 15), (
        start: at(day, 60),
        end: at(day, 75),
      ));
    });

    test("FF5 a search from a minute starts there, rounded up to the slots "
        "and no earlier than the hours, and with nothing free after it "
        "starts again at the hours' start", () async {
      final store = await readDay(Harness(), <CalendarEntry<String>>[
        task("item-1", day, 480, 540),
        task("item-2", day, 900, 960),
      ]);
      store.hours = const DayHours(480, 1200);
      expect(store.firstFreeRange(day, slotMinutes: 15, from: 840), (
        start: at(day, 840),
        end: at(day, 855),
      ));
      // 14:10 rounds up to 14:15.
      expect(store.firstFreeRange(day, slotMinutes: 15, from: 850), (
        start: at(day, 855),
        end: at(day, 870),
      ));
      // Each slot from 15:00 meets item-2 until it ends.
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
  });

  test("CS1 a confirmed write that changes only the payload shows the new "
      "payload", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    final before = store.entriesOn(DateTime(2026, 4, 21)).single;

    final done = item.copyWith(payload: "done");
    final updating = store.update(done);
    final notifications = harness.notifications;
    harness.lastCall.succeed(done);
    await updating;
    expect(harness.notifications, notifications + 1);
    final after = store.entriesOn(DateTime(2026, 4, 21)).single;
    expect(after.entry.payload, "done");
    expect(after.pending, isFalse);
    expect(after == before, isFalse);
  });

  group("CS2 the store holds the data source to its contract", () {
    final day = DateTime(2026, 4, 22);

    test("a read answering an entry with no id fails", () async {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[
        task("item-1", day, 600, 660),
        draft(day, 720, 780),
      ]);
      await settle();
      expect(store.status, CalendarLoadStatus.failed);
      expect(store.loadError, isA<StateError>());
      expect(store.isRead(day), isFalse);
      expect(store.readFailed(day), isTrue);
      expect(store.entriesOn(day), isEmpty);
    });

    test("a create answered with no id fails and files nothing", () async {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      final created = draft(day, 600, 660);
      final creating = errorOf(store.create(created));
      harness.lastCall.succeed(created);
      await settle();
      expect(creating(), isA<StateError>());
      expect(store.entriesOn(day), isEmpty);
    });

    test("a move answered under another id fails, and the entry shows as "
        "stored", () async {
      final harness = Harness();
      final store = harness.store;
      final item = task("item-1", day, 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      store.requestMove(retimed(item, 720, 780));
      harness.lastCall.succeed(retimed(item, 720, 780).copyWith(id: "item-9"));
      await settle();
      expect(harness.failures, <Matcher>[
        failureOf("item-1", isA<StateError>()),
      ]);
      expect(store.isPending("item-1"), isFalse);
      expect(store.entriesOn(day), <CalendarShownEntry<String>>[
        CalendarShownEntry<String>(item, pending: false),
      ]);
      expect(store.storedEntry("item-9"), isNull);
    });

    test("an update of an entry with no id fails and sends nothing", () async {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      final calls = harness.source.calls.length;
      final updating = errorOf(store.update(draft(day, 600, 660)));
      await settle();
      expect(updating(), isA<ArgumentError>());
      expect(harness.source.calls, hasLength(calls));
      expect(
        () => store.requestMove(draft(day, 600, 660)),
        throwsArgumentError,
      );
      expect(harness.source.calls, hasLength(calls));
    });

    test("a create answered after a read brought its entry and a move took "
        "it pending leaves the move pending", () async {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      final read = harness.lastCall;
      final created = draft(day, 600, 660);
      final creating = store.create(created);
      final create = harness.lastCall;
      final stored = created.copyWith(id: "item-5");
      read.succeed(<CalendarEntry<String>>[stored]);
      await settle();
      final requested = retimed(stored, 720, 780);
      store.requestMove(requested);
      expect(store.isPending("item-5"), isTrue);

      create.succeed(stored);
      await creating;
      expect(store.isPending("item-5"), isTrue);
      expect(store.entriesOn(day), <CalendarShownEntry<String>>[
        CalendarShownEntry<String>(requested, pending: true),
      ]);
      store.requestMove(retimed(stored, 900, 960));
      expect(harness.failures, <Matcher>[
        failureOf("item-5", pendingRefusal("item-5")),
      ]);
    });
  });

  test("CS3 a failed read's load error is the data source's error", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final error = harness.lastCall.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    expect(store.loadError, same(error));

    store.retry();
    expect(store.status, CalendarLoadStatus.loading);
    expect(store.loadError, isNull);
  });

  test(
    "CS4 a data source call that throws fails as its future would",
    () async {
      final harness = Harness();
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      final other = task("item-2", DateTime(2026, 4, 22), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item, other]);
      await settle();

      const thrown = SourceFailure("Thrown.");
      harness.source.thrown = thrown;
      expect(() => store.show(aprilFirst, aprilLast), returnsNormally);
      store.requestMove(retimed(item, 720, 780));
      store.requestDelete("item-2");
      await settle();
      expect(store.status, CalendarLoadStatus.failed);
      expect(store.loadError, same(thrown));
      expect(store.isRead(aprilFirst), isFalse);
      expect(harness.failures, <Matcher>[
        failureOf("item-1", same(thrown)),
        failureOf("item-2", same(thrown)),
      ]);
      expect(store.isPending("item-1"), isFalse);
      expect(store.isPending("item-2"), isFalse);
      expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);
      expect(idsOn(store, DateTime(2026, 4, 22)), <String>["item-2"]);
    },
  );

  test("CS5 a range merges each read day's entries and the pending ones, "
      "each once, in order", () async {
    final harness = Harness();
    final store = harness.store;
    // All-day from May 5 to May 7, sharing time with no entry.
    final three = task(
      "three",
      DateTime(2026, 5, 5),
      0,
      0,
      dayCount: 4,
      title: "Three",
    );
    final ten = task("ten", DateTime(2026, 5, 6), 600, 660, title: "Ten");
    final nine = task("nine", DateTime(2026, 5, 7), 540, 570, title: "Nine");
    store.show(DateTime(2026, 5, 6), DateTime(2026, 5, 7));
    harness.lastCall.succeed(<CalendarEntry<String>>[three, ten, nine]);
    await settle();
    expect(store.isRead(DateTime(2026, 5, 5)), isFalse);

    List<CalendarShownEntry<String>> range() {
      return store.entriesBetween(DateTime(2026, 5, 4), DateTime(2026, 5, 8));
    }

    expect(range(), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(three, pending: false),
      CalendarShownEntry<String>(ten, pending: false),
      CalendarShownEntry<String>(nine, pending: false),
    ]);

    final moved = ten.copyWith(
      start: DateTime(2026, 5, 7, 8),
      end: DateTime(2026, 5, 7, 9),
    );
    store.requestMove(moved);
    expect(store.isPending("ten"), isTrue);
    expect(range(), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(three, pending: false),
      CalendarShownEntry<String>(moved, pending: true),
      CalendarShownEntry<String>(nine, pending: false),
    ]);
    expect(store.entriesOn(DateTime(2026, 5, 7)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(three, pending: false),
      CalendarShownEntry<String>(moved, pending: true),
      CalendarShownEntry<String>(nine, pending: false),
    ]);

    store.update(nine.copyWith(title: "Nine o'clock"));
    expect(range(), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(three, pending: false),
      CalendarShownEntry<String>(moved, pending: true),
      CalendarShownEntry<String>(nine, pending: true),
    ]);
  });

  test("CS6 a data source answering within the call settles the store "
      "within the call", () async {
    final source = SyncSource();
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    source.entries = <CalendarEntry<String>>[item];
    final store = CachingCalendarStore<String>(dataSource: source);

    store.show(weekFirst, weekLast);
    expect(store.status, CalendarLoadStatus.ready);
    expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);

    source.readError = const SourceFailure("Offline.");
    store.show(aprilFirst, aprilLast);
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    source.readError = null;
    store.retry();
    expect(store.status, CalendarLoadStatus.ready);

    store.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    expect(store.isRead(DateTime(2026, 5, 4)), isTrue);

    final moved = retimed(item, 720, 780);
    store.requestMove(moved);
    expect(store.isPending("item-1"), isFalse);
    expect(store.storedEntry("item-1"), moved);
    store.dispose();
  });
}
