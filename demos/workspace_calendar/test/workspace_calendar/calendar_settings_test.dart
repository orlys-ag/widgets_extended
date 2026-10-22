/// The values the calendar's settings choose: the weekdays it shows and
/// the hours it shows and schedules in.
library;

import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  group("C6 CalendarSettings month layout", () {
    test("starts on Fit to screen and takes part in copyWith and ==", () {
      const settings = CalendarSettings();
      expect(settings.monthLayout, MonthLayout.fitScreen);
      final all = settings.copyWith(monthLayout: MonthLayout.showAll);
      expect(all.monthLayout, MonthLayout.showAll);
      expect(
        all.copyWith(minSlotHeight: 20.0).monthLayout,
        MonthLayout.showAll,
      );
      expect(all == settings, isFalse);
      final again = settings.copyWith(monthLayout: MonthLayout.showAll);
      expect(all == again, isTrue);
      expect(all.hashCode == settings.hashCode, isFalse);
    });

    test("names each layout", () {
      expect(MonthLayout.showAll.label, "Show all items");
      expect(MonthLayout.fitScreen.label, "Fit to screen");
    });
  });

  group("C8 CalendarSettings hour label format", () {
    test("starts on 24-hour and takes part in copyWith and ==", () {
      const settings = CalendarSettings();
      expect(settings.hourLabelFormat, HourLabelFormat.twentyFourHour);
      final twelve = settings.copyWith(
        hourLabelFormat: HourLabelFormat.twelveHour,
      );
      expect(twelve.hourLabelFormat, HourLabelFormat.twelveHour);
      expect(
        twelve.copyWith(minSlotHeight: 20.0).hourLabelFormat,
        HourLabelFormat.twelveHour,
      );
      expect(twelve == settings, isFalse);
      final again = settings.copyWith(
        hourLabelFormat: HourLabelFormat.twelveHour,
      );
      expect(twelve == again, isTrue);
      expect(twelve.hashCode == settings.hashCode, isFalse);
    });
  });

  group("C9 CalendarSettings month week scale", () {
    test("is 1 at the default slot height and under it, and above it the "
        "slot height over the default", () {
      const settings = CalendarSettings();
      expect(settings.monthWeekScale, 1.0);
      expect(
        settings.copyWith(minSlotHeight: minSlotHeightLow).monthWeekScale,
        1.0,
      );
      expect(settings.copyWith(minSlotHeight: 24.0).monthWeekScale, 1.5);
      expect(
        settings.copyWith(minSlotHeight: minSlotHeightHigh).monthWeekScale,
        3.0,
      );
    });

    test("withMonthWeekScale sets the slot height the scale reads, and at 1 "
        "keeps one at or under the default and lowers one over it to the "
        "default", () {
      const settings = CalendarSettings();
      expect(settings.withMonthWeekScale(2.5).minSlotHeight, 40.0);
      expect(
        settings
            .copyWith(minSlotHeight: 10.0)
            .withMonthWeekScale(1.0)
            .minSlotHeight,
        10.0,
      );
      expect(
        settings
            .copyWith(minSlotHeight: 30.0)
            .withMonthWeekScale(1.0)
            .minSlotHeight,
        defaultMinSlotHeight,
      );
    });
  });

  group("C10 CalendarSettings edit mode", () {
    test("starts out of edit mode and takes part in copyWith and ==", () {
      const settings = CalendarSettings();
      expect(settings.editing, isFalse);
      final editing = settings.copyWith(editing: true);
      expect(editing.editing, isTrue);
      expect(editing.copyWith(minSlotHeight: 20.0).editing, isTrue);
      expect(editing == settings, isFalse);
      expect(editing == settings.copyWith(editing: true), isTrue);
      expect(editing.hashCode == settings.hashCode, isFalse);
    });
  });
}
