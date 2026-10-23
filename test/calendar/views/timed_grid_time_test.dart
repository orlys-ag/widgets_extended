/// The timed grid on start and end: an entry drawn as one piece per shown
/// day at its exact minutes, the gestures on pieces (a move keeping the
/// entry's elapsed duration, resizes, the handles of the first and the
/// last piece, a lift of a pieced entry), the create ranges across days and
/// their day limit, and the wall-clock rows of the local zone's DST days.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

import '../dst_days.dart';

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
  const Shown.week(this.first, {this.hours = DayHours.allDay})
    : week = true;

  const Shown.day(this.first, {this.hours = DayHours.allDay}) : week = false;

  final DateTime first;
  final bool week;
  final DayHours hours;

  static const int slotMinutes = 15;

  /// The row of the first slot: under the day header and the room above
  /// the slots in Week, under the room alone in Day.
  int get firstSlotRow {
    return week ? 2 : 1;
  }

  /// The row of the slot starting at [minute].
  int rowOf(int minute) {
    return firstSlotRow + (minute - hours.start) ~/ slotMinutes;
  }

  /// The column of [day], which the grid shows.
  int colOf(DateTime day) {
    return week ? 1 + daysBetween(first, day) : 1;
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
class CountingStore extends MemoryCalendarStore<String> {
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
    final from = dayNumber(first);
    final to = dayNumber(last);
    return SynchronousFuture<List<CalendarEntry<String>>>(
      <CalendarEntry<String>>[
        for (final entry in entries)
          if (dayNumber(entry.start) <= to &&
              lastDayNumberOf(entry.start, entry.end) >= from)
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
/// create range it reports.
class Harness {
  Harness(this.store, this.shown, {this.maxDayCount, this.editable = true});

  final CalendarStore<String> store;
  final Shown shown;
  final int? maxDayCount;
  final bool editable;

  final List<CreateRange> creates = <CreateRange>[];
  final ValueNotifier<DateTime> now = ValueNotifier<DateTime>(
    DateTime(2026, 1, 5, 9),
  );

  TimedGrid<String> grid() {
    return TimedGrid<String>(
      key: ObjectKey(this),
      store: store,
      firstDay: shown.first,
      dayCount: shown.week ? 7 : 1,
      selectedDay: shown.first,
      today: DateTime(2026, 1, 5),
      now: now,
      onSelectDay: (day) {},
      onOpenItem: (id) {},
      onCreate: (range) async {
        creates.add(range);
      },
      editable: editable,
      hours: shown.hours,
      maxDayCount: maxDayCount,
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
}

/// A store holding [entries], disposed at the test's end.
CountingStore storeOf(
  List<CalendarEntry<String>> entries, {
  DayHours hours = DayHours.allDay,
}) {
  final store = CountingStore(entries: entries, hours: hours);
  addTearDown(store.dispose);
  return store;
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

/// The body of the class [name] declares in [source], comments dropped, to
/// its matching brace.
String classBody(String source, String name) {
  final code = source
      .replaceAll(RegExp(r"/\*[\s\S]*?\*/"), "")
      .replaceAll(RegExp(r"//[^\n]*"), "");
  final start = code.indexOf(RegExp("class $name\\b"));
  expect(start, isNot(-1), reason: name);
  final open = code.indexOf("{", start);
  var depth = 1;
  var at = open + 1;
  while (depth > 0) {
    final char = code[at];
    if (char == "{") {
      depth++;
    } else if (char == "}") {
      depth--;
    }
    at++;
  }
  return code.substring(open + 1, at - 1);
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
        final last = shown.rowOf(minutesPerDay - 15);
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
      monday: (10 * 60, minutesPerDay),
      tuesday: (0, minutesPerDay),
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
              cellRect(tester, shown.rowOf(minutesPerDay - 15), col).bottom,
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

  testWidgets("TP6 two entries sharing a minute sit side by side",
      (tester) async {
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

  testWidgets("TP9 an end resize writes an end on the slot grid",
      (tester) async {
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
    final from = addDays(monday, -100);
    final year = entryOf("year", at(from, 10), at(addDays(from, 366), 10));
    for (final view in views) {
      final shown = view(wednesday);
      await Harness(storeOf(<CalendarEntry<String>>[year]), shown).pump(tester);
      expect(blocksOf("year"), findsNWidgets(shown.week ? 7 : 1));
    }
  });

  testWidgets("TP21 in Week a one-day entry dropped on another day's column "
      "stays selected, and glides from the proxy's last rect", (
    tester,
  ) async {
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
    store.show(monday, addDays(monday, 6));
    final shown = Shown.week(monday);
    await Harness(store, shown).pump(tester);
    store.requestMove(night.copyWith(title: "renamed"));
    await tester.pumpAndSettle();
    expect(store.isPending("night"), isTrue);
    expect(source.replaces, hasLength(1));
    for (final day in <DateTime>[monday, tuesday]) {
      final gesture = await lift(tester, tester.getCenter(blockFinder("night", day)));
      await tester.pump();
      expect(find.byKey(liftedBlockKey), findsNothing, reason: "$day");
      await gesture.up();
      await tester.pumpAndSettle();
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
    expect(harness.creates, <CreateRange>[
      CreateRange(start: at(tuesday, 10), end: at(tuesday, 10, 15)),
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
    expect(harness.creates, <CreateRange>[
      CreateRange(start: at(monday, 10), end: at(wednesday, 12, 15)),
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
      expect(
        harness.creates,
        <CreateRange>[CreateRange(start: at(monday, 10), end: end)],
        reason: "$limit over $day",
      );
    }
  });

  testWidgets("TR3b under hours 08:00-18:00 with maxDayCount 3, a create "
      "drag from Monday 10:00 released over Thursday 12:00 reports Monday "
      "10:00 to Wednesday 18:00", (tester) async {
    const office = DayHours(8 * 60, 18 * 60);
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
    expect(harness.creates, <CreateRange>[
      CreateRange(start: at(monday, 10), end: at(wednesday, 18)),
    ]);
  });

  test("TR5 the CreateRange class declares no member of the day, minute and "
      "day-count time", () {
    final body = classBody(
      File("lib/calendar/views/timed_grid.dart").readAsStringSync(),
      "CreateRange",
    );
    bool declares(String name) {
      return RegExp(
        "(final|get)\\s+(int|DateTime)?\\s*$name\\b",
      ).hasMatch(body);
    }

    expect(declares("start") || declares("day"), isTrue);
    for (final name in const <String>[
      "day",
      "startMinute",
      "endMinute",
      "dayCount",
    ]) {
      expect(declares(name), isFalse, reason: name);
    }
  });

  testWidgets("TR6 a press on the free part of the 09:00 slot under an entry "
      "from 09:10 reports no create", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(
      storeOf(<CalendarEntry<String>>[
        entryOf("task", at(tuesday, 9, 10), at(tuesday, 9, 50)),
      ]),
      shown,
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
    expect(harness.creates, <CreateRange>[
      CreateRange(start: at(tuesday, 8, 45), end: at(tuesday, 9)),
    ]);
  });

  testWidgets("TR8 a create drag across 10 slots reads the store's entries "
      "once", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(tuesday, 15), at(tuesday, 16)),
    ]);
    final harness = Harness(store, shown);
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
    expect(harness.creates, <CreateRange>[
      CreateRange(start: at(tuesday, 10), end: at(tuesday, 12, 45)),
    ]);
    expect(store.betweenCalls - calls, 1);
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    testWidgets("TP12 in Week and in Day, the day's column shows 24 hours of "
        "rows, the same as the day beside it, and 01:30 to 03:30 draws from "
        "the 01:30 row to the 03:30 row", (tester) async {
      final day = shortDayStart;
      final early = entryOf("early", at(day, 1, 30), at(day, 3, 30));
      for (final shown in <Shown>[
        Shown.week(addDays(day, -6)),
        Shown.day(day),
      ]) {
        await Harness(storeOf(<CalendarEntry<String>>[early]), shown).pump(
          tester,
        );
        final col = shown.colOf(day);
        final viewport = viewportOf(tester);
        expect(viewport.rectOfCell(shown.rowOf(minutesPerDay - 15), col), isNotNull);
        expect(
          tester
              .widget<Board<GridKey, GridShape<String>>>(
                find.byType(Board<GridKey, GridShape<String>>),
              )
              .controller
              .rows
              .axis
              .trackCount,
          shown.firstSlotRow + 96 + 1,
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
        slotRect(tester, shown, day, 2 * 60).topLeft - from +
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
        slotRect(tester, shown, day, 90).topLeft - from +
            const Offset(0.0, 2.0),
      );
      final moved = store.storedEntry("task")!;
      expect(moved.start, at(day, 1, 30));
      expect(moved.end, at(day, 3, 30));
      expect(moved.end.difference(moved.start), const Duration(minutes: 60));
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
        Shown.week(addDays(day, -6)),
        Shown.day(day),
      ]) {
        await Harness(storeOf(<CalendarEntry<String>>[second]), shown).pump(
          tester,
        );
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
          shown.firstSlotRow + 96 + 1,
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
        slotRect(tester, shown, day, 30).topLeft - from + const Offset(0.0, 2.0),
      );
      final moved = store.storedEntry("task")!;
      expect(moved.start, at(day, 0, 30));
      expect(moved.end, day.add(const Duration(minutes: 90)));
      expect(isLaterOccurrence(moved.end), isFalse);
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
      expect(isLaterOccurrence(moved.start), isTrue);
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
      expect(harness.creates, <CreateRange>[
        CreateRange(start: first, end: first.add(const Duration(minutes: 15))),
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
  });
}
