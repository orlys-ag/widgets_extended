/// What the calendar's settings choose: whether it is in edit mode, how far
/// the history lock keeps the past as it is, the weekdays it shows and the
/// one its weeks start on, the hours it shows
/// and schedules in, how the timed grid labels its hours, how Month fits
/// its weeks, the least width of a day in Week, Day and Month, and the
/// least height of the timed grid's slots, which also scales the height
/// of Month's weeks. Beside them: the field errors, keyed as
/// `validateItemJson` keys them, of an item outside the calendar's hours,
/// [hoursErrorsOf]; and the names of Month's layouts in the settings sheet,
/// [MonthLayoutLabel].
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';

/// The field errors of an item from [start] to [end] minutes that does not
/// lie in [hours], keyed as `validateItemJson` keys them: the start when it
/// does not begin a slot inside them, the end when it does not end one.
Map<String, String> hoursErrorsOf(int start, int end, DayHours hours) {
  return <String, String>{
    if (!hours.holdsStart(start))
      "startMinute":
          "The start is ${clockLabel(hours.start)} to "
          "${clockLabel(hours.end - minutesPerSlot)}, inside the calendar's "
          "hours.",
    if (!hours.holdsEnd(end))
      "endMinute":
          "The end is ${clockLabel(hours.start + minutesPerSlot)} to "
          "${clockLabel(hours.end)}, inside the calendar's hours.",
  };
}

/// The names of Month's layouts in the settings sheet.
extension MonthLayoutLabel on MonthLayout {
  /// The layout's name in the settings sheet.
  String get label {
    switch (this) {
      case MonthLayout.showAll:
        return "Show all items";
      case MonthLayout.fitScreen:
        return "Fit to screen";
    }
  }
}

/// What the calendar bar and the settings sheet choose: whether the
/// calendar is in [editing] mode, whether the history lock holds past days, [lockPast], and earlier
/// today too, [lockEarlierToday], the [weekdays] it shows and the one its
/// weeks start on, the
/// [hours] it shows and schedules in, the [hourLabelFormat] the timed grid
/// labels them in, Month's [monthLayout], the least width of a day in
/// Week, Day and Month, and the least height of the timed grid's slots,
/// which stretch past them to fill the screen, and through it the height
/// of Month's weeks.
@immutable
class CalendarSettings {
  const CalendarSettings({
    this.editing = false,
    this.lockPast = false,
    this.lockEarlierToday = false,
    this.weekdays = WeekdaySet.all,
    this.hours = DayHours.allDay,
    this.hourLabelFormat = HourLabelFormat.twentyFourHour,
    this.monthLayout = MonthLayout.fitScreen,
    this.minDayWidth = minDayWidthLow,
    this.minSlotHeight = defaultMinSlotHeight,
  });

  /// Whether the calendar's items can be moved, resized, created, edited
  /// and deleted. Out of edit mode the calendar is read-only, and a tap on
  /// an item opens its form read-only.
  final bool editing;

  /// Whether the items before today, and the time before it, are kept as
  /// they are: no item there is moved, resized, edited or deleted, nor
  /// does one move there or start there; an item reaching from before
  /// today into it changes only its end, to a time after the start of
  /// today.
  final bool lockPast;

  /// Whether, under [lockPast], the lock holds today up to the current
  /// minute too, and so an item in progress changes only its end, to a
  /// time after now. Without [lockPast] it holds nothing.
  final bool lockEarlierToday;

  /// The weekdays the calendar shows, at least one, which the month grid
  /// and the timed grid assert, and the weekday its weeks start on, which
  /// orders them in every view.
  final WeekdaySet weekdays;

  final DayHours hours;

  final HourLabelFormat hourLabelFormat;

  final MonthLayout monthLayout;

  /// The least width of a day column, in logical pixels.
  final double minDayWidth;

  /// The least height of one slot, in logical pixels.
  final double minSlotHeight;

  /// How many times its share of Month's height a week rests at:
  /// [minSlotHeight] over [defaultMinSlotHeight], and never less than 1, so
  /// at the default slot height and under it the weeks fit the screen.
  double get monthWeekScale {
    return math.max(1.0, minSlotHeight / defaultMinSlotHeight);
  }

  /// These settings with [monthWeekScale] at [scale], at least 1: the slot
  /// height [scale] times its default above 1, and at 1 the slot height
  /// as it is where that is at most its default, and its default where it
  /// is over it.
  CalendarSettings withMonthWeekScale(double scale) {
    return copyWith(
      minSlotHeight: scale > 1.0
          ? defaultMinSlotHeight * scale
          : math.min(minSlotHeight, defaultMinSlotHeight),
    );
  }

  CalendarSettings copyWith({
    bool? editing,
    bool? lockPast,
    bool? lockEarlierToday,
    WeekdaySet? weekdays,
    DayHours? hours,
    HourLabelFormat? hourLabelFormat,
    MonthLayout? monthLayout,
    double? minDayWidth,
    double? minSlotHeight,
  }) {
    return CalendarSettings(
      editing: editing ?? this.editing,
      lockPast: lockPast ?? this.lockPast,
      lockEarlierToday: lockEarlierToday ?? this.lockEarlierToday,
      weekdays: weekdays ?? this.weekdays,
      hours: hours ?? this.hours,
      hourLabelFormat: hourLabelFormat ?? this.hourLabelFormat,
      monthLayout: monthLayout ?? this.monthLayout,
      minDayWidth: minDayWidth ?? this.minDayWidth,
      minSlotHeight: minSlotHeight ?? this.minSlotHeight,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarSettings &&
        other.editing == editing &&
        other.lockPast == lockPast &&
        other.lockEarlierToday == lockEarlierToday &&
        other.weekdays == weekdays &&
        other.hours == hours &&
        other.hourLabelFormat == hourLabelFormat &&
        other.monthLayout == monthLayout &&
        other.minDayWidth == minDayWidth &&
        other.minSlotHeight == minSlotHeight;
  }

  @override
  int get hashCode {
    return Object.hash(
      editing,
      lockPast,
      lockEarlierToday,
      weekdays,
      hours,
      hourLabelFormat,
      monthLayout,
      minDayWidth,
      minSlotHeight,
    );
  }

  @override
  String toString() {
    return "CalendarSettings(${editing ? "editing" : "viewing"}, "
        "${lockPast ? "past locked${lockEarlierToday ? " to now" : ""}, " : ""}"
        "$weekdays, $hours, ${hourLabelFormat.name}, "
        "${monthLayout.name}, day width $minDayWidth, "
        "slot height $minSlotHeight)";
  }
}
