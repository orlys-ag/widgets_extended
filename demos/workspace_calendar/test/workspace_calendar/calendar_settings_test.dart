/// The values the calendar's settings choose: the weekdays it shows and
/// the hours it shows and schedules in.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      expect(DayHours.allDay.slotCount, 96);
      expect(office.slotCount, 40);
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
}
