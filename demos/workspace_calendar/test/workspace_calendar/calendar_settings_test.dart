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

  group("C3 hoursErrorsOf", () {
    const office = DayHours(8 * 60, 18 * 60);
    const startError =
        "The start is 08:00 to 17:45, inside the calendar's "
        "hours.";
    const endError = "The end is 08:15 to 18:00, inside the calendar's hours.";

    test("is empty for minutes inside the hours, to their edges", () {
      expect(hoursErrorsOf(8 * 60, 18 * 60, office), isEmpty);
      expect(hoursErrorsOf(17 * 60 + 45, 18 * 60, office), isEmpty);
      expect(hoursErrorsOf(8 * 60, 8 * 60 + 15, office), isEmpty);
    });

    test("names a start or an end outside the hours", () {
      expect(hoursErrorsOf(7 * 60 + 45, 9 * 60, office), <String, String>{
        "startMinute": startError,
      });
      expect(hoursErrorsOf(17 * 60, 18 * 60 + 15, office), <String, String>{
        "endMinute": endError,
      });
    });

    test("names both for minutes wholly past either end", () {
      expect(hoursErrorsOf(18 * 60, 18 * 60 + 15, office), <String, String>{
        "startMinute": startError,
        "endMinute": endError,
      });
      expect(hoursErrorsOf(7 * 60, 8 * 60, office), <String, String>{
        "startMinute": startError,
        "endMinute": endError,
      });
    });
  });

  group("C4 CalendarSettings", () {
    test("starts on the whole day and the grid's own sizes", () {
      const settings = CalendarSettings();
      expect(settings.hours, DayHours.allDay);
      expect(settings.minDayWidth, 44.0);
      expect(settings.minSlotHeight, 16.0);
    });

    test("copyWith replaces what it is given and keeps the rest", () {
      const settings = CalendarSettings();
      const office = DayHours(8 * 60, 18 * 60);
      final copy = settings.copyWith(hours: office);
      expect(copy.hours, office);
      expect(copy.minDayWidth, settings.minDayWidth);
      expect(copy.minSlotHeight, settings.minSlotHeight);
      expect(settings.copyWith(minDayWidth: 60.0).minDayWidth, 60.0);
      expect(settings.copyWith(minSlotHeight: 24.0).minSlotHeight, 24.0);
    });

    test("compares by its values", () {
      // Built at run time, as DayHours' own comparison test explains.
      CalendarSettings settings({
        int start = 0,
        double width = 44.0,
        double height = 16.0,
      }) {
        return CalendarSettings(
          hours: DayHours(start, 24 * 60),
          minDayWidth: width,
          minSlotHeight: height,
        );
      }

      expect(settings(), settings());
      expect(settings().hashCode, settings().hashCode);
      expect(settings() == settings(start: 60), isFalse);
      expect(settings() == settings(width: 48.0), isFalse);
      expect(settings() == settings(height: 18.0), isFalse);
    });
  });

  group("C5 CalendarSettings weekdays", () {
    test("start on every weekday and take part in copyWith and ==", () {
      const settings = CalendarSettings();
      expect(settings.weekdays, WeekdaySet.all);
      final workweek = settings.copyWith(weekdays: WeekdaySet.workweek);
      expect(workweek.weekdays, WeekdaySet.workweek);
      expect(
        workweek.copyWith(minSlotHeight: 20.0).weekdays,
        WeekdaySet.workweek,
      );
      expect(workweek == settings, isFalse);
      final again = settings.copyWith(weekdays: WeekdaySet.workweek);
      expect(workweek == again, isTrue);
      expect(workweek.hashCode == settings.hashCode, isFalse);
    });
  });
}
