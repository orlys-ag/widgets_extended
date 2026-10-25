/// What the calendar's settings choose: whether it is in edit mode, how far
/// the history lock keeps the past as it is, and so the calendar's edit
/// policy, the weekdays it shows and the
/// one its weeks start on, the hours it shows
/// and schedules in and the length of its slots, how the timed grid labels
/// its hours, and how Month fits its weeks. Beside them: the field errors,
/// keyed as `validateItemJson` keys them, of an item outside the calendar's
/// hours, [hoursErrorsOf]; and the names of Month's layouts in the
/// settings sheet, [MonthLayoutLabel].
library;

import 'package:flutter/foundation.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';

import 'calendar_item.dart';
import 'calendar_schema.dart';

/// The history lock as the demo's edit policy: an item covers at most
/// [maxDayCount] days, which the gestures a `CalendarView` limits by its
/// policy's day limit hold to.
class WorkspaceHistoryLockPolicy extends HistoryLockPolicy<ItemPayload> {
  const WorkspaceHistoryLockPolicy({
    super.lockEarlierToday,
    super.allowsOverlaps,
  });

  @override
  int get dayLimit {
    return maxDayCount;
  }
}

/// The demo's edit policy with no lock: an item covers at most
/// [maxDayCount] days, as under [WorkspaceHistoryLockPolicy].
class WorkspaceUnrestrictedPolicy extends UnrestrictedEditPolicy<ItemPayload> {
  const WorkspaceUnrestrictedPolicy({super.allowsOverlaps});

  @override
  int get dayLimit {
    return maxDayCount;
  }
}

/// The field errors of an item from [start] to [end] that [hours] do not
/// hold ([DayHours.holdsTimes]), keyed as `validateItemJson` keys them: the
/// start when the hours do not hold its time of day as a start, the end
/// when they do not hold its minute on its last day as an end, each naming
/// the bounds [DayHours.holdsStart] and [DayHours.holdsEnd] take any minute
/// between. An all-day item has none.
Map<String, String> hoursErrorsOf(
  DateTime start,
  DateTime end,
  DayHours hours,
) {
  if (hours.holdsTimes(start, end)) {
    return const <String, String>{};
  }
  return <String, String>{
    if (!hours.holdsStart(minuteOfDay(start)))
      "start":
          "The start is from ${clockLabel(hours.start)} to before "
          "${clockLabel(hours.end)}, inside the calendar's hours.",
    if (!hours.holdsEnd(endMinuteOfDay(end)))
      "end":
          "The end is from after ${clockLabel(hours.start)} to "
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
/// [hours] it shows and schedules in, the [slotMinutes] of its slots, the
/// [hourLabelFormat] the timed grid labels them in, and Month's
/// [monthLayout].
@immutable
class CalendarSettings {
  const CalendarSettings({
    this.editing = false,
    this.lockPast = false,
    this.lockEarlierToday = false,
    this.weekdays = WeekdaySet.all,
    this.hours = DayHours.allDay,
    this.slotMinutes = defaultSlotMinutes,
    this.hourLabelFormat = HourLabelFormat.twentyFourHour,
    this.monthLayout = MonthLayout.fitScreen,
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

  /// The hours, which start and end on the grid of [slotMinutes] where
  /// [withSlotMinutes] set it.
  final DayHours hours;

  /// The length of the calendar's slots, in minutes, one of
  /// [slotMinuteChoices]: Week's and Day's rows, the step of their
  /// gestures and of the item form's times, and the slot a create from
  /// Agenda or Month takes.
  final int slotMinutes;

  final HourLabelFormat hourLabelFormat;

  final MonthLayout monthLayout;

  /// The edit policy the calendar and the item form both read: the history
  /// lock, of earlier today too under [lockEarlierToday], under
  /// [lockPast], and no lock otherwise. Neither allows overlapping items.
  /// Equal settings give equal policies, so a rebuild with them cancels no
  /// gesture.
  CalendarEditPolicy<ItemPayload> get editPolicy {
    if (lockPast) {
      return WorkspaceHistoryLockPolicy(
        lockEarlierToday: lockEarlierToday,
        allowsOverlaps: false,
      );
    }
    return const WorkspaceUnrestrictedPolicy(allowsOverlaps: false);
  }

  CalendarSettings copyWith({
    bool? editing,
    bool? lockPast,
    bool? lockEarlierToday,
    WeekdaySet? weekdays,
    DayHours? hours,
    int? slotMinutes,
    HourLabelFormat? hourLabelFormat,
    MonthLayout? monthLayout,
  }) {
    return CalendarSettings(
      editing: editing ?? this.editing,
      lockPast: lockPast ?? this.lockPast,
      lockEarlierToday: lockEarlierToday ?? this.lockEarlierToday,
      weekdays: weekdays ?? this.weekdays,
      hours: hours ?? this.hours,
      slotMinutes: slotMinutes ?? this.slotMinutes,
      hourLabelFormat: hourLabelFormat ?? this.hourLabelFormat,
      monthLayout: monthLayout ?? this.monthLayout,
    );
  }

  /// These settings with slots of [slotMinutes], and the [hours] rounded out
  /// to their grid ([DayHours.roundedOutTo]), so the calendar never shows
  /// hours off it.
  CalendarSettings withSlotMinutes(int slotMinutes) {
    return copyWith(
      slotMinutes: slotMinutes,
      hours: hours.roundedOutTo(slotMinutes),
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
        other.slotMinutes == slotMinutes &&
        other.hourLabelFormat == hourLabelFormat &&
        other.monthLayout == monthLayout;
  }

  @override
  int get hashCode {
    return Object.hash(
      editing,
      lockPast,
      lockEarlierToday,
      weekdays,
      hours,
      slotMinutes,
      hourLabelFormat,
      monthLayout,
    );
  }

  @override
  String toString() {
    return "CalendarSettings(${editing ? "editing" : "viewing"}, "
        "${lockPast ? "past locked${lockEarlierToday ? " to now" : ""}, " : ""}"
        "$weekdays, $hours, $slotMinutes-minute slots, "
        "${hourLabelFormat.name}, "
        "${monthLayout.name})";
  }
}
