/// The timed grid on start and end: an entry drawn as one piece per shown
/// day at its exact minutes, the gestures on pieces (a move keeping the
/// entry's elapsed duration, resizes, the handles of the first and the
/// last piece, a lift of a pieced entry), the create ranges across days and
/// their day limit, the wall-clock rows of the local zone's DST days, the
/// slot length, and a slot length or hours change during a gesture.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/move_request.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/timed_grid_layout.dart';

import '../../scheduling/dst_days.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime saturday = DateTime(2026, 4, 25);

/// [day] at [hour] and [minute] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
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

/// A grid the tests pump: Week over the seven days from [first], under a
/// day header, or Day over [first] alone, with none; its slots of
/// [slotMinutes] over [hours].
class Shown {
  const Shown.week(
    this.first, {
    this.hours = CalendarDayHours.allDay,
    this.slotMinutes = 15,
  }) : week = true;

  const Shown.day(
    this.first, {
    this.hours = CalendarDayHours.allDay,
    this.slotMinutes = 15,
  }) : week = false;

  final DateTime first;
  final bool week;
  final CalendarDayHours hours;
  final int slotMinutes;

  /// The row of the first slot of the grid shown now, under the day header
  /// in Week, the all-day strip's rows and the room above the slots: its
  /// board's row count less its slot rows and the room below them.
  int get firstSlotRow {
    final grid =
        find.byType(TimedGrid<String>).evaluate().single.widget
            as TimedGrid<String>;
    final board =
        find.byType(Board<GridKey, GridShape<String>>).evaluate().single.widget
            as Board<GridKey, GridShape<String>>;
    return board.controller.rows.axis.trackCount -
        grid.hours.slotCountOf(grid.slotMinutes) -
        1;
  }

  /// The rows above the first slot of an editable grid with no bar: the
  /// day header in Week, the room above the all-day strip, the strip's one
  /// empty row and the room above the slots.
  int get editLeadingRows {
    return (week ? 1 : 0) + 1 + 1 + 1;
  }

  /// The row of the slot starting at [minute].
  int rowOf(int minute) {
    return firstSlotRow + (minute - hours.start) ~/ slotMinutes;
  }

  /// The column of [day], which the grid shows.
  int colOf(DateTime day) {
    return week ? 1 + CalendarDates.daysBetween(first, day) : 1;
  }

  String get name {
    return week ? "Week" : "Day";
  }
}

/// The grid's viewport.
RenderBoardViewport<GridKey> viewportOf(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
}

/// The global rect of the grid's cell at [row] and [col].
Rect cellRect(WidgetTester tester, int row, int col) {
  final viewport = viewportOf(tester);
  final rect = viewport.rectOfCell(row, col)!;
  return viewport.localToGlobal(rect.topLeft) & rect.size;
}

/// The global rect of the slot starting at [minute] in [day]'s column.
Rect slotRect(WidgetTester tester, Shown shown, DateTime day, int minute) {
  return cellRect(tester, shown.rowOf(minute), shown.colOf(day));
}

/// The number of rows of the grid's board.
int rowCount(WidgetTester tester) {
  return tester
      .widget<Board<GridKey, GridShape<String>>>(
        find.byType(Board<GridKey, GridShape<String>>),
      )
      .controller
      .rows
      .axis
      .trackCount;
}

/// A canvas that records the rects drawn on it with their paints. Every
/// other call is ignored.
class RecordingCanvas implements Canvas {
  final List<({Rect rect, Paint paint})> rects = <({Rect rect, Paint paint})>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add((rect: rect, paint: paint));
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

/// Whether the grid's background marks a range of slots or a landing,
/// each of which it edges with a stroke.
bool marksSlots(WidgetTester tester) {
  final viewport = viewportOf(tester);
  final canvas = RecordingCanvas();
  viewport.background!.paint(canvas, viewport);
  return canvas.rects.any((record) {
    return record.paint.style == PaintingStyle.stroke;
  });
}

/// The block of [id]'s piece on [day].
Finder blockFinder(String id, DateTime day) {
  return find.byKey(blockKey(id, day));
}

/// Every block of [id], on whichever day.
Finder blocksOf(String id) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("block-$id@");
  });
}

/// An in-memory store that counts its [entriesBetween] calls and the
/// changes it applies.
final class CountingStore extends MemoryCalendarStore<String> {
  CountingStore({super.entries, super.hours}) : super();

  int betweenCalls = 0;

  int changes = 0;

  @override
  List<CalendarShownEntry<String>> entriesBetween(
    DateTime first,
    DateTime last,
  ) {
    betweenCalls++;
    return super.entriesBetween(first, last);
  }

  @override
  void notifyListeners() {
    changes++;
    super.notifyListeners();
  }
}

/// A data source that answers each read within the call with the entries
/// having any part in its days, and holds each replace until the test
/// completes it.
class HeldSource implements CalendarDataSource<String> {
  HeldSource(this.entries);

  final List<CalendarEntry<String>> entries;

  final List<Completer<CalendarEntry<String>>> replaces =
      <Completer<CalendarEntry<String>>>[];

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final from = CalendarDates.dayNumber(first);
    final to = CalendarDates.dayNumber(last);
    return SynchronousFuture<List<CalendarEntry<String>>>(
      <CalendarEntry<String>>[
        for (final entry in entries)
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
    final completer = Completer<CalendarEntry<String>>();
    replaces.add(completer);
    return completer.future;
  }

  @override
  Future<void> delete(String id) {
    return SynchronousFuture<void>(null);
  }
}

/// What a test pumps: the grid of [shown] over [store], in a view 800 wide
/// and 2000 tall, where every slot of the day shows; [creates] records each
/// create range it reports, and where [recordsMoves] is true, [moves] each
/// move and resize request it lands, which the store then does not write.
/// [hours] and [slotMinutes] start as [shown]'s, and [rebuild] builds the
/// grid again with them. The grid's policy is the unrestricted one,
/// combined with a [DayLimitPolicy] of [maxDayCount] where it is given and
/// with a [NoOverlapsPolicy] where [allowsOverlaps] is false.
class Harness {
  Harness(
    this.store,
    this.shown, {
    this.maxDayCount,
    this.editable = true,
    this.allowsOverlaps = true,
    this.recordsMoves = false,
  }) : hours = shown.hours,
       slotMinutes = shown.slotMinutes;

  final CalendarStore<String> store;
  final Shown shown;
  final int? maxDayCount;
  final bool editable;
  final bool allowsOverlaps;
  final bool recordsMoves;

  CalendarEditPolicy<String> get policy {
    final limit = maxDayCount;
    return CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
      const UnrestrictedEditPolicy<String>(),
      if (limit != null) DayLimitPolicy<String>(limit),
      if (!allowsOverlaps) const NoOverlapsPolicy<String>(),
    ]);
  }

  CalendarDayHours hours;
  int slotMinutes;

  final List<CalendarCreateRange> creates = <CalendarCreateRange>[];
  final List<CalendarMoveRequest<String>> moves =
      <CalendarMoveRequest<String>>[];
  final ValueNotifier<CalendarNow> now = ValueNotifier<CalendarNow>(
    CalendarNow(time: DateTime(2026, 1, 5, 9), today: DateTime(2026, 1, 5)),
  );

  TimedGrid<String> grid() {
    return TimedGrid<String>(
      key: ObjectKey(this),
      store: store,
      firstDay: shown.first,
      dayCount: shown.week ? 7 : 1,
      selectedDay: shown.first,
      now: now,
      onSelectDay: (day) {},
      onOpenEntry: (id) {},
      onCreate: (details) async {
        creates.add(details.range);
      },
      onMoveRequest: recordsMoves
          ? (request) async {
              moves.add(request);
            }
          : null,
      editable: editable,
      editPolicy: policy,
      hours: hours,
      slotMinutes: slotMinutes,
      showsDayHeader: shown.week,
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 2000.0);
    addTearDown(tester.view.reset);
    addTearDown(now.dispose);
    await tester.pumpWidget(MaterialApp(home: grid()));
    await tester.pumpAndSettle();
  }

  /// Builds the grid again, the same grid with [hours] and [slotMinutes] as
  /// they are now, and pumps one frame.
  Future<void> rebuild(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: grid()));
  }
}

/// A store holding [entries], disposed at the test's end.
CountingStore storeOf(
  List<CalendarEntry<String>> entries, {
  CalendarDayHours hours = CalendarDayHours.allDay,
}) {
  final store = CountingStore(entries: entries, hours: hours);
  addTearDown(store.dispose);
  return store;
}

/// The requested start and end of each of [moves], in order.
List<(DateTime, DateTime)> timesOf(List<CalendarMoveRequest<String>> moves) {
  return <(DateTime, DateTime)>[
    for (final move in moves) (move.requested.start, move.requested.end),
  ];
}

/// Long-presses [at], lifting the block there, and returns the gesture.
Future<TestGesture> lift(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  return gesture;
}

/// Lifts the block [block] at its centre, moves it by [by], drops it, and
/// lets the drop settle.
Future<void> moveBlock(WidgetTester tester, Finder block, Offset by) async {
  final gesture = await lift(tester, tester.getCenter(block));
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Long-presses [block] and lets go where it lifted, which selects it.
Future<void> selectBlock(WidgetTester tester, Finder block) async {
  final gesture = await lift(tester, tester.getCenter(block));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Drags the bottom edge of the selected [block], pressed 3 px above its
/// bottom, by [by], and lets go.
Future<void> resizeEnd(WidgetTester tester, Finder block, Offset by) async {
  final rect = tester.getRect(block);
  final gesture = await tester.startGesture(
    Offset(rect.center.dx, rect.bottom - 3.0),
  );
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Drags the top edge of the selected [block], pressed 3 px below its
/// top, by [by], and lets go.
Future<void> resizeStart(WidgetTester tester, Finder block, Offset by) async {
  final rect = tester.getRect(block);
  final gesture = await tester.startGesture(
    Offset(rect.center.dx, rect.top + 3.0),
  );
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A mouse drag from [from] to [to], let go there: a create drag.
Future<void> createDrag(WidgetTester tester, Offset from, Offset to) async {
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

void main() {
  final views = <Shown Function(DateTime day)>[
    (day) {
      return Shown.week(monday);
    },
    (day) {
      return Shown.day(day);
    },
  ];

  testWidgets("TP1 in Week and in Day, Monday 22:00 to Tuesday 02:00 draws "
      "Monday's block from the 22:00 row to the day's end and Tuesday's "
      "from the day's start to the 02:00 row", (tester) async {
    final night = entryOf("night", at(monday, 22), at(tuesday, 2));
    for (final day in <DateTime>[monday, tuesday]) {
      for (final view in views) {
        final shown = view(day);
        final harness = Harness(storeOf(<CalendarEntry<String>>[night]), shown);
        await harness.pump(tester);
        final last = shown.rowOf(CalendarDates.minutesPerDay - 15);
        if (shown.week || day == monday) {
          final rect = tester.getRect(blockFinder("night", monday));
          final col = shown.colOf(monday);
          expect(
            rect.top,
            moreOrLessEquals(cellRect(tester, shown.rowOf(22 * 60), col).top),
            reason: shown.name,
          );
          expect(
            rect.bottom,
            moreOrLessEquals(cellRect(tester, last, col).bottom),
            reason: shown.name,
          );
        }
        if (shown.week || day == tuesday) {
          final rect = tester.getRect(blockFinder("night", tuesday));
          final col = shown.colOf(tuesday);
          expect(
            rect.top,
            moreOrLessEquals(cellRect(tester, shown.firstSlotRow, col).top),
            reason: shown.name,
          );
          expect(
            rect.bottom,
            moreOrLessEquals(cellRect(tester, shown.rowOf(2 * 60), col).top),
            reason: shown.name,
          );
        }
        expect(blocksOf("night"), findsNWidgets(shown.week ? 2 : 1));
      }
    }
  });

  testWidgets("TP2 in Week and in Day, Monday 10:00 to Wednesday 12:00 draws "
      "three blocks, each at its piece's rows", (tester) async {
    final long = entryOf("long", at(monday, 10), at(wednesday, 12));
    final pieces = <DateTime, (int, int)>{
      monday: (10 * 60, CalendarDates.minutesPerDay),
      tuesday: (0, CalendarDates.minutesPerDay),
      wednesday: (0, 12 * 60),
    };
    for (final day in pieces.keys) {
      for (final view in views) {
        final shown = view(day);
        final harness = Harness(storeOf(<CalendarEntry<String>>[long]), shown);
        await harness.pump(tester);
        expect(blocksOf("long"), findsNWidgets(shown.week ? 3 : 1));
        for (final MapEntry(key: pieceDay, value: (start, end))
            in pieces.entries) {
          if (!shown.week && pieceDay != day) {
            continue;
          }
          final col = shown.colOf(pieceDay);
          final rect = tester.getRect(blockFinder("long", pieceDay));
          expect(
            rect.top,
            moreOrLessEquals(cellRect(tester, shown.rowOf(start), col).top),
            reason: "${shown.name} $pieceDay",
          );
          expect(
            rect.bottom,
            moreOrLessEquals(
              cellRect(tester, shown.rowOf(end - 15), col).bottom,
            ),
            reason: "${shown.name} $pieceDay",
          );
          expect(
            rect.left,
            moreOrLessEquals(cellRect(tester, shown.firstSlotRow, col).left),
            reason: "${shown.name} $pieceDay",
          );
        }
      }
    }
  });

  testWidgets("TP3 in Week and in Day, an entry ending at Tuesday's start "
      "builds no Tuesday block, and its Monday block ends at the last row's "
      "bottom", (tester) async {
    final late = entryOf("late", at(monday, 22), tuesday);
    for (final view in views) {
      for (final day in <DateTime>[monday, tuesday]) {
        final shown = view(day);
        final harness = Harness(storeOf(<CalendarEntry<String>>[late]), shown);
        await harness.pump(tester);
        expect(blockFinder("late", tuesday), findsNothing, reason: shown.name);
        if (shown.week || day == monday) {
          final col = shown.colOf(monday);
          expect(
            tester.getRect(blockFinder("late", monday)).bottom,
            moreOrLessEquals(
              cellRect(
                tester,
                shown.rowOf(CalendarDates.minutesPerDay - 15),
                col,
              ).bottom,
            ),
            reason: shown.name,
          );
        } else {
          expect(blocksOf("late"), findsNothing);
        }
      }
    }
  });

  testWidgets("TP4 at slot 15, 09:10 to 09:50 lies from 10/15 to 50/15 of a "
      "slot below the 09:00 row's top", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(
      storeOf(<CalendarEntry<String>>[
        entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50)),
      ]),
      shown,
    );
    await harness.pump(tester);
    final nine = slotRect(tester, shown, tuesday, 9 * 60);
    final rect = tester.getRect(blockFinder("task", tuesday));
    expect(
      rect.top,
      moreOrLessEquals(nine.top + nine.height * 10 / 15, epsilon: 0.5),
    );
    expect(
      rect.bottom,
      moreOrLessEquals(nine.top + nine.height * 50 / 15, epsilon: 0.5),
    );
  });

  testWidgets("TP5 09:00-09:05 and 09:10-09:15 each span the column's full "
      "width", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(
      storeOf(<CalendarEntry<String>>[
        entryOf("first", at(tuesday, 9), at(tuesday, 9, 5)),
        entryOf("second", at(tuesday, 9, 10), at(tuesday, 9, 15)),
      ]),
      shown,
    );
    await harness.pump(tester);
    final column = slotRect(tester, shown, tuesday, 9 * 60);
    for (final id in const <String>["first", "second"]) {
      final rect = tester.getRect(blockFinder(id, tuesday));
      expect(rect.left, moreOrLessEquals(column.left, epsilon: 0.5));
      expect(rect.width, moreOrLessEquals(column.width, epsilon: 0.5));
    }
  });

  testWidgets("TP6 two entries sharing a minute sit side by side", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    final harness = Harness(
      storeOf(<CalendarEntry<String>>[
        entryOf("first", at(tuesday, 9), at(tuesday, 9, 11)),
        entryOf("second", at(tuesday, 9, 10), at(tuesday, 9, 30)),
      ]),
      shown,
    );
    await harness.pump(tester);
    final column = slotRect(tester, shown, tuesday, 9 * 60);
    final first = tester.getRect(blockFinder("first", tuesday));
    final second = tester.getRect(blockFinder("second", tuesday));
    expect(first.width, moreOrLessEquals(column.width / 2, epsilon: 0.5));
    expect(second.width, moreOrLessEquals(column.width / 2, epsilon: 0.5));
    expect(first.left == second.left, isFalse);
  });

  testWidgets("TP7 a move of 09:10-09:50 dropped lower writes a start on the "
      "slot grid and keeps its 40 minutes", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50)),
    ]);
    await Harness(store, shown).pump(tester);
    final slot = slotRect(tester, shown, tuesday, 9 * 60).height;
    await moveBlock(
      tester,
      blockFinder("task", tuesday),
      Offset(0.0, slot * 3 + 2.0),
    );
    final moved = store.storedEntry("task")!;
    expect(moved.start.isAfter(at(tuesday, 9, 10)), isTrue);
    expect(moved.start.minute % 15, 0);
    expect(moved.end.difference(moved.start), const Duration(minutes: 40));
  });

  testWidgets("TP8 a lift let go in place writes nothing", (tester) async {
    final shown = Shown.week(monday);
    final task = entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50));
    final store = storeOf(<CalendarEntry<String>>[task]);
    await Harness(store, shown).pump(tester);
    final changes = store.changes;
    await selectBlock(tester, blockFinder("task", tuesday));
    // The lift selected the block, so it did lift.
    expect(find.byKey(blockHandlesKey("task")), findsOneWidget);
    expect(store.changes, changes);
    expect(store.storedEntry("task"), task);
  });

  testWidgets("TP9 an end resize writes an end on the slot grid", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50)),
    ]);
    await Harness(store, shown).pump(tester);
    final slot = slotRect(tester, shown, tuesday, 9 * 60).height;
    final block = blockFinder("task", tuesday);
    await selectBlock(tester, block);
    await resizeEnd(tester, block, Offset(0.0, slot + 2.0));
    final resized = store.storedEntry("task")!;
    expect(resized.start, at(tuesday, 9, 10));
    expect(resized.end.isAfter(at(tuesday, 9, 50)), isTrue);
    expect(resized.end.minute % 15, 0);
  });

  testWidgets("TP10 a long press on either piece of Monday 22:00 to Tuesday "
      "02:00 lifts the entry, and a drop keeps its 4 hours", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(tuesday, 2)),
    ]);
    await Harness(store, shown).pump(tester);
    final slot = slotRect(tester, shown, monday, 9 * 60).height;
    // Monday's piece runs to the day's end, so it moves up.
    await moveBlock(
      tester,
      blockFinder("night", monday),
      Offset(0.0, -slot * 2 - 2.0),
    );
    var moved = store.storedEntry("night")!;
    expect(moved.start, at(monday, 21, 30));
    expect(moved.end.difference(moved.start), const Duration(hours: 4));

    await moveBlock(
      tester,
      blockFinder("night", tuesday),
      Offset(0.0, slot * 2 + 2.0),
    );
    moved = store.storedEntry("night")!;
    expect(moved.start, at(monday, 22));
    expect(moved.end, at(tuesday, 2));
  });

  testWidgets("TP11 after a lift of either piece, only Monday's piece has "
      "the top grip and only Tuesday's the bottom", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(tuesday, 2)),
    ]);
    await Harness(store, shown).pump(tester);
    for (final lifted in <DateTime>[monday, tuesday]) {
      await selectBlock(tester, blockFinder("night", lifted));
      Finder grip(DateTime day, AxisDirection side) {
        return find.descendant(
          of: blockFinder("night", day),
          matching: find.byKey(blockGripKey("night", side)),
        );
      }

      expect(grip(monday, AxisDirection.up), findsOneWidget, reason: "$lifted");
      expect(grip(monday, AxisDirection.down), findsNothing, reason: "$lifted");
      expect(grip(tuesday, AxisDirection.up), findsNothing, reason: "$lifted");
      expect(
        grip(tuesday, AxisDirection.down),
        findsOneWidget,
        reason: "$lifted",
      );
      expect(grip(monday, AxisDirection.right), findsNothing);
      expect(grip(tuesday, AxisDirection.right), findsNothing);
      // A tap on the gutter clears the selection.
      await tester.tapAt(Offset(10.0, slotRect(tester, shown, monday, 0).top));
      await tester.pumpAndSettle();
    }
  });

  testWidgets("TP14 an entry 366 days long draws 7 blocks in Week and 1 in "
      "Day", (tester) async {
    final from = CalendarDates.addDays(monday, -100);
    final year = entryOf(
      "year",
      at(from, 10),
      at(CalendarDates.addDays(from, 366), 10),
    );
    for (final view in views) {
      final shown = view(wednesday);
      await Harness(storeOf(<CalendarEntry<String>>[year]), shown).pump(tester);
      expect(blocksOf("year"), findsNWidgets(shown.week ? 7 : 1));
    }
  });

  testWidgets("TP21 in Week a one-day entry dropped on another day's column "
      "stays selected, and glides from the proxy's last rect", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(tuesday, 10), at(tuesday, 11)),
    ]);
    await Harness(store, shown).pump(tester);
    final from = slotRect(tester, shown, tuesday, 10 * 60);
    final to = slotRect(tester, shown, thursday, 10 * 60);
    final gesture = await lift(
      tester,
      tester.getCenter(blockFinder("task", tuesday)),
    );
    // A few pixels below the slot's top, which the drop snaps off.
    await gesture.moveBy(to.topLeft - from.topLeft + const Offset(4.0, 5.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final proxy = tester.getRect(find.byKey(liftedBlockKey));
    await gesture.up();
    await tester.pump();
    final block = blockFinder("task", thursday);
    final painted = tester.getRect(block);
    expect(painted.top, moreOrLessEquals(proxy.top, epsilon: 1.0));
    expect(painted.left, moreOrLessEquals(proxy.left, epsilon: 1.0));
    await tester.pumpAndSettle();
    expect(store.storedEntry("task")!.start, at(thursday, 10));
    final landed = tester.getRect(block);
    expect(landed.top, moreOrLessEquals(to.top));
    expect((landed.top - proxy.top).abs() > 2.0, isTrue);
    expect(find.byKey(blockHandlesKey("task")), findsOneWidget);
  });

  testWidgets("TP22 over a caching store, a long press on either piece of an "
      "entry whose write is pending lifts nothing", (tester) async {
    final night = entryOf("night", at(monday, 22), at(tuesday, 2));
    final source = HeldSource(<CalendarEntry<String>>[night]);
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    store.show(monday, CalendarDates.addDays(monday, 6));
    final shown = Shown.week(monday);
    await Harness(store, shown).pump(tester);
    store.requestMove(night.copyWith(title: "renamed"));
    // A pending block's activity indicator runs until the write ends, so
    // the test pumps fixed frames rather than settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.isPending("night"), isTrue);
    expect(source.replaces, hasLength(1));
    for (final day in <DateTime>[monday, tuesday]) {
      final gesture = await lift(
        tester,
        tester.getCenter(blockFinder("night", day)),
      );
      await tester.pump();
      expect(find.byKey(liftedBlockKey), findsNothing, reason: "$day");
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
    }
  });

  testWidgets("TP23 in Week, Tuesday's piece of Monday 22:00 to Tuesday "
      "02:00 moved one slot down writes Monday 22:15 to Tuesday 02:15, and "
      "dropped on Wednesday 10:00 writes Wednesday 08:00 to 12:00, built at "
      "its landing a frame after, with no Monday block while it is lifted", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    final night = entryOf("night", at(monday, 22), at(tuesday, 2));
    var store = storeOf(<CalendarEntry<String>>[night]);
    await Harness(store, shown).pump(tester);
    final slot = slotRect(tester, shown, tuesday, 0).height;
    await moveBlock(
      tester,
      blockFinder("night", tuesday),
      Offset(0.0, slot + 2.0),
    );
    expect(store.storedEntry("night")!.start, at(monday, 22, 15));
    expect(store.storedEntry("night")!.end, at(tuesday, 2, 15));

    store = storeOf(<CalendarEntry<String>>[night]);
    await Harness(store, shown).pump(tester);
    final from = tester.getRect(blockFinder("night", tuesday)).topLeft;
    final to = slotRect(tester, shown, wednesday, 10 * 60);
    expect(blockFinder("night", monday), findsOneWidget);
    final gesture = await lift(
      tester,
      tester.getCenter(blockFinder("night", tuesday)),
    );
    await tester.pump();
    await gesture.moveBy(to.topLeft - from + const Offset(0.0, 2.0));
    await tester.pump();
    expect(blockFinder("night", monday), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(store.storedEntry("night")!.start, at(wednesday, 8));
    expect(store.storedEntry("night")!.end, at(wednesday, 12));
    final landed = tester.getRect(blockFinder("night", wednesday));
    expect(
      landed.top,
      moreOrLessEquals(slotRect(tester, shown, wednesday, 8 * 60).top),
    );
    expect(
      landed.bottom,
      moreOrLessEquals(slotRect(tester, shown, wednesday, 12 * 60).top),
    );
    await tester.pumpAndSettle();
  });

  testWidgets("TP24 in Week, Monday's piece of Monday 22:00 to Tuesday 02:00 "
      "dropped on Wednesday 10:00 writes Wednesday 10:00 to 14:00", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(tuesday, 2)),
    ]);
    await Harness(store, shown).pump(tester);
    final from = tester.getRect(blockFinder("night", monday)).topLeft;
    final to = slotRect(tester, shown, wednesday, 10 * 60);
    await moveBlock(
      tester,
      blockFinder("night", monday),
      to.topLeft - from + const Offset(0.0, 2.0),
    );
    expect(store.storedEntry("night")!.start, at(wednesday, 10));
    expect(store.storedEntry("night")!.end, at(wednesday, 14));
  });

  testWidgets("TP25 in Week, Tuesday's piece moved one slot down glides from "
      "the proxy's last rect, and the Monday block is built a frame after "
      "the release", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(tuesday, 2)),
    ]);
    await Harness(store, shown).pump(tester);
    final slot = slotRect(tester, shown, tuesday, 0).height;
    final gesture = await lift(
      tester,
      tester.getCenter(blockFinder("night", tuesday)),
    );
    await gesture.moveBy(Offset(0.0, slot + 5.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final proxy = tester.getRect(find.byKey(liftedBlockKey));
    await gesture.up();
    await tester.pump();
    final painted = tester.getRect(blockFinder("night", tuesday));
    expect(painted.top, moreOrLessEquals(proxy.top, epsilon: 1.0));
    expect(blockFinder("night", monday), findsOneWidget);
    await tester.pumpAndSettle();
    expect(store.storedEntry("night")!.start, at(monday, 22, 15));
    final landed = tester.getRect(blockFinder("night", tuesday));
    expect(
      landed.top,
      moreOrLessEquals(slotRect(tester, shown, tuesday, 0).top),
    );
    expect((landed.top - proxy.top).abs() > 2.0, isTrue);
  });

  testWidgets("TP26 in Week, two frames after a lift of the Tuesday piece, a "
      "block that shared lanes with the Monday piece spans its column's "
      "full width", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(tuesday, 2)),
      entryOf("late", at(monday, 23), at(monday, 23, 30)),
    ]);
    await Harness(store, shown).pump(tester);
    final column = slotRect(tester, shown, monday, 23 * 60);
    expect(
      tester.getRect(blockFinder("late", monday)).width,
      moreOrLessEquals(column.width / 2, epsilon: 0.5),
    );
    final gesture = await lift(
      tester,
      tester.getCenter(blockFinder("night", tuesday)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getRect(blockFinder("late", monday)).width,
      moreOrLessEquals(column.width, epsilon: 0.5),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("TR1 a tap on an empty slot reports that slot", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
    await harness.pump(tester);
    await tester.tapAt(slotRect(tester, shown, tuesday, 10 * 60).center);
    await tester.pumpAndSettle();
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(tuesday, 10), end: at(tuesday, 10, 15)),
    ]);
  });

  testWidgets("TR2 a create drag in Week from Monday 10:00 to Wednesday "
      "12:00 reports Monday 10:00 to Wednesday 12:15", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
    await harness.pump(tester);
    await createDrag(
      tester,
      slotRect(tester, shown, monday, 10 * 60).center,
      slotRect(tester, shown, wednesday, 12 * 60).center,
    );
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(monday, 10), end: at(wednesday, 12, 15)),
    ]);
  });

  testWidgets("TR3 with maxDayCount 3 a create drag from Monday is held at "
      "Thursday's start past Wednesday, and with none it reaches "
      "Thursday", (tester) async {
    final shown = Shown.week(monday);
    for (final (limit, day, end) in <(int?, DateTime, DateTime)>[
      (3, thursday, thursday),
      (3, saturday, thursday),
      (3, wednesday, at(wednesday, 12, 15)),
      (null, thursday, at(thursday, 12, 15)),
    ]) {
      final harness = Harness(
        storeOf(const <CalendarEntry<String>>[]),
        shown,
        maxDayCount: limit,
      );
      await harness.pump(tester);
      await createDrag(
        tester,
        slotRect(tester, shown, monday, 10 * 60).center,
        slotRect(tester, shown, day, 12 * 60).center,
      );
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: at(monday, 10), end: end),
      ], reason: "$limit over $day");
    }
  });

  testWidgets("TR3b under hours 08:00-18:00 with maxDayCount 3, a create "
      "drag from Monday 10:00 released over Thursday 12:00 reports Monday "
      "10:00 to Wednesday 18:00", (tester) async {
    final office = CalendarDayHours(8 * 60, 18 * 60);
    final shown = Shown.week(monday, hours: office);
    final harness = Harness(
      storeOf(const <CalendarEntry<String>>[], hours: office),
      shown,
      maxDayCount: 3,
    );
    await harness.pump(tester);
    await createDrag(
      tester,
      slotRect(tester, shown, monday, 10 * 60).center,
      slotRect(tester, shown, thursday, 12 * 60).center,
    );
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(monday, 10), end: at(wednesday, 18)),
    ]);
  });

  testWidgets("TR10 in Day over Tuesday, a create drag from the 00:00 slot "
      "to the 23:45 slot reports Tuesday's start to Wednesday's, a timed "
      "range", (tester) async {
    final shown = Shown.day(tuesday);
    final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
    await harness.pump(tester);
    await createDrag(
      tester,
      slotRect(tester, shown, tuesday, 0).center,
      slotRect(tester, shown, tuesday, CalendarDates.minutesPerDay - 15).center,
    );
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: tuesday, end: wednesday),
    ]);
    expect(harness.creates.single.isAllDay, isFalse);
  });

  testWidgets("TR6 a press on the free part of the 09:00 slot under an entry "
      "from 09:10 reports no create", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(
      storeOf(<CalendarEntry<String>>[
        entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50)),
      ]),
      shown,
      allowsOverlaps: false,
    );
    await harness.pump(tester);
    final nine = slotRect(tester, shown, tuesday, 9 * 60);
    final top = tester.getRect(blockFinder("task", tuesday)).top;
    final free = Offset(nine.center.dx, nine.top + 2.0);
    // The press lies above the block, over no item.
    expect(free.dy < top, isTrue);
    await tester.tapAt(free);
    await tester.pumpAndSettle();
    expect(harness.creates, isEmpty);
    // A slot that shares no time takes the tap.
    await tester.tapAt(slotRect(tester, shown, tuesday, 8 * 60 + 45).center);
    await tester.pumpAndSettle();
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(tuesday, 8, 45), end: at(tuesday, 9)),
    ]);
  });

  testWidgets("TR8 a create drag across 10 slots reads no store entries", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(tuesday, 15), at(tuesday, 16)),
    ]);
    final harness = Harness(store, shown, allowsOverlaps: false);
    await harness.pump(tester);
    final calls = store.betweenCalls;
    final from = slotRect(tester, shown, tuesday, 10 * 60).center;
    final slot = slotRect(tester, shown, tuesday, 10 * 60).height;
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 1; step <= 10; step++) {
      await gesture.moveTo(from + Offset(0.0, slot * step));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(tuesday, 10), end: at(tuesday, 12, 45)),
    ]);
    expect(store.betweenCalls - calls, 0);
  });

  testWidgets("TR9 a create drag from Tuesday 10:00 reaches up to the end of "
      "an entry ending at 09:00 and down to the start of one starting at "
      "11:00, and no further", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(
      storeOf(<CalendarEntry<String>>[
        entryOf("before", at(tuesday, 8), at(tuesday, 9)),
        entryOf("after", at(tuesday, 11), at(tuesday, 12)),
      ]),
      shown,
      allowsOverlaps: false,
    );
    await harness.pump(tester);
    await createDrag(
      tester,
      slotRect(tester, shown, tuesday, 10 * 60).center,
      slotRect(tester, shown, tuesday, 7 * 60).center,
    );
    await createDrag(
      tester,
      slotRect(tester, shown, tuesday, 10 * 60).center,
      slotRect(tester, shown, tuesday, 13 * 60).center,
    );
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(tuesday, 9), end: at(tuesday, 10, 15)),
      CalendarCreateRange(start: at(tuesday, 10), end: at(tuesday, 11)),
    ]);
  });

  testWidgets("TC1 at slot 30 over 00:00-24:00 the grid has 48 slot rows and "
      "a tap reports 30 minutes", (tester) async {
    for (final shown in <Shown>[
      Shown.week(monday, slotMinutes: 30),
      Shown.day(tuesday, slotMinutes: 30),
    ]) {
      final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
      await harness.pump(tester);
      // The slots, and the room below them.
      expect(
        rowCount(tester),
        shown.editLeadingRows + 48 + 1,
        reason: shown.name,
      );
      await tester.tapAt(slotRect(tester, shown, tuesday, 10 * 60).center);
      await tester.pumpAndSettle();
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: at(tuesday, 10), end: at(tuesday, 10, 30)),
      ], reason: shown.name);
    }
  });

  testWidgets("TP7b at slot 30 a move of 09:10-09:50 dropped lower writes a "
      "start on the slot grid and keeps its 40 minutes", (tester) async {
    final shown = Shown.week(monday, slotMinutes: 30);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50)),
    ]);
    await Harness(store, shown).pump(tester);
    final slot = slotRect(tester, shown, tuesday, 9 * 60).height;
    await moveBlock(
      tester,
      blockFinder("task", tuesday),
      Offset(0.0, slot * 3 + 2.0),
    );
    final moved = store.storedEntry("task")!;
    // The lifted top, 10:40, lands on the nearest 30-minute slot.
    expect(moved.start, at(tuesday, 10, 30));
    expect(moved.end.difference(moved.start), const Duration(minutes: 40));
  });

  testWidgets("TP8b at slot 30 a lift let go in place writes nothing", (
    tester,
  ) async {
    final shown = Shown.week(monday, slotMinutes: 30);
    final task = entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50));
    final store = storeOf(<CalendarEntry<String>>[task]);
    await Harness(store, shown).pump(tester);
    final changes = store.changes;
    await selectBlock(tester, blockFinder("task", tuesday));
    // The lift selected the block, so it did lift.
    expect(find.byKey(blockHandlesKey("task")), findsOneWidget);
    expect(store.changes, changes);
    expect(store.storedEntry("task"), task);
  });

  testWidgets("TP9b at slot 30 an end resize writes an end on the slot "
      "grid", (tester) async {
    final shown = Shown.week(monday, slotMinutes: 30);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50)),
    ]);
    await Harness(store, shown).pump(tester);
    final slot = slotRect(tester, shown, tuesday, 9 * 60).height;
    final block = blockFinder("task", tuesday);
    await selectBlock(tester, block);
    await resizeEnd(tester, block, Offset(0.0, slot + 2.0));
    final resized = store.storedEntry("task")!;
    expect(resized.start, at(tuesday, 9, 10));
    // The dragged edge, at 10:20, lands on the nearest 30-minute edge.
    expect(resized.end, at(tuesday, 10, 30));
  });

  /// The two changes TC2 to TC4 make during a gesture: the slot length
  /// from 15 to 30, and the hours' end from 24:00 to 23:00, which leaves
  /// every row of a block at 10:00 where it was.
  final changes = <String, void Function(Harness harness)>{
    "slotMinutes": (harness) {
      harness.slotMinutes = 30;
    },
    "hours": (harness) {
      harness.hours = CalendarDayHours(0, 23 * 60);
    },
  };

  testWidgets("TC2 a slotMinutes change, and an hours change, during a move "
      "write nothing, leave the entry, and clear the marks", (tester) async {
    for (final MapEntry(key: name, value: change) in changes.entries) {
      final shown = Shown.week(monday);
      final task = entryOf("task", at(tuesday, 10), at(tuesday, 11));
      final store = storeOf(<CalendarEntry<String>>[task]);
      final harness = Harness(store, shown);
      await harness.pump(tester);
      final writes = store.changes;
      final slot = slotRect(tester, shown, tuesday, 10 * 60).height;
      final gesture = await lift(
        tester,
        tester.getCenter(blockFinder("task", tuesday)),
      );
      await gesture.moveBy(Offset(0.0, slot * 2 + 2.0));
      await tester.pump();
      // The move shows where it lands.
      expect(find.byKey(landingLabelKey), findsOneWidget, reason: name);
      expect(marksSlots(tester), isTrue, reason: name);

      change(harness);
      await harness.rebuild(tester);
      await tester.pump();
      expect(find.byKey(landingLabelKey), findsNothing, reason: name);
      expect(marksSlots(tester), isFalse, reason: name);
      await gesture.moveBy(Offset(0.0, slot));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.changes, writes, reason: name);
      expect(store.storedEntry("task"), task, reason: name);
      expect(blockFinder("task", tuesday), findsOneWidget, reason: name);
    }
  });

  testWidgets("TC3 a slotMinutes change, and an hours change, during a "
      "resize write nothing, leave the entry, and clear the marks, an hours "
      "change leaving the entry wholly outside them throwing nothing", (
    tester,
  ) async {
    final cases = <String, (CalendarEntry<String>, void Function(Harness))>{
      for (final MapEntry(key: name, value: change) in changes.entries)
        name: (entryOf("task", at(tuesday, 10), at(tuesday, 11)), change),
      "hours that leave it outside": (
        entryOf("task", at(tuesday, 20), at(tuesday, 21)),
        (harness) {
          harness.hours = CalendarDayHours(8 * 60, 18 * 60);
        },
      ),
    };
    for (final MapEntry(key: name, value: (task, change)) in cases.entries) {
      final shown = Shown.week(monday);
      final store = storeOf(<CalendarEntry<String>>[task]);
      final harness = Harness(store, shown);
      await harness.pump(tester);
      final writes = store.changes;
      final slot = slotRect(tester, shown, tuesday, 10 * 60).height;
      final block = blockFinder("task", tuesday);
      await selectBlock(tester, block);
      final rect = tester.getRect(block);
      final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.bottom - 3.0),
      );
      await gesture.moveBy(Offset(0.0, slot * 2 + 2.0));
      await tester.pump();
      // The resize shows the times it would write.
      expect(find.byKey(landingLabelKey), findsOneWidget, reason: name);

      change(harness);
      await harness.rebuild(tester);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      expect(find.byKey(landingLabelKey), findsNothing, reason: name);
      await gesture.moveBy(Offset(0.0, slot));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      expect(store.changes, writes, reason: name);
      expect(store.storedEntry("task"), task, reason: name);
    }
  });

  testWidgets("TC4 a slotMinutes change, and an hours change, during a "
      "create drag report nothing and clear the marks", (tester) async {
    for (final MapEntry(key: name, value: change) in changes.entries) {
      final shown = Shown.week(monday);
      final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
      await harness.pump(tester);
      final from = slotRect(tester, shown, tuesday, 10 * 60).center;
      final slot = slotRect(tester, shown, tuesday, 10 * 60).height;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(from + Offset(0.0, slot * 4));
      await tester.pump();
      // The range is marked while it is dragged.
      expect(marksSlots(tester), isTrue, reason: name);

      change(harness);
      await harness.rebuild(tester);
      await tester.pump();
      expect(marksSlots(tester), isFalse, reason: name);
      await gesture.moveTo(from + Offset(0.0, slot * 5));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.creates, isEmpty, reason: name);
      expect(marksSlots(tester), isFalse, reason: name);
    }
  });

  testWidgets("TP31 in Week and in Day, a timed entry from Tuesday's start "
      "to Wednesday's draws one block on Tuesday from the 00:00 row's top to "
      "the 23:45 row's bottom, and no bar", (tester) async {
    final whole = entryOf("whole", tuesday, wednesday);
    for (final view in views) {
      final shown = view(tuesday);
      await Harness(
        storeOf(<CalendarEntry<String>>[whole]),
        shown,
      ).pump(tester);
      expect(
        find.byKey(allDayBarKey("whole")),
        findsNothing,
        reason: shown.name,
      );
      expect(blocksOf("whole"), findsOneWidget, reason: shown.name);
      final col = shown.colOf(tuesday);
      final rect = tester.getRect(blockFinder("whole", tuesday));
      expect(
        rect.top,
        moreOrLessEquals(cellRect(tester, shown.rowOf(0), col).top),
        reason: shown.name,
      );
      expect(
        rect.bottom,
        moreOrLessEquals(
          cellRect(
            tester,
            shown.rowOf(CalendarDates.minutesPerDay - 15),
            col,
          ).bottom,
        ),
        reason: shown.name,
      );
    }
  });

  testWidgets("TP34 in Week where overlaps are forbidden, Tuesday 10:00 to "
      "11:00 dropped on Tuesday's 14:00 row writes nothing over a timed "
      "entry from Tuesday's start to Wednesday's, with the days beside it "
      "full", (tester) async {
    final shown = Shown.week(monday);
    final ten = entryOf("ten", at(tuesday, 10), at(tuesday, 11));
    final full = <CalendarEntry<String>>[
      entryOf("mon", monday, tuesday),
      entryOf("wed", wednesday, thursday),
    ];

    /// Pumps the grid over [entries], drops "ten" with its top on Tuesday's
    /// 14:00 row, and returns the store and its change count before the
    /// drop.
    Future<(CountingStore, int)> dropTen(
      List<CalendarEntry<String>> entries,
    ) async {
      final store = storeOf(entries);
      await Harness(store, shown, allowsOverlaps: false).pump(tester);
      final block = tester.getRect(blockFinder("ten", tuesday));
      final slot = slotRect(tester, shown, tuesday, 14 * 60);
      final changes = store.changes;
      await moveBlock(
        tester,
        blockFinder("ten", tuesday),
        Offset(0.0, slot.top - block.top + 2.0),
      );
      return (store, changes);
    }

    // Setup sanity: with Tuesday free but for "ten", the drop writes it.
    final (free, _) = await dropTen(<CalendarEntry<String>>[ten, ...full]);
    expect(free.storedEntry("ten")!.start, at(tuesday, 14));
    expect(free.storedEntry("ten")!.end, at(tuesday, 15));

    final (store, changes) = await dropTen(<CalendarEntry<String>>[
      entryOf("whole", tuesday, wednesday),
      ten,
      ...full,
    ]);
    expect(store.changes, changes);
    expect(store.storedEntry("ten"), ten);
  });

  testWidgets("TP35 in Week where overlaps are forbidden, a timed entry from "
      "Tuesday's start to Wednesday's dropped on Wednesday's 00:00 row is "
      "not stored over Wednesday 10:00 to 11:00", (tester) async {
    final shown = Shown.week(monday);
    final whole = entryOf("whole", tuesday, wednesday);
    final wedTen = entryOf("wedTen", at(wednesday, 10), at(wednesday, 11));

    /// Pumps the grid over [entries] and drops "whole"'s Tuesday block
    /// with its top on Wednesday's 00:00 row.
    Future<CountingStore> dropWhole(List<CalendarEntry<String>> entries) async {
      final store = storeOf(entries);
      await Harness(store, shown, allowsOverlaps: false).pump(tester);
      final block = tester.getRect(blockFinder("whole", tuesday));
      final slot = slotRect(tester, shown, wednesday, 0);
      await moveBlock(
        tester,
        blockFinder("whole", tuesday),
        slot.topLeft - block.topLeft + const Offset(0.0, 2.0),
      );
      return store;
    }

    // Setup sanity: with Wednesday free, the drop writes the whole of it.
    var store = await dropWhole(<CalendarEntry<String>>[whole]);
    expect(store.storedEntry("whole")!.start, wednesday);
    expect(store.storedEntry("whole")!.end, thursday);

    store = await dropWhole(<CalendarEntry<String>>[whole, wedTen]);
    final stored = store.storedEntry("whole")!;
    expect(
      !stored.end.isAfter(wedTen.start) || !stored.start.isBefore(wedTen.end),
      isTrue,
      reason: "$stored",
    );
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    testWidgets("TP12 in Week and in Day, the day's column shows 24 hours of "
        "rows, the same as the day beside it, and 01:30 to 03:30 draws from "
        "the 01:30 row to the 03:30 row", (tester) async {
      final day = shortDayStart;
      final early = entryOf("early", at(day, 1, 30), at(day, 3, 30));
      for (final shown in <Shown>[
        Shown.week(CalendarDates.addDays(day, -6)),
        Shown.day(day),
      ]) {
        await Harness(
          storeOf(<CalendarEntry<String>>[early]),
          shown,
        ).pump(tester);
        final col = shown.colOf(day);
        final viewport = viewportOf(tester);
        expect(
          viewport.rectOfCell(
            shown.rowOf(CalendarDates.minutesPerDay - 15),
            col,
          ),
          isNotNull,
        );
        expect(
          tester
              .widget<Board<GridKey, GridShape<String>>>(
                find.byType(Board<GridKey, GridShape<String>>),
              )
              .controller
              .rows
              .axis
              .trackCount,
          shown.editLeadingRows + 96 + 1,
        );
        if (shown.week) {
          for (final minute in const <int>[60, 2 * 60, 3 * 60]) {
            final here = cellRect(tester, shown.rowOf(minute), col);
            final beside = cellRect(tester, shown.rowOf(minute), col - 1);
            expect(here.top, beside.top);
            expect(here.height, beside.height);
          }
        }
        final rect = tester.getRect(blockFinder("early", day));
        expect(
          rect.top,
          moreOrLessEquals(cellRect(tester, shown.rowOf(90), col).top),
          reason: shown.name,
        );
        expect(
          rect.bottom,
          moreOrLessEquals(cellRect(tester, shown.rowOf(210), col).top),
          reason: shown.name,
        );
      }
    });

    testWidgets("TP13 a move and a resize edge onto 02:00-02:59 and a create "
        "drag ending there write and report nothing, and a tap there "
        "creates nothing", (tester) async {
      final day = shortDayStart;
      final shown = Shown.day(day);
      final late = entryOf("late", at(day, 5), at(day, 6));
      final early = entryOf("early", at(day, 0, 30), at(day, 1, 30));
      final store = storeOf(<CalendarEntry<String>>[late, early]);
      final harness = Harness(store, shown);
      await harness.pump(tester);
      final changes = store.changes;
      final slot = slotRect(tester, shown, day, 0).height;

      final from = tester.getRect(blockFinder("late", day)).topLeft;
      await moveBlock(
        tester,
        blockFinder("late", day),
        slotRect(tester, shown, day, 2 * 60).topLeft -
            from +
            const Offset(0.0, 2.0),
      );
      expect(store.storedEntry("late"), late);

      await selectBlock(tester, blockFinder("early", day));
      await resizeEnd(tester, blockFinder("early", day), Offset(0.0, slot * 4));
      expect(store.storedEntry("early"), early);
      expect(store.changes, changes);

      await createDrag(
        tester,
        slotRect(tester, shown, day, 3 * 60 + 30).center,
        slotRect(tester, shown, day, 2 * 60 + 30).center,
      );
      expect(harness.creates, isEmpty);
      await tester.tapAt(slotRect(tester, shown, day, 2 * 60 + 30).center);
      await tester.pumpAndSettle();
      expect(harness.creates, isEmpty);
      // A tap beside the skipped hour creates.
      await tester.tapAt(slotRect(tester, shown, day, 3 * 60).center);
      await tester.pumpAndSettle();
      expect(harness.creates, hasLength(1));
    });

    testWidgets("TP15 a 60-minute entry dropped on the 01:30 row is written "
        "01:30 to 03:30, 60 minutes apart", (tester) async {
      final day = shortDayStart;
      final shown = Shown.day(day);
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("task", at(day, 5), at(day, 6)),
      ]);
      await Harness(store, shown).pump(tester);
      final from = tester.getRect(blockFinder("task", day)).topLeft;
      await moveBlock(
        tester,
        blockFinder("task", day),
        slotRect(tester, shown, day, 90).topLeft -
            from +
            const Offset(0.0, 2.0),
      );
      final moved = store.storedEntry("task")!;
      expect(moved.start, at(day, 1, 30));
      expect(moved.end, at(day, 3, 30));
      expect(moved.end.difference(moved.start), const Duration(minutes: 60));
    });

    testWidgets("TP32 in Week, 00:00 to 23:00 of the day before, dropped "
        "with its top on the day's 00:00 row, is stored timed from the day's "
        "start to the next day's and draws as a block", (tester) async {
      final day = shortDayStart;
      final before = CalendarDates.addDays(day, -1);
      expect(
        CalendarDates.addDays(day, 1).difference(day),
        const Duration(hours: 23),
      );
      final shown = Shown.week(CalendarDates.addDays(day, -6));
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("long", before, at(before, 23)),
      ]);
      await Harness(store, shown).pump(tester);
      final from = tester.getRect(blockFinder("long", before)).topLeft;
      await moveBlock(
        tester,
        blockFinder("long", before),
        slotRect(tester, shown, day, 0).topLeft - from + const Offset(0.0, 2.0),
      );
      final moved = store.storedEntry("long")!;
      expect(moved.start, day);
      expect(moved.end, CalendarDates.addDays(day, 1));
      expect(moved.isAllDay, isFalse);
      expect(blockFinder("long", day), findsOneWidget);
      expect(find.byKey(allDayBarKey("long")), findsNothing);
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    testWidgets("TP12 in Week and in Day, the day's column shows 24 hours of "
        "rows, and an entry at the second 01:30 draws from the 01:30 row", (
      tester,
    ) async {
      final day = longDayStart;
      final second = entryOf(
        "second",
        secondHalfPastOne,
        secondHalfPastOne.add(const Duration(minutes: 30)),
      );
      for (final shown in <Shown>[
        Shown.week(CalendarDates.addDays(day, -6)),
        Shown.day(day),
      ]) {
        await Harness(
          storeOf(<CalendarEntry<String>>[second]),
          shown,
        ).pump(tester);
        final col = shown.colOf(day);
        expect(
          tester
              .widget<Board<GridKey, GridShape<String>>>(
                find.byType(Board<GridKey, GridShape<String>>),
              )
              .controller
              .rows
              .axis
              .trackCount,
          shown.editLeadingRows + 96 + 1,
        );
        if (shown.week) {
          final here = cellRect(tester, shown.rowOf(90), col);
          final beside = cellRect(tester, shown.rowOf(90), col - 1);
          expect(here.top, beside.top);
        }
        final rect = tester.getRect(blockFinder("second", day));
        expect(
          rect.top,
          moreOrLessEquals(cellRect(tester, shown.rowOf(90), col).top),
          reason: shown.name,
        );
      }
    });

    testWidgets("TP16 a 60-minute entry dropped on the 00:30 row ends at the "
        "first 01:30", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("task", at(day, 5), at(day, 6)),
      ]);
      await Harness(store, shown).pump(tester);
      final from = tester.getRect(blockFinder("task", day)).topLeft;
      await moveBlock(
        tester,
        blockFinder("task", day),
        slotRect(tester, shown, day, 30).topLeft -
            from +
            const Offset(0.0, 2.0),
      );
      final moved = store.storedEntry("task")!;
      expect(moved.start, at(day, 0, 30));
      expect(moved.end, day.add(const Duration(minutes: 90)));
      expect(CalendarDates.isLaterOccurrence(moved.end), isFalse);
    });

    testWidgets("TP17 at slot 15 an entry starting at the second 01:30, moved "
        "down one slot, starts at the second 01:45", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final store = storeOf(<CalendarEntry<String>>[
        entryOf(
          "second",
          secondHalfPastOne,
          secondHalfPastOne.add(const Duration(minutes: 15)),
        ),
      ]);
      await Harness(store, shown).pump(tester);
      final slot = slotRect(tester, shown, day, 0).height;
      await moveBlock(
        tester,
        blockFinder("second", day),
        Offset(0.0, slot + 2.0),
      );
      final moved = store.storedEntry("second")!;
      expect(moved.start, secondHalfPastOne.add(const Duration(minutes: 15)));
      expect(CalendarDates.isLaterOccurrence(moved.start), isTrue);
    });

    testWidgets("TP18 an entry from the second 01:00 to the second 01:45 "
        "whose end is resized up one slot ends at the second 01:30", (
      tester,
    ) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final secondOne = secondHalfPastOne.subtract(const Duration(minutes: 30));
      final store = storeOf(<CalendarEntry<String>>[
        entryOf(
          "second",
          secondOne,
          secondOne.add(const Duration(minutes: 45)),
        ),
      ]);
      await Harness(store, shown).pump(tester);
      final slot = slotRect(tester, shown, day, 0).height;
      final block = blockFinder("second", day);
      await selectBlock(tester, block);
      await resizeEnd(tester, block, Offset(0.0, -slot - 2.0));
      final resized = store.storedEntry("second")!;
      expect(resized.start, secondOne);
      expect(resized.end, secondHalfPastOne);
    });

    testWidgets("TP19 a tap on the 01:30 row reports a range starting at the "
        "first 01:30", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
      await harness.pump(tester);
      await tester.tapAt(slotRect(tester, shown, day, 90).center);
      await tester.pumpAndSettle();
      final first = day.add(const Duration(minutes: 90));
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(
          start: first,
          end: first.add(const Duration(minutes: 15)),
        ),
      ]);
    });

    testWidgets("TP20 a lift of an entry at the second 01:30 let go in place "
        "writes nothing", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final second = entryOf(
        "second",
        secondHalfPastOne,
        secondHalfPastOne.add(const Duration(minutes: 30)),
      );
      final store = storeOf(<CalendarEntry<String>>[second]);
      await Harness(store, shown).pump(tester);
      final changes = store.changes;
      await selectBlock(tester, blockFinder("second", day));
      expect(find.byKey(blockHandlesKey("second")), findsOneWidget);
      expect(store.changes, changes);
      expect(store.storedEntry("second"), second);
    });

    testWidgets("TP27 in Week and in Day, 00:30 to the second 02:30 draws to "
        "the 02:30 row, and the first 01:30 to the second 01:15 from the "
        "01:30 row to the 02:15 row", (tester) async {
      final day = longDayStart;
      // 180 minutes, over the repeated hour.
      final spans = entryOf("spans", at(day, 0, 30), at(day, 2, 30));
      // 45 minutes, whose end's wall time is before its start's.
      final folds = entryOf(
        "folds",
        day.add(const Duration(minutes: 90)),
        secondHalfPastOne.subtract(const Duration(minutes: 15)),
      );
      for (final shown in <Shown>[
        Shown.week(CalendarDates.addDays(day, -6)),
        Shown.day(day),
      ]) {
        await Harness(
          storeOf(<CalendarEntry<String>>[spans, folds]),
          shown,
        ).pump(tester);
        final col = shown.colOf(day);
        expect(
          tester.getRect(blockFinder("spans", day)).bottom,
          moreOrLessEquals(cellRect(tester, shown.rowOf(135), col).bottom),
          reason: shown.name,
        );
        expect(blockFinder("folds", day), findsOneWidget, reason: shown.name);
        expect(
          tester.getRect(blockFinder("folds", day)).bottom,
          moreOrLessEquals(cellRect(tester, shown.rowOf(120), col).bottom),
          reason: shown.name,
        );
      }
    });

    testWidgets("TP33 in Week, an entry from 00:00 of the day before lasting "
        "25 hours, lifted by the day before's block and dropped with its top "
        "on the day's 00:00 row, is stored timed from the day's start to the "
        "next day's and draws as a block", (tester) async {
      final day = longDayStart;
      final before = CalendarDates.addDays(day, -1);
      expect(
        CalendarDates.addDays(day, 1).difference(day),
        const Duration(hours: 25),
      );
      final shown = Shown.week(CalendarDates.addDays(day, -6));
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("long", before, before.add(const Duration(hours: 25))),
      ]);
      await Harness(store, shown).pump(tester);
      // Setup sanity: the week draws it as two blocks, and the day before's
      // holds its start.
      expect(blocksOf("long"), findsNWidgets(2));
      expect(blockFinder("long", before), findsOneWidget);
      final from = tester.getRect(blockFinder("long", before)).topLeft;
      await moveBlock(
        tester,
        blockFinder("long", before),
        slotRect(tester, shown, day, 0).topLeft - from + const Offset(0.0, 2.0),
      );
      final moved = store.storedEntry("long")!;
      expect(moved.start, day);
      expect(moved.end, CalendarDates.addDays(day, 1));
      expect(moved.isAllDay, isFalse);
      expect(blockFinder("long", day), findsOneWidget);
      expect(find.byKey(allDayBarKey("long")), findsNothing);
    });

    testWidgets("TP45 in Day, the first 01:30 to the second 01:00 draws to "
        "the 02:00 row, and its end edge dragged up a slot requests an end "
        "at the first 01:45", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final first = day.add(const Duration(minutes: 90));
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("folds", first, first.add(const Duration(minutes: 30))),
        ]),
        shown,
        recordsMoves: true,
      );
      await harness.pump(tester);
      final block = blockFinder("folds", day);
      // Setup sanity: the end edge lies at the start plus the length, not
      // at the end's 01:00.
      expect(
        tester.getRect(block).bottom,
        moreOrLessEquals(slotRect(tester, shown, day, 120).top),
      );
      final slot = slotRect(tester, shown, day, 0).height;
      await selectBlock(tester, block);
      await resizeEnd(tester, block, Offset(0.0, -slot - 2.0));
      expect(timesOf(harness.moves), <(DateTime, DateTime)>[
        (first, first.add(const Duration(minutes: 15))),
      ]);
    });

    testWidgets("TP46 in Day, the first 01:30 to the second 01:00 with its "
        "end edge dragged down a slot requests an end at the second 01:15", (
      tester,
    ) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final first = day.add(const Duration(minutes: 90));
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("folds", first, first.add(const Duration(minutes: 30))),
        ]),
        shown,
        recordsMoves: true,
      );
      await harness.pump(tester);
      final block = blockFinder("folds", day);
      final slot = slotRect(tester, shown, day, 0).height;
      await selectBlock(tester, block);
      await resizeEnd(tester, block, Offset(0.0, slot + 2.0));
      expect(timesOf(harness.moves), <(DateTime, DateTime)>[
        (first, secondHalfPastOne.subtract(const Duration(minutes: 15))),
      ]);
    });

    testWidgets("TP47 in Day, the first 01:30 to the second 01:15 draws to "
        "the 02:15 row, and its end edge dragged up a slot requests an end "
        "at the second 01:00", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final first = day.add(const Duration(minutes: 90));
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("folds", first, first.add(const Duration(minutes: 45))),
        ]),
        shown,
        recordsMoves: true,
      );
      await harness.pump(tester);
      final block = blockFinder("folds", day);
      // Setup sanity: the end edge lies at the start plus the length, not
      // at the end's 01:15.
      expect(
        tester.getRect(block).bottom,
        moreOrLessEquals(slotRect(tester, shown, day, 135).top),
      );
      final slot = slotRect(tester, shown, day, 0).height;
      await selectBlock(tester, block);
      await resizeEnd(tester, block, Offset(0.0, -slot - 2.0));
      expect(timesOf(harness.moves), <(DateTime, DateTime)>[
        (first, secondHalfPastOne.subtract(const Duration(minutes: 30))),
      ]);
    });

    testWidgets("TP49 in Day, the first 01:30 to the second 01:00 with its "
        "end edge dragged down three slots, past the second 01:30, requests "
        "an end at 02:45", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final first = day.add(const Duration(minutes: 90));
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("folds", first, first.add(const Duration(minutes: 30))),
        ]),
        shown,
        recordsMoves: true,
      );
      await harness.pump(tester);
      final block = blockFinder("folds", day);
      final slot = slotRect(tester, shown, day, 0).height;
      await selectBlock(tester, block);
      await resizeEnd(tester, block, Offset(0.0, 3 * slot + 2.0));
      expect(timesOf(harness.moves), <(DateTime, DateTime)>[
        (first, at(day, 2, 45)),
      ]);
    });

    testWidgets("TP52 a tap on the 01:45 row reports a range from the first "
        "01:45 to the second 01:00, where the first pass ends", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
      await harness.pump(tester);
      await tester.tapAt(slotRect(tester, shown, day, 105).center);
      await tester.pumpAndSettle();
      final first = day.add(const Duration(minutes: 105));
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(
          start: first,
          end: first.add(const Duration(minutes: 15)),
        ),
      ]);
    });

    testWidgets("TP55 a create drag from the 01:15 row down to the 01:45 row "
        "ends at the second 01:00, and one from the 00:45 row ends at 02:00, "
        "past the second pass", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
      await harness.pump(tester);
      await createDrag(
        tester,
        slotRect(tester, shown, day, 75).center,
        slotRect(tester, shown, day, 105).center,
      );
      await createDrag(
        tester,
        slotRect(tester, shown, day, 45).center,
        slotRect(tester, shown, day, 105).center,
      );
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(
          start: day.add(const Duration(minutes: 75)),
          end: day.add(const Duration(minutes: 120)),
        ),
        CalendarCreateRange(start: at(day, 0, 45), end: at(day, 2)),
      ]);
    });

    testWidgets("TP56 where overlaps are forbidden, a create drag from the "
        "01:45 row up to the 00:45 row, beside an entry in the second pass, "
        "holds at the 01:00 row and ends at the second 01:00", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf(
            "later",
            day.add(const Duration(minutes: 135)),
            day.add(const Duration(minutes: 150)),
          ),
        ]),
        shown,
        allowsOverlaps: false,
      );
      await harness.pump(tester);
      await createDrag(
        tester,
        slotRect(tester, shown, day, 105).center,
        slotRect(tester, shown, day, 45).center,
      );
      // A start before 01:00 would end the range at 02:00, over the entry.
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(
          start: day.add(const Duration(minutes: 60)),
          end: day.add(const Duration(minutes: 120)),
        ),
      ]);
    });

    testWidgets("TP57 where overlaps are forbidden, a create drag from the "
        "01:15 row down to the 01:45 row, before an entry from the second "
        "01:00, reaches the 01:45 row and ends at the second 01:00", (
      tester,
    ) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf(
            "later",
            day.add(const Duration(minutes: 120)),
            day.add(const Duration(minutes: 135)),
          ),
        ]),
        shown,
        allowsOverlaps: false,
      );
      await harness.pump(tester);
      await createDrag(
        tester,
        slotRect(tester, shown, day, 75).center,
        slotRect(tester, shown, day, 105).center,
      );
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(
          start: day.add(const Duration(minutes: 75)),
          end: day.add(const Duration(minutes: 120)),
        ),
      ]);
    });

    testWidgets("TP58 in Day, the first 01:00 to the first 01:30 with its end "
        "edge dragged down two slots requests an end at the second 01:00", (
      tester,
    ) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final first = day.add(const Duration(minutes: 60));
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("task", first, first.add(const Duration(minutes: 30))),
        ]),
        shown,
        recordsMoves: true,
      );
      await harness.pump(tester);
      final block = blockFinder("task", day);
      final slot = slotRect(tester, shown, day, 0).height;
      await selectBlock(tester, block);
      await resizeEnd(tester, block, Offset(0.0, 2 * slot + 2.0));
      expect(timesOf(harness.moves), <(DateTime, DateTime)>[
        (first, first.add(const Duration(minutes: 60))),
      ]);
    });

    testWidgets("TP59 in Day under 01:30-24:00, a 30-minute entry dropped on "
        "the 01:30 row, which ends at the second 01:00 and draws to the 02:00 "
        "row, is requested", (tester) async {
      final day = longDayStart;
      final shown = Shown.day(
        day,
        hours: CalendarDayHours(90, CalendarDates.minutesPerDay),
      );
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("task", at(day, 5), at(day, 5, 30)),
        ]),
        shown,
        recordsMoves: true,
      );
      await harness.pump(tester);
      final from = tester.getRect(blockFinder("task", day)).topLeft;
      await moveBlock(
        tester,
        blockFinder("task", day),
        slotRect(tester, shown, day, 90).topLeft -
            from +
            const Offset(0.0, 2.0),
      );
      final first = day.add(const Duration(minutes: 90));
      expect(timesOf(harness.moves), <(DateTime, DateTime)>[
        (first, first.add(const Duration(minutes: 30))),
      ]);
    });
  });

  group("the hours' edges", () {
    final edgeViews = <Shown>[
      Shown.week(monday),
      Shown.day(monday),
      Shown.day(monday, hours: CalendarDayHours(8 * 60, 18 * 60)),
    ];

    /// Monday at [minute] past its midnight, the next midnight for 1440.
    DateTime mondayAt(int minute) {
      return DateTime(2026, 4, 20, 0, minute);
    }

    /// The height of one slot of [shown].
    double slotHeightOf(WidgetTester tester, Shown shown) {
      final start = shown.hours.start;
      return slotRect(tester, shown, monday, start + shown.slotMinutes).top -
          slotRect(tester, shown, monday, start).top;
    }

    testWidgets("TP28 in Week and in Day, over the whole day and over part "
        "of it, a block dragged past the last slot lands ending at the "
        "hours' end, and one dragged above the first slot starting at their "
        "start", (tester) async {
      for (final shown in edgeViews) {
        final start = shown.hours.start;
        final end = shown.hours.end;
        final late = entryOf("late", mondayAt(end - 120), mondayAt(end - 60));
        final early = entryOf(
          "early",
          mondayAt(start + 60),
          mondayAt(start + 120),
        );
        final store = storeOf(<CalendarEntry<String>>[late, early]);
        await Harness(store, shown).pump(tester);
        final slot = slotHeightOf(tester, shown);
        // Six slots: the block's top half an hour past the last hour's.
        await moveBlock(
          tester,
          blockFinder("late", monday),
          Offset(0.0, slot * 6),
        );
        expect(
          store.storedEntry("late"),
          late.copyWith(start: mondayAt(end - 60), end: mondayAt(end)),
          reason: shown.name,
        );
        // The pointer onto the first slot's top, the block's half an hour
        // above it.
        await moveBlock(
          tester,
          blockFinder("early", monday),
          Offset(0.0, -slot * 6),
        );
        expect(
          store.storedEntry("early"),
          early.copyWith(start: mondayAt(start), end: mondayAt(start + 60)),
          reason: shown.name,
        );
      }
    });

    testWidgets("TP29 in Week and in Day, over the whole day and over part "
        "of it, a bottom handle dragged past the last slot ends its entry at "
        "the hours' end, and a top handle dragged above the first slot "
        "starts it at their start", (tester) async {
      for (final shown in edgeViews) {
        final start = shown.hours.start;
        final end = shown.hours.end;
        final late = entryOf("late", mondayAt(end - 120), mondayAt(end - 60));
        final early = entryOf(
          "early",
          mondayAt(start + 60),
          mondayAt(start + 120),
        );
        final store = storeOf(<CalendarEntry<String>>[late, early]);
        await Harness(store, shown).pump(tester);
        final slot = slotHeightOf(tester, shown);
        await selectBlock(tester, blockFinder("late", monday));
        await resizeEnd(
          tester,
          blockFinder("late", monday),
          Offset(0.0, slot * 6),
        );
        expect(
          store.storedEntry("late"),
          late.copyWith(end: mondayAt(end)),
          reason: shown.name,
        );
        await selectBlock(tester, blockFinder("early", monday));
        await resizeStart(
          tester,
          blockFinder("early", monday),
          Offset(0.0, -slot * 6),
        );
        expect(
          store.storedEntry("early"),
          early.copyWith(start: mondayAt(start)),
          reason: shown.name,
        );
      }
    });

    testWidgets("TP30 in Day, over the whole day and over part of it, a "
        "block dragged past the last slot while another entry holds it "
        "lands at the free time just before that entry", (tester) async {
      for (final shown in edgeViews.skip(1)) {
        final end = shown.hours.end;
        final move = entryOf("move", mondayAt(end - 180), mondayAt(end - 120));
        final last = entryOf("last", mondayAt(end - 30), mondayAt(end));
        final store = storeOf(<CalendarEntry<String>>[move, last]);
        await Harness(store, shown, allowsOverlaps: false).pump(tester);
        final slot = slotHeightOf(tester, shown);
        await moveBlock(
          tester,
          blockFinder("move", monday),
          Offset(0.0, slot * 10),
        );
        expect(
          store.storedEntry("move"),
          move.copyWith(start: mondayAt(end - 90), end: mondayAt(end - 30)),
          reason: shown.name,
        );
      }
    });
  });

  group(
    "on the day whose clock skips its midnight",
    skip: skippedMidnightSkip,
    () {
      testWidgets("TP36 in Week and in Day, an entry from the day's start "
          "draws from the 01:00 row, and one from the day before from the "
          "00:00 row", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final early = entryOf("early", day, at(day, 2));
        final night = entryOf("night", at(before, 23), at(day, 2));
        for (final shown in <Shown>[
          Shown.week(CalendarDates.addDays(day, -6)),
          Shown.day(day),
        ]) {
          await Harness(
            storeOf(<CalendarEntry<String>>[early, night]),
            shown,
          ).pump(tester);
          final col = shown.colOf(day);
          final rect = tester.getRect(blockFinder("early", day));
          expect(
            rect.top,
            moreOrLessEquals(cellRect(tester, shown.rowOf(60), col).top),
            reason: shown.name,
          );
          // Guard, as the bottom of night's block below: red when a time
          // reads at its elapsed minutes from its day's start.
          expect(
            rect.bottom,
            moreOrLessEquals(cellRect(tester, shown.rowOf(120), col).top),
            reason: shown.name,
          );
          // Guard: red when a piece starts at its day's first minute the
          // clock reads.
          final continued = tester.getRect(blockFinder("night", day));
          expect(
            continued.top,
            moreOrLessEquals(cellRect(tester, shown.rowOf(0), col).top),
            reason: shown.name,
          );
          expect(
            continued.bottom,
            moreOrLessEquals(cellRect(tester, shown.rowOf(120), col).top),
            reason: shown.name,
          );
        }
      });

      testWidgets("TP37 in Day, a create drag between the 00:00 and the "
          "01:00 slots reports nothing either way, and a tap on the 01:00 "
          "slot creates from the day's start", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final shown = Shown.day(day);
        final harness = Harness(
          storeOf(const <CalendarEntry<String>>[]),
          shown,
        );
        await harness.pump(tester);
        // Guard: red when a press on the 00:00 slot starts a range and its
        // start reads the day's start.
        await createDrag(
          tester,
          slotRect(tester, shown, day, 0).center,
          slotRect(tester, shown, day, 60).center,
        );
        expect(harness.creates, isEmpty);
        await createDrag(
          tester,
          slotRect(tester, shown, day, 60).center,
          slotRect(tester, shown, day, 0).center,
        );
        expect(harness.creates, isEmpty);
        // Setup sanity: the 01:00 slot is the day's first.
        await tester.tapAt(slotRect(tester, shown, day, 60).center);
        await tester.pumpAndSettle();
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(
            start: day,
            end: day.add(const Duration(minutes: 15)),
          ),
        ]);
      });

      testWidgets("TP38 in Day, a move and a start edge onto the 00:00 row "
          "request nothing, and a move onto the 01:00 row starts at the "
          "day's start", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final shown = Shown.day(day);
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("long", at(day, 5), at(day, 7)),
            entryOf("edge", at(day, 2), at(day, 3)),
          ]),
          shown,
          recordsMoves: true,
        );
        await harness.pump(tester);

        var from = tester.getRect(blockFinder("long", day)).topLeft;
        await moveBlock(
          tester,
          blockFinder("long", day),
          slotRect(tester, shown, day, 0).topLeft -
              from +
              const Offset(0.0, 2.0),
        );
        expect(harness.moves, isEmpty);

        final edge = blockFinder("edge", day);
        await selectBlock(tester, edge);
        await resizeStart(
          tester,
          edge,
          Offset(
            0.0,
            slotRect(tester, shown, day, 0).top - tester.getRect(edge).top,
          ),
        );
        expect(harness.moves, isEmpty);

        // Setup sanity: the same move onto the 01:00 row lands.
        from = tester.getRect(blockFinder("long", day)).topLeft;
        await moveBlock(
          tester,
          blockFinder("long", day),
          slotRect(tester, shown, day, 60).topLeft -
              from +
              const Offset(0.0, 2.0),
        );
        expect(timesOf(harness.moves), <(DateTime, DateTime)>[
          (day, at(day, 3)),
        ]);
      });

      testWidgets("TP39 in Week, an end edge dragged to the day before's "
          "bottom and a create drag to its last slot end at the day's "
          "start", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("late", at(before, 22), at(before, 23)),
          ]),
          shown,
          recordsMoves: true,
        );
        await harness.pump(tester);
        // Guard: red when a create's end converts by the clock. It runs
        // before the resize, whose selection a press elsewhere clears.
        await createDrag(
          tester,
          slotRect(tester, shown, before, 23 * 60).center,
          slotRect(tester, shown, before, 23 * 60 + 45).center,
        );
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(start: at(before, 23), end: day),
        ]);
        final slot = slotRect(tester, shown, before, 0).height;
        final block = blockFinder("late", before);
        await selectBlock(tester, block);
        // Guard: red when the end edge converts by the clock.
        await resizeEnd(tester, block, Offset(0.0, slot * 4));
        expect(timesOf(harness.moves), <(DateTime, DateTime)>[
          (at(before, 22), day),
        ]);
      });

      testWidgets("TP42 in Week, the day's piece of an entry from the day "
          "before, dropped with its top on the 02:00 row, moves the entry by "
          "the hour from the day's start, 01:00", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("night", at(before, 23), at(day, 2)),
        ]);
        await Harness(store, shown).pump(tester);
        final from = tester.getRect(blockFinder("night", day)).topLeft;
        // Guard: red when the anchor of the piece's top, minute 0, reads by
        // the clock, which names no time there.
        await moveBlock(
          tester,
          blockFinder("night", day),
          slotRect(tester, shown, day, 2 * 60).topLeft -
              from +
              const Offset(0.0, 2.0),
        );
        final moved = store.storedEntry("night")!;
        expect((moved.start, moved.end), (day, at(day, 3)));
      });
    },
  );

  group(
    "on the day whose clock repeats its midnight",
    skip: repeatedMidnightSkip,
    () {
      testWidgets("TP40 in Day, an entry in the later pass moved onto the "
          "00:00 row starts at the later 00:00", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final shown = Shown.day(day);
        final start = laterMidnight.add(const Duration(minutes: 15));
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("later", start, start.add(const Duration(minutes: 30))),
          ]),
          shown,
          recordsMoves: true,
        );
        await harness.pump(tester);
        final from = tester.getRect(blockFinder("later", day)).topLeft;
        // Setup sanity: the block lies at the 00:15 row.
        expect(from.dy, moreOrLessEquals(slotRect(tester, shown, day, 15).top));
        await moveBlock(
          tester,
          blockFinder("later", day),
          slotRect(tester, shown, day, 0).topLeft -
              from +
              const Offset(0.0, 2.0),
        );
        expect(timesOf(harness.moves), <(DateTime, DateTime)>[
          (laterMidnight, laterMidnight.add(const Duration(minutes: 30))),
        ]);
      });

      testWidgets("TP41 in Week, an entry moved to end at the later 00:00 is "
          "stored, draws on that day to the 01:00 row, and holds its end "
          "grip there", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        // Two hours from the day's start, drawn from the 00:00 row to the
        // 01:00 row: a block short enough to drop on the day before's last
        // hour, where it ends two hours after 23:00.
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("late", day, day.add(const Duration(hours: 2))),
        ]);
        await Harness(store, shown).pump(tester);
        final from = tester.getRect(blockFinder("late", day)).topLeft;
        await moveBlock(
          tester,
          blockFinder("late", day),
          slotRect(tester, shown, before, 23 * 60).topLeft -
              from +
              const Offset(0.0, 2.0),
        );
        final moved = store.storedEntry("late")!;
        expect(moved.start, at(before, 23));
        expect(moved.end, laterMidnight);
        expect(blockFinder("late", before), findsOneWidget);
        expect(
          tester.getRect(blockFinder("late", day)).bottom,
          moreOrLessEquals(
            cellRect(tester, shown.rowOf(60), shown.colOf(day)).top,
          ),
        );
        await selectBlock(tester, blockFinder("late", day));
        expect(
          find.descendant(
            of: blockFinder("late", day),
            matching: find.byKey(blockGripKey("late", AxisDirection.down)),
          ),
          findsOneWidget,
        );
        // Guard: red when every piece holds the end grip.
        expect(
          find.descendant(
            of: blockFinder("late", before),
            matching: find.byKey(blockGripKey("late", AxisDirection.down)),
          ),
          findsNothing,
        );
      });

      testWidgets("TP43 in Day under 00:00-18:00, an hour moved onto the "
          "00:00 row from a later time requests the earlier 00:00 to the "
          "later 00:00", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final hours = CalendarDayHours(0, 18 * 60);
        final shown = Shown.day(day, hours: hours);
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("hour", at(day, 3), at(day, 4)),
          ], hours: hours),
          shown,
          recordsMoves: true,
        );
        await harness.pump(tester);
        final from = tester.getRect(blockFinder("hour", day)).topLeft;
        await moveBlock(
          tester,
          blockFinder("hour", day),
          slotRect(tester, shown, day, 0).topLeft -
              from +
              const Offset(0.0, 2.0),
        );
        expect(timesOf(harness.moves), <(DateTime, DateTime)>[
          (day, laterMidnight),
        ]);
      });

      testWidgets("TP44 in Day, an entry from the day before ending at the "
          "later 00:00 draws to the 01:00 row, and its end edge dragged up "
          "a slot requests an end at the first 00:45", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final shown = Shown.day(day);
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("late", at(before, 23), laterMidnight),
          ]),
          shown,
          recordsMoves: true,
        );
        await harness.pump(tester);
        final block = blockFinder("late", day);
        expect(
          tester.getRect(block).bottom,
          moreOrLessEquals(
            cellRect(tester, shown.rowOf(60), shown.colOf(day)).top,
          ),
        );
        final slot = slotRect(tester, shown, day, 0).height;
        await selectBlock(tester, block);
        await resizeEnd(tester, block, Offset(0.0, -slot - 2.0));
        expect(timesOf(harness.moves), <(DateTime, DateTime)>[
          (at(before, 23), day.add(const Duration(minutes: 45))),
        ]);
      });

      testWidgets("TP48 in Day, the first 00:30 to the later 00:15 draws to "
          "the 01:15 row, and its end edge dragged up a slot requests an end "
          "at the later 00:00", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final shown = Shown.day(day);
        final first = day.add(const Duration(minutes: 30));
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("folds", first, first.add(const Duration(minutes: 45))),
          ]),
          shown,
          recordsMoves: true,
        );
        await harness.pump(tester);
        final block = blockFinder("folds", day);
        // Setup sanity: the end edge lies at the start plus the length, not
        // at the end's 00:15.
        expect(
          tester.getRect(block).bottom,
          moreOrLessEquals(slotRect(tester, shown, day, 75).top),
        );
        final slot = slotRect(tester, shown, day, 0).height;
        await selectBlock(tester, block);
        await resizeEnd(tester, block, Offset(0.0, -slot - 2.0));
        expect(timesOf(harness.moves), <(DateTime, DateTime)>[
          (first, laterMidnight),
        ]);
      });

      testWidgets("TP53 in Day, a tap on the 00:45 row reports a range from "
          "the first 00:45 to the later 00:00, where the first pass ends", (
        tester,
      ) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final shown = Shown.day(day);
        final harness = Harness(
          storeOf(const <CalendarEntry<String>>[]),
          shown,
        );
        await harness.pump(tester);
        await tester.tapAt(slotRect(tester, shown, day, 45).center);
        await tester.pumpAndSettle();
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(
            start: day.add(const Duration(minutes: 45)),
            end: laterMidnight,
          ),
        ]);
      });
    },
  );

  group(
    "on the day whose clock repeats its last hour",
    skip: repeatedLastHourSkip,
    () {
      testWidgets("TP50 in Week and in Day, the first 23:30 to the second "
          "23:30 draws to the day's 24:00 and holds its end grip there", (
        tester,
      ) async {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final first = day.add(const Duration(minutes: 23 * 60 + 30));
        for (final shown in <Shown>[
          Shown.week(CalendarDates.addDays(day, -6)),
          Shown.day(day),
        ]) {
          await Harness(
            storeOf(<CalendarEntry<String>>[
              entryOf("folds", first, first.add(const Duration(hours: 1))),
            ]),
            shown,
          ).pump(tester);
          final block = blockFinder("folds", day);
          expect(
            tester.getRect(block).bottom,
            moreOrLessEquals(slotRect(tester, shown, day, 23 * 60 + 45).bottom),
            reason: shown.name,
          );
          await selectBlock(tester, block);
          expect(
            find.descendant(
              of: block,
              matching: find.byKey(blockGripKey("folds", AxisDirection.down)),
            ),
            findsOneWidget,
            reason: shown.name,
          );
        }
      });

      testWidgets("TP51 in Day, the first 23:30 to the second 23:30 with its "
          "end edge dragged up a slot requests an end at the first 23:45", (
        tester,
      ) async {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final shown = Shown.day(day);
        final first = day.add(const Duration(minutes: 23 * 60 + 30));
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("folds", first, first.add(const Duration(hours: 1))),
          ]),
          shown,
          recordsMoves: true,
        );
        await harness.pump(tester);
        final block = blockFinder("folds", day);
        final slot = slotRect(tester, shown, day, 0).height;
        await selectBlock(tester, block);
        await resizeEnd(tester, block, Offset(0.0, -slot - 2.0));
        expect(timesOf(harness.moves), <(DateTime, DateTime)>[
          (first, first.add(const Duration(minutes: 15))),
        ]);
      });

      testWidgets("TP54 in Day, a tap on the 23:45 row reports a range from "
          "the first 23:45 to the later 23:00, where the first pass ends", (
        tester,
      ) async {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final shown = Shown.day(day);
        final harness = Harness(
          storeOf(const <CalendarEntry<String>>[]),
          shown,
        );
        await harness.pump(tester);
        await tester.tapAt(slotRect(tester, shown, day, 23 * 60 + 45).center);
        await tester.pumpAndSettle();
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(
            start: day.add(const Duration(minutes: 23 * 60 + 45)),
            end: laterLastHour,
          ),
        ]);
      });
    },
  );
}
