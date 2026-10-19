/// The calendar model's day cache, its shown range and the per-item lock,
/// over a fake API whose calls the tests complete by hand.
library;

import 'dart:async';

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_model.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

/// One call the fake API received, completed by the test.
class FakeCall {
  FakeCall(this.method, {this.id, this.first, this.last, this.body});

  final CalendarMethod method;
  final String? id;
  final DateTime? first;
  final DateTime? last;
  final Map<String, Object?>? body;
  final Completer<Object?> completer = Completer<Object?>();

  void succeed([Object? value]) {
    completer.complete(value);
  }

  void fail([String message = "Offline."]) {
    completer.completeError(CalendarFailureException(message));
  }
}

class FakeCalendarApi implements CalendarApi {
  final List<FakeCall> calls = <FakeCall>[];

  Future<T> _add<T>(FakeCall call) {
    calls.add(call);
    return call.completer.future.then((value) {
      return value as T;
    });
  }

  @override
  Future<List<Map<String, Object?>>> list(DateTime first, DateTime last) {
    return _add(FakeCall(CalendarMethod.list, first: first, last: last));
  }

  @override
  Future<Map<String, Object?>> get(String id) {
    return _add(FakeCall(CalendarMethod.get, id: id));
  }

  @override
  Future<Map<String, Object?>> create(Map<String, Object?> item) {
    return _add(FakeCall(CalendarMethod.create, body: item));
  }

  @override
  Future<Map<String, Object?>> update(String id, Map<String, Object?> item) {
    return _add(FakeCall(CalendarMethod.update, id: id, body: item));
  }

  @override
  Future<void> delete(String id) {
    return _add(FakeCall(CalendarMethod.delete, id: id));
  }
}

/// A model over a fake API, recording what reaches `onWriteFailed` and
/// how often it notifies.
class Harness {
  Harness() {
    model = CalendarModel(
      api: api,
      onWriteFailed: (message) {
        failures.add(message);
      },
    );
    model.addListener(() {
      notifications++;
    });
  }

  final FakeCalendarApi api = FakeCalendarApi();
  late final CalendarModel model;
  final List<String> failures = <String>[];
  int notifications = 0;

  FakeCall get lastCall {
    return api.calls.last;
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

CalendarItem task(
  String id,
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
  String title = "Task",
}) {
  return CalendarItem(
    id: id,
    type: CalendarItemType.task,
    title: title,
    day: day,
    startMinute: start,
    endMinute: end,
    dayCount: dayCount,
    fields: const <String, Object?>{"status": "toDo", "priority": "medium"},
  );
}

/// Lets the futures the fake API's completions resolve run.
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

List<String> idsOn(CalendarModel model, DateTime day) {
  return <String>[for (final entry in model.itemsOn(day)) entry.id];
}

void main() {
  test("M1 a read range sends nothing", () async {
    final harness = Harness();
    final model = harness.model;
    model.show(aprilFirst, aprilLast);
    harness.lastCall.succeed(<Map<String, Object?>>[]);
    await settle();

    model.show(weekFirst, weekLast);
    expect(harness.api.calls, hasLength(1));
    expect(model.status, CalendarLoadStatus.ready);

    model.show(aprilFirst, aprilLast);
    expect(harness.api.calls, hasLength(1));
    expect(model.status, CalendarLoadStatus.ready);
  });

  test("M2 a late read fills only unread days, by the cached shapes", () async {
    final harness = Harness();
    final model = harness.model;
    final moving = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final multi = task(
      "item-2",
      DateTime(2026, 4, 25),
      1140,
      1200,
      dayCount: 3,
    );
    model.show(weekFirst, weekLast);
    harness.lastCall.succeed(<Map<String, Object?>>[
      moving.toJson(),
      multi.toJson(),
    ]);
    await settle();
    model.show(aprilFirst, aprilLast);
    expect(harness.api.calls, hasLength(2));
    final april = harness.lastCall;

    // Three writes the API confirms before April's read answers.
    final moved = moving.copyWith(
      day: DateTime(2026, 4, 22),
      startMinute: 840,
      endMinute: 900,
    );
    model.requestMove(moved);
    harness.lastCall.succeed(moved.toJson());
    await settle();
    final multiMoved = multi.copyWith(day: DateTime(2026, 4, 21));
    model.requestMove(multiMoved);
    harness.lastCall.succeed(multiMoved.toJson());
    await settle();
    final draft = CalendarItem(
      type: CalendarItemType.task,
      title: "Created",
      day: DateTime(2026, 4, 25),
      startMinute: 1260,
      endMinute: 1320,
      dayCount: 3,
      fields: const <String, Object?>{"status": "toDo"},
    );
    final creating = model.create(draft);
    final created = <String, Object?>{...draft.toJson(), "id": "item-3"};
    harness.lastCall.succeed(created);
    await creating;

    // The read answers with the first two where they were when it was
    // sent, and without the third.
    april.succeed(<Map<String, Object?>>[moving.toJson(), multi.toJson()]);
    await settle();
    expect(model.status, CalendarLoadStatus.ready);
    final onWednesday = model.itemsOn(DateTime(2026, 4, 22));
    expect(
      <CalendarItem>[
        for (final entry in onWednesday)
          if (entry.id == "item-1") entry.item,
      ],
      <CalendarItem>[moved],
    );
    expect(idsOn(model, DateTime(2026, 4, 21)), isNot(contains("item-1")));
    final onMonday = idsOn(model, DateTime(2026, 4, 27));
    expect(onMonday, isNot(contains("item-2")));
    expect(onMonday, contains("item-3"));
  });

  test(
    "M3 a read the shown range does not wait on changes no shown state",
    () async {
      final failing = Harness();
      failing.model.show(aprilFirst, aprilLast);
      final april = failing.lastCall;
      failing.model.show(mayFirst, mayLast);
      expect(failing.api.calls, hasLength(2));
      april.fail();
      await settle();
      expect(failing.model.status, CalendarLoadStatus.loading);
      expect(failing.model.error, isNull);

      final filling = Harness();
      filling.model.show(aprilFirst, aprilLast);
      final read = filling.lastCall;
      filling.model.show(mayFirst, mayLast);
      read.succeed(<Map<String, Object?>>[
        task("item-1", DateTime(2026, 4, 27), 600, 660).toJson(),
      ]);
      await settle();
      expect(filling.model.status, CalendarLoadStatus.loading);
      expect(filling.model.dayHasShownItems(DateTime(2026, 4, 27)), isFalse);
    },
  );

  test("M4 writes update the cache and the lock", () async {
    final harness = Harness();
    final model = harness.model;
    final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
    final other = task("item-2", DateTime(2026, 4, 22), 900, 960);
    model.show(weekFirst, weekLast);
    harness.lastCall.succeed(<Map<String, Object?>>[
      item.toJson(),
      other.toJson(),
    ]);
    await settle();

    // A move that fails.
    final requested = item.copyWith(day: DateTime(2026, 4, 23));
    model.requestMove(requested);
    final failing = harness.lastCall;
    expect(failing.method, CalendarMethod.update);
    expect(model.itemsOn(DateTime(2026, 4, 23)), <ShownItem>[
      ShownItem(requested, pending: true),
    ]);
    expect(idsOn(model, DateTime(2026, 4, 21)), isEmpty);
    expect(model.isLocked("item-1"), isTrue);

    // Every write on the locked id is refused without a call or a throw.
    final calls = harness.api.calls.length;
    model.requestMove(item.copyWith(day: DateTime(2026, 4, 24)));
    expect(harness.failures, <String>["This item has a change in progress."]);
    final refusal = errorOf(model.update(item.copyWith(title: "Renamed")));
    model.requestDelete("item-1");
    await settle();
    expect(
      refusal(),
      isA<CalendarFailureException>().having(
        (error) => error.message,
        "message",
        "This item has a change in progress.",
      ),
    );
    expect(harness.failures, <String>[
      "This item has a change in progress.",
      "This item has a change in progress.",
    ]);
    expect(harness.api.calls, hasLength(calls));

    failing.fail("Moving failed.");
    await settle();
    expect(model.itemsOn(DateTime(2026, 4, 21)), <ShownItem>[
      ShownItem(item, pending: false),
    ]);
    expect(model.isLocked("item-1"), isFalse);
    expect(harness.failures.last, "Moving failed.");

    // A move that succeeds.
    model.requestMove(requested);
    harness.lastCall.succeed(requested.toJson());
    await settle();
    expect(model.storedItem("item-1"), requested);
    expect(model.isLocked("item-1"), isFalse);

    // A form edit shows the stored item until the API answers, and its
    // failure reaches the caller alone.
    final failuresBefore = harness.failures.length;
    final edit = errorOf(model.update(other.copyWith(title: "Renamed")));
    expect(model.itemsOn(DateTime(2026, 4, 22)), <ShownItem>[
      ShownItem(other, pending: true),
    ]);
    harness.lastCall.fail("Saving failed.");
    await settle();
    expect(
      edit(),
      isA<CalendarFailureException>().having(
        (error) => error.message,
        "message",
        "Saving failed.",
      ),
    );
    expect(model.isLocked("item-2"), isFalse);
    expect(harness.failures, hasLength(failuresBefore));

    // A confirmed create and delete add and remove.
    final draft = CalendarItem(
      type: CalendarItemType.meeting,
      title: "Created",
      day: DateTime(2026, 4, 24),
      startMinute: 600,
      endMinute: 660,
    );
    final creating = model.create(draft);
    harness.lastCall.succeed(<String, Object?>{
      ...draft.toJson(),
      "id": "item-3",
    });
    await creating;
    expect(idsOn(model, DateTime(2026, 4, 24)), <String>["item-3"]);
    model.requestDelete("item-3");
    harness.lastCall.succeed();
    await settle();
    expect(idsOn(model, DateTime(2026, 4, 24)), isEmpty);
  });

  test("M4 a move that meets an item on a read day sends nothing", () async {
    final harness = Harness();
    final model = harness.model;
    final multi = task(
      "item-1",
      DateTime(2026, 4, 25),
      1140,
      1200,
      dayCount: 3,
    );
    final single = task("item-2", DateTime(2026, 4, 27), 1020, 1080);
    final morning = task("item-3", DateTime(2026, 4, 26), 600, 660);
    model.show(DateTime(2026, 4, 25), DateTime(2026, 4, 27));
    harness.lastCall.succeed(<Map<String, Object?>>[
      multi.toJson(),
      single.toJson(),
      morning.toJson(),
    ]);
    await settle();
    final calls = harness.api.calls.length;

    model.requestMove(multi.copyWith(startMinute: 1020, endMinute: 1080));
    expect(harness.api.calls, hasLength(calls));
    expect(model.isLocked("item-1"), isFalse);
    expect(harness.failures, <String>[
      const CalendarOverlapException(<String>["item-2"]).message,
    ]);

    model.requestMove(multi.copyWith(startMinute: 1110, endMinute: 1170));
    expect(harness.api.calls, hasLength(calls + 1));
    harness.lastCall.succeed(
      multi.copyWith(startMinute: 1110, endMinute: 1170).toJson(),
    );
    await settle();

    // Two single-day items are kept apart as well.
    final reported = harness.failures.length;
    model.requestMove(
      single.copyWith(
        day: DateTime(2026, 4, 26),
        startMinute: 630,
        endMinute: 690,
      ),
    );
    expect(harness.api.calls, hasLength(calls + 1));
    expect(model.isLocked("item-2"), isFalse);
    expect(harness.failures.sublist(reported), <String>[
      const CalendarOverlapException(<String>["item-3"]).message,
    ]);
  });

  test("M5 a multi-day item shows on each day it covers", () async {
    final harness = Harness();
    final model = harness.model;
    model.show(aprilFirst, aprilLast);
    harness.lastCall.succeed(<Map<String, Object?>>[
      task("item-1", DateTime(2026, 4, 28), 600, 660, dayCount: 3).toJson(),
    ]);
    await settle();
    for (final day in <int>[28, 29, 30]) {
      expect(idsOn(model, DateTime(2026, 4, day)), <String>[
        "item-1",
      ], reason: "2026-04-$day");
      expect(
        model.dayHasShownItems(DateTime(2026, 4, day)),
        isTrue,
        reason: "2026-04-$day",
      );
    }
    expect(idsOn(model, DateTime(2026, 4, 27)), isEmpty);
    expect(idsOn(model, DateTime(2026, 5, 1)), isEmpty);
  });

  test("M6 the shown range follows the read it waits on", () async {
    final harness = Harness();
    final model = harness.model;
    model.show(weekFirst, weekLast);
    final week = harness.lastCall;
    model.show(aprilFirst, aprilLast);
    final april = harness.lastCall;
    expect(harness.api.calls, hasLength(2));
    model.show(weekFirst, weekLast);
    expect(harness.api.calls, hasLength(2));

    april.succeed(<Map<String, Object?>>[]);
    await settle();
    expect(model.status, CalendarLoadStatus.loading);
    week.fail();
    await settle();
    expect(model.status, CalendarLoadStatus.ready);
    expect(model.error, isNull);
    model.retry();
    expect(harness.api.calls, hasLength(2));
    expect(model.status, CalendarLoadStatus.ready);

    final fresh = Harness();
    fresh.model.show(aprilFirst, aprilLast);
    fresh.lastCall.fail();
    await settle();
    expect(fresh.model.status, CalendarLoadStatus.failed);
    final notifications = fresh.notifications;
    fresh.model.show(aprilFirst, aprilLast);
    expect(fresh.api.calls, hasLength(1));
    expect(fresh.model.status, CalendarLoadStatus.failed);
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
        final model = harness.model;
        final item = task("item-1", DateTime(2026, 4, 21), 600, 660);
        model.show(weekFirst, weekLast);
        harness.lastCall.succeed(<Map<String, Object?>>[item.toJson()]);
        await settle();
        model.show(aprilFirst, aprilLast);
        final read = harness.lastCall;
        model.requestMove(item.copyWith(day: DateTime(2026, 4, 22)));
        final write = harness.lastCall;

        model.dispose();
        read.succeed(<Map<String, Object?>>[]);
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

  test("M8 the hours hold a new item and a change of an item's days or "
      "minutes", () async {
    const startError = <String, String>{
      "startMinute":
          "The start is 08:00 to 17:45, inside the calendar's hours.",
    };
    final harness = Harness();
    final model = harness.model;
    final early = task("item-1", DateTime(2026, 4, 21), 420, 540);
    model.show(weekFirst, weekLast);
    harness.lastCall.succeed(<Map<String, Object?>>[early.toJson()]);
    await settle();
    model.hours = const DayHours(480, 1080);
    final calls = harness.api.calls.length;

    final created = errorOf(
      model.create(
        CalendarItem(
          type: CalendarItemType.task,
          title: "Late",
          day: DateTime(2026, 4, 22),
          startMinute: 1050,
          endMinute: 1110,
          fields: const <String, Object?>{"status": "toDo"},
        ),
      ),
    );
    final moved = errorOf(model.update(early.copyWith(day: weekLast)));
    await settle();
    expect(
      created(),
      isA<CalendarValidationException>().having(
        (error) => error.fieldErrors,
        "fieldErrors",
        <String, String>{
          "endMinute":
              "The end is 08:15 to 18:00, inside the calendar's hours.",
        },
      ),
    );
    expect(
      moved(),
      isA<CalendarValidationException>().having(
        (error) => error.fieldErrors,
        "fieldErrors",
        startError,
      ),
    );
    expect(model.isLocked("item-1"), isFalse);

    model.requestMove(early.copyWith(startMinute: 450, endMinute: 510));
    expect(harness.failures, <String>[
      const CalendarValidationException(startError).message,
    ]);
    expect(model.isLocked("item-1"), isFalse);
    expect(harness.api.calls, hasLength(calls));

    // A write that keeps the stored days and minutes is not held to them.
    final renamed = model.update(early.copyWith(title: "Renamed"));
    expect(harness.api.calls, hasLength(calls + 1));
    harness.lastCall.succeed(early.copyWith(title: "Renamed").toJson());
    await renamed;
    model.requestMove(early.copyWith(startMinute: 480, endMinute: 600));
    expect(harness.api.calls, hasLength(calls + 2));
    expect(harness.lastCall.body!["startMinute"], 480);
  });

  test("M9 isWithinShown holds for the days inside the shown range", () {
    final model = Harness().model;
    expect(model.isWithinShown(weekFirst, weekFirst), isFalse);

    model.show(weekFirst, weekLast);
    expect(model.isWithinShown(weekFirst, weekLast), isTrue);
    expect(
      model.isWithinShown(DateTime(2026, 4, 22), DateTime(2026, 4, 22)),
      isTrue,
    );
    expect(
      model.isWithinShown(DateTime(2026, 4, 19), DateTime(2026, 4, 21)),
      isFalse,
    );
    expect(
      model.isWithinShown(DateTime(2026, 4, 25), DateTime(2026, 4, 27)),
      isFalse,
    );
  });

  test("M10 a prefetch reads only the unread days, keeps the shown range "
      "and its status, and notifies once it marks days read", () async {
    final harness = Harness();
    final model = harness.model;
    model.show(weekFirst, weekLast);
    harness.lastCall.succeed(<Map<String, Object?>>[]);
    await settle();
    final notifications = harness.notifications;

    model.prefetch(weekFirst, weekLast);
    expect(harness.api.calls, hasLength(1));

    // Of April 23 to May 3, April 27 on are unread.
    model.prefetch(DateTime(2026, 4, 23), aprilLast);
    expect(harness.api.calls, hasLength(2));
    final read = harness.lastCall;
    expect((read.first, read.last), (DateTime(2026, 4, 27), aprilLast));
    // The read in flight covers these.
    model.prefetch(DateTime(2026, 4, 28), DateTime(2026, 4, 29));
    expect(harness.api.calls, hasLength(2));
    expect(model.status, CalendarLoadStatus.ready);
    expect(model.isShown(weekFirst, weekLast), isTrue);
    expect(harness.notifications, notifications);

    read.succeed(<Map<String, Object?>>[
      task("item-1", DateTime(2026, 4, 28), 540, 600).toJson(),
    ]);
    await settle();
    expect(harness.notifications, notifications + 1);
    expect(model.dayHasShownItems(DateTime(2026, 4, 28)), isTrue);
    expect(model.dayHasShownItems(DateTime(2026, 4, 29)), isFalse);

    // A failed one leaves its days unread and marks them failed, so the
    // next one sends again, which clears the mark.
    model.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    harness.lastCall.fail();
    await settle();
    expect(harness.notifications, notifications + 2);
    expect(model.isRead(DateTime(2026, 5, 4)), isFalse);
    expect(model.readFailed(DateTime(2026, 5, 4)), isTrue);
    expect(model.readFailed(DateTime(2026, 4, 28)), isFalse);
    model.prefetch(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    expect(harness.api.calls, hasLength(4));
    expect(model.readFailed(DateTime(2026, 5, 4)), isFalse);
  });

  test("M11 a day is read once a read fills it, and a failed read of the "
      "shown range marks its days failed too", () async {
    final harness = Harness();
    final model = harness.model;
    model.show(weekFirst, weekLast);
    expect(model.isRead(weekFirst), isFalse);
    harness.lastCall.fail();
    await settle();
    expect(model.status, CalendarLoadStatus.failed);
    expect(model.readFailed(weekFirst), isTrue);

    model.retry();
    expect(model.readFailed(weekFirst), isFalse);
    harness.lastCall.succeed(<Map<String, Object?>>[]);
    await settle();
    expect(model.isRead(weekFirst), isTrue);
    expect(model.readFailed(weekFirst), isFalse);
  });

  group("first free", () {
    final day = DateTime(2026, 4, 22);

    /// Shows [day] and completes its read with [items].
    Future<CalendarModel> readDay(
      Harness harness,
      List<CalendarItem> items,
    ) async {
      final model = harness.model;
      model.show(day, day);
      harness.lastCall.succeed(<Map<String, Object?>>[
        for (final item in items) item.toJson(),
      ]);
      await settle();
      expect(model.status, CalendarLoadStatus.ready);
      return model;
    }

    test(
      "FF1 the first free range is the earliest slot that meets no shown item",
      () async {
        final model = await readDay(Harness(), <CalendarItem>[
          task("item-1", day, 0, 60),
          task("item-2", day, 75, 120),
        ]);
        expect(model.firstFreeRange(day), (start: 60, end: 75));
      },
    );

    test(
      "FF2 a day free only in the hours' last slot gets that slot",
      () async {
        final model = await readDay(Harness(), <CalendarItem>[
          task("item-1", day, 540, 705),
        ]);
        model.hours = const DayHours(540, 720);
        expect(model.firstFreeRange(day), (start: 705, end: 720));
      },
    );

    test("FF3 with no free start the range is the hours' first slot", () async {
      final model = await readDay(Harness(), <CalendarItem>[
        task("item-1", day, 0, 1440),
      ]);
      expect(model.firstFreeRange(day), (start: 0, end: 15));
    });

    test("FF4 a pending move counts where it shows", () async {
      final harness = Harness();
      final item = task("item-1", day, 60, 120);
      final model = await readDay(harness, <CalendarItem>[item]);
      // Sanity: the stored item leaves the first slot free.
      expect(model.firstFreeRange(day), (start: 0, end: 15));

      final calls = harness.api.calls.length;
      model.requestMove(item.copyWith(startMinute: 0, endMinute: 60));
      expect(harness.api.calls, hasLength(calls + 1));
      expect(model.isLocked("item-1"), isTrue);
      expect(model.firstFreeRange(day), (start: 60, end: 75));
    });

    test("FF5 a search from a minute starts there, rounded up to the slots "
        "and no earlier than the hours, and with nothing free after it "
        "starts again at the hours' start", () async {
      final model = await readDay(Harness(), <CalendarItem>[
        task("item-1", day, 480, 540),
        task("item-2", day, 900, 960),
      ]);
      model.hours = const DayHours(480, 1200);
      expect(model.firstFreeRange(day, from: 840), (start: 840, end: 855));
      // 14:10 rounds up to 14:15.
      expect(model.firstFreeRange(day, from: 850), (start: 855, end: 870));
      // Each slot from 15:00 meets item-2 until it ends.
      expect(model.firstFreeRange(day, from: 900), (start: 960, end: 975));
      expect(model.firstFreeRange(day, from: 300), (start: 540, end: 555));
      expect(model.firstFreeRange(day, from: 1200), (start: 540, end: 555));
    });
  });
}
