/// The mock API: its envelope and schema rules, the overlap rule, the
/// failure policy and latency, the copies it hands in and out, and the
/// seed. Every call is answered through the test binding's fake time.
library;

import 'package:examples/workspace_calendar/calendar_api.dart';
import 'package:examples/workspace_calendar/calendar_data.dart';
import 'package:examples/workspace_calendar/calendar_schema.dart';
import 'package:examples/workspace_calendar/mock_calendar_api.dart';
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

Map<String, Object?> envelope({
  CalendarItemType type = CalendarItemType.task,
  String title = "Item",
  DateTime? day,
  int start = 9 * 60,
  int end = 10 * 60,
  int dayCount = 1,
  Map<String, Object?>? fields,
}) {
  return <String, Object?>{
    "type": type.id,
    "title": title,
    "day": isoDate(day ?? wednesday),
    "startMinute": start,
    "endMinute": end,
    "dayCount": dayCount,
    "fields": fields ?? validFields(type),
  };
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
    expect(got["startMinute"], 11 * 60);
    expect(got["endMinute"], 12 * 60 + 30);
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
        "startMinute": 10 * 60,
        "endMinute": 11 * 60,
      }),
    );
    expect(linkless.error, isNull);
    final id = (linkless.value! as Map<String, Object?>)["id"]! as String;
    expect(
      ((await fetched(tester, api, id))["fields"]! as Map)["videoLink"],
      "",
    );
  });

  testWidgets("A4 time and day-count rules", (tester) async {
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

    Map<String, Object?> withKey(String key, Object? value) {
      return <String, Object?>{...envelope(start: 0, end: 60), key: value};
    }

    expect(
      await created(envelope(start: 540, end: 540)),
      validationOf(<String>{"endMinute"}),
    );
    expect(
      await created(envelope(start: 550, end: 600)),
      validationOf(<String>{"startMinute"}),
    );
    expect(
      await created(envelope(start: 540, end: 610)),
      validationOf(<String>{"endMinute"}),
    );
    expect(
      await created(envelope(start: -15, end: 600)),
      validationOf(<String>{"startMinute"}),
    );
    expect(
      await created(envelope(start: 1380, end: 1455)),
      validationOf(<String>{"endMinute"}),
    );
    expect(
      await created(envelope(dayCount: 0)),
      validationOf(<String>{"dayCount"}),
    );
    expect(
      await created(envelope(dayCount: 367)),
      validationOf(<String>{"dayCount"}),
    );
    expect(
      await created(withKey("day", "21/04/2026")),
      validationOf(<String>{"day"}),
    );
    expect(
      await created(withKey("startMinute", "540")),
      validationOf(<String>{"startMinute"}),
    );
    expect(
      await created(withKey("endMinute", 600.0)),
      validationOf(<String>{"endMinute"}),
    );
    expect(
      await created(withKey("dayCount", "2")),
      validationOf(<String>{"dayCount"}),
    );
    expect(
      await created(envelope(start: 1440, end: 1455)),
      validationOf(<String>{"startMinute", "endMinute"}),
    );
    expect(
      await listed(tester, api, DateTime(2025, 1, 1), DateTime(2027, 12, 31)),
      before,
    );

    final longest = await answer(
      tester,
      api.create(envelope(start: 1380, end: 1440, dayCount: 366)),
    );
    expect(longest.error, isNull);
    final id = (longest.value! as Map<String, Object?>)["id"]! as String;
    expect((await fetched(tester, api, id))["dayCount"], 366);
  });

  testWidgets("A5 overlap rules", (tester) async {
    final api = MockCalendarApi(latency: latency);
    final thursday = DateTime(2026, 4, 23);
    final away = await stored(
      tester,
      api,
      envelope(type: CalendarItemType.outOfOffice, start: 540, end: 600),
    );
    final meeting = await stored(
      tester,
      api,
      envelope(
        type: CalendarItemType.meeting,
        day: DateTime(2026, 4, 27),
        start: 13 * 60,
        end: 14 * 60,
        dayCount: 3,
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
      await created(
        envelope(day: DateTime(2026, 4, 28), start: 13 * 60 + 30, end: 14 * 60),
      ),
      overlapWith(<String>[meeting]),
    );
    expect(
      await created(
        envelope(
          type: CalendarItemType.meeting,
          day: wednesday,
          start: 15 * 60,
          end: 15 * 60 + 30,
          dayCount: 2,
        ),
      ),
      overlapWith(<String>[single]),
    );
    expect(
      await created(
        envelope(
          type: CalendarItemType.outOfOffice,
          day: wednesday,
          start: 15 * 60 + 30,
          end: 17 * 60,
          dayCount: 2,
        ),
      ),
      overlapWith(<String>[single]),
    );
    expect(
      await listed(tester, api, DateTime(2026, 4, 20), DateTime(2026, 5, 3)),
      before,
    );

    final after = await answer(
      tester,
      api.create(envelope(start: 600, end: 660)),
    );
    expect(after.error, isNull);
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
    expect((await fetched(tester, api, away))["endMinute"], 585);

    // Two single-day items of any types are kept apart too.
    final early = await stored(
      tester,
      api,
      envelope(day: thursday, start: 9 * 60, end: 10 * 60),
    );
    final thursdayBefore = await listed(tester, api, thursday, thursday);
    expect(
      await created(
        envelope(day: thursday, start: 9 * 60 + 30, end: 10 * 60 + 30),
      ),
      overlapWith(<String>[early]),
    );
    expect(
      await created(
        envelope(
          type: CalendarItemType.deadline,
          day: thursday,
          start: 15 * 60 + 45,
          end: 16 * 60,
        ),
      ),
      overlapWith(<String>[single]),
    );
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
    expect(dayOff["day"], "2026-04-20");
    expect(dayOff["startMinute"], 9 * 60);
    expect(dayOff["endMinute"], 17 * 60);

    final may = await listed(
      tester,
      api,
      DateTime(2026, 5, 1),
      DateTime(2026, 5, 31),
    );
    final trip = may.singleWhere((item) => item["title"] == "Conference trip");
    expect(trip["type"], CalendarItemType.outOfOffice.id);
    expect(trip["day"], "2026-05-11");
    expect(trip["dayCount"], 5);
    expect(trip["startMinute"], 9 * 60);
    expect(trip["endMinute"], 17 * 60);
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
