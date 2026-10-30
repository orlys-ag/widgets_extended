/// The calendar's item: an entry whose payload is its type and fields,
/// read from and written to the API's envelope, whose start and end are
/// UTC times with a Z, or local times with no offset as before.
library;

import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// A meeting's envelope, built anew on each call, its attendees a list:
/// from 10:00 on 2026-04-21 to 11:10 the next day.
Map<String, Object?> envelope({List<String> attendees = const ["Ana", "Bo"]}) {
  return <String, Object?>{
    "id": "item-4",
    "type": "meeting",
    "title": "Planning",
    "start": "2026-04-21T10:00",
    "end": "2026-04-22T11:10",
    "fields": <String, Object?>{
      "location": "Room 4B",
      "attendees": <Object?>[...attendees],
    },
  };
}

/// The local time [local], written with no offset, in UTC with a Z, as
/// `DateTime.toIso8601String` writes it.
String utcText(String local) {
  return DateTime.parse(local).toUtc().toIso8601String();
}

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
    expect(item.type, CalendarItemType.meeting);
    expect(item.start, DateTime(2026, 4, 21, 10));
    expect(item.end, DateTime(2026, 4, 22, 11, 10));

    final again = itemFromJson(envelope());
    expect(again == item, isTrue);
    expect(again.hashCode, item.hashCode);
    final changed = itemFromJson(envelope(attendees: const ["Ana", "Cy"]));
    expect(changed == item, isFalse);

    final task = calendarItem(
      type: CalendarItemType.task,
      title: "Write",
      start: DateTime(2026, 4, 22, 9),
      end: DateTime(2026, 4, 22, 10),
    );
    expect(task.color, harborTypeStyleOf(CalendarItemType.task).edge);
    expect(item.color, harborTypeStyleOf(CalendarItemType.meeting).edge);

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
}
