/// The item form's schedule heading, schedule section and overlap notice,
/// the parts of the form any item type shares: the section edits a
/// [CalendarSchedule], the heading shows its length and zone beside the
/// form's title, and the notice shows a card of each entry it overlaps, as
/// its [CalendarScheduleCheck] answers while the user edits.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_item.dart';
import 'harbor_theme.dart';

/// The key of the text of the heading's length pill, after its title: the
/// length of a timed schedule of a positive length, such as "1d 2h 30m",
/// or of an all-day schedule, "All day" for one day and "All day" with its
/// count of days in parentheses, such as "All day (3 days)", for more.
const ValueKey<String> scheduleLengthKey = ValueKey<String>("schedule-length");

/// The key of the heading's zone box, at its right end: the zone's city or
/// the device's zone's name, above the zone's offset from UTC.
const ValueKey<String> scheduleZoneKey = ValueKey<String>("schedule-zone");

/// The key of the text of the schedule's summary ([ScheduleSummary]).
const ValueKey<String> scheduleSummaryKey = ValueKey<String>(
  "schedule-summary",
);

/// The key of the overlap notice.
const ValueKey<String> scheduleOverlapKey = ValueKey<String>(
  "schedule-overlap",
);

/// The key of the overlap notice's card of the overlapped item [id].
ValueKey<String> scheduleOverlapCardKey(String id) {
  return ValueKey<String>("schedule-overlap-card-$id");
}

/// The key of the bar of the overlap notice's card of the item [id]: its
/// axis and the axis's times.
ValueKey<String> scheduleOverlapBarKey(String id) {
  return ValueKey<String>("schedule-overlap-bar-$id");
}

/// The key of the axis of the bar of the overlap notice's card of the item
/// [id], whose width stands for the time from the axis's start to its end.
ValueKey<String> scheduleOverlapAxisKey(String id) {
  return ValueKey<String>("schedule-overlap-axis-$id");
}

/// The key of the striped part of the shared time on the axis of the
/// overlap notice's card of the item [id].
ValueKey<String> scheduleOverlapShareKey(String id) {
  return ValueKey<String>("schedule-overlap-share-$id");
}

/// The key of the part of the axis of the overlap notice's card of the item
/// [id] that lies before the shared time, where the axis starts before it.
ValueKey<String> scheduleOverlapBeforeKey(String id) {
  return ValueKey<String>("schedule-overlap-before-$id");
}

/// The key of the part of the axis of the overlap notice's card of the item
/// [id] that lies after the shared time, where the axis ends after it.
ValueKey<String> scheduleOverlapAfterKey(String id) {
  return ValueKey<String>("schedule-overlap-after-$id");
}

/// The key of the [Focus] around the Start row, a button that shows the
/// schedule's start and opens the Start row's picker.
const ValueKey<String> scheduleStartKey = ValueKey<String>("schedule-start");

/// The key of the [Focus] around the End row, a button that shows the
/// schedule's end and opens the End row's picker.
const ValueKey<String> scheduleEndKey = ValueKey<String>("schedule-end");

/// The key of the Start row's time, which a timed schedule's row shows
/// after its day.
const ValueKey<String> scheduleStartTimeKey = ValueKey<String>(
  "schedule-start-time",
);

/// The key of the End row's time, which a timed schedule's row shows after
/// its day.
const ValueKey<String> scheduleEndTimeKey = ValueKey<String>(
  "schedule-end-time",
);

/// The key of the message under the Start row, the form's message keyed
/// `start` ([ScheduleSection.errors]).
const ValueKey<String> scheduleStartErrorKey = ValueKey<String>(
  "schedule-start-error",
);

/// The key of the message under the End row, the form's message keyed
/// `end` ([ScheduleSection.errors]).
const ValueKey<String> scheduleEndErrorKey = ValueKey<String>(
  "schedule-end-error",
);

/// The key of the All day switch.
const ValueKey<String> scheduleAllDayKey = ValueKey<String>("schedule-all-day");

/// The key of the panel under the Start row that holds its date-time
/// picker.
const ValueKey<String> scheduleStartPanelKey = ValueKey<String>(
  "schedule-start-panel",
);

/// The key of the panel under the End row that holds its date-time picker.
const ValueKey<String> scheduleEndPanelKey = ValueKey<String>(
  "schedule-end-panel",
);

/// The section of [check]'s schedule: an All day switch, where the kind
/// takes all-day or the schedule is all-day, which turned off restores the
/// times the schedule keeps; then a Start row above an End row. Each row is
/// a button ([_RowButton]) that shows its label, "Start" or "End", then its
/// day with its weekday and, for a timed schedule, its time, and a chevron
/// at its end. A row's tap opens a panel under it holding the row's
/// [CalendarDateTimePicker], one of the two open at a time, the row drawn
/// open while it is and keeping the focus.
///
/// The picker's day picker lies on the week or month of the row's day,
/// that day selected and the [CalendarNow.today] of [now] ringed, its weeks
/// starting on the weekday column [firstColumn], and its days with entries
/// of [store] badged as [dayBadges] marks them, the circles of its first
/// and last columns on the row's sides
/// ([CalendarDayPicker.daysToEdges]). Its chevrons, swipes and month picks
/// only browse, End's to no week, month or year before the start day's
/// ([CalendarDayPicker.browsesBeforeFirstDay]). It draws disabled, and
/// takes no tap on, the days its check's day answers rule out: Start's
/// those before [CalendarScheduleCheck.firstStartDay], End's those outside
/// [CalendarScheduleCheck.endDays]; the section reads them of each check
/// once, as a picker first builds under it. For a timed schedule the
/// picker's time picker, with its haptic feedback on, lies under the day
/// picker, and its Time toggle shows and hides it. Each opening of a row
/// shows its day picker on the view either picker last turned to
/// ([CalendarDateTimePicker.onViewChanged]), folded into its week row at
/// first, and its time shown or hidden as either picker's Time toggle last
/// left it, shown at first.
///
/// A tap on a day moves the row's day to it, Start's moving the end by as
/// many days, and keeps the row's time where the time picker offers it on
/// the new day, or moves it to the nearest time it offers there; a pick of
/// a time moves the row's time; and an all-day schedule's picker picks days
/// alone. Times are written on [hourLabelFormat]'s clock.
/// [ScheduleHeading] shows the schedule's length and zone, and
/// [ScheduleOverlapNotice] its overlaps.
///
/// A panel grows and fades in as its row's tap opens it, and shrinks and
/// fades out as that row's tap closes it, or the other row's opens its
/// own, over the [CalendarTheme]'s motion, or at once where the platform
/// asks for no animations; it then scrolls into view, and again where its
/// picker grows once it rests, as a day picker unfolds into its month or
/// the time shows. A picker whose row is not the open one takes no pick.
///
/// A time picker refuses a time only for a problem some other time of it
/// avoids: of the check of the schedule with each of the picker's times on
/// its day ([CalendarScheduleCheck.withSchedule]), it takes as witnesses
/// those whose times are checked ([CalendarScheduleCheck.timesChecked]),
/// or every time where none is, and refuses a time whose check names a
/// problem that not every witness's check names. The start's picker offers
/// the hours' starts, the end's its ends, on the start day only those after
/// the start. A time picker's Now shows only on a row whose day is [now]'s
/// today, and where the time at or before now is refused picks the first
/// later time the picker offers.
///
/// The section pads its controls by nothing. Its rows reach its sides; at
/// its top lies the All day row, the switch's touch target whole, or with
/// no switch the Start row; and at its bottom the End row, or its panel
/// while open.
///
/// Every edit goes to [onChanged] as a new schedule. A [locked] section
/// takes no input; a [CalendarScheduleCheck.startFixed] one takes none at
/// its start or kind; and an all-day schedule's End row takes none where
/// the options refuse spanning days ([CalendarScheduleOptions.spansDays])
/// and the schedule ends on its start day. An open picker stays open as its
/// row locks, taking no pick, until its row's tap closes it. The All day
/// switch leaves an open row open, its picker hiding its time and Time
/// toggle as the switch turns on and showing them as it turns off, and
/// turned on takes the focus from the open picker. [errors] holds the
/// form's messages keyed `start` and `end`, which show under the Start and
/// End rows and tint those rows with the soft error colour.
class ScheduleSection extends StatefulWidget {
  const ScheduleSection({
    super.key,
    required this.check,
    required this.hours,
    required this.slotMinutes,
    required this.hourLabelFormat,
    required this.now,
    required this.onChanged,
    required this.store,
    this.dayBadges,
    this.firstColumn = 0,
    this.locked = false,
    this.errors = const <String, String>{},
  });

  final CalendarScheduleCheck<ItemPayload> check;

  /// The hours the pickers offer times in.
  final CalendarDayHours hours;

  /// The step of the pickers' times.
  final int slotMinutes;

  /// The clock the time fields and the pickers write times on.
  final CalendarHourLabelFormat hourLabelFormat;

  /// The current time, whose minute on the clock of [store]'s zone the
  /// pickers' Now picks; Now shows only on a row whose day is its
  /// [CalendarNow.today].
  final ValueGetter<CalendarNow> now;

  final ValueChanged<CalendarSchedule> onChanged;

  /// The store whose entries badge the day pickers' days, and on the clock
  /// of whose zone, or of the device where it has none, the section reads
  /// its days and times.
  final CalendarStore<ItemPayload> store;

  /// The kinds of entry the day pickers' badges mark; none for one primary
  /// dot on a day with entries.
  final CalendarDayBadges<ItemPayload>? dayBadges;

  /// The weekday column the day pickers' weeks start on, 0 for Monday to 6
  /// for Sunday.
  final int firstColumn;

  final bool locked;

  final Map<String, String> errors;

  @override
  ScheduleSectionState createState() {
    return ScheduleSectionState();
  }
}

/// A row of the section, Start or End, each of which opens its own picker.
enum _Row { start, end }

/// The All day switch's size, as a share of a [Switch]'s.
const double _allDaySwitchScale = 0.75;

/// A Start or End row of the section: a button whose tap, [onTap], opens
/// or closes the row's picker. It shows [label] in a column [_labelWidth]
/// wide in a 13-pixel medium weight, then [day] and, where not null, [time]
/// 12 pixels after it under [timeKey], in a 15-pixel bold weight, and at
/// its end a chevron that points down, turning to point up as the row
/// opens. A box [_height] high with corners rounded by 12 and no outline
/// holds them, filled with the page's grey, its label and chevron in the
/// muted colour, or where [error] filled with the soft error tint, its
/// label and chevron in the error colour; while [open] it is filled with
/// the primary tint, and all it shows is drawn in the primary colour. It
/// moves from the one look to the other over the [CalendarTheme]'s motion,
/// the chevron turning with it, or at once where the platform asks for no
/// animations. A row with no
/// [onTap], which takes no input, shows its day and time in the muted
/// colour with no box around them and no chevron, as text rather than a
/// button, unless [error] tints it. The day and the time keep to one line,
/// and shrink together to fit a box too narrow for them, as a 12-hour time
/// in a narrow form or under a large text scale, rather than lose their
/// end; so does the label in its column. A screen reader hears the label,
/// the day and the time as one button, expanded while [open]. A tap
/// anywhere on the box reaches [onTap], and [focusNode] is its [InkWell]'s.
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.day,
    required this.time,
    required this.timeKey,
    required this.open,
    required this.error,
    required this.focusNode,
    required this.onTap,
  });

  final String label;
  final String day;
  final String? time;
  final Key timeKey;
  final bool open;
  final bool error;
  final FocusNode focusNode;
  final VoidCallback? onTap;

  static const BorderRadius _corners = BorderRadius.all(Radius.circular(12.0));

  static const double _height = 48.0;

  static const double _labelWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = CalendarTheme.of(context);
    final takesInput = onTap != null;
    final time = this.time;
    return Semantics(
      container: true,
      button: true,
      enabled: takesInput,
      expanded: takesInput ? open : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: open ? 1.0 : 0.0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : theme.motionDuration,
        curve: theme.motionCurve,
        builder: (context, opening, child) {
          Color between(Color shut, Color opened) {
            return Color.lerp(shut, opened, opening)!;
          }

          final shut = error
              ? HarborColors.errorNotice
              : takesInput
              ? HarborColors.background
              : Colors.transparent;
          final fill = takesInput
              ? between(shut, HarborColors.primaryTint)
              : shut;
          final ink = takesInput
              ? between(HarborColors.text, HarborColors.primary)
              : HarborColors.textMuted;
          final shutMark = error ? HarborColors.error : HarborColors.textMuted;
          final mark = takesInput
              ? between(shutMark, HarborColors.primary)
              : shutMark;
          final valueStyle = TextStyle(
            color: ink,
            fontSize: 15.0,
            fontWeight: FontWeight.w600,
          );
          return DecoratedBox(
            decoration: BoxDecoration(color: fill, borderRadius: _corners),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                focusNode: focusNode,
                onTap: onTap,
                customBorder: const RoundedRectangleBorder(
                  borderRadius: _corners,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _height),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: _labelWidth,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: TextStyle(
                                color: mark,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(day, maxLines: 1, style: valueStyle),
                                if (time != null) ...<Widget>[
                                  const SizedBox(width: 12.0),
                                  KeyedSubtree(
                                    key: timeKey,
                                    child: Text(
                                      time,
                                      maxLines: 1,
                                      style: valueStyle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (takesInput) ...<Widget>[
                          const SizedBox(width: 8.0),
                          Transform.rotate(
                            angle: math.pi * opening,
                            child: Icon(
                              Icons.expand_more,
                              size: 20.0,
                              color: mark,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The lookups the open picker has made of its [_TimeTable], in debug
/// builds; the release build counts none.
int debugSchedulePickerAsks = 0;

/// The reads the section has made of its check's day ranges,
/// [CalendarScheduleCheck.firstStartDay] and
/// [CalendarScheduleCheck.endDays], in debug builds; the release build
/// counts none.
int debugScheduleDayRangeAsks = 0;

/// Which times of [row]'s time picker, from [min] to [max], the picker
/// offers under [check], whose schedule lies on the day the picker shows:
/// each time's check is [CalendarScheduleCheck.withSchedule] of the
/// schedule with that time, or [check] itself at the row's own time; the
/// witnesses are the times on the [slot] grid whose check has
/// [CalendarScheduleCheck.timesChecked], or every time on it where none
/// has; and a time is offered where each of its problems is a problem of
/// every witness. A time outside [min] to [max] is not offered. The grid's
/// times are computed at the first lookup, and a time off it, as a stored
/// item's own, at each.
class _TimeTable {
  _TimeTable({
    required this.check,
    required this.row,
    required this.min,
    required this.max,
    required this.slot,
  });

  final CalendarScheduleCheck<ItemPayload> check;
  final _Row row;
  final int min;
  final int max;
  final int slot;

  List<bool>? _offered;

  /// The problems every witness's check names; null before the first
  /// lookup.
  Set<CalendarScheduleProblem>? _shared;

  /// The first time on the grid at or after [min].
  int get _first {
    return (min + slot - 1) ~/ slot * slot;
  }

  /// The check of the schedule with the row's time at [time].
  CalendarScheduleCheck<ItemPayload> _checkAt(int time) {
    final schedule = check.schedule;
    final start = row == _Row.start;
    if (time == (start ? schedule.startMinute : schedule.endMinute)) {
      return check;
    }
    return check.withSchedule(
      start ? schedule.withStartMinute(time) : schedule.withEndMinute(time),
    );
  }

  /// Whether the picker offers [minute].
  bool offers(int minute) {
    assert(() {
      debugSchedulePickerAsks++;
      return true;
    }());
    if (minute < min || minute > max) {
      return false;
    }
    final offered = _offered ??= _compute();
    final first = _first;
    if (minute >= first && (minute - first) % slot == 0) {
      return offered[(minute - first) ~/ slot];
    }
    return _checkAt(minute).problems.every(_shared!.contains);
  }

  List<bool> _compute() {
    final checks = <CalendarScheduleCheck<ItemPayload>>[
      for (var time = _first; time <= max; time += slot) _checkAt(time),
    ];
    var witnesses = checks.where((each) {
      return each.timesChecked;
    });
    if (witnesses.isEmpty) {
      witnesses = checks;
    }
    Set<CalendarScheduleProblem>? shared;
    for (final witness in witnesses) {
      final problems = witness.problems.toSet();
      shared = shared == null ? problems : shared.intersection(problems);
    }
    final every = _shared = shared ?? <CalendarScheduleProblem>{};
    return <bool>[
      for (final each in checks) each.problems.every(every.contains),
    ];
  }
}

/// The times [row]'s time picker offers on a day under [check], in [hours]
/// on the [slot] grid: the first and last of them ([boundsOn]), and which
/// it offers ([offers]), as a [_TimeTable] of the schedule with the row's
/// day on that day answers. Keeps the table of the row's own day, and of
/// the last other day asked of, as a tap on a day asks of the day it picks.
/// The section keeps one while its check, hours and slot stay, so [offers]
/// keeps one identity, by which the picker keeps the answers it has.
class _RowTimes {
  _RowTimes({
    required this.check,
    required this.row,
    required this.hours,
    required this.slot,
    required this.zone,
  });

  final CalendarScheduleCheck<ItemPayload> check;
  final _Row row;
  final CalendarDayHours hours;
  final int slot;

  /// The zone the schedule's times are on; none for the device's.
  final Location? zone;

  /// The table of the row's own day; null before its first lookup.
  _TimeTable? _own;

  /// The table of the last other day asked of, by its day number.
  ({int day, _TimeTable table})? _other;

  /// Whether these are the times for these parameters.
  bool holds(
    CalendarScheduleCheck<ItemPayload> check,
    _Row row,
    CalendarDayHours hours,
    int slot,
    Location? zone,
  ) {
    return identical(this.check, check) &&
        this.row == row &&
        this.hours == hours &&
        this.slot == slot &&
        this.zone == zone;
  }

  /// The schedule with the row's day moved to [day]; the start's end moves
  /// by as many days.
  CalendarSchedule _scheduleOn(DateTime day) {
    final schedule = check.schedule;
    return row == _Row.start
        ? schedule.withStartDay(day)
        : schedule.withEndDay(day);
  }

  /// The first and last time the picker offers on [day]: the start's the
  /// hours' starts; the end's the hours' ends, on the start's day only
  /// those whose instant is after the start's, or where the start leaves no
  /// such end in the hours its own time alone.
  ({int min, int max}) boundsOn(DateTime day) {
    return _boundsOf(_scheduleOn(day));
  }

  ({int min, int max}) _boundsOf(CalendarSchedule schedule) {
    if (row == _Row.start) {
      return (min: hours.start, max: math.max(hours.start, hours.end - slot));
    }
    var min = hours.start + slot;
    var max = hours.end;
    if (!schedule.spansDays) {
      min = math.max(min, _firstEndAfterStart(schedule, min));
    }
    if (min > max) {
      min = schedule.endMinute;
      max = schedule.endMinute;
    }
    return (min: min, max: max);
  }

  /// The least end minute from [from] to [schedule]'s start minute plus one
  /// whose end, in the pass [CalendarSchedule.withEndMinute] keeps, lies
  /// after the start as instants on [zone]'s clock, for a timed [schedule]
  /// that ends on its start day; the start minute plus one where none
  /// does. A later-pass end can read a wall minute before the start's only
  /// where the start day's clock repeats a stretch
  /// ([CalendarDates.repeatedStretchOf]), so only there is the clock read,
  /// by bisection over the minutes, as the ends rise with the minute in
  /// one pass; elsewhere, and where the clock skips an edge, the start
  /// minute plus one.
  int _firstEndAfterStart(CalendarSchedule schedule, int from) {
    final after = schedule.startMinute + 1;
    if (schedule.isAllDay ||
        CalendarDates.repeatedStretchOf(
              CalendarDates.dateOfDayNumber(
                CalendarDates.dayNumber(schedule.startDay),
                zone: zone,
              ),
            ) ==
            Duration.zero ||
        schedule.timesOn(zone) == null) {
      return after;
    }
    var low = from;
    var high = after;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final times = schedule.withEndMinute(middle).timesOn(zone);
      if (times != null && times.end.isAfter(times.start)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }

  /// Whether the picker offers [minute] on [day].
  bool offers(DateTime day, int minute) {
    final number = CalendarDates.dayNumber(day);
    final schedule = check.schedule;
    final own = row == _Row.start ? schedule.startDay : schedule.endDay;
    if (number == CalendarDates.dayNumber(own)) {
      return (_own ??= _tableOf(check)).offers(minute);
    }
    var other = _other;
    if (other == null || other.day != number) {
      other = (
        day: number,
        table: _tableOf(check.withSchedule(_scheduleOn(day))),
      );
      _other = other;
    }
    return other.table.offers(minute);
  }

  _TimeTable _tableOf(CalendarScheduleCheck<ItemPayload> check) {
    final bounds = _boundsOf(check.schedule);
    return _TimeTable(
      check: check,
      row: row,
      min: bounds.min,
      max: bounds.max,
      slot: slot,
    );
  }
}

/// The state of a [ScheduleSection], which finds the row a message of
/// [ScheduleSection.errors] shows on.
class ScheduleSectionState extends State<ScheduleSection> {
  /// The row whose picker is open; none where null.
  _Row? _open;

  /// How many times each row has opened its picker, which keys the row's
  /// picker, so that each opening builds a new one, on [_dayPickerView] and
  /// [_showsTime].
  int _startOpenings = 0;
  int _endOpenings = 0;

  /// The view either day picker last turned to, which the next one opens
  /// on; read only as a picker is made, so a change needs no build.
  CalendarDayPickerView _dayPickerView = const CalendarDayPickerView();

  /// Whether either picker's Time toggle last left its time shown, as the
  /// next one opens; read only as a picker is made, so a change needs no
  /// build.
  bool _showsTime = true;

  /// Each row's picker's times, kept across builds while they hold.
  final Map<_Row, _RowTimes> _times = <_Row, _RowTimes>{};

  /// The check [_startRange] and [_endRange] were read of; none before a
  /// picker first builds.
  CalendarScheduleCheck<ItemPayload>? _rangedCheck;

  /// The first and last day the Start row's and the End row's day pickers
  /// take, null for none.
  ({DateTime? first, DateTime? last}) _startRange = (first: null, last: null);
  ({DateTime? first, DateTime? last}) _endRange = (first: null, last: null);

  final FocusNode _startNode = FocusNode(debugLabel: "Start");
  final FocusNode _endNode = FocusNode(debugLabel: "End");

  /// The nodes of the [Focus] around each row, which take the focus back
  /// as a row that takes no input closes its picker: an [InkWell] with no
  /// tap takes none.
  final FocusNode _startRestNode = FocusNode(
    debugLabel: "Start rest",
    skipTraversal: true,
  );
  final FocusNode _endRestNode = FocusNode(
    debugLabel: "End rest",
    skipTraversal: true,
  );

  /// The nodes of the [Focus] around each row's picker, which have the
  /// focus while a control of the picker does.
  final FocusNode _startPanelNode = FocusNode(
    debugLabel: "Start picker",
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode _endPanelNode = FocusNode(
    debugLabel: "End picker",
    canRequestFocus: false,
    skipTraversal: true,
  );

  final FocusNode _allDayNode = FocusNode(debugLabel: "All day");

  @override
  void dispose() {
    _startNode.dispose();
    _endNode.dispose();
    _startRestNode.dispose();
    _endRestNode.dispose();
    _startPanelNode.dispose();
    _endPanelNode.dispose();
    _allDayNode.dispose();
    super.dispose();
  }

  CalendarSchedule get _schedule {
    return widget.check.schedule;
  }

  CalendarScheduleOptions get _options {
    return widget.check.options;
  }

  bool get _startLocked {
    return widget.locked || widget.check.startFixed;
  }

  void _change(CalendarSchedule schedule) {
    if (schedule != _schedule) {
      widget.onChanged(schedule);
    }
  }

  /// Whether [row] takes input: Start where neither the section is locked
  /// nor the start fixed; End where the section is not locked and the
  /// schedule is timed, or the options take spanning days, or the schedule
  /// spans them.
  bool _takesInput(_Row row) {
    if (row == _Row.start) {
      return !_startLocked;
    }
    final schedule = _schedule;
    return !widget.locked &&
        (!schedule.isAllDay || _options.spansDays || schedule.spansDays);
  }

  /// The node of [row]'s [InkWell].
  FocusNode _nodeOf(_Row row) {
    return row == _Row.start ? _startNode : _endNode;
  }

  /// The node of the [Focus] around [row].
  FocusNode _restNodeOf(_Row row) {
    return row == _Row.start ? _startRestNode : _endRestNode;
  }

  /// The node of the [Focus] around [row]'s picker.
  FocusNode _panelNodeOf(_Row row) {
    return row == _Row.start ? _startPanelNode : _endPanelNode;
  }

  /// The context of the row that shows the message of
  /// [ScheduleSection.errors] keyed [key], `start` or `end`, built in every
  /// build; null before the section first builds.
  BuildContext? errorFieldOf(String key) {
    return _restNodeOf(key == "start" ? _Row.start : _Row.end).context;
  }

  /// The context of the Start row, whose box tells where it lies; null
  /// before the section builds.
  BuildContext? get startRowContext {
    return _startRestNode.context;
  }

  /// Opens [row]'s picker, closing the open one, or closes [row]'s where it
  /// is open, the row taking the focus. A spin of a time picker's columns
  /// that the tap cuts off reports nothing: a picker whose row is not the
  /// open one has a null `onChanged`.
  void _tapRow(_Row row) {
    if (_open == row) {
      setState(() {
        _open = null;
      });
      // Made before the next frame, so a control of the closing picker no
      // longer holds the focus as the panel shrinks and leaves the tree.
      if (_takesInput(row)) {
        _nodeOf(row).requestFocus();
      } else {
        _restNodeOf(row).requestFocus();
      }
      return;
    }
    setState(() {
      _open = row;
      if (row == _Row.start) {
        _startOpenings++;
      } else {
        _endOpenings++;
      }
    });
    _nodeOf(row).requestFocus();
  }

  /// The button of [row], showing the row's day with its weekday
  /// ([MaterialLocalizations.formatMediumDate]) and, for a timed schedule,
  /// its time, tinted with the soft error colour where [error]; its tap
  /// opens or closes the row's picker.
  Widget _rowButton(_Row row, {required bool error}) {
    final schedule = _schedule;
    final start = row == _Row.start;
    final open = _open == row;
    return Focus(
      key: start ? scheduleStartKey : scheduleEndKey,
      focusNode: _restNodeOf(row),
      child: _RowButton(
        label: start ? "Start" : "End",
        day: MaterialLocalizations.of(
          context,
        ).formatMediumDate(start ? schedule.startDay : schedule.endDay),
        time: schedule.isAllDay
            ? null
            : CalendarLocalizations.of(context).formatTime(
                start ? schedule.startMinute : schedule.endMinute,
                widget.hourLabelFormat,
              ),
        timeKey: start ? scheduleStartTimeKey : scheduleEndTimeKey,
        open: open,
        error: error,
        focusNode: _nodeOf(row),
        onTap: open || _takesInput(row)
            ? () {
                _tapRow(row);
              }
            : null,
      ),
    );
  }

  /// The current minute after midnight on the zone's clock.
  int _nowMinute() {
    return CalendarDates.minuteOfDay(
      CalendarDates.inZone(widget.now().time, zone: widget.store.zone),
    );
  }

  /// The times of [row]'s picker: the kept ones where they hold for the
  /// section's check, hours and slot, and new ones otherwise.
  _RowTimes _timesOf(_Row row) {
    final check = widget.check;
    final hours = widget.hours;
    final slot = widget.slotMinutes;
    final zone = widget.store.zone;
    final times = _times[row];
    if (times != null && times.holds(check, row, hours, slot, zone)) {
      return times;
    }
    return _times[row] = _RowTimes(
      check: check,
      row: row,
      hours: hours,
      slot: slot,
      zone: zone,
    );
  }

  /// Moves [row]'s day to [day], and its time to [minute] where not null.
  void _pick(_Row row, DateTime day, int? minute) {
    final date = CalendarDates.dateOnly(day);
    final schedule = _schedule;
    if (row == _Row.start) {
      final moved = schedule.withStartDay(date);
      _change(
        minute == null || moved.isAllDay
            ? moved
            : moved.withStartMinute(minute),
      );
    } else {
      final moved = schedule.withEndDay(date);
      _change(
        minute == null || moved.isAllDay ? moved : moved.withEndMinute(minute),
      );
    }
  }

  /// The All day switch, at [_allDaySwitchScale] of a [Switch]'s size, 8
  /// pixels after its label, which takes no tap.
  Widget _allDayRow(CalendarSchedule schedule, bool startLocked) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        children: <Widget>[
          Text(
            "All day",
            style: theme.textTheme.bodyLarge?.copyWith(
              color: startLocked
                  ? theme.disabledColor
                  : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8.0),
          // A FittedBox scales the switch, its layout and its touch target
          // included, to the box's height.
          SizedBox(
            height: kMinInteractiveDimension * _allDaySwitchScale,
            child: FittedBox(
              child: Switch(
                key: scheduleAllDayKey,
                value: schedule.isAllDay,
                focusNode: _allDayNode,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onChanged: startLocked
                    ? null
                    : (on) {
                        // The open picker's time and Time toggle go away;
                        // the focus a control of the picker held moves to
                        // the switch, not to the scope's last focused node.
                        final open = _open;
                        if (on && open != null && _panelNodeOf(open).hasFocus) {
                          _allDayNode.requestFocus();
                        }
                        _change(schedule.withAllDay(on));
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The first and last day [row]'s day picker takes: Start's from the
  /// check's [CalendarScheduleCheck.firstStartDay] with no last day, End's
  /// the check's [CalendarScheduleCheck.endDays]. Both rows' are read anew
  /// only under a check other than the one they were read of.
  ({DateTime? first, DateTime? last}) _dayRangeOf(_Row row) {
    final check = widget.check;
    if (!identical(check, _rangedCheck)) {
      assert(() {
        debugScheduleDayRangeAsks++;
        return true;
      }());
      _rangedCheck = check;
      _startRange = (first: check.firstStartDay, last: null);
      final ends = check.endDays;
      _endRange = (first: ends.first, last: ends.last);
    }
    return row == _Row.start ? _startRange : _endRange;
  }

  /// [row]'s picker, whose row's key is its
  /// [CalendarDateTimePicker.subject]: its day picker on the week or month
  /// of the row's day, that day selected and [ScheduleSection.now]'s today
  /// ringed, taking the days of [_dayRangeOf], End's browsing back no
  /// further than the first of them; and for a timed schedule its time
  /// picker on the row's time, offering the times of [_timesOf]. Keyed by
  /// the row's openings, so each opening builds a new one, on the view
  /// either picker last turned to, [_dayPickerView], and with its time
  /// shown as [_showsTime] says. It takes no pick while its panel closes or
  /// where the row takes no input.
  Widget _picker(_Row row) {
    final schedule = _schedule;
    final start = row == _Row.start;
    final range = _dayRangeOf(row);
    final times = _timesOf(row);
    return CalendarDateTimePicker<ItemPayload>(
      key: ValueKey<int>(start ? _startOpenings : _endOpenings),
      day: start ? schedule.startDay : schedule.endDay,
      minute: schedule.isAllDay
          ? null
          : start
          ? schedule.startMinute
          : schedule.endMinute,
      onChanged: _open != row || !_takesInput(row)
          ? null
          : (day, minute) {
              _pick(row, day, minute);
            },
      store: widget.store,
      today: widget.now().today,
      firstDay: range.first,
      lastDay: range.last,
      firstColumn: widget.firstColumn,
      dayBadges: widget.dayBadges,
      daysToEdges: true,
      browsesBeforeFirstDay: start,
      initialView: _dayPickerView,
      onViewChanged: (view) {
        _dayPickerView = view;
      },
      hourLabelFormat: widget.hourLabelFormat,
      minuteStep: widget.slotMinutes,
      timeBoundsOf: times.boundsOn,
      isTimeEnabled: times.offers,
      now: _nowMinute,
      nowPicksLater: true,
      hapticFeedback: true,
      subject: start ? scheduleStartKey : scheduleEndKey,
      initialShowsTime: _showsTime,
      onShowsTimeChanged: (shows) {
        _showsTime = shows;
      },
    );
  }

  /// The Start or End row of [row], above the panel that holds its picker:
  /// [error] shows under the row's button and tints it with the soft error
  /// colour. The button and the panel keep their places in the tree
  /// whichever way All day turns, and with them the panel's state and the
  /// button's focus: a [Focus] that leaves the tree drops its focus. So
  /// does each row as the All day switch above it comes or goes: a row's
  /// outermost widget is a [Column], and the switch's row a
  /// [MergeSemantics], which the section's [Column] does not match to it.
  Widget _row(_Row row, String? error) {
    final start = row == _Row.start;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _rowButton(row, error: error != null),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              error,
              key: start ? scheduleStartErrorKey : scheduleEndErrorKey,
              style: const TextStyle(color: HarborColors.error, fontSize: 12.0),
            ),
          ),
        _PickerPanel(
          key: start ? scheduleStartPanelKey : scheduleEndPanelKey,
          open: _open == row,
          field: _restNodeOf(row),
          builder: (context) {
            return Focus(focusNode: _panelNodeOf(row), child: _picker(row));
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    final errors = widget.errors;
    final allDayShows = _options.allowsAllDay || schedule.isAllDay;
    final children = <Widget>[
      if (allDayShows) _allDayRow(schedule, _startLocked),
      _row(_Row.start, errors["start"]),
      _row(_Row.end, errors["end"]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < children.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 12.0),
          children[index],
        ],
      ],
    );
  }
}

/// [minutes], a positive count of minutes, written in days of 24 hours,
/// hours and minutes, each that is not none, as "2d 4h 30m", "1d",
/// "1h 30m" or "45m".
String _lengthLabel(int minutes) {
  assert(minutes > 0);
  final days = minutes ~/ CalendarDates.minutesPerDay;
  final hours = minutes % CalendarDates.minutesPerDay ~/ 60;
  final rest = minutes % 60;
  return <String>[
    if (days > 0) "${days}d",
    if (hours > 0) "${hours}h",
    if (rest > 0) "${rest}m",
  ].join(" ");
}

/// The form's heading: its [title], and 8 pixels after it, where the
/// schedule has a length to show, a pill with a timer icon before [check]'s
/// schedule's length: an all-day schedule's "All day" for one day, or
/// "All day" with its count of civil days in parentheses, such as
/// "All day (3 days)", for more; or a timed schedule's days, hours and
/// minutes, such as "1d 2h 30m", where it is positive. At the heading's
/// right end lies, in a light grey rounded box, [zone]'s name, its city
/// ([CalendarZonePanel.cityOf]) or, for the device's zone,
/// [CalendarLocalizations.deviceZoneName], above the zone's offset from UTC
/// at the start ([CalendarLocalizations.utcOffset]), or at its day's start
/// where the zone's clock skips the start. The title and the pill centre on
/// the heading's height. Where the room before the box cannot hold them on
/// one line, the title wraps; where it cannot hold the pill beside its gap,
/// the pill shrinks to fit.
class ScheduleHeading extends StatelessWidget {
  const ScheduleHeading({
    super.key,
    required this.title,
    required this.check,
    this.zone,
  });

  /// The form's title, such as "New item".
  final String title;

  final CalendarScheduleCheck<ItemPayload> check;

  /// The zone the times are on, which the heading names; none for the
  /// device's.
  final Location? zone;

  /// The title.
  static const TextStyle _titleStyle = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.text,
  );

  /// The text of the pill.
  static const TextStyle _lengthStyle = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.primary,
  );

  /// The zone's name in its box.
  static const TextStyle _zoneNameStyle = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
    color: HarborColors.textMuted,
  );

  /// The zone's offset under its name.
  static const TextStyle _zoneOffsetStyle = TextStyle(
    fontSize: 11.0,
    color: HarborColors.textMuted,
  );

  /// The text of the pill for [schedule], null where it shows none: for a
  /// timed schedule of no length.
  static String? _lengthOf(CalendarSchedule schedule) {
    if (schedule.isAllDay) {
      final days =
          CalendarDates.daysBetween(schedule.startDay, schedule.endDay) + 1;
      return days > 1 ? "All day ($days days)" : "All day";
    }
    if (schedule.lengthMinutes > 0) {
      return _lengthLabel(schedule.lengthMinutes);
    }
    return null;
  }

  /// [label] in a pill, a timer icon before it.
  Widget _pill(String label) {
    return DecoratedBox(
      decoration: const ShapeDecoration(
        color: HarborColors.primaryTint,
        shape: StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 3.0, 10.0, 3.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.timer_outlined,
              size: 14.0,
              color: HarborColors.primary,
            ),
            const SizedBox(width: 4.0),
            Text(label, key: scheduleLengthKey, style: _lengthStyle),
          ],
        ),
      ),
    );
  }

  /// The zone's name above its offset from UTC at the schedule's start, in
  /// a light grey rounded box.
  Widget _zone(CalendarLocalizations strings) {
    final zone = this.zone;
    final schedule = check.schedule;
    final day = CalendarDates.dayNumber(schedule.startDay);
    final start =
        schedule.timesOn(zone)?.start ??
        CalendarDates.timeAtWallMinute(
          day * CalendarDates.minutesPerDay + schedule.startMinute,
          zone: zone,
        ) ??
        CalendarDates.dateOfDayNumber(day, zone: zone);
    return Container(
      key: scheduleZoneKey,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            zone == null
                ? strings.deviceZoneName
                : CalendarZonePanel.cityOf(zone),
            style: _zoneNameStyle,
          ),
          Text(
            strings.utcOffset(start.timeZoneOffset.inMinutes),
            style: _zoneOffsetStyle,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final length = _lengthOf(check.schedule);
    return Row(
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: <Widget>[
                  Flexible(child: Text(title, style: _titleStyle)),
                  if (length != null) ...<Widget>[
                    const SizedBox(width: 8.0),
                    // The pill takes its own width before the title takes
                    // the rest, and no more than the room beside the gap.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(0.0, constraints.maxWidth - 8.0),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _pill(length),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 12.0),
        _zone(CalendarLocalizations.of(context)),
      ],
    );
  }
}

/// The form's page, [child], under a band that writes [check]'s schedule
/// where [shown]: its first day as the rows write it
/// ([MaterialLocalizations.formatMediumDate]) and, for a timed schedule,
/// its times on [hourLabelFormat]'s clock, as "Wed, Apr 22, 09:00-10:00",
/// or each day's across days, as "Wed, Apr 22, 22:00 - Thu, Apr 23, 02:00",
/// an end at a day's 24:00 written as the End row writes it
/// ([CalendarSchedule.endMinute]); for an all-day schedule its first day,
/// and its last after " - " where it has more, as
/// "Wed, Apr 22 - Fri, Apr 24". The spaces within a day and a time do not
/// break, so a summary too long for its line breaks after " - " alone.
///
/// The band paints the sheet's colour, [HarborColors.surface], with a
/// hairline of [HarborColors.outline] along its bottom, and starts its text
/// where the heading's title starts. As [shown] turns true the band grows
/// from no height to its own over the [CalendarTheme]'s motion, sliding
/// down from its top edge as it fades in, and the page's view starts under
/// it; as [shown] turns false it shrinks back over that motion, fading out
/// and taking no pointer; each at once where the platform asks for no
/// animations. A band built [shown] shows at once.
///
/// As the band's height changes, the offset of [controller]'s position
/// changes by as much, so what the page shows stays where it lies, the band
/// covering or uncovering the top of it; where that would take the offset
/// below its least, the offset stops there and the page moves with its
/// view. An animated scroll of the page sets its offset whole on each
/// frame ([ScrollPosition.animateTo]), so the page moves with the band
/// while one runs.
class ScheduleSummary extends StatefulWidget {
  const ScheduleSummary({
    super.key,
    required this.check,
    required this.hourLabelFormat,
    required this.shown,
    required this.controller,
    required this.child,
  });

  final CalendarScheduleCheck<ItemPayload> check;

  final CalendarHourLabelFormat hourLabelFormat;

  /// Whether the band shows, or comes in.
  final bool shown;

  /// The controller of the page's scroll view, whose offset follows the
  /// band's height.
  final ScrollController controller;

  /// The page, under the band.
  final Widget child;

  @override
  State<ScheduleSummary> createState() {
    return _ScheduleSummaryState();
  }
}

class _ScheduleSummaryState extends State<ScheduleSummary>
    with SingleTickerProviderStateMixin {
  /// The summary's text.
  static const TextStyle _style = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    color: HarborColors.textMuted,
  );

  /// How far in the band is, from 0, gone, to 1, shown.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.shown ? 1.0 : 0.0,
  );

  /// [_controller] on the theme's curve, which the band's height and
  /// opacity read.
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: Curves.linear,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = CalendarTheme.of(context);
    // A reverse reads its curve from 1 down to 0, so the flip of the curve
    // eases a going as the curve eases a coming.
    _curved
      ..curve = theme.motionCurve
      ..reverseCurve = FlippedCurve(theme.motionCurve);
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
  }

  @override
  void didUpdateWidget(ScheduleSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown != oldWidget.shown) {
      if (widget.shown) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// [schedule] as the band writes it.
  static String _summaryOf(
    CalendarSchedule schedule,
    MaterialLocalizations dates,
    CalendarLocalizations strings,
    CalendarHourLabelFormat format,
  ) {
    String unbroken(String text) {
      return text.replaceAll(" ", "\u00A0");
    }

    final start = dates.formatMediumDate(schedule.startDay);
    final end = dates.formatMediumDate(schedule.endDay);
    final oneDay =
        CalendarDates.dayNumber(schedule.startDay) ==
        CalendarDates.dayNumber(schedule.endDay);
    if (schedule.isAllDay) {
      return oneDay ? unbroken(start) : "${unbroken(start)} - ${unbroken(end)}";
    }
    if (oneDay) {
      final times = strings.formatTimeRange(
        schedule.startMinute,
        schedule.endMinute,
        format,
      );
      return unbroken("$start, $times");
    }
    final from = strings.formatTime(schedule.startMinute, format);
    final to = strings.formatTime(schedule.endMinute, format);
    return "${unbroken("$start, $from")} - ${unbroken("$end, $to")}";
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summaryOf(
      widget.check.schedule,
      MaterialLocalizations.of(context),
      CalendarLocalizations.of(context),
      widget.hourLabelFormat,
    );
    return _SummaryInset(
      reveal: _curved,
      controller: widget.controller,
      band: IgnorePointer(
        ignoring: !widget.shown,
        child: FadeTransition(
          opacity: _curved,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: HarborColors.surface,
              border: Border(bottom: BorderSide(color: HarborColors.outline)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 8.0),
              child: Text(summary, key: scheduleSummaryKey, style: _style),
            ),
          ),
        ),
      ),
      page: widget.child,
    );
  }
}

/// [band] over [page]: the band's own height times [reveal] of it shows,
/// its bottom edge there, and the page lies under it, the change of that
/// share moving [controller]'s offset by as much
/// ([ScheduleSummary.controller]).
class _SummaryInset extends MultiChildRenderObjectWidget {
  _SummaryInset({
    required this.reveal,
    required this.controller,
    required Widget band,
    required Widget page,
  }) : super(children: <Widget>[band, page]);

  final Animation<double> reveal;

  final ScrollController controller;

  @override
  _RenderSummaryInset createRenderObject(BuildContext context) {
    return _RenderSummaryInset(reveal: reveal, controller: controller);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSummaryInset renderObject,
  ) {
    renderObject
      ..reveal = reveal
      ..controller = controller;
  }
}

class _SummaryInsetParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays out [_SummaryInset]'s band, then its page under the share of the
/// band that shows, and moves the page's offset by the change of that
/// share before the page lays out, as a viewport corrects its own offset
/// ([ScrollPosition.correctBy]): a drag and a fling go on from the moved
/// offset, and an idle page keeps it.
class _RenderSummaryInset extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SummaryInsetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SummaryInsetParentData> {
  _RenderSummaryInset({
    required Animation<double> reveal,
    required this.controller,
  }) : _reveal = reveal;

  /// The share of the band that shows, from 0 to 1.
  Animation<double> get reveal {
    return _reveal;
  }

  Animation<double> _reveal;

  set reveal(Animation<double> value) {
    if (identical(value, _reveal)) {
      return;
    }
    if (attached) {
      _reveal.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _reveal = value;
    markNeedsLayout();
  }

  /// The controller of the page's scroll view, read as the band's share
  /// changes.
  ScrollController controller;

  /// The height of the band that showed at the last layout, by which the
  /// page's offset has moved; null before the first.
  double? _inset;

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  RenderBox get _band {
    return firstChild!;
  }

  RenderBox get _page {
    return lastChild!;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SummaryInsetParentData) {
      child.parentData = _SummaryInsetParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _reveal.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _reveal.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  /// The band's constraints: the width of [constraints], where it has one,
  /// and any height.
  static BoxConstraints _bandConstraints(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: constraints.hasBoundedWidth ? constraints.maxWidth : 0.0,
      maxWidth: constraints.maxWidth,
    );
  }

  /// The page's constraints under [inset] of the band.
  static BoxConstraints _pageConstraints(
    BoxConstraints constraints,
    double inset,
  ) {
    return BoxConstraints(
      minWidth: constraints.minWidth,
      maxWidth: constraints.maxWidth,
      minHeight: math.max(0.0, constraints.minHeight - inset),
      maxHeight: math.max(0.0, constraints.maxHeight - inset),
    );
  }

  /// The share of a band [height] tall that shows, no taller than
  /// [maxHeight].
  double _insetOf(double height, double maxHeight) {
    return math.min(height * _reveal.value, maxHeight);
  }

  @override
  void performLayout() {
    final band = _band;
    final page = _page;
    band.layout(_bandConstraints(constraints), parentUsesSize: true);
    final inset = _insetOf(band.size.height, constraints.maxHeight);
    final last = _inset;
    _inset = inset;
    if (last != null && inset != last) {
      _movePage(inset - last);
    }
    page.layout(_pageConstraints(constraints, inset), parentUsesSize: true);
    (band.parentData! as _SummaryInsetParentData).offset = Offset(
      0.0,
      inset - band.size.height,
    );
    (page.parentData! as _SummaryInsetParentData).offset = Offset(0.0, inset);
    size = constraints.constrain(
      Size(page.size.width, inset + page.size.height),
    );
  }

  /// Moves the page's offset by [change], the change of the band's share,
  /// so what the page shows stays where it lies; no further down than the
  /// offset's least.
  void _movePage(double change) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    if (!position.hasPixels || !position.hasContentDimensions) {
      return;
    }
    var correction = change;
    if (correction < 0.0) {
      correction = math.min(
        0.0,
        math.max(correction, position.minScrollExtent - position.pixels),
      );
    }
    if (correction != 0.0) {
      position.correctBy(correction);
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final band = _band.getDryLayout(_bandConstraints(constraints));
    final inset = _insetOf(band.height, constraints.maxHeight);
    final page = _page.getDryLayout(_pageConstraints(constraints, inset));
    return constraints.constrain(Size(page.width, inset + page.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return math.max(
      _band.getMinIntrinsicWidth(double.infinity),
      _page.getMinIntrinsicWidth(height),
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return math.max(
      _band.getMaxIntrinsicWidth(double.infinity),
      _page.getMaxIntrinsicWidth(height),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _band.getMinIntrinsicHeight(width) * _reveal.value +
        _page.getMinIntrinsicHeight(width);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _band.getMaxIntrinsicHeight(width) * _reveal.value +
        _page.getMaxIntrinsicHeight(width);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final page = _page;
    context.paintChild(
      page,
      offset + (page.parentData! as _SummaryInsetParentData).offset,
    );
    final inset = _inset ?? 0.0;
    if (inset <= 0.0) {
      _clip.layer = null;
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & Size(size.width, inset),
      _paintBand,
      oldLayer: _clip.layer,
    );
  }

  void _paintBand(PaintingContext context, Offset offset) {
    final band = _band;
    context.paintChild(
      band,
      offset + (band.parentData! as _SummaryInsetParentData).offset,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    if (identical(child, _band)) {
      return Offset.zero & Size(size.width, _inset ?? 0.0);
    }
    return null;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = position.dy < (_inset ?? 0.0) ? _band : _page;
    return result.addWithPaintOffset(
      offset: (child.parentData! as _SummaryInsetParentData).offset,
      position: position,
      hitTest: (result, transformed) {
        return child.hitTest(result, position: transformed);
      },
    );
  }
}

/// The notice of the entries [check]'s schedule overlaps
/// ([CalendarScheduleCheck.overlaps]), which shows while there are any.
///
/// Its heading, after a warning icon level with its top, counts them,
/// "Overlaps 2 items", and those whose overlap the rules refuse
/// ([CalendarScheduleOverlapRefused]): "Overlaps 2 items, 1 not allowed",
/// or "Can't overlap 2 items" where they refuse each. Beside it a "Next
/// free time" button sends [CalendarScheduleCheck.nextFree] to [onChanged],
/// and "Next free:" under the heading writes that schedule's times; both
/// show where it is another schedule, unless the form is [locked] or the
/// check's start is fixed.
///
/// Under them lies a card per overlapped item, in the order of their starts
/// and then their ends. A white card with no outline, its type's edge
/// colour down its leading side, holds its type's icon and its
/// title across the card, its times under the title, the time it shares
/// with the schedule, or "Covers all of this item" where that is all of it,
/// in a chip, and a bar zoomed on the shared time; where the rules refuse
/// its overlap, its chip and the tint under its bar's stripes are soft red.
/// The bar's axis reaches the shared time's length past each of its ends,
/// within the two items' times, so the shared time fills a third of it or
/// more. One track fills the axis: the shared time striped in the item's
/// colour, and the time before and after it in the item's colour where it
/// is the item's and in grey where it is the schedule's; the axis's first
/// and last times lie under its ends.
/// Times are written on [hourLabelFormat]'s clock, an end at a day's start
/// as the 24:00 of the day before, and a range that runs past the
/// schedule's start day with the weekday of each end. The notice shows its
/// first [shownCards] cards and a button that shows the rest, which then
/// shows fewer again.
///
/// The cards are the rows of a [SyncedSliverTree]: a card that comes, as
/// the button shows it or the schedule comes to overlap its item, grows in;
/// one that goes shrinks out still showing what it showed; and one whose
/// place changes slides to it; each over the [CalendarTheme]'s motion, or
/// at once where the platform asks for no animations.
///
/// As [check] comes to name overlaps, the notice, with [padding] around it,
/// grows from no height over the theme's motion: its box, the fill and the
/// outline, fades in over the motion's first half, and what the box holds
/// from a fifth of the motion to seven tenths, so the box comes first. As
/// it stops, the notice shrinks out over the motion, what the box holds
/// fading out from three tenths of the motion to four fifths and the box
/// over its last half, still showing the overlaps it last named, and takes
/// no pointer. Overlaps that come back while it shrinks turn it back from
/// where it is, its cards as they were. A notice built over overlaps shows
/// at once, as all of it does where the platform asks for no animations.
///
/// The notice is soft yellow ([HarborColors.notice]), or soft red
/// ([HarborColors.errorNotice]) where the rules refuse an overlap.
class ScheduleOverlapNotice extends StatefulWidget {
  const ScheduleOverlapNotice({
    super.key,
    required this.check,
    required this.hourLabelFormat,
    required this.onChanged,
    this.zone,
    this.locked = false,
    this.padding = EdgeInsets.zero,
  });

  final CalendarScheduleCheck<ItemPayload> check;

  final CalendarHourLabelFormat hourLabelFormat;

  /// The zone on whose clock the schedule's times are read
  /// ([CalendarSchedule.timesOn]), the device's where it is null: the clock
  /// [check] reads them on. A card whose schedule's times the clock skips
  /// shows no shared time and no bar.
  final Location? zone;

  /// Takes the schedule "Next free time" moves to.
  final ValueChanged<CalendarSchedule> onChanged;

  /// Whether the form takes no input, under which "Next free time" does
  /// not show.
  final bool locked;

  /// The room around the notice, which grows in and shrinks out with it.
  final EdgeInsetsGeometry padding;

  /// How many cards show before the button that shows the rest.
  static const int shownCards = 2;

  @override
  State<ScheduleOverlapNotice> createState() {
    return _ScheduleOverlapNoticeState();
  }
}

class _ScheduleOverlapNoticeState extends State<ScheduleOverlapNotice>
    with SingleTickerProviderStateMixin {
  /// Whether every card shows, past [ScheduleOverlapNotice.shownCards].
  bool _expanded = false;

  /// The check whose overlaps show: the widget's while it names any, the
  /// last that did while the notice shrinks out, and null once it has.
  CalendarScheduleCheck<ItemPayload>? _shown;

  /// How far in the notice is, from 0, gone, to 1, shown.
  late final AnimationController _controller = AnimationController(vsync: this);

  /// [_controller] on the theme's curve, which the notice's height reads.
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _controller,
    curve: Curves.linear,
  );

  /// The share of [_controller] by which the box has faded in.
  static const double _boxFadeEnd = 0.5;

  /// The share of [_controller] at which what the box holds starts to fade
  /// in, after its box.
  static const double _contentFadeStart = 0.2;

  /// The share of [_controller] by which what the box holds has faded in.
  static const double _contentFadeEnd = 0.7;

  /// [_controller] up to [_boxFadeEnd] on the theme's curve, which the
  /// alphas of the box's fill and outline read.
  late final CurvedAnimation _boxFade = CurvedAnimation(
    parent: _controller,
    curve: Curves.linear,
  );

  /// [_controller] from [_contentFadeStart] to [_contentFadeEnd] on the
  /// theme's curve, which the opacity of what the box holds reads.
  late final CurvedAnimation _contentFade = CurvedAnimation(
    parent: _controller,
    curve: Curves.linear,
  );

  @override
  void initState() {
    super.initState();
    if (widget.check.overlaps.isNotEmpty) {
      _shown = widget.check;
      _controller.value = 1.0;
    }
    _controller.addStatusListener(_statusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = CalendarTheme.of(context);
    final curve = theme.motionCurve;
    // A reverse reads its curve from 1 down to 0, so the flip of the curve
    // eases a closing as the curve eases an opening.
    final flipped = FlippedCurve(curve);
    _size
      ..curve = curve
      ..reverseCurve = flipped;
    _boxFade
      ..curve = Interval(0.0, _boxFadeEnd, curve: curve)
      ..reverseCurve = Interval(0.0, _boxFadeEnd, curve: flipped);
    _contentFade
      ..curve = Interval(_contentFadeStart, _contentFadeEnd, curve: curve)
      ..reverseCurve = Interval(
        _contentFadeStart,
        _contentFadeEnd,
        curve: flipped,
      );
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
  }

  @override
  void didUpdateWidget(ScheduleOverlapNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.check.overlaps.isNotEmpty) {
      _shown = widget.check;
      _controller.forward();
    } else if (_shown != null) {
      _controller.reverse();
    }
  }

  /// Drops the shown check once the notice has shrunk out, so a notice
  /// that comes again starts with its cards folded.
  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      setState(() {
        _shown = null;
        _expanded = false;
      });
    }
  }

  @override
  void dispose() {
    _size.dispose();
    _boxFade.dispose();
    _contentFade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final check = _shown;
    if (check == null) {
      return const SizedBox.shrink();
    }
    final strings = CalendarLocalizations.of(context);
    final format = widget.hourLabelFormat;
    final refused = <CalendarEntry<ItemPayload>>{
      for (final problem in check.problems)
        if (problem is CalendarScheduleOverlapRefused<ItemPayload>)
          problem.other,
    };
    final overlaps = check.overlaps.toList()..sort(_byTimes);
    final refusedCount = overlaps.where(refused.contains).length;
    final alert = refusedCount > 0;
    final ink = alert ? HarborColors.onErrorNotice : HarborColors.onNotice;
    final next = check.nextFree;
    final offered =
        next != null &&
            next != check.schedule &&
            !(widget.locked || check.startFixed)
        ? next
        : null;
    const shownCards = ScheduleOverlapNotice.shownCards;
    final folds = overlaps.length > shownCards;
    final shown = folds && !_expanded
        ? overlaps.sublist(0, shownCards)
        : overlaps;
    final times = check.schedule.timesOn(widget.zone);
    final day = CalendarDates.dayNumber(check.schedule.startDay);
    final rows = <_OverlapRow>[
      for (final item in shown)
        (item: item, times: times, day: day, refused: refused.contains(item)),
    ];
    final theme = CalendarTheme.of(context);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? TreeAnimationStyle.disabled
        : TreeAnimationStyle.uniform(
            duration: theme.motionDuration,
            curve: theme.motionCurve,
          );
    final fill = alert ? HarborColors.errorNotice : HarborColors.notice;
    final edge = alert ? HarborColors.errorNoticeEdge : HarborColors.noticeEdge;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The icon lies at the heading's top, beside its first
              // line; the two together centre on the button.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.warning_amber, size: 18.0, color: ink),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _overlapHeading(overlaps.length, refusedCount),
                            style: TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (offered != null)
                            Text(
                              "Next free: ${strings.formatTimeRange(offered.startMinute, offered.endMinute, format)}",
                              style: TextStyle(color: ink, fontSize: 13.0),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (offered != null)
                TextButton(
                  onPressed: () {
                    widget.onChanged(offered);
                  },
                  child: const Text("Next free time"),
                ),
            ],
          ),
          CustomScrollView(
            shrinkWrap: true,
            // The form's scroll view, not this one, takes the route's
            // PrimaryScrollController.
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            slivers: <Widget>[
              SyncedSliverTree<Object, _OverlapRow>.flat(
                items: rows,
                keyOf: (row) {
                  return row.item.id ?? row.item;
                },
                parentOf: (row) {
                  return null;
                },
                animationStyle: motion,
                itemBuilder: (context, node) {
                  final row = node.item;
                  // The gap lies inside the row, so it grows and shrinks
                  // with its card.
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _OverlapCard(
                      item: row.item,
                      times: row.times,
                      day: row.day,
                      refused: row.refused,
                      hourLabelFormat: format,
                    ),
                  );
                },
              ),
            ],
          ),
          if (folds)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                child: Text(
                  _expanded
                      ? "Show fewer"
                      : "Show ${overlaps.length - shownCards} more",
                ),
              ),
            ),
        ],
      ),
    );
    // The box fades through the alphas of its colours rather than under an
    // opacity of its own, which would fade what it holds with it.
    final notice = AnimatedBuilder(
      animation: _boxFade,
      builder: (context, child) {
        final alpha = _boxFade.value;
        return DecoratedBox(
          key: scheduleOverlapKey,
          decoration: BoxDecoration(
            color: fill.withValues(alpha: fill.a * alpha),
            border: Border.all(color: edge.withValues(alpha: edge.a * alpha)),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: child,
        );
      },
      child: FadeTransition(opacity: _contentFade, child: content),
    );
    return IgnorePointer(
      ignoring: widget.check.overlaps.isEmpty,
      child: SizeTransition(
        sizeFactor: _size,
        alignment: AlignmentDirectional.topStart,
        child: Padding(padding: widget.padding, child: notice),
      ),
    );
  }
}

/// Orders items by their starts, then their ends, then their titles and
/// ids, so that the cards' order does not rest on the sort's stability.
int _byTimes(CalendarItem a, CalendarItem b) {
  final start = a.start.compareTo(b.start);
  if (start != 0) {
    return start;
  }
  final end = a.end.compareTo(b.end);
  if (end != 0) {
    return end;
  }
  final title = a.title.compareTo(b.title);
  if (title != 0) {
    return title;
  }
  return (a.id ?? "").compareTo(b.id ?? "");
}

/// The overlap notice's heading for [count] overlapped items, [refused] of
/// them refused.
String _overlapHeading(int count, int refused) {
  final items = count == 1 ? "1 item" : "$count items";
  if (refused == 0) {
    return "Overlaps $items";
  }
  if (refused == count) {
    return "Can't overlap $items";
  }
  return "Overlaps $items, $refused not allowed";
}

/// The times from [start] to [end] in [format]: as
/// [CalendarLocalizations.entryTimes] writes them where the range starts
/// and ends on the day numbered [day], its last day
/// ([CalendarDates.lastDayNumberOf]) counted as the day it ends on, and
/// otherwise each time after its day's weekday, as "Tue 22:00-Wed 09:30".
String _overlapTimes(
  DateTime start,
  DateTime end,
  int day,
  CalendarLocalizations strings,
  CalendarHourLabelFormat format,
) {
  final firstDay = CalendarDates.dayNumber(start);
  final lastDay = CalendarDates.lastDayNumberOf(start, end);
  if (firstDay == day && lastDay == day) {
    return strings.entryTimes(start, end, format, isAllDay: false);
  }
  final from = CalendarDates.minuteOfDay(start);
  final to = CalendarDates.endMinuteOfDay(end);
  return "${_weekdayTime(firstDay, from, strings, format)}-"
      "${_weekdayTime(lastDay, to, strings, format)}";
}

/// [time] in [format], after its day's weekday where that is not the day
/// numbered [day]; where [end], a day's start reads as the 24:00 of the
/// day before ([CalendarDates.endMinuteOfDay]).
String _overlapTime(
  DateTime time,
  int day,
  CalendarLocalizations strings,
  CalendarHourLabelFormat format, {
  required bool end,
}) {
  final endsDay = end && CalendarDates.isDayStart(time);
  final number = CalendarDates.dayNumber(time) - (endsDay ? 1 : 0);
  final minute = endsDay
      ? CalendarDates.minutesPerDay
      : CalendarDates.minuteOfDay(time);
  if (number == day) {
    return strings.formatTime(minute, format);
  }
  return _weekdayTime(number, minute, strings, format);
}

/// The [minute] of the day numbered [number] in [format], after the day's
/// weekday, as "Tue 22:00".
String _weekdayTime(
  int number,
  int minute,
  CalendarLocalizations strings,
  CalendarHourLabelFormat format,
) {
  final weekday = CalendarDates.dateOfDayNumber(number).weekday;
  return "${strings.weekdayAbbreviation(weekday)} "
      "${strings.formatTime(minute, format)}";
}

/// The earlier of [a] and [b], [a] where they are the same instant.
DateTime _earlier(DateTime a, DateTime b) {
  return b.isBefore(a) ? b : a;
}

/// The later of [a] and [b], [a] where they are the same instant.
DateTime _later(DateTime a, DateTime b) {
  return b.isAfter(a) ? b : a;
}

/// A row of the [ScheduleOverlapNotice]'s cards: the overlapped [item], the
/// schedule's [times] and the number of its start [day], which its card
/// reads [item] against, and whether the rules have [refused] the overlap.
/// A row holds all its card shows, so a card that leaves shows, while it
/// shrinks, what it showed before the schedule changed.
typedef _OverlapRow = ({
  CalendarItem item,
  _Range? times,
  int day,
  bool refused,
});

/// An overlapped [item]'s card in the [ScheduleOverlapNotice].
class _OverlapCard extends StatelessWidget {
  const _OverlapCard({
    required this.item,
    required this.times,
    required this.day,
    required this.refused,
    required this.hourLabelFormat,
  });

  final CalendarItem item;

  /// The schedule's times, or null where the clock skips one, under which
  /// the card shows no shared time and no bar.
  final _Range? times;

  /// The day number of the schedule's start day.
  final int day;

  /// Whether the rules refuse the item's overlap.
  final bool refused;

  final CalendarHourLabelFormat hourLabelFormat;

  /// The width of the type's edge colour down the card's leading side.
  static const double _edgeWidth = 4.0;

  static const double _radius = 8.0;

  /// The width of the icon's column and the gap after it, which the lines
  /// under the title are indented by.
  static const double _indent = 22.0;

  static const double _iconSize = 16.0;

  @override
  Widget build(BuildContext context) {
    final strings = CalendarLocalizations.of(context);
    final style = harborTypeStyleOf(item.type);
    final id = item.id;
    String? shares;
    Widget? bar;
    final times = this.times;
    if (times != null) {
      final shared = (
        start: _later(item.start, times.start),
        end: _earlier(item.end, times.end),
      );
      if (shared.end.isAfter(shared.start)) {
        if (!item.start.isAfter(times.start) && !item.end.isBefore(times.end)) {
          shares = "Covers all of this item";
        } else {
          final range = _overlapTimes(
            shared.start,
            shared.end,
            day,
            strings,
            hourLabelFormat,
          );
          final minutes = shared.end.difference(shared.start).inMinutes;
          shares = "Shares $range, ${strings.duration(minutes)}";
        }
        // The axis reaches the shared time's length past each of its ends,
        // and no further than the two items' times, so the shared time
        // fills a third of it or more.
        final length = shared.end.difference(shared.start);
        final axis = (
          start: _later(
            shared.start.subtract(length),
            _earlier(item.start, times.start),
          ),
          end: _earlier(shared.end.add(length), _later(item.end, times.end)),
        );
        bar = _OverlapBar(
          id: id,
          axis: axis,
          mine: times,
          theirs: (start: item.start, end: item.end),
          shared: shared,
          color: item.color,
          refused: refused,
          startLabel: _overlapTime(
            axis.start,
            day,
            strings,
            hourLabelFormat,
            end: false,
          ),
          endLabel: _overlapTime(
            axis.end,
            day,
            strings,
            hourLabelFormat,
            end: true,
          ),
        );
      }
    }
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(_edgeWidth + 10.0, 8.0, 10.0, 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(style.icon, size: _iconSize, color: style.edge),
              const SizedBox(width: _indent - _iconSize),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HarborColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: _indent, top: 2.0),
            child: Text(
              _overlapTimes(
                item.start,
                item.end,
                day,
                strings,
                hourLabelFormat,
              ),
              style: const TextStyle(
                color: HarborColors.textSecondary,
                fontSize: 13.0,
              ),
            ),
          ),
          if (shares != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _indent,
                top: 8.0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: refused
                        ? HarborColors.errorNotice
                        : HarborColors.notice,
                    shape: const StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 2.0,
                    ),
                    child: Text(
                      shares,
                      style: TextStyle(
                        color: refused
                            ? HarborColors.onErrorNotice
                            : HarborColors.onNotice,
                        fontSize: 12.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (bar != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _indent,
                top: 10.0,
              ),
              child: bar,
            ),
        ],
      ),
    );
    return DecoratedBox(
      key: id == null ? null : scheduleOverlapCardKey(id),
      decoration: BoxDecoration(
        color: HarborColors.surface,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Stack(
          children: <Widget>[
            content,
            PositionedDirectional(
              start: 0.0,
              top: 0.0,
              bottom: 0.0,
              width: _edgeWidth,
              child: ColoredBox(color: style.edge),
            ),
          ],
        ),
      ),
    );
  }
}

/// A range of time, its end exclusive.
typedef _Range = ({DateTime start, DateTime end});

/// A card's bar for the overlapped item [id]: an axis of time from
/// [axis]'s start to its end, which one track rounded at both ends fills.
/// On it the [shared] time is striped in [color], the item's, over a tint,
/// soft red where [refused] and soft yellow otherwise ([_StripesPainter]),
/// rounded at both ends and parted from the rest of the track by a gap of
/// the card's colour. The time before and after it is in [color] where it
/// is the item's ([theirs]) and in grey where it is the schedule's
/// ([mine]). Under the axis's ends [startLabel] and [endLabel] write its
/// times. A screen reader skips the bar, as the card's shared time states
/// the same.
class _OverlapBar extends StatelessWidget {
  const _OverlapBar({
    required this.id,
    required this.axis,
    required this.mine,
    required this.theirs,
    required this.shared,
    required this.color,
    required this.refused,
    required this.startLabel,
    required this.endLabel,
  });

  final String? id;
  final _Range axis;
  final _Range mine;
  final _Range theirs;
  final _Range shared;
  final Color color;
  final bool refused;
  final String startLabel;
  final String endLabel;

  static const double _height = 10.0;

  /// The width of the gap of the card's colour around the striped part.
  static const double _gap = 1.5;

  static const BorderRadius _track = BorderRadius.all(
    Radius.circular(_height / 2.0),
  );

  static const TextStyle _labelStyle = TextStyle(
    color: HarborColors.textMuted,
    fontSize: 11.0,
  );

  @override
  Widget build(BuildContext context) {
    final id = this.id;
    final total = axis.end.difference(axis.start).inMicroseconds;
    double fractionOf(DateTime time) {
      final fraction = time.difference(axis.start).inMicroseconds / total;
      return clampDouble(fraction, 0.0, 1.0);
    }

    final before = theirs.start.isBefore(mine.start)
        ? color
        : HarborColors.textSecondary;
    final after = theirs.end.isAfter(mine.end)
        ? color
        : HarborColors.textSecondary;
    final stripes = _StripesPainter(
      tint: refused ? HarborColors.errorNotice : HarborColors.notice,
      stripe: color,
      textDirection: Directionality.of(context),
    );
    return ExcludeSemantics(
      child: Column(
        key: id == null ? null : scheduleOverlapBarKey(id),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            key: id == null ? null : scheduleOverlapAxisKey(id),
            height: _height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final from = width * fractionOf(shared.start);
                final to = width * fractionOf(shared.end);
                // The parts before and after the shared time meet under its
                // middle, so each fills the corners its rounded ends leave.
                final middle = (from + to) / 2.0;
                final radius = math.min(to - from, _height) / 2.0;
                return ClipRRect(
                  borderRadius: _track,
                  child: Stack(
                    children: <Widget>[
                      if (from > 0.0)
                        PositionedDirectional(
                          start: 0.0,
                          top: 0.0,
                          bottom: 0.0,
                          width: middle,
                          child: ColoredBox(
                            key: id == null
                                ? null
                                : scheduleOverlapBeforeKey(id),
                            color: before,
                          ),
                        ),
                      if (to < width)
                        PositionedDirectional(
                          start: middle,
                          end: 0.0,
                          top: 0.0,
                          bottom: 0.0,
                          child: ColoredBox(
                            key: id == null
                                ? null
                                : scheduleOverlapAfterKey(id),
                            color: after,
                          ),
                        ),
                      PositionedDirectional(
                        start: from - _gap,
                        top: -_gap,
                        bottom: -_gap,
                        width: to - from + 2.0 * _gap,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: HarborColors.surface,
                            borderRadius: BorderRadius.all(
                              Radius.circular(radius + _gap),
                            ),
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: from,
                        top: 0.0,
                        bottom: 0.0,
                        width: to - from,
                        child: CustomPaint(
                          key: id == null ? null : scheduleOverlapShareKey(id),
                          painter: stripes,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Row(
              children: <Widget>[
                Text(startLabel, style: _labelStyle),
                const Spacer(),
                Text(endLabel, style: _labelStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the striped part of an [_OverlapBar]: its box, its ends rounded
/// by half its height, or by half its width where it is narrower, filled
/// with [tint] and striped with [stripe], each stripe rising at 45 degrees
/// from the box's bottom edge toward the end of a line of [textDirection].
class _StripesPainter extends CustomPainter {
  const _StripesPainter({
    required this.tint,
    required this.stripe,
    required this.textDirection,
  });

  final Color tint;
  final Color stripe;
  final TextDirection textDirection;

  /// The width of a stripe along the box's width, and of the tint between
  /// two stripes.
  static const double _stripeWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final radius = math.min(size.width, size.height) / 2.0;
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)))
      ..drawRect(box, Paint()..color = tint);
    Offset at(double x, double y) {
      return Offset(textDirection == TextDirection.ltr ? x : size.width - x, y);
    }

    final stripes = Path();
    // The first stripe's foot lies a height before the box, so its top
    // fills the box's first corner.
    for (
      var foot = -size.height;
      foot < size.width;
      foot += 2.0 * _stripeWidth
    ) {
      stripes.addPolygon(<Offset>[
        at(foot, size.height),
        at(foot + _stripeWidth, size.height),
        at(foot + _stripeWidth + size.height, 0.0),
        at(foot + size.height, 0.0),
      ], true);
    }
    canvas
      ..drawPath(stripes, Paint()..color = stripe)
      ..restore();
  }

  @override
  bool shouldRepaint(_StripesPainter oldDelegate) {
    return tint != oldDelegate.tint ||
        stripe != oldDelegate.stripe ||
        textDirection != oldDelegate.textDirection;
  }
}

/// How far past its sides the picker panel shows what its pickers paint,
/// as the badges of a day picker's edge columns, which reach past the
/// picker's sides under [CalendarDayPicker.daysToEdges]; the sheet's page
/// keeps a wider margin around the section.
const double _panelOverhang = 16.0;

/// Clips to its box's height, and [_panelOverhang] past each of its sides.
class _OverhangClipper extends CustomClipper<Rect> {
  const _OverhangClipper();

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      -_panelOverhang,
      0.0,
      size.width + _panelOverhang,
      size.height,
    );
  }

  /// The clip itself, which reaches past the box, rather than the box
  /// [CustomClipper.getApproximateClipRect] takes by default.
  @override
  Rect getApproximateClipRect(Size size) {
    return getClip(size);
  }

  @override
  bool shouldReclip(_OverhangClipper oldClipper) {
    return false;
  }
}

/// The panel under a Start or End row that holds the row's picker, which
/// [builder] builds only while the panel shows. The panel and its picker
/// span the section, as the row does, and the panel clips [_panelOverhang]
/// past its sides, so what the picker paints a little past them shows.
/// As [open] turns true the panel grows from no height to the picker's
/// over the [CalendarTheme]'s motion, the picker fading in over the
/// motion's first half, and as it turns false it shrinks over the motion,
/// the picker fading out over its last half. Each eases on the theme's
/// curve whichever way it runs, so a closing eases as an opening does. All
/// of it happens at once where the platform asks for no animations
/// ([MediaQuery.disableAnimationsOf]), a motion under way included; the
/// panel shows nothing once closed.
///
/// Once it has opened, and where its picker grows once it rests, as a day
/// picker unfolds into its month or the time shows, it scrolls into view:
/// the row, whose [Focus] has [field] for its node, where the row lies
/// before the visible part of the form, then the panel where it lies past
/// it, the panel winning where both do not fit, in one scroll over the
/// [CalendarTheme]'s motion, or at once where the platform asks for no
/// animations. A picker that grows over a motion or under a pointer is
/// revealed once that motion has ended and the pointer has lifted.
class _PickerPanel extends StatefulWidget {
  const _PickerPanel({
    super.key,
    required this.open,
    required this.field,
    required this.builder,
  });

  final bool open;
  final FocusNode field;
  final WidgetBuilder builder;

  @override
  State<_PickerPanel> createState() {
    return _PickerPanelState();
  }
}

class _PickerPanelState extends State<_PickerPanel>
    with SingleTickerProviderStateMixin {
  /// The share of the motion, from the panel's closed end, over which the
  /// picker fades.
  static const double _fadeShare = 0.5;

  late final AnimationController _controller;

  /// [_controller] on the theme's curve, which the panel's height reads.
  late final CurvedAnimation _curved;

  /// The first [_fadeShare] of [_controller] on the theme's curve, which
  /// the picker's opacity reads. [CurvedAnimation] keeps the curve of the
  /// direction a motion started in until the motion ends, so a reversal
  /// mid-motion keeps the opacity continuous.
  late final CurvedAnimation _fade;

  /// Whether the picker grew, while the panel was open with no motion of
  /// its own under way, and has not been revealed since.
  bool _grown = false;

  /// Whether the picker grew since [_revealGrowth] last looked.
  bool _growing = false;

  /// Whether [_revealGrowth] waits among the post-frame callbacks.
  bool _growthQueued = false;

  /// The pointers down on the panel's picker.
  int _pointers = 0;

  /// [_revealGrowth], torn off once.
  late final void Function(Duration) _revealGrowthCallback = _revealGrowth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.open ? 1.0 : 0.0,
    )..addStatusListener(_statusChanged);
    // The theme's curve replaces these in didChangeDependencies, which
    // runs before the first build.
    _curved = CurvedAnimation(parent: _controller, curve: Curves.linear);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.linear);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = CalendarTheme.of(context);
    final curve = theme.motionCurve;
    // A reverse reads its curve from 1 down to 0, so the flip of the curve
    // eases a closing as the curve eases an opening.
    final flipped = FlippedCurve(curve);
    _curved
      ..curve = curve
      ..reverseCurve = flipped;
    _fade
      ..curve = Interval(0.0, _fadeShare, curve: curve)
      ..reverseCurve = Interval(0.0, _fadeShare, curve: flipped);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
    _retime(_controller, duration);
  }

  /// Gives [controller] [duration]. A running motion keeps the duration it
  /// started with, so it starts again from where it is, toward the same
  /// end, under the new one.
  static void _retime(AnimationController controller, Duration duration) {
    if (duration == controller.duration) {
      return;
    }
    controller.duration = duration;
    if (controller.isAnimating) {
      if (controller.status == AnimationStatus.forward) {
        controller.forward();
      } else {
        controller.reverse();
      }
    }
  }

  @override
  void didUpdateWidget(_PickerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      if (widget.open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Drops the picker once the panel has closed, and reveals the panel once
  /// it has opened. Under a zero duration both come inside
  /// [didUpdateWidget] or [didChangeDependencies], during a build.
  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      setState(() {});
    } else if (status == AnimationStatus.completed && widget.open) {
      _revealAfterFrame();
    }
  }

  /// Scrolls the row and then the panel into view after the frame, once
  /// the panel has its height. The row can lie before the view where a
  /// panel above it has closed as this one opened.
  void _revealAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reveal();
      }
    });
  }

  /// Scrolls the form the least that shows the row's leading edge, and
  /// then the panel's trailing edge, which wins where both do not fit: over
  /// the [CalendarTheme]'s motion, or at once where the platform asks for
  /// no animations.
  void _reveal() {
    final position = Scrollable.maybeOf(context)?.position;
    final panel = context.findRenderObject();
    if (position == null || panel == null) {
      return;
    }
    var target = position.pixels;
    final field = widget.field.context?.findRenderObject();
    if (field != null) {
      final viewport = RenderAbstractViewport.of(field);
      target = math.min(target, viewport.getOffsetToReveal(field, 0.0).offset);
    }
    final viewport = RenderAbstractViewport.of(panel);
    target = math.max(target, viewport.getOffsetToReveal(panel, 1.0).offset);
    target = clampDouble(
      target,
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
    } else {
      final theme = CalendarTheme.of(context);
      position.animateTo(
        target,
        duration: theme.motionDuration,
        curve: theme.motionCurve,
      );
    }
  }

  /// [_GrowthBox] laid the picker out taller than before. A growth while
  /// the panel opens needs nothing: its opening reveals it.
  void _grew() {
    if (!widget.open || !_controller.isCompleted) {
      return;
    }
    _grown = true;
    _growing = true;
    _queueGrowthReveal();
  }

  void _queueGrowthReveal() {
    if (_growthQueued) {
      return;
    }
    _growthQueued = true;
    WidgetsBinding.instance.addPostFrameCallback(_revealGrowthCallback);
  }

  /// Reveals a grown picker once its height holds: after a frame in which
  /// it grew, as each frame of a day picker's unfold or of its time's
  /// showing does, this asks again after the next frame, which it
  /// schedules, since no motion may be left to; a pointer down on the
  /// picker asks again as it lifts. So a growth over many frames is
  /// revealed once, a frame after it ends, whatever other motion runs.
  void _revealGrowth(Duration timeStamp) {
    _growthQueued = false;
    if (!mounted || !_grown || _pointers > 0) {
      return;
    }
    if (_growing) {
      _growing = false;
      _queueGrowthReveal();
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    _grown = false;
    if (widget.open && _controller.isCompleted) {
      _reveal();
    }
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers++;
  }

  void _pointerUp(PointerEvent event) {
    _pointers--;
    if (_pointers == 0 && _grown && mounted) {
      _queueGrowthReveal();
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    return FadeTransition(
      opacity: _fade,
      // A SizeTransition of the panel's height, but for its clip, which
      // reaches past the panel's sides as the one inside it does.
      child: AnimatedBuilder(
        animation: _curved,
        builder: (context, child) {
          return ClipRect(
            clipper: const _OverhangClipper(),
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: math.max(_curved.value, 0.0),
              child: child,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: ClipRect(
            clipper: const _OverhangClipper(),
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              child: _GrowthBox(onGrow: _grew, child: widget.builder(context)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays [child] out as it is, and tells [onGrow] where it lays it out
/// taller than it last did.
class _GrowthBox extends SingleChildRenderObjectWidget {
  const _GrowthBox({required this.onGrow, required super.child});

  final VoidCallback onGrow;

  @override
  _RenderGrowthBox createRenderObject(BuildContext context) {
    return _RenderGrowthBox(onGrow: onGrow);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderGrowthBox renderObject) {
    renderObject.onGrow = onGrow;
  }
}

class _RenderGrowthBox extends RenderProxyBox {
  _RenderGrowthBox({required this.onGrow});

  VoidCallback onGrow;

  /// The height of the last layout; null before the first.
  double? _laidOutHeight;

  @override
  void performLayout() {
    super.performLayout();
    final last = _laidOutHeight;
    _laidOutHeight = size.height;
    if (last != null && size.height > last) {
      onGrow();
    }
  }
}
