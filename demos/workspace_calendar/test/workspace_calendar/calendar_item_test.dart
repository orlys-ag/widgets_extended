/// The calendar's item: an entry whose payload is its type and fields,
/// read from and written to the API's envelope.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// A meeting's envelope, built anew on each call, its attendees a list.
Map<String, Object?> envelope({List<String> attendees = const ["Ana", "Bo"]}) {
  return <String, Object?>{
    "id": "item-4",
    "type": "meeting",
    "title": "Planning",
    "day": "2026-04-21",
    "startMinute": 600,
    "endMinute": 660,
    "dayCount": 2,
    "fields": <String, Object?>{
      "location": "Room 4B",
      "attendees": <Object?>[...attendees],
    },
  };
}

void main() {
  test("CI1 an item reads and writes its envelope and compares its payload "
      "deeply", () {
    final item = itemFromJson(envelope());
    expect(item.toJson(), envelope());
    expect(item.type, CalendarItemType.meeting);
    // From 10:00 on its day to 11:00 on the next, its second.
    expect(item.start, DateTime(2026, 4, 21, 10));
    expect(item.end, DateTime(2026, 4, 22, 11));

    final again = itemFromJson(envelope());
    expect(again == item, isTrue);
    expect(again.hashCode, item.hashCode);
    final changed = itemFromJson(envelope(attendees: const ["Ana", "Cy"]));
    expect(changed == item, isFalse);

    final task = calendarItem(
      type: CalendarItemType.task,
      title: "Write",
      day: DateTime(2026, 4, 22),
      startMinute: 540,
      endMinute: 600,
    );
    expect(task.color, harborTypeStyleOf(CalendarItemType.task).edge);
    expect(item.color, harborTypeStyleOf(CalendarItemType.meeting).edge);

    final missing = envelope()..remove("title");
    expect(() => itemFromJson(missing), throwsFormatException);
  });
}
