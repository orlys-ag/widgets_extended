/// The zone panel: its first list of the device's zone and the added ones,
/// its second of every zone with a search, its rows' words and offsets, the
/// rows it builds and the zones it asks, its controller, its theme, and the
/// README's sample of it beside a calendar.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:widgets_extended/calendar/composition/calendar_theme_extension.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/composition/calendar_zone_panel.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

import '../../scheduling/zones.dart';

/// Noon UTC on 2026-01-15, when America/New_York keeps standard time.
DateTime fixedClock() {
  return DateTime.utc(2026, 1, 15, 12);
}

/// [panel] in a Scaffold of an app whose calendar localizations are
/// [words], English where none is given, under [theme].
Widget host(Widget panel, {CalendarLocalizations? words, ThemeData? theme}) {
  return MaterialApp(
    theme: theme,
    localizationsDelegates: <LocalizationsDelegate<Object?>>[
      if (words != null)
        _WordsDelegate(words)
      else
        DefaultCalendarLocalizations.delegate,
    ],
    home: Scaffold(body: panel),
  );
}

/// The keys of the first list's rows, in order, null where it does not
/// show.
List<String>? userKeys(WidgetTester tester) {
  final tree = find.byType(SliverTree<String, Location?>);
  if (tree.evaluate().isEmpty) {
    return null;
  }
  return tester
      .widget<SliverTree<String, Location?>>(tree)
      .controller
      .liveRootKeys;
}

/// The keys of the second list's rows, in order, null where it does not
/// show.
List<String>? allKeys(WidgetTester tester) {
  final tree = find.byType(SliverTree<String, Location>);
  if (tree.evaluate().isEmpty) {
    return null;
  }
  return tester
      .widget<SliverTree<String, Location>>(tree)
      .controller
      .liveRootKeys;
}

/// The row of the zone named [name], or of the device's zone for "".
Finder rowOf(String name) {
  return find.byKey(zonePanelRowKey(name));
}

/// Every row mounted.
Finder get rows {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("zone-row-");
  });
}

/// The names of the rows that show a check mark.
Set<String> markedRows(WidgetTester tester) {
  return <String>{
    for (final row in rows.evaluate())
      if (find
          .descendant(
            of: find.byWidget(row.widget),
            matching: find.byIcon(Icons.check),
          )
          .evaluate()
          .isNotEmpty)
        (row.widget.key! as ValueKey<String>).value.substring(
          "zone-row-".length,
        ),
  };
}

/// Taps the panel's button that opens its second list.
Future<void> openAdding(WidgetTester tester) async {
  await tester.tap(
    find.text(const DefaultCalendarLocalizations().addZonesLabel),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    "ZP1 view 1 lists the device zone then the added zones, marks the "
    "current one, reports a tap and removes a zone by its button",
    (tester) async {
      ensureZones();
      final havana = tz.getLocation("America/Havana");
      final tokyo = tz.getLocation("Asia/Tokyo");
      final controller = CalendarZoneController(
        zones: <Location>[havana, tokyo],
      );
      addTearDown(controller.dispose);
      final changes = <Location?>[];
      Widget panel(Location? value, CalendarZoneController zones) {
        return host(
          CalendarZonePanel(
            value: value,
            onChanged: changes.add,
            controller: zones,
            clock: fixedClock,
          ),
        );
      }

      await tester.pumpWidget(panel(null, controller));
      // View 1 alone, the device row first.
      expect(allKeys(tester), isNull);
      expect(find.byType(TextField), findsNothing);
      expect(userKeys(tester), <String>["", "America/Havana", "Asia/Tokyo"]);
      final device = tester.getRect(rowOf("")).top;
      final first = tester.getRect(rowOf("America/Havana")).top;
      expect(device, lessThan(first));
      expect(first, lessThan(tester.getRect(rowOf("Asia/Tokyo")).top));
      expect(markedRows(tester), <String>{""});

      await tester.tap(find.text("Tokyo"));
      await tester.pump();
      expect(changes, <Location?>[tokyo]);

      // A remove button on each added row, none on the device's.
      expect(
        find.descendant(of: rowOf(""), matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(find.byTooltip("Remove Havana"), findsOneWidget);
      expect(find.byTooltip("Remove Tokyo"), findsOneWidget);

      await tester.tap(find.byTooltip("Remove Havana"));
      expect(controller.zones, <Location>[tokyo]);
      await tester.pump();
      expect(rowOf("America/Havana"), findsOneWidget);
      await tester.pumpAndSettle();
      expect(rowOf("America/Havana"), findsNothing);
      // The device's zone is the current one, so nothing is reported.
      expect(changes, <Location?>[tokyo]);

      await tester.pumpWidget(panel(tokyo, controller));
      expect(markedRows(tester), <String>{"Asia/Tokyo"});
      await tester.tap(find.byTooltip("Remove Tokyo"));
      await tester.pumpAndSettle();
      expect(controller.zones, isEmpty);
      expect(changes, <Location?>[tokyo, null]);

      // A value the controller does not hold marks no row.
      controller.add(tokyo);
      await tester.pumpWidget(panel(havana, controller));
      await tester.pumpAndSettle();
      expect(userKeys(tester), <String>["", "Asia/Tokyo"]);
      expect(markedRows(tester), isEmpty);

      // Another controller's zones, and none of the old one's notifies.
      final other = CalendarZoneController(zones: <Location>[havana]);
      addTearDown(other.dispose);
      await tester.pumpWidget(panel(null, other));
      await tester.pumpAndSettle();
      expect(userKeys(tester), <String>["", "America/Havana"]);
      expect(tester.binding.hasScheduledFrame, isFalse);
      controller.add(havana);
      expect(tester.binding.hasScheduledFrame, isFalse);
      other.add(tokyo);
      // Setup sanity: a notify of the controller the panel holds builds.
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(userKeys(tester), <String>["", "America/Havana", "Asia/Tokyo"]);
    },
  );

  testWidgets(
    "ZP2 the pill shows view 2, which lists every zone sorted by id, filters "
    "by city and id, and toggles a zone in and out of the added zones",
    (tester) async {
      ensureZones();
      final controller = CalendarZoneController();
      addTearDown(controller.dispose);
      final changes = <Location?>[];
      Widget panel(Location? value, {List<Location>? zones}) {
        return host(
          CalendarZonePanel(
            value: value,
            onChanged: changes.add,
            controller: controller,
            zones: zones,
            clock: fixedClock,
          ),
        );
      }

      await tester.pumpWidget(panel(null));
      await openAdding(tester);
      // View 2 alone: every zone of the database, by name, and no device
      // row.
      expect(userKeys(tester), isNull);
      expect(find.byType(TextField), findsOneWidget);
      final names = <String>[
        for (final zone in CalendarDates.loadedZones()) zone.name,
      ];
      // Setup sanity: the database is loaded, and the order expected is
      // by name.
      expect(names, hasLength(greaterThan(400)));
      expect(allKeys(tester), names);
      expect(names.toList()..sort(), names);
      expect(rowOf(""), findsNothing);

      // A search keeps the zones whose city or id holds it.
      final firstRow = names.first;
      expect(rowOf(firstRow), findsOneWidget);
      await tester.enterText(find.byType(TextField), "new y");
      await tester.pump();
      final matching = <String>[
        for (final zone in CalendarDates.loadedZones())
          if (zone.name.toLowerCase().contains("new y") ||
              CalendarZonePanel.cityOf(zone).toLowerCase().contains("new y"))
            zone.name,
      ];
      expect(matching, contains("America/New_York"));
      expect(allKeys(tester), matching);
      expect(rowOf(firstRow), findsOneWidget);
      await tester.pumpAndSettle();
      expect(rowOf(firstRow), findsNothing);

      // A tap adds the zone with a check, a second removes it, and neither
      // reports.
      final newYork = tz.getLocation("America/New_York");
      await tester.tap(find.text("New York"));
      await tester.pumpAndSettle();
      expect(controller.zones, <Location>[newYork]);
      expect(markedRows(tester), <String>{"America/New_York"});
      await tester.tap(find.text("New York"));
      await tester.pumpAndSettle();
      expect(controller.zones, isEmpty);
      expect(markedRows(tester), isEmpty);
      expect(changes, isEmpty);

      // Back shows view 1 with the zone added.
      await tester.tap(find.text("New York"));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(const DefaultCalendarLocalizations().zonesBackTooltip),
      );
      await tester.pumpAndSettle();
      expect(allKeys(tester), isNull);
      expect(find.byType(TextField), findsNothing);
      expect(userKeys(tester), <String>["", "America/New_York"]);

      // With the added zone current, a tap on its view 2 row removes it
      // and reports null.
      await tester.pumpWidget(panel(newYork));
      await openAdding(tester);
      // Setup sanity: the back button cleared the search.
      expect(allKeys(tester), names);
      await tester.enterText(find.byType(TextField), "new y");
      await tester.pumpAndSettle();
      await tester.tap(find.text("New York"));
      await tester.pumpAndSettle();
      expect(controller.zones, isEmpty);
      expect(changes, <Location?>[null]);

      // A list naming a zone twice shows one row of it.
      await tester.pumpWidget(const SizedBox());
      final havana = tz.getLocation("America/Havana");
      final tokyo = tz.getLocation("Asia/Tokyo");
      await tester.pumpWidget(
        panel(null, zones: <Location>[tokyo, havana, tokyo]),
      );
      await openAdding(tester);
      expect(allKeys(tester), <String>["America/Havana", "Asia/Tokyo"]);

      // A new list while view 2 shows a search lists its zones the search
      // matches.
      await tester.enterText(find.byType(TextField), "ha");
      await tester.pumpAndSettle();
      expect(allKeys(tester), <String>["America/Havana"]);
      await tester.pumpWidget(
        panel(
          null,
          zones: <Location>[
            havana,
            tz.getLocation("Asia/Kolkata"),
            tz.getLocation("America/Halifax"),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(allKeys(tester), <String>["America/Halifax", "America/Havana"]);
    },
  );

  testWidgets(
    "ZP3 each row shows its city, id and UTC offset, and every fixed word "
    "comes from CalendarLocalizations",
    (tester) async {
      ensureZones();
      final kolkata = tz.getLocation("Asia/Kolkata");
      final newYork = tz.getLocation("America/New_York");
      final controller = CalendarZoneController(
        zones: <Location>[kolkata, newYork],
      );
      addTearDown(controller.dispose);
      const english = DefaultCalendarLocalizations();
      Widget panel({CalendarLocalizations? words, List<Location>? zones}) {
        return host(
          CalendarZonePanel(
            value: null,
            onChanged: (zone) {},
            controller: controller,
            zones: zones,
            clock: fixedClock,
          ),
          words: words,
        );
      }

      Finder textIn(String row, String text) {
        return find.descendant(of: rowOf(row), matching: find.text(text));
      }

      await tester.pumpWidget(panel());
      expect(textIn("Asia/Kolkata", "Kolkata"), findsOneWidget);
      expect(textIn("Asia/Kolkata", "Asia/Kolkata"), findsOneWidget);
      expect(textIn("Asia/Kolkata", "UTC+05:30"), findsOneWidget);
      expect(textIn("America/New_York", "New York"), findsOneWidget);
      expect(textIn("America/New_York", "America/New_York"), findsOneWidget);
      expect(textIn("America/New_York", "UTC-05:00"), findsOneWidget);
      final deviceOffset = english.utcOffset(
        fixedClock().toLocal().timeZoneOffset.inMinutes,
      );
      expect(textIn("", "Device time zone"), findsOneWidget);
      expect(textIn("", deviceOffset), findsOneWidget);
      expect(english.utcOffset(0), "UTC+00:00");
      expect(english.utcOffset(-180), "UTC-03:00");

      // Every word from the localizations above.
      const words = _Words();
      await tester.pumpWidget(panel(words: words));
      await tester.pumpAndSettle();
      expect(textIn("", "<device>"), findsOneWidget);
      expect(
        textIn(
          "",
          "<offset ${fixedClock().toLocal().timeZoneOffset.inMinutes}>",
        ),
        findsOneWidget,
      );
      expect(textIn("Asia/Kolkata", "<offset 330>"), findsOneWidget);
      expect(textIn("America/New_York", "<offset -300>"), findsOneWidget);
      expect(find.text("<add>"), findsOneWidget);
      expect(find.byTooltip("<remove Kolkata>"), findsOneWidget);
      expect(find.byTooltip("<remove New York>"), findsOneWidget);
      await tester.tap(find.text("<add>"));
      await tester.pumpAndSettle();
      expect(find.byTooltip("<back>"), findsOneWidget);
      expect(find.text("<search>"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(panel(words: words, zones: const <Location>[]));
      await tester.tap(find.text("<add>"));
      await tester.pumpAndSettle();
      expect(find.text("<none>"), findsOneWidget);
      expect(find.text(english.noZonesMessage), findsNothing);
    },
  );

  testWidgets(
    "ZP5 each view and each keystroke build rows and ask offsets only for "
    "the rows in view",
    (tester) async {
      ensureZones();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400.0, 600.0);
      addTearDown(tester.view.reset);
      final counting = <CountingLocation>[
        for (final zone in CalendarDates.loadedZones()) CountingLocation(zone),
      ];

      /// The rows a view may mount: those its viewport and the cache
      /// extent on each side hold, plus one cut at each end.
      double boundOf() {
        final viewport = tester.getSize(find.byType(CustomScrollView)).height;
        final extent = tester.getSize(rows.first).height;
        // Setup sanity: a row is at least 56 pixels tall.
        expect(extent, greaterThanOrEqualTo(56.0));
        return (viewport + 2 * RenderAbstractViewport.defaultCacheExtent) /
                extent +
            2;
      }

      for (final zones in <List<CountingLocation>>[
        counting,
        counting.sublist(0, 60),
      ]) {
        final controller = CalendarZoneController(zones: zones);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          host(
            CalendarZonePanel(
              value: null,
              onChanged: (zone) {},
              controller: controller,
              zones: zones,
              clock: fixedClock,
            ),
          ),
        );
        // Setup sanity: the list holds more rows than its viewport.
        expect(userKeys(tester), hasLength(zones.length + 1));
        expect(rows.evaluate().length, lessThanOrEqualTo(boundOf()));
        await openAdding(tester);
        expect(allKeys(tester), hasLength(zones.length));
        expect(rows.evaluate().length, lessThanOrEqualTo(boundOf()));
        await tester.pumpWidget(const SizedBox());
      }

      // Each frame of a keystroke builds the rows the list holds in view
      // before the filter, as they leave or stay, and those it holds in view
      // after it, as they arrive or slide in: at most the rows of two lists
      // at rest, whatever the list's length. A row's build asks its zone's
      // offset once, through `CalendarDates.inZone`, so the lookups count
      // the builds, and every zone asked has its row mounted.
      for (final zones in <List<CountingLocation>>[
        counting,
        counting.sublist(0, 60),
      ]) {
        final controller = CalendarZoneController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          host(
            CalendarZonePanel(
              value: null,
              onChanged: (zone) {},
              controller: controller,
              zones: zones,
              clock: fixedClock,
            ),
          ),
        );
        await openAdding(tester);
        final bound = 2 * boundOf();
        for (final query in <String>[
          "z",
          "",
          "a",
          "am",
          "ame",
          "am",
          "a",
          "",
        ]) {
          // The first frame's count holds what the keystroke itself asks.
          var before = <int>[for (final zone in zones) zone.lookups];
          await tester.enterText(find.byType(TextField), query);
          var frames = 0;
          var built = 0;
          do {
            await tester.pump(
              frames == 0 ? Duration.zero : const Duration(milliseconds: 16),
            );
            frames += 1;
            var builds = 0;
            final asked = <String>[];
            for (var index = 0; index < zones.length; index++) {
              final lookups = zones[index].lookups - before[index];
              if (lookups > 0) {
                builds += lookups;
                asked.add(zones[index].name);
              }
            }
            before = <int>[for (final zone in zones) zone.lookups];
            final reason = "${zones.length} zones, \"$query\", frame $frames";
            expect(builds, lessThanOrEqualTo(bound), reason: reason);
            for (final name in asked) {
              expect(rowOf(name), findsOneWidget, reason: "$reason: $name");
            }
            built += builds;
          } while (tester.binding.hasScheduledFrame);
          // Setup sanity: the keystroke built rows.
          expect(built, greaterThan(0), reason: "${zones.length} \"$query\"");
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  test("ZP6 the zone controller keeps the first zone of each name in order "
      "and notifies only on a change", () {
    ensureZones();
    final tokyo = tz.getLocation("Asia/Tokyo");
    final havana = tz.getLocation("America/Havana");
    final kolkata = tz.getLocation("Asia/Kolkata");
    final otherTokyo = CountingLocation(tokyo);
    final controller = CalendarZoneController(
      zones: <Location>[tokyo, havana, otherTokyo],
    );
    addTearDown(controller.dispose);
    expect(controller.zones, hasLength(2));
    expect(identical(controller.zones[0], tokyo), isTrue);
    expect(identical(controller.zones[1], havana), isTrue);
    expect(controller.contains(otherTokyo), isTrue);
    expect(controller.contains(kolkata), isFalse);
    expect(() {
      controller.zones.add(kolkata);
    }, throwsUnsupportedError);
    var notifies = 0;
    controller.addListener(() {
      notifies++;
    });
    final held = controller.zones;
    expect(identical(controller.zones, held), isTrue);
    controller.add(otherTokyo);
    controller.remove(kolkata);
    expect(notifies, 0);
    expect(identical(controller.zones, held), isTrue);
    controller.add(kolkata);
    expect(notifies, 1);
    expect(controller.zones, <Location>[tokyo, havana, kolkata]);
    expect(identical(controller.zones, held), isFalse);
    controller.remove(otherTokyo);
    expect(notifies, 2);
    expect(controller.zones, <Location>[havana, kolkata]);
  });

  testWidgets(
    "ZP7 the panel draws in the theme a CalendarView beside it resolves",
    (tester) async {
      ensureZones();
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00897B));
      final derived = CalendarThemeExtension.fromColorScheme(scheme).data;
      // Setup sanity: the derived text colour is not the built-in one.
      expect(derived.text, isNot(CalendarThemeData.builtIn.text));
      final controller = CalendarZoneController(
        zones: <Location>[tz.getLocation("Asia/Tokyo")],
      );
      addTearDown(controller.dispose);
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        host(
          Row(
            children: <Widget>[
              SizedBox(
                width: 320.0,
                child: CalendarZonePanel(
                  value: null,
                  onChanged: (zone) {},
                  controller: controller,
                ),
              ),
              Expanded(child: CalendarView<String>(store: store)),
            ],
          ),
          theme: ThemeData(colorScheme: scheme),
        ),
      );
      await tester.pumpAndSettle();
      final city = tester.widget<Text>(
        find.descendant(of: rowOf("Asia/Tokyo"), matching: find.text("Tokyo")),
      );
      expect(city.style!.color, derived.text);
      final calendarTheme = tester.widget<CalendarTheme>(
        find
            .descendant(
              of: find.byType(CalendarView<String>),
              matching: find.byType(CalendarTheme),
            )
            .first,
      );
      expect(calendarTheme.data.text, city.style!.color);
    },
  );

  testWidgets("RS2 the README's panel sample runs and is verbatim", (
    tester,
  ) async {
    // A checkout may hold either file with CRLF line ends.
    final readme = File(
      "README.md",
    ).readAsStringSync().replaceAll("\r\n", "\n");
    final own = File(
      "test/calendar/composition/calendar_zone_panel_test.dart",
    ).readAsStringSync().replaceAll("\r\n", "\n");
    const startMark = "// README panel sample:";
    const endMark = "// End of the README panel sample.";
    final from = own.lastIndexOf(startMark) + startMark.length;
    final to = own.lastIndexOf(endMark);
    // The statements between the two marks are the README's sample, each
    // line less the indent of this test's body.
    final sample = own
        .substring(from, to)
        .split("\n")
        .map((line) {
          return line.startsWith("    ") ? line.substring(4) : line;
        })
        .join("\n")
        .trim();
    expect(
      readme.indexOf(sample),
      isNot(-1),
      reason: "The README holds the sample verbatim.",
    );
    ensureZones();

    // README panel sample:
    final zones = CalendarZoneController(
      zones: <Location>[tz.getLocation("Asia/Tokyo")],
    );
    final store = MemoryCalendarStore<String>();
    final app = MaterialApp(
      home: Scaffold(
        body: Row(
          children: <Widget>[
            SizedBox(
              width: 320.0,
              child: ListenableBuilder(
                listenable: store,
                builder: (context, child) {
                  return CalendarZonePanel(
                    value: store.zone,
                    controller: zones,
                    onChanged: (zone) {
                      store.zone = zone;
                    },
                  );
                },
              ),
            ),
            Expanded(child: CalendarView<String>(store: store)),
          ],
        ),
      ),
    );
    // End of the README panel sample.

    addTearDown(zones.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(store.zone, isNull);
    await tester.tap(find.text("Tokyo"));
    await tester.pumpAndSettle();
    expect(store.zone?.name, "Asia/Tokyo");
    expect(tester.takeException(), isNull);
    expect(find.byType(CalendarView<String>), findsOneWidget);
    expect(markedRows(tester), <String>{"Asia/Tokyo"});
  });
}

/// Every word of the zone panel marked, so a word it writes some other way
/// shows.
final class _Words extends DefaultCalendarLocalizations {
  const _Words();

  @override
  String get deviceZoneName {
    return "<device>";
  }

  @override
  String utcOffset(int minutes) {
    return "<offset $minutes>";
  }

  @override
  String get addZonesLabel {
    return "<add>";
  }

  @override
  String get searchZonesHint {
    return "<search>";
  }

  @override
  String get noZonesMessage {
    return "<none>";
  }

  @override
  String removeZoneTooltip(String city) {
    return "<remove $city>";
  }

  @override
  String get zonesBackTooltip {
    return "<back>";
  }
}

class _WordsDelegate extends LocalizationsDelegate<CalendarLocalizations> {
  const _WordsDelegate(this.words);

  final CalendarLocalizations words;

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<CalendarLocalizations> load(Locale locale) {
    return SynchronousFuture<CalendarLocalizations>(words);
  }

  @override
  bool shouldReload(_WordsDelegate old) {
    return !identical(words, old.words);
  }
}
