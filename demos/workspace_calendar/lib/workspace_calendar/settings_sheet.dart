/// The calendar's settings sheet. Its first part, in compact rows: the zone
/// whose clock the calendar reads, picked among the device's and the zones
/// the user added, which the sheet's manage mode adds and removes; the
/// weekdays the calendar shows and the weekday a week starts on, the
/// length of the calendar's slots, and the hours it shows and schedules
/// in, with whether the timed grid labels them AM/PM. Under them, whether
/// items may overlap.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
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

/// The key of the sheet's chip that turns its manage mode on and off.
const ValueKey<String> manageZonesKey = ValueKey<String>(
  "settings-manage-zones",
);

/// The key of the manage mode's back button, which shows the settings
/// again.
const ValueKey<String> zonesBackKey = ValueKey<String>("settings-zones-back");

/// The key of the manage mode's search field.
const ValueKey<String> zoneSearchKey = ValueKey<String>("settings-zone-search");

/// The key of the manage mode's list of the zones to add.
const ValueKey<String> zoneListKey = ValueKey<String>("settings-zone-list");

/// The key of the manage mode's row of the zone named [name].
ValueKey<String> zoneRowKey(String name) {
  return ValueKey<String>("settings-zone-row-$name");
}

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
/// the device's, and the zones of [zones], above the keyboard and at most
/// nine tenths of the height the keyboard and the screen's top intrusions
/// leave, scrolling past it. Each change applies at once, a
/// setting through [onChanged] and a zone through [onZoneChanged], so the
/// calendar behind the sheet shows it while the sheet is open. The zones
/// show their offsets at [clock]'s reading. Completes when the sheet
/// closes.
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

/// The sheet [showCalendarSettings] opens.
///
/// First, in compact rows of a title with its control at the row's
/// end: the time zone, named with its offset from UTC, with a Manage pill
/// at the row's end that turns the manage mode on and off, over a chip for
/// the device's zone and one for each zone of [zones], the chip of the
/// chosen zone selected, a tap on one choosing its zone; the days, a menu
/// of the weekday a week starts on over a button for each weekday, in the
/// week's order, that shows or hides it, never hiding the last one shown;
/// the slot length, a button for each of [slotMinuteChoices], choosing
/// through [CalendarSettings.withSlotMinutes]; and the hours, a switch for
/// AM/PM hour labels over a range slider for the hours, in whole hours at
/// least one apart, with no labels over its thumbs, the hours, and to a
/// screen reader the thumbs, reading as that switch says. Its switches are
/// three quarters of their Material size.
///
/// Under them, a switch that lets items overlap.
///
/// The manage mode, titled "Time zone selection" beside a back button that
/// ends it, keeps the time zone part, the Manage chip selected and each
/// chip of [zones] holding a button that removes its zone, which grows in
/// and out over Harbor's motion; a removal of the chosen zone chooses the
/// device's. In place of the settings under the
/// time zone part it shows a search field over a list of the loaded zones
/// ([CalendarDates.loadedZones]) that [zones] does not hold, sorted by
/// name, whose id or city holds the search text, ignoring case and the
/// text's outer spaces. A tap on a row adds its zone to [zones], which
/// takes the row out of the list and gives the zone a chip, and leaves
/// the mode on. The list is two fifths of the height the keyboard and the
/// screen's top intrusions leave, from two rows to 320 px tall, and
/// scrolls; its rows enter and leave over Harbor's motion, and each shows
/// its zone's city, id and offset at [clock]'s reading. The modes
/// cross-fade over Harbor's motion as the sheet's height follows.
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

  /// The zones the user added, which the chips offer and the manage mode
  /// adds and removes.
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

  /// The chosen zone, null for the device's, which the chips mark.
  late Location? _zone = widget.zone;

  /// Whether the manage mode shows.
  bool _managing = false;

  /// The manage mode's search text, and its field's focus.
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// The search field's place, which [_revealSearch] scrolls to.
  final GlobalKey _searchField = GlobalKey();

  /// The keyboard's height at the last build.
  double _keyboard = 0.0;

  /// The zones the manage mode offers, sorted by name, and beside each its
  /// id and its city in lower case, which the search reads; read when the
  /// mode first shows.
  List<Location>? _all;
  List<String> _idsLower = const <String>[];
  List<String> _citiesLower = const <String>[];

  /// The manage mode's rows: the zones of [_all] that
  /// [CalendarSettingsSheet.zones] does not hold and the search text
  /// matches.
  List<Location> _shown = const <Location>[];

  /// The motion the chips' remove buttons grow and shrink with: Harbor's
  /// duration, on the chip's own curve, which is Harbor's.
  static final ChipAnimationStyle _chipMotion = ChipAnimationStyle(
    deleteDrawerAnimation: const AnimationStyle(
      duration: harborMotionDuration,
      reverseDuration: harborMotionDuration,
    ),
  );

  /// The motion the manage mode's rows enter and leave with.
  static final TreeAnimationStyle _rowMotion = TreeAnimationStyle.uniform(
    duration: harborMotionDuration,
    curve: harborMotionCurve,
  );

  @override
  void initState() {
    super.initState();
    widget.zones.addListener(_handleZones);
  }

  @override
  void didUpdateWidget(CalendarSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.zones != oldWidget.zones) {
      oldWidget.zones.removeListener(_handleZones);
      widget.zones.addListener(_handleZones);
      _handleZones();
    }
  }

  @override
  void dispose() {
    widget.zones.removeListener(_handleZones);
    _search.dispose();
    _searchFocus.dispose();
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
    if (zone?.name == _zone?.name) {
      return;
    }
    setState(() {
      _zone = zone;
    });
    widget.onZoneChanged(zone);
  }

  /// Removes [zone] from [CalendarSettingsSheet.zones], then chooses the
  /// device's zone where [zone] was the chosen one.
  void _removeZone(Location zone) {
    widget.zones.remove(zone);
    if (_zone?.name == zone.name) {
      _setZone(null);
    }
  }

  /// Rebuilds the chips and the manage mode's rows on the zones held.
  void _handleZones() {
    setState(() {
      if (_managing) {
        _shown = _filtered();
      }
    });
  }

  void _openManaging() {
    final all = _all ?? CalendarDates.loadedZones();
    if (_all == null) {
      _all = all;
      _idsLower = <String>[for (final zone in all) zone.name.toLowerCase()];
      _citiesLower = <String>[
        for (final zone in all) CalendarZonePanel.cityOf(zone).toLowerCase(),
      ];
    }
    setState(() {
      _managing = true;
      _shown = _filtered();
    });
  }

  void _closeManaging() {
    _searchFocus.unfocus();
    _search.clear();
    setState(() {
      _managing = false;
      _shown = const <Location>[];
    });
  }

  void _handleQuery(String text) {
    setState(() {
      _shown = _filtered();
    });
  }

  void _clearQuery() {
    _search.clear();
    _handleQuery("");
  }

  /// The zones of [_all] that [CalendarSettingsSheet.zones] does not hold
  /// and whose id or city holds the search text, all of them for an empty
  /// text.
  List<Location> _filtered() {
    final all = _all ?? const <Location>[];
    final query = _search.text.trim().toLowerCase();
    return List<Location>.unmodifiable(<Location>[
      for (var index = 0; index < all.length; index++)
        if (!widget.zones.contains(all[index]) &&
            (query.isEmpty ||
                _idsLower[index].contains(query) ||
                _citiesLower[index].contains(query)))
          all[index],
    ]);
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

  /// Scrolls the search field to the top of the sheet's view, or as near
  /// it as the sheet scrolls, so the list under it fills the rest.
  void _revealSearch() {
    final field = _searchField.currentContext;
    if (!mounted || field == null) {
      return;
    }
    Scrollable.ensureVisible(field);
  }

  @override
  Widget build(BuildContext context) {
    final strings = CalendarLocalizations.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard != _keyboard) {
      _keyboard = keyboard;
      // After the layout the new keyboard brings, and after the field's
      // own reveal of its caret, which runs first.
      if (_managing && _searchFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
          _revealSearch();
        });
      }
    }
    final Widget below;
    if (_managing) {
      final listHeight = _listHeight(context);
      below = Column(
        key: const ValueKey<String>("settings-managing"),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 12.0),
          KeyedSubtree(key: _searchField, child: _buildSearch()),
          const SizedBox(height: 8.0),
          _buildZoneList(strings, listHeight),
        ],
      );
    } else {
      below = Column(
        key: const ValueKey<String>("settings-settings"),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8.0),
          ..._buildCompactPart(context),
          const SizedBox(height: 8.0),
          ..._buildOverlapPart(),
        ],
      );
    }
    // The sheet rises above the keyboard, so the search field and the list
    // under it stay in view, and with the drag handle its route draws above
    // this keeps to nine tenths of the room.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(
            0.0,
            _room(context) * 0.9 - kMinInteractiveDimension,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildTitle(),
                const SizedBox(height: 8.0),
                _buildZonePart(strings),
                _Switched(child: below),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The height the keyboard and the screen's top intrusions, such as a
  /// status bar, leave the sheet. Its route takes the top intrusions out of
  /// its [MediaQuery], so they are read from its view.
  double _room(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final top = MediaQueryData.fromView(View.of(context)).padding.top;
    return MediaQuery.sizeOf(context).height - keyboard - top;
  }

  /// The height of the manage mode's list: two fifths of the sheet's
  /// [_room], from two rows to 320 px.
  double _listHeight(BuildContext context) {
    return clampDouble(_room(context) * 0.4, 2 * _zoneRowHeight, 320.0);
  }

  /// The height of a row of the manage mode's list.
  static const double _zoneRowHeight = 56.0;

  /// The sheet's title, "Calendar settings", or in the manage mode "Time
  /// zone selection" after the back button that ends it.
  Widget _buildTitle() {
    const style = TextStyle(
      fontSize: 20.0,
      fontWeight: FontWeight.w600,
      color: HarborColors.text,
    );
    final Widget title;
    if (_managing) {
      title = Row(
        key: const ValueKey<String>("settings-title-managing"),
        children: <Widget>[
          IconButton(
            key: zonesBackKey,
            icon: const Icon(Icons.arrow_back),
            tooltip: "Back to settings",
            color: HarborColors.text,
            visualDensity: VisualDensity.compact,
            onPressed: _closeManaging,
          ),
          const SizedBox(width: 4.0),
          const Expanded(
            child: Text(
              "Time zone selection",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    } else {
      title = const Align(
        key: ValueKey<String>("settings-title-settings"),
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          "Calendar settings",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
    }
    return SizedBox(height: 40.0, child: _Switched(child: title));
  }

  /// The time zone part: the chosen zone and its offset, with the Manage
  /// pill at the row's end, over the chips.
  Widget _buildZonePart(CalendarLocalizations strings) {
    final chosen = _zone;
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
      trailing: FilterChip(
        key: manageZonesKey,
        avatar: const Icon(Icons.edit_location_alt_outlined),
        label: const Text("Manage"),
        tooltip: _managing
            ? "Done with time zones"
            : "Add or remove time zones",
        selected: _managing,
        showCheckmark: false,
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (selected) {
          if (selected) {
            _openManaging();
          } else {
            _closeManaging();
          }
        },
      ),
      child: AnimatedSize(
        duration: harborMotionDuration,
        curve: harborMotionCurve,
        alignment: Alignment.topCenter,
        child: Wrap(
          key: zoneChoicesKey,
          spacing: 8.0,
          runSpacing: 4.0,
          children: <Widget>[
            for (final zone in <Location?>[null, ...widget.zones.zones])
              _buildZoneChip(zone, chosen),
          ],
        ),
      ),
    );
  }

  /// The chip of [zone], or of the device's zone for null, selected where
  /// it is [chosen]; in the manage mode a zone's chip ends with a button
  /// that removes it.
  Widget _buildZoneChip(Location? zone, Location? chosen) {
    final name = zone == null ? _deviceChip : CalendarZonePanel.cityOf(zone);
    return InputChip(
      key: zoneChipKey(zone?.name ?? ""),
      label: Text(name),
      selected: zone?.name == chosen?.name,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (selected) {
        _setZone(zone);
      },
      deleteIcon: const Icon(Icons.close, size: 18.0),
      deleteButtonTooltipMessage: "Remove $name",
      chipAnimationStyle: _chipMotion,
      onDeleted: zone == null || !_managing
          ? null
          : () {
              _removeZone(zone);
            },
    );
  }

  /// The manage mode's search field. It reveals no more than its caret
  /// on its own, as [_revealSearch] places it as a keyboard comes.
  Widget _buildSearch() {
    return TextField(
      key: zoneSearchKey,
      controller: _search,
      focusNode: _searchFocus,
      onChanged: _handleQuery,
      textInputAction: TextInputAction.search,
      scrollPadding: EdgeInsets.zero,
      decoration: InputDecoration(
        isDense: true,
        hintText: "Search time zones",
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: "Clear search",
                onPressed: _clearQuery,
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
      ),
    );
  }

  /// The manage mode's list of [height]: a row for each of [_shown], or a
  /// message where there is none.
  Widget _buildZoneList(CalendarLocalizations strings, double height) {
    final reading = widget.clock();
    final String? message;
    if (_all!.isEmpty) {
      message = strings.noZonesMessage;
    } else if (_shown.isEmpty) {
      message = "No time zone to add matches.";
    } else {
      message = null;
    }
    const radius = BorderRadius.all(Radius.circular(12.0));
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: HarborColors.outline),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        // The rows' ink draws on this Material, so the list clips it.
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            key: zoneListKey,
            height: height,
            child: Stack(
              children: <Widget>[
                CustomScrollView(
                  slivers: <Widget>[
                    SyncedSliverTree<String, Location>.flat(
                      items: _shown,
                      keyOf: (zone) {
                        return zone.name;
                      },
                      parentOf: (zone) {
                        return null;
                      },
                      animationStyle: _rowMotion,
                      itemBuilder: (context, node) {
                        return _buildZoneRow(strings, node.item, reading);
                      },
                    ),
                  ],
                ),
                if (message != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.0,
                          color: HarborColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The row of [zone]: an add mark, its city and id, and its offset at
  /// [reading]; a tap adds the zone to [CalendarSettingsSheet.zones].
  Widget _buildZoneRow(
    CalendarLocalizations strings,
    Location zone,
    DateTime reading,
  ) {
    final city = CalendarZonePanel.cityOf(zone);
    final offset = strings.utcOffset(
      CalendarDates.inZone(reading, zone: zone).timeZoneOffset.inMinutes,
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: "Add $city",
        child: InkWell(
          key: zoneRowKey(zone.name),
          onTap: () {
            widget.zones.add(zone);
          },
          child: SizedBox(
            height: _zoneRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.add,
                    size: 20.0,
                    color: HarborColors.primary,
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.0,
                            fontWeight: FontWeight.w500,
                            color: HarborColors.text,
                          ),
                        ),
                        Text(
                          zone.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.0,
                            color: HarborColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    offset,
                    style: const TextStyle(
                      fontSize: 13.0,
                      color: HarborColors.textSecondary,
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

  /// The name of the device's zone on its chip and in the time zone part.
  static const String _deviceChip = "This device";

  /// The days, the slot length and the hours, in compact rows.
  List<Widget> _buildCompactPart(BuildContext context) {
    final weekdays = _settings.weekdays;
    final hours = _settings.hours;
    final format = _settings.hourLabelFormat;
    final strings = CalendarLocalizations.of(context);
    return <Widget>[
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

  /// The overlap switch and its note.
  List<Widget> _buildOverlapPart() {
    return <Widget>[
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

/// [child] in place of the child before it, cross-fading over Harbor's
/// motion while its height follows. The child that leaves keeps to the
/// height of the one that comes, clipped.
class _Switched extends StatelessWidget {
  const _Switched({required this.child});

  /// The child shown, keyed apart from the one it replaces.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: harborMotionDuration,
      curve: harborMotionCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: harborMotionDuration,
        switchInCurve: harborMotionCurve,
        switchOutCurve: harborMotionCurve,
        layoutBuilder: (current, previous) {
          return Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              for (final child in previous)
                Positioned(top: 0.0, left: 0.0, right: 0.0, child: child),
              ?current,
            ],
          );
        },
        child: child,
      ),
    );
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
