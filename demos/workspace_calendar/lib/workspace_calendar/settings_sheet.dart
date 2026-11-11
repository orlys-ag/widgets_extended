/// The calendar's settings sheet. Its first part, in compact rows: the edit
/// mode switch, the weekdays the calendar shows and the weekday a week
/// starts on, the length of the calendar's slots, and the hours it shows
/// and schedules in, with whether the timed grid labels them AM/PM. Under a
/// divider: the history lock, how Month fits its weeks, on the calendar's
/// controller the least width of a day in Week, Day and Month and the least
/// height of the timed grid's slots, and whether items may overlap.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_settings.dart';
import 'harbor_theme.dart';

/// The key of the sheet's edit mode switch.
const ValueKey<String> editModeKey = ValueKey<String>("settings-edit-mode");

/// The key of the sheet's menu of the weekday a week starts on.
const ValueKey<String> weekStartKey = ValueKey<String>("settings-week-start");

/// The key of the sheet's buttons of the weekdays the calendar shows.
const ValueKey<String> shownDaysKey = ValueKey<String>("settings-shown-days");

/// The key of the sheet's hours slider.
const ValueKey<String> hoursSliderKey = ValueKey<String>("settings-hours");

/// The key of the sheet's AM/PM hour labels switch.
const ValueKey<String> hourLabelFormatKey = ValueKey<String>(
  "settings-hour-label-format",
);

/// The key of the divider between the sheet's two parts.
const ValueKey<String> settingsDividerKey = ValueKey<String>(
  "settings-divider",
);

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

/// "08:00 - 18:00", or "8 AM - 6 PM", for [hours] in [format], as
/// [strings] write times.
String hoursLabel(
  CalendarDayHours hours,
  CalendarHourLabelFormat format,
  CalendarLocalizations strings,
) {
  final start = strings.formatTime(hours.start, format);
  final end = strings.formatTime(hours.end, format);
  return "$start - $end";
}

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

/// The sheet [showCalendarSettings] opens, in two parts a divider parts.
///
/// The first, in compact rows of a title with its control at the row's
/// end: a switch of edit mode; the days, a menu of the weekday a week
/// starts on over a button for each weekday, in the week's order, that
/// shows or hides it, never hiding the last one shown; the slot length,
/// a button for each of [slotMinuteChoices], choosing through
/// [CalendarSettings.withSlotMinutes]; and the hours, a switch for AM/PM
/// hour labels over a range slider for the hours, in whole hours at least
/// one apart, with no labels over its thumbs, the hours, and to a screen
/// reader the thumbs, reading as that switch says. Its switches are three
/// quarters of their Material size.
///
/// The second: a switch for the history lock of past days and, under it,
/// one that extends the lock to earlier today, which takes input only
/// while the first is on; a segmented button for Month's layout; a slider
/// for each least size of [controller]; and last a switch that lets items
/// overlap.
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

  /// Whole hours from the slider's two thumbs. A pair less than an hour
  /// apart is dropped, which leaves both thumbs where they were.
  void _setHours(RangeValues values) {
    final start = values.start.round() * 60;
    final end = values.end.round() * 60;
    if (end - start < 60) {
      return;
    }
    _set(_settings.copyWith(hours: CalendarDayHours(start, end)));
  }

  /// The style of the compact rows' buttons, which keep to their text.
  static const ButtonStyle _compactButtons = ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
  );

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
            const SizedBox(height: 8.0),
            ..._buildCompactPart(context),
            const Divider(
              key: settingsDividerKey,
              height: 32.0,
              thickness: 1.0,
              color: HarborColors.outline,
            ),
            ..._buildListPart(),
          ],
        ),
      ),
    );
  }

  /// Edit mode, the days, the slot length and the hours, in compact rows.
  List<Widget> _buildCompactPart(BuildContext context) {
    final weekdays = _settings.weekdays;
    final hours = _settings.hours;
    final format = _settings.hourLabelFormat;
    final strings = CalendarLocalizations.of(context);
    return <Widget>[
      _SwitchRow(
        switchKey: editModeKey,
        label: "Edit mode",
        value: _settings.editing,
        onChanged: (editing) {
          _set(_settings.copyWith(editing: editing));
        },
      ),
      _Part(
        title: "Days shown",
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Flexible(
              child: Text(
                "Week starts on",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _Part.labelStyle,
              ),
            ),
            _WeekStartMenu(
              firstColumn: weekdays.firstColumn,
              onSelected: (column) {
                _set(_settings.copyWith(weekdays: weekdays.startingOn(column)));
              },
            ),
          ],
        ),
        child: SegmentedButton<int>(
          key: shownDaysKey,
          expandedInsets: EdgeInsets.zero,
          multiSelectionEnabled: true,
          showSelectedIcon: false,
          style: _compactButtons,
          segments: <ButtonSegment<int>>[
            for (var offset = 0; offset < DateTime.daysPerWeek; offset++)
              ButtonSegment<int>(
                value: weekdays.columnAt(offset),
                label: Text(
                  strings.weekdayAbbreviation(weekdays.columnAt(offset) + 1),
                  style: const TextStyle(fontSize: 13.0),
                ),
              ),
          ],
          selected: weekdays.columns.toSet(),
          onSelectionChanged: (selected) {
            _set(
              _settings.copyWith(
                weekdays: CalendarWeekdaySet.of(
                  selected,
                  firstColumn: weekdays.firstColumn,
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8.0),
      _Part(
        title: "Slot length",
        child: SegmentedButton<int>(
          key: slotLengthKey,
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          style: _compactButtons,
          segments: <ButtonSegment<int>>[
            for (final minutes in CalendarDates.slotMinuteChoices)
              ButtonSegment<int>(
                value: minutes,
                label: Text(
                  "$minutes",
                  style: const TextStyle(fontSize: 13.0),
                ),
              ),
          ],
          selected: <int>{_settings.slotMinutes},
          onSelectionChanged: (selected) {
            _set(_settings.withSlotMinutes(selected.single));
          },
        ),
      ),
      const SizedBox(height: 4.0),
      const _Note(
        "Minutes per row in Week and Day, and the step of moves, "
        "resizes and new items; the hours widen to whole slots.",
      ),
      const SizedBox(height: 8.0),
      _Part(
        title: "Hours",
        value: hoursLabel(hours, format, strings),
        trailing: _LabeledSwitch(
          switchKey: hourLabelFormatKey,
          label: "AM/PM",
          value: format == CalendarHourLabelFormat.twelveHour,
          onChanged: (twelveHour) {
            _set(
              _settings.copyWith(
                hourLabelFormat: twelveHour
                    ? CalendarHourLabelFormat.twelveHour
                    : CalendarHourLabelFormat.twentyFourHour,
              ),
            );
          },
        ),
        child: RangeSlider(
          key: hoursSliderKey,
          // Vertical padding alone replaces the room the slider keeps
          // beside its track for its thumbs' overlay, so its track starts
          // half a thumb in from the sheet's edge.
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          values: RangeValues(hours.start / 60, hours.end / 60),
          max: 24.0,
          divisions: 24,
          semanticFormatterCallback: (value) {
            return strings.formatTime(value.round() * 60, format);
          },
          onChanged: _setHours,
        ),
      ),
    ];
  }

  /// The history lock, Month's layout, the least sizes and the overlap
  /// switch.
  List<Widget> _buildListPart() {
    return <Widget>[
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
                _set(_settings.copyWith(lockEarlierToday: lockEarlierToday));
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
    ];
  }
}

/// A part of the sheet's compact rows: a row of its [title], its [value]
/// when it has one, and its [trailing] control at the end when it has one,
/// over [child].
class _Part extends StatelessWidget {
  const _Part({
    required this.title,
    this.value,
    this.trailing,
    required this.child,
  });

  /// The height of a compact row.
  static const double rowHeight = 40.0;

  /// The style of a part's title.
  static const TextStyle titleStyle = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.text,
  );

  /// The style of a control's label and of a part's value, regular even
  /// where it follows a title in the same text.
  static const TextStyle labelStyle = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    color: HarborColors.textSecondary,
  );

  final String title;
  final String? value;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final trailing = this.trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: rowHeight,
          // The trailing control takes its own width, up to three fifths of
          // the row, and the title and the value the rest, each ending its
          // text where its room runs out, so a narrow sheet does not
          // overflow.
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: <Widget>[
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: title,
                        style: titleStyle,
                        children: <InlineSpan>[
                          if (value != null) ...<InlineSpan>[
                            const WidgetSpan(child: SizedBox(width: 8.0)),
                            TextSpan(text: value, style: labelStyle),
                          ],
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 8.0),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.6,
                      ),
                      child: trailing,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}

/// A switch three quarters of its Material size: it has no size of its
/// own to set, so its 52 by 40 box, with no padding and a shrink-wrapped
/// tap target, is scaled down, its layout and its taps with it.
class _SmallSwitch extends StatelessWidget {
  const _SmallSwitch({
    required this.switchKey,
    required this.value,
    required this.onChanged,
  });

  static const double _scale = 0.75;

  final Key switchKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52.0 * _scale,
      height: 40.0 * _scale,
      child: FittedBox(
        child: Switch(
          key: switchKey,
          value: value,
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// [label], a part's title, along a compact row with a small switch of
/// [value], keyed [switchKey], at its end: a screen reader hears the two
/// as one switch, and a tap anywhere on the row flips it as a tap on the
/// switch does.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        onTap: () {
          onChanged(!value);
        },
        child: SizedBox(
          height: _Part.rowHeight,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Part.titleStyle,
                ),
              ),
              _SmallSwitch(
                switchKey: switchKey,
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [label] before a small switch of [value], keyed [switchKey]: a screen
/// reader hears the two as one switch, and a tap on the label flips it as
/// a tap on the switch does.
class _LabeledSwitch extends StatelessWidget {
  const _LabeledSwitch({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(8.0),
        onTap: () {
          onChanged(!value);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Part.labelStyle,
                ),
              ),
            ),
            _SmallSwitch(
              switchKey: switchKey,
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// The weekday a week starts on, in three letters, and a menu of the
/// weekdays' names that picks another, as the calendar header's menu picks
/// a view.
class _WeekStartMenu extends StatelessWidget {
  const _WeekStartMenu({required this.firstColumn, required this.onSelected});

  /// The [CalendarDates.weekdayColumn] of the weekday a week starts on.
  final int firstColumn;

  final ValueChanged<int> onSelected;

  /// The weekdays' names, Monday first, as the menu lists them.
  static const List<String> _weekdayNames = <String>[
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      key: weekStartKey,
      tooltip: "Week starts on",
      initialValue: firstColumn,
      color: HarborColors.surface,
      onSelected: onSelected,
      itemBuilder: (context) {
        return <PopupMenuEntry<int>>[
          for (var column = 0; column < DateTime.daysPerWeek; column++)
            PopupMenuItem<int>(
              value: column,
              child: Text(_weekdayNames[column]),
            ),
        ];
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              CalendarLocalizations.of(
                context,
              ).weekdayAbbreviation(firstColumn + 1),
              style: _Part.titleStyle,
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 20.0,
              color: HarborColors.text,
            ),
          ],
        ),
      ),
    );
  }
}

/// A heading of the sheet's second part: [label], and its [value] at the
/// end of the row when it has one.
class _Heading extends StatelessWidget {
  const _Heading({required this.label, this.value});

  final String label;
  final String? value;

  /// The style of a heading's label.
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
