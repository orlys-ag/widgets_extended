/// The calendar on a zone: the settings sheet's time zone part and its
/// manage mode, the item form's times and the store's hours on the store's
/// zone clock, and the history lock judged on it.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';

import 'calendar_harness.dart';

/// Noon of [today] on the device's clock, the instant the zones far from
/// the device are chosen at.
final DateTime noon = DateTime(2026, 4, 21, 12);

DateTime noonClock() {
  return noon;
}

/// A size tall enough that a grid shows many hours at once.
const Size tall = Size(390.0, 1400.0);

/// The `Etc/GMT` zone of [offset] whole hours east of UTC.
tz.Location _gmtZone(int offset) {
  if (offset == 0) {
    return tz.getLocation("Etc/GMT");
  }
  // The names' signs are POSIX's: Etc/GMT-3 lies three hours east.
  return tz.getLocation(offset > 0 ? "Etc/GMT-$offset" : "Etc/GMT+${-offset}");
}

/// An `Etc/GMT` zone 12 or more hours from the device's offset at [on],
/// reading another civil day than the device does at [on].
tz.Location _zoneFarFromDevice(DateTime on) {
  final device = on.timeZoneOffset.inHours;
  final deviceDay = CalendarDates.dayNumber(on);
  for (var offset = 14; offset >= -12; offset--) {
    if ((offset - device).abs() < 12) {
      continue;
    }
    final zone = _gmtZone(offset);
    if (CalendarDates.dayNumber(tz.TZDateTime.from(on, zone)) != deviceDay) {
      return zone;
    }
  }
  throw StateError("No Etc/GMT zone is 12 hours from the device at $on");
}

/// A zone of one offset, the device's at [on] plus [hours].
tz.Location _zoneApartFromDevice(DateTime on, int hours) {
  final name = "Test/Apart$hours";
  return tz.Location(name, <int>[tz.minTime], <int>[0], <tz.TimeZone>[
    tz.TimeZone(
      on.timeZoneOffset + Duration(hours: hours),
      isDst: false,
      abbreviation: name,
    ),
  ]);
}

/// The calendar's store.
CalendarStore<ItemPayload> storeOf(WidgetTester tester) {
  return tester
      .widget<CalendarView<ItemPayload>>(find.byType(CalendarView<ItemPayload>))
      .store;
}

/// Sets the store's zone to [zone] and lets the reads it sends answer.
Future<void> zoneStore(
  WidgetTester tester,
  MockCalendarApi api,
  Location? zone,
) async {
  storeOf(tester).zone = zone;
  await tester.pump();
  await tester.pump(api.latency);
  await tester.pumpAndSettle();
}

/// Opens the settings sheet where it is closed, then its manage mode from
/// its Manage chip.
Future<void> openManaging(WidgetTester tester) async {
  await openSettings(tester);
  await tester.tap(find.byKey(manageZonesKey));
  await tester.pumpAndSettle();
}

/// Types [text] in the manage mode's search field.
Future<void> searchZones(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(zoneSearchKey), text);
  await tester.pumpAndSettle();
}

/// Adds the zone named [name] with a tap on its row in the manage mode's
/// list, searched for by [query] so the row shows.
Future<void> addZone(WidgetTester tester, String query, String name) async {
  await searchZones(tester, query);
  await tester.tap(find.byKey(zoneRowKey(name)));
  await tester.pumpAndSettle();
}

/// The sheet's chip of the zone named [name], or with the empty name the
/// chip of the device's zone.
Finder zoneChip(String name) {
  return find.byKey(zoneChipKey(name));
}

/// The names of the zones the manage mode's list holds, in its order.
List<String> listedZones(WidgetTester tester) {
  return tester
      .widget<SliverTree<String, Location>>(
        find.descendant(
          of: find.byKey(zoneListKey),
          matching: find.byType(SliverTree<String, Location>),
        ),
      )
      .controller
      .liveRootKeys;
}

/// Scrolls the grid so the slot row of [minute] shows near its top.
Future<void> showMinute(WidgetTester tester, int minute) async {
  final vertical = gridViewport(tester).verticalPosition!;
  final slot = cellRect(tester, rowOf(minute), colOf(1)).height;
  vertical.jumpTo(
    math.min(
      vertical.maxScrollExtent,
      math.max(0.0, slot * (rowOf(minute) - 4)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps Tuesday's slot of [minute] in Week and picks Task in the create
/// flow, which opens the form of a new Task.
Future<void> createTaskAt(WidgetTester tester, int minute) async {
  await showMinute(tester, minute);
  await tester.tapAt(cellRect(tester, rowOf(minute), colOf(1)).center);
  await tester.pumpAndSettle();
  expect(find.text("New item"), findsOneWidget);
  await tester.tap(find.text("Task").last);
  await tester.pumpAndSettle();
  expect(find.text("New item"), findsOneWidget);
}

/// Creates "Zoned" through the form at 09:00 on Tuesday of Week, over a
/// store on [zone], and returns its id and the mock.
Future<({String id, MockCalendarApi api})> createAtNine(
  WidgetTester tester,
  tz.Location zone,
) async {
  final api = await pumpCalendar(
    tester,
    api: MockCalendarApi(latency: harnessLatency),
    editing: true,
    clock: noonClock,
    size: tall,
  );
  await zoneStore(tester, api, zone);
  await pickMode(tester, "Week");
  await createTaskAt(tester, 9 * 60);
  expect(
    find.descendant(
      of: dropdownFinder("Start time"),
      matching: find.text("09:00"),
    ),
    findsOneWidget,
  );
  await tester.enterText(find.widgetWithText(TextField, "Title"), "Zoned");
  await tester.tap(find.widgetWithText(FilledButton, "Save"));
  await tester.pump(api.latency);
  await tester.pumpAndSettle();
  expect(find.text("New item"), findsNothing);
  final listed = await listAll(
    tester,
    api,
    DateTime(2026, 4, 19),
    DateTime(2026, 4, 23),
  );
  final created = listed.where((item) {
    return item["title"] == "Zoned";
  }).single;
  return (id: created["id"]! as String, api: api);
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets(
    "DZ1 the settings sheet's time zone part names the chosen zone with its "
    "offset over a chip for the device's zone and one for each added zone, "
    "and a tap on a chip zones the store",
    (tester) async {
      await pumpCalendar(tester, clock: noonClock);
      final store = storeOf(tester);
      expect(store, isA<CachingCalendarStore<ItemPayload>>());
      expect((store as CachingCalendarStore<ItemPayload>).readAhead, 2);
      const strings = DefaultCalendarLocalizations();
      String offsetOf(Location? zone) {
        return strings.utcOffset(
          CalendarDates.inZone(noon, zone: zone).timeZoneOffset.inMinutes,
        );
      }

      bool chosen(String name) {
        return tester.widget<InputChip>(zoneChip(name)).selected;
      }

      final chips = find.descendant(
        of: find.byKey(zoneChoicesKey),
        matching: find.byType(InputChip),
      );
      await openSettings(tester);
      expect(
        find.textContaining("This device, ${offsetOf(null)}"),
        findsOneWidget,
      );
      expect(chips, findsOneWidget);
      expect(chosen(""), isTrue);

      await tester.tap(find.byKey(manageZonesKey));
      await tester.pumpAndSettle();
      await addZone(tester, "havana", "America/Havana");
      await addZone(tester, "tokyo", "Asia/Tokyo");
      await tester.tap(find.byKey(manageZonesKey));
      await tester.pumpAndSettle();
      // Setup sanity: the adds chose no zone.
      expect(store.zone, isNull);
      expect(chips, findsNWidgets(3));

      await tester.tap(zoneChip("America/Havana"));
      await tester.pumpAndSettle();
      expect(store.zone?.name, "America/Havana");
      expect(chosen("America/Havana"), isTrue);
      expect(chosen(""), isFalse);
      expect(
        find.textContaining(
          "Havana, ${offsetOf(tz.getLocation("America/Havana"))}",
        ),
        findsOneWidget,
      );

      await tester.tap(zoneChip(""));
      await tester.pumpAndSettle();
      expect(store.zone, isNull);
      expect(chosen(""), isTrue);
      expect(chosen("America/Havana"), isFalse);
      await tester.tap(zoneChip("Asia/Tokyo"));
      await tester.pumpAndSettle();
      expect(store.zone?.name, "Asia/Tokyo");
      expect(chosen("Asia/Tokyo"), isTrue);
      // Tokyo's offset is not the device's in any zone the tests run in.
      expect(
        find.textContaining("Tokyo, ${offsetOf(tz.getLocation("Asia/Tokyo"))}"),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    "MZ1 the Manage chip turns the manage mode on and off: the title reads "
    "Time zone selection, with no back button before or beside it, the time "
    "zone part stays with Manage reading Done, and a search field over the "
    "zone list takes the place of the settings under it",
    (tester) async {
      await pumpCalendar(tester, clock: noonClock);
      await openSettings(tester);
      final sheet = find.byType(CalendarSettingsSheet);
      Finder manageReading(String label) {
        return find.descendant(
          of: find.byKey(manageZonesKey),
          matching: find.text(label),
        );
      }

      Rect rectOf(Key key) {
        return tester.getRect(find.byKey(key));
      }

      void expectSettings() {
        expect(find.text("Calendar settings"), findsOneWidget);
        expect(manageReading("Manage"), findsOneWidget);
        expect(find.byKey(slotLengthKey), findsOneWidget);
        expect(find.byKey(allowsOverlapsKey), findsOneWidget);
        expect(find.byKey(zoneSearchKey), findsNothing);
        expect(find.byKey(zoneListKey), findsNothing);
      }

      void expectManaging() {
        expect(find.text("Time zone selection"), findsOneWidget);
        expect(find.text("Calendar settings"), findsNothing);
        // The sheet pads its content 24 px from its edges.
        expect(
          tester.getRect(find.text("Time zone selection")).left,
          tester.getRect(sheet).left + 24.0,
        );
        expect(
          find.descendant(of: sheet, matching: find.byIcon(Icons.arrow_back)),
          findsNothing,
        );
        expect(zoneChip(""), findsOneWidget);
        expect(manageReading("Done"), findsOneWidget);
        expect(find.byKey(slotLengthKey), findsNothing);
        expect(find.byKey(allowsOverlapsKey), findsNothing);
        expect(
          rectOf(zoneChoicesKey).bottom,
          lessThan(rectOf(zoneSearchKey).top),
        );
        expect(rectOf(zoneSearchKey).bottom, lessThan(rectOf(zoneListKey).top));
      }

      expectSettings();
      await tester.tap(find.byKey(manageZonesKey));
      await tester.pumpAndSettle();
      expectManaging();
      await tester.tap(find.byKey(manageZonesKey));
      await tester.pumpAndSettle();
      expectSettings();
    },
  );

  testWidgets(
    "MZ2 a tap on a zone's row adds the zone: the rows under it close up "
    "over Harbor's motion, a chip with a remove button shows for it, the "
    "store's zone stays, and the manage mode stays on",
    (tester) async {
      await pumpCalendar(tester, clock: noonClock);
      final store = storeOf(tester);
      await openManaging(tester);
      await searchZones(tester, "america/h");
      final havana = find.byKey(zoneRowKey("America/Havana"));
      final below = find.byKey(zoneRowKey("America/Hermosillo"));
      // Setup sanity: Hermosillo's row is the one under Havana's.
      expect(tester.getRect(below).top, tester.getRect(havana).bottom);
      final from = tester.getRect(below).top;
      final to = tester.getRect(havana).top;
      expect(zoneChip("America/Havana"), findsNothing);

      await tester.tap(havana);
      // The add rebuilds the list, which starts the rows' motion a frame on.
      await tester.pump();
      await tester.pump();
      await tester.pump(harborMotionDuration ~/ 2);
      expect(tester.getRect(below).top, inExclusiveRange(to, from));
      await tester.pumpAndSettle();
      expect(find.byKey(zoneSearchKey), findsOneWidget);
      expect(zoneChip("America/Havana"), findsOneWidget);
      expect(
        tester.widget<InputChip>(zoneChip("America/Havana")).onDeleted,
        isNotNull,
      );
      expect(store.zone, isNull);
    },
  );

  testWidgets(
    "MZ3 the list holds, by name, the loaded zones not added whose id or "
    "city holds the search text, ignoring case and outer spaces, and a "
    "text that matches none shows a message",
    (tester) async {
      await pumpCalendar(tester, clock: noonClock);
      await openManaging(tester);
      final all = CalendarDates.loadedZones();
      List<String> expected(String query, Set<String> added) {
        final text = query.trim().toLowerCase();
        return <String>[
          for (final zone in all)
            if (!added.contains(zone.name) &&
                (zone.name.toLowerCase().contains(text) ||
                    CalendarZonePanel.cityOf(
                      zone,
                    ).toLowerCase().contains(text)))
              zone.name,
        ];
      }

      // Setup sanity: the zone database is loaded, and New York's id and
      // city differ in the text each search below matches.
      expect(all.length, greaterThan(400));
      expect(
        CalendarZonePanel.cityOf(tz.getLocation("America/New_York")),
        "New York",
      );
      expect(listedZones(tester), expected("", <String>{}));
      await searchZones(tester, "  HAVANA ");
      expect(
        listedZones(tester),
        allOf(contains("America/Havana"), expected("havana", <String>{})),
      );
      await searchZones(tester, "new york");
      expect(
        listedZones(tester),
        allOf(contains("America/New_York"), expected("new york", <String>{})),
      );
      await searchZones(tester, "america/new_");
      expect(
        listedZones(tester),
        allOf(
          contains("America/New_York"),
          expected("america/new_", <String>{}),
        ),
      );

      await addZone(tester, "havana", "America/Havana");
      await searchZones(tester, "");
      expect(listedZones(tester), expected("", <String>{"America/Havana"}));

      const message = "No time zone to add matches.";
      expect(find.text(message), findsNothing);
      await searchZones(tester, "zzzz");
      expect(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith("settings-zone-row-");
        }),
        findsNothing,
      );
      expect(find.text(message), findsOneWidget);
    },
  );

  testWidgets(
    "MZ4 in the manage mode each added zone's chip, never the device's, "
    "grows a remove button over Harbor's motion; a removal puts the zone "
    "back in the list, and that of the chosen zone chooses the device's",
    (tester) async {
      await pumpCalendar(tester, clock: noonClock);
      final store = storeOf(tester);
      InputChip chipOf(String name) {
        return tester.widget<InputChip>(zoneChip(name));
      }

      await openManaging(tester);
      await addZone(tester, "havana", "America/Havana");
      await addZone(tester, "tokyo", "Asia/Tokyo");
      await tester.tap(find.byKey(manageZonesKey));
      await tester.pumpAndSettle();
      expect(chipOf("America/Havana").onDeleted, isNull);
      await tester.tap(zoneChip("America/Havana"));
      await tester.pumpAndSettle();
      // Setup sanity: Havana is the chosen zone.
      expect(store.zone?.name, "America/Havana");
      final narrow = tester.getSize(zoneChip("America/Havana")).width;

      await tester.tap(find.byKey(manageZonesKey));
      await tester.pump();
      await tester.pump(harborMotionDuration ~/ 2);
      final growing = tester.getSize(zoneChip("America/Havana")).width;
      await tester.pumpAndSettle();
      final wide = tester.getSize(zoneChip("America/Havana")).width;
      expect(growing, inExclusiveRange(narrow, wide));
      expect(chipOf("").onDeleted, isNull);

      await tester.tap(
        find.descendant(
          of: zoneChip("America/Havana"),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();
      expect(zoneChip("America/Havana"), findsNothing);
      expect(store.zone, isNull);
      expect(chipOf("").selected, isTrue);
      expect(zoneChip("Asia/Tokyo"), findsOneWidget);
      await searchZones(tester, "havana");
      expect(find.byKey(zoneRowKey("America/Havana")), findsOneWidget);
    },
  );

  /// The zones DZ2 and DZ3 zone the store to: Havana, and an `Etc/GMT`
  /// zone 12 or more hours from the device.
  List<tz.Location> zonesToCreateIn() {
    return <tz.Location>[
      tz.getLocation("America/Havana"),
      _zoneFarFromDevice(noon),
    ];
  }

  testWidgets(
    "DZ2 an item the form creates at 09:00 is stored and shown in Week at "
    "09:00 on the store's zone clock",
    (tester) async {
      for (final zone in zonesToCreateIn()) {
        final (:id, :api) = await createAtNine(tester, zone);
        final listed = await listAll(
          tester,
          api,
          DateTime(2026, 4, 19),
          DateTime(2026, 4, 23),
        );
        final stored = listed.singleWhere((item) {
          return item["id"] == id;
        });
        final start = startOfJson(stored);
        expect(
          start.isAtSameMomentAs(tz.TZDateTime(zone, 2026, 4, 21, 9)),
          isTrue,
          reason: "${zone.name}: $start",
        );
        await showMinute(tester, 9 * 60);
        expect(
          tester.getRect(blockFinder(id)).top,
          moreOrLessEquals(
            cellRect(tester, rowOf(9 * 60), colOf(1)).top,
            epsilon: 0.5,
          ),
          reason: zone.name,
        );
        // The next zone's calendar starts anew.
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    "DZ3 the form opened on an item shows its times on the store's zone "
    "clock",
    (tester) async {
      for (final zone in zonesToCreateIn()) {
        final (:id, api: _) = await createAtNine(tester, zone);
        await showMinute(tester, 9 * 60);
        await tester.tap(blockFinder(id));
        await tester.pumpAndSettle();
        expect(find.text("Edit Task"), findsOneWidget, reason: zone.name);
        expect(
          find.descendant(
            of: dropdownFinder("Start time"),
            matching: find.text("09:00"),
          ),
          findsOneWidget,
          reason: zone.name,
        );
        expect(
          find.descendant(
            of: dropdownFinder("End time"),
            matching: find.text("09:15"),
          ),
          findsOneWidget,
          reason: zone.name,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    "DZ4 the hours errors name times on the store's zone clock, and the lock "
    "errors are judged on it",
    (tester) async {
      // The hours: a zone 3 hours behind the device, whose 08:00 the
      // device reads at 11:00, inside hours of 09:00 to 17:00.
      final west = _zoneApartFromDevice(noon, -3);
      final early = tz.TZDateTime(west, 2026, 4, 21, 8);
      // Setup sanity: the device reads the zone's 08:00 inside the hours.
      expect(
        CalendarDates.minuteOfDay(early.toLocal()),
        inInclusiveRange(9 * 60, 17 * 60 - 1),
      );
      final api = await pumpCalendar(
        tester,
        api: MockCalendarApi(latency: harnessLatency),
        editing: true,
        clock: noonClock,
        size: tall,
      );
      await zoneStore(tester, api, west);
      await pickMode(tester, "Week");
      await createTaskAt(tester, 8 * 60);
      await tester.enterText(find.widgetWithText(TextField, "Title"), "Early");
      storeOf(tester).hours = CalendarDayHours(9 * 60, 17 * 60);
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pump(api.latency);
      await tester.pumpAndSettle();
      expect(
        find.text(
          "The start is from 09:00 to before 17:00, inside the calendar's "
          "hours.",
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "The end is from after 09:00 to 17:00, inside the calendar's hours.",
        ),
        findsOneWidget,
      );
      expect(find.text("New item"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      // The lock: the store on a zone 12 or more hours from the device, the
      // clock at the zone's 11:00 on today's date where the zone is ahead
      // of the device, and at its 13:00 where it is behind, so the device
      // reads another date, and an hour each side stays on the zone's day.
      final far = _zoneFarFromDevice(noon);
      final reading = tz.TZDateTime.from(noon, far);
      final ahead = reading.timeZoneOffset > noon.timeZoneOffset;
      final hour = ahead ? 11 : 13;
      final now = tz.TZDateTime(far, 2026, 4, 21, hour);
      final plainNow = DateTime.fromMicrosecondsSinceEpoch(
        now.microsecondsSinceEpoch,
      );
      // Setup sanity: the device reads the clock on another date.
      expect(CalendarDates.dateOnly(plainNow), isNot(today));
      final before = tz.TZDateTime(far, 2026, 4, 21, hour - 1);
      final after = tz.TZDateTime(far, 2026, 4, 21, hour + 1);
      final policy = const CalendarSettings(
        lockPast: true,
        lockEarlierToday: true,
      ).editPolicy;
      Map<String, String> judged(DateTime start, CalendarNow at) {
        return formErrorsOf<ItemPayload>(policy, at, null, (
          start: start,
          end: start.add(const Duration(minutes: 15)),
        ), isAllDay: false);
      }

      final onZone = CalendarNow(time: now, today: today);
      final onDevice = CalendarNow(time: plainNow, today: today);
      DateTime plain(DateTime time) {
        return DateTime.fromMicrosecondsSinceEpoch(time.microsecondsSinceEpoch);
      }

      // Setup sanity: the zone's clock refuses the earlier start alone, and
      // the device's clock would judge one of the two the other way.
      expect(judged(before, onZone), isNotEmpty);
      expect(judged(after, onZone), isEmpty);
      expect(
        judged(plain(before), onDevice).isEmpty ||
            judged(plain(after), onDevice).isNotEmpty,
        isTrue,
      );

      final lockApi = await pumpCalendar(
        tester,
        api: MockCalendarApi(latency: harnessLatency),
        editing: true,
        settings: const CalendarSettings(
          lockPast: true,
          lockEarlierToday: true,
        ),
        clock: () {
          return plainNow;
        },
        size: tall,
      );
      await zoneStore(tester, lockApi, far);
      await pickMode(tester, "Week");
      await createTaskAt(tester, (hour + 1) * 60);
      await tester.enterText(find.widgetWithText(TextField, "Title"), "Lock");
      String hourText(int value) {
        return "${value.toString().padLeft(2, "0")}:00";
      }

      // The zone's clock, not the device's, refuses the earlier start,
      // which the form offers disabled.
      expect(optionEnabled(tester, "Start time", hourText(hour - 1)), isFalse);
      expect(optionEnabled(tester, "Start time", hourText(hour + 1)), isTrue);

      await chooseOption(tester, "Start time", hourText(hour + 1));
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pump();
      expect(find.text("The start can't be in the past."), findsNothing);
      expect(find.text("Past days are locked."), findsNothing);
      await tester.pump(lockApi.latency);
      await tester.pumpAndSettle();
      expect(find.text("New item"), findsNothing);
    },
  );

  testWidgets(
    "MZ5 the Manage chip, the last of the zone chips, 8 px after the last "
    "zone's chip, as tall as it and level with it, is drawn as a button: a "
    "borderless pill of an 18 px add icon and Manage in Harbor's primary, "
    "in the manage mode filled with that primary around a check icon and "
    "Done in white",
    (tester) async {
      // Wide enough that the chips share one line in the test font.
      await pumpCalendar(
        tester,
        clock: noonClock,
        size: const Size(800.0, 844.0),
      );
      await openManaging(tester);
      await addZone(tester, "havana", "America/Havana");
      final manage = find.byKey(manageZonesKey);
      final last = zoneChip("America/Havana");
      Finder inManage(Finder finder) {
        return find.descendant(of: manage, matching: finder);
      }

      /// The color [finder]'s text or icon draws in.
      Color? colorOf(Finder finder) {
        return tester
            .widget<RichText>(
              find.descendant(of: finder, matching: find.byType(RichText)),
            )
            .text
            .style
            ?.color;
      }

      for (final managing in <bool>[true, false]) {
        if (!managing) {
          await tester.tap(manage);
          await tester.pumpAndSettle();
          // Setup sanity: the manage mode ended.
          expect(find.byKey(zoneSearchKey), findsNothing);
        }
        final reason = managing ? "managing" : "settings";
        final rect = tester.getRect(manage);
        final label = inManage(find.text(managing ? "Done" : "Manage"));
        final icon = inManage(find.byIcon(managing ? Icons.check : Icons.add));
        final foreground = managing
            ? HarborColors.onPrimary
            : HarborColors.primary;
        expect(
          tester.widget<Material>(inManage(find.byType(Material)).first).shape,
          isA<StadiumBorder>().having(
            (shape) => shape.side.color,
            "side color",
            Colors.transparent,
          ),
          reason: reason,
        );
        expect(
          (tester.widget<Ink>(inManage(find.byType(Ink))).decoration!
                  as ShapeDecoration)
              .color,
          managing ? HarborColors.primary : Colors.transparent,
          reason: reason,
        );
        expect(label, findsOneWidget, reason: reason);
        expect(colorOf(label), foreground, reason: reason);
        expect(tester.getSize(icon), const Size.square(18.0), reason: reason);
        expect(colorOf(icon), foreground, reason: reason);
        expect(
          rect.left,
          moreOrLessEquals(tester.getRect(last).right + 8.0),
          reason: reason,
        );
        expect(rect.height, tester.getSize(last).height, reason: reason);
        expect(
          rect.center.dy,
          moreOrLessEquals(tester.getCenter(last).dy, epsilon: 0.5),
          reason: reason,
        );
      }
    },
  );

  testWidgets(
    "DZ5 the manage mode's list is two fifths of the height the keyboard "
    "and the status bar leave, from 112 to 320 px; the sheet keeps the "
    "search field and the list above the keyboard, and itself below the "
    "status bar",
    (tester) async {
      await pumpCalendar(tester, clock: noonClock);
      // Month, whose scaffold keeps its height under a keyboard, so the
      // calendar behind the sheet lays out as with none.
      await pickMode(tester, "Month");
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      await openManaging(tester);
      final field = find.byKey(zoneSearchKey);
      final list = find.byKey(zoneListKey);
      final sheet = find.byType(BottomSheet);
      expect(tester.getSize(list).height, 320.0);
      await tester.tap(field);
      await tester.pump();

      for (final keyboard in <double>[300.0, 600.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await tester.pumpAndSettle();
        final reason = "keyboard $keyboard";
        expect(
          tester.getSize(list).height,
          moreOrLessEquals(
            clampDouble((screen - keyboard) * 0.4, 112.0, 320.0),
          ),
          reason: reason,
        );
        // The field shows under the sheet's drag handle, and the list
        // ends above the keyboard.
        expect(
          tester.getRect(field).top,
          greaterThanOrEqualTo(
            tester.getRect(sheet).top + kMinInteractiveDimension - 0.5,
          ),
          reason: reason,
        );
        expect(
          tester.getRect(list).bottom,
          lessThanOrEqualTo(screen - keyboard + 0.5),
          reason: reason,
        );
      }

      const statusBar = 47.0;
      tester.view.padding = const FakeViewPadding(top: statusBar);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300.0);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(list).height,
        moreOrLessEquals((screen - 300.0 - statusBar) * 0.4),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 600.0);
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, greaterThanOrEqualTo(statusBar));
      tester.view.resetPadding();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
    },
  );
}
