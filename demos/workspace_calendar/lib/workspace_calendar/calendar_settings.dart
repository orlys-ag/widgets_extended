/// What the calendar's settings choose: whether it is in edit mode, how far
/// the history lock keeps the past as it is, the weekdays it shows and the
/// one its weeks start on, the hours it shows
/// and schedules in, how the timed grid labels its hours, how Month fits
/// its weeks, the least width of a day in Week, Day and Month, and the
/// least height of the timed grid's slots, which also scales the height
/// of Month's weeks.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

/// The most [CalendarSettings.monthWeekScale] the settings offer: the
/// most slot height over its default.
const double maxMonthWeekScale = minSlotHeightHigh / defaultMinSlotHeight;

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

/// What a screen reader says for a count of [count] of [day]'s items
/// before [minute], or after it when [above] is false, naming the minute
/// in [format]: the timed grid's rows and Agenda's banners outside the
/// hours alike.
String hiddenRowLabel(
  DateTime day,
  int count,
  int minute, {
  required bool above,
  required HourLabelFormat format,
}) {
  final date =
      "${weekdayNames[weekdayColumn(day)]}, "
      "${monthNames[day.month - 1]} ${day.day}";
  final side = above ? "before" : "after";
  return "$date, ${moreItemsLabel(count)} $side ${hourLabel(minute, format)}";
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
