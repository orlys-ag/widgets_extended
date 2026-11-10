/// The calendar on a zone: the app bar's time zone button and its sheet,
/// the item form's times and the store's hours on the store's zone clock,
/// and the history lock judged on it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/composition/calendar_zone_panel.dart'
    show zonePanelRowKey;
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';
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

/// The app bar's time zone button.
Finder get zoneButton {
  return find.widgetWithIcon(TextButton, Icons.public);
}

/// [finder] inside the open zone panel.
Finder inPanel(Finder finder) {
  return find.descendant(of: find.byType(CalendarZonePanel), matching: finder);
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

/// The text a dropdown labelled [label] shows as its value.
Finder dropdownFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) {
      return widget is DropdownButtonFormField;
    }),
  );
}

/// Picks [option] in the form's dropdown labelled [label], scrolling its
/// menu until the option shows.
Future<void> chooseOption(
  WidgetTester tester,
  String label,
  String option,
) async {
  await tester.tap(dropdownFinder(label));
  await tester.pumpAndSettle();
  final menu = find.byType(Scrollable).last;
  final item = find.descendant(of: menu, matching: find.text(option));
  await tester.scrollUntilVisible(item, -100.0, scrollable: menu);
  // Centred, as an item scrolled to the menu's edge can sit under it.
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(item);
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
  expect(find.text("New Task"), findsOneWidget);
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
  expect(find.text("New Task"), findsNothing);
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
    "DZ1 the app bar's zone button opens the panel in a sheet, and picking a "
    "zone in view 1 zones the store and closes the sheet",
    (tester) async {
      await pumpCalendar(tester, clock: noonClock);
      final store = storeOf(tester);
      expect(store, isA<CachingCalendarStore<ItemPayload>>());
      expect((store as CachingCalendarStore<ItemPayload>).readAhead, 2);
      const strings = DefaultCalendarLocalizations();
      expect(
        find.descendant(
          of: zoneButton,
          matching: find.text(strings.deviceZoneName),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip("Time zone"), findsOneWidget);

      Future<void> openSheet() async {
        await tester.tap(zoneButton);
        await tester.pumpAndSettle();
        expect(find.byType(CalendarZonePanel), findsOneWidget);
      }

      Future<void> search(String text) async {
        await tester.enterText(inPanel(find.byType(TextField)), text);
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        await tester.tap(inPanel(find.byTooltip(strings.zonesBackTooltip)));
        await tester.pumpAndSettle();
      }

      // Havana added in view 2 and picked in view 1.
      await openSheet();
      await tester.tap(inPanel(find.text(strings.addZonesLabel)));
      await tester.pumpAndSettle();
      await search("havana");
      await tester.tap(inPanel(find.text("Havana")));
      await tester.pumpAndSettle();
      // Setup sanity: an add reports nothing, so the sheet stays.
      expect(store.zone, isNull);
      await back();
      await tester.tap(inPanel(find.text("Havana")));
      await tester.pumpAndSettle();
      expect(store.zone?.name, "America/Havana");
      expect(find.byType(CalendarZonePanel), findsNothing);
      expect(
        find.descendant(of: zoneButton, matching: find.text("Havana")),
        findsOneWidget,
      );

      // Unchecking the current zone in view 2 puts the store back on the
      // device's clock and leaves the sheet open there.
      await openSheet();
      await tester.tap(inPanel(find.text(strings.addZonesLabel)));
      await tester.pumpAndSettle();
      await search("havana");
      await tester.tap(inPanel(find.text("Havana")));
      await tester.pumpAndSettle();
      expect(store.zone, isNull);
      expect(find.byType(CalendarZonePanel), findsOneWidget);
      expect(inPanel(find.byType(TextField)), findsOneWidget);

      // Tokyo checked there, then picked in view 1.
      await search("tokyo");
      await tester.tap(inPanel(find.text("Tokyo")));
      await tester.pumpAndSettle();
      await back();
      await tester.tap(inPanel(find.text("Tokyo")));
      await tester.pumpAndSettle();
      expect(store.zone?.name, "Asia/Tokyo");
      expect(find.byType(CalendarZonePanel), findsNothing);
      expect(
        find.descendant(of: zoneButton, matching: find.text("Tokyo")),
        findsOneWidget,
      );

      // Under the keyboard, the sheet stays within the screen and its list
      // scrolls its last row above the keyboard.
      await openSheet();
      await tester.tap(inPanel(find.text(strings.addZonesLabel)));
      await tester.pumpAndSettle();
      const keyboard = 300.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      final screen = tester.view.physicalSize.height;
      expect(tester.getRect(find.byType(CalendarZonePanel)).top, 0.0);
      final list = tester.state<ScrollableState>(
        find.descendant(
          of: inPanel(find.byType(CustomScrollView)),
          matching: find.byType(Scrollable),
        ),
      );
      // The list's extent grows as it lays its rows out, so it jumps to
      // its end until the end stays.
      while (list.position.pixels < list.position.maxScrollExtent) {
        list.position.jumpTo(list.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      final last = tester
          .widget<SliverTree<String, Location>>(
            inPanel(find.byType(SliverTree<String, Location>)),
          )
          .controller
          .liveRootKeys
          .last;
      expect(
        tester.getRect(find.byKey(zonePanelRowKey(last))).bottom,
        lessThanOrEqualTo(screen - keyboard + 0.5),
      );
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
      expect(find.text("New Task"), findsOneWidget);
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
        return lockErrorsOf<ItemPayload>(policy, at, null, (
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
        clock: () {
          return plainNow;
        },
        size: tall,
      );
      await zoneStore(tester, lockApi, far);
      await openSettings(tester);
      await tester.tap(find.byKey(lockPastKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(lockEarlierTodayKey));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195.0, 20.0));
      await tester.pumpAndSettle();
      await pickMode(tester, "Week");
      await createTaskAt(tester, (hour + 1) * 60);
      await tester.enterText(find.widgetWithText(TextField, "Title"), "Lock");
      String hourText(int value) {
        return "${value.toString().padLeft(2, "0")}:00";
      }

      await chooseOption(tester, "Start time", hourText(hour - 1));
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pumpAndSettle();
      expect(find.text("The start can't be in the past."), findsOneWidget);
      expect(find.text("New Task"), findsOneWidget);

      await chooseOption(tester, "Start time", hourText(hour + 1));
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pump();
      expect(find.text("The start can't be in the past."), findsNothing);
      expect(find.text("Past days are locked."), findsNothing);
      await tester.pump(lockApi.latency);
      await tester.pumpAndSettle();
      expect(find.text("New Task"), findsNothing);
    },
  );
}
