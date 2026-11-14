/// The item form's schedule section: the part of the form any item type
/// shares, which edits a [CalendarSchedule] and shows what its
/// [CalendarScheduleCheck] answers as the user edits.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_item.dart';
import 'harbor_theme.dart';

/// The key of the section's summary line.
const ValueKey<String> scheduleSummaryKey = ValueKey<String>(
  "schedule-summary",
);

/// The key of the section's overlap notice.
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

/// The section of [check]'s schedule: a summary line; an All day switch,
/// where the kind takes all-day or the schedule is all-day, which turned
/// off restores the times the schedule keeps; Start date; Start time and
/// End time, each a field whose tap opens the one [CalendarTimePicker], with
/// its haptic feedback on, in a panel under their row; an End date for an
/// all-day or a multi-day schedule, or after "Ends on another day"; an
/// overlap notice with "Next free time"; and the store's zone where it has
/// one. Times are written on [hourLabelFormat]'s clock.
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

  /// The clock the summary, the time fields and the pickers write times on.
  final CalendarHourLabelFormat hourLabelFormat;

  /// The current time, whose minute on [zone]'s clock the pickers' Now
  /// picks; Now shows only on a field whose day is its
  /// [CalendarNow.today].
  final ValueGetter<CalendarNow> now;

  final ValueChanged<CalendarSchedule> onChanged;

  /// The zone the times are on, which the section names; none for the
  /// device's.
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

  /// The field the panel's picker edits: the open one, kept while the panel
  /// closes; none where null.
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

  String _summary(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    final strings = CalendarLocalizations.of(context);
    final schedule = _schedule;
    final startDay = dates.formatMediumDate(schedule.startDay);
    final endDay = dates.formatMediumDate(schedule.endDay);
    if (schedule.isAllDay) {
      return schedule.spansDays
          ? "$startDay - $endDay, all day"
          : "$startDay, all day";
    }
    final start = strings.formatTime(
      schedule.startMinute,
      widget.hourLabelFormat,
    );
    final end = strings.formatTime(schedule.endMinute, widget.hourLabelFormat);
    final length = schedule.lengthMinutes > 0
        ? " (${_lengthLabel(schedule.lengthMinutes)})"
        : "";
    return schedule.spansDays
        ? "$startDay $start - $endDay $end$length"
        : "$startDay, $start - $end$length";
  }

  Widget _overlapNotice(CalendarScheduleCheck<ItemPayload> check) {
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
            if (next != null && next != check.schedule && !_startLocked)
              TextButton(
                onPressed: () {
                  _change(next);
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
    final schedule = _schedule;
    final check = widget.check;
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
    final zone = widget.zone;
    final children = <Widget>[
      Text(
        _summary(context),
        key: scheduleSummaryKey,
        style: const TextStyle(
          fontSize: 15.0,
          fontWeight: FontWeight.w600,
          color: HarborColors.text,
        ),
      ),
      if (_options.allowsAllDay || schedule.isAllDay)
        SwitchListTile(
          key: scheduleAllDayKey,
          contentPadding: EdgeInsets.zero,
          title: const Text("All day"),
          value: schedule.isAllDay,
          focusNode: _allDayNode,
          onChanged: startLocked
              ? null
              : (on) {
                  if (on) {
                    // The time row and its open picker go away; the focus
                    // their Hour column held moves to the switch, not to
                    // the scope's last focused node.
                    setState(() {
                      _open = null;
                      _shown = null;
                    });
                    _allDayNode.requestFocus();
                  }
                  _change(schedule.withAllDay(on));
                },
        ),
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
      if (timed)
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
              revealKey: shown != null && _nowOn(_dayOf(shown)) != null,
              child: shown == null ? null : _picker(shown),
            ),
          ],
        ),
      if (showsEndDay)
        _dateField(
          label: "End date",
          date: schedule.endDay,
          error: errors["end"],
          onPicked: locked
              ? null
              : (day) {
                  _change(schedule.withEndDay(day));
                },
        )
      else if (_options.spansDays && !locked)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _endDayShown = true;
              });
            },
            icon: const Icon(Icons.add),
            label: const Text("Ends on another day"),
          ),
        ),
      if (check.overlaps.isNotEmpty) _overlapNotice(check),
      if (zone != null)
        Text(
          "Times in ${zone.name}",
          style: const TextStyle(color: HarborColors.textMuted),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final child in children)
          Padding(padding: const EdgeInsets.only(bottom: 12.0), child: child),
      ],
    );
  }
}

/// The panel under the time row that holds the section's one picker,
/// [child]. As [open] turns true it grows from no height to the child's and
/// fades in, and as it turns false it shrinks and fades out, over the
/// [CalendarTheme]'s motion, or at once where the platform asks for no
/// animations ([MediaQuery.disableAnimationsOf]); it shows nothing once
/// closed or where [child] is null. A panel made while [open] shows its
/// child at once. Once it has opened, it scrolls into view where it lies
/// past the visible part of the form, and again where [revealKey] changes
/// while it is open, as the picker's footer comes or goes.
class _PickerPanel extends StatefulWidget {
  const _PickerPanel({
    super.key,
    required this.open,
    required this.revealKey,
    required this.child,
  });

  final bool open;
  final Object? revealKey;
  final Widget? child;

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
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
    _curved.curve = theme.motionCurve;
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

  /// Drops the child once the panel has closed, and reveals the panel once
  /// it has opened. Under a zero duration both come inside
  /// [didUpdateWidget], during the section's build.
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
    final child = widget.child;
    if (child == null || (!widget.open && _controller.isDismissed)) {
      return const SizedBox.shrink();
    }
    return FadeTransition(
      opacity: _curved,
      child: SizeTransition(
        sizeFactor: _curved,
        alignment: Alignment.topCenter,
        child: Padding(padding: const EdgeInsets.only(top: 12.0), child: child),
      ),
    );
  }
}
