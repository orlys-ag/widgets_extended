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

  /// While set, `read` answers these entries within the call through a
  /// [SynchronousFuture], recording the call in [answeredNow], and so do
  /// `replace`, with the entry it writes, and `delete`.
  List<CalendarEntry<String>>? answerNow;

  /// The calls answered within the call while [answerNow] was set, in the
  /// order they arrived; [calls], which the tests answer by hand, holds
  /// none of them.
  final List<FakeCall> answeredNow = <FakeCall>[];

  /// Runs at each `read` call, before it answers, while set.
  void Function()? onRead;

  /// The first and the last day of each read in [answeredNow].
  List<(DateTime, DateTime)> get readsNow {
    return <(DateTime, DateTime)>[
      for (final call in answeredNow)
        if (call.method == SourceMethod.read) (call.first!, call.last!),
    ];
  }

  Future<R> _add<R>(FakeCall call) {
    calls.add(call);
    return call.completer.future.then((value) {
      return value as R;
    });
  }

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    onRead?.call();
    final error = thrown;
    if (error != null) {
      throw error;
    }
    final now = answerNow;
    if (now != null) {
      answeredNow.add(FakeCall(SourceMethod.read, first: first, last: last));
      return SynchronousFuture<List<CalendarEntry<String>>>(
        List<CalendarEntry<String>>.of(now),
      );
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
    if (answerNow != null) {
      answeredNow.add(
        FakeCall(SourceMethod.replace, id: entry.id, entry: entry),
      );
      return SynchronousFuture<CalendarEntry<String>>(entry);
    }
    return _add(FakeCall(SourceMethod.replace, id: entry.id, entry: entry));
  }

  @override
  Future<void> delete(String id) {
    final error = thrown;
    if (error != null) {
      throw error;
    }
    if (answerNow != null) {
      answeredNow.add(FakeCall(SourceMethod.delete, id: id));
      return SynchronousFuture<void>(null);
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
  final shift =
      CalendarDates.dayNumber(day) - CalendarDates.dayNumber(entry.start);
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

/// A data source whose reads take [script]'s answers in turn: a list
/// answers within the call, through a [SynchronousFuture], and a null
/// leaves the read in flight for good.
class ScriptedSource implements CalendarDataSource<String> {
  final List<List<CalendarEntry<String>>?> script =
      <List<CalendarEntry<String>>?>[];

  int reads = 0;

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    reads++;
    final answer = script.removeAt(0);
    if (answer == null) {
      return Completer<List<CalendarEntry<String>>>().future;
    }
    return SynchronousFuture<List<CalendarEntry<String>>>(answer);
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}

/// A data source whose reads answer [entries] within the call, through
/// a [SynchronousFuture] or, while [readThenThrows] is set, a
/// [ThenThrows]; or through an ordinary future while [readLater] is set.
/// Its writes answer the entry written, a create's under [createdId] or
/// else a new id: within the call, through a [SynchronousFuture] or,
/// while [thenThrows] is set, a [ThenThrows]; or through an ordinary
/// future while [later] is set. Each write counts toward [writes], then
/// runs [onWrite], if set, before it answers.
class WriteNowSource<P> implements CalendarDataSource<P> {
  List<CalendarEntry<P>> entries = <CalendarEntry<P>>[];

  bool later = false;

  bool readLater = false;

  bool readThenThrows = false;

  bool thenThrows = false;

  void Function()? onWrite;

  String? createdId;

  int writes = 0;

  Future<R> _answer<R>(R value) {
    writes++;
    onWrite?.call();
    if (later) {
      return Future<R>.value(value);
    }
    return thenThrows ? ThenThrows<R>(value) : SynchronousFuture<R>(value);
  }

  @override
  Future<List<CalendarEntry<P>>> read(DateTime first, DateTime last) {
    final answer = List<CalendarEntry<P>>.of(entries);
    if (readLater) {
      return Future<List<CalendarEntry<P>>>.value(answer);
    }
    if (readThenThrows) {
      return ThenThrows<List<CalendarEntry<P>>>(answer);
    }
    return SynchronousFuture<List<CalendarEntry<P>>>(answer);
  }

  @override
  Future<CalendarEntry<P>> create(CalendarEntry<P> draft) {
    return _answer(draft.copyWith(id: createdId ?? "created-${writes + 1}"));
  }

  @override
  Future<CalendarEntry<P>> replace(CalendarEntry<P> entry) {
    return _answer(entry);
  }

  @override
  Future<void> delete(String id) {
    return _answer<void>(null);
  }
}

/// A [SynchronousFuture] that, against the [Future] contract, throws
/// from [then] once it has answered.
class ThenThrows<T> extends SynchronousFuture<T> {
  ThenThrows(super.value);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    super.then(onValue, onError: onError);
    throw const SourceFailure("Then.");
  }
}

/// What a [Brittle] payload's `==` throws.
class BrittleFailure implements Exception {
  const BrittleFailure();
}

/// A payload whose `==` throws a [BrittleFailure] where [brittle], as a
/// host's payload's `==` can.
class Brittle {
  const Brittle({this.brittle = false});

  final bool brittle;

  @override
  bool operator ==(Object other) {
    if (brittle) {
      throw const BrittleFailure();
    }
    return other is Brittle && !other.brittle;
  }

  @override
  int get hashCode {
    return brittle.hashCode;
  }
}

/// The four writes on [store] by name, each sending a new write when
/// called: an update and a move of [item], a delete of it, and a create
/// on its day.
Map<String, Future<Object?> Function()> writesOf(
  CalendarStore<String> store,
  CalendarEntry<String> item,
) {
  return <String, Future<Object?> Function()>{
    "update": () {
      return store.update(retimed(item, 720, 780));
    },
    "move": () {
      return store.requestMove(retimed(item, 800, 860));
    },
    "delete": () {
      return store.requestDelete(item.id!);
    },
    "create": () {
      return store.create(draft(item.start, 900, 960));
    },
  };
}

/// Runs [body] in a zone that notes the errors it leaves uncaught, with
/// [FlutterError.onError] noting each error reported, then settles; the
/// types of both, in the order they came.
Future<({List<Type> uncaught, List<Type> reported})> caughtIn(
  void Function() body,
) async {
  final uncaught = <Type>[];
  final reported = <Type>[];
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    reported.add(details.exception.runtimeType);
  };
  try {
    runZonedGuarded(body, (error, stack) {
      uncaught.add(error.runtimeType);
    });
    await settle();
  } finally {
    FlutterError.onError = onError;
  }
  return (uncaught: uncaught, reported: reported);
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
    // next one sends again, which keeps the mark until it answers.
    store.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    harness.lastCall.fail();
    await settle();
    expect(harness.notifications, notifications + 2);
    expect(store.isRead(DateTime(2026, 5, 4)), isFalse);
    expect(store.readFailed(DateTime(2026, 5, 4)), isTrue);
    expect(store.readFailed(DateTime(2026, 4, 28)), isFalse);
    store.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    expect(harness.source.calls, hasLength(4));
    expect(store.readFailed(DateTime(2026, 5, 4)), isTrue);
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
      final notifications = harness.notifications;
      final creating = errorOf(store.create(created));
      harness.lastCall.succeed(created);
      await settle();
      expect(creating(), isA<StateError>());
      expect(store.entriesOn(day), isEmpty);
      expect(harness.notifications, notifications);
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

    test("an update answered under another id fails, and the entry shows "
        "as stored", () async {
      final harness = Harness();
      final store = harness.store;
      final item = task("item-1", day, 600, 660);
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      final updating = errorOf(store.update(retimed(item, 720, 780)));
      final notifications = harness.notifications;
      harness.lastCall.succeed(
        onDay(item, DateTime(2026, 4, 23)).copyWith(id: "item-9"),
      );
      await settle();
      expect(
        updating(),
        isA<StateError>().having(
          (error) {
            return error.message;
          },
          "message",
          contains("under item-9"),
        ),
      );
      expect(store.isPending("item-1"), isFalse);
      expect(store.entriesOn(day), <CalendarShownEntry<String>>[
        CalendarShownEntry<String>(item, pending: false),
      ]);
      expect(store.storedEntry("item-9"), isNull);
      expect(harness.notifications, notifications + 1);
    });

    test("a write answered within the call is stored within it, and its "
        "future completes after the call, as a future does", () async {
      final source = WriteNowSource<String>();
      final item = task("item-1", day, 600, 660);
      source.entries = <CalendarEntry<String>>[item];
      final store = CachingCalendarStore<String>(dataSource: source);
      store.show(weekFirst, weekLast);
      const host = SourceFailure("Host.");
      final outcomes = <String, Object? Function()>{};
      final within = <String, CalendarEntry<String>?>{};
      for (final MapEntry(key: write, value: send) in writesOf(
        store,
        item,
      ).entries) {
        var called = false;
        send().then((value) {
          called = true;
        });
        final calledBack = called;
        if (write == "update" || write == "move") {
          within[write] = store.storedEntry("item-1");
        }
        final recovered = completedOf(
          send().catchError((Object error) {
            return error;
          }),
        );
        Object? thrown;
        Object? Function()? failure;
        try {
          failure = errorOf(
            send().then((value) {
              throw host;
            }),
          );
        } on Object catch (error) {
          thrown = error;
        }
        outcomes[write] = () {
          return (
            calledBack: calledBack,
            recovered: recovered(),
            thrown: thrown,
            failure: failure?.call(),
          );
        };
      }
      expect(within, <String, CalendarEntry<String>?>{
        "update": retimed(item, 720, 780),
        "move": retimed(item, 800, 860),
      });
      expect(idsOn(store, day), <String>[
        "created-10",
        "created-11",
        "created-12",
      ]);
      await settle();
      // Each write's callback runs after the call, its catchError passes
      // its value on, and a callback's throw fails the callback's future.
      const settled = (
        calledBack: false,
        recovered: true,
        thrown: null,
        failure: host,
      );
      expect(
        <String, Object?>{
          for (final MapEntry(key: write, value: outcome) in outcomes.entries)
            write: outcome(),
        },
        <String, Object?>{
          "update": settled,
          "move": settled,
          "delete": settled,
          "create": settled,
        },
      );
    });

    test("a write whose answer's payload's == throws stores the answer, "
        "and the throw is reported", () async {
      final failures = <String, Type>{};
      final stored = <String, bool>{};
      final reported = <String, List<Type>>{};
      for (final write in <String>["update", "move", "create"]) {
        for (final later in <bool>[false, true]) {
          final name = later ? "$write later" : write;
          final source = WriteNowSource<Brittle>()..later = later;
          final item = CalendarEntry<Brittle>(
            id: "item-1",
            start: at(day, 600),
            end: at(day, 660),
            title: "Task",
            color: taskColor,
            payload: const Brittle(),
          );
          source.entries = <CalendarEntry<Brittle>>[item];
          final store = CachingCalendarStore<Brittle>(dataSource: source);
          store.show(weekFirst, weekLast);
          // Storing the answer compares it with the held entry, through
          // the answer's payload's ==, which throws.
          final written = item.copyWith(payload: const Brittle(brittle: true));
          source.createdId = "item-1";
          late Object? Function() failure;
          final caught = await caughtIn(() {
            failure = errorOf(switch (write) {
              "update" => store.update(written),
              "move" => store.requestMove(written),
              _ => store.create(
                CalendarEntry<Brittle>(
                  start: written.start,
                  end: written.end,
                  title: written.title,
                  color: written.color,
                  payload: written.payload,
                ),
              ),
            });
          });
          failures[name] = failure().runtimeType;
          stored[name] = store.storedEntry("item-1")!.payload.brittle;
          reported[name] = caught.reported;
          store.dispose();
        }
      }
      final names = <String>[
        for (final write in <String>["update", "move", "create"])
          for (final suffix in <String>["", " later"]) "$write$suffix",
      ];
      expect(failures, <String, Type>{for (final name in names) name: Null});
      expect(stored, <String, bool>{for (final name in names) name: true});
      expect(reported, <String, List<Type>>{
        for (final name in names) name: <Type>[BrittleFailure],
      });
    });

    test("a read whose answer's payload's == throws stores the answer, "
        "and the throw is reported", () async {
      final uncaught = <String, List<Type>>{};
      final stored = <String, bool>{};
      final reported = <String, List<Type>>{};
      for (final later in <bool>[false, true]) {
        final name = later ? "later" : "within the call";
        final item = CalendarEntry<Brittle>(
          id: "item-1",
          start: at(day, 600),
          end: at(day, 660),
          title: "Task",
          color: taskColor,
          payload: const Brittle(),
        );
        final source = WriteNowSource<Brittle>()
          ..entries = <CalendarEntry<Brittle>>[item];
        final store = CachingCalendarStore<Brittle>(dataSource: source);
        store.show(weekFirst, weekLast);
        source
          ..readLater = later
          ..entries = <CalendarEntry<Brittle>>[
            item.copyWith(payload: const Brittle(brittle: true)),
          ];
        // Applying the read compares its answer with the held entry,
        // through the answer's payload's ==, which throws.
        final caught = await caughtIn(() {
          store.invalidate(day, day);
        });
        uncaught[name] = caught.uncaught;
        stored[name] = store.storedEntry("item-1")!.payload.brittle;
        reported[name] = caught.reported;
        store.dispose();
      }
      expect(uncaught, <String, List<Type>>{
        "within the call": <Type>[],
        "later": <Type>[],
      });
      expect(stored, <String, bool>{"within the call": true, "later": true});
      expect(reported, <String, List<Type>>{
        "within the call": <Type>[BrittleFailure],
        "later": <Type>[BrittleFailure],
      });
    });

    test("a throw from the store's own handling of a read's answer escapes, "
        "within the call as later", () async {
      final uncaught = <String, List<Type>>{};
      final reported = <String, List<Type>>{};
      for (final later in <bool>[false, true]) {
        final name = later ? "later" : "within the call";
        final item = CalendarEntry<Brittle>(
          id: "item-1",
          start: at(day, 600),
          end: at(day, 660),
          title: "Task",
          color: taskColor,
          payload: const Brittle(),
        );
        final source = WriteNowSource<Brittle>()
          ..entries = <CalendarEntry<Brittle>>[item];
        final store = CachingCalendarStore<Brittle>(dataSource: source);
        store.show(weekFirst, weekLast);
        source
          ..readLater = later
          ..entries = <CalendarEntry<Brittle>>[
            item.copyWith(payload: const Brittle(brittle: true)),
          ];
        // Applying the read reports the throw of the answer's payload's ==
        // through FlutterError.onError, which throws in turn, as a host's
        // can.
        final onError = FlutterError.onError;
        FlutterError.onError = (details) {
          (reported[name] ??= <Type>[]).add(details.exception.runtimeType);
          throw StateError("Host.");
        };
        try {
          runZonedGuarded(
            () {
              store.invalidate(day, day);
            },
            (error, stack) {
              (uncaught[name] ??= <Type>[]).add(error.runtimeType);
            },
          );
          await settle();
        } finally {
          FlutterError.onError = onError;
        }
        store.dispose();
      }
      expect(reported, <String, List<Type>>{
        "within the call": <Type>[BrittleFailure],
        "later": <Type>[BrittleFailure],
      });
      expect(uncaught, <String, List<Type>>{
        "within the call": <Type>[StateError],
        "later": <Type>[StateError],
      });
    });

    test("an announced entry whose payload's == throws is stored, and the "
        "throw is reported", () async {
      final item = CalendarEntry<Brittle>(
        id: "item-1",
        start: at(day, 600),
        end: at(day, 660),
        title: "Task",
        color: taskColor,
        payload: const Brittle(),
      );
      final changes = StreamController<CalendarSourceChange<Brittle>>();
      late CachingCalendarStore<Brittle> store;
      var notifications = 0;
      final caught = await caughtIn(() {
        store = CachingCalendarStore<Brittle>(
          dataSource: WriteNowSource<Brittle>()
            ..entries = <CalendarEntry<Brittle>>[item],
          changes: changes.stream,
        );
        store.show(weekFirst, weekLast);
        store.addListener(() {
          notifications++;
        });
        // Applying the put compares it with the held entry, through its
        // payload's ==, which throws.
        changes.add(
          CalendarEntryPut<Brittle>(
            item.copyWith(payload: const Brittle(brittle: true)),
          ),
        );
      });
      expect(caught.uncaught, isEmpty);
      expect(
        (
          brittle: store.storedEntry("item-1")!.payload.brittle,
          notifications: notifications,
        ),
        (brittle: true, notifications: 1),
      );
      expect(caught.reported, <Type>[BrittleFailure]);
      await changes.close();
      store.dispose();
    });

    test("a write whose data source call throws ends the pending write "
        "within the call", () async {
      final source = WriteNowSource<String>();
      final item = task("item-1", day, 600, 660);
      source.entries = <CalendarEntry<String>>[item];
      final store = CachingCalendarStore<String>(dataSource: source);
      store.show(weekFirst, weekLast);
      const thrown = SourceFailure("Thrown.");
      source.onWrite = () {
        throw thrown;
      };
      final pending = <String, bool>{};
      final failures = <String, Object? Function()>{};
      final writes = writesOf(store, item)..remove("create");
      for (final MapEntry(key: write, value: send) in writes.entries) {
        failures[write] = errorOf(send());
        pending[write] = store.isPending("item-1");
      }
      expect(pending, <String, bool>{
        "update": false,
        "move": false,
        "delete": false,
      });
      await settle();
      expect(
        <String, Object?>{
          for (final MapEntry(key: write, value: failure) in failures.entries)
            write: failure(),
        },
        <String, Object?>{"update": thrown, "move": thrown, "delete": thrown},
      );
    });

    test("a data source future that throws from then once it answered "
        "leaves the write completed", () async {
      final source = WriteNowSource<String>()..thenThrows = true;
      final item = task("item-1", day, 600, 660);
      source.entries = <CalendarEntry<String>>[item];
      final store = CachingCalendarStore<String>(dataSource: source);
      store.show(weekFirst, weekLast);
      final thrown = <String, Type>{};
      final completed = <String, bool Function()>{};
      for (final MapEntry(key: write, value: send) in writesOf(
        store,
        item,
      ).entries) {
        try {
          completed[write] = completedOf(send());
        } on Object catch (error) {
          thrown[write] = error.runtimeType;
        }
      }
      expect(thrown, isEmpty);
      await settle();
      expect(
        <String, bool>{
          for (final MapEntry(key: write, value: done) in completed.entries)
            write: done(),
        },
        <String, bool>{
          "update": true,
          "move": true,
          "delete": true,
          "create": true,
        },
      );
    });

    test("a store disposed within a write's data source call throws "
        "nothing, and the write completes", () async {
      final thrown = <String, Type>{};
      final completed = <String, bool Function()>{};
      for (final write in <String>["update", "move", "delete", "create"]) {
        final source = WriteNowSource<String>();
        final item = task("item-1", day, 600, 660);
        source.entries = <CalendarEntry<String>>[item];
        final store = CachingCalendarStore<String>(dataSource: source);
        store.show(weekFirst, weekLast);
        source.onWrite = store.dispose;
        try {
          completed[write] = completedOf(writesOf(store, item)[write]!());
        } on Object catch (error) {
          thrown[write] = error.runtimeType;
        }
      }
      expect(thrown, isEmpty);
      await settle();
      expect(
        <String, bool>{
          for (final MapEntry(key: write, value: done) in completed.entries)
            write: done(),
        },
        <String, bool>{
          "update": true,
          "move": true,
          "delete": true,
          "create": true,
        },
      );
    });

    test("a write after dispose sends nothing and fails with a "
        "StateError", () async {
      final source = WriteNowSource<String>();
      final item = task("item-1", day, 600, 660);
      source.entries = <CalendarEntry<String>>[item];
      final store = CachingCalendarStore<String>(dataSource: source);
      store.show(weekFirst, weekLast);
      store.dispose();
      final thrown = <String, Type>{};
      final failures = <String, Object? Function()>{};
      for (final MapEntry(key: write, value: send) in writesOf(
        store,
        item,
      ).entries) {
        try {
          failures[write] = errorOf(send());
        } on Object catch (error) {
          thrown[write] = error.runtimeType;
        }
      }
      expect(source.writes, 0);
      expect(thrown, isEmpty);
      await settle();
      expect(
        <String, Type>{
          for (final MapEntry(key: write, value: failure) in failures.entries)
            write: failure().runtimeType,
        },
        <String, Type>{
          "update": StateError,
          "move": StateError,
          "delete": StateError,
          "create": StateError,
        },
      );
    });

    test("a refused write fails with a stack trace in a zone that gives "
        "it none", () async {
      final traced = <String, bool>{};
      final testZone = Zone.current;
      // A zone forked from the root gives an error no stack trace, unlike
      // the test's zone; it hands the test any error left uncaught in it.
      final zone = Zone.root.fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) {
            testZone.handleUncaughtError(error, stackTrace);
          },
        ),
      );
      zone.run(() {
        void trace(String refusal, Future<Object?> write) {
          write.then(
            (value) {},
            onError: (Object error, StackTrace stackTrace) {
              traced[refusal] = stackTrace.toString().isNotEmpty;
            },
          );
        }

        final source = WriteNowSource<String>()..later = true;
        final item = task("item-1", day, 600, 660);
        source.entries = <CalendarEntry<String>>[item];
        final store = CachingCalendarStore<String>(
          dataSource: source,
          hours: const DayHours(480, 1080),
        );
        store.show(weekFirst, weekLast);
        trace("no id", store.update(draft(day, 600, 660)));
        trace("hours", store.requestMove(retimed(item, 1100, 1160)));
        store.requestDelete("item-1");
        trace("pending", store.requestDelete("item-1"));
        final disposed = CachingCalendarStore<String>(dataSource: source);
        disposed.dispose();
        trace("disposed", disposed.create(draft(day, 720, 780)));
      });
      await settle();
      expect(traced, <String, bool>{
        "no id": true,
        "hours": true,
        "pending": true,
        "disposed": true,
      });
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

  test("CS4 a data source call that throws fails within the call, with the "
      "error it threw", () async {
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
    // The read fails within the call, as a write does.
    expect(store.status, CalendarLoadStatus.failed);
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
  });

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

    final notifications = harness.notifications;
    final refreshing = completedOf(store.refresh());
    expect(store.status, CalendarLoadStatus.loading);
    expect(harness.notifications, notifications + 1);
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

  test("FR16 a failed read the shown range waits on marks none of its "
      "days, leaving it loading, while a read sent after it is in flight "
      "over them", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final load = harness.lastCall;
    final refreshing = completedOf(store.refresh());
    final refresh = harness.lastCall;
    final notifications = harness.notifications;
    load.fail();
    await settle();
    expect(store.readFailed(weekFirst), isFalse);
    expect(store.status, CalendarLoadStatus.loading);
    expect(harness.notifications, notifications);

    refresh.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(refreshing(), isTrue);
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
      "the read sent after it, in flight over its unread days, fails "
      "too", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final load = harness.lastCall;
    errorOf(store.refresh());
    final refresh = harness.lastCall;
    load.fail();
    await settle();

    final failure = refresh.fail("Down.");
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

  test("FR34 a failed read leaves the shown range loading while reads "
      "retries asked for since cover its unread days between them, and "
      "failed with the error of the one that leaves a day unread with none "
      "asked for since in flight", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(DateTime(2026, 4, 21), DateTime(2026, 4, 25));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 26));
    final shown = harness.lastCall;
    store.retry(DateTime(2026, 4, 19), DateTime(2026, 4, 20));
    final before = harness.lastCall;
    store.retry(DateTime(2026, 4, 26), DateTime(2026, 4, 27));
    shown.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.loading);

    final failure = before.fail("Down.");
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    expect(store.loadError, same(failure));
  });

  test("FR35 a read the shown range did not ask for leaves it failed, "
      "notifying nothing, while it reads the day whose read failed", () async {
    final seen = <String, (CalendarLoadStatus, int, bool, bool)>{};
    final failedDay = DateTime(2026, 4, 23);
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
      final calls = harness.source.calls.length;

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
        store.readFailed(failedDay),
        harness.source.calls.skip(calls).any((call) {
          return !call.first!.isAfter(failedDay) &&
              !call.last!.isBefore(failedDay);
        }),
      );
      await changes.close();
    }
    expect(seen, <String, (CalendarLoadStatus, int, bool, bool)>{
      "prefetch": (CalendarLoadStatus.failed, 0, true, true),
      "invalidate": (CalendarLoadStatus.failed, 0, true, true),
      "announce": (CalendarLoadStatus.failed, 0, true, true),
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

  test("FR38 a failed shown range's loadError is the error of the latest "
      "read that marked a day of it readFailed, which a read sent before it "
      "leaves as it was, failing or not, though filling the day makes the "
      "range ready", () async {
    for (final early in <String>["fails", "fills"]) {
      final harness = Harness();
      final store = harness.store;
      store.show(DateTime(2026, 4, 21), DateTime(2026, 4, 25));
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      store.prefetch(DateTime(2026, 4, 19), DateTime(2026, 4, 20));
      final before = harness.lastCall;
      store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 26));
      final first = harness.lastCall.fail("First.");
      await settle();
      store.prefetch(DateTime(2026, 4, 26), DateTime(2026, 4, 27));
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      expect(store.readFailed(DateTime(2026, 4, 20)), isTrue);
      expect(store.status, CalendarLoadStatus.failed);

      store.prefetch(mayFirst, mayLast);
      harness.lastCall.fail("Elsewhere.");
      await settle();
      expect(store.loadError, same(first));
      if (early == "fails") {
        before.fail("Second.");
        await settle();
        expect(store.loadError, same(first));
      } else {
        before.succeed(<CalendarEntry<String>>[]);
        await settle();
        expect(store.status, CalendarLoadStatus.ready);
        expect(store.loadError, isNull);
      }
    }
  });

  test("FR39 a show, a retry or a refresh whose read fails within the call "
      "leaves that read's error", () async {
    final errors = <String, Type>{};
    for (final call in <String>["show", "retry", "refresh"]) {
      final source = SyncSource();
      final store = CachingCalendarStore<String>(dataSource: source);
      source.readError = const SourceFailure("First.");
      store.show(weekFirst, weekLast);
      await settle();
      source.readError = null;
      // An entry with no id fails the read, within the call.
      source.entries = <CalendarEntry<String>>[
        draft(DateTime(2026, 4, 21), 600, 660),
      ];
      if (call == "show") {
        store.show(DateTime(2026, 4, 21), DateTime(2026, 4, 27));
      } else if (call == "retry") {
        store.retry();
      } else {
        errorOf(store.refresh());
      }
      await settle();
      errors[call] = store.loadError.runtimeType;
      store.dispose();
    }
    expect(errors, <String, Type>{
      "show": StateError,
      "retry": StateError,
      "refresh": StateError,
    });
  });

  test("FR39a a show whose read fails within the call leaves the range "
      "loading while its read of the changed days covers the failed "
      "ones", () async {
    final source = ScriptedSource();
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    source.script.addAll(<List<CalendarEntry<String>>?>[
      <CalendarEntry<String>>[],
      <CalendarEntry<String>>[],
    ]);
    store.prefetch(weekFirst, weekFirst);
    store.prefetch(weekLast, weekLast);
    store.invalidate(weekFirst, weekLast);
    // The show's read of its unread and changed days answers an entry
    // with no id within the call, which fails it; its read of the
    // changed days, sent next, stays in flight.
    source.script.addAll(<List<CalendarEntry<String>>?>[
      <CalendarEntry<String>>[draft(DateTime(2026, 4, 21), 600, 660)],
      null,
    ]);

    store.show(weekFirst, weekLast);
    expect(source.reads, 4);
    expect(store.readFailed(DateTime(2026, 4, 21)), isFalse);
    expect(store.status, CalendarLoadStatus.loading);
    expect(store.loadError, isNull);
  });

  test("FR40 showing a range after a failure tells the listeners only that "
      "it loads, though a read answers within the call", () async {
    final harness = Harness();
    final store = harness.store;
    store.prefetch(DateTime(2026, 4, 13), DateTime(2026, 4, 19));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.invalidate(DateTime(2026, 4, 13), DateTime(2026, 4, 13));
    store.show(DateTime(2026, 4, 20), DateTime(2026, 4, 21));
    harness.lastCall.fail();
    await settle();
    store.prefetch(DateTime(2026, 4, 20), DateTime(2026, 4, 28));
    final seen = <CalendarLoadStatus>[];
    store.addListener(() {
      seen.add(store.status);
    });

    harness.source.answerNow = <CalendarEntry<String>>[
      task("item-1", DateTime(2026, 4, 13), 600, 660),
    ];
    // One read answers within the call, of the changed day and the failed
    // ones; the prefetch's days after them are left loading.
    store.show(DateTime(2026, 4, 13), DateTime(2026, 4, 28));
    expect(harness.source.readsNow, <(DateTime, DateTime)>[
      (DateTime(2026, 4, 13), DateTime(2026, 4, 21)),
    ]);
    expect(idsOn(store, DateTime(2026, 4, 13)), <String>["item-1"]);
    expect(seen, <CalendarLoadStatus>[CalendarLoadStatus.loading]);
  });

  test("FR41 a call whose read or write answers within it notifies once, "
      "and so does a read's answer whose read of changed days answers "
      "within it", () async {
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final moved = retimed(item, 720, 780);
    final updated = retimed(item, 800, 860);
    // By call: how often the store notified within it, and in all once the
    // futures it left ran; the days of the reads the source answered within
    // it; and, as a write returns, item-1 as stored and whether it is pending.
    final counts = <String, int>{};
    final settled = <String, int>{};
    final reads = <String, List<(DateTime, DateTime)>>{};
    final written = <String, (CalendarEntry<String>?, bool)>{};
    final writes = <String, Future<Object?>>{};
    var harness = Harness();

    Future<List<(DateTime, DateTime)>> count(
      String name,
      void Function() call,
    ) async {
      final notifications = harness.notifications;
      final answered = harness.source.readsNow.length;
      call();
      counts[name] = harness.notifications - notifications;
      final within = harness.source.readsNow.sublist(answered);
      await settle();
      settled[name] = harness.notifications - notifications;
      return within;
    }

    void noteWrite(String name) {
      written[name] = (
        harness.store.storedEntry("item-1"),
        harness.store.isPending("item-1"),
      );
    }

    harness.store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    harness.source.answerNow = <CalendarEntry<String>>[item];
    reads["retry"] = await count("retry", () {
      harness.store.retry();
    });
    harness.source.answerNow = <CalendarEntry<String>>[];
    reads["show"] = await count("show", () {
      harness.store.show(mayFirst, mayLast);
    });
    await count("requestMove", () {
      writes["requestMove"] = outcomeOf(harness.store.requestMove(moved));
      noteWrite("requestMove");
    });
    await count("update", () {
      writes["update"] = outcomeOf(harness.store.update(updated));
      noteWrite("update");
    });
    await count("requestDelete", () {
      writes["requestDelete"] = outcomeOf(
        harness.store.requestDelete("item-1"),
      );
      noteWrite("requestDelete");
    });

    harness = Harness();
    harness.store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    harness.source.answerNow = <CalendarEntry<String>>[item];
    reads["refresh"] = await count("refresh", () {
      harness.store.refresh();
    });

    harness = Harness();
    harness.store.show(weekFirst, weekLast);
    final week = harness.lastCall;
    harness.store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    harness.source.answerNow = <CalendarEntry<String>>[item];
    final notifications = harness.notifications;
    week.succeed(<CalendarEntry<String>>[]);
    await settle();
    settled["answer"] = harness.notifications - notifications;
    reads["answer"] = harness.source.readsNow;

    expect(reads, <String, List<(DateTime, DateTime)>>{
      "retry": [(weekFirst, weekLast)],
      "show": [(mayFirst, mayLast)],
      "refresh": [(weekFirst, weekLast)],
      "answer": [(DateTime(2026, 4, 21), DateTime(2026, 4, 21))],
    });
    expect(written, <String, (CalendarEntry<String>?, bool)>{
      "requestMove": (moved, false),
      "update": (updated, false),
      "requestDelete": (null, false),
    });
    expect(
      <String, Object?>{
        for (final MapEntry(key: write, value: outcome) in writes.entries)
          write: await outcome,
      },
      <String, Object?>{
        "requestMove": moved,
        "update": updated,
        "requestDelete": null,
      },
    );
    expect(counts, <String, int>{
      "retry": 1,
      "show": 1,
      "requestMove": 1,
      "update": 1,
      "requestDelete": 1,
      "refresh": 1,
    });
    expect(settled, <String, int>{
      "retry": 1,
      "show": 1,
      "requestMove": 1,
      "update": 1,
      "requestDelete": 1,
      "refresh": 1,
      "answer": 1,
    });
  });

  test("FR42 a write's contradicted answer whose days are read again within "
      "the call notifies once", () async {
    final counts = <String, int>{};
    final reads = <String, List<(DateTime, DateTime)>>{};
    for (final write in <String>["move", "update", "create", "delete"]) {
      final harness = Harness();
      final store = harness.store;
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      final moved = onDay(item, DateTime(2026, 4, 23));
      final created = draft(DateTime(2026, 4, 23), 600, 660);
      final stored = created.copyWith(id: "item-2");
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[
        if (write != "create") item,
      ]);
      await settle();
      if (write == "move") {
        store.requestMove(moved);
      } else if (write == "update") {
        store.update(moved);
      } else if (write == "create") {
        store.create(created);
      } else {
        store.requestDelete("item-1");
      }
      final sent = harness.lastCall;
      // A read sent since the write answers what contradicts its answer.
      final day = DateTime(2026, 4, write == "delete" ? 21 : 23);
      store.invalidate(day, day);
      harness.lastCall.succeed(<CalendarEntry<String>>[
        if (write == "delete") item,
      ]);
      await settle();

      harness.source.answerNow = <CalendarEntry<String>>[
        if (write == "create") stored,
      ];
      final notifications = harness.notifications;
      sent.succeed(
        write == "create"
            ? stored
            : write == "delete"
            ? null
            : moved,
      );
      await settle();
      counts[write] = harness.notifications - notifications;
      reads[write] = harness.source.readsNow;
    }
    // Each answer sends one read, from the first to the last day of the
    // entry the store holds and of the answer, where there is one.
    expect(reads, <String, List<(DateTime, DateTime)>>{
      "move": [(DateTime(2026, 4, 21), DateTime(2026, 4, 23))],
      "update": [(DateTime(2026, 4, 21), DateTime(2026, 4, 23))],
      "create": [(DateTime(2026, 4, 23), DateTime(2026, 4, 23))],
      "delete": [(DateTime(2026, 4, 21), DateTime(2026, 4, 21))],
    });
    expect(counts, <String, int>{
      "move": 1,
      "update": 1,
      "create": 1,
      "delete": 1,
    });
  });

  test("FR43 a read sent in the background over failed days leaves them "
      "readFailed, notifying nothing, until it fills them, and its failure "
      "on days marked already changes nothing", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final first = harness.lastCall.fail("First.");
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    final notifications = harness.notifications;

    store.prefetch(weekFirst, weekLast);
    expect(harness.source.calls, hasLength(2));
    expect(store.readFailed(weekFirst), isTrue);
    expect(harness.notifications, notifications);
    harness.lastCall.fail("Second.");
    await settle();
    expect(store.loadError, same(first));
    expect(harness.notifications, notifications);

    store.prefetch(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.readFailed(weekFirst), isFalse);
    expect(harness.notifications, notifications + 1);
  });

  test("FR44 a retry of a range outside the shown range ends the "
      "readFailed marks of its days and of the shown range's, notifying "
      "once, and reads both", () async {
    final harness = Harness();
    final store = harness.store;
    final mayWeekFirst = DateTime(2026, 5, 4);
    final mayWeekLast = DateTime(2026, 5, 10);
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    store.prefetch(mayWeekFirst, mayWeekLast);
    harness.lastCall.fail();
    await settle();
    expect(store.readFailed(mayWeekFirst), isTrue);
    final notifications = harness.notifications;
    final calls = harness.source.calls.length;

    store.retry(mayWeekFirst, mayWeekLast);
    expect(store.readFailed(mayWeekFirst), isFalse);
    expect(store.readFailed(weekFirst), isFalse);
    expect(store.status, CalendarLoadStatus.loading);
    expect(store.loadError, isNull);
    expect(harness.notifications, notifications + 1);
    expect(
      <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(calls))
          (call.first, call.last),
      ],
      <(DateTime?, DateTime?)>[
        (weekFirst, weekLast),
        (mayWeekFirst, mayWeekLast),
      ],
    );
  });

  test("FR45 a retry reads the shown range and the range it is given as "
      "one read where their spans touch, and as two apart", () async {
    final reads = <String, List<(DateTime?, DateTime?)>>{};
    for (final given in <String>["touching", "apart"]) {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.fail();
      await settle();
      final calls = harness.source.calls.length;
      store.retry(
        DateTime(2026, 4, given == "touching" ? 27 : 28),
        DateTime(2026, 5, 3),
      );
      reads[given] = <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(calls))
          (call.first, call.last),
      ];
    }
    expect(reads, <String, List<(DateTime?, DateTime?)>>{
      "touching": [(weekFirst, DateTime(2026, 5, 3))],
      "apart": [
        (weekFirst, weekLast),
        (DateTime(2026, 4, 28), DateTime(2026, 5, 3)),
      ],
    });
  });

  test("FR46 a retry takes over a read in flight over unread days it ends "
      "no mark on, with no second read, and reads the days whose marks it "
      "ends again though a read in flight covers them", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final calls = harness.source.calls.length;
    store.retry();
    store.retry(weekFirst, DateTime(2026, 4, 22));
    expect(harness.source.calls, hasLength(calls));

    harness.lastCall.fail();
    await settle();
    store.prefetch(weekFirst, weekLast);
    final background = harness.source.calls.length;
    store.retry();
    expect(harness.source.calls, hasLength(background + 1));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (weekFirst, weekLast),
    );
    expect(store.status, CalendarLoadStatus.loading);

    // A retry of days a read in the background covers takes that read
    // over, so a read sent before it that fails marks none of them.
    final other = Harness();
    other.store.prefetch(weekFirst, weekFirst);
    final older = other.lastCall;
    other.store.prefetch(weekFirst, weekLast);
    final sent = other.source.calls.length;
    other.store.retry(weekFirst, weekLast);
    expect(other.source.calls, hasLength(sent));
    older.fail();
    await settle();
    expect(other.store.readFailed(weekFirst), isFalse);
  });

  test("FR47 a retry whose two reads answer within the call notifies "
      "once", () async {
    final harness = Harness();
    final store = harness.store;
    final mayWeekFirst = DateTime(2026, 5, 4);
    final mayWeekLast = DateTime(2026, 5, 10);
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    store.prefetch(mayWeekFirst, mayWeekLast);
    harness.lastCall.fail();
    await settle();
    final notifications = harness.notifications;

    harness.source.answerNow = <CalendarEntry<String>>[];
    store.retry(mayWeekFirst, mayWeekLast);
    expect(harness.source.readsNow, <(DateTime, DateTime)>[
      (weekFirst, weekLast),
      (mayWeekFirst, mayWeekLast),
    ]);
    expect(harness.notifications, notifications + 1);
  });

  test("FR48 a retry given one of first and last throws an ArgumentError, "
      "and one whose first is after its last gives no day, as a prefetch "
      "does", () {
    final harness = Harness();
    final store = harness.store;
    expect(() {
      store.retry(weekFirst);
    }, throwsArgumentError);
    expect(() {
      store.retry(null, weekLast);
    }, throwsArgumentError);
    store.retry(weekLast, weekFirst);
    store.prefetch(weekLast, weekFirst);
    store.retry();
    expect(harness.source.calls, isEmpty);
    expect(harness.notifications, 0);
  });

  test("FR49 a read the shown range asked for that fails while a read sent "
      "before it is in flight over one of its days marks that day "
      "readFailed, so the range stays failed while reads in the background "
      "fill the others", () async {
    final harness = Harness();
    final store = harness.store;
    store.prefetch(weekFirst, weekFirst);
    final older = harness.lastCall;
    store.show(weekFirst, weekLast);
    final failure = harness.lastCall.fail();
    await settle();
    expect(store.readFailed(weekFirst), isTrue);

    store.prefetch(DateTime(2026, 4, 21), weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    expect(store.loadError, same(failure));

    older.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
  });

  test("FR50 a read the shown range asked for that fails while a read sent "
      "after it in the background is in flight over some of its days marks "
      "those days readFailed, so the range stays failed while another read "
      "in the background fills the others", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    final shown = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 19), DateTime(2026, 4, 21));
    final background = harness.lastCall;
    final failure = shown.fail();
    await settle();
    expect(store.readFailed(DateTime(2026, 4, 21)), isTrue);

    store.prefetch(DateTime(2026, 4, 22), weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.failed);
    expect(store.loadError, same(failure));

    background.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(store.status, CalendarLoadStatus.ready);
  });

  test("FR51 a show or a retry that takes over a read in flight after a "
      "read was sent keeps that read's failure from marking readFailed the "
      "days the read taken over covers", () async {
    final marks = <String, (bool, bool)>{};
    for (final call in <String>["show", "retry"]) {
      final harness = Harness();
      final store = harness.store;
      store.prefetch(weekFirst, weekLast);
      store.show(DateTime(2026, 4, 23), DateTime(2026, 4, 29));
      final failing = harness.lastCall;
      final calls = harness.source.calls.length;
      if (call == "show") {
        store.show(weekFirst, weekLast);
      } else {
        store.retry(weekFirst, weekLast);
      }
      expect(harness.source.calls, hasLength(calls));
      failing.fail();
      await settle();
      marks[call] = (
        store.readFailed(DateTime(2026, 4, 23)),
        store.readFailed(DateTime(2026, 4, 27)),
      );
    }
    expect(marks, <String, (bool, bool)>{
      "show": (false, true),
      "retry": (false, true),
    });
  });

  test("FR52 a retry over a range of more days than are marked readFailed "
      "reads again the marked days of the range alone, though a read in "
      "flight covers them", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 4, 28));
    harness.lastCall.fail();
    store.prefetch(DateTime(2026, 5, 10), DateTime(2026, 5, 10));
    harness.lastCall.fail();
    await settle();
    store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 4, 28));
    final calls = harness.source.calls.length;

    store.retry(weekFirst, DateTime(2026, 4, 28));
    expect(harness.source.calls, hasLength(calls + 1));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (DateTime(2026, 4, 27), DateTime(2026, 4, 28)),
    );
  });

  test("FR53 a show over days marked readFailed that a read in flight "
      "covers reads them with a read of its own, so the failure of the "
      "read in flight marks none of them, and the range is ready once its "
      "own read answers, whether the read in flight fails before or after "
      "it", () async {
    final nextFirst = DateTime(2026, 4, 27);
    final nextLast = DateTime(2026, 5, 3);
    for (final staleFails in <String>["before", "after"]) {
      final harness = Harness();
      final store = harness.store;
      List<DateTime> marked() {
        return <DateTime>[
          for (var i = 0; i < 7; i++)
            DateTime(nextFirst.year, nextFirst.month, nextFirst.day + i),
        ].where(store.readFailed).toList();
      }

      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      store.prefetch(nextFirst, nextLast);
      harness.lastCall.fail();
      await settle();
      store.prefetch(nextFirst, nextLast);
      final stale = harness.lastCall;
      expect(
        (stale.first, stale.last, stale.completer.isCompleted),
        (nextFirst, nextLast, false),
      );
      expect(store.readFailed(nextFirst), isTrue);

      store.show(nextFirst, nextLast);
      expect(harness.source.calls, hasLength(4));
      final fresh = harness.lastCall;
      expect((fresh.first, fresh.last), (nextFirst, nextLast));
      expect(store.readFailed(nextFirst), isFalse);
      expect(store.status, CalendarLoadStatus.loading);

      if (staleFails == "before") {
        stale.fail();
        await settle();
        expect(marked(), isEmpty);
        fresh.succeed(<CalendarEntry<String>>[]);
        await settle();
        expect(store.status, CalendarLoadStatus.ready);
      } else {
        fresh.succeed(<CalendarEntry<String>>[]);
        await settle();
        expect(store.status, CalendarLoadStatus.ready);
        stale.fail();
        await settle();
        expect(store.status, CalendarLoadStatus.ready);
      }
    }
  });

  test("FR54 a show whose range holds no day marked readFailed takes over "
      "the read in flight that covers its unread days, sending no read, "
      "though that read covers marked days outside the range", () async {
    final harness = Harness();
    final store = harness.store;
    final mayWeekFirst = DateTime(2026, 5, 4);
    final mayWeekLast = DateTime(2026, 5, 10);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.prefetch(mayWeekFirst, mayWeekLast);
    harness.lastCall.fail();
    await settle();
    store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 4, 30));
    final older = harness.lastCall;
    store.prefetch(DateTime(2026, 4, 27), mayWeekLast);
    final covering = harness.lastCall;
    expect(
      (covering.first, covering.last, covering.completer.isCompleted),
      (DateTime(2026, 4, 27), mayWeekLast, false),
    );
    expect(store.readFailed(mayWeekFirst), isTrue);
    final calls = harness.source.calls.length;

    store.show(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
    expect(harness.source.calls, hasLength(calls));
    // The read taken over was asked for after the older one was sent, so
    // the older one's failure marks none of the days it covers.
    older.fail();
    await settle();
    expect(store.status, CalendarLoadStatus.loading);
  });

  test("FR55 a show reads its days marked readFailed under a read in "
      "flight and its changed days no read in flight covers as one read, "
      "with no other read where the changed days lie around the marked "
      "ones", () async {
    final reads = <String, List<(DateTime?, DateTime?)>>{};
    for (final changed in <String>["before", "around"]) {
      final harness = Harness();
      final store = harness.store;
      store.prefetch(DateTime(2026, 4, 13), DateTime(2026, 4, 19));
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      store.prefetch(DateTime(2026, 4, 27), DateTime(2026, 5, 3));
      harness.lastCall.succeed(<CalendarEntry<String>>[]);
      await settle();
      store.invalidate(DateTime(2026, 4, 13), DateTime(2026, 4, 13));
      if (changed == "around") {
        store.invalidate(DateTime(2026, 4, 27), DateTime(2026, 4, 27));
      }
      store.prefetch(weekFirst, weekLast);
      harness.lastCall.fail();
      await settle();
      store.prefetch(weekFirst, weekLast);
      final stale = harness.lastCall;
      expect(
        (stale.first, stale.last, stale.completer.isCompleted),
        (weekFirst, weekLast, false),
      );
      expect(store.readFailed(weekFirst), isTrue);
      final calls = harness.source.calls.length;

      store.show(DateTime(2026, 4, 13), DateTime(2026, 4, 27));
      reads[changed] = <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(calls))
          (call.first, call.last),
      ];
    }
    expect(reads["before"], <(DateTime?, DateTime?)>[
      (DateTime(2026, 4, 13), weekLast),
    ]);
    expect(reads["around"], <(DateTime?, DateTime?)>[
      (DateTime(2026, 4, 13), DateTime(2026, 4, 27)),
    ]);
  });

  test("FR56 a read sent since a move or a create that answers after the "
      "write's answer, on a day the answer covers without the entry, "
      "contradicts it as one answering before does: the store keeps the "
      "answer and reads its days again", () async {
    final stored = <String, CalendarEntry<String>?>{};
    final reads = <String, List<(DateTime?, DateTime?)>>{};
    final day = DateTime(2026, 4, 23);
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final moved = onDay(item, day);
    final created = draft(day, 600, 660);
    for (final write in <String>["move", "create"]) {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[
        if (write == "move") item,
      ]);
      await settle();
      if (write == "move") {
        store.requestMove(moved);
      } else {
        store.create(created);
      }
      final sent = harness.lastCall;
      store.invalidate(day, day);
      final read = harness.lastCall;
      expect(harness.source.calls, hasLength(3), reason: write);
      final answer = write == "move" ? moved : created.copyWith(id: "item-1");
      sent.succeed(answer);
      await settle();
      expect(store.storedEntry("item-1"), answer, reason: write);
      final calls = harness.source.calls.length;

      read.succeed(<CalendarEntry<String>>[]);
      await settle();
      stored[write] = store.storedEntry("item-1");
      reads[write] = <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(calls))
          (call.first, call.last),
      ];
    }
    expect(stored, <String, CalendarEntry<String>?>{
      "move": moved,
      "create": created.copyWith(id: "item-1"),
    });
    expect(reads, <String, List<(DateTime?, DateTime?)>>{
      "move": [(day, day)],
      "create": [(day, day)],
    });
  });

  test("FR57 a read sent since a move or a delete that answers after the "
      "write's answer with the entry as it was contradicts the answer: the "
      "store keeps the answer and reads the days of both again", () async {
    final stored = <String, CalendarEntry<String>?>{};
    final reads = <String, List<(DateTime?, DateTime?)>>{};
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final moved = onDay(item, DateTime(2026, 4, 23));
    for (final write in <String>["move", "delete"]) {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      if (write == "move") {
        store.requestMove(moved);
      } else {
        store.requestDelete("item-1");
      }
      final sent = harness.lastCall;
      store.invalidate(
        DateTime(2026, 4, 21),
        write == "move" ? DateTime(2026, 4, 23) : DateTime(2026, 4, 21),
      );
      final read = harness.lastCall;
      expect(harness.source.calls, hasLength(3), reason: write);
      sent.succeed(write == "move" ? moved : null);
      await settle();
      final calls = harness.source.calls.length;

      // The source served the read before the write.
      read.succeed(<CalendarEntry<String>>[item]);
      await settle();
      stored[write] = store.storedEntry("item-1");
      reads[write] = <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(calls))
          (call.first, call.last),
      ];
    }
    expect(stored, <String, CalendarEntry<String>?>{
      "move": moved,
      "delete": null,
    });
    expect(reads, <String, List<(DateTime?, DateTime?)>>{
      "move": [(DateTime(2026, 4, 21), DateTime(2026, 4, 23))],
      "delete": [(DateTime(2026, 4, 21), DateTime(2026, 4, 21))],
    });
  });

  test("FR58 a read sent since a move that answers after the move's answer "
      "and agrees with it sends no read again", () async {
    final outcomes = <String, (CalendarEntry<String>?, int)>{};
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final moved = onDay(item, DateTime(2026, 4, 23));
    for (final read in <String>["with the entry", "off its day"]) {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      harness.lastCall.succeed(<CalendarEntry<String>>[item]);
      await settle();
      store.requestMove(moved);
      final sent = harness.lastCall;
      final day = DateTime(2026, 4, read == "with the entry" ? 23 : 21);
      store.invalidate(day, day);
      final since = harness.lastCall;
      expect(harness.source.calls, hasLength(3), reason: read);
      sent.succeed(moved);
      await settle();

      since.succeed(<CalendarEntry<String>>[
        if (read == "with the entry") moved,
      ]);
      await settle();
      outcomes[read] = (
        store.storedEntry("item-1"),
        harness.source.calls.length,
      );
    }
    expect(outcomes, <String, (CalendarEntry<String>?, int)>{
      "with the entry": (moved, 3),
      "off its day": (moved, 3),
    });
  });

  test("FR59 an older read's answer of an entry that a newer read forgot "
      "on other days is stored, with no read again", () async {
    final harness = Harness();
    final store = harness.store;
    final earlier = DateTime(2026, 4, 13);
    final item = task("item-1", earlier, 600, 660);
    store.prefetch(earlier, earlier);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();

    // The source moves item-1 to the 21st, telling the store nothing.
    final moved = onDay(item, DateTime(2026, 4, 21));
    store.show(weekFirst, weekLast);
    final older = harness.lastCall;
    store.invalidate(earlier, earlier);
    store.prefetch(earlier, earlier);
    final newer = harness.lastCall;
    expect(
      (newer.first, newer.last, harness.source.calls.length),
      (earlier, earlier, 3),
    );
    newer.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect(idsOn(store, earlier), isEmpty);

    older.succeed(<CalendarEntry<String>>[moved]);
    await settle();
    expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);
    expect(harness.source.calls, hasLength(3));
  });

  test("FR60 so is one the store sent before a change of all, once a "
      "prefetch of the days the change left changed forgot the "
      "entry", () async {
    final changes = StreamController<CalendarSourceChange<String>>();
    addTearDown(changes.close);
    final harness = Harness(changes: changes.stream);
    final store = harness.store;
    final between = DateTime(2026, 4, 13);
    final betweenLast = DateTime(2026, 4, 19);
    store.show(between, betweenLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[
      task("item-1", between, 600, 660),
    ]);
    await settle();
    store.show(DateTime(2026, 4, 6), DateTime(2026, 4, 12));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    // Another client moves item-1 to the 21st, and the source announces a
    // change of all.
    final moved = task("item-1", DateTime(2026, 4, 21), 600, 660);
    changes.add(const CalendarAllChanged<String>());
    await settle();
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(weekFirst, weekLast);
    final week = harness.lastCall;
    store.prefetch(between, betweenLast);
    final strip = harness.lastCall;
    expect(
      (strip.first, strip.last, harness.source.calls.length),
      (between, betweenLast, 5),
    );
    strip.succeed(<CalendarEntry<String>>[]);
    await settle();

    week.succeed(<CalendarEntry<String>>[moved]);
    await settle();
    expect(idsOn(store, DateTime(2026, 4, 21)), <String>["item-1"]);
    expect(harness.source.calls, hasLength(5));
  });

  test("FR61 an older read's answer of an entry that a newer read forgot, "
      "on a day the newer read filled, is not stored, and the older read's "
      "days of the entry are read again", () async {
    final harness = Harness();
    final store = harness.store;
    final earlier = DateTime(2026, 4, 13);
    store.prefetch(earlier, earlier);
    harness.lastCall.succeed(<CalendarEntry<String>>[
      task("item-1", earlier, 600, 660),
    ]);
    await settle();

    // From the 19th 22:00 to the 20th 01:00, as the source held it when
    // the older read was sent.
    final spanning = task("item-1", DateTime(2026, 4, 19), 1320, 1500);
    store.show(weekFirst, weekLast);
    final older = harness.lastCall;
    store.invalidate(earlier, earlier);
    store.prefetch(earlier, DateTime(2026, 4, 19));
    final newer = harness.lastCall;
    expect(
      (newer.first, newer.last, harness.source.calls.length),
      (earlier, DateTime(2026, 4, 19), 3),
    );
    newer.succeed(<CalendarEntry<String>>[]);
    await settle();

    older.succeed(<CalendarEntry<String>>[spanning]);
    await settle();
    expect(store.storedEntry("item-1"), isNull);
    expect(harness.source.calls, hasLength(4));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (weekFirst, weekFirst),
    );
  });

  test("FR62 an older read's answer of an entry that a newer read forgot, "
      "once stored, outlives the answer of a read sent before it", () async {
    final harness = Harness();
    final store = harness.store;
    final earlier = DateTime(2026, 4, 13);
    final item = task("item-1", earlier, 600, 660);
    store.prefetch(earlier, earlier);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();

    // The source held item-1 on the 28th when the oldest read was sent,
    // and on the 21st when the older one was.
    final oldest = DateTime(2026, 4, 28);
    store.prefetch(oldest, oldest);
    final oldestRead = harness.lastCall;
    final moved = onDay(item, DateTime(2026, 4, 21));
    store.show(weekFirst, weekLast);
    final older = harness.lastCall;
    store.invalidate(earlier, earlier);
    store.prefetch(earlier, earlier);
    final newer = harness.lastCall;
    expect(
      (newer.first, newer.last, harness.source.calls.length),
      (earlier, earlier, 4),
    );
    newer.succeed(<CalendarEntry<String>>[]);
    await settle();
    older.succeed(<CalendarEntry<String>>[moved]);
    await settle();
    expect(store.storedEntry("item-1"), moved);

    oldestRead.succeed(<CalendarEntry<String>>[onDay(item, oldest)]);
    await settle();
    expect(store.storedEntry("item-1"), moved);
    expect(harness.source.calls, hasLength(4));
  });

  test("FR63 a move whose answer a read sent since contradicts completes "
      "with the data source's answer, while the store keeps what it "
      "holds", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    final moved = onDay(item, DateTime(2026, 4, 23));
    final moving = outcomeOf(store.requestMove(moved));
    final write = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 23), DateTime(2026, 4, 23));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();

    write.succeed(moved);
    expect(await moving, moved);
    expect(store.storedEntry("item-1"), item);
  });

  test("FR64 a delete's answer after a read sent since removed the entry "
      "from its days is contradicted by a read sent since that answers the "
      "entry on other days, which are read again", () async {
    final harness = Harness();
    final store = harness.store;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[item]);
    await settle();
    store.requestDelete("item-1");
    final write = harness.lastCall;
    // The source held item-1 on the 25th when the older read was sent, and
    // nowhere when the newer one was.
    final elsewhere = DateTime(2026, 4, 25);
    store.invalidate(elsewhere, elsewhere);
    final older = harness.lastCall;
    store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 21));
    final newer = harness.lastCall;
    expect(
      (newer.first, newer.last, harness.source.calls.length),
      (DateTime(2026, 4, 21), DateTime(2026, 4, 21), 4),
    );
    newer.succeed(<CalendarEntry<String>>[]);
    await settle();
    write.succeed();
    await settle();

    older.succeed(<CalendarEntry<String>>[onDay(item, elsewhere)]);
    await settle();
    expect(store.storedEntry("item-1"), isNull);
    expect(harness.source.calls, hasLength(5));
    expect(
      (harness.lastCall.first, harness.lastCall.last),
      (elsewhere, elsewhere),
    );
  });

  test("FR65 a failed shown range's loadError is the error of the latest "
      "failure among the marks on its unread days, as reads fill "
      "them", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(DateTime(2026, 4, 21), DateTime(2026, 4, 25));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    store.show(weekFirst, weekLast);
    final shown = harness.lastCall;
    store.retry(DateTime(2026, 4, 19), weekFirst);
    final early = harness.lastCall;
    store.retry(weekLast, DateTime(2026, 4, 27));
    final late = harness.lastCall;
    shown.fail();
    await settle();
    final first = early.fail("First.");
    await settle();
    final second = late.fail("Second.");
    await settle();
    expect(
      (store.readFailed(weekFirst), store.readFailed(weekLast)),
      (true, true),
    );
    expect(store.loadError, same(second));

    // A read in the background fills the 26th, the only shown day the
    // second failure marked.
    store.prefetch(weekLast, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    expect((store.status, store.loadError), (CalendarLoadStatus.failed, first));
  });

  test("FR66 a retry notifies only where it changes the status or the "
      "loadError, or leaves a mark it ended ended", () async {
    final counts = <String, int>{};
    final mayWeekFirst = DateTime(2026, 5, 4);
    final mayWeekLast = DateTime(2026, 5, 10);
    for (final retried in <String>["marked again", "new error", "in flight"]) {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      if (retried == "new error") {
        harness.lastCall.fail();
      } else {
        harness.lastCall.succeed(<CalendarEntry<String>>[]);
        await settle();
        store.prefetch(mayWeekFirst, mayWeekLast);
        harness.lastCall.fail();
      }
      await settle();
      final notifications = harness.notifications;
      final calls = harness.source.calls.length;
      if (retried != "in flight") {
        // An entry with no id fails the read within the call.
        harness.source.answerNow = <CalendarEntry<String>>[
          draft(weekFirst, 600, 660),
        ];
      }

      if (retried == "new error") {
        store.retry();
        expect(
          (store.status, store.loadError.runtimeType),
          (CalendarLoadStatus.failed, StateError),
          reason: retried,
        );
      } else {
        store.retry(mayWeekFirst, mayWeekLast);
        expect(
          (
            store.readFailed(mayWeekFirst),
            store.status,
            harness.source.calls.length - calls,
            harness.source.readsNow.length,
          ),
          retried == "marked again"
              ? (true, CalendarLoadStatus.ready, 0, 1)
              : (false, CalendarLoadStatus.ready, 1, 0),
          reason: retried,
        );
      }
      counts[retried] = harness.notifications - notifications;
    }
    expect(counts, <String, int>{
      "marked again": 0,
      "new error": 1,
      "in flight": 1,
    });
  });

  test("FR67 a store disposed within a read's data source call sends no "
      "other read", () async {
    final harness = Harness();
    final store = harness.store;
    final mayWeekFirst = DateTime(2026, 5, 4);
    final mayWeekLast = DateTime(2026, 5, 10);
    store.show(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    store.prefetch(mayWeekFirst, mayWeekLast);
    harness.lastCall.fail();
    await settle();
    final calls = harness.source.calls.length;
    var reads = 0;
    harness.source.onRead = () {
      reads++;
      if (reads == 1) {
        store.dispose();
      }
    };

    // The retry reads the shown range and the range it is given apart.
    store.retry(mayWeekFirst, mayWeekLast);
    expect((reads, harness.source.calls.length - calls), (1, 1));
  });

  test("FR68 a read future that throws from then once it answered is taken "
      "at its answer, and the throw escapes no call", () async {
    final thrown = <String, Object>{};
    final stored = <String, CalendarEntry<String>?>{};
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final renamed = item.copyWith(title: "Renamed");
    for (final call in <String>[
      "show",
      "prefetch",
      "retry",
      "refresh",
      "invalidate",
    ]) {
      final source = WriteNowSource<String>()
        ..entries = <CalendarEntry<String>>[item];
      final store = CachingCalendarStore<String>(dataSource: source);
      if (call != "show") {
        store.show(weekFirst, weekLast);
      }
      source
        ..readThenThrows = true
        ..entries = <CalendarEntry<String>>[renamed];
      try {
        switch (call) {
          case "show":
            store.show(weekFirst, weekLast);
          case "prefetch":
            store.prefetch(mayFirst, mayLast);
          case "retry":
            store.retry(mayFirst, mayLast);
          case "refresh":
            errorOf(store.refresh());
          default:
            store.invalidate(weekFirst, weekLast);
        }
      } on Object catch (error) {
        thrown[call] = error;
      }
      stored[call] = store.storedEntry("item-1");
      store.dispose();
    }
    expect(thrown, isEmpty);
    expect(stored, <String, CalendarEntry<String>?>{
      "show": renamed,
      "prefetch": renamed,
      "retry": renamed,
      "refresh": renamed,
      "invalidate": renamed,
    });
  });

  test("FR69 a show over days a read in the background failed to read "
      "ends their marks, and reads them with a read of its own", () async {
    final harness = Harness();
    final store = harness.store;
    store.prefetch(weekFirst, weekLast);
    harness.lastCall.fail();
    await settle();
    expect(store.readFailed(weekFirst), isTrue);
    final calls = harness.source.calls.length;

    store.show(weekFirst, weekLast);
    expect(
      (
        store.readFailed(weekFirst),
        store.status,
        harness.source.calls.length - calls,
        (harness.lastCall.first, harness.lastCall.last),
      ),
      (false, CalendarLoadStatus.loading, 1, (weekFirst, weekLast)),
    );
  });

  test("FR70 a retry reads the changed days of the range it is "
      "given", () async {
    final harness = Harness();
    final store = harness.store;
    final mayWeekFirst = DateTime(2026, 5, 4);
    final mayWeekLast = DateTime(2026, 5, 10);
    store.show(weekFirst, weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    store.prefetch(mayWeekFirst, mayWeekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    await settle();
    final changed = DateTime(2026, 5, 6);
    store.invalidate(changed, changed);
    final calls = harness.source.calls.length;

    store.retry(mayWeekFirst, mayWeekLast);
    expect(
      <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(calls))
          (call.first, call.last),
      ],
      <(DateTime?, DateTime?)>[(changed, changed)],
    );
  });

  test("FR71 a shown range is failed while one of its unread days is "
      "readFailed, though an unread day before it is not and a read of it "
      "is in flight", () async {
    final harness = Harness();
    final store = harness.store;
    store.show(weekFirst, weekLast);
    // A read sent after the show's, over the range's last days and the
    // next one.
    store.prefetch(DateTime(2026, 4, 25), DateTime(2026, 4, 27));
    final failure = harness.lastCall.fail();
    await settle();

    expect(
      (store.status, store.loadError),
      (CalendarLoadStatus.failed, failure),
    );
  });

  test("FR72 a retry reads the days marked readFailed and the longer span "
      "of the range's other unread and changed days around them as one "
      "read", () async {
    final harness = Harness();
    final store = harness.store;
    store.prefetch(weekFirst, DateTime(2026, 4, 22));
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    store.prefetch(DateTime(2026, 4, 24), weekLast);
    harness.lastCall.succeed(<CalendarEntry<String>>[]);
    final marked = DateTime(2026, 4, 23);
    store.prefetch(marked, marked);
    harness.lastCall.fail();
    await settle();
    store.invalidate(weekFirst, weekLast);
    expect((store.readFailed(marked), harness.source.calls.length), (true, 3));

    store.retry(weekFirst, weekLast);
    expect(
      <(DateTime?, DateTime?)>[
        for (final call in harness.source.calls.skip(3))
          (call.first, call.last),
      ],
      <(DateTime?, DateTime?)>[(weekFirst, weekLast)],
    );
  });

  test("FR73 a refresh notifies only where it changes the status or the "
      "loadError, or leaves a mark it ended ended", () async {
    final outcomes = <String, (CalendarLoadStatus, int)>{};
    for (final refreshed in <String>["same error", "new error", "in flight"]) {
      final harness = Harness();
      final store = harness.store;
      store.show(weekFirst, weekLast);
      final error = harness.lastCall.fail();
      await settle();
      final notifications = harness.notifications;
      if (refreshed == "same error") {
        harness.source.thrown = error;
      } else if (refreshed == "new error") {
        harness.source.thrown = SourceFailure("Offline again.");
      }

      store.refresh().then<void>((_) {}, onError: (Object error) {});
      outcomes[refreshed] = (
        store.status,
        harness.notifications - notifications,
      );
      await settle();
    }
    expect(outcomes, <String, (CalendarLoadStatus, int)>{
      "same error": (CalendarLoadStatus.failed, 0),
      "new error": (CalendarLoadStatus.failed, 1),
      "in flight": (CalendarLoadStatus.loading, 1),
    });
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

    test("CF13 a read sent between a write and its echo that answers after "
        "the write's answer with the entry as it was sends no read again, "
        "as the echo is newer than the read", () async {
      final outcomes = <String, (CalendarEntry<String>?, int)>{};
      final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
      final moved = onDay(item, DateTime(2026, 4, 23));
      for (final write in <String>["move", "delete"]) {
        final source = StreamController<CalendarSourceChange<String>>();
        final harness = Harness(changes: source.stream);
        final store = harness.store;
        store.show(weekFirst, weekLast);
        harness.lastCall.succeed(<CalendarEntry<String>>[item]);
        await settle();
        if (write == "move") {
          store.requestMove(moved);
        } else {
          store.requestDelete("item-1");
        }
        final sent = harness.lastCall;
        store.invalidate(DateTime(2026, 4, 21), DateTime(2026, 4, 23));
        final read = harness.lastCall;
        expect(harness.source.calls, hasLength(3), reason: write);
        source.add(
          write == "move"
              ? CalendarEntryPut<String>(moved)
              : const CalendarEntryRemoved<String>("item-1"),
        );
        await settle();
        sent.succeed(write == "move" ? moved : null);
        await settle();

        // The source served the read before the write.
        read.succeed(<CalendarEntry<String>>[item]);
        await settle();
        outcomes[write] = (
          store.storedEntry("item-1"),
          harness.source.calls.length,
        );
        await source.close();
      }
      expect(outcomes, <String, (CalendarEntry<String>?, int)>{
        "move": (moved, 3),
        "delete": (null, 3),
      });
    });
  });
}
