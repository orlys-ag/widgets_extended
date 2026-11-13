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

/// The key of the start's picker, open under the time row.
const ValueKey<String> scheduleStartPickerKey = ValueKey<String>(
  "schedule-start-picker",
);

/// The key of the end's picker, open under the time row.
const ValueKey<String> scheduleEndPickerKey = ValueKey<String>(
  "schedule-end-picker",
);

/// The section of [check]'s schedule: a summary line; Start date; Start
/// time and End time, each a field whose tap opens a [CalendarTimePicker]
/// under their row, one at a time, the start's times before the first a
/// start may take refused, on the start day only ends after the start
/// offered, and every time [zone]'s clock skips refused; an End date for
/// an all-day or a multi-day schedule, or after "Ends on another day"; a
/// row of length chips and, after them, All day, where a length makes an
/// all-day schedule timed at that length; an overlap notice with "Next
/// free time"; and the store's zone where it has one. Times are written
/// on [hourLabelFormat]'s clock.
///
/// Every edit goes to [onChanged] as a new schedule. A [locked] section
/// takes no input; a [CalendarScheduleCheck.startFixed] one takes none at
/// its start or kind. An open picker stays open as its field locks, taking
/// no pick, until its field's tap or All day closes it. [errors] holds the
/// form's messages keyed `start` and `end`.
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
  /// picks.
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

class _ScheduleSectionState extends State<ScheduleSection> {
  /// Whether "Ends on another day" showed the End date of a schedule that
  /// ends on its start day.
  bool _endDayShown = false;

  /// The field whose picker is open; none where null.
  _TimeField? _open;

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

  final FocusNode _startHourNode = FocusNode(debugLabel: "Start Hour column");
  final FocusNode _endHourNode = FocusNode(debugLabel: "End Hour column");
  final FocusNode _allDayNode = FocusNode(debugLabel: "All day");

  @override
  void didUpdateWidget(ScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_schedule.isAllDay) {
      _open = null;
    }
  }

  @override
  void dispose() {
    _startFieldNode.dispose();
    _endFieldNode.dispose();
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

  /// Opens [field]'s picker, closing the other's, or closes it where it is
  /// open. A picker closed while a column moves drops that motion's pick:
  /// disposing the picker cancels the motion's [TickerFuture], so the time
  /// it would come to rest on is never reported.
  void _tapTimeField(_TimeField field) {
    final start = field == _TimeField.start;
    if (_open == field) {
      setState(() {
        _open = null;
      });
      // Made before the next frame, so the picker's Hour column no longer
      // holds the focus as it leaves the tree.
      if (_takesInput(field)) {
        (start ? _startFieldNode : _endFieldNode).requestFocus();
      } else {
        (start ? _startRestNode : _endRestNode).requestFocus();
      }
      return;
    }
    setState(() {
      _open = field;
    });
    // The request waits for the new picker's Hour column to join the tree,
    // and so wins over the focus the other picker's column drops as it
    // leaves.
    (start ? _startHourNode : _endHourNode).requestFocus();
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

  /// The start's picker: the hours' times a start may take, each refused
  /// before the first start the check allows, other than the start itself,
  /// and where the schedule's own reading of it finds the clock skips it.
  Widget _startPicker(CalendarSchedule schedule) {
    final hours = widget.hours;
    final slot = widget.slotMinutes;
    final first = widget.check.firstStartMinute;
    final zone = widget.zone;
    return CalendarTimePicker(
      value: schedule.startMinute,
      onChanged: _startLocked
          ? null
          : (minute) {
              if (minute != null) {
                _change(schedule.withStartMinute(minute));
              }
            },
      hourLabelFormat: widget.hourLabelFormat,
      minuteStep: slot,
      min: hours.start,
      max: math.max(hours.start, hours.end - slot),
      isEnabled: (minute) {
        return (first == null ||
                minute >= first ||
                minute == schedule.startMinute) &&
            !schedule.withStartMinute(minute).startSkippedOn(zone);
      },
      now: _nowMinute,
      focusNode: _startHourNode,
    );
  }

  /// The end's picker: the hours' ends, on the start's day only those after
  /// the start, each refused where the schedule's own reading of it finds
  /// the clock skips it. An end on its start's day whose start leaves no
  /// such end in the hours has a row for its own time alone.
  Widget _endPicker(CalendarSchedule schedule) {
    final hours = widget.hours;
    final slot = widget.slotMinutes;
    final zone = widget.zone;
    final spans = schedule.spansDays;
    var min = hours.start + slot;
    var max = hours.end;
    if (!spans) {
      min = math.max(min, schedule.startMinute + 1);
    }
    if (min > max) {
      min = schedule.endMinute;
      max = schedule.endMinute;
    }
    return CalendarTimePicker(
      value: schedule.endMinute,
      onChanged: widget.locked
          ? null
          : (minute) {
              if (minute != null) {
                _change(schedule.withEndMinute(minute));
              }
            },
      hourLabelFormat: widget.hourLabelFormat,
      minuteStep: slot,
      min: min,
      max: max,
      isEnabled: (minute) {
        return (spans || minute > schedule.startMinute) &&
            !schedule.withEndMinute(minute).endSkippedOn(zone);
      },
      now: _nowMinute,
      focusNode: _endHourNode,
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
    final timed = !schedule.isAllDay;
    final offersAllDay = _options.allowsAllDay || schedule.isAllDay;
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
      if (open != null)
        _RevealedPicker(
          key: open == _TimeField.start
              ? scheduleStartPickerKey
              : scheduleEndPickerKey,
          child: open == _TimeField.start
              ? _startPicker(schedule)
              : _endPicker(schedule),
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
      if (_options.lengthChoices.isNotEmpty || offersAllDay)
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: <Widget>[
            for (final minutes in _options.lengthChoices)
              ChoiceChip(
                label: Text(_lengthLabel(minutes)),
                selected: timed && schedule.lengthMinutes == minutes,
                // Of an all-day schedule a length changes the kind, which a
                // fixed start keeps.
                onSelected: locked || (!timed && startLocked)
                    ? null
                    : (on) {
                        _change(schedule.withAllDay(false).withLength(minutes));
                      },
              ),
            if (offersAllDay)
              ChoiceChip(
                focusNode: _allDayNode,
                label: const Text("All day"),
                selected: schedule.isAllDay,
                onSelected: startLocked
                    ? null
                    : (on) {
                        // The time row and its open picker go away; the
                        // focus their Hour column held moves to the chip,
                        // not to the scope's last focused node.
                        if (on && _open != null) {
                          setState(() {
                            _open = null;
                          });
                          _allDayNode.requestFocus();
                        }
                        _change(schedule.withAllDay(on));
                      },
              ),
          ],
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

/// [child], an open picker, which the frame it first shows in scrolls
/// into view where it lies past the visible part of the form.
class _RevealedPicker extends StatefulWidget {
  const _RevealedPicker({super.key, required this.child});

  final Widget child;

  @override
  State<_RevealedPicker> createState() {
    return _RevealedPickerState();
  }
}

class _RevealedPickerState extends State<_RevealedPicker> {
  @override
  void initState() {
    super.initState();
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
    return widget.child;
  }
}
