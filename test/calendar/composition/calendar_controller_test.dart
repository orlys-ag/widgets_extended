/// The calendar's controller: its sizes and their defaults, the sets that
/// reach a bound calendar, the events that notify it, the range the
/// calendar asks, goTo, and the lifecycle changes a bind, a swap, a
/// second calendar and an unmount make.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

import 'recording_store.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime saturday = DateTime(2026, 4, 25);
final DateTime sunday = DateTime(2026, 4, 26);

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// [home] under a MaterialApp with no Scaffold and no ink splash, whose
/// shader a widget test cannot load.
Widget app(Widget home) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
}

/// The month grid's days of [day]'s month under [weekdays].
DayRange gridRange(DateTime day, {WeekdaySet weekdays = WeekdaySet.all}) {
  final grid = MonthGrid.of(day, weekdays: weekdays);
  return (first: grid.firstDay, last: grid.lastDay);
}

/// Counts a controller's notifies, and records what [visibleRange] reads
/// at each.
class Notifies {
  Notifies(this.controller) {
    controller.addListener(_record);
  }

  final CalendarController controller;

  final List<DayRange?> ranges = <DayRange?>[];

  int get count {
    return ranges.length;
  }

  void clear() {
    ranges.clear();
  }

  void _record() {
    ranges.add(controller.visibleRange);
  }
}

/// A host that owns [controller]'s life: it disposes the controller when
/// it leaves the tree, after the calendar under it.
class ControllerHost extends StatefulWidget {
  const ControllerHost({
    super.key,
    required this.controller,
    required this.store,
  });

  final CalendarController controller;
  final MemoryCalendarStore<String> store;

  @override
  State<ControllerHost> createState() {
    return _ControllerHostState();
  }
}

class _ControllerHostState extends State<ControllerHost> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CalendarView<String>(
      store: widget.store,
      controller: widget.controller,
      clock: fixedClock,
    );
  }
}

void main() {
  late RecordingStore store;

  setUp(() {
    store = RecordingStore();
  });

  tearDown(() {
    store.dispose();
  });

  Future<void> pumpCalendar(
    WidgetTester tester,
    CalendarController? controller, {
    WeekdaySet weekdays = WeekdaySet.all,
  }) async {
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
          weekdays: weekdays,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test("CO1 the least sizes default to 44 and 16, and a set notifies once "
      "where it changes one", () {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    expect(controller.minDayWidth, 44.0);
    expect(controller.minSlotHeight, 16.0);
    var notifies = 0;
    controller.addListener(() {
      notifies++;
    });
    controller.minDayWidth = 48.0;
    expect(notifies, 1);
    controller.minSlotHeight = 18.0;
    expect(notifies, 2);
    controller.minDayWidth = 60.0;
    expect(controller.minDayWidth, 60.0);
    expect(controller.minSlotHeight, 18.0);
    controller.minSlotHeight = 24.0;
    expect(controller.minSlotHeight, 24.0);
    expect(controller.minDayWidth, 60.0);
    notifies = 0;
    controller.minDayWidth = 60.0;
    controller.minSlotHeight = 24.0;
    expect(notifies, 0);
  });

  test("CO2 Month's week scale is the slot height over the default, never "
      "under 1, and a set of it sets the slot height", () {
    CalendarController sized(double minSlotHeight) {
      final controller = CalendarController(minSlotHeight: minSlotHeight);
      addTearDown(controller.dispose);
      return controller;
    }

    expect(sized(defaultMinSlotHeight).monthWeekScale, 1.0);
    expect(sized(minSlotHeightLow).monthWeekScale, 1.0);
    expect(sized(24.0).monthWeekScale, 1.5);
    expect(sized(minSlotHeightHigh).monthWeekScale, 3.0);
    final scaled = sized(defaultMinSlotHeight)..monthWeekScale = 2.5;
    expect(scaled.minSlotHeight, 40.0);
    final small = sized(10.0)..monthWeekScale = 1.0;
    expect(small.minSlotHeight, 10.0);
    final large = sized(30.0)..monthWeekScale = 1.0;
    expect(large.minSlotHeight, defaultMinSlotHeight);
  });

  test("CO3 setZoom notifies once for both sizes and takes one of the slot "
      "height and the week scale; the sizes assert positive and finite "
      "values; an unbound controller given no view or day throws", () {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    var notifies = 0;
    controller.addListener(() {
      notifies++;
    });
    controller.setZoom(minDayWidth: 60.0, minSlotHeight: 24.0);
    expect(notifies, 1);
    expect(controller.minDayWidth, 60.0);
    expect(controller.minSlotHeight, 24.0);
    expect(() {
      controller.setZoom(minSlotHeight: 20.0, monthWeekScale: 2.0);
    }, throwsAssertionError);
    for (final size in <double>[0.0, -1.0, double.infinity]) {
      expect(() {
        CalendarController(minDayWidth: size);
      }, throwsAssertionError);
      expect(() {
        CalendarController(minSlotHeight: size);
      }, throwsAssertionError);
      expect(() {
        controller.minDayWidth = size;
      }, throwsAssertionError);
      expect(() {
        controller.minSlotHeight = size;
      }, throwsAssertionError);
    }
    expect(controller.minDayWidth, 60.0);
    expect(controller.minSlotHeight, 24.0);
    expect(() {
      return controller.view;
    }, throwsStateError);
    expect(() {
      return controller.selectedDay;
    }, throwsStateError);
    final named = CalendarController(
      view: CalendarViewKind.week,
      selectedDay: DateTime(2026, 4, 21, 15, 30),
    );
    addTearDown(named.dispose);
    expect(named.view, CalendarViewKind.week);
    expect(named.selectedDay, tuesday);
  });

  testWidgets("CO4 a host's sets reach the bound calendar before the "
      "controller notifies once", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await pumpCalendar(tester, controller);
    final notifies = Notifies(controller);
    TimedGrid<String> grid() {
      return tester.widget<TimedGrid<String>>(find.byType(TimedGrid<String>));
    }

    controller.view = CalendarViewKind.week;
    expect(notifies.ranges, <DayRange>[(first: monday, last: sunday)]);
    await tester.pumpAndSettle();
    expect(grid().dayCount, 7);
    expect(grid().firstDay, monday);

    await pumpCalendar(tester, controller, weekdays: WeekdaySet.workweek);
    notifies.clear();
    final shown = shownDayNear(saturday, WeekdaySet.workweek);
    expect(shown, DateTime(2026, 4, 27));
    controller.selectedDay = saturday;
    expect(controller.selectedDay, shown);
    expect(notifies.ranges, <DayRange>[
      (first: shown, last: DateTime(2026, 5, 3)),
    ]);
    await tester.pumpAndSettle();
    expect(grid().selectedDay, shown);
    expect(grid().firstDay, shown);

    notifies.clear();
    controller.setZoom(minSlotHeight: 24.0, minDayWidth: 60.0);
    expect(notifies.count, 1);
    await tester.pump();
    expect(grid().minSlotHeight, 24.0);
    expect(grid().minDayWidth, 60.0);

    controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    notifies.clear();
    controller.setZoom(monthWeekScale: 2.0);
    expect(notifies.count, 1);
    await tester.pump();
    final board = tester.widget<MonthBoard<String>>(
      find.byType(MonthBoard<String>),
    );
    expect(board.weekScale, 2.0);
    expect(controller.minSlotHeight, 2.0 * defaultMinSlotHeight);
  });

  testWidgets("CO5 a menu pick, a day tap, a chevron step and Month's tap "
      "that opens Day each notify once; a browse notifies nothing", (
    tester,
  ) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await pumpCalendar(tester, controller);
    final notifies = Notifies(controller);
    final april28 = DateTime(2026, 4, 28);

    await tester.tap(find.byKey(dayCellKey(april28)).hitTestable());
    await tester.pumpAndSettle();
    expect(controller.selectedDay, april28);
    expect(notifies.count, 1);

    notifies.clear();
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);
    expect(controller.selectedDay, april28);
    expect(notifies.count, 0);

    await tester.tap(find.byTooltip("Calendar view"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Week").last);
    await tester.pumpAndSettle();
    expect(controller.view, CalendarViewKind.week);
    expect(notifies.count, 1);

    notifies.clear();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, DateTime(2026, 5, 5));
    expect(notifies.count, 1);

    controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    notifies.clear();
    final may12 = DateTime(2026, 5, 12);
    await tester.tap(find.byKey(monthStripKey(may12)));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, may12);
    expect(controller.view, CalendarViewKind.day);
    expect(notifies.count, 1);
  });

  testWidgets("CO6 the visible range is the range the calendar last asked "
      "the store to show, and null while the controller is unbound", (
    tester,
  ) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    expect(controller.visibleRange, isNull);
    await pumpCalendar(tester, controller);
    void expectRange(DayRange range) {
      expect(store.shows.last, range);
      expect(controller.visibleRange, range);
    }

    expectRange(gridRange(tuesday));
    controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    expectRange(gridRange(tuesday));
    controller.view = CalendarViewKind.week;
    await tester.pumpAndSettle();
    expectRange((first: monday, last: sunday));
    controller.view = CalendarViewKind.day;
    await tester.pumpAndSettle();
    expectRange((first: monday, last: sunday));
    await pumpCalendar(tester, controller, weekdays: WeekdaySet.workweek);
    expectRange((first: monday, last: DateTime(2026, 4, 24)));

    await tester.pumpWidget(const SizedBox());
    expect(controller.visibleRange, isNull);
  });

  testWidgets("CO6 a store listener that moves the selection from inside "
      "the store's show leaves the later range shown and visible", (
    tester,
  ) async {
    final controller = CalendarController(view: CalendarViewKind.week);
    addTearDown(controller.dispose);
    await pumpCalendar(tester, controller);
    var moved = false;
    store.addListener(() {
      if (!moved) {
        moved = true;
        controller.goTo(DateTime(2026, 5, 5));
      }
    });
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expect(moved, isTrue);
    final may = (first: DateTime(2026, 5, 4), last: DateTime(2026, 5, 10));
    expect(store.shows.reversed.take(2).toList(), <DayRange>[
      may,
      (first: DateTime(2026, 4, 27), last: DateTime(2026, 5, 3)),
    ]);
    expect(controller.visibleRange, may);
    expect(controller.selectedDay, DateTime(2026, 5, 5));
  });

  testWidgets("CO7 goTo brings the card or the strip back to the selected "
      "day with no notify, selects another day with one, and closes the "
      "month picker", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await pumpCalendar(tester, controller);
    final notifies = Notifies(controller);

    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);
    controller.goTo(tuesday);
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);
    expect(notifies.count, 0);

    final april28 = DateTime(2026, 4, 28);
    controller.goTo(april28);
    await tester.pumpAndSettle();
    expect(controller.selectedDay, april28);
    expect(notifies.count, 1);

    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    const picker = ValueKey<String>("month-picker");
    expect(find.byKey(picker), findsOneWidget);
    controller.goTo(april28);
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsNothing);
    expect(notifies.count, 1);

    controller.view = CalendarViewKind.day;
    await tester.pumpAndSettle();
    notifies.clear();
    final selected = find.byKey(weekStripDayKey(april28)).hitTestable();
    expect(selected, findsOneWidget);
    final strip = find.byType(WeekStrip<String>);
    await tester.drag(strip, Offset(-tester.getSize(strip).width, 0.0));
    await tester.pumpAndSettle();
    expect(selected, findsNothing);
    expect(find.text("May 2026"), findsOneWidget);
    controller.goTo(april28);
    await tester.pumpAndSettle();
    expect(selected, findsOneWidget);
    expect(find.text("Apr 2026"), findsOneWidget);
    expect(notifies.count, 0);
  });

  testWidgets("CO8 with no controller the menu switches the views", (
    tester,
  ) async {
    await pumpCalendar(tester, null);
    expect(find.byType(DayList<String>), findsOneWidget);
    Future<void> pick(String view) async {
      await tester.tap(find.byTooltip("Calendar view"));
      await tester.pumpAndSettle();
      await tester.tap(find.text(view).last);
      await tester.pumpAndSettle();
    }

    await pick("Week");
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(
      tester.widget<TimedGrid<String>>(find.byType(TimedGrid<String>)).dayCount,
      7,
    );
    await pick("Month");
    expect(find.byType(MonthBoard<String>), findsOneWidget);
    await pick("Day");
    expect(
      tester.widget<TimedGrid<String>>(find.byType(TimedGrid<String>)).dayCount,
      1,
    );
    await pick("Agenda");
    expect(find.byType(DayList<String>), findsOneWidget);
  });

  testWidgets("CO9 an unmount notifies the host's controller once after the "
      "frame, its range null, and the controller lives on", (tester) async {
    final controller = CalendarController();
    var shows = true;
    late StateSetter setHost;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) {
            setHost = setState;
            if (!shows) {
              return const SizedBox();
            }
            return CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final calls = <({SchedulerPhase phase, DayRange? range})>[];
    controller.addListener(() {
      calls.add((
        phase: SchedulerBinding.instance.schedulerPhase,
        range: controller.visibleRange,
      ));
      setHost(() {});
    });
    setHost(() {
      shows = false;
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(calls, <({SchedulerPhase phase, DayRange? range})>[
      (phase: SchedulerPhase.postFrameCallbacks, range: null),
    ]);
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    controller.addListener(() {});
    controller.dispose();
  });

  group("CO10 a controller swapped in, dropped or given to another "
      "calendar", () {
    testWidgets("a swap shows the new controller's view and notifies the "
        "old one after the frame, which then reaches no calendar", (
      tester,
    ) async {
      final first = CalendarController();
      addTearDown(first.dispose);
      final second = CalendarController(view: CalendarViewKind.week);
      addTearDown(second.dispose);
      var current = first;
      late StateSetter setHost;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              setHost = setState;
              return CalendarView<String>(
                store: store,
                controller: current,
                clock: fixedClock,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final phases = <SchedulerPhase>[];
      first.addListener(() {
        phases.add(SchedulerBinding.instance.schedulerPhase);
        setHost(() {});
      });
      setHost(() {
        current = second;
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(phases, <SchedulerPhase>[SchedulerPhase.postFrameCallbacks]);
      await tester.pumpAndSettle();
      expect(phases, hasLength(1));
      expect(find.byType(TimedGrid<String>), findsOneWidget);
      expect(first.visibleRange, isNull);
      expect(second.visibleRange, (first: monday, last: sunday));
      first.view = CalendarViewKind.month;
      await tester.pumpAndSettle();
      expect(find.byType(MonthBoard<String>), findsNothing);
      expect(find.byType(TimedGrid<String>), findsOneWidget);
    });

    testWidgets("a swap to a controller of the view and day shown gives it "
        "the range shown, in the swap's frame and after it", (tester) async {
      final first = CalendarController();
      addTearDown(first.dispose);
      final second = CalendarController(
        view: CalendarViewKind.agenda,
        selectedDay: tuesday,
      );
      addTearDown(second.dispose);
      final readInBuild = <DayRange?>[];
      Widget calendar(CalendarController controller) {
        return app(
          Column(
            children: <Widget>[
              Expanded(
                child: CalendarView<String>(
                  store: store,
                  controller: controller,
                  clock: fixedClock,
                ),
              ),
              Builder(
                builder: (context) {
                  readInBuild.add(second.visibleRange);
                  return const SizedBox(height: 1.0);
                },
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(calendar(first));
      await tester.pumpAndSettle();
      expect(readInBuild.last, isNull);
      final asks = store.shows.length;
      await tester.pumpWidget(calendar(second));
      expect(readInBuild.last, gridRange(tuesday));
      expect(store.shows, hasLength(asks));
      await tester.pumpAndSettle();
      expect(second.visibleRange, gridRange(tuesday));
      expect(store.shows.last, gridRange(tuesday));
    });

    testWidgets("a rebuild that drops the host's controller keeps the view, "
        "the day and the zoom", (tester) async {
      final controller = CalendarController(
        view: CalendarViewKind.week,
        selectedDay: DateTime(2026, 4, 23),
      );
      addTearDown(controller.dispose);
      await pumpCalendar(tester, controller);
      final focal = tester.getCenter(find.byType(TimedGrid<String>));
      final top = await tester.startGesture(focal - const Offset(0.0, 30.0));
      final bottom = await tester.startGesture(focal + const Offset(0.0, 30.0));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await top.moveBy(const Offset(0.0, -6.0));
        await bottom.moveBy(const Offset(0.0, 6.0));
        await tester.pump();
      }
      await top.up();
      await bottom.up();
      await tester.pumpAndSettle();
      final zoomed = controller.minSlotHeight;
      expect(zoomed, greaterThan(defaultMinSlotHeight));

      await pumpCalendar(tester, null);
      final grid = tester.widget<TimedGrid<String>>(
        find.byType(TimedGrid<String>),
      );
      expect(grid.dayCount, 7);
      expect(grid.selectedDay, DateTime(2026, 4, 23));
      expect(grid.minSlotHeight, zoomed);
      expect(grid.minDayWidth, controller.minDayWidth);
    });

    testWidgets("a new calendar in the old one's place takes the "
        "controller", (tester) async {
      final controller = CalendarController();
      addTearDown(controller.dispose);
      Widget calendar(Key key) {
        return app(
          Column(
            children: <Widget>[
              Expanded(
                child: CalendarView<String>(
                  key: key,
                  store: store,
                  controller: controller,
                  clock: fixedClock,
                ),
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(calendar(const ValueKey<int>(1)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(calendar(const ValueKey<int>(2)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.view = CalendarViewKind.week;
      await tester.pumpAndSettle();
      expect(find.byType(TimedGrid<String>), findsOneWidget);
      expect(controller.visibleRange, (first: monday, last: sunday));
    });

    testWidgets("a second calendar given the controller takes it, and a "
        "debug build reports the first", (tester) async {
      final controller = CalendarController();
      addTearDown(controller.dispose);
      final other = RecordingStore();
      addTearDown(other.dispose);
      const firstKey = ValueKey<String>("first");
      const secondKey = ValueKey<String>("second");
      Widget calendars({required bool both}) {
        return app(
          Row(
            children: <Widget>[
              Expanded(
                child: CalendarView<String>(
                  key: firstKey,
                  store: other,
                  controller: controller,
                  clock: fixedClock,
                ),
              ),
              Expanded(
                child: both
                    ? CalendarView<String>(
                        key: secondKey,
                        store: store,
                        controller: controller,
                        clock: fixedClock,
                      )
                    : const SizedBox(),
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(calendars(both: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(calendars(both: true));
      expect(tester.takeException(), isA<AssertionError>());
      await tester.pumpAndSettle();

      controller.view = CalendarViewKind.week;
      await tester.pumpAndSettle();
      Finder under(ValueKey<String> key, Finder finder) {
        return find.descendant(of: find.byKey(key), matching: finder);
      }

      expect(under(secondKey, find.byType(TimedGrid<String>)), findsOneWidget);
      expect(under(firstKey, find.byType(TimedGrid<String>)), findsNothing);
      expect(under(firstKey, find.byType(DayList<String>)), findsOneWidget);
      final range = controller.visibleRange;
      expect(range, (first: monday, last: sunday));

      final april28 = DateTime(2026, 4, 28);
      await tester.tap(
        under(firstKey, find.byKey(dayCellKey(april28))).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(other.shows.last, isNot(range));
      expect(controller.visibleRange, range);
      expect(controller.selectedDay, tuesday);
    });
  });

  testWidgets("CO11 the bind of a controller given nothing notifies once "
      "after the frame, the range already asked", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    late StateSetter setHost;
    final calls = <({SchedulerPhase phase, DayRange? range, DayRange shown})>[];
    void record() {
      calls.add((
        phase: SchedulerBinding.instance.schedulerPhase,
        range: controller.visibleRange,
        shown: store.shows.last,
      ));
      setHost(() {});
    }

    controller.addListener(record);
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) {
            setHost = setState;
            return Builder(
              builder: (context) {
                return CalendarView<String>(
                  store: store,
                  controller: controller,
                  clock: fixedClock,
                );
              },
            );
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(calls, <({SchedulerPhase phase, DayRange? range, DayRange shown})>[
      (
        phase: SchedulerPhase.postFrameCallbacks,
        range: gridRange(tuesday),
        shown: gridRange(tuesday),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(controller.view, CalendarViewKind.agenda);
    expect(controller.selectedDay, tuesday);
    // The host goes with the test's tree, before the controller.
    controller.removeListener(record);
  });

  group("CO12 a controller disposed in the frame of a lifecycle change "
      "gets no notify", () {
    testWidgets("an own controller a host's replaces as the weekdays "
        "change", (tester) async {
      final host = CalendarController(view: CalendarViewKind.week);
      addTearDown(host.dispose);
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            clock: fixedClock,
            weekdays: WeekdaySet.all,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            controller: host,
            clock: fixedClock,
            weekdays: WeekdaySet.workweek,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TimedGrid<String>), findsOneWidget);
      expect(host.visibleRange, (first: monday, last: sunday));
    });

    testWidgets("a host's controller its host disposes as the calendar "
        "leaves", (tester) async {
      final controller = CalendarController();
      await tester.pumpWidget(
        app(ControllerHost(controller: controller, store: store)),
      );
      await tester.pumpAndSettle();
      expect(controller.visibleRange, gridRange(tuesday));
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
