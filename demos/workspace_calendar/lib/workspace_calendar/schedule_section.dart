/// The item form's schedule section: the part of the form any item type
/// shares, which edits a [CalendarSchedule] and shows what its
/// [CalendarScheduleCheck] answers as the user edits.
library;

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

/// The section of [check]'s schedule: a summary line; Start date, Start
/// time and End time, the start's minutes before the first a start may
/// take disabled, and on the start day only ends after the start; an End
/// date for an all-day or a multi-day schedule, or after "Ends on another
/// day"; length chips; All day; an overlap notice with "Next free time";
/// and the store's zone where it has one.
///
/// Every edit goes to [onChanged] as a new schedule. A [locked] section
/// takes no input; a [CalendarScheduleCheck.startFixed] one takes none at
/// its start or kind. [errors] holds the form's messages keyed `start` and
/// `end`.
class ScheduleSection extends StatefulWidget {
  const ScheduleSection({
    super.key,
    required this.check,
    required this.hours,
    required this.slotMinutes,
    required this.onChanged,
    this.zone,
    this.locked = false,
    this.errors = const <String, String>{},
  });

  final CalendarScheduleCheck<ItemPayload> check;

  /// The hours the time fields offer slot boundaries in.
  final CalendarDayHours hours;

  /// The step of the time fields' slot boundaries.
  final int slotMinutes;

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

class _ScheduleSectionState extends State<ScheduleSection> {
  /// Whether "Ends on another day" showed the End date of a schedule that
  /// ends on its start day.
  bool _endDayShown = false;

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

  /// A dropdown of [minutes] and [value], each enabled where [enabled]
  /// takes it.
  Widget _minuteField({
    required String label,
    required int value,
    required Iterable<int> minutes,
    required String? error,
    required ValueChanged<int>? onChanged,
    bool Function(int minute)? enabled,
  }) {
    final strings = CalendarLocalizations.of(context);
    final choices = <int>{...minutes, value}.toList()..sort();
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, errorText: error),
      items: <DropdownMenuItem<int>>[
        for (final minute in choices)
          DropdownMenuItem<int>(
            value: minute,
            enabled: enabled?.call(minute) ?? true,
            child: Text(
              strings.formatTime(
                minute,
                CalendarHourLabelFormat.twentyFourHour,
              ),
            ),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (minute) {
              if (minute != null) {
                onChanged(minute);
              }
            },
    );
  }

  /// The slot boundaries from [first] to [last] minutes.
  Iterable<int> _slots(int first, int last) sync* {
    for (var minute = first; minute <= last; minute += widget.slotMinutes) {
      yield minute;
    }
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
      CalendarHourLabelFormat.twentyFourHour,
    );
    final end = strings.formatTime(
      schedule.endMinute,
      CalendarHourLabelFormat.twentyFourHour,
    );
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
    final hours = widget.hours;
    final slot = widget.slotMinutes;
    final first = check.firstStartMinute;
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
              child: _minuteField(
                label: "Start time",
                value: schedule.startMinute,
                minutes: _slots(hours.start, hours.end - slot),
                error: errors["start"],
                enabled: first == null
                    ? null
                    : (minute) {
                        return minute >= first ||
                            minute == schedule.startMinute;
                      },
                onChanged: startLocked
                    ? null
                    : (minute) {
                        _change(schedule.withStartMinute(minute));
                      },
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: _minuteField(
                label: "End time",
                value: schedule.endMinute,
                minutes: _slots(hours.start + slot, hours.end).where((minute) {
                  return schedule.spansDays || minute > schedule.startMinute;
                }),
                error: showsEndDay ? null : errors["end"],
                onChanged: locked
                    ? null
                    : (minute) {
                        _change(schedule.withEndMinute(minute));
                      },
              ),
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
      if (timed && _options.lengthChoices.isNotEmpty)
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: <Widget>[
            for (final minutes in _options.lengthChoices)
              ChoiceChip(
                label: Text(_lengthLabel(minutes)),
                selected: schedule.lengthMinutes == minutes,
                onSelected: locked
                    ? null
                    : (on) {
                        _change(schedule.withLength(minutes));
                      },
              ),
          ],
        ),
      if (_options.allowsAllDay || schedule.isAllDay)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("All day"),
          value: schedule.isAllDay,
          onChanged: locked || startLocked
              ? null
              : (on) {
                  _change(schedule.withAllDay(on));
                },
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
