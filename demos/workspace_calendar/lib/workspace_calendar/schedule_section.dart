/// The item form's schedule summary and schedule section, the parts of the
/// form any item type shares: the section edits a [CalendarSchedule], and
/// the summary shows it and what its [CalendarScheduleCheck] answers as the
/// user edits.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_item.dart';
import 'harbor_theme.dart';

/// The key of the summary's first line: the schedule's date, or the start
/// of a schedule that spans days.
const ValueKey<String> scheduleSummaryFirstLineKey = ValueKey<String>(
  "schedule-summary-first-line",
);

/// The key of the summary's second line: the schedule's times, or the end
/// of a schedule that spans days. An all-day schedule on one day has none.
const ValueKey<String> scheduleSummarySecondLineKey = ValueKey<String>(
  "schedule-summary-second-line",
);

/// The key of the text of the summary's pill, in its top right corner under
/// the zone: the length of a timed schedule of a positive length, or of an
/// all-day schedule, "All day" for one day and its count of days, such as
/// "3 days", for more.
const ValueKey<String> scheduleSummaryLengthKey = ValueKey<String>(
  "schedule-summary-length",
);

/// The key of the summary's zone, the box at the top of its top right
/// corner: the zone's city or the device's zone's name, above the zone's
/// offset from UTC.
const ValueKey<String> scheduleSummaryZoneKey = ValueKey<String>(
  "schedule-summary-zone",
);

/// The key of the summary's overlap notice.
const ValueKey<String> scheduleOverlapKey = ValueKey<String>(
  "schedule-overlap",
);

/// The key of the Start time field.
const ValueKey<String> scheduleStartTimeKey = ValueKey<String>(
  "schedule-start-time",
);

/// The key of the End time field.
const ValueKey<String> scheduleEndTimeKey = ValueKey<String>(
  "schedule-end-time",
);

/// The key of the All day switch.
const ValueKey<String> scheduleAllDayKey = ValueKey<String>("schedule-all-day");

/// The key of the panel under the time row that holds the section's one
/// time picker.
const ValueKey<String> schedulePickerKey = ValueKey<String>("schedule-picker");

/// The section of [check]'s schedule: an All day switch, where the kind
/// takes all-day or the schedule is all-day, which turned off restores the
/// times the schedule keeps; Start date; Start time and End time, each a
/// field whose tap opens the one [CalendarTimePicker], with its haptic
/// feedback on, in a panel under their row; and an End date for an all-day
/// or a multi-day schedule, or after "Ends on another day". Times are
/// written on [hourLabelFormat]'s clock. [ScheduleSummary] shows the
/// schedule, its overlaps and its zone.
///
/// The panel grows and fades in as a field's tap opens it, and shrinks and
/// fades out as the open field's tap closes it, over the [CalendarTheme]'s
/// motion, or at once where the platform asks for no animations; it then
/// scrolls into view. A tap on the other field while the panel is open hands
/// the picker to that field: the panel stays, and the picker's columns move
/// to the field's time.
///
/// A picker refuses a time only for a problem some other time of it
/// avoids: of the check of the schedule with each of the picker's times
/// ([CalendarScheduleCheck.withSchedule]), it takes as witnesses those whose
/// times are checked ([CalendarScheduleCheck.timesChecked]), or every time
/// where none is, and refuses a time whose check names a problem that not
/// every witness's check names. The start's picker offers the hours'
/// starts, the end's its ends, on the start day only those after the
/// start. A picker's Now shows only on a field whose day is [now]'s today,
/// and where the time at or before now is refused picks the first later
/// time the picker offers.
///
/// The section pads what its controls show 16 pixels from its edges: the
/// All day switch's touch target, and the button of "Ends on another day",
/// reach into that padding, so the switch's track and the button's icon and
/// label line up with the fields.
///
/// Every edit goes to [onChanged] as a new schedule. A [locked] section
/// takes no input; a [CalendarScheduleCheck.startFixed] one takes none at
/// its start or kind. An open picker stays open as its field locks, taking
/// no pick, until its field's tap or the All day switch closes it.
/// [errors] holds the form's messages keyed `start` and `end`.
class ScheduleSection extends StatefulWidget {
  const ScheduleSection({
    super.key,
    required this.check,
    required this.hours,
    required this.slotMinutes,
    required this.hourLabelFormat,
    required this.now,
    required this.onChanged,
    this.zone,
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

  /// The current time, whose minute on [zone]'s clock the pickers' Now
  /// picks; Now shows only on a field whose day is its
  /// [CalendarNow.today].
  final ValueGetter<CalendarNow> now;

  final ValueChanged<CalendarSchedule> onChanged;

  /// The zone the times are on, on whose clock the pickers' Now reads the
  /// current minute; none for the device's.
  final Location? zone;

  final bool locked;

  final Map<String, String> errors;

  @override
  State<ScheduleSection> createState() {
    return _ScheduleSectionState();
  }
}

/// A time field of the section.
enum _TimeField { start, end }

/// The space between the section's edges and what its controls show.
const double _edge = 16.0;

/// The All day switch's size, as a share of a [Switch]'s.
const double _allDaySwitchScale = 0.75;

/// The space above the All day switch's track, at its scale: a [Switch]
/// given [MaterialTapTargetSize.padded] is [kMinInteractiveDimension] tall
/// around Material 3's 32-pixel track.
const double _allDaySwitchTop =
    (kMinInteractiveDimension - 32.0) / 2.0 * _allDaySwitchScale;

/// The space beside the All day switch's track, at its scale: the 4 pixels
/// at each side of Material 3's default [SwitchThemeData.padding].
const double _allDaySwitchSide = 4.0 * _allDaySwitchScale;

/// The padding of the button of "Ends on another day" around its icon and
/// label: at its sides, Material 3's for a [TextButton.icon]; above and
/// below, what makes a touch target [kMinInteractiveDimension] tall around
/// its 20-pixel label at the default text scale, and taller around a
/// larger one.
const EdgeInsetsDirectional _endButtonPadding = EdgeInsetsDirectional.fromSTEB(
  12.0,
  14.0,
  16.0,
  14.0,
);

/// [child] padded [_edge] pixels from the section's sides.
Widget _sides(Widget child) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: _edge),
    child: child,
  );
}

/// The lookups the open picker has made of its [_TimeTable], in debug
/// builds; the release build counts none.
int debugSchedulePickerAsks = 0;

/// Which times of [field]'s picker, from [min] to [max] on the [slot]
/// grid, the picker offers under [check]: each time's check is
/// [CalendarScheduleCheck.withSchedule] of the schedule with that time, or
/// [check] itself at the field's own time; the witnesses are the times
/// whose check has [CalendarScheduleCheck.timesChecked], or every time
/// where none has; and a time is offered where each of its problems is a
/// problem of every witness. Computed at the first lookup, and kept while
/// the picker's [check], [field], [min], [max] and [slot] stay.
class _TimeTable {
  _TimeTable({
    required this.check,
    required this.field,
    required this.min,
    required this.max,
    required this.slot,
  });

  final CalendarScheduleCheck<ItemPayload> check;
  final _TimeField field;
  final int min;
  final int max;
  final int slot;

  List<bool>? _offered;

  /// The first time on the grid at or after [min].
  int get _first {
    return (min + slot - 1) ~/ slot * slot;
  }

  /// Whether the table answers for these parameters.
  bool holds(
    CalendarScheduleCheck<ItemPayload> check,
    _TimeField field,
    int min,
    int max,
    int slot,
  ) {
    return identical(this.check, check) &&
        this.field == field &&
        this.min == min &&
        this.max == max &&
        this.slot == slot;
  }

  /// Whether the picker offers [minute], a time on the grid from [min] to
  /// [max].
  bool offers(int minute) {
    assert(() {
      debugSchedulePickerAsks++;
      return true;
    }());
    final first = _first;
    assert(
      minute >= first && minute <= max && (minute - first) % slot == 0,
      "$minute lies off the table of $first to $max by $slot",
    );
    final offered = _offered ??= _compute();
    return offered[(minute - first) ~/ slot];
  }

  List<bool> _compute() {
    final schedule = check.schedule;
    final start = field == _TimeField.start;
    final own = start ? schedule.startMinute : schedule.endMinute;
    final checks = <CalendarScheduleCheck<ItemPayload>>[
      for (var time = _first; time <= max; time += slot)
        if (time == own)
          check
        else
          check.withSchedule(
            start
                ? schedule.withStartMinute(time)
                : schedule.withEndMinute(time),
          ),
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
    final every = shared ?? const <CalendarScheduleProblem>{};
    return <bool>[
      for (final each in checks) each.problems.every(every.contains),
    ];
  }
}

class _ScheduleSectionState extends State<ScheduleSection> {
  /// Whether "Ends on another day" showed the End date of a schedule that
  /// ends on its start day.
  bool _endDayShown = false;

  /// The field whose picker is open; none where null.
  _TimeField? _open;

  /// The field the panel's picker edits: the open one, or else the last
  /// open one, whose picker the panel builds only while it closes; none
  /// where null.
  _TimeField? _shown;

  /// The open picker's table, kept across builds while it holds.
  _TimeTable? _table;

  final FocusNode _startFieldNode = FocusNode(debugLabel: "Start time");
  final FocusNode _endFieldNode = FocusNode(debugLabel: "End time");

  /// The nodes of the [Focus] around each time field, which take the focus
  /// back as a field that takes no input closes its picker: an [InkWell]
  /// with no tap takes none.
  final FocusNode _startRestNode = FocusNode(
    debugLabel: "Start time rest",
    skipTraversal: true,
  );
  final FocusNode _endRestNode = FocusNode(
    debugLabel: "End time rest",
    skipTraversal: true,
  );

  /// The node of the picker's Hour column, whichever field it edits.
  final FocusNode _pickerHourNode = FocusNode(debugLabel: "Hour column");
  final FocusNode _allDayNode = FocusNode(debugLabel: "All day");

  @override
  void didUpdateWidget(ScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_schedule.isAllDay) {
      _open = null;
      _shown = null;
    }
  }

  @override
  void dispose() {
    _startFieldNode.dispose();
    _endFieldNode.dispose();
    _startRestNode.dispose();
    _endRestNode.dispose();
    _pickerHourNode.dispose();
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

  Future<void> _pickDate(
    DateTime initial,
    ValueChanged<DateTime> onPicked,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      onPicked(CalendarDates.dateOnly(picked));
    }
  }

  Widget _dateField({
    required String label,
    required DateTime date,
    required String? error,
    required ValueChanged<DateTime>? onPicked,
  }) {
    return InkWell(
      onTap: onPicked == null
          ? null
          : () {
              _pickDate(date, onPicked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(CalendarDates.isoDate(date)),
      ),
    );
  }

  /// Whether [field] takes input: the start where neither the section is
  /// locked nor the start fixed, the end where the section is not locked.
  bool _takesInput(_TimeField field) {
    return field == _TimeField.start ? !_startLocked : !widget.locked;
  }

  /// Opens the panel with [field]'s picker, hands the open picker to
  /// [field] where the other field's is open, or closes the panel where
  /// [field]'s is open. A spin of the picker's columns that the tap cuts off
  /// reports nothing: a close gives the closing picker a null `onChanged`,
  /// and a switch gives the picker a new [CalendarTimePicker.subject].
  void _tapTimeField(_TimeField field) {
    final start = field == _TimeField.start;
    if (_open == field) {
      setState(() {
        _open = null;
      });
      // Made before the next frame, so the closing picker's Hour column no
      // longer holds the focus as the panel shrinks and leaves the tree.
      if (_takesInput(field)) {
        (start ? _startFieldNode : _endFieldNode).requestFocus();
      } else {
        (start ? _startRestNode : _endRestNode).requestFocus();
      }
      return;
    }
    setState(() {
      _open = field;
      _shown = field;
    });
    // The picker's Hour column takes the focus as the panel opens, the
    // request waiting for the column to join the tree where the panel was
    // closed.
    _pickerHourNode.requestFocus();
  }

  /// The Start time or End time field, showing [minute]; its tap opens or
  /// closes its picker.
  Widget _timeField(
    _TimeField field, {
    required String label,
    required int minute,
    required String? error,
  }) {
    final strings = CalendarLocalizations.of(context);
    final start = field == _TimeField.start;
    final open = _open == field;
    return Focus(
      key: start ? scheduleStartTimeKey : scheduleEndTimeKey,
      focusNode: start ? _startRestNode : _endRestNode,
      child: InkWell(
        focusNode: start ? _startFieldNode : _endFieldNode,
        onTap: open || _takesInput(field)
            ? () {
                _tapTimeField(field);
              }
            : null,
        child: InputDecorator(
          isFocused: open,
          decoration: InputDecoration(labelText: label, errorText: error),
          child: Text(strings.formatTime(minute, widget.hourLabelFormat)),
        ),
      ),
    );
  }

  /// The current minute after midnight on the zone's clock.
  int _nowMinute() {
    return CalendarDates.minuteOfDay(
      CalendarDates.inZone(widget.now().time, zone: widget.zone),
    );
  }

  /// The table of [field]'s picker from [min] to [max]: the kept one where
  /// it holds for the section's check, these bounds and the slot, and a new
  /// one otherwise.
  _TimeTable _tableFor(_TimeField field, int min, int max) {
    final check = widget.check;
    final slot = widget.slotMinutes;
    final table = _table;
    if (table != null && table.holds(check, field, min, max, slot)) {
      return table;
    }
    return _table = _TimeTable(
      check: check,
      field: field,
      min: min,
      max: max,
      slot: slot,
    );
  }

  /// The current minute for a picker whose field lies on [day]: Now shows
  /// only where [day] is the [CalendarNow.today] of [ScheduleSection.now].
  ValueGetter<int>? _nowOn(DateTime day) {
    final today = widget.now().today;
    if (CalendarDates.dayNumber(day) != CalendarDates.dayNumber(today)) {
      return null;
    }
    return _nowMinute;
  }

  /// The day of [field]'s time.
  DateTime _dayOf(_TimeField field) {
    return field == _TimeField.start ? _schedule.startDay : _schedule.endDay;
  }

  /// The panel's picker, editing [field], whose key is its
  /// [CalendarTimePicker.subject]: the start's offers the hours' starts; the
  /// end's the hours' ends, on the start's day only those after the start,
  /// or where the start leaves no such end in the hours a row for its own
  /// time alone. Each time is offered as its [_TimeTable] answers, so a time
  /// is refused only for a problem some other time of the picker avoids. It
  /// takes no pick while the panel closes or where [field] takes no input.
  Widget _picker(_TimeField field) {
    final schedule = _schedule;
    final hours = widget.hours;
    final slot = widget.slotMinutes;
    final start = field == _TimeField.start;
    int min;
    int max;
    if (start) {
      min = hours.start;
      max = math.max(hours.start, hours.end - slot);
    } else {
      min = hours.start + slot;
      max = hours.end;
      if (!schedule.spansDays) {
        min = math.max(min, schedule.startMinute + 1);
      }
      if (min > max) {
        min = schedule.endMinute;
        max = schedule.endMinute;
      }
    }
    return CalendarTimePicker(
      subject: start ? scheduleStartTimeKey : scheduleEndTimeKey,
      value: start ? schedule.startMinute : schedule.endMinute,
      onChanged: _open == null || !_takesInput(field)
          ? null
          : (minute) {
              if (minute != null) {
                _change(
                  start
                      ? schedule.withStartMinute(minute)
                      : schedule.withEndMinute(minute),
                );
              }
            },
      hourLabelFormat: widget.hourLabelFormat,
      minuteStep: slot,
      min: min,
      max: max,
      isEnabled: _tableFor(field, min, max).offers,
      now: _nowOn(_dayOf(field)),
      nowPicksLater: true,
      focusNode: _pickerHourNode,
      hapticFeedback: true,
    );
  }

  /// The All day switch, at [_allDaySwitchScale] of a [Switch]'s size, on
  /// the right of its label, which takes no tap.
  Widget _allDayRow(CalendarSchedule schedule, bool startLocked) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              "All day",
              style: theme.textTheme.bodyLarge?.copyWith(
                color: startLocked
                    ? theme.disabledColor
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
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
                        if (on) {
                          // The time row and its open picker go away; the
                          // focus their Hour column held moves to the
                          // switch, not to the scope's last focused node.
                          setState(() {
                            _open = null;
                            _shown = null;
                          });
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

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    final errors = widget.errors;
    final locked = widget.locked;
    final startLocked = _startLocked;
    final open = _open;
    final shown = _shown;
    final timed = !schedule.isAllDay;
    final showsEndDay =
        schedule.isAllDay ||
        schedule.spansDays ||
        (_endDayShown && _options.spansDays);
    final allDayShows = _options.allowsAllDay || schedule.isAllDay;
    final endButtonShows = !showsEndDay && _options.spansDays && !locked;
    final children = <Widget>[
      if (allDayShows)
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: _edge,
            end: _edge - _allDaySwitchSide,
          ),
          child: _allDayRow(schedule, startLocked),
        ),
      _sides(
        _dateField(
          label: "Start date",
          date: schedule.startDay,
          error: timed ? null : errors["start"],
          onPicked: startLocked
              ? null
              : (day) {
                  _change(schedule.withStartDay(day));
                },
        ),
      ),
      if (timed)
        _sides(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _timeField(
                      _TimeField.start,
                      label: "Start time",
                      minute: schedule.startMinute,
                      error: errors["start"],
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: _timeField(
                      _TimeField.end,
                      label: "End time",
                      minute: schedule.endMinute,
                      error: showsEndDay ? null : errors["end"],
                    ),
                  ),
                ],
              ),
              _PickerPanel(
                key: schedulePickerKey,
                open: open != null,
                // The picker shows its footer, Now, only on today's field.
                revealKey: open != null && _nowOn(_dayOf(open)) != null,
                builder: shown == null
                    ? null
                    : (context) {
                        return _picker(shown);
                      },
              ),
            ],
          ),
        ),
      if (showsEndDay)
        _sides(
          _dateField(
            label: "End date",
            date: schedule.endDay,
            error: errors["end"],
            onPicked: locked
                ? null
                : (day) {
                    _change(schedule.withEndDay(day));
                  },
          ),
        )
      else if (endButtonShows)
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: _edge - _endButtonPadding.start,
            end: _edge,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: _endButtonPadding,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
              ),
              onPressed: () {
                setState(() {
                  _endDayShown = true;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text("Ends on another day"),
            ),
          ),
        ),
    ];
    // The top and the bottom padding are measured to what the first and the
    // last control show.
    return Padding(
      padding: EdgeInsets.only(
        top: allDayShows ? _edge - _allDaySwitchTop : _edge,
        bottom: endButtonShows ? _edge - _endButtonPadding.bottom : _edge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < children.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 12.0),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// [minutes] written in hours and minutes, as "1h 30m", "2h" or "45m".
String _lengthLabel(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) {
    return "${rest}m";
  }
  if (rest == 0) {
    return "${hours}h";
  }
  return "${hours}h ${rest}m";
}

/// The summary of [check]'s schedule, top to bottom: its date, and a timed
/// schedule's times under it, or an all-day schedule's date alone, as large
/// as times; for a schedule that spans days, its start and its end instead,
/// each under its label, Start or End, in smaller type, and shrunk onto one
/// line where its room is too narrow: a timed one's each a date and a
/// time, an all-day one's its first and last day; and, while
/// [CalendarScheduleCheck.overlaps] is not empty, an overlap
/// notice naming them, whose "Next free time" sends
/// [CalendarScheduleCheck.nextFree] to [onChanged] unless the form is
/// [locked] or the check's start is fixed. Times are written on
/// [hourLabelFormat]'s clock.
///
/// Its top right corner shows, in a light grey rounded box, [zone]'s name,
/// its city ([CalendarZonePanel.cityOf]) or, for the device's zone,
/// [CalendarLocalizations.deviceZoneName], above the zone's offset from UTC
/// at the start ([CalendarLocalizations.utcOffset]), or at its day's start
/// where the zone's clock skips the start; and under the box, a pill with a
/// timer icon before the schedule's length: an all-day schedule's "All
/// day" for one day, or its count of civil days, such as "3 days", for
/// more; or a timed schedule's hours and minutes, where it is positive. The
/// corner lies at the same place whatever lines the schedule shows beside
/// it.
class ScheduleSummary extends StatelessWidget {
  const ScheduleSummary({
    super.key,
    required this.check,
    required this.hourLabelFormat,
    required this.onChanged,
    this.zone,
    this.locked = false,
  });

  final CalendarScheduleCheck<ItemPayload> check;

  /// The clock the summary writes times on.
  final CalendarHourLabelFormat hourLabelFormat;

  /// Takes the schedule "Next free time" moves to.
  final ValueChanged<CalendarSchedule> onChanged;

  /// The zone the times are on, which the summary names; none for the
  /// device's.
  final Location? zone;

  /// Whether the form takes no input, under which "Next free time" does
  /// not show.
  final bool locked;

  /// The first line of a schedule on one day or of an all-day one.
  static const TextStyle _dayStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w500,
    color: HarborColors.textMuted,
  );

  /// The second line of a schedule on one day or of an all-day one.
  static const TextStyle _timesStyle = TextStyle(
    fontSize: 22.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.text,
  );

  /// Both lines of a schedule that spans days, each a date or a date and a
  /// time, smaller than [_timesStyle] so that they fit beside the corner
  /// on a narrow screen.
  static const TextStyle _spanStyle = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.text,
  );

  /// The Start and End labels above the lines of a schedule that spans
  /// days.
  static const TextStyle _spanLabelStyle = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
    color: HarborColors.textMuted,
  );

  /// The text of the pill.
  static const TextStyle _lengthStyle = TextStyle(
    fontSize: 12.0,
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
            Text(label, key: scheduleSummaryLengthKey, style: _lengthStyle),
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
        CalendarDates.timeAtWallMinute(
          day * CalendarDates.minutesPerDay + schedule.startMinute,
          zone: zone,
        ) ??
        CalendarDates.dateOfDayNumber(day, zone: zone);
    return Container(
      key: scheduleSummaryZoneKey,
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

  Widget _overlapNotice() {
    final next = check.nextFree;
    return DecoratedBox(
      key: scheduleOverlapKey,
      decoration: BoxDecoration(
        color: HarborColors.notice,
        border: Border.all(color: HarborColors.noticeEdge),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 8.0, 8.0, 8.0),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.warning_amber,
              size: 18.0,
              color: HarborColors.onNotice,
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                "Overlaps ${check.overlaps.map((other) {
                  return other.title;
                }).join(", ")}",
                style: const TextStyle(color: HarborColors.onNotice),
              ),
            ),
            if (next != null &&
                next != check.schedule &&
                !(locked || check.startFixed))
              TextButton(
                onPressed: () {
                  onChanged(next);
                },
                child: const Text("Next free time"),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    final strings = CalendarLocalizations.of(context);
    final schedule = check.schedule;
    final startDay = dates.formatMediumDate(schedule.startDay);
    final endDay = dates.formatMediumDate(schedule.endDay);
    final start = strings.formatTime(schedule.startMinute, hourLabelFormat);
    final end = strings.formatTime(schedule.endMinute, hourLabelFormat);
    final timed = !schedule.isAllDay;
    final spans = schedule.spansDays;
    final String first;
    final String? second;
    if (!timed) {
      first = startDay;
      second = spans ? endDay : null;
    } else if (spans) {
      first = "$startDay, $start";
      second = "$endDay, $end";
    } else {
      first = startDay;
      second = "$start - $end";
    }
    final TextStyle firstStyle;
    if (spans) {
      firstStyle = _spanStyle;
    } else if (timed) {
      firstStyle = _dayStyle;
    } else {
      firstStyle = _timesStyle;
    }
    final firstLine = Text(
      first,
      key: scheduleSummaryFirstLineKey,
      style: firstStyle,
    );
    final secondLine = second == null
        ? null
        : Text(
            second,
            key: scheduleSummarySecondLineKey,
            style: spans ? _spanStyle : _timesStyle,
          );
    final String? pill;
    if (!timed) {
      final days =
          CalendarDates.daysBetween(schedule.startDay, schedule.endDay) + 1;
      pill = days > 1 ? "$days days" : "All day";
    } else if (schedule.lengthMinutes > 0) {
      pill = _lengthLabel(schedule.lengthMinutes);
    } else {
      pill = null;
    }
    // A line of a schedule that spans days sits under its label and, too
    // wide for the room beside the corner, shrinks onto one line.
    Widget spanLine(String label, Widget line) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: _spanLabelStyle),
          const SizedBox(height: 2.0),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: line,
          ),
        ],
      );
    }

    final lines = <Widget>[
      if (secondLine == null)
        firstLine
      else if (spans) ...<Widget>[
        spanLine("Start", firstLine),
        spanLine("End", secondLine),
      ] else ...<Widget>[firstLine, secondLine],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (
                    var index = 0;
                    index < lines.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) SizedBox(height: spans ? 8.0 : 4.0),
                    lines[index],
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12.0),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _zone(strings),
                if (pill != null) ...<Widget>[
                  const SizedBox(height: 6.0),
                  _pill(pill),
                ],
              ],
            ),
          ],
        ),
        if (check.overlaps.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12.0),
          _overlapNotice(),
        ],
      ],
    );
  }
}

/// The panel under the time row that holds the section's one picker, which
/// [builder] builds, called only while the panel shows. As [open] turns
/// true it grows from no height to the picker's and fades in, and as it
/// turns false it shrinks and fades out, over the [CalendarTheme]'s
/// motion, or at once where the platform asks for no animations
/// ([MediaQuery.disableAnimationsOf]), a motion under way included; it
/// shows nothing once closed or where [builder] is null. A panel made while
/// [open] shows its picker at once. Once it has opened, it scrolls into
/// view where it lies past the visible part of the form, and again where
/// [revealKey] changes while it is open, as the picker's footer comes or
/// goes.
class _PickerPanel extends StatefulWidget {
  const _PickerPanel({
    super.key,
    required this.open,
    required this.revealKey,
    required this.builder,
  });

  final bool open;
  final Object? revealKey;
  final WidgetBuilder? builder;

  @override
  State<_PickerPanel> createState() {
    return _PickerPanelState();
  }
}

class _PickerPanelState extends State<_PickerPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// [_controller] on the theme's curve, which both transitions read.
  late final CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.open ? 1.0 : 0.0,
    )..addStatusListener(_statusChanged);
    // The theme's curve replaces this one in didChangeDependencies, which
    // runs before the first build.
    _curved = CurvedAnimation(parent: _controller, curve: Curves.linear);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = CalendarTheme.of(context);
    _curved.curve = theme.motionCurve;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
    if (duration == _controller.duration) {
      return;
    }
    _controller.duration = duration;
    // A running motion keeps the duration it started with, so it starts
    // again from where it is, toward the same end, under the new one.
    if (_controller.isAnimating) {
      if (_controller.status == AnimationStatus.forward) {
        _controller.forward();
      } else {
        _controller.reverse();
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
    if (widget.revealKey != oldWidget.revealKey &&
        widget.open &&
        _controller.isCompleted) {
      _revealAfterFrame();
    }
  }

  @override
  void dispose() {
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

  /// Scrolls the panel into view after the frame, once it has its height.
  void _revealAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.builder;
    if (builder == null || (!widget.open && _controller.isDismissed)) {
      return const SizedBox.shrink();
    }
    return FadeTransition(
      opacity: _curved,
      child: SizeTransition(
        sizeFactor: _curved,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: builder(context),
        ),
      ),
    );
  }
}
