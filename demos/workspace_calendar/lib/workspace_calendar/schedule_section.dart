/// The item form's schedule heading, schedule section and overlap notice,
/// the parts of the form any item type shares: the section edits a
/// [CalendarSchedule], the heading shows its length and zone beside the
/// form's title, and the notice shows a card of each entry it overlaps, as
/// its [CalendarScheduleCheck] answers while the user edits.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_item.dart';
import 'harbor_theme.dart';
import 'item_builders.dart' show ItemCard;

/// The key of the text of the heading's length pill, after its title: the
/// length of a timed schedule of a positive length, or of an all-day
/// schedule, "All day" for one day and its count of days, such as "3 days",
/// for more.
const ValueKey<String> scheduleLengthKey = ValueKey<String>("schedule-length");

/// The key of the heading's zone box, at its right end: the zone's city or
/// the device's zone's name, above the zone's offset from UTC.
const ValueKey<String> scheduleZoneKey = ValueKey<String>("schedule-zone");

/// The key of the overlap notice.
const ValueKey<String> scheduleOverlapKey = ValueKey<String>(
  "schedule-overlap",
);

/// The key of the overlap notice's card of the overlapped item [id].
ValueKey<String> scheduleOverlapCardKey(String id) {
  return ValueKey<String>("schedule-overlap-card-$id");
}

/// The key of the bar of the overlap notice's card of the item [id], which
/// stands for the schedule's time.
ValueKey<String> scheduleOverlapBarKey(String id) {
  return ValueKey<String>("schedule-overlap-bar-$id");
}

/// The key of the filled part of the bar of the overlap notice's card of
/// the item [id]: the part of the schedule's time the item shares.
ValueKey<String> scheduleOverlapShareKey(String id) {
  return ValueKey<String>("schedule-overlap-share-$id");
}

/// The key of the [Focus] around the Start date field.
const ValueKey<String> scheduleStartDateKey = ValueKey<String>(
  "schedule-start-date",
);

/// The key of the [Focus] around the End date field.
const ValueKey<String> scheduleEndDateKey = ValueKey<String>(
  "schedule-end-date",
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

/// The key of the panel under the Start row that holds Start date's day
/// picker or Start time's picker.
const ValueKey<String> scheduleStartPanelKey = ValueKey<String>(
  "schedule-start-panel",
);

/// The key of the panel under the End row that holds End date's day picker
/// or End time's picker.
const ValueKey<String> scheduleEndPanelKey = ValueKey<String>(
  "schedule-end-panel",
);

/// The section of [check]'s schedule: an All day switch, where the kind
/// takes all-day or the schedule is all-day, which turned off restores the
/// times the schedule keeps; then a Start row, Start date beside Start
/// time, above an End row, End date beside End time, each date taking
/// three fifths of its row; an all-day schedule's rows hold their dates
/// alone. A field's tap opens its own picker in a panel under the field's
/// row, one of the four open at a time, the field drawn focused while it
/// is open. A time field's picker is a [CalendarTimePicker], with its
/// haptic feedback on, whose Hour column takes the focus. A date field's is
/// a [CalendarDayPicker], folded on the week of the field's day, that day
/// selected and the [CalendarNow.today] of [now] ringed, its weeks starting
/// on the weekday column [firstColumn], and its days with entries of
/// [store] badged as [dayBadges] marks them, the circles of its first and
/// last columns on the row's sides
/// ([CalendarDayPicker.daysToEdges]); the field keeps the focus. A
/// tap on a day there moves the field's day to it and leaves the picker
/// open, and its chevrons, swipes and month picks only browse, End date's
/// to no week, month or year before the start day's
/// ([CalendarDayPicker.browsesBeforeFirstDay]). Each opening
/// of a date field shows its picker folded. A day picker draws disabled,
/// and takes no tap on, the days its check's day answers rule out: Start
/// date's those before [CalendarScheduleCheck.firstStartDay], End date's
/// those outside [CalendarScheduleCheck.endDays]; the section reads them
/// of each check once, as a day picker first builds under it. Times are
/// written on [hourLabelFormat]'s clock. [ScheduleHeading] shows the
/// schedule's length and zone, and [ScheduleOverlapNotice] its overlaps.
///
/// A panel grows and fades in as its field's tap opens it, and shrinks and
/// fades out as that field's tap closes it, over the [CalendarTheme]'s
/// motion, or at once where the platform asks for no animations; it then
/// scrolls into view, and again where its picker grows once it rests, as a
/// day picker unfolds into its month. A tap on the other field of the
/// panel's row swaps the panel's pickers in place over that motion, its
/// height moving from the one picker's to the other's as the leaving one
/// fades out over the motion's first half and the coming one fades in over
/// its last. A tap on a field of the other row closes the panel as the
/// field's own opens. A picker whose field is not the open one takes no
/// pick.
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
/// The section pads its controls by nothing. Its rows reach its sides; at
/// its top lies the All day row, the switch's touch target whole, or with
/// no switch the Start row; and at its bottom the End row's fields, or its
/// panel while open.
///
/// Every edit goes to [onChanged] as a new schedule. A [locked] section
/// takes no input; a [CalendarScheduleCheck.startFixed] one takes none at
/// its start or kind; and End date takes none where the options refuse
/// spanning days ([CalendarScheduleOptions.spansDays]) and the schedule ends
/// on its start day. An open picker stays open as its field locks, taking
/// no pick, until its field's tap closes it, or for a time picker the All
/// day switch. The switch turned on closes an open time picker and takes
/// the focus from a time field; an open date field keeps its panel, its
/// picker and the focus whichever way the switch turns.
/// [errors] holds the form's messages keyed `start` and `end`, which show on
/// Start time and End time, or for an all-day schedule on Start date and
/// End date.
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
    this.store,
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

  /// The current time, whose minute on [zone]'s clock the pickers' Now
  /// picks; Now shows only on a field whose day is its
  /// [CalendarNow.today].
  final ValueGetter<CalendarNow> now;

  final ValueChanged<CalendarSchedule> onChanged;

  /// The zone the times are on, on whose clock the pickers' Now reads the
  /// current minute; none for the device's.
  final Location? zone;

  /// The store whose entries badge the day pickers' days; none for no
  /// badges.
  final CalendarStore<ItemPayload>? store;

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

/// A row of the section, Start or End, and its time field.
enum _TimeField {
  start,
  end;

  /// The row's date field.
  _ScheduleField get dateField {
    return this == start ? _ScheduleField.startDate : _ScheduleField.endDate;
  }

  /// The row's time field.
  _ScheduleField get timeField {
    return this == start ? _ScheduleField.startTime : _ScheduleField.endTime;
  }
}

/// A field of the section, each of which opens its own picker.
enum _ScheduleField {
  startDate,
  startTime,
  endDate,
  endTime;

  /// The row the field lies in.
  _TimeField get row {
    return this == startDate || this == startTime
        ? _TimeField.start
        : _TimeField.end;
  }

  /// Whether the field is a date field.
  bool get isDate {
    return this == startDate || this == endDate;
  }
}

/// The All day switch's size, as a share of a [Switch]'s.
const double _allDaySwitchScale = 0.75;

/// The shares of a Start or End row that its date and its time take: the
/// date three fifths, the time two.
const int _dateFlex = 3;
const int _timeFlex = 2;

/// The lookups the open picker has made of its [_TimeTable], in debug
/// builds; the release build counts none.
int debugSchedulePickerAsks = 0;

/// The reads the section has made of its check's day ranges,
/// [CalendarScheduleCheck.firstStartDay] and
/// [CalendarScheduleCheck.endDays], in debug builds; the release build
/// counts none.
int debugScheduleDayRangeAsks = 0;

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

/// The state of a [ScheduleSection], which finds the field a message of
/// [ScheduleSection.errors] shows on.
class ScheduleSectionState extends State<ScheduleSection> {
  /// The field whose picker is open; none where null.
  _ScheduleField? _open;

  /// How many times each date field has opened its picker, which keys the
  /// row's day picker, so that each opening builds a new one, folded.
  int _startDateOpenings = 0;
  int _endDateOpenings = 0;

  /// Each field's picker's table, kept across builds while it holds.
  final Map<_TimeField, _TimeTable> _tables = <_TimeField, _TimeTable>{};

  /// The check [_startRange] and [_endRange] were read of; none before a
  /// day picker first builds.
  CalendarScheduleCheck<ItemPayload>? _rangedCheck;

  /// The first and last day the Start row's and the End row's day pickers
  /// take, null for none.
  ({DateTime? first, DateTime? last}) _startRange = (first: null, last: null);
  ({DateTime? first, DateTime? last}) _endRange = (first: null, last: null);

  final FocusNode _startDateNode = FocusNode(debugLabel: "Start date");
  final FocusNode _endDateNode = FocusNode(debugLabel: "End date");
  final FocusNode _startFieldNode = FocusNode(debugLabel: "Start time");
  final FocusNode _endFieldNode = FocusNode(debugLabel: "End time");

  /// The nodes of the [Focus] around each field, which take the focus back
  /// as a field that takes no input closes its picker: an [InkWell] with no
  /// tap takes none.
  final FocusNode _startDateRestNode = FocusNode(
    debugLabel: "Start date rest",
    skipTraversal: true,
  );
  final FocusNode _endDateRestNode = FocusNode(
    debugLabel: "End date rest",
    skipTraversal: true,
  );
  final FocusNode _startRestNode = FocusNode(
    debugLabel: "Start time rest",
    skipTraversal: true,
  );
  final FocusNode _endRestNode = FocusNode(
    debugLabel: "End time rest",
    skipTraversal: true,
  );

  /// The nodes of each picker's Hour column.
  final FocusNode _startHourNode = FocusNode(debugLabel: "Start Hour column");
  final FocusNode _endHourNode = FocusNode(debugLabel: "End Hour column");
  final FocusNode _allDayNode = FocusNode(debugLabel: "All day");

  @override
  void didUpdateWidget(ScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final open = _open;
    // An all-day schedule has no time fields; an open date field stays.
    if (_schedule.isAllDay && open != null && !open.isDate) {
      _open = null;
    }
  }

  @override
  void dispose() {
    _startDateNode.dispose();
    _endDateNode.dispose();
    _startFieldNode.dispose();
    _endFieldNode.dispose();
    _startDateRestNode.dispose();
    _endDateRestNode.dispose();
    _startRestNode.dispose();
    _endRestNode.dispose();
    _startHourNode.dispose();
    _endHourNode.dispose();
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

  /// Whether [field] takes input: Start date and Start time where neither
  /// the section is locked nor the start fixed; End time where the section
  /// is not locked; and End date where it is not locked and the options
  /// take spanning days or the schedule spans them.
  bool _takesInput(_ScheduleField field) {
    switch (field) {
      case _ScheduleField.startDate:
      case _ScheduleField.startTime:
        return !_startLocked;
      case _ScheduleField.endDate:
        return !widget.locked && (_options.spansDays || _schedule.spansDays);
      case _ScheduleField.endTime:
        return !widget.locked;
    }
  }

  /// The node of [field]'s [InkWell].
  FocusNode _fieldNodeOf(_ScheduleField field) {
    switch (field) {
      case _ScheduleField.startDate:
        return _startDateNode;
      case _ScheduleField.startTime:
        return _startFieldNode;
      case _ScheduleField.endDate:
        return _endDateNode;
      case _ScheduleField.endTime:
        return _endFieldNode;
    }
  }

  /// The node of the [Focus] around [field].
  FocusNode _restNodeOf(_ScheduleField field) {
    switch (field) {
      case _ScheduleField.startDate:
        return _startDateRestNode;
      case _ScheduleField.startTime:
        return _startRestNode;
      case _ScheduleField.endDate:
        return _endDateRestNode;
      case _ScheduleField.endTime:
        return _endRestNode;
    }
  }

  /// The context of the field that shows the message of
  /// [ScheduleSection.errors] keyed [key], `start` or `end`: its row's time
  /// field, or for an all-day schedule its date field, each built in every
  /// build that shows its schedule; null before the section first builds.
  BuildContext? errorFieldOf(String key) {
    final row = key == "start" ? _TimeField.start : _TimeField.end;
    return _restNodeOf(
      _schedule.isAllDay ? row.dateField : row.timeField,
    ).context;
  }

  /// Whether a time field, or anything under its [Focus], has the focus.
  bool get _timeFieldHasFocus {
    return _startFieldNode.hasFocus ||
        _endFieldNode.hasFocus ||
        _startRestNode.hasFocus ||
        _endRestNode.hasFocus;
  }

  /// Opens [field]'s picker, closing or swapping out the open one, or
  /// closes [field]'s where it is open. A spin of a time picker's columns
  /// that the tap cuts off reports nothing: a picker whose field is not the
  /// open one has a null `onChanged`.
  void _tapField(_ScheduleField field) {
    if (_open == field) {
      setState(() {
        _open = null;
      });
      // Made before the next frame, so the closing picker's Hour column no
      // longer holds the focus as the panel shrinks and leaves the tree.
      if (_takesInput(field)) {
        _fieldNodeOf(field).requestFocus();
      } else {
        _restNodeOf(field).requestFocus();
      }
      return;
    }
    setState(() {
      _open = field;
      if (field == _ScheduleField.startDate) {
        _startDateOpenings++;
      } else if (field == _ScheduleField.endDate) {
        _endDateOpenings++;
      }
    });
    if (field.isDate) {
      _fieldNodeOf(field).requestFocus();
    } else {
      // The picker's Hour column takes the focus as its panel opens, the
      // request waiting for the column to join the tree.
      (field.row == _TimeField.start ? _startHourNode : _endHourNode)
          .requestFocus();
    }
  }

  /// The Start date or End date field of [row], showing the row's day with
  /// its weekday ([MaterialLocalizations.formatMediumDate]); its tap opens
  /// or closes its day picker.
  Widget _dateField(_TimeField row, {required String? error}) {
    final field = row.dateField;
    final start = row == _TimeField.start;
    final open = _open == field;
    return Focus(
      key: start ? scheduleStartDateKey : scheduleEndDateKey,
      focusNode: _restNodeOf(field),
      child: InkWell(
        focusNode: _fieldNodeOf(field),
        onTap: open || _takesInput(field)
            ? () {
                _tapField(field);
              }
            : null,
        child: InputDecorator(
          isFocused: open,
          decoration: InputDecoration(
            labelText: start ? "Start date" : "End date",
            errorText: error,
          ),
          child: Text(
            MaterialLocalizations.of(
              context,
            ).formatMediumDate(start ? _schedule.startDay : _schedule.endDay),
          ),
        ),
      ),
    );
  }

  /// The Start time or End time field of [row], showing [minute]; its tap
  /// opens or closes its picker.
  Widget _timeField(
    _TimeField row, {
    required String label,
    required int minute,
    required String? error,
  }) {
    final strings = CalendarLocalizations.of(context);
    final field = row.timeField;
    final open = _open == field;
    return Focus(
      key: row == _TimeField.start ? scheduleStartTimeKey : scheduleEndTimeKey,
      focusNode: _restNodeOf(field),
      child: InkWell(
        focusNode: _fieldNodeOf(field),
        onTap: open || _takesInput(field)
            ? () {
                _tapField(field);
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
    final table = _tables[field];
    if (table != null && table.holds(check, field, min, max, slot)) {
      return table;
    }
    return _tables[field] = _TimeTable(
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

  /// [field]'s picker, whose field's key is its
  /// [CalendarTimePicker.subject]: the start's offers the hours' starts; the
  /// end's the hours' ends, on the start's day only those after the start,
  /// or where the start leaves no such end in the hours a row for its own
  /// time alone. Each time is offered as its [_TimeTable] answers, so a time
  /// is refused only for a problem some other time of the picker avoids. It
  /// takes no pick while its panel closes or where [field] takes no input.
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
      onChanged: _open != field.timeField || !_takesInput(field.timeField)
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
      focusNode: start ? _startHourNode : _endHourNode,
      hapticFeedback: true,
    );
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
                        if (on) {
                          // The time fields and an open time picker go
                          // away; the focus they held moves to the switch,
                          // not to the scope's last focused node. An open
                          // date field keeps its picker and the focus.
                          final open = _open;
                          final keepsDate = open != null && open.isDate;
                          if (open != null && !keepsDate) {
                            setState(() {
                              _open = null;
                            });
                          }
                          if (!keepsDate || _timeFieldHasFocus) {
                            _allDayNode.requestFocus();
                          }
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
  ({DateTime? first, DateTime? last}) _dayRangeOf(_TimeField row) {
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
    return row == _TimeField.start ? _startRange : _endRange;
  }

  /// [row]'s day picker, folded on the week of the row's day, that day
  /// selected and [ScheduleSection.now]'s today ringed, taking the days of
  /// [_dayRangeOf], End date's browsing back no further than the first
  /// of them. Keyed by the row's openings, so each opening of its
  /// date field builds a new one, folded, whatever the last one showed. A
  /// tap on a day moves the row's day to it; the picker takes no pick while
  /// its panel closes or swaps it out, or where the field takes no input.
  Widget _dayPicker(_TimeField row) {
    final schedule = _schedule;
    final start = row == _TimeField.start;
    final field = row.dateField;
    final range = _dayRangeOf(row);
    return CalendarDayPicker<ItemPayload>(
      key: ValueKey<int>(start ? _startDateOpenings : _endDateOpenings),
      value: start ? schedule.startDay : schedule.endDay,
      onChanged: _open != field || !_takesInput(field)
          ? null
          : (day) {
              final date = CalendarDates.dateOnly(day);
              _change(
                start ? schedule.withStartDay(date) : schedule.withEndDay(date),
              );
            },
      store: widget.store,
      today: widget.now().today,
      firstDay: range.first,
      lastDay: range.last,
      firstColumn: widget.firstColumn,
      dayBadges: widget.dayBadges,
      daysToEdges: true,
      browsesBeforeFirstDay: start,
    );
  }

  /// The Start or End row of [row], above the panel that holds the picker
  /// of the row's open field: its date field, and for a timed schedule its
  /// time field beside it, the date taking three fifths of the row; [error]
  /// shows on the time field, or for an all-day schedule on the date field.
  /// The date field and the panel keep their places in the tree whichever
  /// way All day turns, and with them the panel's state and the field's
  /// focus: a [Focus] that leaves the tree drops its focus. So does each
  /// row as the All day switch above it comes or goes: a row's outermost
  /// widget is a [Column], and the switch's row a [MergeSemantics], which
  /// the section's [Column] does not match to it.
  Widget _dateRow(_TimeField row, String? error) {
    final schedule = _schedule;
    final timed = !schedule.isAllDay;
    final start = row == _TimeField.start;
    final open = _open;
    final showsTime = open == row.timeField;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: timed ? _dateFlex : 1,
              child: _dateField(row, error: timed ? null : error),
            ),
            if (timed) ...<Widget>[
              const SizedBox(width: 12.0),
              Expanded(
                flex: _timeFlex,
                child: _timeField(
                  row,
                  label: start ? "Start time" : "End time",
                  minute: start ? schedule.startMinute : schedule.endMinute,
                  error: error,
                ),
              ),
            ],
          ],
        ),
        _PickerPanel(
          key: start ? scheduleStartPanelKey : scheduleEndPanelKey,
          open: open != null && open.row == row,
          showsTime: showsTime,
          // The time picker shows its footer, Now, only on today's field.
          revealKey: showsTime && _nowOn(_dayOf(row)) != null,
          field: _restNodeOf(showsTime ? row.timeField : row.dateField),
          dateBuilder: (context) {
            return _dayPicker(row);
          },
          timeBuilder: timed
              ? (context) {
                  return _picker(row);
                }
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    final errors = widget.errors;
    final startLocked = _startLocked;
    final allDayShows = _options.allowsAllDay || schedule.isAllDay;
    final children = <Widget>[
      if (allDayShows) _allDayRow(schedule, startLocked),
      _dateRow(_TimeField.start, errors["start"]),
      _dateRow(_TimeField.end, errors["end"]),
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

/// The form's heading: its [title], and 8 pixels after it, where the
/// schedule has a length to show, a pill with a timer icon before
/// [check]'s schedule's length: an all-day schedule's "All day" for one
/// day, or its count of civil days, such as "3 days", for more; or a timed
/// schedule's hours and minutes, where it is positive. At the heading's
/// right end lies, in a light grey rounded box, [zone]'s name, its city
/// ([CalendarZonePanel.cityOf]) or, for the device's zone,
/// [CalendarLocalizations.deviceZoneName], above the zone's offset from UTC
/// at the start ([CalendarLocalizations.utcOffset]), or at its day's start
/// where the zone's clock skips the start. The title and the pill centre on
/// the heading's height. Where the room before the box cannot hold them on
/// one line, the title wraps; where it cannot hold the pill beside its
/// gap, the pill shrinks to fit.
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

  /// The text of the pill for [schedule], null where it shows none: for a
  /// timed schedule of no length.
  static String? _lengthOf(CalendarSchedule schedule) {
    if (schedule.isAllDay) {
      final days =
          CalendarDates.daysBetween(schedule.startDay, schedule.endDay) + 1;
      return days > 1 ? "$days days" : "All day";
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

/// The notice of the entries [check]'s schedule overlaps
/// ([CalendarScheduleCheck.overlaps]), which the form shows while there are
/// any.
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
/// and then their ends. A white card, its type's edge colour down its
/// leading side, holds its type's icon, its title and its times, the
/// summaries its schema gives it ([ItemCard.summariesOf]), the time it
/// shares with the schedule, or "Covers all of this item" where that is
/// all of it, and "Not allowed" where the rules refuse its overlap; and a
/// bar that stands for the schedule's time, the part the item shares filled
/// in the item's colour. Times are written on [hourLabelFormat]'s clock, an
/// end at a day's start as the 24:00 of the day before, and a range that
/// runs past the schedule's start day with the weekday of each end. The
/// notice shows its first [shownCards] cards and a button that shows the
/// rest, which then shows fewer again.
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

  /// How many cards show before the button that shows the rest.
  static const int shownCards = 3;

  @override
  State<ScheduleOverlapNotice> createState() {
    return _ScheduleOverlapNoticeState();
  }
}

class _ScheduleOverlapNoticeState extends State<ScheduleOverlapNotice> {
  /// Whether every card shows, past [ScheduleOverlapNotice.shownCards].
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final check = widget.check;
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
    return DecoratedBox(
      key: scheduleOverlapKey,
      decoration: BoxDecoration(
        color: alert ? HarborColors.errorNotice : HarborColors.notice,
        border: Border.all(
          color: alert ? HarborColors.errorNoticeEdge : HarborColors.noticeEdge,
        ),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
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
            for (final item in shown) ...<Widget>[
              const SizedBox(height: 8.0),
              _OverlapCard(
                item: item,
                times: times,
                day: day,
                refused: refused.contains(item),
                hourLabelFormat: format,
              ),
            ],
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
  final lastDay = CalendarDates.lastDayNumberOf(start, end);
  if (CalendarDates.dayNumber(start) == day && lastDay == day) {
    return strings.entryTimes(start, end, format, isAllDay: false);
  }
  final from = strings.formatTime(CalendarDates.minuteOfDay(start), format);
  final to = strings.formatTime(CalendarDates.endMinuteOfDay(end), format);
  final lastWeekday = CalendarDates.dateOfDayNumber(lastDay).weekday;
  return "${strings.weekdayAbbreviation(start.weekday)} $from-"
      "${strings.weekdayAbbreviation(lastWeekday)} $to";
}

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
  final ({DateTime start, DateTime end})? times;

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
    final summaries = ItemCard.summariesOf(item);
    final id = item.id;
    String? shares;
    ({double from, double to})? share;
    final times = this.times;
    if (times != null) {
      final total = times.end.difference(times.start).inMicroseconds;
      final start = item.start.isAfter(times.start) ? item.start : times.start;
      final end = item.end.isBefore(times.end) ? item.end : times.end;
      if (total > 0 && end.isAfter(start)) {
        if (!item.start.isAfter(times.start) && !item.end.isBefore(times.end)) {
          shares = "Covers all of this item";
        } else {
          final range = _overlapTimes(
            start,
            end,
            day,
            strings,
            hourLabelFormat,
          );
          final minutes = end.difference(start).inMinutes;
          shares = "Shares $range, ${strings.duration(minutes)}";
        }
        share = (
          from: start.difference(times.start).inMicroseconds / total,
          to: end.difference(times.start).inMicroseconds / total,
        );
      }
    }
    final tags = <Widget>[
      if (shares != null)
        DecoratedBox(
          decoration: ShapeDecoration(
            color: refused ? HarborColors.errorNotice : HarborColors.notice,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
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
      if (refused)
        const Text(
          "Not allowed",
          style: TextStyle(
            color: HarborColors.error,
            fontSize: 12.0,
            fontWeight: FontWeight.w600,
          ),
        ),
    ];
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
              const SizedBox(width: 8.0),
              Text(
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
            ],
          ),
          if (summaries.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _indent,
                top: 2.0,
              ),
              child: Text(
                summaries.join(", "),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HarborColors.textMuted,
                  fontSize: 12.0,
                ),
              ),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _indent,
                top: 8.0,
              ),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: tags,
              ),
            ),
          if (share != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _indent,
                top: 8.0,
              ),
              child: _ShareBar(
                id: id,
                from: share.from,
                to: share.to,
                color: item.color,
              ),
            ),
        ],
      ),
    );
    return DecoratedBox(
      key: id == null ? null : scheduleOverlapCardKey(id),
      decoration: BoxDecoration(
        color: HarborColors.surface,
        border: Border.all(
          color: refused
              ? HarborColors.errorNoticeEdge
              : HarborColors.noticeEdge,
        ),
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

/// A card's bar: a track that stands for the schedule's time, filled in
/// [color] from the fraction [from] of its width to the fraction [to], the
/// part the item [id] shares. A screen reader skips it, as the card's
/// shared time states the same.
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.id,
    required this.from,
    required this.to,
    required this.color,
  });

  final String? id;
  final double from;
  final double to;
  final Color color;

  static const double _height = 4.0;

  @override
  Widget build(BuildContext context) {
    final id = this.id;
    const radius = BorderRadius.all(Radius.circular(_height / 2.0));
    return ExcludeSemantics(
      child: SizedBox(
        key: id == null ? null : scheduleOverlapBarKey(id),
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: <Widget>[
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: HarborColors.outline,
                      borderRadius: radius,
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: width * from,
                  width: width * (to - from),
                  top: 0.0,
                  bottom: 0.0,
                  child: DecoratedBox(
                    key: id == null ? null : scheduleOverlapShareKey(id),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: radius,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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

/// The panel under a Start or End row that holds the picker of the row's
/// open field: its date field's day picker, which [dateBuilder] builds, or
/// where [showsTime] its time field's picker, which [timeBuilder] builds,
/// null for an all-day row, which has no time field. Each is built only
/// while the panel shows it. The panel and its pickers span the section,
/// as the row's fields do, and the panel clips [_panelOverhang] past its
/// sides, so what a picker paints a little past them shows.
/// As [open] turns true the panel grows from no height to the picker's
/// over the [CalendarTheme]'s motion, the picker fading in over the
/// motion's first half, and as it turns false it plays
/// that backwards: it shrinks over the motion, the picker fading out over
/// its last half, the closing panel keeping the picker it showed. As
/// [showsTime] changes while [open], the panel swaps its pickers in place
/// over that motion: its height moves from the one picker's to the
/// other's, the leaving picker fading out over the motion's first half and
/// the coming one fading in over its last, and the leaving one takes no
/// pointer. All of it happens at once where the platform asks for no
/// animations ([MediaQuery.disableAnimationsOf]), a motion under way
/// included; the panel shows nothing once closed. A panel made while
/// [open], or opened once closed, shows its picker at once. A row that
/// loses its time field, as [timeBuilder] turns null, drops its time
/// picker at once.
///
/// Once it has opened, once a swap has ended while it is open, again
/// where [revealKey] changes while it is open, as the time picker's footer
/// comes or goes, and where its picker grows once it rests, it scrolls into
/// view: the open field, whose [Focus] has [field] for its node, where the
/// field lies before the visible part of the form, then the panel where it
/// lies past it, the panel winning where both do not fit. A picker that
/// grows over a motion or under a pointer, as a day picker unfolds, is
/// revealed once that motion has ended and the pointer has lifted.
class _PickerPanel extends StatefulWidget {
  const _PickerPanel({
    super.key,
    required this.open,
    required this.showsTime,
    required this.revealKey,
    required this.field,
    required this.dateBuilder,
    required this.timeBuilder,
  });

  final bool open;
  final bool showsTime;
  final Object? revealKey;
  final FocusNode field;
  final WidgetBuilder dateBuilder;
  final WidgetBuilder? timeBuilder;

  @override
  State<_PickerPanel> createState() {
    return _PickerPanelState();
  }
}

class _PickerPanelState extends State<_PickerPanel>
    with TickerProviderStateMixin {
  /// The share of the motion, from the panel's closed end, over which the
  /// picker fades.
  static const double _fadeShare = 0.5;

  late final AnimationController _controller;

  /// [_controller] on the theme's curve, which the panel's height reads.
  late final CurvedAnimation _curved;

  /// The first [_fadeShare] of [_controller] on the theme's curve, which
  /// the picker's opacity reads. [CurvedAnimation] applies a curve with no
  /// reverse curve both ways, so the opacity is one function of how far
  /// open the panel is, and a reversal mid-motion keeps it continuous.
  late final CurvedAnimation _fade;

  /// The swap of the panel's pickers, from 0 for the day picker to 1 for
  /// the time picker.
  late final AnimationController _swap;

  /// [_swap] on the theme's curve, which the panel's height reads.
  late final CurvedAnimation _swapCurved;

  /// The time picker's opacity: the last half of [_swap] on the theme's
  /// curve.
  late final CurvedAnimation _timeOpacity;

  /// The first half of [_swap] on the theme's curve, of which the day
  /// picker's opacity, [_dateOpacity], is the complement. Each opacity is
  /// one function of [_swap]'s value, so a reversal mid-swap keeps both
  /// continuous, and at most one picker is partly faded at a time.
  late final CurvedAnimation _dateFade;
  late final Animation<double> _dateOpacity;

  /// Whether the panel shows, or swaps to, its time picker.
  bool _showsTime = false;

  /// Whether the picker grew, while the panel was open with no motion of
  /// its own under way, and has not been revealed since.
  bool _grown = false;

  /// Whether the picker grew since [_revealGrowth] last looked.
  bool _growing = false;

  /// Whether [_revealGrowth] waits among the post-frame callbacks.
  bool _growthQueued = false;

  /// The pointers down on the panel's pickers.
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
    _showsTime = widget.showsTime && widget.timeBuilder != null;
    _swap = AnimationController(vsync: this, value: _showsTime ? 1.0 : 0.0)
      ..addStatusListener(_swapStatusChanged);
    // The theme's curve replaces these in didChangeDependencies, which
    // runs before the first build.
    _curved = CurvedAnimation(parent: _controller, curve: Curves.linear);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.linear);
    _swapCurved = CurvedAnimation(parent: _swap, curve: Curves.linear);
    _timeOpacity = CurvedAnimation(parent: _swap, curve: Curves.linear);
    _dateFade = CurvedAnimation(parent: _swap, curve: Curves.linear);
    _dateOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(_dateFade);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = CalendarTheme.of(context);
    final curve = theme.motionCurve;
    _curved.curve = curve;
    _fade.curve = Interval(0.0, _fadeShare, curve: curve);
    _swapCurved.curve = curve;
    _timeOpacity.curve = Interval(0.5, 1.0, curve: curve);
    _dateFade.curve = Interval(0.0, 0.5, curve: curve);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
    _retime(_controller, duration);
    _retime(_swap, duration);
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
    final hasTime = widget.timeBuilder != null;
    if (widget.open) {
      if (!oldWidget.open && _controller.isDismissed) {
        _showsTime = widget.showsTime && hasTime;
        _swap.value = _showsTime ? 1.0 : 0.0;
      } else if (widget.showsTime != _showsTime) {
        _showsTime = widget.showsTime;
        if (_showsTime) {
          _swap.forward();
        } else {
          _swap.reverse();
        }
      }
    }
    if (widget.open != oldWidget.open) {
      if (widget.open) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
    // A row that loses its time field drops its time picker in this frame,
    // and a closing panel that showed it closes at once.
    if (!hasTime && _swap.value > 0.0) {
      _showsTime = false;
      _swap.value = 0.0;
      if (!widget.open) {
        _controller.value = 0.0;
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
    _dateFade.dispose();
    _timeOpacity.dispose();
    _swapCurved.dispose();
    _swap.dispose();
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

  /// Drops the picker a swap has left once it has ended, and reveals the
  /// panel where it is open. Under a zero duration both come inside
  /// [didUpdateWidget] or [didChangeDependencies], during a build.
  void _swapStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    setState(() {});
    if (widget.open && _controller.isCompleted) {
      _revealAfterFrame();
    }
  }

  /// Scrolls the field and then the panel into view after the frame, once
  /// the panel has its height. The field can lie before the view where a
  /// panel above it has closed as this one opened.
  void _revealAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reveal();
      }
    });
  }

  void _reveal() {
    final field = widget.field.context;
    if (field != null) {
      Scrollable.ensureVisible(
        field,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
    Scrollable.ensureVisible(
      context,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  /// [_PanelSwap] laid its pickers out taller than before, with no swap
  /// under way. A growth while the panel opens needs nothing: its opening
  /// reveals it.
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
  /// it grew, as each frame of a day picker's unfold does, this asks again
  /// after the next frame, which it schedules, since no motion may be left
  /// to; a pointer down on the pickers asks again as it lifts. So a growth
  /// over many frames is revealed once, a frame after it ends, whatever
  /// other motion runs.
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
    final timeBuilder = widget.timeBuilder;
    final swap = _swap.value;
    final Widget datePicker = swap < 1.0 || !_showsTime
        ? widget.dateBuilder(context)
        : const SizedBox.shrink();
    final Widget timePicker = timeBuilder != null && (swap > 0.0 || _showsTime)
        ? timeBuilder(context)
        : const SizedBox.shrink();
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
              child: _PanelSwap(
                t: _swapCurved,
                onGrow: _grew,
                children: <Widget>[
                  IgnorePointer(
                    ignoring: _showsTime,
                    child: FadeTransition(
                      opacity: _dateOpacity,
                      child: datePicker,
                    ),
                  ),
                  IgnorePointer(
                    ignoring: !_showsTime,
                    child: FadeTransition(
                      opacity: _timeOpacity,
                      child: timePicker,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A panel's two pickers, the day picker first, laid over each other at
/// the panel's width, its height [t] of the way from the first's to the
/// second's: [t] marks it to lay out again at each tick, and neither child
/// lays out again under its unchanged constraints, so a swap rebuilds no
/// widget. It paints the first child, then the second, and hit-tests them
/// the other way round. [onGrow] is told where it lays out taller than it
/// last did while [t] rests.
class _PanelSwap extends MultiChildRenderObjectWidget {
  const _PanelSwap({
    required this.t,
    required this.onGrow,
    required super.children,
  });

  final Animation<double> t;
  final VoidCallback onGrow;

  @override
  _RenderPanelSwap createRenderObject(BuildContext context) {
    return _RenderPanelSwap(t: t, onGrow: onGrow);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderPanelSwap renderObject) {
    renderObject
      ..t = t
      ..onGrow = onGrow;
  }
}

class _PanelSwapParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPanelSwap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PanelSwapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PanelSwapParentData> {
  _RenderPanelSwap({required Animation<double> t, required VoidCallback onGrow})
    : _t = t,
      _onGrow = onGrow;

  Animation<double> _t;
  set t(Animation<double> value) {
    if (identical(value, _t)) {
      return;
    }
    if (attached) {
      _t.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _t = value;
    markNeedsLayout();
  }

  VoidCallback _onGrow;
  set onGrow(VoidCallback value) {
    _onGrow = value;
  }

  /// The height of the last layout; null before the first.
  double? _laidOutHeight;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PanelSwapParentData) {
      child.parentData = _PanelSwapParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _t.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _t.removeListener(markNeedsLayout);
    super.detach();
  }

  /// The height [t] of the way from [first] to [second].
  double _heightBetween(double first, double second) {
    return first + (second - first) * _t.value;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var width = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      width = math.max(width, child.getMinIntrinsicWidth(double.infinity));
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      width = math.max(width, child.getMaxIntrinsicWidth(double.infinity));
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final first = firstChild!;
    return _heightBetween(
      first.getMinIntrinsicHeight(width),
      childAfter(first)!.getMinIntrinsicHeight(width),
    );
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final first = firstChild!;
    return _heightBetween(
      first.getMaxIntrinsicHeight(width),
      childAfter(first)!.getMaxIntrinsicHeight(width),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    final first = firstChild!;
    return constraints.constrain(
      Size(
        constraints.maxWidth,
        _heightBetween(
          first.getDryLayout(childConstraints).height,
          childAfter(first)!.getDryLayout(childConstraints).height,
        ),
      ),
    );
  }

  @override
  void performLayout() {
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    final first = firstChild!;
    final second = childAfter(first)!;
    first.layout(childConstraints, parentUsesSize: true);
    second.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        constraints.maxWidth,
        _heightBetween(first.size.height, second.size.height),
      ),
    );
    final last = _laidOutHeight;
    _laidOutHeight = size.height;
    if (last != null && size.height > last && !_t.isAnimating) {
      _onGrow();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
