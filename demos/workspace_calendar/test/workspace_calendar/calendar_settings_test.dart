/// The values the calendar's settings choose: the weekdays it shows and
/// the hours it shows and schedules in.
library;

import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// [minute] minutes after the midnight of Tuesday, April 21 2026.
DateTime onTuesday(int minute) {
  return DateTime(2026, 4, 21, 0, minute);
}

void main() {
  group("C3 hoursErrorsOf", () {
    const office = DayHours(8 * 60, 18 * 60);
    const startError =
        "The start is from 08:00 to before 18:00, inside the calendar's "
        "hours.";
    const endError =
        "The end is from after 08:00 to 18:00, inside the calendar's hours.";

    test("is empty for minutes inside the hours, to their edges", () {
      expect(
        hoursErrorsOf(onTuesday(8 * 60), onTuesday(18 * 60), office),
        isEmpty,
      );
      expect(
        hoursErrorsOf(onTuesday(17 * 60 + 45), onTuesday(18 * 60), office),
        isEmpty,
      );
      expect(
        hoursErrorsOf(onTuesday(8 * 60), onTuesday(8 * 60 + 15), office),
        isEmpty,
      );
    });

    test("names a start or an end outside the hours", () {
      expect(
        hoursErrorsOf(onTuesday(7 * 60 + 45), onTuesday(9 * 60), office),
        <String, String>{"start": startError},
      );
      expect(
        hoursErrorsOf(onTuesday(17 * 60), onTuesday(18 * 60 + 15), office),
        <String, String>{"end": endError},
      );
    });

    test("names both for minutes wholly past either end", () {
      expect(
        hoursErrorsOf(onTuesday(18 * 60), onTuesday(18 * 60 + 15), office),
        <String, String>{"start": startError, "end": endError},
      );
      expect(
        hoursErrorsOf(onTuesday(7 * 60), onTuesday(8 * 60), office),
        <String, String>{"start": startError, "end": endError},
      );
    });
  });

  group("C4 CalendarSettings", () {
    test("starts on the whole day", () {
      const settings = CalendarSettings();
      expect(settings.hours, DayHours.allDay);
    });

    test("copyWith replaces the hours it is given", () {
      const settings = CalendarSettings();
      const office = DayHours(8 * 60, 18 * 60);
      final copy = settings.copyWith(hours: office);
      expect(copy.hours, office);
    });

    test("compares by its hours", () {
      // Built at run time, as DayHours' own comparison test explains.
      CalendarSettings settings({int start = 0}) {
        return CalendarSettings(hours: DayHours(start, 24 * 60));
      }

      expect(settings(), settings());
      expect(settings().hashCode, settings().hashCode);
      expect(settings() == settings(start: 60), isFalse);
    });
  });

  group("C5 CalendarSettings weekdays", () {
    test("start on every weekday and take part in copyWith and ==", () {
      const settings = CalendarSettings();
      expect(settings.weekdays, WeekdaySet.all);
      final workweek = settings.copyWith(weekdays: WeekdaySet.workweek);
      expect(workweek.weekdays, WeekdaySet.workweek);
      expect(
        workweek.copyWith(hours: const DayHours(8 * 60, 18 * 60)).weekdays,
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
        all.copyWith(hours: const DayHours(8 * 60, 18 * 60)).monthLayout,
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
        twelve.copyWith(hours: const DayHours(8 * 60, 18 * 60)).hourLabelFormat,
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

  group("C10 CalendarSettings edit mode", () {
    test("starts out of edit mode and takes part in copyWith and ==", () {
      const settings = CalendarSettings();
      expect(settings.editing, isFalse);
      final editing = settings.copyWith(editing: true);
      expect(editing.editing, isTrue);
      expect(
        editing.copyWith(hours: const DayHours(8 * 60, 18 * 60)).editing,
        isTrue,
      );
      expect(editing == settings, isFalse);
      expect(editing == settings.copyWith(editing: true), isTrue);
      expect(editing.hashCode == settings.hashCode, isFalse);
    });
  });
}
