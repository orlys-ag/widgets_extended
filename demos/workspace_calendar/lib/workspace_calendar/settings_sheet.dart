/// The calendar's settings sheet. Its first part, in compact rows: the zone
/// whose clock the calendar reads, picked among the device's and the zones
/// the user added, which a sheet of zones over it adds and removes; the
/// weekdays the calendar shows and the weekday a week starts on, the
/// length of the calendar's slots, and the hours it shows and schedules
/// in, with whether the timed grid labels them AM/PM. Under a divider: the
/// history lock, how Month fits its weeks, and whether items may overlap.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_settings.dart';
import 'harbor_theme.dart';

/// The key of the sheet's chips of the zones the calendar can read.
const ValueKey<String> zoneChoicesKey = ValueKey<String>("settings-zones");

/// The key of the sheet's chip of the zone named [name], or with the empty
/// name the chip of the device's zone.
ValueKey<String> zoneChipKey(String name) {
  return ValueKey<String>("settings-zone-$name");
}

/// The key of the sheet's chip that opens the sheet of zones.
const ValueKey<String> manageZonesKey = ValueKey<String>(
  "settings-manage-zones",
);

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

/// Opens the settings sheet on [settings], the calendar's [zone], null for
/// the device's, and the zones of [zones], at most nine tenths of the
/// screen's height, scrolling past it. Each change applies at once, a
/// setting through [onChanged] and a zone through [onZoneChanged], so the
/// calendar behind the sheet shows it while the sheet is open. The zones show their offsets at
/// [clock]'s reading. Completes when the sheet closes.
Future<void> showCalendarSettings(
  BuildContext context, {
  required CalendarSettings settings,
  required Location? zone,
  required CalendarZoneController zones,
  required DateTime Function() clock,
  required ValueChanged<CalendarSettings> onChanged,
  required ValueChanged<Location?> onZoneChanged,
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
        zone: zone,
        zones: zones,
        clock: clock,
        onChanged: onChanged,
        onZoneChanged: onZoneChanged,
      );
    },
  );
}

/// The sheet [showCalendarSettings] opens, in two parts a divider parts.
///
/// The first, in compact rows of a title with its control at the row's
/// end: the time zone, named with its offset from UTC, over a chip for the
/// device's zone and one for each zone of [zones], the chip of the chosen
/// zone selected, a tap on one choosing its zone, and a chip that opens
/// the sheet of zones over this one; the days, a menu of the
/// weekday a week starts on over a button for each weekday, in the week's
/// order, that shows or hides it, never hiding the last one shown; the
/// slot length, a button for each of [slotMinuteChoices], choosing through
/// [CalendarSettings.withSlotMinutes]; and the hours, a switch for AM/PM
/// hour labels over a range slider for the hours, in whole hours at least
/// one apart, with no labels over its thumbs, the hours, and to a screen
/// reader the thumbs, reading as that switch says. Its switches are three
/// quarters of their Material size.
///
/// The second: a switch for the history lock of past days and, under it,
/// one that extends the lock to earlier today, which takes input only
/// while the first is on; a segmented button for Month's layout; and last
/// a switch that lets items overlap.
///
/// The sheet of zones holds a [CalendarZonePanel] over [zones], marking the
/// chosen zone, 0.7 of the screen tall or what the keyboard leaves of it,
/// padded above the keyboard. A pick there chooses its zone and closes it;
/// a removal of the chosen zone chooses the device's and leaves it open.
class CalendarSettingsSheet extends StatefulWidget {
  const CalendarSettingsSheet({
    super.key,
    required this.settings,
    required this.zone,
    required this.zones,
    required this.clock,
    required this.onChanged,
    required this.onZoneChanged,
  });

  /// The settings the sheet opens on.
  final CalendarSettings settings;

  /// The zone the sheet opens on, the one whose clock the calendar reads;
  /// null for the device's.
  final Location? zone;

  /// The zones the user added, which the chips offer and the sheet of
  /// zones adds and removes.
  final CalendarZoneController zones;

  /// Reads the time at which the zones show their offsets.
  final DateTime Function() clock;

  /// Reports each change of the settings, once per new value.
  final ValueChanged<CalendarSettings> onChanged;

  /// Reports each change of the zone, once per new zone, null for the
  /// device's.
  final ValueChanged<Location?> onZoneChanged;

  @override
  State<CalendarSettingsSheet> createState() {
    return _CalendarSettingsSheetState();
  }
}

class _CalendarSettingsSheetState extends State<CalendarSettingsSheet> {
  late CalendarSettings _settings = widget.settings;

  /// The chosen zone, null for the device's, which the chips and the sheet
  /// of zones mark.
  late final ValueNotifier<Location?> _zone = ValueNotifier<Location?>(
    widget.zone,
  );

  @override
  void dispose() {
    _zone.dispose();
    super.dispose();
  }

  void _set(CalendarSettings settings) {
    if (settings == _settings) {
      return;
    }
    setState(() {
      _settings = settings;
    });
    widget.onChanged(settings);
  }

  /// Chooses [zone], null for the device's, where it is not the chosen one.
  void _setZone(Location? zone) {
    if (zone == _zone.value) {
      return;
    }
    setState(() {
      _zone.value = zone;
    });
    widget.onZoneChanged(zone);
  }

  /// Opens the sheet of zones over this one: the zone panel over the
  /// chosen zone, 0.7 of the screen tall, padded above the keyboard. The
  /// sheet stays below the screen's top intrusions, such as a status bar,
  /// and within the screen, so where the keyboard leaves less than that
  /// height the panel takes what is left, in which its list scrolls.
  void _openZones() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * 0.7,
            child: ValueListenableBuilder<Location?>(
              valueListenable: _zone,
              builder: (context, zone, child) {
                return CalendarZonePanel(
                  value: zone,
                  controller: widget.zones,
                  clock: widget.clock,
                  onChanged: (picked) {
                    _pickZone(sheet, picked);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// The sheet of zones' pick of [zone], null for the device's: chooses it
  /// and closes the sheet of [sheet], unless the panel reported the removal
  /// of the chosen zone, which it removes from [CalendarSettingsSheet.zones]
  /// before it reports it.
  void _pickZone(BuildContext sheet, Location? zone) {
    final current = _zone.value;
    final removed =
        zone == null && current != null && !widget.zones.contains(current);
    _setZone(zone);
    if (!removed) {
      Navigator.pop(sheet);
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

  /// The time zone part: the chosen zone and its offset over the chips.
  Widget _buildZonePart(CalendarLocalizations strings) {
    final chosen = _zone.value;
    final offset = CalendarDates.inZone(
      widget.clock(),
      zone: chosen,
    ).timeZoneOffset.inMinutes;
    final name = chosen == null
        ? _deviceChip
        : CalendarZonePanel.cityOf(chosen);
    return _Part(
      title: "Time zone",
      value: "$name, ${strings.utcOffset(offset)}",
      child: ListenableBuilder(
        listenable: widget.zones,
        builder: (context, child) {
          return Wrap(
            key: zoneChoicesKey,
            spacing: 8.0,
            runSpacing: 4.0,
            children: <Widget>[
              for (final zone in <Location?>[null, ...widget.zones.zones])
                ChoiceChip(
                  key: zoneChipKey(zone?.name ?? ""),
                  label: Text(
                    zone == null ? _deviceChip : CalendarZonePanel.cityOf(zone),
                  ),
                  selected: zone?.name == chosen?.name,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (selected) {
                    _setZone(zone);
                  },
                ),
              ActionChip(
                key: manageZonesKey,
                avatar: const Icon(Icons.edit_location_alt_outlined),
                label: const Text("Manage"),
                tooltip: "Add or remove time zones",
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: _openZones,
              ),
            ],
          );
        },
      ),
    );
  }

  /// The name of the device's zone on its chip and in the time zone part.
  static const String _deviceChip = "This device";

  /// The time zone, the days, the slot length and the hours, in compact
  /// rows.
  List<Widget> _buildCompactPart(BuildContext context) {
    final weekdays = _settings.weekdays;
    final hours = _settings.hours;
    final format = _settings.hourLabelFormat;
    final strings = CalendarLocalizations.of(context);
    return <Widget>[
      _buildZonePart(strings),
      const SizedBox(height: 8.0),
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
                label: Text("$minutes", style: const TextStyle(fontSize: 13.0)),
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

  /// The history lock, Month's layout and the overlap switch.
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

/// A heading of the sheet's second part.
class _Heading extends StatelessWidget {
  const _Heading({required this.label});

  final String label;

  /// The style of a heading's label.
  static const TextStyle labelStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.text,
  );

  @override
  Widget build(BuildContext context) {
    return Text(label, style: labelStyle);
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
