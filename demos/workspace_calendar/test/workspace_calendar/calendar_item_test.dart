/// The calendar's item: an entry whose payload is its type and fields,
/// read from and written to the API's envelope.
library;

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

void main() {
  test("CI1 an item reads and writes its envelope's start and end text, "
      "holds no day, minute or day-count key, and compares its payload "
      "deeply", () {
    final item = itemFromJson(envelope());
    expect(item.toJson(), envelope());
    expect(item.toJson()["start"], "2026-04-21T10:00");
    expect(item.toJson()["end"], "2026-04-22T11:10");
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
}
