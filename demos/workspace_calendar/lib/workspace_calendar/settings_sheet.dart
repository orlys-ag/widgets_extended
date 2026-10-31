/// The calendar's settings sheet: the history lock, how Month fits its
/// weeks, the length of the calendar's slots, on the calendar's controller
/// the least width of a day in Week, Day and Month and the least height of
/// the timed grid's slots, and whether items may overlap.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_settings.dart';
import 'harbor_theme.dart';

/// The key of the sheet's switch of the history lock of past days.
const ValueKey<String> lockPastKey = ValueKey<String>("settings-lock-past");

/// The key of the sheet's switch that extends the history lock to earlier
/// today.
const ValueKey<String> lockEarlierTodayKey = ValueKey<String>(
  "settings-lock-earlier-today",
);

/// The key of the sheet's month layout buttons.
const ValueKey<String> monthLayoutKey = ValueKey<String>(
  "settings-month-layout",
);

/// The key of the sheet's slot length buttons.
const ValueKey<String> slotLengthKey = ValueKey<String>("settings-slot-length");

/// The key of the sheet's day width slider.
const ValueKey<String> dayWidthSliderKey = ValueKey<String>(
  "settings-day-width",
);

/// The key of the sheet's slot height slider.
const ValueKey<String> slotHeightSliderKey = ValueKey<String>(
  "settings-slot-height",
);

/// The key of the sheet's switch that lets items share time.
const ValueKey<String> allowsOverlapsKey = ValueKey<String>(
  "settings-allows-overlaps",
);

/// Opens the settings sheet on [settings] and the sizes of [controller],
/// at most nine tenths of the screen's height, scrolling past it. Each
/// change applies at once, a setting through [onChanged] and a size on
/// [controller], so the calendar behind the sheet shows it while the
/// sheet is open. Completes when the sheet closes.
Future<void> showCalendarSettings(
  BuildContext context, {
  required CalendarSettings settings,
  required CalendarController controller,
  required ValueChanged<CalendarSettings> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    // Light, so the calendar the changes apply to shows through.
    barrierColor: Colors.black12,
    builder: (context) {
      return CalendarSettingsSheet(
        settings: settings,
        controller: controller,
        onChanged: onChanged,
      );
    },
  );
}

/// The sheet [showCalendarSettings] opens: a switch for the history lock of
/// past days and, under it, one that extends the lock to earlier today,
/// which takes input only while the first is on, a segmented button for
/// Month's layout, one for the slot length, offering each of
/// [slotMinuteChoices] and choosing through
/// [CalendarSettings.withSlotMinutes], a slider for each least size of
/// [controller], and last a switch that lets items overlap.
class CalendarSettingsSheet extends StatefulWidget {
  const CalendarSettingsSheet({
    super.key,
    required this.settings,
    required this.controller,
    required this.onChanged,
  });

  /// The settings the sheet opens on.
  final CalendarSettings settings;

  /// The calendar's controller, whose least day width and slot height the
  /// sliders show and set, following a pinch on a grid as well.
  final CalendarController controller;

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

  @override
  Widget build(BuildContext context) {
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
            SwitchListTile(
              key: lockPastKey,
              contentPadding: EdgeInsets.zero,
              title: const Text("Lock past days"),
              value: _settings.lockPast,
              onChanged: (lockPast) {
                _set(_settings.copyWith(lockPast: lockPast));
              },
            ),
            SwitchListTile(
              key: lockEarlierTodayKey,
              contentPadding: const EdgeInsets.only(left: 16.0),
              title: const Text("Lock earlier today too"),
              value: _settings.lockEarlierToday,
              onChanged: _settings.lockPast
                  ? (lockEarlierToday) {
                      _set(
                        _settings.copyWith(lockEarlierToday: lockEarlierToday),
                      );
                    }
                  : null,
            ),
            const _Note(
              "In edit mode, past items are not moved, resized, edited or "
              "deleted, and nothing is added in the past: before today, or "
              "with the second switch before now. An item in progress can "
              "still change its end.",
            ),
            const SizedBox(height: 16.0),
            const _Heading(label: "Month layout"),
            const SizedBox(height: 8.0),
            SegmentedButton<CalendarMonthLayout>(
              key: monthLayoutKey,
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: <ButtonSegment<CalendarMonthLayout>>[
                for (final layout in CalendarMonthLayout.values)
                  ButtonSegment<CalendarMonthLayout>(
                    value: layout,
                    label: Text(layout.label),
                  ),
              ],
              selected: <CalendarMonthLayout>{_settings.monthLayout},
              onSelectionChanged: (selected) {
                _set(_settings.copyWith(monthLayout: selected.single));
              },
            ),
            const SizedBox(height: 4.0),
            const _Note(
              "Fit to screen keeps the month on the screen; a busy day "
              "shows +N more.",
            ),
            const SizedBox(height: 16.0),
            const _Heading(label: "Slot length"),
            const SizedBox(height: 8.0),
            SegmentedButton<int>(
              key: slotLengthKey,
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: <ButtonSegment<int>>[
                for (final minutes in CalendarDates.slotMinuteChoices)
                  ButtonSegment<int>(value: minutes, label: Text("$minutes")),
              ],
              selected: <int>{_settings.slotMinutes},
              onSelectionChanged: (selected) {
                _set(_settings.withSlotMinutes(selected.single));
              },
            ),
            const SizedBox(height: 4.0),
            const _Note(
              "Minutes per row in Week and Day, and the step of moves, "
              "resizes and new items; the hours widen to whole slots.",
            ),
            const SizedBox(height: 16.0),
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, child) {
                final controller = widget.controller;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Heading(
                      label: "Day width",
                      value: "At least ${controller.minDayWidth.round()} px",
                    ),
                    Slider(
                      key: dayWidthSliderKey,
                      value: controller.minDayWidth,
                      min: CalendarController.minDayWidthLow,
                      max: CalendarController.minDayWidthHigh,
                      divisions:
                          ((CalendarController.minDayWidthHigh -
                                      CalendarController.minDayWidthLow) /
                                  4.0)
                              .round(),
                      onChanged: (value) {
                        controller.minDayWidth = value.roundToDouble();
                      },
                    ),
                    _Heading(
                      label: "Slot height",
                      value:
                          "At least ${controller.minSlotHeight.round()} px "
                          "per ${_settings.slotMinutes} minutes",
                    ),
                    Slider(
                      key: slotHeightSliderKey,
                      value: controller.minSlotHeight,
                      min: CalendarController.minSlotHeightLow,
                      max: CalendarController.minSlotHeightHigh,
                      divisions:
                          ((CalendarController.minSlotHeightHigh -
                                      CalendarController.minSlotHeightLow) /
                                  2.0)
                              .round(),
                      onChanged: (value) {
                        controller.minSlotHeight = value.roundToDouble();
                      },
                    ),
                  ],
                );
              },
            ),
            const _Note(
              "Days and slots stretch to fill the grid; larger sizes make "
              "it scroll. A pinch on a grid sets them too.",
            ),
            const SizedBox(height: 16.0),
            SwitchListTile(
              key: allowsOverlapsKey,
              contentPadding: EdgeInsets.zero,
              title: const Text("Allow overlapping items"),
              value: _settings.allowsOverlaps,
              onChanged: (allowsOverlaps) {
                _set(_settings.copyWith(allowsOverlaps: allowsOverlaps));
              },
            ),
            const _Note(
              "In edit mode, items can be moved, resized and added over "
              "other items' times, and show side by side. Off, they keep "
              "to free time.",
            ),
          ],
        ),
      ),
    );
  }
}

/// A section's [label], and its [value] at the end of the row when it has
/// one.
class _Heading extends StatelessWidget {
  const _Heading({required this.label, this.value});

  final String label;
  final String? value;

  /// The style of a section's label.
  static const TextStyle labelStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    // The value takes the width the label leaves and wraps in it, so a
    // narrow sheet does not overflow.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: labelStyle),
        if (value != null) ...<Widget>[
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
