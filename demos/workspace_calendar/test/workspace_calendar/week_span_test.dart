/// How itemFromSpan builds an item from the span a drop reports.
library;

import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// The Monday of the week shown.
final int weekStartDay = dayNumber(DateTime(2026, 4, 20));

/// The week from [weekStartDay], every day and every minute shown.
final GridTracks week = GridTracks(firstDay: weekStartDay, dayCount: 7);

CalendarEntryTime shapeOf(DateTime firstDay, int dayCount, int start, int end) {
  return (
    firstDay: dayNumber(firstDay),
    dayCount: dayCount,
    start: start,
    end: end,
  );
}

void main() {
  group("S2 itemFromSpan", () {
    test("itemFromSpan keeps the item and takes shapeFromSpan's days and "
        "minutes", () {
      final item = calendarItem(
        id: "item-9",
        type: CalendarItemType.meeting,
        title: "Planning",
        day: DateTime(2026, 4, 25),
        startMinute: 1080,
        endMinute: 1140,
        dayCount: 4,
        fields: const <String, Object?>{"location": "Room 4B"},
      );
      final from = gridSpanOf(item.time, week)!;
      const to = BoardSpan(rowStart: 69, colStart: 6, rowSpan: 4, colSpan: 1);
      final moved = itemFromSpan(item, from, to, week);
      final shape = shapeFromSpan(item.time, from, to, week);
      expect(moved.id, "item-9");
      expect(moved.type, CalendarItemType.meeting);
      expect(moved.title, "Planning");
      expect(moved.fields, const <String, Object?>{"location": "Room 4B"});
      expect(moved.time, shape);
      expect(moved.time, shapeOf(DateTime(2026, 4, 25), 1, 1020, 1080));
    });
  });
}
