/// The calendar's item: an entry whose payload is its type and fields,
/// read from and written to the API's envelope, whose start and end are
/// dates for an all-day item, and UTC times with a Z or local times with
/// no offset for a timed one.
library;

import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// A request's envelope, built anew on each call, its approvers a list:
/// from 10:00 on 2026-04-21 to 11:10 the next day.
Map<String, Object?> envelope({List<String> approvers = const ["Ana", "Bo"]}) {
  return <String, Object?>{
    "id": "item-4",
    "type": "request",
    "title": "Planning",
    "start": "2026-04-21T10:00",
    "end": "2026-04-22T11:10",
    "fields": <String, Object?>{
      "kind": "review",
      "approvers": <Object?>[...approvers],
    },
  };
}

/// The local time [local], written with no offset, in UTC with a Z, as
/// `DateTime.toIso8601String` writes it.
String utcText(String local) {
  return DateTime.parse(local).toUtc().toIso8601String();
}

/// [envelope] with its `start` and `end` replaced by [start] and [end].
Map<String, Object?> envelopeAt(String start, String end) {
  return <String, Object?>{...envelope(), "start": start, "end": end};
}

/// What `validateItemJson` reports for a start or an end it cannot read.
const String timeError =
    "Enter a date as YYYY-MM-DD for an all-day item, or a date and time in "
    "UTC as YYYY-MM-DDTHH:MM:SSZ on a whole minute of local time, or as a "
    "local YYYY-MM-DDTHH:MM at a time the clock reads.";

/// What `validateItemJson` reports for a start and an end of two forms.
const String mixedTimeError =
    "The start and end are both dates, for an all-day item, or both dates "
    "and times.";

/// The first instant of 2026 at half past an hour that is the later of the
/// two at which the local clock reads that time, on the zone's first day
/// of 25 hours; null where the zone has none. Days are built from their
/// fields, not stepped with `addDays`.
DateTime? _laterHalfPast() {
  for (var index = 0; DateTime(2026, 1, 1 + index).year == 2026; index++) {
    final day = DateTime(2026, 1, 1 + index);
    if (DateTime(2026, 1, 2 + index).difference(day).inHours != 25) {
      continue;
    }
    for (var minutes = 30; minutes < 25 * 60; minutes += 60) {
      final time = day.add(Duration(minutes: minutes));
      if (CalendarDates.isLaterOccurrence(time)) {
        return time;
      }
    }
  }
  return null;
}

void main() {
  test("CI1 an item reads its envelope's local start and end text and "
      "writes them in UTC, holds no day, minute or day-count key, and "
      "compares its payload deeply", () {
    final item = itemFromJson(envelope());
    expect(item.toJson(), <String, Object?>{
      ...envelope(),
      "start": utcText("2026-04-21T10:00"),
      "end": utcText("2026-04-22T11:10"),
    });
    expect(
      item.toJson().keys,
      isNot(
        anyElement(
          isIn(<String>["day", "startMinute", "endMinute", "dayCount"]),
        ),
      ),
    );
    expect(item.type, CalendarItemType.request);
    expect(item.start, DateTime(2026, 4, 21, 10));
    expect(item.end, DateTime(2026, 4, 22, 11, 10));

    final again = itemFromJson(envelope());
    expect(again == item, isTrue);
    expect(again.hashCode, item.hashCode);
    final changed = itemFromJson(envelope(approvers: const ["Ana", "Cy"]));
    expect(changed == item, isFalse);

    final task = calendarItem(
      type: CalendarItemType.task,
      title: "Write",
      start: DateTime(2026, 4, 22, 9),
      end: DateTime(2026, 4, 22, 10),
    );
    expect(task.color, harborTypeStyleOf(CalendarItemType.task).edge);
    expect(item.color, harborTypeStyleOf(CalendarItemType.request).edge);

    final missing = envelope()..remove("title");
    expect(() => itemFromJson(missing), throwsFormatException);
    final minutes = <String, Object?>{...envelope(), "start": 600};
    expect(() => itemFromJson(minutes), throwsFormatException);
  });

  test("CI2 isoDateTime writes a time in UTC with a Z, and parseIsoDateTime "
      "reads that text, with or without its milliseconds, as the local time "
      "of the same instant", () {
    expect(
      isoDateTime(DateTime.utc(2026, 4, 21, 14, 5)),
      "2026-04-21T14:05:00.000Z",
    );
    final local = DateTime(2026, 4, 21, 14, 5);
    final text = isoDateTime(local);
    expect(text, local.toUtc().toIso8601String());
    for (final read in <String>[
      text,
      text.replaceFirst(RegExp(r"\.000Z$"), "Z"),
    ]) {
      expect(parseIsoDateTime(read), local, reason: read);
    }
  });

  test("CI5 a whole local minute reads back from the text isoDateTime "
      "writes of it in any zone, one whose offset has seconds included", () {
    for (final local in <DateTime>[
      DateTime(1880, 1, 1, 10),
      DateTime(1960, 6, 1, 10, 15),
      DateTime(2026, 4, 21, 14, 5),
    ]) {
      expect(parseIsoDateTime(isoDateTime(local)), local, reason: "$local");
    }
  });

  test("CI3 parseIsoDateTime reads a local time with no offset as that "
      "local time, and refuses a UTC time with no seconds, off a whole "
      "local minute, on a day that does not exist or with another offset", () {
    expect(parseIsoDateTime("2026-04-21T10:00"), DateTime(2026, 4, 21, 10));
    final local = DateTime(2026, 4, 21, 14, 5);
    for (final text in <String>[
      "2026-04-21T14:05Z",
      isoDateTime(local.add(const Duration(seconds: 30))),
      isoDateTime(local.add(const Duration(milliseconds: 500))),
      "2026-02-30T14:05:00.000Z",
      "2026-04-21T24:05:00.000Z",
      "2026-04-21T14:04:60.000Z",
      "2026-04-21T14:05:00.000+02:00",
    ]) {
      expect(parseIsoDateTime(text), isNull, reason: text);
    }
  });

  final later = _laterHalfPast();
  test(
    "CI4 an item at the later instant of a time the clock reads twice "
    "keeps it through its envelope, and one from the earlier instant into "
    "the later is valid",
    () {
      final second = later!;
      final item = calendarItem(
        type: CalendarItemType.task,
        title: "Late",
        start: second,
        end: second.add(const Duration(minutes: 30)),
      );
      final again = itemFromJson(item.toJson());
      expect(again.start, second);
      expect(again.end, second.add(const Duration(minutes: 30)));
      final first = CalendarDates.timeAtWallMinute(
        CalendarDates.wallMinuteOf(second),
      )!;
      final across = calendarItem(
        type: CalendarItemType.task,
        title: "Across",
        start: first,
        end: second.subtract(const Duration(minutes: 15)),
        fields: const <String, Object?>{"status": "toDo"},
      );
      expect(validateItemJson(across.toJson()), isEmpty);
    },
    skip: later == null
        ? "No time the local clock reads twice in 2026; run in a zone with a "
              "daylight-saving change"
        : null,
  );

  test("CI6 an all-day item writes its start and end as dates, and "
      "itemTimeText writes a date for an all-day time and its instant in UTC "
      "for a timed one", () {
    final away = calendarItem(
      type: CalendarItemType.request,
      title: "Away",
      start: DateTime(2026, 4, 21),
      end: DateTime(2026, 4, 22),
      fields: const <String, Object?>{"kind": "travel"},
      isAllDay: true,
    );
    final json = away.toJson();
    expect(json["start"], "2026-04-21");
    expect(json["end"], "2026-04-22");
    expect(itemTimeText(DateTime(2026, 4, 21), allDay: true), "2026-04-21");
    expect(
      itemTimeText(DateTime(2026, 4, 21, 10), allDay: false),
      utcText("2026-04-21T10:00"),
    );
  });

  test("CI7 an envelope of dates reads as an all-day item and writes the "
      "same dates, and one of date-times from a day's start to the next "
      "day's reads, writes and reads back timed", () {
    final allDay = itemFromJson(envelopeAt("2026-04-21", "2026-04-22"));
    expect(allDay.isAllDay, isTrue);
    expect(allDay.start, DateTime(2026, 4, 21));
    expect(allDay.end, DateTime(2026, 4, 22));
    expect(allDay.toJson()["start"], "2026-04-21");
    expect(allDay.toJson()["end"], "2026-04-22");

    final whole = itemFromJson(
      envelopeAt("2026-04-21T00:00", "2026-04-22T00:00"),
    );
    expect(whole.isAllDay, isFalse);
    expect(whole.start, DateTime(2026, 4, 21));
    expect(whole.end, DateTime(2026, 4, 22));
    final written = whole.toJson();
    expect(written["start"], utcText("2026-04-21T00:00"));
    expect(written["end"], utcText("2026-04-22T00:00"));
    expect(itemFromJson(written).isAllDay, isFalse);
  });

  test("CI8 a date and a date-time in one envelope key the end with the "
      "mixed-form message and do not read, and a date that does not exist "
      "keys the start", () {
    for (final mixed in <Map<String, Object?>>[
      envelopeAt("2026-04-21", "2026-04-22T11:10"),
      envelopeAt("2026-04-21T10:00", "2026-04-22"),
    ]) {
      final errors = validateItemJson(mixed);
      expect(errors["end"], mixedTimeError, reason: "$mixed");
      expect(errors.containsKey("start"), isFalse, reason: "$mixed");
      expect(() => itemFromJson(mixed), throwsFormatException);
    }
    expect(
      validateItemJson(envelopeAt("2026-02-30", "2026-03-02")).keys,
      contains("start"),
    );
  });

  test("CI9 a start and an end the validator cannot read are each keyed "
      "with the message naming both forms", () {
    final errors = validateItemJson(envelopeAt("2026-04-21 10:00", "May 1"));
    expect(errors["start"], timeError);
    expect(errors["end"], timeError);
  });
}
