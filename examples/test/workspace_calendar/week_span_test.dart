/// How an item's days and minutes map onto the week grid's tracks, and
/// back from the span a drop reports.
library;

import 'package:examples/workspace_calendar/calendar_data.dart';
import 'package:examples/workspace_calendar/calendar_item.dart';
import 'package:examples/workspace_calendar/calendar_schema.dart';
import 'package:examples/workspace_calendar/week_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// The Monday of the week shown.
final int weekStartDay = dayNumber(DateTime(2026, 4, 20));

ItemShape shapeOf(
  DateTime firstDay,
  int dayCount,
  int start,
  int end, {
  CalendarItemType type = CalendarItemType.task,
}) {
  return (
    type: type,
    firstDay: dayNumber(firstDay),
    dayCount: dayCount,
    start: start,
    end: end,
  );
}

void main() {
  group("S1 weekSpanOf", () {
    test("places a day's slots in its column, below the header", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      expect(
        weekSpanOf(tuesday, weekStartDay),
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 12, colSpan: 1),
      );
    });

    test("clips the days outside the week", () {
      final fromFriday = shapeOf(DateTime(2026, 4, 17), 4, 1080, 1140);
      expect(
        weekSpanOf(fromFriday, weekStartDay),
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 1),
      );
      final fromSaturday = shapeOf(DateTime(2026, 4, 25), 4, 1080, 1140);
      expect(
        weekSpanOf(fromSaturday, weekStartDay),
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 4, colSpan: 2),
      );
    });

    test("is null for an item with no day in the week", () {
      final later = shapeOf(DateTime(2026, 5, 4), 1, 600, 660);
      expect(weekSpanOf(later, weekStartDay), isNull);
    });
  });

  group("S2 shapeFromSpan and itemFromSpan", () {
    test("a move shifts the first day by the column change and the minutes "
        "by the row change", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      final from = weekSpanOf(tuesday, weekStartDay)!;
      final moved = shapeFromSpan(
        tuesday,
        from,
        const BoardSpan(rowStart: 45, colStart: 3, rowSpan: 12, colSpan: 1),
        weekStartDay,
      );
      expect(moved, shapeOf(DateTime(2026, 4, 22), 1, 660, 840));
    });

    test("a right-edge resize of one column adds a day", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      final from = weekSpanOf(tuesday, weekStartDay)!;
      final resized = shapeFromSpan(
        tuesday,
        from,
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 12, colSpan: 2),
        weekStartDay,
      );
      expect(resized, shapeOf(DateTime(2026, 4, 21), 2, 600, 780));
    });

    test("an item clipped at the week's start keeps its hidden days", () {
      final fromFriday = shapeOf(DateTime(2026, 4, 17), 4, 1080, 1140);
      final from = weekSpanOf(fromFriday, weekStartDay)!;
      final moved = shapeFromSpan(
        fromFriday,
        from,
        const BoardSpan(rowStart: 73, colStart: 2, rowSpan: 4, colSpan: 1),
        weekStartDay,
      );
      expect(moved, shapeOf(DateTime(2026, 4, 18), 4, 1080, 1140));
      final toSunday = shapeFromSpan(
        fromFriday,
        from,
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 7),
        weekStartDay,
      );
      expect(toSunday, shapeOf(DateTime(2026, 4, 17), 10, 1080, 1140));
    });

    test("an item clipped at the week's end ends on the column its right "
        "edge is dropped on", () {
      final fromSaturday = shapeOf(DateTime(2026, 4, 25), 4, 1080, 1140);
      final from = weekSpanOf(fromSaturday, weekStartDay)!;
      final shortened = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 4, colSpan: 1),
        weekStartDay,
      );
      expect(shortened, shapeOf(DateTime(2026, 4, 25), 1, 1080, 1140));
      final movedLeft = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 5, rowSpan: 4, colSpan: 2),
        weekStartDay,
      );
      expect(movedLeft, shapeOf(DateTime(2026, 4, 24), 4, 1080, 1140));
      final longer = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 6, colSpan: 2),
        weekStartDay,
      );
      expect(longer, shapeOf(DateTime(2026, 4, 25), 4, 1080, 1170));
    });

    test("itemFromSpan keeps the item and takes shapeFromSpan's days and "
        "minutes", () {
      final item = CalendarItem(
        id: "item-9",
        type: CalendarItemType.meeting,
        title: "Planning",
        day: DateTime(2026, 4, 25),
        startMinute: 1080,
        endMinute: 1140,
        dayCount: 4,
        fields: const <String, Object?>{"location": "Room 4B"},
      );
      final from = weekSpanOf(item.shape, weekStartDay)!;
      const to = BoardSpan(rowStart: 69, colStart: 6, rowSpan: 4, colSpan: 1);
      final moved = itemFromSpan(item, from, to, weekStartDay);
      final shape = shapeFromSpan(item.shape, from, to, weekStartDay);
      expect(moved.id, "item-9");
      expect(moved.type, CalendarItemType.meeting);
      expect(moved.title, "Planning");
      expect(moved.fields, const <String, Object?>{"location": "Room 4B"});
      expect(moved.shape, shape);
      expect(
        moved.shape,
        shapeOf(
          DateTime(2026, 4, 25),
          1,
          1020,
          1080,
          type: CalendarItemType.meeting,
        ),
      );
    });
  });
}
