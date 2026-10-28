/// The calendar's dates: the month grid and the shown days over some of
/// the weekdays, the weekday set, and the hours of a day.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

void main() {
  group("D1 MonthGrid over some of the weekdays", () {
    test("lays out the shown weekdays of each week holding the month", () {
      final april = MonthGrid(2026, 4, weekdays: WeekdaySet.workweek);
      expect(april.columnCount, 5);
      expect(april.weekCount, 5);
      expect(april.firstDay, DateTime(2026, 3, 30));
      expect(april.lastDay, DateTime(2026, 5, 1));
      expect(april.dateAt(0, 2), DateTime(2026, 4, 1));
      expect(april.cellOf(DateTime(2026, 4, 24)), (row: 3, col: 4));
    });

    test("drops a first week whose days of the month are all hidden", () {
      // August 2026 starts on a Saturday.
      final august = MonthGrid(2026, 8, weekdays: WeekdaySet.workweek);
      expect(MonthGrid(2026, 8).weekCount, 6);
      expect(august.weekCount, 5);
      expect(august.firstDay, DateTime(2026, 8, 3));
      expect(august.lastDay, DateTime(2026, 9, 4));
      expect(august.cellOf(DateTime(2026, 8, 31)), (row: 4, col: 0));
    });

    test("drops a last week whose days of the month are all hidden", () {
      // August 2026 ends on a Monday.
      final august = MonthGrid(
        2026,
        8,
        weekdays: WeekdaySet.of(const <int>[1, 2, 3, 4, 5, 6]),
      );
      expect(august.weekCount, 5);
      expect(august.firstDay, DateTime(2026, 7, 28));
      expect(august.lastDay, DateTime(2026, 8, 30));
      expect(august.cellOf(DateTime(2026, 8, 1)), (row: 0, col: 4));
    });
  });

  group("D2 the shown day near a hidden one", () {
    test("shownDayNear keeps a shown day and otherwise takes the nearest "
        "shown day of its month, later first", () {
      const workweek = WeekdaySet.workweek;
      expect(
        shownDayNear(DateTime(2026, 4, 22), workweek),
        DateTime(2026, 4, 22),
      );
      expect(
        shownDayNear(DateTime(2026, 4, 25), workweek),
        DateTime(2026, 4, 27),
      );
      // May 30 2026 is a Saturday, and June 1 is in the next month.
      expect(
        shownDayNear(DateTime(2026, 5, 30), workweek),
        DateTime(2026, 5, 29),
      );
    });

    test("shownDaysOfWeek lists the shown days of the day's Monday-first "
        "week", () {
      expect(shownDaysOfWeek(DateTime(2026, 4, 22), WeekdaySet.all), <DateTime>[
        for (var day = 20; day <= 26; day++) DateTime(2026, 4, day),
      ]);
      // A Sunday is the last day of its week, and May 1 2026 a Friday.
      expect(
        shownDaysOfWeek(DateTime(2026, 5, 3), WeekdaySet.workweek),
        <DateTime>[
          DateTime(2026, 4, 27),
          DateTime(2026, 4, 28),
          DateTime(2026, 4, 29),
          DateTime(2026, 4, 30),
          DateTime(2026, 5, 1),
        ],
      );
      expect(
        shownDaysOfWeek(
          DateTime(2026, 4, 22),
          WeekdaySet.of(const <int>[0, 2, 6]),
        ),
        <DateTime>[
          DateTime(2026, 4, 20),
          DateTime(2026, 4, 22),
          DateTime(2026, 4, 26),
        ],
      );
    });

    test("nextShownDay steps over hidden days either way", () {
      const workweek = WeekdaySet.workweek;
      expect(
        nextShownDay(DateTime(2026, 4, 22), 1, workweek),
        DateTime(2026, 4, 23),
      );
      expect(
        nextShownDay(DateTime(2026, 4, 24), 1, workweek),
        DateTime(2026, 4, 27),
      );
      expect(
        nextShownDay(DateTime(2026, 4, 27), -1, workweek),
        DateTime(2026, 4, 24),
      );
    });
  });

  group("D4 WeekdaySet's first weekday", () {
    test("orders the columns from it, finds each week's first day, and "
        "tells two sets apart by it", () {
      final fromWednesday = WeekdaySet.workweek.startingOn(2);
      expect(fromWednesday.firstColumn, 2);
      expect(fromWednesday.columns, <int>[2, 3, 4, 0, 1]);
      expect(fromWednesday.offsetOf(1), 6);
      // April 21, 2026 is a Tuesday, and April 22 a Wednesday.
      expect(
        fromWednesday.weekStartOf(DateTime(2026, 4, 21)),
        DateTime(2026, 4, 15),
      );
      expect(
        fromWednesday.weekStartOf(DateTime(2026, 4, 22)),
        DateTime(2026, 4, 22),
      );
      expect(
        fromWednesday.weekStartOfDay(dayNumber(DateTime(2026, 4, 21))),
        dayNumber(DateTime(2026, 4, 15)),
      );
      expect(fromWednesday == WeekdaySet.workweek, isFalse);
      expect(
        fromWednesday == WeekdaySet.of(<int>[0, 1, 2, 3, 4], firstColumn: 2),
        isTrue,
      );
    });
  });

  group("D5 MonthGrid and shownDaysOfWeek from the first weekday", () {
    // May 2026 runs from a Friday to a Sunday.
    test("starts each week on the first weekday", () {
      final may = MonthGrid(2026, 5, weekdays: WeekdaySet.all.startingOn(6));
      expect(may.firstDay, DateTime(2026, 4, 26));
    });

    test("holds the weeks a later first weekday adds", () {
      final may = MonthGrid(2026, 5, weekdays: WeekdaySet.all.startingOn(6));
      expect(may.weekCount, 6);
    });

    test("puts the shown weekdays' columns in the week's order", () {
      final may = MonthGrid(
        2026,
        5,
        weekdays: WeekdaySet.workweek.startingOn(6),
      );
      expect(may.dateAt(1, 0), DateTime(2026, 5, 4));
    });

    test("lists a week's shown days from its first weekday", () {
      expect(
        shownDaysOfWeek(
          DateTime(2026, 4, 21),
          WeekdaySet.workweek.startingOn(6),
        ),
        <DateTime>[for (var day = 20; day <= 24; day++) DateTime(2026, 4, day)],
      );
    });
  });

  group("C1 WeekdaySet", () {
    test("weekdayColumnOfDay agrees with weekdayColumn on either side of "
        "day 0", () {
      for (var offset = -9; offset <= 9; offset++) {
        final date = DateTime(1970, 1, 1 + offset);
        expect(
          weekdayColumnOfDay(dayNumber(date)),
          weekdayColumn(date),
          reason: "$date",
        );
      }
    });

    test("holds the columns it was given", () {
      expect(<bool>[
        for (var column = 0; column < 7; column++)
          WeekdaySet.all.containsColumn(column),
      ], List<bool>.filled(7, true));
      expect(
        <bool>[
          for (var column = 0; column < 7; column++)
            WeekdaySet.workweek.containsColumn(column),
        ],
        <bool>[true, true, true, true, true, false, false],
      );
      final wednesday = WeekdaySet.of(const <int>[2]);
      expect(wednesday.containsDate(DateTime(2026, 4, 22)), isTrue);
      expect(wednesday.containsDate(DateTime(2026, 4, 23)), isFalse);
      expect(wednesday.containsDay(dayNumber(DateTime(2026, 4, 29))), isTrue);
      expect(wednesday.containsDay(dayNumber(DateTime(2026, 4, 28))), isFalse);
    });

    test("compares by the columns it holds", () {
      final weekdays = WeekdaySet.of(const <int>[4, 3, 2, 1, 0]);
      expect(weekdays, WeekdaySet.workweek);
      expect(weekdays.hashCode, WeekdaySet.workweek.hashCode);
      expect(weekdays == WeekdaySet.all, isFalse);
      expect(WeekdaySet.of(const <int>[]).isEmpty, isTrue);
      expect(WeekdaySet.workweek.isEmpty, isFalse);
    });
  });

  group("C2 DayHours", () {
    test("counts its slots and holds the minutes inside it", () {
      const office = DayHours(8 * 60, 18 * 60);
      expect(DayHours.allDay.slotCountOf(15), 96);
      expect(office.slotCountOf(15), 40);
      expect(office.contains(8 * 60, 18 * 60), isTrue);
      expect(office.contains(7 * 60 + 45, 9 * 60), isFalse);
      expect(office.contains(17 * 60, 18 * 60 + 15), isFalse);
    });

    test("compares by its minutes", () {
      // Built at run time: two const instances with the same minutes are
      // one object, which compares equal whatever == does.
      DayHours hours(int start, int end) {
        return DayHours(start, end);
      }

      expect(hours(8 * 60, 18 * 60), hours(480, 1080));
      expect(hours(8 * 60, 18 * 60).hashCode, hours(480, 1080).hashCode);
      expect(hours(8 * 60, 18 * 60) == hours(8 * 60, 17 * 60), isFalse);
      expect(hours(8 * 60, 18 * 60) == hours(9 * 60, 18 * 60), isFalse);
    });
  });

  group("DH1 DayHours' starts and ends", () {
    test("holds a start from its start to before its end, and an end from "
        "after its start to its end", () {
      const office = DayHours(480, 1080);
      expect(office.holdsStart(480), isTrue);
      expect(office.holdsStart(1065), isTrue);
      expect(office.holdsStart(465), isFalse);
      expect(office.holdsStart(1080), isFalse);
      expect(office.holdsEnd(495), isTrue);
      expect(office.holdsEnd(1080), isTrue);
      expect(office.holdsEnd(480), isFalse);
      expect(office.holdsEnd(1095), isFalse);
      expect(DayHours.allDay.holdsStart(0), isTrue);
      expect(DayHours.allDay.holdsEnd(1440), isTrue);
    });
  });

  group("DI1 the developers' text", () {
    test("isoTime writes hours and minutes, 1440 as 24:00, and the weekday "
        "sets and day hours write themselves with it", () {
      expect(isoTime(0), "00:00");
      expect(isoTime(570), "09:30");
      expect(isoTime(1440), "24:00");
      expect(
        WeekdaySet.workweek.startingOn(2).toString(),
        "WeekdaySet(We, Th, Fr, Mo, Tu; from We)",
      );
      expect(const DayHours(480, 1080).toString(), "DayHours(08:00-18:00)");
    });
  });
}
