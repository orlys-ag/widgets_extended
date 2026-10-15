/// The calendar's dates over some of the weekdays: the month grid, and the
/// shown day near a hidden one.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
