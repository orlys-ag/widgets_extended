/// What the calendar's settings choose: whether it is in edit mode, the
/// weekdays it shows and the one its weeks start on, the hours it shows
/// and schedules in, how the timed grid labels its hours, how Month fits
/// its weeks, the least width of a day in Week, Day and Month, and the
/// least height of the timed grid's slots, which also scales the height
/// of Month's weeks.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'calendar_data.dart';
import 'calendar_schema.dart';

/// The part of each day the calendar shows and schedules in: from [start]
/// to [end] minutes after midnight, in whole slots.
@immutable
class DayHours {
  const DayHours(this.start, this.end)
    : assert(start >= 0 && start % minutesPerSlot == 0),
      assert(end <= minutesPerDay && end % minutesPerSlot == 0),
      assert(start < end);

  /// The whole day, 00:00 to 24:00.
  static const DayHours allDay = DayHours(0, minutesPerDay);

  final int start;
  final int end;

  /// The slots from [start] to [end].
  int get slotCount {
    return (end - start) ~/ minutesPerSlot;
  }

  /// Whether the minutes [from] to [to] lie inside these hours.
  bool contains(int from, int to) {
    return from >= start && to <= end;
  }

  @override
  bool operator ==(Object other) {
    return other is DayHours && other.start == start && other.end == end;
  }

  @override
  int get hashCode {
    return Object.hash(start, end);
  }

  @override
  String toString() {
    return "DayHours(${clockLabel(start)}-${clockLabel(end)})";
  }
}

/// The field errors of an item from [start] to [end] minutes that does not
/// lie in [hours], keyed as `validateItemJson` keys them: the start when it
/// does not begin a slot inside them, the end when it does not end one.
Map<String, String> hoursErrorsOf(int start, int end, DayHours hours) {
  return <String, String>{
    if (start < hours.start || start > hours.end - minutesPerSlot)
      "startMinute":
          "The start is ${clockLabel(hours.start)} to "
          "${clockLabel(hours.end - minutesPerSlot)}, inside the calendar's "
          "hours.",
    if (end < hours.start + minutesPerSlot || end > hours.end)
      "endMinute":
          "The end is ${clockLabel(hours.start + minutesPerSlot)} to "
          "${clockLabel(hours.end)}, inside the calendar's hours.",
  };
}

/// The least day width the settings offer, which is the grid's default.
const double minDayWidthLow = 44.0;

/// The most day width the settings offer.
const double minDayWidthHigh = 240.0;

/// The least slot height the settings offer.
const double minSlotHeightLow = 8.0;

/// The most slot height the settings offer.
const double minSlotHeightHigh = 48.0;

/// The slot height the grid has before the settings change it.
const double defaultMinSlotHeight = 16.0;

/// How Month lays out a week whose chips need more lanes than its share
/// of the board's height holds.
enum MonthLayout {
  /// The week grows to hold every chip, and the month scrolls.
  showAll("Show all items"),

  /// Every week keeps its share of the board's height, so the month fits
  /// on the screen; a day shows the chips that fit and how many it hides.
  fitScreen("Fit to screen");

  const MonthLayout(this.label);

  /// The layout's name in the settings sheet.
  final String label;
}

/// How the timed grid's hour gutter names the times it labels.
enum HourLabelFormat {
  /// "13:00", as [clockLabel] writes it.
  twentyFourHour,

  /// "1 PM", as [hourLabel] writes it.
  twelveHour,
}

/// What the hour gutter names [minute] minutes after midnight with in
/// [format]: [clockLabel]'s "13:00" in 24-hour, and in AM/PM the hour,
/// its minutes where it has some, and the half of the day, as "1 PM" or
/// "8:15 AM". Midnight, 1440 included, reads "12 AM" and noon "12 PM".
String hourLabel(int minute, HourLabelFormat format) {
  if (format == HourLabelFormat.twentyFourHour) {
    return clockLabel(minute);
  }
  final ofDay = minute % minutesPerDay;
  final hour = ofDay ~/ 60;
  final half = hour < 12 ? "AM" : "PM";
  final shown = hour % 12 == 0 ? 12 : hour % 12;
  final minutes = ofDay % 60;
  if (minutes == 0) {
    return "$shown $half";
  }
  return "$shown:${minutes.toString().padLeft(2, "0")} $half";
}

/// What the settings sheet chooses: whether the calendar is in [editing]
/// mode, the [weekdays] it shows and the one its weeks start on, the
/// [hours] it shows and schedules in, the [hourLabelFormat] the timed grid
/// labels them in, Month's [monthLayout], the least width of a day in
/// Week, Day and Month, and the least height of the timed grid's slots,
/// which stretch past them to fill the screen, and through it the height
/// of Month's weeks.
@immutable
class CalendarSettings {
  const CalendarSettings({
    this.editing = false,
    this.weekdays = WeekdaySet.all,
    this.hours = DayHours.allDay,
    this.hourLabelFormat = HourLabelFormat.twentyFourHour,
    this.monthLayout = MonthLayout.fitScreen,
    this.minDayWidth = minDayWidthLow,
    this.minSlotHeight = defaultMinSlotHeight,
  });

  /// Whether the calendar's items can be resized, edited and deleted, and
  /// created by every gesture. Out of edit mode, in Week and Day, a long
  /// press still moves an item, and one on an empty slot, dragged or not,
  /// still creates one.
  final bool editing;

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

  CalendarSettings copyWith({
    bool? editing,
    WeekdaySet? weekdays,
    DayHours? hours,
    HourLabelFormat? hourLabelFormat,
    MonthLayout? monthLayout,
    double? minDayWidth,
    double? minSlotHeight,
  }) {
    return CalendarSettings(
      editing: editing ?? this.editing,
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
        "$weekdays, $hours, ${hourLabelFormat.name}, "
        "${monthLayout.name}, day width $minDayWidth, "
        "slot height $minSlotHeight)";
  }
}
