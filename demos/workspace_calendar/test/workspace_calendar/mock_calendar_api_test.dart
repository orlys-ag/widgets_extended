/// The mock API: its envelope and schema rules, the overlap rule, the
/// failure policy and latency, the copies it hands in and out, and the
/// seed. Every call is answered through the test binding's fake time.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:flutter_test/flutter_test.dart';

const Duration latency = Duration(milliseconds: 100);

final DateTime wednesday = DateTime(2026, 4, 22);

/// What a call completed with by the end of a pump of its latency.
typedef Outcome = ({bool done, Object? value, Object? error});

/// Pumps [wait] and returns what [call] completed with by then.
Future<Outcome> answer(
  WidgetTester tester,
  Future<Object?> call, {
  Duration wait = latency,
}) async {
  var done = false;
  Object? value;
  Object? error;
  call.then(
    (result) {
      done = true;
      value = result;
    },
    onError: (Object failure) {
      done = true;
      error = failure;
    },
  );
  await tester.pump(wait);
  return (done: done, value: value, error: error);
}

/// The fields an item of [type] needs to be valid.
Map<String, Object?> validFields(CalendarItemType type) {
  switch (type) {
    case CalendarItemType.task:
      return <String, Object?>{"status": "toDo"};
    case CalendarItemType.meeting:
      return <String, Object?>{};
    case CalendarItemType.outOfOffice:
      return <String, Object?>{"reason": "vacation"};
    case CalendarItemType.deadline:
      return <String, Object?>{"project": "Roadmap"};
  }
}

/// An envelope of [type] from [start] minutes after [day]'s midnight to
/// [end] minutes after the midnight of the day [dayCount] - 1 days on,
/// [day] Wednesday unless given.
Map<String, Object?> envelope({
  CalendarItemType type = CalendarItemType.task,
  String title = "Item",
  DateTime? day,
  int start = 9 * 60,
  int end = 10 * 60,
  int dayCount = 1,
  Map<String, Object?>? fields,
}) {
  final first = day ?? wednesday;
  final last = addDays(first, dayCount - 1);
  return <String, Object?>{
    "type": type.id,
    "title": title,
    "start": isoDateTime(
      DateTime(first.year, first.month, first.day, 0, start),
    ),
    "end": isoDateTime(DateTime(last.year, last.month, last.day, 0, end)),
    "fields": fields ?? validFields(type),
  };
}

/// The local time [local], written with no offset, in UTC with a Z, as
/// `DateTime.toIso8601String` writes it.
String utcText(String local) {
  return DateTime.parse(local).toUtc().toIso8601String();
}

/// An envelope of [type] whose `start` and `end` are the texts given.
Map<String, Object?> timed(
  Object? start,
  Object? end, {
  CalendarItemType type = CalendarItemType.task,
  String title = "Item",
}) {
  return <String, Object?>{
    ...envelope(type: type, title: title),
    "start": start,
    "end": end,
  };
}

/// The first hour of 2026 that the local clock skips, on its first day of
/// 23 hours, as [isoDateTime] would write its half hour; null where the
/// zone has no such day.
String? _skippedHalfHour() {
  for (var day = DateTime(2026); day.year == 2026; day = addDays(day, 1)) {
    if (addDays(day, 1).difference(day).inHours != 23) {
      continue;
    }
    for (var hour = 0; hour < 24; hour++) {
      if (DateTime(day.year, day.month, day.day, hour, 30).hour != hour) {
        final text = hour.toString().padLeft(2, "0");
        return "${isoDate(day)}T$text:30";
      }
    }
  }
  return null;
}

/// The error [call] completed with by the end of a pump of the latency.
Future<Object?> errorOf(WidgetTester tester, Future<Object?> call) async {
  return (await answer(tester, call)).error;
}

/// Stores [item] through a create and returns its id.
Future<String> stored(
  WidgetTester tester,
  MockCalendarApi api,
  Map<String, Object?> item,
) async {
  final created = await answer(tester, api.create(item));
  return (created.value! as Map<String, Object?>)["id"]! as String;
}

/// What `list` returns for [first] to [last].
Future<List<Map<String, Object?>>> listed(
  WidgetTester tester,
  MockCalendarApi api,
  DateTime first,
  DateTime last,
) async {
  final listing = await answer(tester, api.list(first, last));
  return listing.value! as List<Map<String, Object?>>;
}

Future<Map<String, Object?>> fetched(
  WidgetTester tester,
  MockCalendarApi api,
  String id,
) async {
  final got = await answer(tester, api.get(id));
  return got.value! as Map<String, Object?>;
}

/// The ids in [items], in order.
List<String> idsOf(List<Map<String, Object?>> items) {
  return <String>[for (final item in items) item["id"]! as String];
}

/// Matches a [CalendarValidationException] whose keys are exactly [keys].
Matcher validationOf(Set<String> keys) {
  return isA<CalendarValidationException>().having(
    (error) {
      return error.fieldErrors.keys.toSet();
    },
    "keys",
    keys,
  );
}

Matcher overlapWith(List<String> ids) {
  return isA<CalendarOverlapException>().having(
    (error) {
      return error.conflictingIds;
    },
    "conflictingIds",
    ids,
  );
}

void main() {
  testWidgets("A1 creates each type with an assigned id and lists it once", (
    tester,
  ) async {
    final api = MockCalendarApi(latency: latency);
    final created = <String, CalendarItemType>{};
    var start = 0;
    for (final type in CalendarItemType.values) {
      final outcome = await answer(
        tester,
        api.create(envelope(type: type, start: start, end: start + 60)),
      );
      final id = (outcome.value! as Map<String, Object?>)["id"];
      expect(id, isA<String>().having((id) => id.isEmpty, "isEmpty", false));
      created[id! as String] = type;
      start += 60;
    }
    final day = await listed(tester, api, wednesday, wednesday);
    expect(idsOf(day), unorderedEquals(created.keys));
    expect(
      <String>[for (final item in day) item["type"]! as String],
      unorderedEquals(<String>[
        for (final type in CalendarItemType.values) type.id,
      ]),
    );

    final withId = await answer(
      tester,
      api.create(<String, Object?>{
        ...envelope(start: 600, end: 660),
        "id": "x",
      }),
    );
    final assigned = (withId.value! as Map<String, Object?>)["id"];
    expect(assigned, isA<String>());
    expect(assigned, isNot("x"));

    final task = await stored(
      tester,
      api,
      envelope(start: 720, end: 780, fields: const <String, Object?>{}),
    );
    final deadline = await stored(
      tester,
      api,
      envelope(
        type: CalendarItemType.deadline,
        start: 780,
        end: 840,
        fields: const <String, Object?>{"project": "Roadmap"},
      ),
    );
    final taskFields = (await fetched(tester, api, task))["fields"]! as Map;
    expect(taskFields["status"], "toDo");
    expect(taskFields["priority"], "medium");
    final deadlineFields =
        (await fetched(tester, api, deadline))["fields"]! as Map;
    expect(deadlineFields["met"], false);

    // A three-day Meeting, Monday 2026-04-27 to Wednesday 2026-04-29.
    final meeting = await stored(
      tester,
      api,
      envelope(
        type: CalendarItemType.meeting,
        day: DateTime(2026, 4, 27),
        dayCount: 3,
      ),
    );
    final firstDay = await listed(
      tester,
      api,
      DateTime(2026, 4, 27),
      DateTime(2026, 4, 27),
    );
    expect(idsOf(firstDay).where((id) => id == meeting), hasLength(1));
    final lastDay = await listed(
      tester,
      api,
      DateTime(2026, 4, 29),
      DateTime(2026, 5, 2),
    );
    expect(idsOf(lastDay).where((id) => id == meeting), hasLength(1));
    final around = await listed(
      tester,
      api,
      DateTime(2026, 4, 22),
      DateTime(2026, 5, 4),
    );
    expect(idsOf(around).where((id) => id == meeting), hasLength(1));
  });

  testWidgets("A2 update changes title, times and fields; delete makes get "
      "fail", (tester) async {
    final api = MockCalendarApi(latency: latency);
    final id = await stored(tester, api, envelope());
    final updated = await answer(
      tester,
      api.update(
        id,
        envelope(
          title: "Renamed",
          start: 11 * 60,
          end: 12 * 60 + 30,
          fields: const <String, Object?>{"status": "done", "assignee": "Sam"},
        ),
      ),
    );
    expect(updated.error, isNull);
    final got = await fetched(tester, api, id);
    expect(got["title"], "Renamed");
    expect(got["start"], utcText("2026-04-22T11:00"));
    expect(got["end"], utcText("2026-04-22T12:30"));
    expect(got["fields"], <String, Object?>{
      "status": "done",
      "priority": "medium",
      "assignee": "Sam",
    });

    final renamed = await answer(
      tester,
      api.update(id, <String, Object?>{...envelope(title: "Again"), "id": "x"}),
    );
    expect((renamed.value! as Map<String, Object?>)["id"], id);
    final missing = await answer(tester, api.get("x"));
    expect(missing.error, isA<CalendarNotFoundException>());

    final deleted = await answer(tester, api.delete(id));
    expect(deleted.error, isNull);
    final gone = await answer(tester, api.get(id));
    expect(gone.error, isA<CalendarNotFoundException>());
  });

  testWidgets("A3 type rule violations name every offending field", (
    tester,
  ) async {
    final api = MockCalendarApi(latency: latency);
    final task = await stored(tester, api, envelope());
    final before = await listed(tester, api, wednesday, wednesday);

    Map<String, Object?> meeting(Map<String, Object?> fields) {
      return envelope(type: CalendarItemType.meeting, fields: fields);
    }

    Map<String, Object?> deadline(Map<String, Object?> fields) {
      return envelope(type: CalendarItemType.deadline, fields: fields);
    }

    expect(
      await errorOf(tester, api.create(envelope(title: "  "))),
      validationOf(<String>{"title"}),
    );
    expect(
      await errorOf(tester, api.create(deadline(const <String, Object?>{}))),
      validationOf(<String>{"fields.project"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(deadline(const <String, Object?>{"project": "  "})),
      ),
      validationOf(<String>{"fields.project"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(<String, Object?>{
          ...deadline(const <String, Object?>{}),
          "title": "",
        }),
      ),
      validationOf(<String>{"title", "fields.project"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(
          envelope(fields: const <String, Object?>{"status": "blocked"}),
        ),
      ),
      validationOf(<String>{"fields.status"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(meeting(const <String, Object?>{"videoLink": "ftp://x"})),
      ),
      validationOf(<String>{"fields.videoLink"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(meeting(const <String, Object?>{"videoLink": "https://"})),
      ),
      validationOf(<String>{"fields.videoLink"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(meeting(const <String, Object?>{"location": 5})),
      ),
      validationOf(<String>{"fields.location"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(meeting(const <String, Object?>{"attendees": "Ana"})),
      ),
      validationOf(<String>{"fields.attendees"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(
          deadline(const <String, Object?>{"project": "Roadmap", "met": "yes"}),
        ),
      ),
      validationOf(<String>{"fields.met"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(
          envelope(
            fields: const <String, Object?>{"status": "toDo", "color": 1},
          ),
        ),
      ),
      validationOf(<String>{"fields.color"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(<String, Object?>{...envelope(), "colour": "red"}),
      ),
      validationOf(<String>{"colour"}),
    );
    expect(
      await errorOf(
        tester,
        api.update(task, meeting(const <String, Object?>{})),
      ),
      validationOf(<String>{"type"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(<String, Object?>{...envelope(), "title": 5}),
      ),
      validationOf(<String>{"title"}),
    );
    expect(
      await errorOf(
        tester,
        api.create(<String, Object?>{...envelope(), "type": "holiday"}),
      ),
      validationOf(<String>{"type"}),
    );
    expect(await listed(tester, api, wednesday, wednesday), before);

    // An hour after the Task, so the overlap rule does not refuse it.
    final linkless = await answer(
      tester,
      api.create(<String, Object?>{
        ...meeting(const <String, Object?>{"videoLink": ""}),
        "start": "2026-04-22T10:00",
        "end": "2026-04-22T11:00",
      }),
    );
    expect(linkless.error, isNull);
    final id = (linkless.value! as Map<String, Object?>)["id"]! as String;
    expect(
      ((await fetched(tester, api, id))["fields"]! as Map)["videoLink"],
      "",
    );
  });

  testWidgets("A4 the validator requires start and end as a local "
      "YYYY-MM-DDTHH:MM or in UTC with seconds and a Z, refuses a local time "
      "with seconds, another offset, a UTC time with no seconds, a day that "
      "does not exist, an end not after the start and 367 days, and accepts "
      "and keeps 09:10", (tester) async {
    final api = MockCalendarApi(latency: latency);
    await stored(tester, api, envelope());
    final before = await listed(
      tester,
      api,
      DateTime(2025, 1, 1),
      DateTime(2027, 12, 31),
    );

    Future<Object?> created(Map<String, Object?> item) {
      return errorOf(tester, api.create(item));
    }

    const end = "2026-04-23T10:00";
    expect(
      await created(timed("2026-04-23T09:00:00", end)),
      validationOf(<String>{"start"}),
    );
    expect(
      await created(timed("2026-04-23T09:00", "2026-04-23T10:00-04:00")),
      validationOf(<String>{"end"}),
    );
    expect(
      await created(timed("2026-04-23T09:00Z", end)),
      validationOf(<String>{"start"}),
    );
    expect(
      await created(timed("2026-04-23 09:00", end)),
      validationOf(<String>{"start"}),
    );
    expect(
      await created(timed("2026-02-30T09:00", end)),
      validationOf(<String>{"start"}),
    );
    expect(
      await created(timed("2026-04-23T24:00", "2026-04-24T01:00")),
      validationOf(<String>{"start"}),
    );
    expect(await created(timed(540, end)), validationOf(<String>{"start"}));
    expect(
      await created(timed("2026-04-23T09:00", null)),
      validationOf(<String>{"end"}),
    );
    expect(
      await created(timed("2026-04-23T10:00", end)),
      validationOf(<String>{"end"}),
    );
    expect(
      await created(timed("2026-04-23T11:00", end)),
      validationOf(<String>{"end"}),
    );
    // From 23:00 on Thursday to 01:00 a year and a day on: 367 days.
    expect(
      await created(timed("2026-04-23T23:00", "2027-04-24T01:00")),
      validationOf(<String>{"end"}),
    );
    expect(
      await created(<String, Object?>{
        ...envelope(),
        "day": "2026-04-23",
        "startMinute": 540,
      }),
      validationOf(<String>{"day", "startMinute"}),
    );
    expect(
      await listed(tester, api, DateTime(2025, 1, 1), DateTime(2027, 12, 31)),
      before,
    );

    final offGrid = await answer(
      tester,
      api.create(timed("2026-04-23T09:10", "2026-04-23T09:50")),
    );
    expect(offGrid.error, isNull);
    final offGridId = (offGrid.value! as Map<String, Object?>)["id"]! as String;
    final kept = await fetched(tester, api, offGridId);
    // Kept off the slot grid, and written in UTC as the API writes times.
    expect(kept["start"], utcText("2026-04-23T09:10"));
    expect(kept["end"], utcText("2026-04-23T09:50"));

    // From 23:00 on Friday to 01:00 a year on: 366 days.
    final longest = await answer(
      tester,
      api.create(timed("2026-04-24T23:00", "2027-04-24T01:00")),
    );
    expect(longest.error, isNull);
  });

  final skipped = _skippedHalfHour();
  testWidgets(
    "A4 the validator refuses a start or an end the clock skips",
    (tester) async {
      final api = MockCalendarApi(latency: latency);
      final day = skipped!.substring(0, 10);
      expect(
        await errorOf(tester, api.create(timed(skipped, "${day}T23:00"))),
        validationOf(<String>{"start"}),
      );
      expect(
        await errorOf(tester, api.create(timed("${day}T00:30", skipped))),
        validationOf(<String>{"end"}),
      );
      expect(
        await listed(tester, api, DateTime(2026), DateTime(2026, 12, 31)),
        isEmpty,
      );
    },
    skip: skipped == null,
  );

  testWidgets("A5 overlap rules: instants that intersect conflict, an "
      "overnight entry with each day it covers, and an all-day entry with "
      "none", (tester) async {
    final api = MockCalendarApi(latency: latency);
    final thursday = DateTime(2026, 4, 23);
    final away = await stored(
      tester,
      api,
      envelope(type: CalendarItemType.outOfOffice, start: 540, end: 600),
    );
    // Monday 22:00 to Tuesday 02:00.
    final overnight = await stored(
      tester,
      api,
      timed(
        "2026-04-27T22:00",
        "2026-04-28T02:00",
        type: CalendarItemType.meeting,
      ),
    );
    final single = await stored(
      tester,
      api,
      envelope(day: thursday, start: 15 * 60, end: 16 * 60),
    );
    final before = await listed(
      tester,
      api,
      DateTime(2026, 4, 20),
      DateTime(2026, 5, 3),
    );

    Future<Object?> created(Map<String, Object?> item) {
      return errorOf(tester, api.create(item));
    }

    expect(
      await created(envelope(start: 570, end: 585)),
      overlapWith(<String>[away]),
    );
    expect(
      await created(timed("2026-04-28T01:00", "2026-04-28T03:00")),
      overlapWith(<String>[overnight]),
    );
    expect(
      await created(timed("2026-04-27T21:00", "2026-04-27T23:00")),
      overlapWith(<String>[overnight]),
    );
    expect(
      await created(
        timed(
          "2026-04-22T15:00",
          "2026-04-23T15:30",
          type: CalendarItemType.meeting,
        ),
      ),
      overlapWith(<String>[single]),
    );
    expect(
      await listed(tester, api, DateTime(2026, 4, 20), DateTime(2026, 5, 3)),
      before,
    );

    // Touching ends share no time.
    final evening = await answer(
      tester,
      api.create(timed("2026-04-27T21:00", "2026-04-27T22:00")),
    );
    expect(evening.error, isNull);
    final morning = await answer(
      tester,
      api.create(timed("2026-04-28T02:00", "2026-04-28T03:00")),
    );
    expect(morning.error, isNull);

    // An all-day entry over the busy Thursday, and over Monday to Tuesday,
    // shares no time with any.
    final allDay = await answer(
      tester,
      api.create(
        timed(
          "2026-04-23T00:00",
          "2026-04-24T00:00",
          type: CalendarItemType.outOfOffice,
        ),
      ),
    );
    expect(allDay.error, isNull);
    final trip = await answer(
      tester,
      api.create(
        timed(
          "2026-04-27T00:00",
          "2026-04-29T00:00",
          type: CalendarItemType.outOfOffice,
        ),
      ),
    );
    expect(trip.error, isNull);
    final over = await answer(
      tester,
      api.create(timed("2026-04-23T15:30", "2026-04-23T15:45")),
    );
    expect(over.error, overlapWith(<String>[single]));

    final renamed = await answer(
      tester,
      api.update(
        away,
        envelope(
          type: CalendarItemType.outOfOffice,
          title: "Dentist",
          start: 540,
          end: 600,
        ),
      ),
    );
    expect(renamed.error, isNull);
    final shortened = await answer(
      tester,
      api.update(
        away,
        envelope(
          type: CalendarItemType.outOfOffice,
          title: "Dentist",
          start: 540,
          end: 585,
        ),
      ),
    );
    expect(shortened.error, isNull);
    expect(
      (await fetched(tester, api, away))["end"],
      utcText("2026-04-22T09:45"),
    );

    final early = await stored(
      tester,
      api,
      envelope(day: thursday, start: 9 * 60, end: 10 * 60),
    );
    final thursdayBefore = await listed(tester, api, thursday, thursday);
    final moved = await answer(
      tester,
      api.update(
        single,
        envelope(day: thursday, start: 9 * 60 + 45, end: 10 * 60 + 15),
      ),
    );
    expect(moved.error, overlapWith(<String>[early]));
    expect(await listed(tester, api, thursday, thursday), thursdayBefore);
  });

  testWidgets("A10 a list of a day answers an overnight entry on both days "
      "it covers, and not an entry ending at that day's start", (tester) async {
    final api = MockCalendarApi(latency: latency);
    final overnight = await stored(
      tester,
      api,
      timed("2026-04-20T22:00", "2026-04-21T02:00"),
    );
    // An all-day Monday, which shares no time with the overnight entry.
    final allMonday = await stored(
      tester,
      api,
      timed("2026-04-20T00:00", "2026-04-21T00:00"),
    );
    final tuesday = await listed(
      tester,
      api,
      DateTime(2026, 4, 21),
      DateTime(2026, 4, 21),
    );
    expect(idsOf(tuesday), <String>[overnight]);
    final monday = await listed(
      tester,
      api,
      DateTime(2026, 4, 20),
      DateTime(2026, 4, 20),
    );
    expect(idsOf(monday), <String>[allMonday, overnight]);

    final evening = MockCalendarApi(latency: latency);
    final toMidnight = await stored(
      tester,
      evening,
      timed("2026-04-20T18:00", "2026-04-21T00:00"),
    );
    expect(
      idsOf(
        await listed(
          tester,
          evening,
          DateTime(2026, 4, 20),
          DateTime(2026, 4, 20),
        ),
      ),
      <String>[toMidnight],
    );
    expect(
      await listed(
        tester,
        evening,
        DateTime(2026, 4, 21),
        DateTime(2026, 4, 21),
      ),
      isEmpty,
    );
  });

  testWidgets("A6 failure policy, latency and the request log", (tester) async {
    final api = MockCalendarApi(
      latency: latency,
      failurePolicy: (request) {
        return request.method == CalendarMethod.create ? "Offline." : null;
      },
    );
    final failed = await answer(tester, api.create(envelope()));
    expect(
      failed.error,
      isA<CalendarFailureException>().having(
        (error) => error.message,
        "message",
        "Offline.",
      ),
    );
    expect(await listed(tester, api, wednesday, wednesday), isEmpty);

    api.failurePolicy = (request) {
      return null;
    };
    final created = await answer(tester, api.create(envelope()));
    expect(created.error, isNull);
    final id = (created.value! as Map<String, Object?>)["id"]! as String;

    final slow = MockCalendarApi(
      latency: const Duration(seconds: 1),
      seed: <Map<String, Object?>>[envelope()],
    );
    final early = await answer(
      tester,
      slow.get("item-1"),
      wait: const Duration(milliseconds: 999),
    );
    expect(early.done, isFalse);
    final call = slow.get("item-1");
    await tester.pump(const Duration(milliseconds: 999));
    final late = await answer(
      tester,
      call,
      wait: const Duration(milliseconds: 1),
    );
    expect(late.done, isTrue);
    await tester.pump(const Duration(seconds: 1));

    await answer(tester, api.update(id, envelope(title: "Renamed")));
    await answer(tester, api.delete(id));
    final requests = api.requests;
    expect(
      <CalendarMethod>[for (final request in requests) request.method],
      <CalendarMethod>[
        CalendarMethod.create,
        CalendarMethod.list,
        CalendarMethod.create,
        CalendarMethod.update,
        CalendarMethod.delete,
      ],
    );
    expect(requests[0].body, envelope());
    expect(requests[1].first, wednesday);
    expect(requests[1].last, wednesday);
    expect(requests[3].id, id);
    expect(requests[3].body, envelope(title: "Renamed"));
    expect(requests[4].id, id);
    expect(
      <String?>[for (final request in slow.requests) request.id],
      <String?>["item-1", "item-1"],
    );
  });

  testWidgets("A7 returned maps are copies", (tester) async {
    final api = MockCalendarApi(latency: latency);
    final input = envelope(
      type: CalendarItemType.meeting,
      fields: <String, Object?>{
        "attendees": <String>["Ana", "Ben"],
      },
    );
    final call = api.create(input);
    input["title"] = "Changed";
    (input["fields"]! as Map<String, Object?>)["attendees"] = <String>["Zed"];
    final created = await answer(tester, call);
    final id = (created.value! as Map<String, Object?>)["id"]! as String;
    final first = await fetched(tester, api, id);
    expect(first["title"], "Item");
    expect((first["fields"]! as Map)["attendees"], <String>["Ana", "Ben"]);

    first["title"] = "Mutated";
    ((first["fields"]! as Map)["attendees"]! as List).add("Chen");
    final second = await fetched(tester, api, id);
    expect(second["title"], "Item");
    expect((second["fields"]! as Map)["attendees"], <String>["Ana", "Ben"]);
  });

  testWidgets("A8 the seed", (tester) async {
    expect(() {
      return MockCalendarApi(
        seed: <Map<String, Object?>>[envelope(title: " ")],
      );
    }, throwsArgumentError);
    expect(() {
      return MockCalendarApi(
        seed: <Map<String, Object?>>[
          envelope(type: CalendarItemType.outOfOffice, start: 540, end: 660),
          envelope(type: CalendarItemType.outOfOffice, start: 600, end: 720),
        ],
      );
    }, throwsArgumentError);
    for (var day = 20; day <= 26; day++) {
      expect(
        () {
          return MockCalendarApi.seeded(DateTime(2026, 4, day));
        },
        returnsNormally,
        reason: "seeded around 2026-04-$day",
      );
    }

    final api = MockCalendarApi.seeded(DateTime(2026, 4, 21), latency: latency);
    final week = await listed(
      tester,
      api,
      DateTime(2026, 4, 20),
      DateTime(2026, 4, 26),
    );
    expect(
      <String>{for (final item in week) item["type"]! as String},
      <String>{for (final type in CalendarItemType.values) type.id},
    );
    final dayOff = week.singleWhere((item) => item["title"] == "Day off");
    expect(dayOff["type"], CalendarItemType.outOfOffice.id);
    expect(dayOff["start"], utcText("2026-04-20T09:00"));
    expect(dayOff["end"], utcText("2026-04-20T17:00"));
  });

  testWidgets("A11 the seed's Conference trip is one all-day entry over "
      "five days", (tester) async {
    final api = MockCalendarApi.seeded(DateTime(2026, 4, 21), latency: latency);
    final may = await listed(
      tester,
      api,
      DateTime(2026, 5, 1),
      DateTime(2026, 5, 31),
    );
    final trip = may.singleWhere((item) => item["title"] == "Conference trip");
    expect(trip["type"], CalendarItemType.outOfOffice.id);
    expect(trip["start"], utcText("2026-05-11T00:00"));
    expect(trip["end"], utcText("2026-05-16T00:00"));
    final id = trip["id"]! as String;
    for (var day = 11; day <= 15; day++) {
      final listing = await listed(
        tester,
        api,
        DateTime(2026, 5, day),
        DateTime(2026, 5, day),
      );
      expect(idsOf(listing), contains(id), reason: "May $day");
    }
    final after = await listed(
      tester,
      api,
      DateTime(2026, 5, 16),
      DateTime(2026, 5, 16),
    );
    expect(idsOf(after), isNot(contains(id)));
  });

  testWidgets("A12 allowing overlaps, a create and an update sharing time "
      "are stored; refusing them, the same calls fail, and an item already "
      "sharing time saves an update that keeps its times", (tester) async {
    final api = MockCalendarApi(latency: latency, allowsOverlaps: true);
    final busy = await stored(tester, api, envelope(start: 540, end: 600));
    final moving = await stored(tester, api, envelope(start: 840, end: 900));
    final later = await stored(tester, api, envelope(start: 960, end: 1020));
    final sharing = envelope(title: "Sharing", start: 570, end: 630);
    final onBusy = envelope(start: 555, end: 585);

    final created = await answer(tester, api.create(sharing));
    expect(created.error, isNull);
    final shared = (created.value! as Map<String, Object?>)["id"]! as String;
    final moved = await answer(tester, api.update(moving, onBusy));
    expect(moved.error, isNull);
    expect(
      (await fetched(tester, api, moving))["start"],
      utcText("2026-04-22T09:15"),
    );

    api.allowsOverlaps = false;
    final before = await listed(tester, api, wednesday, wednesday);
    expect(
      await errorOf(tester, api.create(sharing)),
      overlapWith(<String>[busy, moving, shared]),
    );
    expect(
      await errorOf(tester, api.update(later, onBusy)),
      overlapWith(<String>[busy, moving, shared]),
    );
    expect(await listed(tester, api, wednesday, wednesday), before);
    final renamed = await answer(
      tester,
      api.update(shared, envelope(title: "Renamed", start: 570, end: 630)),
    );
    expect(renamed.error, isNull);
    expect((await fetched(tester, api, shared))["title"], "Renamed");
  });

  test("A9 the schemas' summary keys", () {
    final expected = <CalendarItemType, List<String>>{
      CalendarItemType.task: <String>["status", "priority"],
      CalendarItemType.meeting: <String>["location", "attendees"],
      CalendarItemType.outOfOffice: <String>["reason"],
      CalendarItemType.deadline: <String>["project", "met"],
    };
    for (final type in CalendarItemType.values) {
      final schema = schemaOf(type);
      expect(schema.summaryKeys, expected[type], reason: type.label);
      expect(schema.summaryKeys.length, lessThanOrEqualTo(2));
      for (final key in schema.summaryKeys) {
        expect(schema.fieldOf(key), isNotNull, reason: "${type.label} $key");
      }
    }
  });
}
