/// The zone panel: [CalendarZonePanel], an inline list from which a user
/// picks the zone a calendar's store draws on, and
/// [CalendarZoneController], the zones the user added to it.
library;

import 'dart:collection';

import 'package:flutter/material.dart';

import '../../scheduling/scheduling.dart';
import '../../sliver_tree/sliver_tree.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import 'calendar_theme_extension.dart';

/// The key of the zone panel's row of the zone named [key], or with the
/// empty key the row of the device's zone.
ValueKey<String> zonePanelRowKey(String key) {
  return ValueKey<String>("zone-row-$key");
}

/// The style the zone panel animates its rows with under [theme]: every
/// family over its [CalendarThemeData.motionDuration] on its
/// [CalendarThemeData.motionCurve], and every family off at a zero
/// duration. The one site that declares the panel's motion.
TreeAnimationStyle _zonePanelAnimationStyleOf(CalendarThemeData theme) {
  return TreeAnimationStyle.uniform(
    duration: theme.motionDuration,
    curve: theme.motionCurve,
  );
}

/// The zones a user added to a [CalendarZonePanel], one per zone name, in
/// the order added.
///
/// A host makes one, keeps it while its users keep their zones, hands it
/// to its panels, and disposes it.
final class CalendarZoneController extends ChangeNotifier {
  /// A controller holding [zones], the first zone of each name, in their
  /// order.
  CalendarZoneController({Iterable<Location> zones = const <Location>[]}) {
    for (final zone in zones) {
      _zones.putIfAbsent(zone.name, () {
        return zone;
      });
    }
    _list = List<Location>.unmodifiable(_zones.values);
  }

  /// The zones held, by name, in the order added.
  final LinkedHashMap<String, Location> _zones =
      LinkedHashMap<String, Location>();

  /// [_zones]' values, made again at each change.
  late List<Location> _list;

  /// The zones held, in the order added: an unmodifiable list, the same
  /// instance until the next change.
  List<Location> get zones {
    return _list;
  }

  /// Whether a zone named as [zone] is held.
  bool contains(Location zone) {
    return _zones.containsKey(zone.name);
  }

  /// Appends [zone] and notifies, where no zone of its name is held.
  void add(Location zone) {
    if (_zones.containsKey(zone.name)) {
      return;
    }
    _zones[zone.name] = zone;
    _list = List<Location>.unmodifiable(_zones.values);
    notifyListeners();
  }

  /// Removes the zone named as [zone] and notifies, where one is held.
  void remove(Location zone) {
    if (_zones.remove(zone.name) == null) {
      return;
    }
    _list = List<Location>.unmodifiable(_zones.values);
    notifyListeners();
  }
}

/// An inline list from which a user picks a zone, such as the one a
/// calendar's store draws on ([CalendarStore.zone]).
///
/// It shows one of two lists, switching between them at once. The first
/// shows a bar holding a button that opens the second, then a row for the
/// device's own zone and a row for each zone of [controller], in its
/// order: a tap on a row reports its zone through [onChanged], null for
/// the device's, and each zone's row ends with a button that removes it
/// from [controller]. The row of [value], or the device's row where
/// [value] is null, is marked; no row is where [controller] holds no zone
/// of [value]'s name. The second shows a back button and a search field,
/// then a row for each of [zones], or with none each zone of the loaded
/// zone database ([CalendarDates.loadedZones]), sorted by name, whose id or
/// city holds the search text, ignoring case and the text's outer spaces;
/// a row of a zone [controller] holds is marked. A tap on a row adds its
/// zone to [controller], or removes it where [controller] holds it, and
/// reports nothing through [onChanged]. A removal of the zone of [value],
/// from either list, reports null through [onChanged] after [controller]
/// notifies. The back button clears the search text and shows the first
/// list. With no zone to list, the second shows a message in place of
/// the list.
///
/// Each row shows the zone's city ([cityOf]), its id and its offset from
/// UTC at [clock]'s reading, the device's row its name and the device's
/// offset. The rows enter and leave over the calendar's motion, and the
/// panel builds and asks a zone for its offset only for the rows in view.
/// It draws in the theme a `CalendarView` beside it would: a [CalendarTheme]
/// above, or the theme of a Material [Theme] above
/// ([CalendarThemeExtension]); every word comes from
/// [CalendarLocalizations].
///
/// It fills the bounded height its parent gives. It needs a
/// [MaterialLocalizations] above it, as its [TextField] does, and builds a
/// transparent [Material] under it where none is above.
class CalendarZonePanel extends StatefulWidget {
  /// A panel marking [value] and reporting a pick through [onChanged], over
  /// the zones [controller] holds.
  const CalendarZonePanel({
    super.key,
    required this.value,
    required this.onChanged,
    required this.controller,
    this.zones,
    this.clock,
  });

  /// The zone the panel marks, null for the device's.
  final Location? value;

  /// Called with the zone of a row tapped in the first list, null for the
  /// device's, and with null after a removal of the zone of [value].
  final ValueChanged<Location?> onChanged;

  /// The zones the user added, which the first list shows and the second
  /// adds to and removes from. A new controller is listened to at once.
  final CalendarZoneController controller;

  /// The zones the second list offers, the first of each name kept; null
  /// for every zone of the loaded zone database. A list unlike the last
  /// one, by its length or by an element not [identical] in its place, is
  /// read again while the second list shows.
  final List<Location>? zones;

  /// Reads the time at which the rows show each zone's offset, once per
  /// build of the panel; null reads [DateTime.now].
  final DateTime Function()? clock;

  /// The city of [zone]: its name's last `/` segment, with each underscore
  /// a space, as "New York" of America/New_York.
  static String cityOf(Location zone) {
    final name = zone.name;
    return name.substring(name.lastIndexOf("/") + 1).replaceAll("_", " ");
  }

  @override
  State<CalendarZonePanel> createState() {
    return _CalendarZonePanelState();
  }
}

class _CalendarZonePanelState extends State<CalendarZonePanel> {
  /// Resolves the theme the panel draws in, as a [CalendarView] does.
  final CalendarThemeResolver _themes = CalendarThemeResolver();

  /// The rows' motion under [_themes]' theme.
  TreeAnimationStyle _treeStyle = _zonePanelAnimationStyleOf(
    CalendarThemeData.builtIn,
  );

  /// The search field's text.
  final TextEditingController _search = TextEditingController();

  /// Whether the second list shows.
  bool _adding = false;

  /// The first list's rows: null for the device's zone, then the
  /// controller's zones.
  late List<Location?> _userRows = _userRowsOf();

  /// While the second list shows, the zones it offers, sorted by name, and
  /// beside each its id and its city in lower case, which the search
  /// reads.
  List<Location>? _all;
  List<String> _idsLower = const <String>[];
  List<String> _citiesLower = const <String>[];

  /// While the second list shows, its rows: the zones of [_all] the search
  /// text matches, or [_all] itself for an empty text.
  List<Location>? _shown;

  /// The time the rows read their offsets at, read at each build.
  late DateTime _reading;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleZones);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTheme();
  }

  @override
  void reassemble() {
    _themes.reset();
    super.reassemble();
    _resolveTheme();
  }

  @override
  void didUpdateWidget(CalendarZonePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_handleZones);
      widget.controller.addListener(_handleZones);
      _userRows = _userRowsOf();
    }
    if (_adding && !_sameZones(widget.zones, oldWidget.zones)) {
      _readAll();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleZones);
    _search.dispose();
    super.dispose();
  }

  void _resolveTheme() {
    _themes.resolve(context);
    _treeStyle = _zonePanelAnimationStyleOf(_themes.theme);
  }

  void _handleZones() {
    setState(() {
      _userRows = _userRowsOf();
    });
  }

  List<Location?> _userRowsOf() {
    return List<Location?>.unmodifiable(<Location?>[
      null,
      ...widget.controller.zones,
    ]);
  }

  /// Whether [a] and [b] list the same zones: both null, or lists of one
  /// length whose elements in each place are [identical].
  static bool _sameZones(List<Location>? a, List<Location>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!identical(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }

  /// Reads the zones the second list offers into [_all], with their ids
  /// and cities, and filters them into [_shown].
  void _readAll() {
    final zones = widget.zones;
    final List<Location> all;
    if (zones == null) {
      all = CalendarDates.loadedZones();
    } else {
      final byName = <String, Location>{};
      for (final zone in zones) {
        byName.putIfAbsent(zone.name, () {
          return zone;
        });
      }
      final sorted = byName.values.toList()
        ..sort((a, b) {
          return a.name.compareTo(b.name);
        });
      all = List<Location>.unmodifiable(sorted);
    }
    _all = all;
    _idsLower = <String>[for (final zone in all) zone.name.toLowerCase()];
    _citiesLower = <String>[
      for (final zone in all) CalendarZonePanel.cityOf(zone).toLowerCase(),
    ];
    _shown = _filtered();
  }

  /// The zones of [_all] whose id or city holds the search text, or [_all]
  /// itself for an empty text.
  List<Location> _filtered() {
    final all = _all!;
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return all;
    }
    return List<Location>.unmodifiable(<Location>[
      for (var index = 0; index < all.length; index++)
        if (_idsLower[index].contains(query) ||
            _citiesLower[index].contains(query))
          all[index],
    ]);
  }

  void _openAdding() {
    setState(() {
      _adding = true;
      _readAll();
    });
  }

  void _closeAdding() {
    _search.clear();
    setState(() {
      _adding = false;
      _all = null;
      _idsLower = const <String>[];
      _citiesLower = const <String>[];
      _shown = null;
    });
  }

  void _handleQuery(String text) {
    setState(() {
      _shown = _filtered();
    });
  }

  /// Removes [zone] from the controller, then reports null where it was
  /// the zone the panel marks.
  void _remove(Location zone) {
    widget.controller.remove(zone);
    if (widget.value?.name == zone.name) {
      widget.onChanged(null);
    }
  }

  void _toggle(Location zone) {
    if (widget.controller.contains(zone)) {
      _remove(zone);
    } else {
      widget.controller.add(zone);
    }
  }

  @override
  Widget build(BuildContext context) {
    _reading = (widget.clock ?? DateTime.now)();
    final theme = _themes.theme;
    final strings = CalendarLocalizations.of(context);
    final Widget content;
    if (_adding) {
      content = _buildAdding(theme, strings);
    } else {
      content = _buildUsers(theme, strings);
    }
    if (_themes.hasMaterial) {
      return content;
    }
    return Material(type: MaterialType.transparency, child: content);
  }

  /// The first list: the bar with its button, the device's row and the
  /// controller's zones.
  Widget _buildUsers(CalendarThemeData theme, CalendarLocalizations strings) {
    final value = widget.value;
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            shape: const StadiumBorder(),
            backgroundColor: theme.primaryTint,
            foregroundColor: theme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
          ),
          icon: const Icon(Icons.add),
          label: Text(strings.addZonesLabel),
          onPressed: _openAdding,
        ),
      ),
    );
    final list = CustomScrollView(
      key: const ValueKey<String>("zone-panel-users"),
      slivers: <Widget>[
        SyncedSliverTree<String, Location?>.flat(
          key: const ValueKey<String>("zone-panel-users-tree"),
          items: _userRows,
          keyOf: (zone) {
            return zone?.name ?? "";
          },
          parentOf: (zone) {
            return null;
          },
          animationStyle: _treeStyle,
          itemBuilder: (context, node) {
            final zone = node.item;
            final marked = zone == null
                ? value == null
                : value != null &&
                      value.name == zone.name &&
                      widget.controller.contains(value);
            return _buildRow(
              theme,
              strings,
              zone: zone,
              marked: marked,
              checks: false,
              onTap: () {
                widget.onChanged(zone);
              },
            );
          },
        ),
      ],
    );
    return Column(
      children: <Widget>[
        _barOver(theme, bar),
        Expanded(child: list),
      ],
    );
  }

  /// The second list: the back button and the search field, then the zones
  /// the search text matches, or the message where there is no zone.
  Widget _buildAdding(CalendarThemeData theme, CalendarLocalizations strings) {
    final bar = Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: strings.zonesBackTooltip,
          color: theme.text,
          onPressed: _closeAdding,
        ),
        Expanded(
          child: TextField(
            controller: _search,
            onChanged: _handleQuery,
            cursorColor: theme.primary,
            style: TextStyle(fontSize: 16.0, color: theme.text),
            decoration: InputDecoration(
              hintText: strings.searchZonesHint,
              hintStyle: TextStyle(fontSize: 16.0, color: theme.textMuted),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
    final Widget body;
    if (_all!.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            strings.noZonesMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.0, color: theme.textSecondary),
          ),
        ),
      );
    } else {
      body = CustomScrollView(
        key: const ValueKey<String>("zone-panel-all"),
        slivers: <Widget>[
          SyncedSliverTree<String, Location>.flat(
            key: const ValueKey<String>("zone-panel-all-tree"),
            items: _shown!,
            keyOf: (zone) {
              return zone.name;
            },
            parentOf: (zone) {
              return null;
            },
            animationStyle: _treeStyle,
            itemBuilder: (context, node) {
              final zone = node.item;
              return _buildRow(
                theme,
                strings,
                zone: zone,
                marked: widget.controller.contains(zone),
                checks: true,
                onTap: () {
                  _toggle(zone);
                },
              );
            },
          ),
        ],
      );
    }
    return Column(
      children: <Widget>[
        _barOver(theme, bar),
        Expanded(child: body),
      ],
    );
  }

  /// [bar] above a line in the theme's outline.
  Widget _barOver(CalendarThemeData theme, Widget bar) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.outline)),
      ),
      child: bar,
    );
  }

  /// The row of [zone], or of the device's zone for null: its mark, its
  /// city and id, and its offset at [_reading], under one semantics node
  /// that is [marked] as selected, or as checked where [checks]; and in
  /// the first list, a zone's button that removes it.
  Widget _buildRow(
    CalendarThemeData theme,
    CalendarLocalizations strings, {
    required Location? zone,
    required bool marked,
    required bool checks,
    required VoidCallback onTap,
  }) {
    final city = zone == null
        ? strings.deviceZoneName
        : CalendarZonePanel.cityOf(zone);
    final offset = strings.utcOffset(
      CalendarDates.inZone(_reading, zone: zone).timeZoneOffset.inMinutes,
    );
    final texts = MergeSemantics(
      child: Semantics(
        selected: checks ? null : marked,
        checked: checks ? marked : null,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56.0),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                8.0,
                8.0,
                16.0,
                8.0,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 40.0,
                    child: marked
                        ? Icon(Icons.check, size: 20.0, color: theme.primary)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.0,
                            fontWeight: FontWeight.w500,
                            color: theme.text,
                          ),
                        ),
                        if (zone != null)
                          Text(
                            zone.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.0,
                              color: theme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    offset,
                    style: TextStyle(
                      fontSize: 13.0,
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Row(
      key: zonePanelRowKey(zone?.name ?? ""),
      children: <Widget>[
        Expanded(child: texts),
        if (zone != null && !checks)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: strings.removeZoneTooltip(city),
            color: theme.textSecondary,
            onPressed: () {
              _remove(zone);
            },
          ),
      ],
    );
  }
}
