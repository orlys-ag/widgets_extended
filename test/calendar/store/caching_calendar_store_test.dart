/// The caching store's day cache, its shown range, the per-entry lock, how
/// it reads changed days again and applies the changes a source announces,
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

/// A store over a fake data source, recording how often it notifies, and
/// applying [changes], if given.
class Harness {
  Harness({Stream<CalendarSourceChange<String>>? changes}) {
    store = CachingCalendarStore<String>(dataSource: source, changes: changes);
    store.addListener(() {
      notifications++;
    });
  }

  final FakeDataSource source = FakeDataSource();
  late final CachingCalendarStore<String> store;
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

/// Listens to [call] at once and returns whether it completed with a value
/// so far.
bool Function() completedOf(Future<Object?> call) {
  var completed = false;
  call.then((value) {
    completed = true;
  }, onError: (Object error) {});
  return () {
    return completed;
  };
}

List<String> idsOn(CalendarStore<String> store, DateTime day) {
  return <String>[for (final entry in store.entriesOn(day)) entry.id];
}

Matcher pendingRefusal(String id) {
  return isA<CalendarWritePendingException>().having(
    (error) => error.id,
    "id",
    id,
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
    final moving = errorOf(store.requestMove(requested));
    final failing = harness.lastCall;
    expect(failing.method, SourceMethod.replace);
    expect(store.entriesOn(DateTime(2026, 4, 23)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(requested, pending: true),
    ]);
    expect(idsOn(store, DateTime(2026, 4, 21)), isEmpty);
    expect(store.isPending("item-1"), isTrue);

    // Every write on the locked id is refused without a call or a throw.
    final calls = harness.source.calls.length;
    final moved = errorOf(
      store.requestMove(onDay(item, DateTime(2026, 4, 24))),
    );
    final refusal = errorOf(store.update(item.copyWith(title: "Renamed")));
    final deleted = errorOf(store.requestDelete("item-1"));
    await settle();
    expect(moved(), pendingRefusal("item-1"));
    expect(refusal(), pendingRefusal("item-1"));
    expect(deleted(), pendingRefusal("item-1"));
    expect(harness.source.calls, hasLength(calls));

    final movingFailed = failing.fail("Moving failed.");
    await settle();
    expect(store.entriesOn(DateTime(2026, 4, 21)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(item, pending: false),
    ]);
    expect(store.isPending("item-1"), isFalse);
    expect(moving(), same(movingFailed));

    // A move that succeeds completes with the entry the source stored.
    final succeeding = outcomeOf(store.requestMove(requested));
    final confirmed = requested.copyWith(title: "Confirmed");
    harness.lastCall.succeed(confirmed);
    await settle();
    expect(store.storedEntry("item-1"), confirmed);
    expect(store.isPending("item-1"), isFalse);
    expect(await succeeding, same(confirmed));

    // A form edit shows the stored entry until the data source answers,
    // and its failure reaches the caller.
    final edit = errorOf(store.update(other.copyWith(title: "Renamed")));
    expect(store.entriesOn(DateTime(2026, 4, 22)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(other, pending: true),
    ]);
    final savingFailed = harness.lastCall.fail("Saving failed.");
    await settle();
    expect(edit(), same(savingFailed));
    expect(store.isPending("item-2"), isFalse);

    // A confirmed create and delete add and remove.
    final created = draft(DateTime(2026, 4, 24), 600, 660);
    final creating = store.create(created);
    harness.lastCall.succeed(created.copyWith(id: "item-3"));
    await creating;
    expect(idsOn(store, DateTime(2026, 4, 24)), <String>["item-3"]);
    final deleting = outcomeOf(store.requestDelete("item-3"));
    harness.lastCall.succeed();
    await settle();
    expect(idsOn(store, DateTime(2026, 4, 24)), isEmpty);
    expect(await deleting, isNull);
  });

  test("M4 a move that meets an entry on a read day is sent to the source "
      "and stored once it answers", () async {
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
    final meeting = multi.copyWith(
      start: DateTime(2026, 4, 27, 13),
      end: DateTime(2026, 4, 27, 19),
    );
    final meetingMove = outcomeOf(store.requestMove(meeting));
    expect(harness.source.calls, hasLength(calls + 1));
    expect(harness.lastCall.method, SourceMethod.replace);
    expect(store.isPending("item-1"), isTrue);
    harness.lastCall.succeed(meeting);
    await settle();
    expect(store.isPending("item-1"), isFalse);
    expect(store.storedEntry("item-1"), meeting);

    // Two single-day entries share time as well.
    final sharing = single.copyWith(
      start: DateTime(2026, 4, 26, 10, 30),
      end: DateTime(2026, 4, 26, 11, 30),
    );
    final sharingMove = outcomeOf(store.requestMove(sharing));
    expect(harness.source.calls, hasLength(calls + 2));
    harness.lastCall.succeed(sharing);
    await settle();
    expect(store.storedEntry("item-2"), sharing);
    expect(await meetingMove, meeting);
    expect(await sharingMove, sharing);
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
    expect(store.status, CalendarLoadStatus.ready);
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

  test("M7 a completion after dispose calls no notifyListeners, and a "
      "failed move still fails to its caller", () async {
    // A notifyListeners after dispose throws in debug, from the callback
    // that completes the call, so it lands here.
    final errors = <Object>[];
    final done = Completer<(Object? Function(), Object)>();
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
        final moving = errorOf(
          store.requestMove(onDay(item, DateTime(2026, 4, 22))),
        );
        final write = harness.lastCall;

        store.dispose();
        read.succeed(<CalendarEntry<String>>[]);
        final writeFailed = write.fail();
        await settle();
        done.complete((moving, writeFailed));
      },
      (error, stackTrace) {
        errors.add(error);
      },
    );
    final (moving, writeFailed) = await done.future;
    expect(errors, isEmpty);
    expect(moving(), same(writeFailed));
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

    final refused = errorOf(store.requestMove(retimed(early, 450, 510)));
    expect(store.isPending("item-1"), isFalse);
    expect(harness.source.calls, hasLength(calls));
    await settle();
    expect(refused(), hoursRefusal(startOutside: true));

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
      final moving = errorOf(store.requestMove(retimed(item, 720, 780)));
      harness.lastCall.succeed(retimed(item, 720, 780).copyWith(id: "item-9"));
      await settle();
      expect(moving(), isA<StateError>());
      expect(store.isPending("item-1"), isFalse);
      expect(store.entriesOn(day), <CalendarShownEntry<String>>[
        CalendarShownEntry<String>(item, pending: false),
      ]);
      expect(store.storedEntry("item-9"), isNull);
    });

    test("an update or a move of an entry with no id fails and sends "
        "nothing", () async {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      final calls = harness.source.calls.length;
      final updating = errorOf(store.update(draft(day, 600, 660)));
      final moving = errorOf(store.requestMove(draft(day, 600, 660)));
      await settle();
      expect(updating(), isA<ArgumentError>());
      expect(moving(), isA<ArgumentError>());
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
      final again = errorOf(store.requestMove(retimed(stored, 900, 960)));
      await settle();
      expect(again(), pendingRefusal("item-5"));
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
      final moving = errorOf(store.requestMove(retimed(item, 720, 780)));
      final deleting = errorOf(store.requestDelete("item-2"));
      await settle();
      expect(store.status, CalendarLoadStatus.failed);
      expect(store.loadError, same(thrown));
      expect(store.isRead(aprilFirst), isFalse);
      expect(moving(), same(thrown));
      expect(deleting(), same(thrown));
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

  test("CS7 a write on an entry the store does not hold shows it pending "
      "once a read brings it", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final read = harness.lastCall;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.requestDelete("item-1");

    read.succeed(<CalendarEntry<String>>[item]);
    await settle();
    expect(store.entriesOn(DateTime(2026, 4, 21)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(item, pending: true),
    ]);
  });

  test("FR1 an invalidated shown day keeps showing what the store holds "
      "while it is read again, and the answer replaces its entries", () async {
    final harness = Harness();
    final store = harness.store;
    final kept = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final dropped = task("item-2", DateTime(2026, 4, 22), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[kept, dropped]);
    await settle();
    final notifications = harness.notifications;

    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 22));
    expect(harness.source.calls, hasLength(2));
    final read = harness.lastCall;
    expect(
      (read.first, read.last),
      (DateTime(2026, 4, 21), DateTime(2026, 4, 22)),
    );
    expect(store.status, CalendarLoadStatus.ready);
    expect(store.isRead(DateTime(2026, 4, 22)), isTrue);
    expect(idsOn(store, DateTime(2026, 4, 22)), <String>["item-2"]);
    expect(harness.notifications, notifications);

    final renamed = kept.copyWith(title: "Renamed");
    final added = task("item-3", DateTime(2026, 4, 22), 720, 780);
    read.succeed(<CalendarEntry<String>>[renamed, added]);
    await settle();
    expect(store.storedEntry("item-1"), renamed);
    expect(store.storedEntry("item-2"), isNull);
    expect(idsOn(store, DateTime(2026, 4, 22)), <String>["item-3"]);
    expect(harness.notifications, notifications + 1);
    expect(store.status, CalendarLoadStatus.ready);

    // Read again, the days send nothing more.
    store.prefetch(weekFirst, weekLast);
    expect(harness.source.calls, hasLength(2));
  });

  test("FR2 an invalidated day outside the shown range is read again once "
      "a prefetch covers it", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(aprilFirst, aprilLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(weekFirst, weekLast);

    store.invalidate(DateTime(2026, 4, 28), DateTime(2026, 4, 29));
    expect(harness.source.calls, hasLength(1));
    store.prefetch(DateTime(2026, 4, 27), aprilLast);
    expect(harness.source.calls, hasLength(2));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 28), DateTime(2026, 4, 29)),
    );
    // The read in flight covers them.
    store.prefetch(DateTime(2026, 4, 28), DateTime(2026, 4, 28));
    expect(harness.source.calls, hasLength(2));
  });

  test("FR3 an invalidated day outside the shown range is read again in "
      "the background once a show covers it", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(aprilFirst, aprilLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(weekFirst, weekLast);

    store.invalidate(DateTime(2026, 4, 1), DateTime(2026, 4, 2));
    expect(harness.source.calls, hasLength(1));
    store.show(aprilFirst, aprilLast);
    expect(harness.source.calls, hasLength(2));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 1), DateTime(2026, 4, 2)),
    );
    expect(store.status, CalendarLoadStatus.ready);
  });

  test("FR4 a refresh reads the whole shown range again, keeps the entries "
      "shown while it runs and after it fails, and completes with its "
      "read", () async {
    final harness = Harness();
    final store = harness.store;
    final unshown = completedOf(store.refresh());
    await settle();
    expect(unshown(), isTrue);

    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(aprilFirst, aprilLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    store.show(weekFirst, weekLast);
    final notifications = harness.notifications;

    final failing = errorOf(store.refresh());
    expect(harness.source.calls, hasLength(2));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (weekFirst, weekLast),
    );
    expect(store.status, CalendarLoadStatus.ready);
    expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);
    expect(harness.notifications, notifications);
    final error = harness.lastCall.fail();
    await settle();
    expect(failing(), same(error));
    expect(store.status, CalendarLoadStatus.ready);
    expect(store.readFailed(DateTime(2026, 4, 21)), isFalse);
    expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);

    final succeeding = completedOf(store.refresh());
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(succeeding(), isTrue);
    expect(idsOn(store, DateTime(2026, 4, 21)), isEmpty);

    // The days of April outside the week stay changed.
    store.prefetch(aprilFirst, aprilLast);
    expect(harness.source.calls, hasLength(4));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (aprilFirst, aprilLast),
    );
  });

  test("FR5 a refresh while the shown range's read failed waits on its "
      "read, as a retry does", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.failed);

    final refreshing = completedOf(store.refresh());
    expect(store.status, CalendarLoadStatus.loading);
    expect(store.loadError, isNull);
    expect(harness.source.calls, hasLength(2));
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    expect(refreshing(), isTrue);
    expect(store.status, CalendarLoadStatus.ready);
    expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);
  });

  test("FR6 a change on the days a read in flight covers leaves them "
      "changed once it answers, and the shown ones are read again", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final read = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    expect(harness.source.calls, hasLength(1));

    read.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(harness.source.calls, hasLength(2));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 21), DateTime(2026, 4, 21)),
    );
  });

  test("FR7 a read answering after one sent later changes nothing the "
      "later one answered", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final older = harness.lastCall;
    store.refresh();
    final newer = harness.lastCall;
    expect(newer, isNot(same(older)));

    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final renamed = item.copyWith(title: "Renamed");
    final removed = task("item-2", DateTime(2026, 4, 22), 600, 660);
    newer.succeed(<CalendarEntry<String>>[renamed]);
    await settle();
    older.succeed(<CalendarEntry<String>>[item, removed]);
    await settle();
    expect(store.storedEntry("item-1"), renamed);
    expect(store.storedEntry("item-2"), isNull);
  });

  test("FR8 an answered entry on a day a later read filled without it is "
      "out of date, and the days it covers in its own read are read "
      "again", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 22));
    final older = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 22), DateTime(2026, 4, 24));
    final newer = harness.lastCall;
    expect(
      (newer.first, newer.last),
      (DateTime(2026, 4, 22), DateTime(2026, 4, 24)),
    );

    // From Tuesday 22:00 to Wednesday 01:00.
    final spanning = task("item-1", DateTime(2026, 4, 21), 1320, 1500);
    newer.succeed(<CalendarEntry<String>>[]);
    await settle();
    older.succeed(<CalendarEntry<String>>[spanning]);
    await settle();
    expect(store.storedEntry("item-1"), isNull);
    expect(harness.source.calls, hasLength(3));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 21), DateTime(2026, 4, 21)),
    );
  });

  test("FR9 a read replaces a held entry it answers on a day read "
      "before", () async {
    final harness = Harness();
    final store = harness.store;
    // From Sunday 19:00 to Monday 01:00.
    final spanning = task("item-1", DateTime(2026, 4, 26), 1140, 1500);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[spanning]);
    await settle();
    expect(idsOn(store, DateTime(2026, 4, 26)), <String>["item-1"]);

    final moved = spanning.copyWith(
      start: DateTime(2026, 4, 27, 10),
      end: DateTime(2026, 4, 27, 11),
    );
    store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    harness.lastCall.succeed(<CalendarEntry<String>>[moved]);
    await settle();
    expect(store.storedEntry("item-1"), moved);
    expect(idsOn(store, DateTime(2026, 4, 26)), isEmpty);
    expect(idsOn(store, DateTime(2026, 4, 27)), <String>["item-1"]);
  });

  test("FR10 a delete confirmed while a read is in flight outlives the "
      "read's answer", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    store.refresh();
    final read = harness.lastCall;

    store.requestDelete("item-1");
    harness.lastCall.succeed();
    await settle();
    read.succeed(<CalendarEntry<String>>[item]);
    await settle();
    expect(store.storedEntry("item-1"), isNull);
  });

  test("FR11 an invalidate over more days than the store has read marks "
      "each read day in it", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    store.invalidate(DateTime(2000, 1, 1), DateTime(2100, 12, 31));
    expect(harness.source.calls, hasLength(2));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (weekFirst, weekLast),
    );
  });

  test("FR12 a write confirmed while two reads are in flight outlives the "
      "answer of the one that answers last", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    store.refresh();
    final first = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    final second = harness.lastCall;

    final moved = onDay(item, DateTime(2026, 4, 22));
    store.requestMove(moved);
    harness.lastCall.succeed(moved);
    await settle();
    second.succeed(<CalendarEntry<String>>[]);
    await settle();
    first.succeed(<CalendarEntry<String>>[item]);
    await settle();
    expect(store.storedEntry("item-1"), moved);
  });

  test("FR13 a prefetch or a show over unread and changed days sends one "
      "read for both", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 22));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(DateTime(2026, 4, 27), DateTime(2026, 4, 27));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    store.prefetch(DateTime(2026, 4, 20), DateTime(2026, 4, 24));
    expect(harness.source.calls, hasLength(3));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 21), DateTime(2026, 4, 24)),
    );

    store.invalidate(DateTime(2026, 4, 20), DateTime(2026, 4, 20));
    store.show(DateTime(2026, 4, 18), DateTime(2026, 4, 20));
    expect(harness.source.calls, hasLength(4));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 18), DateTime(2026, 4, 20)),
    );
  });

  test("FR14 a read that does not answer a held entry leaves changed the "
      "read days the entry covers outside the read", () async {
    final harness = Harness();
    final store = harness.store;
    // From the 22nd 22:00 to the 23rd 01:00.
    final spanning = task("item-1", DateTime(2026, 4, 22), 1320, 1500);
    store.show(DateTime(2026, 4, 23), DateTime(2026, 4, 25));
    harness.lastCall.succeed(<CalendarEntry<String>>[spanning]);
    await settle();
    store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 22));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    store.show(DateTime(2026, 4, 23), DateTime(2026, 4, 25));
    expect(harness.source.calls, hasLength(3));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 23), DateTime(2026, 4, 23)),
    );
  });

  test("FR15 so does one answering before an older read over the entry's "
      "other day, which is then read again", () async {
    final harness = Harness();
    final store = harness.store;
    final spanning = task("item-1", DateTime(2026, 4, 22), 1320, 1500);
    store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 22));
    harness.lastCall.succeed(<CalendarEntry<String>>[spanning]);
    await settle();
    store.prefetch(DateTime(2026, 4, 23), DateTime(2026, 4, 25));
    harness.lastCall.succeed(<CalendarEntry<String>>[spanning]);
    await settle();
    store.refresh();
    final older = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 23), DateTime(2026, 4, 25));
    final newer = harness.lastCall;

    newer.succeed(<CalendarEntry<String>>[]);
    await settle();
    older.succeed(<CalendarEntry<String>>[retimed(spanning, 1320, 1440)]);
    await settle();
    expect(harness.source.calls, hasLength(5));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 22), DateTime(2026, 4, 22)),
    );
  });

  test("FR16 a failed read the shown range waits on leaves it loading on "
      "another read in flight over its unread days", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final load = harness.lastCall;
    final refreshing = errorOf(store.refresh());
    harness.lastCall.fail();
    await settle();
    expect(refreshing(), isA<SourceFailure>());
    expect(store.status, CalendarLoadStatus.loading);

    load.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
  });

  test("FR17 a burst of changes on a shown day sends one read, and one "
      "more once it answers", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    for (var i = 0; i < 3; i++) {
      store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    }
    expect(harness.source.calls, hasLength(2));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(harness.source.calls, hasLength(3));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(harness.source.calls, hasLength(3));
  });

  test("FR18 changes on two days a read in flight covers are both read "
      "again once it answers", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final read = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    store.invalidate(DateTime(2026, 4, 24), DateTime(2026, 4, 24));

    read.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(harness.source.calls, hasLength(2));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 21), DateTime(2026, 4, 24)),
    );
  });

  test("FR19 a disposed store sends nothing for an invalidate, and its "
      "refresh completes", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.dispose();

    store.invalidate(weekFirst, weekLast);
    expect(harness.source.calls, hasLength(1));
    final refreshing = completedOf(store.refresh());
    await settle();
    expect(refreshing(), isTrue);
  });

  test("FR20 a write's contradicted answer leaves its days changed under a "
      "read in flight, which are read again once shown", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    final moved = onDay(item, DateTime(2026, 4, 28));
    store.update(moved);
    final write = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    final prefetch = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();

    write.succeed(moved);
    await settle();
    prefetch.succeed(<CalendarEntry<String>>[]);
    await settle();
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    expect(harness.source.calls, hasLength(6));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 28), DateTime(2026, 4, 28)),
    );
  });

  test("FR21 a move's answer outside the days of a later read that removed "
      "the entry is stored", () async {
    for (final target in <int>[23, 20]) {
      final harness = Harness();
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      final moved = onDay(item, DateTime(2026, 4, target));
      store.requestMove(moved);
      final write = harness.lastCall;
      store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();

      write.succeed(moved);
      await settle();
      expect(store.storedEntry("item-1"), moved, reason: "to the $target");
      expect(harness.source.calls, hasLength(3), reason: "to the $target");
    }
  });

  test("FR22 a move's answer on the days of a later read that removed the "
      "entry is not stored", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    final moved = retimed(item, 720, 780);
    store.requestMove(moved);
    final write = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    write.succeed(moved);
    await settle();
    expect(store.storedEntry("item-1"), isNull);
  });

  test("FR23 a change on a shown day reads that day at once, while reads "
      "of other days are in flight", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    for (var day = 20; day <= 26; day++) {
      store.invalidate(DateTime(2026, 4, day), DateTime(2026, 4, day));
    }
    expect(
      <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(1))
          (call.first, call.last),
      ],
      <(DateTime?, DateTime?)>[
        for (var day = 20; day <= 26; day++)
          (DateTime(2026, 4, day), DateTime(2026, 4, day)),
      ],
    );
    for (final call in harness.source.calls.skip(1).toList()) {
      call.succeed(<CalendarEntry<String>>[]);
    }
    await settle();
    expect(harness.source.calls, hasLength(8));
  });

  test("FR26 changes read again through a source answering within the call "
      "keep being read", () {
    final source = SyncSource();
    final store = CachingCalendarStore<String>(dataSource: source);
    store.show(weekFirst, weekLast);
    final first = task("item-1", DateTime(2026, 4, 21), 600, 660);
    source.entries = <CalendarEntry<String>>[first];
    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);

    final second = task("item-2", DateTime(2026, 4, 22), 600, 660);
    source.entries = <CalendarEntry<String>>[first, second];
    store.invalidate(DateTime(2026, 4, 22), DateTime(2026, 4, 22));
    expect(idsOn(store, DateTime(2026, 4, 22)), <String>["item-2"]);
    store.dispose();
  });

  test("FR27 showing a range reads its changed days while a read of "
      "another range's is in flight", () async {
    final harness = Harness();
    final store = harness.store;
    final mayWeekFirst = DateTime(2026, 4, 27);
    final mayWeekLast = DateTime(2026, 5, 3);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(mayWeekFirst, mayWeekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(weekFirst, weekLast);
    store.invalidate(DateTime(2026, 4, 28), DateTime(2026, 4, 28));
    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));

    store.show(mayWeekFirst, mayWeekLast);
    expect(harness.source.calls, hasLength(4));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 28), DateTime(2026, 4, 28)),
    );
  });

  test("FR28 a read that leaves the shown range with no unread day makes "
      "it ready while the read it waits on is in flight", () async {
    final harness = Harness();
    final store = harness.store;
    store.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.loading);

    store.show(weekFirst, weekLast);
    final week = harness.lastCall;
    store.show(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    final mayWeek = harness.lastCall;
    store.show(DateTime(2026, 4, 23), DateTime(2026, 4, 29));
    final awaited = harness.lastCall;
    week.succeed(<CalendarEntry<String>>[
      task("item-1", DateTime(2026, 4, 24), 600, 660),
    ]);
    await settle();
    expect(store.status, CalendarLoadStatus.loading);
    mayWeek.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
    expect(store.dayHasShownEntries(DateTime(2026, 4, 24)), isTrue);
    awaited.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
  });

  test("FR24 a change on an unread day a read in flight covers outlives an "
      "older read's answer removing an entry there", () async {
    final harness = Harness();
    final store = harness.store;
    // From the 26th 22:00 to the 27th 01:00.
    final spanning = task("item-1", DateTime(2026, 4, 26), 1320, 1500);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[spanning]);
    await settle();
    store.invalidate(DateTime(2026, 4, 26), DateTime(2026, 4, 26));
    final older = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    final prefetch = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 27), DateTime(2026, 4, 27));

    older.succeed(<CalendarEntry<String>>[]);
    await settle();
    prefetch.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    expect(harness.source.calls, hasLength(4));
  });

  test("FR25 a read that leaves a failed shown range with no unread day "
      "makes it ready", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.failed);

    store.prefetch(DateTime(2026, 4, 20), DateTime(2026, 4, 23));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    final notifications = harness.notifications;
    store.prefetch(DateTime(2026, 4, 24), DateTime(2026, 4, 26));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
    expect(store.loadError, isNull);
    expect(harness.notifications, notifications + 1);
  });

  test("FR29 a failed read the shown range waits on leaves it failed once "
      "the read in flight over its unread days fails too", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final load = harness.lastCall;
    errorOf(store.refresh());
    harness.lastCall.fail();
    await settle();

    final failure = load.fail("Down.");
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    expect(store.loadError, same(failure));
  });

  test("FR30 the read the shown range waited on, once other reads made it "
      "ready, notifies only when it changes what the store answers", () async {
    final notified = <int>[];
    for (final answer in <List<CalendarEntry<String>>?>[
      <CalendarEntry<String>>[],
      null,
      <CalendarEntry<String>>[task("item-1", DateTime(2026, 4, 24), 600, 660)],
    ]) {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      final week = harness.lastCall;
      store.show(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
      final mayWeek = harness.lastCall;
      store.show(DateTime(2026, 4, 23), DateTime(2026, 4, 29));
      final awaited = harness.lastCall;
      week.succeed(<CalendarEntry<String>>[]);
      mayWeek.succeed(<CalendarEntry<String>>[]);
      await settle();
      final notifications = harness.notifications;
      if (answer == null) {
        awaited.fail();
      } else {
        awaited.succeed(answer);
      }
      await settle();
      notified.add(harness.notifications - notifications);
    }
    expect(notified, <int>[0, 0, 1]);
  });

  test("FR31 a move's answer on a day a read sent since answered without "
      "the entry is not stored, and the days of both are read again", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    final moved = onDay(item, DateTime(2026, 4, 23));
    store.requestMove(moved);
    final write = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 23), DateTime(2026, 4, 23));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    write.succeed(moved);
    await settle();
    expect(store.storedEntry("item-1"), item);
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 21), DateTime(2026, 4, 23)),
    );
  });

  test("FR32 a create's answer on a day a read sent since answered without "
      "it is not stored, and its days are read again", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    final created = draft(DateTime(2026, 4, 23), 600, 660);
    final creating = store.create(created);
    final write = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 23), DateTime(2026, 4, 23));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    final answer = created.copyWith(id: "item-1");
    write.succeed(answer);
    await creating;
    expect(store.storedEntry("item-1"), isNull);
    expect(harness.source.calls, hasLength(4));
  });

  test("FR33 a disposed store sends nothing for a prefetch, a show or a "
      "retry", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    expect(store.isRead(weekFirst), isFalse);
    store.dispose();

    store.prefetch(mayFirst, mayLast);
    expect(harness.source.calls, hasLength(1));
    expect(() => store.show(mayFirst, mayLast), returnsNormally);
    expect(harness.source.calls, hasLength(1));
    expect(store.retry, returnsNormally);
    expect(harness.source.calls, hasLength(1));
  });

  test("FR34 a failed read leaves the shown range loading while reads in "
      "flight cover its unread days between them, and failed with the error "
      "of the one that leaves a day unread with no read", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(DateTime(2026, 4, 21), DateTime(2026, 4, 25));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.prefetch(DateTime(2026, 4, 19), DateTime(2026, 4, 20));
    final before = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 26), DateTime(2026, 4, 27));
    store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 26));
    harness.lastCall.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.loading);

    final failure = before.fail("Down.");
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    expect(store.loadError, same(failure));
  });

  test("FR35 a read the shown range did not ask for leaves it failed, "
      "notifying nothing, while it reads the day whose read failed", () async {
    final seen = <String, (CalendarLoadStatus, int, bool)>{};
    for (final trigger in <String>["prefetch", "invalidate", "announce"]) {
      final changes = StreamController<CalendarSourceChange<String>>();
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.fail();
      await settle();
      store.prefetch(weekFirst, DateTime(2026, 4, 22));
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      store.prefetch(DateTime(2026, 4, 24), weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      final notifications = harness.notifications;

      if (trigger == "prefetch") {
        store.prefetch(weekFirst, weekLast);
      } else if (trigger == "invalidate") {
        store.invalidate(weekFirst, weekLast);
      } else {
        changes.add(const CalendarAllChanged<String>());
        await settle();
      }
      seen[trigger] = (
        store.status,
        harness.notifications - notifications,
        store.readFailed(DateTime(2026, 4, 23)),
      );
      await changes.close();
    }
    expect(seen, <String, (CalendarLoadStatus, int, bool)>{
      "prefetch": (CalendarLoadStatus.failed, 0, false),
      "invalidate": (CalendarLoadStatus.failed, 0, false),
      "announce": (CalendarLoadStatus.failed, 0, false),
    });
  });

  test("FR36 a failed shown range stays failed when a read answers while "
      "another reads the day whose read failed", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    store.prefetch(weekFirst, DateTime(2026, 4, 22));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    store.prefetch(DateTime(2026, 4, 24), weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.prefetch(DateTime(2026, 4, 23), DateTime(2026, 4, 23));

    store.invalidate(weekFirst, weekFirst);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
  });

  test("FR37 showing another range after the shown range failed loads "
      "it", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();

    store.show(mayFirst, mayLast);
    expect(store.status, CalendarLoadStatus.loading);
    expect(store.loadError, isNull);
  });

  group("CF the changes the source announces", () {
    late StreamController<CalendarSourceChange<String>> changes;

    setUp(() {
      changes = StreamController<CalendarSourceChange<String>>();
    });

    tearDown(() {
      changes.close();
    });

    test("CF1 a put or a removal applies without a read where the store "
        "holds the days", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      final notifications = harness.notifications;

      changes.add(CalendarEntryPut<String>(onDay(item, DateTime(2026, 4, 23))));
      await settle();
      expect(idsOn(store, DateTime(2026, 4, 21)), isEmpty);
      expect(idsOn(store, DateTime(2026, 4, 23)), <String>["item-1"]);
      expect(harness.notifications, notifications + 1);
      final added = task("item-2", DateTime(2026, 4, 24), 600, 660);
      changes.add(CalendarEntryPut<String>(added));
      await settle();
      expect(idsOn(store, DateTime(2026, 4, 24)), <String>["item-2"]);
      changes.add(const CalendarEntryRemoved<String>("item-1"));
      await settle();
      expect(store.storedEntry("item-1"), isNull);
      expect(harness.notifications, notifications + 3);

      // Off the days the store holds, a new entry is dropped, and a held
      // one moving there is forgotten.
      changes.add(
        CalendarEntryPut<String>(task("item-3", DateTime(2026, 6, 1), 0, 60)),
      );
      changes.add(CalendarEntryPut<String>(onDay(added, DateTime(2026, 6, 1))));
      await settle();
      expect(store.storedEntry("item-3"), isNull);
      expect(store.storedEntry("item-2"), isNull);
      expect(harness.source.calls, hasLength(1));
    });

    test("CF2 a change of days or of all, or an error on the stream, reads "
        "the changed shown days again", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();

      changes.add(
        CalendarDaysChanged<String>(
          DateTime(2026, 4, 21),
          DateTime(2026, 4, 22),
        ),
      );
      await settle();
      expect(harness.source.calls, hasLength(2));
      expect(
        (harness.lastCall.first, harness.lastCall.last),
        (DateTime(2026, 4, 21), DateTime(2026, 4, 22)),
      );
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();

      changes.add(const CalendarAllChanged<String>());
      await settle();
      expect(harness.source.calls, hasLength(3));
      expect(
        (harness.lastCall.first, harness.lastCall.last),
        (weekFirst, weekLast),
      );
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();

      changes.addError(const SourceFailure("Disconnected."));
      await settle();
      expect(harness.source.calls, hasLength(4));
      expect(
        (harness.lastCall.first, harness.lastCall.last),
        (weekFirst, weekLast),
      );
    });

    test("CF3 a change announced while a read is in flight outlives the "
        "read's answer", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      store.show(weekFirst, weekLast);
      final read = harness.lastCall;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      final added = task("item-2", DateTime(2026, 4, 22), 600, 660);
      changes.add(const CalendarEntryRemoved<String>("item-1"));
      changes.add(CalendarEntryPut<String>(added));
      await settle();

      read.succeed(<CalendarEntry<String>>[item]);
      await settle();
      expect(store.storedEntry("item-1"), isNull);
      expect(idsOn(store, DateTime(2026, 4, 22)), <String>["item-2"]);
    });

    test("CF4 a put on an entry a write runs on changes the stored entry, "
        "which shows once the write fails", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      final requested = onDay(item, DateTime(2026, 4, 23));
      final moving = errorOf(store.requestMove(requested));
      final write = harness.lastCall;

      final renamed = item.copyWith(title: "Renamed");
      changes.add(CalendarEntryPut<String>(renamed));
      await settle();
      expect(store.storedEntry("item-1"), renamed);
      expect(
        store.entriesOn(DateTime(2026, 4, 23)),
        <CalendarShownEntry<String>>[
          CalendarShownEntry<String>(requested, pending: true),
        ],
      );
      final failure = write.fail();
      await settle();
      expect(moving(), same(failure));
      expect(
        store.entriesOn(DateTime(2026, 4, 21)),
        <CalendarShownEntry<String>>[
          CalendarShownEntry<String>(renamed, pending: false),
        ],
      );
    });

    test("CF5 a disposed store stops listening, and a refresh waiting on "
        "a read completes", () async {
      final harness = Harness(changes: changes.stream);
      expect(changes.hasListener, isTrue);
      harness.store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      final refreshing = completedOf(harness.store.refresh());

      harness.store.dispose();
      await settle();
      expect(changes.hasListener, isFalse);
      expect(refreshing(), isTrue);
    });

    test("CF6 a put of an entry with no id throws", () {
      expect(
        () => CalendarEntryPut<String>(draft(DateTime(2026, 4, 21), 600, 660)),
        throwsArgumentError,
      );
    });

    test("CF7 a write's answer that a change announced since its send "
        "contradicts keeps the change, and reads both entries' days "
        "again", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      final moved = onDay(item, DateTime(2026, 4, 23));
      store.requestMove(moved);
      final write = harness.lastCall;

      // The write's echo, then another writer's move.
      final elsewhere = onDay(item, DateTime(2026, 4, 25));
      changes.add(CalendarEntryPut<String>(moved));
      changes.add(CalendarEntryPut<String>(elsewhere));
      await settle();
      write.succeed(moved);
      await settle();
      expect(store.storedEntry("item-1"), elsewhere);
      expect(harness.source.calls, hasLength(3));
      expect(
        (harness.lastCall.first, harness.lastCall.last),
        (DateTime(2026, 4, 23), DateTime(2026, 4, 25)),
      );
    });

    test(
      "CF8 a write's answer its echo already stored sends no read",
      () async {
        final harness = Harness(changes: changes.stream);
        final store = harness.store;
        final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
        store.show(weekFirst, weekLast);
        harness.lastCall.succeed(<CalendarEntry<String>>[item]);
        await settle();
        final moved = onDay(item, DateTime(2026, 4, 23));
        store.requestMove(moved);
        final write = harness.lastCall;

        changes.add(CalendarEntryPut<String>(moved));
        await settle();
        write.succeed(moved);
        await settle();
        expect(harness.source.calls, hasLength(2));
      },
    );

    test("CF9 a create's answer that a removal announced since its send "
        "contradicts is not stored", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      final created = draft(DateTime(2026, 4, 22), 600, 660);
      final creating = store.create(created);
      final write = harness.lastCall;

      changes.add(const CalendarEntryRemoved<String>("item-5"));
      await settle();
      write.succeed(created.copyWith(id: "item-5"));
      await creating;
      expect(store.storedEntry("item-5"), isNull);
      expect(harness.source.calls, hasLength(3));
    });

    test("CF10 a delete's answer that a put announced since its send "
        "contradicts keeps the put entry", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      store.requestDelete("item-1");
      final write = harness.lastCall;

      final renamed = item.copyWith(title: "Renamed");
      changes.add(CalendarEntryPut<String>(renamed));
      await settle();
      write.succeed();
      await settle();
      expect(store.storedEntry("item-1"), renamed);
      expect(harness.source.calls, hasLength(3));
    });

    test("CF11 a pending delete shows the stored entry as a put changes "
        "it", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      store.requestDelete("item-1");

      final moved = onDay(item, DateTime(2026, 4, 23));
      changes.add(CalendarEntryPut<String>(moved));
      await settle();
      expect(
        store.entriesOn(DateTime(2026, 4, 23)),
        <CalendarShownEntry<String>>[
          CalendarShownEntry<String>(moved, pending: true),
        ],
      );
      expect(store.entriesOn(DateTime(2026, 4, 21)), isEmpty);
    });

    test("CF12 a change announced after a read removed the entry "
        "contradicts a write's answer off that read's days", () async {
      final harness = Harness(changes: changes.stream);
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      final moved = onDay(item, DateTime(2026, 4, 23));
      store.requestMove(moved);
      final write = harness.lastCall;
      store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();

      final elsewhere = onDay(item, DateTime(2026, 4, 25));
      changes.add(CalendarEntryPut<String>(elsewhere));
      await settle();
      write.succeed(moved);
      await settle();
      expect(store.storedEntry("item-1"), elsewhere);
    });
  });
}
