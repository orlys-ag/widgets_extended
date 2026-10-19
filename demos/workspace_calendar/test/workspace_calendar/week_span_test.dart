/// How an item's days and minutes map onto the timed grid's tracks, and
/// back from the span a drop reports, and the minute a grid's Add looks
/// from.
library;

import 'package:widgets_extended/calendar/calendar.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
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
  group("S1 gridSpanOf", () {
    test("places a day's slots in its column, below the header", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      expect(
        gridSpanOf(tuesday, week),
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 12, colSpan: 1),
      );
    });

    test("clips the days outside the week", () {
      final fromFriday = shapeOf(DateTime(2026, 4, 17), 4, 1080, 1140);
      expect(
        gridSpanOf(fromFriday, week),
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 1),
      );
      final fromSaturday = shapeOf(DateTime(2026, 4, 25), 4, 1080, 1140);
      expect(
        gridSpanOf(fromSaturday, week),
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 4, colSpan: 2),
      );
    });

    test("is null for an item with no day in the week", () {
      final later = shapeOf(DateTime(2026, 5, 4), 1, 600, 660);
      expect(gridSpanOf(later, week), isNull);
    });

    test("clips to a one-day grid on both sides", () {
      final wednesday = GridTracks(
        firstDay: dayNumber(DateTime(2026, 4, 22)),
        dayCount: 1,
      );
      final threeDays = shapeOf(DateTime(2026, 4, 21), 3, 1080, 1140);
      expect(
        gridSpanOf(threeDays, wednesday),
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 1),
      );
      final thursday = shapeOf(DateTime(2026, 4, 23), 1, 1080, 1140);
      expect(gridSpanOf(thursday, wednesday), isNull);
    });
  });

  group("S2 shapeFromSpan and itemFromSpan", () {
    test("a move shifts the first day by the column change and the minutes "
        "by the row change", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      final from = gridSpanOf(tuesday, week)!;
      final moved = shapeFromSpan(
        tuesday,
        from,
        const BoardSpan(rowStart: 45, colStart: 3, rowSpan: 12, colSpan: 1),
        week,
      );
      expect(moved, shapeOf(DateTime(2026, 4, 22), 1, 660, 840));
    });

    test("a right-edge resize of one column adds a day", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      final from = gridSpanOf(tuesday, week)!;
      final resized = shapeFromSpan(
        tuesday,
        from,
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 12, colSpan: 2),
        week,
      );
      expect(resized, shapeOf(DateTime(2026, 4, 21), 2, 600, 780));
    });

    test("an item clipped at the week's start keeps its hidden days", () {
      final fromFriday = shapeOf(DateTime(2026, 4, 17), 4, 1080, 1140);
      final from = gridSpanOf(fromFriday, week)!;
      final moved = shapeFromSpan(
        fromFriday,
        from,
        const BoardSpan(rowStart: 73, colStart: 2, rowSpan: 4, colSpan: 1),
        week,
      );
      expect(moved, shapeOf(DateTime(2026, 4, 18), 4, 1080, 1140));
      final toSunday = shapeFromSpan(
        fromFriday,
        from,
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 7),
        week,
      );
      expect(toSunday, shapeOf(DateTime(2026, 4, 17), 10, 1080, 1140));
    });

    test("an item clipped at the week's end ends on the column its right "
        "edge is dropped on", () {
      final fromSaturday = shapeOf(DateTime(2026, 4, 25), 4, 1080, 1140);
      final from = gridSpanOf(fromSaturday, week)!;
      final shortened = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 4, colSpan: 1),
        week,
      );
      expect(shortened, shapeOf(DateTime(2026, 4, 25), 1, 1080, 1140));
      final movedLeft = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 5, rowSpan: 4, colSpan: 2),
        week,
      );
      expect(movedLeft, shapeOf(DateTime(2026, 4, 24), 4, 1080, 1140));
      final longer = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 6, colSpan: 2),
        week,
      );
      expect(longer, shapeOf(DateTime(2026, 4, 25), 4, 1080, 1170));
    });

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

  group("S3 a grid over some of the weekdays", () {
    final tuesday = DateTime(2026, 4, 21);
    final wednesday = DateTime(2026, 4, 22);
    final thursday = DateTime(2026, 4, 23);

    /// The week without its Wednesday: Monday, Tuesday, Thursday to
    /// Sunday in columns 1 to 6.
    final noWednesday = GridTracks(
      firstDay: weekStartDay,
      dayCount: 7,
      weekdays: WeekdaySet.of(const <int>[0, 1, 3, 4, 5, 6]),
    );

    test("lays the held days out in order, the others with no column", () {
      expect(noWednesday.columnCount, 6);
      expect(noWednesday.dayAt(2), dayNumber(tuesday));
      expect(noWednesday.dayAt(3), dayNumber(thursday));
      expect(noWednesday.dateAt(6), DateTime(2026, 4, 26));
      expect(noWednesday.columnOf(dayNumber(thursday)), 3);
      expect(noWednesday.columnOf(dayNumber(wednesday)), isNull);
      expect(noWednesday.firstColumnFrom(dayNumber(wednesday)), 3);
      expect(noWednesday.lastColumnUpTo(dayNumber(wednesday)), 2);
      expect(noWednesday.firstColumnFrom(weekStartDay + 7), 7);
      expect(noWednesday.lastColumnUpTo(weekStartDay - 1), 0);
    });

    test("gridSpanOf joins the columns either side of a hidden day", () {
      expect(
        gridSpanOf(shapeOf(tuesday, 3, 600, 660), noWednesday),
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 4, colSpan: 2),
      );
      expect(
        gridSpanOf(shapeOf(wednesday, 2, 600, 660), noWednesday),
        const BoardSpan(rowStart: 41, colStart: 3, rowSpan: 4, colSpan: 1),
      );
      expect(gridSpanOf(shapeOf(wednesday, 1, 600, 660), noWednesday), isNull);
    });

    test("the weekend leaves a workweek grid", () {
      final workweek = GridTracks(
        firstDay: weekStartDay,
        dayCount: 7,
        weekdays: WeekdaySet.workweek,
      );
      expect(workweek.columnCount, 5);
      expect(workweek.dateAt(5), DateTime(2026, 4, 24));
      expect(
        gridSpanOf(shapeOf(DateTime(2026, 4, 24), 3, 600, 660), workweek),
        const BoardSpan(rowStart: 41, colStart: 5, rowSpan: 4, colSpan: 1),
      );
      expect(
        gridSpanOf(shapeOf(DateTime(2026, 4, 25), 2, 600, 660), workweek),
        isNull,
      );
    });

    test("a move shifts the days by the days between the columns", () {
      final one = shapeOf(tuesday, 1, 600, 660);
      expect(
        shapeFromSpan(
          one,
          gridSpanOf(one, noWednesday)!,
          const BoardSpan(rowStart: 41, colStart: 3, rowSpan: 4, colSpan: 1),
          noWednesday,
        ),
        shapeOf(thursday, 1, 600, 660),
      );
      final three = shapeOf(tuesday, 3, 600, 660);
      expect(
        shapeFromSpan(
          three,
          gridSpanOf(three, noWednesday)!,
          const BoardSpan(rowStart: 41, colStart: 3, rowSpan: 4, colSpan: 2),
          noWednesday,
        ),
        shapeOf(thursday, 3, 600, 660),
      );
    });

    test("a right-edge resize ends on its last column's day", () {
      final one = shapeOf(tuesday, 1, 600, 660);
      expect(
        shapeFromSpan(
          one,
          gridSpanOf(one, noWednesday)!,
          const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 4, colSpan: 2),
          noWednesday,
        ),
        shapeOf(tuesday, 3, 600, 660),
      );
    });

    test("a create range over the hidden day covers it", () {
      expect(
        createRangeOver(noWednesday, (row: 44, col: 3), (row: 41, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 600,
          endMinute: 660,
          dayCount: 3,
        ),
      );
      expect(
        createRangeAt(noWednesday, (row: 41, col: 3)),
        CreateRange(
          day: thursday,
          startMinute: 600,
          endMinute: 615,
          dayCount: 1,
        ),
      );
    });
  });

  group("S4 a grid over part of the day", () {
    final tuesday = DateTime(2026, 4, 21);

    /// The week from 08:00 to 18:00: rows 1 to 40.
    final office = GridTracks(
      firstDay: weekStartDay,
      dayCount: 7,
      hours: const DayHours(8 * 60, 18 * 60),
    );

    test("rows count from the first hour", () {
      expect(office.rowCount, 40);
      expect(office.minuteAt(1), 8 * 60);
      expect(office.minuteAt(41), 18 * 60);
      expect(office.rowOf(9 * 60), 5);
    });

    test("gridSpanOf clips the minutes outside the hours", () {
      expect(
        gridSpanOf(shapeOf(tuesday, 1, 9 * 60, 10 * 60), office),
        const BoardSpan(rowStart: 5, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(
        gridSpanOf(shapeOf(tuesday, 1, 7 * 60, 9 * 60), office),
        const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(
        gridSpanOf(shapeOf(tuesday, 1, 17 * 60, 19 * 60), office),
        const BoardSpan(rowStart: 37, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(gridSpanOf(shapeOf(tuesday, 1, 6 * 60, 8 * 60), office), isNull);
      expect(gridSpanOf(shapeOf(tuesday, 1, 18 * 60, 19 * 60), office), isNull);
    });

    test("a move reads the minutes from the rows below the first hour", () {
      final shape = shapeOf(tuesday, 1, 9 * 60, 10 * 60);
      expect(
        shapeFromSpan(
          shape,
          gridSpanOf(shape, office)!,
          const BoardSpan(rowStart: 9, colStart: 2, rowSpan: 4, colSpan: 1),
          office,
        ),
        shapeOf(tuesday, 1, 10 * 60, 11 * 60),
      );
    });

    test("create ranges start at the hours and stop at their end", () {
      expect(
        createRangeAt(office, (row: 1, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 8 * 60,
          endMinute: 8 * 60 + 15,
          dayCount: 1,
        ),
      );
      expect(
        createRangeAt(office, (row: 40, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 17 * 60 + 45,
          endMinute: 18 * 60,
          dayCount: 1,
        ),
      );
      expect(
        createRangeOver(office, (row: 1, col: 2), (row: 4, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 8 * 60,
          endMinute: 9 * 60,
          dayCount: 1,
        ),
      );
    });
  });
}
