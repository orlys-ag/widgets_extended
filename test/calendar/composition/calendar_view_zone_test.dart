/// The calendar over a store with a zone: each view draws, files, labels
/// and reports on the zone's clock, follows a change of the zone with the
/// animation of a store change, ends the drags in flight and moves a
/// running create's mark with its instants, asks the zone a bounded count
/// of lookups on Week's hot paths, and the documents say so.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/month_picker.dart';
import 'package:widgets_extended/calendar/views/move_request.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import '../../scheduling/store/zone_support.dart';
import '../../scheduling/zones.dart';

/// The instant the zones apart from the device are built at.
final DateTime on = DateTime(2026, 4, 21, 12);

/// A zone whose one offset is the device's at [on] plus [hours].
tz.Location apart(int hours) {
  return zoneApartFromDevice(on, hours);
}

/// The `Etc/GMT` zone of [offset] whole hours east of UTC.
tz.Location gmtZone(int offset) {
  if (offset == 0) {
    return tz.getLocation("Etc/GMT");
  }
  // The names' signs are POSIX's: Etc/GMT-3 lies three hours east.
  return tz.getLocation(offset > 0 ? "Etc/GMT-$offset" : "Etc/GMT+${-offset}");
}

/// The day number of [year], [month] and [day].
int numberOf(int year, int month, int day) {
  return CalendarDates.dayNumber(DateTime(year, month, day));
}

/// The day number of [day]'s date, by its fields.
int dateOf(DateTime day) {
  return CalendarDates.dayNumber(day);
}

/// [hour]:[minute] on [year]-[month]-[day] on [zone]'s clock.
DateTime timeIn(
  tz.Location zone,
  int year,
  int month,
  int day,
  int hour, [
  int minute = 0,
]) {
  return tz.TZDateTime(zone, year, month, day, hour, minute);
}

/// The first instant [zone]'s clock reads [year]-[month]-[day].
DateTime dayIn(tz.Location zone, int year, int month, int day) {
  return dayOfNumberIn(numberOf(year, month, day), zone);
}

/// [time]'s instant as a plain local time, as a device's clock reads it.
DateTime instantOf(DateTime time) {
  return DateTime.fromMicrosecondsSinceEpoch(time.microsecondsSinceEpoch);
}

/// Whether [day] is a day start of [zone], a `TZDateTime` of it.
bool isDayStartIn(DateTime day, tz.Location zone) {
  return day is tz.TZDateTime &&
      day.location == zone &&
      CalendarDates.isDayStart(day);
}

CalendarEntry<String> entryOf(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// 11:07 on Tuesday April 21 2026, on the device's clock.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// [home] under a MaterialApp with no ink splash, under [calendarTheme]
/// where one is given.
Widget app(Widget home, {CalendarThemeData? calendarTheme}) {
  var child = home;
  if (calendarTheme != null) {
    child = CalendarTheme(data: calendarTheme, child: child);
  }
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: child,
  );
}

/// Lays the test out in a view 800 wide and 2000 tall.
void useTallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800.0, 2000.0);
  addTearDown(tester.view.reset);
}

/// The block of [id]'s piece on [day], or with no [day] every block of
/// [id].
Finder blockFinder(String id, [DateTime? day]) {
  if (day != null) {
    return find.byKey(blockKey(id, day));
  }
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("block-$id@");
  });
}

/// Month's chips of [id].
Finder chipFinder(String id) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("month-chip-$id@");
  });
}

/// What shows [id]'s entry in [view]: Agenda's card, Day's and Week's
/// blocks, or Month's chips.
Finder entryFinder(CalendarViewKind view, String id) {
  switch (view) {
    case CalendarViewKind.agenda:
      return find.byKey(entryCardKey(id));
    case CalendarViewKind.day:
    case CalendarViewKind.week:
      return blockFinder(id);
    case CalendarViewKind.month:
      return chipFinder(id);
  }
}

/// The one timed grid's viewport.
RenderBoardViewport<GridKey> gridViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
}

/// The one timed grid shown.
TimedGrid<String> gridOf(WidgetTester tester) {
  return tester.widget<TimedGrid<String>>(find.byType(TimedGrid<String>));
}

/// The grid row of the slot holding [minute], a minute after midnight, in
/// the one timed grid shown: its first slot row, which is its board's row
/// count less its slot rows and the room below them, plus the slots from
/// its hours' start.
int gridRowOf(WidgetTester tester, int minute) {
  final grid = gridOf(tester);
  final board =
      find
              .byWidgetPredicate((widget) {
                return widget is Board<GridKey, Object?>;
              })
              .evaluate()
              .single
              .widget
          as Board<GridKey, Object?>;
  final hours = grid.hours;
  final firstSlotRow =
      board.controller.rows.axis.trackCount -
      hours.slotCountOf(grid.slotMinutes) -
      1;
  return firstSlotRow + (minute - hours.start) ~/ grid.slotMinutes;
}

/// Week's grid column of [day], Monday's being 1.
int weekColOf(DateTime day) {
  return 1 + CalendarDates.weekdayColumnOfDay(CalendarDates.dayNumber(day));
}

/// The grid column of [day] in [view]: Day's one column, or Week's.
int colIn(CalendarViewKind view, DateTime day) {
  return view == CalendarViewKind.week ? weekColOf(day) : 1;
}

/// The global rect of the timed grid's cell at [row] and [col].
Rect cellRect(WidgetTester tester, int row, int col) {
  final viewport = gridViewport(tester);
  final rect = viewport.rectOfCell(row, col)!;
  return Rect.fromPoints(
    viewport.localToGlobal(rect.topLeft),
    viewport.localToGlobal(rect.bottomRight),
  );
}

/// The global top of the slot row holding [minute] in [col].
double rowTop(WidgetTester tester, int minute, int col) {
  return cellRect(tester, gridRowOf(tester, minute), col).top;
}

/// The global height of one slot row.
double slotExtent(WidgetTester tester, int col) {
  return cellRect(tester, gridRowOf(tester, 12 * 60), col).height;
}

/// The global centre of the slot row holding [minute] in [col].
Offset slotCenter(WidgetTester tester, int minute, int col) {
  return cellRect(tester, gridRowOf(tester, minute), col).center;
}

/// The timed grid's vertical scroll position.
ScrollPosition verticalOf(WidgetTester tester) {
  return gridViewport(tester).verticalPosition!;
}

/// A canvas that records the rects and lines drawn on it with their
/// paints. Every other call is ignored.
class PaintLog implements Canvas {
  final List<({Rect rect, Paint paint})> rects = <({Rect rect, Paint paint})>[];
  final List<({Offset from, Offset to, Paint paint})> lines =
      <({Offset from, Offset to, Paint paint})>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add((rect: rect, paint: paint));
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines.add((from: p1, to: p2, paint: paint));
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

/// The theme the timed grid draws in.
CalendarThemeData gridTheme(WidgetTester tester) {
  return CalendarTheme.of(tester.element(find.byType(TimedGrid<String>)));
}

/// The day number of the column whose slots the grid's background tints
/// as today's, or null where none is.
int? tintedDay(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = PaintLog();
  viewport.background!.paint(canvas, viewport);
  final tint = gridTheme(tester).primaryTint.toARGB32();
  final row = gridRowOf(tester, 12 * 60);
  final firstDay = CalendarDates.dayNumber(gridOf(tester).firstDay);
  for (final record in canvas.rects) {
    if (record.paint.color.toARGB32() != tint ||
        record.paint.style != PaintingStyle.fill) {
      continue;
    }
    for (
      var col = viewport.firstVisibleCol;
      col <= viewport.lastVisibleCol;
      col++
    ) {
      final cell = viewport.visibleCellRect(row, col);
      if (cell.left == record.rect.left && cell.right == record.rect.right) {
        // Every weekday is shown, so column 1 is the first day.
        return firstDay + col - 1;
      }
    }
  }
  return null;
}

/// The rects the grid's background strokes, a range of slots, in the
/// viewport's paint space.
List<Rect> strokedRects(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = PaintLog();
  viewport.background!.paint(canvas, viewport);
  return <Rect>[
    for (final record in canvas.rects)
      if (record.paint.style == PaintingStyle.stroke) record.rect,
  ];
}

/// The line marking the current time, in the viewport's paint space, or
/// null where the grid draws none.
({Offset from, Offset to})? nowLine(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = PaintLog();
  viewport.foreground!.paint(canvas, viewport);
  final error = gridTheme(tester).error.toARGB32();
  for (final line in canvas.lines) {
    if (line.paint.color.toARGB32() == error) {
      return (from: line.from, to: line.to);
    }
  }
  return null;
}

/// Where the line marking [minute] lies in [col], in the viewport's paint
/// space: as far into its slot's row as the minute lies into the slot.
({double left, double y}) nowLineAt(WidgetTester tester, int minute, int col) {
  final viewport = gridViewport(tester);
  final slot = gridOf(tester).slotMinutes;
  final rect = viewport.visibleCellRect(gridRowOf(tester, minute), col);
  return (left: rect.left, y: rect.top + (minute % slot) / slot * rect.height);
}

/// The day numbers the cells of Agenda's and Day's calendar card select.
Set<int> selectedCells(WidgetTester tester) {
  return <int>{
    for (final cell in tester.widgetList<DayCell>(find.byType(DayCell)))
      if (cell.isSelected) dateOf(cell.day),
  };
}

/// The label a screen reader hears for Month's cell of [day].
String monthCellLabel(WidgetTester tester, DateTime day) {
  return tester
      .widgetList<Semantics>(
        find.descendant(
          of: find.byKey(monthDayKey(day)),
          matching: find.byType(Semantics),
        ),
      )
      .first
      .properties
      .label!;
}

/// The day numbers [view] marks as today: the calendar card's cells in
/// Agenda and Day, the column the grid tints in Week, and the cells whose
/// label says today in Month, of April 2026's grid.
Set<int> todaysMarked(WidgetTester tester, CalendarViewKind view) {
  switch (view) {
    case CalendarViewKind.agenda:
    case CalendarViewKind.day:
      return <int>{
        for (final cell in tester.widgetList<DayCell>(find.byType(DayCell)))
          if (cell.isToday) dateOf(cell.day),
      };
    case CalendarViewKind.week:
      final day = tintedDay(tester);
      return day == null ? <int>{} : <int>{day};
    case CalendarViewKind.month:
      final grid = CalendarMonthGrid.of(DateTime(2026, 4, 1));
      final marked = <int>{};
      for (
        var day = grid.firstDay;
        !day.isAfter(grid.lastDay);
        day = CalendarDates.addDays(day, 1)
      ) {
        final cell = find.byKey(monthDayKey(day));
        if (cell.evaluate().isEmpty) {
          continue;
        }
        final label = monthCellLabel(tester, day);
        if (label.split(", ").contains("today")) {
          marked.add(dateOf(day));
        }
      }
      return marked;
  }
}

/// A touch press at [at] held past the long-press timeout: a lift.
Future<TestGesture> lift(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  return gesture;
}

/// Long-presses [block] and lets go where it lifted, which selects it.
Future<void> select(WidgetTester tester, Finder block) async {
  final gesture = await lift(tester, tester.getCenter(block));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A mouse press at [from] that moves to [to] and lets go.
Future<void> mouseDrag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A touch press at [at] held past the long-press timeout, then let go
/// where it began.
Future<void> holdInPlace(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The decoration of Agenda's and Month's create mark under the theme above
/// [view]: the theme's primary tint, edged in its primary colour.
BoxDecoration createMarkIn(WidgetTester tester, Finder view) {
  final theme = CalendarTheme.of(tester.element(view));
  return BoxDecoration(
    color: theme.primaryTint,
    border: Border.all(color: theme.primary, width: 2.0),
  );
}

/// The create marks, boxes drawing [mark], under [of].
Finder createMarksUnder(Finder of, BoxDecoration mark) {
  return find.descendant(
    of: of,
    matching: find.byWidgetPredicate((widget) {
      return widget is DecoratedBox && widget.decoration == mark;
    }),
  );
}

/// A data source that answers each read within the call, through a
/// [SynchronousFuture], with the entries it holds covering its days, and
/// holds each replace until the test runs [completeWrites], which stores
/// the replaced entries and completes them.
class HeldWrites implements CalendarDataSource<String> {
  HeldWrites(Iterable<CalendarEntry<String>> entries) {
    for (final entry in entries) {
      this.entries[entry.id!] = entry;
    }
  }

  final Map<String, CalendarEntry<String>> entries =
      <String, CalendarEntry<String>>{};

  final List<
    ({CalendarEntry<String> entry, Completer<CalendarEntry<String>> done})
  >
  held =
      <
        ({CalendarEntry<String> entry, Completer<CalendarEntry<String>> done})
      >[];

  /// Stores each held write and completes it with its entry.
  void completeWrites() {
    final writes = held.toList();
    held.clear();
    for (final write in writes) {
      entries[write.entry.id!] = write.entry;
      write.done.complete(write.entry);
    }
  }

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final from = CalendarDates.dayNumber(first);
    final to = CalendarDates.dayNumber(last);
    return SynchronousFuture<List<CalendarEntry<String>>>(
      <CalendarEntry<String>>[
        for (final entry in entries.values)
          if (CalendarDates.dayNumber(entry.start) <= to &&
              CalendarDates.lastDayNumberOf(entry.start, entry.end) >= from)
            entry,
      ],
    );
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    final done = Completer<CalendarEntry<String>>();
    held.add((entry: entry, done: done));
    return done.future;
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}

/// A scan for a zone and a clock where the zone's month differs from the
/// device's: at the device's 2026-04-30 23:30, the first `Etc/GMT` zone
/// from `Etc/GMT-14` down whose date there is in May, or, with none, at
/// the device's 2026-05-01 00:30, the first from `Etc/GMT+12` up whose
/// date there is in April; each skipping a zone a whole number of days
/// from the device, whose clock reads the device's hours.
({tz.Location zone, DateTime clock}) zoneOfAnotherMonth() {
  bool daysApart(tz.Location zone, DateTime at) {
    final there = tz.TZDateTime.from(at, zone);
    return (there.timeZoneOffset - at.timeZoneOffset).inMinutes %
            CalendarDates.minutesPerDay ==
        0;
  }

  final late = DateTime(2026, 4, 30, 23, 30);
  for (var offset = 14; offset >= -12; offset--) {
    final zone = gmtZone(offset);
    if (tz.TZDateTime.from(late, zone).month == 5 && !daysApart(zone, late)) {
      return (zone: zone, clock: late);
    }
  }
  final early = DateTime(2026, 5, 1, 0, 30);
  for (var offset = -12; offset <= 14; offset++) {
    final zone = gmtZone(offset);
    if (tz.TZDateTime.from(early, zone).month == 4 && !daysApart(zone, early)) {
      return (zone: zone, clock: early);
    }
  }
  throw StateError("No Etc/GMT zone reads another month than the device.");
}

void main() {
  testWidgets(
    "VZ1 a calendar over a zoned store builds in Agenda, Day, Week and Month "
    "and shows its entry, with the zone given at construction or after the "
    "first build",
    (tester) async {
      useTallView(tester);
      final zone = apart(5);
      for (final later in <bool>[false, true]) {
        for (final view in CalendarViewKind.values) {
          final store = memoryStoreIn<String>(
            later ? null : zone,
            entries: <CalendarEntry<String>>[
              entryOf(
                "a",
                timeIn(zone, 2026, 4, 21, 10),
                timeIn(zone, 2026, 4, 21, 11),
              ),
            ],
          );
          addTearDown(store.dispose);
          final controller = CalendarController(
            view: view,
            selectedDay: DateTime(2026, 4, 21),
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            app(
              CalendarView<String>(
                store: store,
                controller: controller,
                clock: fixedClock,
              ),
            ),
          );
          if (later) {
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            setStoreZone(store, zone);
            await tester.pump();
          }
          expect(tester.takeException(), isNull, reason: "$view $later");
          await tester.pumpAndSettle();
          expect(entryFinder(view, "a"), findsWidgets, reason: "$view $later");
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    "VZ2 a timed entry shows on the zone's day in each view, and Week's and "
    "Day's block tops at the zone's wall minute",
    (tester) async {
      useTallView(tester);
      final zone = apart(12);
      final tuesday = DateTime(2026, 4, 21);
      final start = timeIn(zone, 2026, 4, 21, 9);
      // Setup sanity: the device reads the entry's start on another day.
      expect(dateOf(instantOf(start)), isNot(dateOf(tuesday)));
      for (final view in CalendarViewKind.values) {
        final store = memoryStoreIn<String>(
          zone,
          entries: <CalendarEntry<String>>[
            entryOf("a", start, timeIn(zone, 2026, 4, 21, 10)),
          ],
        );
        addTearDown(store.dispose);
        final controller = CalendarController(view: view, selectedDay: tuesday);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: "$view");
        await tester.pumpAndSettle();
        switch (view) {
          case CalendarViewKind.agenda:
            final card = tester.getRect(find.byKey(entryCardKey("a")));
            final header = tester.getRect(
              find.byKey(dayListHeaderKey(tuesday)),
            );
            final next = tester.getRect(
              find.byKey(dayListHeaderKey(DateTime(2026, 4, 22))),
            );
            expect(card.top, greaterThanOrEqualTo(header.bottom - 0.5));
            expect(card.bottom, lessThanOrEqualTo(next.top + 0.5));
          case CalendarViewKind.month:
            final chip = tester.getRect(chipFinder("a"));
            final cell = tester.getRect(find.byKey(monthDayKey(tuesday)));
            expect(cell.contains(chip.center), isTrue);
          case CalendarViewKind.day:
          case CalendarViewKind.week:
            final col = colIn(view, tuesday);
            expect(
              tester.getRect(blockFinder("a", tuesday)).top,
              moreOrLessEquals(rowTop(tester, 9 * 60, col), epsilon: 0.5),
              reason: "$view",
            );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    "VZ3 the times, the header, the strips and the month picker read the "
    "zone's clock",
    (tester) async {
      ensureZones();
      useTallView(tester);
      final (:zone, :clock) = zoneOfAnotherMonth();
      final reading = tz.TZDateTime.from(clock, zone);
      // Setup sanity: the zone's month is not the device's.
      expect(reading.month, isNot(clock.month));
      final today = DateTime(reading.year, reading.month, reading.day);
      final start = timeIn(zone, today.year, today.month, today.day, 9);
      // Setup sanity: the device reads the entry's start at another hour.
      expect(instantOf(start).hour, isNot(9));
      const strings = DefaultCalendarLocalizations();
      for (final view in CalendarViewKind.values) {
        final store = memoryStoreIn<String>(
          zone,
          entries: <CalendarEntry<String>>[
            entryOf(
              "a",
              start,
              timeIn(zone, today.year, today.month, today.day, 10),
            ),
          ],
        );
        addTearDown(store.dispose);
        final controller = CalendarController(view: view);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: () {
                return clock;
              },
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: "$view");
        await tester.pumpAndSettle();
        final title = find.text(strings.shortMonthYear(today));
        expect(title, findsOneWidget, reason: "$view");
        switch (view) {
          case CalendarViewKind.agenda:
            expect(
              find.descendant(
                of: find.byKey(dayListTimeKey("a")),
                matching: find.text("09:00"),
              ),
              findsOneWidget,
            );
            expect(selectedCells(tester), <int>{dateOf(today)});
            await tester.tap(title);
            await tester.pumpAndSettle();
            expect(
              tester.widget<MonthPicker>(find.byType(MonthPicker)).currentMonth,
              DateTime(today.year, today.month),
            );
          case CalendarViewKind.day:
            expect(selectedCells(tester), <int>{dateOf(today)});
            expect(
              find.descendant(
                of: blockFinder("a"),
                matching: find.textContaining("09:00"),
              ),
              findsOneWidget,
            );
          case CalendarViewKind.week:
            // Week's blocks are not detailed, so the default block draws
            // its title alone; Day's block above carries the times.
            break;
          case CalendarViewKind.month:
            final labels = tester
                .widgetList<Semantics>(
                  find.descendant(
                    of: chipFinder("a"),
                    matching: find.byType(Semantics),
                    matchRoot: true,
                  ),
                )
                .map((semantics) {
                  return semantics.properties.label ?? "";
                });
            expect(
              labels.any((label) {
                return label.contains("09:00");
              }),
              isTrue,
              reason: "$labels",
            );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    "VZ4 the calendar opens on the zone's today, marks it, draws the now line "
    "at the zone's wall minute and reads a given today by its date",
    (tester) async {
      ensureZones();
      useTallView(tester);
      final clock = DateTime(2026, 4, 21, 12);
      final zone = zoneFarFromDevice(clock);
      final reading = tz.TZDateTime.from(clock, zone);
      final zoneDay = DateTime(reading.year, reading.month, reading.day);
      // Setup sanity: the zone reads another date than the device.
      expect(dateOf(zoneDay), isNot(dateOf(clock)));
      for (final view in CalendarViewKind.values) {
        final store = memoryStoreIn<String>(zone);
        addTearDown(store.dispose);
        final controller = CalendarController(view: view);
        addTearDown(controller.dispose);
        Widget calendar(DateTime? today) {
          return app(
            CalendarView<String>(
              store: store,
              controller: controller,
              today: today,
              clock: () {
                return clock;
              },
            ),
          );
        }

        await tester.pumpWidget(calendar(null));
        expect(tester.takeException(), isNull, reason: "$view");
        await tester.pumpAndSettle();
        expect(dateOf(controller.selectedDay), dateOf(zoneDay));
        expect(todaysMarked(tester, view), <int>{dateOf(zoneDay)});
        if (view == CalendarViewKind.week) {
          final line = nowLine(tester)!;
          final expected = nowLineAt(
            tester,
            reading.hour * 60 + reading.minute,
            weekColOf(zoneDay),
          );
          expect(line.from.dx, moreOrLessEquals(expected.left));
          expect(line.from.dy, moreOrLessEquals(expected.y));
        }
        await tester.pumpWidget(calendar(DateTime(2026, 4, 21)));
        await tester.pumpAndSettle();
        expect(todaysMarked(tester, view), <int>{numberOf(2026, 4, 21)});
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    "VZ5 the selected day, the visible range, a create range and a move "
    "request are on the zone's clock",
    (tester) async {
      useTallView(tester);
      final zone = apart(5);
      final tuesday = DateTime(2026, 4, 21);
      final store = memoryStoreIn<String>(
        zone,
        entries: <CalendarEntry<String>>[
          entryOf(
            "a",
            timeIn(zone, 2026, 4, 21, 10),
            timeIn(zone, 2026, 4, 21, 11),
          ),
        ],
      );
      addTearDown(store.dispose);
      final controller = CalendarController(
        view: CalendarViewKind.week,
        selectedDay: tuesday,
      );
      addTearDown(controller.dispose);
      final creates = <CalendarCreateRange>[];
      final moves = <CalendarMoveRequest<String>>[];
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
            editable: true,
            onCreateRange: (details) async {
              creates.add(details.range);
            },
            onMoveRequest: (request) async {
              moves.add(request);
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      void expectDays() {
        expect(isDayStartIn(controller.selectedDay, zone), isTrue);
        final range = controller.visibleRange!;
        expect(isDayStartIn(range.first, zone), isTrue);
        expect(isDayStartIn(range.last, zone), isTrue);
        expect(dateOf(range.first), numberOf(2026, 4, 20));
        expect(dateOf(range.last), numberOf(2026, 4, 26));
      }

      expect(dateOf(controller.selectedDay), dateOf(tuesday));
      expectDays();
      controller.selectedDay = DateTime(2026, 4, 23);
      await tester.pumpAndSettle();
      expect(dateOf(controller.selectedDay), numberOf(2026, 4, 23));
      expectDays();
      controller.selectedDay = tuesday;
      await tester.pumpAndSettle();
      expect(dateOf(controller.selectedDay), dateOf(tuesday));
      expectDays();

      final col = weekColOf(tuesday);
      await mouseDrag(
        tester,
        slotCenter(tester, 14 * 60, col),
        slotCenter(tester, 15 * 60, col),
      );
      final range = creates.single;
      expect(range.start, timeIn(zone, 2026, 4, 21, 14));
      expect(range.end, timeIn(zone, 2026, 4, 21, 15, 15));

      final slot = slotExtent(tester, col);
      final gesture = await lift(tester, tester.getCenter(blockFinder("a")));
      await gesture.moveBy(Offset(0.0, 4 * slot));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final requested = moves.single.requested;
      expect(requested.start, timeIn(zone, 2026, 4, 21, 11));
      expect(requested.end, timeIn(zone, 2026, 4, 21, 12));
    },
  );

  testWidgets(
    "VZ6 Week and Day place entries over Havana's skipped and repeated "
    "midnight hours where Havana's wall clock gives them",
    (tester) async {
      ensureZones();
      useTallView(tester);
      final havana = tz.getLocation("America/Havana");
      for (final view in <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.day,
      ]) {
        // 2026-03-08: Havana's clock skips 00:00 to 01:00.
        final skipped = DateTime(2026, 3, 8);
        final skippedStart = dayIn(havana, 2026, 3, 8);
        // Setup sanity: the day starts at 01:00.
        expect(CalendarDates.minuteOfDay(skippedStart), 60);
        // 2026-11-01: Havana's clock repeats 00:00 to 01:00.
        final repeated = DateTime(2026, 11, 1);
        final repeatedStart = dayIn(havana, 2026, 11, 1);
        DateTime after(int minutes) {
          return tz.TZDateTime.from(
            repeatedStart.add(Duration(minutes: minutes)),
            havana,
          );
        }

        // Setup sanity: 75 minutes after the start, the clock reads 00:15
        // again.
        expect(CalendarDates.minuteOfDay(after(75)), 15);
        final store = memoryStoreIn<String>(
          havana,
          entries: <CalendarEntry<String>>[
            entryOf("s", skippedStart, timeIn(havana, 2026, 3, 8, 2)),
            entryOf(
              "t",
              timeIn(havana, 2026, 3, 8, 2),
              timeIn(havana, 2026, 3, 8, 3),
            ),
            entryOf("first", after(15), after(45)),
            entryOf("second", after(75), after(105)),
            entryOf("across", after(30), after(90)),
          ],
        );
        addTearDown(store.dispose);
        final controller = CalendarController(view: view, selectedDay: skipped);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: "$view");
        await tester.pumpAndSettle();
        var col = colIn(view, skipped);
        expect(
          tester.getRect(blockFinder("s", skipped)).top,
          moreOrLessEquals(rowTop(tester, 60, col), epsilon: 0.5),
        );
        expect(
          tester.getRect(blockFinder("t", skipped)).top,
          moreOrLessEquals(rowTop(tester, 120, col), epsilon: 0.5),
        );

        controller.selectedDay = repeated;
        await tester.pumpAndSettle();
        col = colIn(view, repeated);
        final slot = slotExtent(tester, col);
        for (final id in <String>["first", "second"]) {
          final block = tester.getRect(blockFinder(id, repeated));
          expect(
            block.top,
            moreOrLessEquals(rowTop(tester, 15, col), epsilon: 0.5),
            reason: id,
          );
          expect(
            block.height,
            moreOrLessEquals(2 * slot, epsilon: 1.0),
            reason: id,
          );
        }
        final across = tester.getRect(blockFinder("across", repeated));
        expect(
          across.top,
          moreOrLessEquals(rowTop(tester, 30, col), epsilon: 0.5),
        );
        expect(across.height, moreOrLessEquals(4 * slot, epsilon: 1.0));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    "VZ7 a zone change keeps the selected date and Week's and Day's top, "
    "moves today and animates each view's entries",
    (tester) async {
      ensureZones();
      useTallView(tester);
      final a = apart(2);
      final b = apart(8);
      final tuesday = DateTime(2026, 4, 21);
      final wednesday = DateTime(2026, 4, 22);
      final clock = instantOf(timeIn(a, 2026, 4, 21, 20));
      // Setup sanity: B's clock reads 02:00 on Wednesday then.
      expect(tz.TZDateTime.from(clock, b).day, 22);
      List<CalendarEntry<String>> entries() {
        return <CalendarEntry<String>>[
          entryOf("a", timeIn(a, 2026, 4, 21, 22), timeIn(a, 2026, 4, 21, 23)),
          entryOf("b", timeIn(a, 2026, 4, 21, 10), timeIn(a, 2026, 4, 21, 11)),
          entryOf("e", timeIn(a, 2026, 4, 20, 21), timeIn(a, 2026, 4, 20, 22)),
        ];
      }

      Future<
        ({
          MemoryCalendarStore<String> store,
          CalendarController controller,
          List<int> notifies,
          List<DateTime> headerDays,
        })
      >
      open(
        CalendarViewKind view,
        tz.Location? zone, {
        DateTime? now,
        CalendarThemeData? theme,
      }) async {
        final store = memoryStoreIn<String>(zone, entries: entries());
        addTearDown(store.dispose);
        final controller = CalendarController(
          view: view,
          selectedDay: tuesday,
          minSlotHeight: 25.0,
        );
        addTearDown(controller.dispose);
        final headerDays = <DateTime>[];
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: () {
                return now ?? clock;
              },
              headerBuilder: (context, details) {
                headerDays.add(details.day);
                return defaultCalendarHeaderBuilder(context, details);
              },
            ),
            calendarTheme: theme,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final notifies = <int>[0];
        controller.addListener(() {
          notifies[0]++;
        });
        return (
          store: store,
          controller: controller,
          notifies: notifies,
          headerDays: headerDays,
        );
      }

      Future<void> close() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }

      /// The rects of [id]'s Agenda cards.
      List<Rect> cardsOf(String id) {
        return <Rect>[
          for (final card in find.byKey(entryCardKey(id)).evaluate())
            tester.getRect(find.byWidget(card.widget)),
        ];
      }

      /// Whether [card] starts under [day]'s header and above the end of
      /// the next day's, as a card arriving in [day]'s body does while the
      /// body opens over the next header.
      bool arriving(Rect card, DateTime day) {
        final header = tester.getRect(find.byKey(dayListHeaderKey(day)));
        final next = find.byKey(
          dayListHeaderKey(CalendarDates.addDays(day, 1)),
        );
        return card.top >= header.bottom - 0.5 &&
            (next.evaluate().isEmpty || card.top < tester.getRect(next).bottom);
      }

      /// Whether [card] lies under [day]'s header, before the next day's.
      bool under(Rect card, DateTime day) {
        final header = tester.getRect(find.byKey(dayListHeaderKey(day)));
        final next = find.byKey(
          dayListHeaderKey(CalendarDates.addDays(day, 1)),
        );
        return card.top >= header.bottom - 0.5 &&
            (next.evaluate().isEmpty ||
                card.bottom <= tester.getRect(next).top + 0.5);
      }

      // First leg: from A to B, 6 hours ahead, in each view.
      for (final view in CalendarViewKind.values) {
        final timed =
            view == CalendarViewKind.week || view == CalendarViewKind.day;
        final opened = await open(view, a);
        expect(todaysMarked(tester, view), <int>{dateOf(tuesday)});
        if (timed) {
          verticalOf(tester).jumpTo(300.0);
          await tester.pumpAndSettle();
        }
        DateTime? browsed;
        if (view == CalendarViewKind.day) {
          final strip = find.byType(WeekStrip<String>);
          await tester.drag(strip, Offset(-tester.getSize(strip).width, 0.0));
          await tester.pumpAndSettle();
          browsed = opened.headerDays.last;
          // Setup sanity: the drag browsed another week.
          expect(
            CalendarDates.daysBetween(tuesday, browsed),
            greaterThanOrEqualTo(4),
          );
        }
        final col = timed ? colIn(view, tuesday) : 0;
        setStoreZone(opened.store, b);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: "$view");
        await tester.pump(const Duration(milliseconds: 16));
        switch (view) {
          case CalendarViewKind.day:
          case CalendarViewKind.week:
            final top = tester.getRect(blockFinder("b", tuesday)).top;
            expect(top, greaterThan(rowTop(tester, 10 * 60, col)));
            expect(top, lessThan(rowTop(tester, 16 * 60, col)));
          case CalendarViewKind.month:
            final left = tester.getRect(chipFinder("a")).left;
            expect(
              left,
              greaterThan(
                tester.getRect(find.byKey(monthDayKey(tuesday))).left,
              ),
            );
            expect(
              left,
              lessThan(tester.getRect(find.byKey(monthDayKey(wednesday))).left),
            );
          case CalendarViewKind.agenda:
            final cards = cardsOf("a");
            expect(cards, hasLength(2));
            expect(
              cards.any((card) {
                return under(card, tuesday);
              }),
              isTrue,
            );
            expect(
              cards.any((card) {
                return arriving(card, wednesday);
              }),
              isTrue,
            );
        }
        await tester.pumpAndSettle();
        switch (view) {
          case CalendarViewKind.day:
          case CalendarViewKind.week:
            expect(
              tester.getRect(blockFinder("b", tuesday)).top,
              moreOrLessEquals(rowTop(tester, 16 * 60, col), epsilon: 0.5),
            );
            expect(verticalOf(tester).pixels, 300.0);
          case CalendarViewKind.month:
            final chip = tester.getRect(chipFinder("a"));
            expect(
              tester
                  .getRect(find.byKey(monthDayKey(wednesday)))
                  .contains(chip.center),
              isTrue,
            );
          case CalendarViewKind.agenda:
            final cards = cardsOf("a");
            expect(cards, hasLength(1));
            expect(under(cards.single, wednesday), isTrue);
        }
        final selected = opened.controller.selectedDay;
        expect(dateOf(selected), dateOf(tuesday), reason: "$view");
        expect(isDayStartIn(selected, b), isTrue, reason: "$view");
        final range = opened.controller.visibleRange!;
        expect(isDayStartIn(range.first, b), isTrue, reason: "$view");
        expect(isDayStartIn(range.last, b), isTrue, reason: "$view");
        if (browsed == null) {
          expect(todaysMarked(tester, view), <int>{dateOf(wednesday)});
        }
        expect(opened.notifies.single, 1, reason: "$view");
        if (browsed != null) {
          expect(dateOf(opened.headerDays.last), dateOf(browsed));
          final strip = tester.getRect(find.byType(WeekStrip<String>));
          final cell = tester.getRect(find.byKey(weekStripDayKey(browsed)));
          expect(strip.contains(cell.center), isTrue);
          // The browsed week holds no today: the strip brought back to the
          // selected day's week shows it.
          expect(todaysMarked(tester, view), isEmpty);
          opened.controller.goTo(opened.controller.selectedDay);
          await tester.pumpAndSettle();
          expect(todaysMarked(tester, view), <int>{dateOf(wednesday)});
        }
        if (view == CalendarViewKind.week) {
          // From B to no zone.
          final device = clock.hour * 60 + clock.minute;
          final onB = tz.TZDateTime.from(clock, b);
          // Setup sanity: B's clock reads another minute.
          expect(onB.hour * 60 + onB.minute, isNot(device));
          setStoreZone(opened.store, null);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final plain = opened.controller.selectedDay;
          expect(plain is tz.TZDateTime, isFalse);
          expect(plain, tuesday);
          expect(todaysMarked(tester, view), <int>{dateOf(clock)});
          final line = nowLine(tester)!;
          final expected = nowLineAt(tester, device, weekColOf(clock));
          expect(line.from.dx, moreOrLessEquals(expected.left));
          expect(line.from.dy, moreOrLessEquals(expected.y));
        }
        await close();

        // Under a theme whose motion is off, at the new place at once.
        final still = await open(
          view,
          a,
          theme: CalendarThemeData(motionDuration: Duration.zero),
        );
        setStoreZone(still.store, b);
        await tester.pump();
        switch (view) {
          case CalendarViewKind.day:
          case CalendarViewKind.week:
            expect(
              tester.getRect(blockFinder("b", tuesday)).top,
              moreOrLessEquals(rowTop(tester, 16 * 60, col), epsilon: 0.5),
            );
          case CalendarViewKind.month:
            final chip = tester.getRect(chipFinder("a"));
            expect(
              tester
                  .getRect(find.byKey(monthDayKey(wednesday)))
                  .contains(chip.center),
              isTrue,
            );
          case CalendarViewKind.agenda:
            // The leaving card takes no room from the first frame, and its
            // row goes at the next, so the arriving card moves no further.
            final arrived = cardsOf("a").where((card) {
              return under(card, wednesday);
            }).toList();
            expect(arrived, hasLength(1));
            await tester.pumpAndSettle();
            expect(cardsOf("a"), <Rect>[arrived.single]);
        }
        await close();
      }

      // In Agenda, "e" moves from the rows above the top day onto it and
      // back, which grows the rows above the top day.
      final agenda = await open(CalendarViewKind.agenda, a);
      setStoreZone(agenda.store, b);
      await tester.pumpAndSettle();
      // Setup sanity: "e" lies in the top day's section, under the top of
      // its pinned header, which can draw over the section's first card.
      final moved = cardsOf("e").single;
      expect(
        moved.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(dayListHeaderKey(tuesday))).top,
        ),
      );
      expect(
        moved.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(dayListHeaderKey(wednesday))).top + 0.5,
        ),
      );
      agenda.notifies[0] = 0;
      setStoreZone(agenda.store, a);
      await tester.pumpAndSettle();
      expect(dateOf(agenda.controller.selectedDay), dateOf(tuesday));
      expect(isDayStartIn(agenda.controller.selectedDay, a), isTrue);
      expect(agenda.notifies.single, 1);
      await close();

      // Second leg: zones 24 hours apart, whose readings and day starts are
      // the same instants.
      final utcNoon = DateTime.utc(2026, 4, 21, 12);
      for (final view in CalendarViewKind.values) {
        final opened = await open(view, gmtZone(-11), now: utcNoon);
        expect(todaysMarked(tester, view), <int>{dateOf(tuesday)});
        setStoreZone(opened.store, gmtZone(13));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(todaysMarked(tester, view), <int>{
          dateOf(wednesday),
        }, reason: "$view");
        await close();
      }

      // Back to A one frame into the change to B, while its motion runs.
      Map<String, List<Rect>> placesIn(CalendarViewKind view) {
        return <String, List<Rect>>{
          for (final id in <String>["a", "b", "e"])
            id: <Rect>[
              for (final element in entryFinder(view, id).evaluate())
                tester.getRect(find.byWidget(element.widget)),
            ],
        };
      }

      for (final view in CalendarViewKind.values) {
        final opened = await open(view, a);
        final atA = placesIn(view);
        setStoreZone(opened.store, b);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        // Setup sanity: the change to B is under way.
        expect(placesIn(view), isNot(atA), reason: "$view");
        setStoreZone(opened.store, a);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: "$view");
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: "$view");
        expect(placesIn(view), atA, reason: "$view");
        await close();
      }
    },
  );

  testWidgets(
    "VZ8 a zone change ends a move, a resize and a create drag in flight, "
    "which request and create nothing",
    (tester) async {
      useTallView(tester);
      final a = apart(2);
      final b = apart(8);
      final tuesday = DateTime(2026, 4, 21);

      // A drag in flight at the zone set, in Week and in Day.
      for (final view in <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.day,
      ]) {
        for (final kind in <String>["move", "resize", "create"]) {
          var changes = 0;
          final moves = <CalendarMoveRequest<String>>[];
          final creates = <CalendarCreateRange>[];
          final store = memoryStoreIn<String>(
            a,
            entries: <CalendarEntry<String>>[
              entryOf(
                "a",
                timeIn(a, 2026, 4, 21, 10),
                timeIn(a, 2026, 4, 21, 11),
              ),
            ],
            onChanged: (old, entry) {
              changes++;
            },
          );
          addTearDown(store.dispose);
          final controller = CalendarController(
            view: view,
            selectedDay: tuesday,
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            app(
              CalendarView<String>(
                store: store,
                controller: controller,
                clock: fixedClock,
                editable: true,
                onCreateRange: (details) async {
                  creates.add(details.range);
                },
                onMoveRequest: (request) async {
                  moves.add(request);
                  await store.requestMove(request.requested);
                },
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
          final col = colIn(view, tuesday);
          final slot = slotExtent(tester, col);
          final TestGesture gesture;
          switch (kind) {
            case "move":
              gesture = await lift(tester, tester.getCenter(blockFinder("a")));
              await gesture.moveBy(Offset(0.0, 2 * slot));
            case "resize":
              await select(tester, blockFinder("a"));
              final rect = tester.getRect(blockFinder("a"));
              gesture = await tester.startGesture(
                Offset(rect.center.dx, rect.bottom - 3.0),
              );
              await gesture.moveBy(Offset(0.0, 2 * slot));
            default:
              gesture = await tester.startGesture(
                slotCenter(tester, 14 * 60, col),
                kind: PointerDeviceKind.mouse,
              );
              await gesture.moveTo(slotCenter(tester, 15 * 60, col));
          }
          await tester.pump();
          setStoreZone(store, b);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: "$view $kind");
          await gesture.up();
          await tester.pumpAndSettle();
          expect(moves, isEmpty, reason: "$view $kind");
          expect(creates, isEmpty, reason: "$view $kind");
          expect(changes, 0, reason: "$view $kind");
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }

      // A move sent to a caching store, whose write is held across the
      // zone set.
      {
        final source = HeldWrites(<CalendarEntry<String>>[
          entryOf("a", timeIn(a, 2026, 4, 21, 10), timeIn(a, 2026, 4, 21, 11)),
        ]);
        final store = cachingStoreIn<String>(a, dataSource: source);
        addTearDown(store.dispose);
        final controller = CalendarController(
          view: CalendarViewKind.week,
          selectedDay: tuesday,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
              editable: true,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final col = weekColOf(tuesday);
        final slot = slotExtent(tester, col);
        // A pending block shows an indicator that repeats until its write
        // completes, so the frames run for a bounded time, past the motion.
        Future<void> settleHeld() async {
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }

        final gesture = await lift(tester, tester.getCenter(blockFinder("a")));
        await gesture.moveBy(Offset(0.0, 8 * slot));
        await tester.pump();
        await gesture.up();
        await settleHeld();
        expect(source.held, hasLength(1));
        expect(
          tester.getRect(blockFinder("a", tuesday)).top,
          moreOrLessEquals(rowTop(tester, 12 * 60, col), epsilon: 0.5),
        );
        setStoreZone(store, b);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await settleHeld();
        // Before the write completes, at its requested time on B's clock.
        expect(
          tester.getRect(blockFinder("a", tuesday)).top,
          moreOrLessEquals(rowTop(tester, 18 * 60, col), epsilon: 0.5),
        );
        source.completeWrites();
        await tester.pumpAndSettle();
        expect(
          tester.getRect(blockFinder("a", tuesday)).top,
          moreOrLessEquals(rowTop(tester, 18 * 60, col), epsilon: 0.5),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }

      // A Week move drag in flight when the calendar is built over another
      // store of another zone.
      {
        final moves = <CalendarMoveRequest<String>>[];
        final first = memoryStoreIn<String>(
          a,
          entries: <CalendarEntry<String>>[
            entryOf(
              "a",
              timeIn(a, 2026, 4, 21, 10),
              timeIn(a, 2026, 4, 21, 11),
            ),
          ],
        );
        addTearDown(first.dispose);
        final second = memoryStoreIn<String>(
          b,
          entries: <CalendarEntry<String>>[
            entryOf(
              "a",
              timeIn(b, 2026, 4, 21, 13),
              timeIn(b, 2026, 4, 21, 14),
            ),
          ],
        );
        addTearDown(second.dispose);
        final controller = CalendarController(
          view: CalendarViewKind.week,
          selectedDay: tuesday,
        );
        addTearDown(controller.dispose);
        Widget calendar(CalendarStore<String> store) {
          return app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
              editable: true,
              onMoveRequest: (request) async {
                moves.add(request);
              },
            ),
          );
        }

        await tester.pumpWidget(calendar(first));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final col = weekColOf(tuesday);
        final slot = slotExtent(tester, col);
        final gesture = await lift(tester, tester.getCenter(blockFinder("a")));
        await gesture.moveBy(Offset(0.0, 2 * slot));
        await tester.pump();
        await tester.pumpWidget(calendar(second));
        expect(tester.takeException(), isNull);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(moves, isEmpty);
        expect(
          tester.getRect(blockFinder("a", tuesday)).top,
          moreOrLessEquals(rowTop(tester, 13 * 60, col), epsilon: 0.5),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }

      // In Week, a store of another zone and a controller of the next week
      // given in one build: the new days sync unanimated.
      {
        final first = memoryStoreIn<String>(
          a,
          entries: <CalendarEntry<String>>[
            entryOf(
              "a",
              timeIn(a, 2026, 4, 21, 10),
              timeIn(a, 2026, 4, 21, 11),
            ),
          ],
        );
        addTearDown(first.dispose);
        final thursday = DateTime(2026, 4, 30);
        final second = memoryStoreIn<String>(
          b,
          entries: <CalendarEntry<String>>[
            entryOf(
              "a",
              timeIn(b, 2026, 4, 30, 14),
              timeIn(b, 2026, 4, 30, 15),
            ),
          ],
        );
        addTearDown(second.dispose);
        final firstController = CalendarController(
          view: CalendarViewKind.week,
          selectedDay: tuesday,
        );
        addTearDown(firstController.dispose);
        final secondController = CalendarController(
          view: CalendarViewKind.week,
          selectedDay: DateTime(2026, 4, 28),
        );
        addTearDown(secondController.dispose);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: first,
              controller: firstController,
              clock: fixedClock,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(blockFinder("a", tuesday), findsOneWidget);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: second,
              controller: secondController,
              clock: fixedClock,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(blockFinder("a", tuesday), findsNothing);
        final jumped = tester.getRect(blockFinder("a", thursday));
        await tester.pumpAndSettle();
        expect(tester.getRect(blockFinder("a", thursday)), jumped);
        expect(
          jumped.top,
          moreOrLessEquals(
            rowTop(tester, 14 * 60, weekColOf(thursday)),
            epsilon: 0.5,
          ),
        );
      }
    },
  );

  testWidgets(
    "VZ9 a running create's mark keeps its instants across a zone change",
    (tester) async {
      useTallView(tester);
      final a = apart(3);
      final c = apart(-3);
      final tuesday = DateTime(2026, 4, 21);
      final wednesday = DateTime(2026, 4, 22);
      for (final view in <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.month,
        CalendarViewKind.agenda,
      ]) {
        final store = memoryStoreIn<String>(a);
        addTearDown(store.dispose);
        final controller = CalendarController(view: view, selectedDay: tuesday);
        addTearDown(controller.dispose);
        final creates = <CalendarCreateRange>[];
        final done = Completer<void>();
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
              editable: true,
              onCreateRange: (details) {
                creates.add(details.range);
                return done.future;
              },
              addButtonBuilder: (context, details) {
                return GestureDetector(
                  onTap: details.onPressed,
                  child: const Text("add"),
                );
              },
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: "$view");
        await tester.pumpAndSettle();
        switch (view) {
          case CalendarViewKind.week:
            final col = weekColOf(wednesday);
            await mouseDrag(
              tester,
              slotCenter(tester, 14 * 60, col),
              slotCenter(tester, 15 * 60, col),
            );
            final viewport = gridViewport(tester);
            double markTop(int minute) {
              return viewport
                      .visibleCellRect(gridRowOf(tester, minute), col)
                      .top +
                  1.0;
            }

            expect(strokedRects(tester).single.top, markTop(14 * 60));
            setStoreZone(store, c);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(strokedRects(tester).single.top, markTop(8 * 60));
            done.complete();
            await tester.pumpAndSettle();
            expect(strokedRects(tester), isEmpty);
          case CalendarViewKind.month:
            await holdInPlace(
              tester,
              tester.getCenter(find.byKey(monthDayKey(wednesday))),
            );
            final mark = createMarkIn(tester, find.byType(MonthBoard<String>));
            expect(
              createMarksUnder(find.byKey(monthDayKey(wednesday)), mark),
              findsOneWidget,
            );
            setStoreZone(store, c);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              createMarksUnder(find.byKey(monthDayKey(wednesday)), mark),
              findsNothing,
            );
            expect(
              createMarksUnder(find.byKey(monthDayKey(tuesday)), mark),
              findsOneWidget,
            );
            done.complete();
            await tester.pumpAndSettle();
            expect(
              createMarksUnder(find.byType(MonthBoard<String>), mark),
              findsNothing,
            );
          case CalendarViewKind.agenda:
          case CalendarViewKind.day:
            await tester.tap(
              find.descendant(
                of: find.byKey(dayListGapKey(wednesday, 0)),
                matching: find.text("add"),
              ),
            );
            await tester.pumpAndSettle();
            final mark = createMarkIn(tester, find.byType(DayList<String>));
            expect(
              createMarksUnder(find.byKey(dayListGapKey(wednesday, 0)), mark),
              findsOneWidget,
            );
            setStoreZone(store, c);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              createMarksUnder(find.byKey(dayListGapKey(wednesday, 0)), mark),
              findsNothing,
            );
            expect(
              createMarksUnder(find.byKey(dayListGapKey(tuesday, 0)), mark),
              findsOneWidget,
            );
            done.complete();
            await tester.pumpAndSettle();
            expect(
              createMarksUnder(find.byType(DayList<String>), mark),
              findsNothing,
            );
        }
        // Setup sanity: the create started at the start of A's Wednesday,
        // or in Week at A's 14:00 that day.
        expect(dateOf(creates.single.start), dateOf(wednesday));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    "VZ10 a Week move drag asks the zone the same lookups per pointer move "
    "with 1 entry and with 500, and none within one slot",
    (tester) async {
      useTallView(tester);
      final tuesday = DateTime(2026, 4, 21);

      /// The lookups each of a move drag's pointer moves across a slot
      /// asks, with [count] entries, after checking that moves within a
      /// slot of a move, a resize and a create drag ask none.
      Future<List<int>> lookupsWith(int count) async {
        final zone = CountingLocation(apart(5));
        final entries = <CalendarEntry<String>>[
          entryOf(
            "a",
            timeIn(zone, 2026, 4, 21, 10),
            timeIn(zone, 2026, 4, 21, 11),
          ),
          for (var index = 1; index < count; index++)
            entryOf(
              "e$index",
              timeIn(zone, 2026, 4, 20 + index % 7, (index ~/ 7) % 20),
              timeIn(zone, 2026, 4, 20 + index % 7, (index ~/ 7) % 20, 30),
            ),
        ];
        final store = memoryStoreIn<String>(zone, entries: entries);
        addTearDown(store.dispose);
        final controller = CalendarController(
          view: CalendarViewKind.week,
          selectedDay: tuesday,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
              editable: true,
              onCreateRange: (details) async {},
              onMoveRequest: (request) async {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final col = weekColOf(tuesday);
        final slot = slotExtent(tester, col);
        final quarter = Offset(0.0, slot / 4);

        Future<void> expectNoneWithin(TestGesture gesture, String drag) async {
          for (final by in <Offset>[quarter, -quarter, quarter, -quarter]) {
            final before = zone.lookups;
            await gesture.moveBy(by);
            await tester.pump();
            expect(zone.lookups - before, 0, reason: "$drag $count");
          }
        }

        // A move.
        final move = await lift(tester, tester.getCenter(blockFinder("a")));
        await move.moveBy(Offset(0.0, slot));
        await tester.pump();
        final perMove = <int>[];
        for (var step = 0; step < 3; step++) {
          final before = zone.lookups;
          await move.moveBy(Offset(0.0, slot));
          await tester.pump();
          perMove.add(zone.lookups - before);
        }
        await expectNoneWithin(move, "move");
        await move.up();
        await tester.pumpAndSettle();

        // A resize.
        await select(tester, blockFinder("a"));
        final rect = tester.getRect(blockFinder("a"));
        final resize = await tester.startGesture(
          Offset(rect.center.dx, rect.bottom - 3.0),
        );
        await resize.moveBy(Offset(0.0, slot));
        await tester.pump();
        // A resize snaps the end it holds to the nearest slot line, so the
        // moves below keep that end within a quarter slot of the line it
        // reached.
        await expectNoneWithin(resize, "resize");
        await resize.up();
        await tester.pumpAndSettle();

        // A create drag, over a day with no entry at 14:00.
        final thursday = weekColOf(DateTime(2026, 4, 23));
        final create = await tester.startGesture(
          slotCenter(tester, 21 * 60, thursday),
          kind: PointerDeviceKind.mouse,
        );
        await create.moveBy(Offset(0.0, slot));
        await tester.pump();
        await expectNoneWithin(create, "create");
        await create.up();
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        return perMove;
      }

      final one = await lookupsWith(1);
      final many = await lookupsWith(500);
      expect(one, <int>[6, 6, 6]);
      expect(many, <int>[6, 6, 6]);
    },
  );

  testWidgets(
    "VZ11 a Week layout asks the zone 2 lookups more per piece it lays out",
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800.0, 600.0);
      addTearDown(tester.view.reset);
      final tuesday = DateTime(2026, 4, 21);

      /// The lookups a set of the store's hours asks with [count] one-day
      /// entries ending off midnight, below the viewport.
      Future<int> lookupsWith(int count) async {
        final zone = CountingLocation(apart(5));
        final store = memoryStoreIn<String>(
          zone,
          entries: <CalendarEntry<String>>[
            for (var index = 0; index < count; index++)
              entryOf(
                "e$index",
                timeIn(zone, 2026, 4, 21, 22),
                timeIn(zone, 2026, 4, 21, 23),
              ),
          ],
        );
        addTearDown(store.dispose);
        final controller = CalendarController(
          view: CalendarViewKind.week,
          selectedDay: tuesday,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          app(
            CalendarView<String>(
              store: store,
              controller: controller,
              clock: () {
                return instantOf(timeIn(zone, 2026, 4, 21, 8));
              },
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        // Setup sanity: the entries lie below the viewport.
        expect(blockFinder("e0"), findsNothing);
        final before = zone.lookups;
        store.hours = CalendarDayHours(60, CalendarDates.minutesPerDay);
        await tester.pump();
        final lookups = zone.lookups - before;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        return lookups;
      }

      final one = await lookupsWith(1);
      final many = await lookupsWith(500);
      expect(many - one, 998);
    },
  );

  test("VZ12 no document says a calendar refuses a zoned store, and "
      "CalendarView's doc and the README name the read-ahead", () {
    final grep = Process.runSync("git", <String>[
      "grep",
      "-n",
      "refuses a store with a zone",
      "--",
      "README.md",
      "CHANGELOG.md",
      "lib",
    ]);
    expect((grep.stdout as String).trim(), isEmpty);
    final source = File(
      "lib/calendar/composition/calendar_view.dart",
    ).readAsStringSync();
    final doc = docOf(source, "class CalendarView<T>");
    expect(doc, contains("draws on its store's zone"));
    expect(doc, contains("readAhead"));
    final storeDoc = docOf(source, "final CalendarStore<T> store;");
    for (final text in <String>[doc, storeDoc]) {
      for (final refusal in <String>[
        "is refused",
        "store with one is refused",
        "for a store with a zone",
        "does not draw on",
        "draws no entry on a store's zone",
      ]) {
        expect(text, isNot(contains(refusal)));
      }
    }
    final readme = File("README.md").readAsStringSync();
    expect(readme, contains("readAhead: 2"));
  });
}

/// The doc comment right above the line of [source] that starts with
/// [declaration], its lines joined by spaces with their `///` dropped.
String docOf(String source, String declaration) {
  final lines = source.split("\n");
  final at = lines.indexWhere((line) {
    return line.trimLeft().startsWith(declaration);
  });
  expect(at, greaterThan(0), reason: declaration);
  final doc = <String>[];
  for (var index = at - 1; index >= 0; index--) {
    final line = lines[index].trim();
    if (!line.startsWith("///")) {
      break;
    }
    doc.insert(0, line.substring(3).trim());
  }
  return doc.join(" ");
}
