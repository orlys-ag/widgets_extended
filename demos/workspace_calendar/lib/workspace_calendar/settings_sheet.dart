/// The calendar's settings sheet: whether the weekends show, the hours the
/// calendar shows and schedules in, and the least size of the timed grid's
/// cells.
library;

import 'package:flutter/material.dart';

import 'calendar_data.dart';
import 'calendar_schema.dart';
import 'calendar_settings.dart';
import 'harbor_theme.dart';

/// The key of the sheet's weekends switch.
const ValueKey<String> weekendsSwitchKey = ValueKey<String>(
  "settings-weekends",
);

/// The key of the sheet's hours slider.
const ValueKey<String> hoursSliderKey = ValueKey<String>("settings-hours");

/// The key of the sheet's day width slider.
const ValueKey<String> dayWidthSliderKey = ValueKey<String>(
  "settings-day-width",
);

/// The key of the sheet's slot height slider.
const ValueKey<String> slotHeightSliderKey = ValueKey<String>(
  "settings-slot-height",
);

/// "08:00 - 18:00" for [hours].
String hoursLabel(DayHours hours) {
  return "${clockLabel(hours.start)} - ${clockLabel(hours.end)}";
}

/// Opens the settings sheet on [settings]. Each change applies at once
/// through [onChanged], so the calendar behind the sheet shows it while
/// the sheet is open. Completes when the sheet closes.
Future<void> showCalendarSettings(
  BuildContext context, {
  required CalendarSettings settings,
  required ValueChanged<CalendarSettings> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Light, so the calendar the changes apply to shows through.
    barrierColor: Colors.black12,
    builder: (context) {
      return CalendarSettingsSheet(settings: settings, onChanged: onChanged);
    },
  );
}

/// The sheet [showCalendarSettings] opens: a switch for the weekends, a
/// range slider for the hours, in whole hours at least one apart, and a
/// slider for each least size.
class CalendarSettingsSheet extends StatefulWidget {
  const CalendarSettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  /// The settings the sheet opens on.
  final CalendarSettings settings;

  /// Reports each change, once per new value.
  final ValueChanged<CalendarSettings> onChanged;

  @override
  State<CalendarSettingsSheet> createState() {
    return _CalendarSettingsSheetState();
  }
}

class _CalendarSettingsSheetState extends State<CalendarSettingsSheet> {
  late CalendarSettings _settings = widget.settings;

  void _set(CalendarSettings settings) {
    if (settings == _settings) {
      return;
    }
    setState(() {
      _settings = settings;
    });
    widget.onChanged(settings);
  }

  /// Whole hours from the slider's two thumbs. A pair less than an hour
  /// apart is dropped, which leaves both thumbs where they were.
  void _setHours(RangeValues values) {
    final start = values.start.round() * 60;
    final end = values.end.round() * 60;
    if (end - start < 60) {
      return;
    }
    _set(_settings.copyWith(hours: DayHours(start, end)));
  }

  @override
  Widget build(BuildContext context) {
    final hours = _settings.hours;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              "Calendar settings",
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.w600,
                color: HarborColors.text,
              ),
            ),
            const SizedBox(height: 8.0),
            SwitchListTile(
              key: weekendsSwitchKey,
              contentPadding: EdgeInsets.zero,
              title: const Text("Show weekends"),
              value: _settings.weekdays != WeekdaySet.workweek,
              onChanged: (show) {
                _set(
                  _settings.copyWith(
                    weekdays: show ? WeekdaySet.all : WeekdaySet.workweek,
                  ),
                );
              },
            ),
            const SizedBox(height: 8.0),
            _Heading(label: "Hours", value: hoursLabel(hours)),
            RangeSlider(
              key: hoursSliderKey,
              values: RangeValues(hours.start / 60, hours.end / 60),
              max: 24.0,
              divisions: 24,
              labels: RangeLabels(
                clockLabel(hours.start),
                clockLabel(hours.end),
              ),
              onChanged: _setHours,
            ),
            const _Note(
              "Items are made and moved inside these hours. One reaching "
              "past them shows cut off, and its form changes it.",
            ),
            const SizedBox(height: 16.0),
            _Heading(
              label: "Day width",
              value: "At least ${_settings.minDayWidth.round()} px",
            ),
            Slider(
              key: dayWidthSliderKey,
              value: _settings.minDayWidth,
              min: minDayWidthLow,
              max: minDayWidthHigh,
              divisions: ((minDayWidthHigh - minDayWidthLow) / 4.0).round(),
              onChanged: (value) {
                _set(_settings.copyWith(minDayWidth: value.roundToDouble()));
              },
            ),
            _Heading(
              label: "Slot height",
              value:
                  "At least ${_settings.minSlotHeight.round()} px per "
                  "$minutesPerSlot minutes",
            ),
            Slider(
              key: slotHeightSliderKey,
              value: _settings.minSlotHeight,
              min: minSlotHeightLow,
              max: minSlotHeightHigh,
              divisions: ((minSlotHeightHigh - minSlotHeightLow) / 2.0).round(),
              onChanged: (value) {
                _set(_settings.copyWith(minSlotHeight: value.roundToDouble()));
              },
            ),
            const _Note(
              "Days and slots stretch to fill the grid; larger sizes make "
              "it scroll.",
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // The value takes the width the label leaves and wraps in it, so a
    // narrow sheet does not overflow.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 15.0,
            fontWeight: FontWeight.w600,
            color: HarborColors.text,
          ),
        ),
        const SizedBox(width: 12.0),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14.0,
              color: HarborColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12.0, color: HarborColors.textMuted),
    );
  }
}
