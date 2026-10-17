/// The calendar bar the app bar's chevron opens: Today and the edit mode
/// switch, then the weekdays the calendar shows and the weekday a week
/// starts on, then the hours it shows and schedules in and whether the
/// timed grid labels them AM/PM.
library;

import 'package:flutter/material.dart';

import 'calendar_data.dart';
import 'calendar_settings.dart';
import 'harbor_theme.dart';

/// The key of the bar's edit mode switch.
const ValueKey<String> editModeKey = ValueKey<String>("bar-edit-mode");

/// The key of the bar's menu of the weekday a week starts on.
const ValueKey<String> weekStartKey = ValueKey<String>("bar-week-start");

/// The key of the bar's buttons of the weekdays the calendar shows.
const ValueKey<String> shownDaysKey = ValueKey<String>("bar-shown-days");

/// The key of the bar's hours slider.
const ValueKey<String> hoursSliderKey = ValueKey<String>("bar-hours");

/// The key of the bar's AM/PM hour labels switch.
const ValueKey<String> hourLabelFormatKey = ValueKey<String>(
  "bar-hour-label-format",
);

/// "08:00 - 18:00" for [hours].
String hoursLabel(DayHours hours) {
  return "${clockLabel(hours.start)} - ${clockLabel(hours.end)}";
}

/// The calendar bar on [settings], in three parts: Today, which reports
/// [onToday], beside a switch of edit mode; the days, a menu of the
/// weekday a week starts on over a button for each weekday, in the
/// week's order, that shows or hides it, never hiding the last one shown;
/// and the hours, a switch for AM/PM hour labels over a range slider for
/// the hours, in whole hours at least one apart. Each change reports the
/// new settings through [onChanged].
class CalendarBar extends StatelessWidget {
  const CalendarBar({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onToday,
  });

  final CalendarSettings settings;

  /// Reports each change, once per new value.
  final ValueChanged<CalendarSettings> onChanged;

  final VoidCallback onToday;

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

  /// The space between the bar's edges and its content.
  static const double gutter = 16.0;

  void _set(CalendarSettings next) {
    if (next != settings) {
      onChanged(next);
    }
  }

  /// Whole hours from the slider's two thumbs. A pair less than an hour
  /// apart is dropped, which leaves both thumbs where they were.
  void _setHours(RangeValues values) {
    final start = values.start.round() * 60;
    final end = values.end.round() * 60;
    if (end - start < 60) {
      return;
    }
    _set(settings.copyWith(hours: DayHours(start, end)));
  }

  @override
  Widget build(BuildContext context) {
    final weekdays = settings.weekdays;
    final hours = settings.hours;
    // A Material rather than a decoration, so the ink of the labels'
    // taps shows on the bar.
    return Material(
      color: HarborColors.surface,
      shape: const Border(bottom: BorderSide(color: HarborColors.outline)),
      child: Padding(
        padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              // Today's own padding takes its text to the gutter.
              padding: const EdgeInsetsDirectional.only(
                start: gutter - _todayPadding,
                end: gutter,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _todayPadding,
                      ),
                      minimumSize: const Size(48.0, 36.0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    onPressed: onToday,
                    child: const Text("Today"),
                  ),
                  Flexible(
                    child: _LabeledSwitch(
                      switchKey: editModeKey,
                      label: "Edit mode",
                      value: settings.editing,
                      onChanged: (editing) {
                        _set(settings.copyWith(editing: editing));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 9.0,
              thickness: 1.0,
              indent: gutter,
              endIndent: gutter,
              color: HarborColors.outline,
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
                      style: labelStyle,
                    ),
                  ),
                  _WeekStartMenu(
                    firstColumn: weekdays.firstColumn,
                    onSelected: (column) {
                      _set(
                        settings.copyWith(
                          weekdays: weekdays.startingOn(column),
                        ),
                      );
                    },
                  ),
                ],
              ),
              child: SegmentedButton<int>(
                key: shownDaysKey,
                expandedInsets: EdgeInsets.zero,
                multiSelectionEnabled: true,
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                    EdgeInsets.zero,
                  ),
                ),
                segments: <ButtonSegment<int>>[
                  for (var offset = 0; offset < DateTime.daysPerWeek; offset++)
                    ButtonSegment<int>(
                      value: weekdays.columnAt(offset),
                      label: Text(
                        weekdayAbbreviations[weekdays.columnAt(offset)],
                        style: const TextStyle(fontSize: 13.0),
                      ),
                    ),
                ],
                selected: weekdays.columns.toSet(),
                onSelectionChanged: (selected) {
                  _set(
                    settings.copyWith(
                      weekdays: WeekdaySet.of(
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
              title: "Hours",
              value: hoursLabel(hours),
              trailing: _LabeledSwitch(
                switchKey: hourLabelFormatKey,
                label: "AM/PM",
                value: settings.hourLabelFormat == HourLabelFormat.twelveHour,
                onChanged: (twelveHour) {
                  _set(
                    settings.copyWith(
                      hourLabelFormat: twelveHour
                          ? HourLabelFormat.twelveHour
                          : HourLabelFormat.twentyFourHour,
                    ),
                  );
                },
              ),
              child: RangeSlider(
                key: hoursSliderKey,
                // Vertical padding alone replaces the room the slider keeps
                // beside its track for its thumbs' overlay, so its track
                // starts half a thumb in from the gutter.
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                values: RangeValues(hours.start / 60, hours.end / 60),
                max: 24.0,
                divisions: 24,
                labels: RangeLabels(
                  clockLabel(hours.start),
                  clockLabel(hours.end),
                ),
                onChanged: _setHours,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The horizontal padding of Today, which its text sits inside.
  static const double _todayPadding = 12.0;
}

/// A part of the [CalendarBar]: a row of its [title], its [value] when it
/// has one, and its [trailing] control at the end, over [child].
class _Part extends StatelessWidget {
  const _Part({
    required this.title,
    this.value,
    required this.trailing,
    required this.child,
  });

  final String title;
  final String? value;
  final Widget trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CalendarBar.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 40.0,
            // The trailing control takes its own width, up to three fifths
            // of the row, and the title and the value the rest, each
            // ending its text where its room runs out, so a narrow bar
            // does not overflow.
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: <Widget>[
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: title,
                          style: CalendarBar.titleStyle,
                          children: <InlineSpan>[
                            if (value != null) ...<InlineSpan>[
                              const WidgetSpan(child: SizedBox(width: 8.0)),
                              TextSpan(
                                text: value,
                                style: CalendarBar.labelStyle,
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.6,
                      ),
                      child: trailing,
                    ),
                  ],
                );
              },
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// [label] before a switch of [value], keyed [switchKey]: a screen reader
/// hears the two as one switch, and a tap on the label flips it as a tap
/// on the switch does.
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
                  style: CalendarBar.labelStyle,
                ),
              ),
            ),
            Switch(
              key: switchKey,
              value: value,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

  /// The [weekdayColumn] of the weekday a week starts on.
  final int firstColumn;

  final ValueChanged<int> onSelected;

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
              child: Text(weekdayNames[column]),
            ),
        ];
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              weekdayAbbreviations[firstColumn],
              style: CalendarBar.titleStyle,
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
