/// The civil-date helpers a host reaches the calendar's days and minutes
/// through, under one name.
library;

import 'calendar_dates.dart' as dates;

/// The calendar's civil-date helpers and constants, on the local wall
/// clock: the day steps, day numbers and minutes that `DayHours`,
/// `WeekdaySet`, a `CalendarDataSource`'s reads by days and a
/// `CalendarEntry`'s times are counted in.
///
/// Its members are static, under this class's name, so they share no name
/// with a host's own helpers.
abstract final class CalendarDates {
  /// {@macro widgets_extended.calendar.defaultSlotMinutes}
  static const int defaultSlotMinutes = dates.defaultSlotMinutes;

  /// {@macro widgets_extended.calendar.slotMinuteChoices}
  static const List<int> slotMinuteChoices = dates.slotMinuteChoices;

  /// {@macro widgets_extended.calendar.minutesPerDay}
  static const int minutesPerDay = dates.minutesPerDay;

  /// {@macro widgets_extended.calendar.dateOnly}
  static DateTime dateOnly(DateTime date) {
    return dates.dateOnly(date);
  }

  /// {@macro widgets_extended.calendar.addDays}
  static DateTime addDays(DateTime date, int days) {
    return dates.addDays(date, days);
  }

  /// {@macro widgets_extended.calendar.weekdayColumn}
  static int weekdayColumn(DateTime date) {
    return dates.weekdayColumn(date);
  }

  /// {@macro widgets_extended.calendar.dayNumber}
  static int dayNumber(DateTime date) {
    return dates.dayNumber(date);
  }

  /// {@macro widgets_extended.calendar.dateOfDayNumber}
  static DateTime dateOfDayNumber(int day) {
    return dates.dateOfDayNumber(day);
  }

  /// {@macro widgets_extended.calendar.lastDayNumberOf}
  static int lastDayNumberOf(DateTime start, DateTime end) {
    return dates.lastDayNumberOf(start, end);
  }

  /// {@macro widgets_extended.calendar.minuteOfDay}
  static int minuteOfDay(DateTime time) {
    return dates.minuteOfDay(time);
  }

  /// {@macro widgets_extended.calendar.endMinuteOfDay}
  static int endMinuteOfDay(DateTime end) {
    return dates.endMinuteOfDay(end);
  }

  /// {@macro widgets_extended.calendar.wallMinuteOf}
  static int wallMinuteOf(DateTime time) {
    return dates.wallMinuteOf(time);
  }

  /// {@macro widgets_extended.calendar.timeAtWallMinute}
  static DateTime? timeAtWallMinute(int wall, {DateTime? from}) {
    return dates.timeAtWallMinute(wall, from: from);
  }

  /// {@macro widgets_extended.calendar.isLaterOccurrence}
  static bool isLaterOccurrence(DateTime time) {
    return dates.isLaterOccurrence(time);
  }
}
