/// CalendarView's creates on the local zone's DST days: under a history
/// lock at the second 01:30 of the 25-hour day, Agenda's add, Month's long
/// press and a tap on Day's 01:30 row create from that occurrence; on that
/// day no create is offered over time an entry holds, though the entry is
/// drawn on other rows, and a create drag runs to the entries around it in
/// the occurrence its times take; and on the 23-hour day Agenda's add after
/// an entry ending next to the skipped hour creates at the first slot the
/// clock reads.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

import '../dst_days.dart';

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

/// Pumps an editable calendar on [view] over [day] with [entries], its
/// clock at [now], under the history lock of earlier today where [lock]
/// holds and the unrestricted policy otherwise, each allowing overlaps as
/// [allowsOverlaps] says, and returns the ranges it reports for a create.
/// Agenda's add buttons read "add" and their minute.
Future<List<CreateRange>> pumpCalendar(
  WidgetTester tester, {
  required CalendarViewKind view,
  required DateTime day,
  required DateTime now,
  List<CalendarEntry<String>> entries = const <CalendarEntry<String>>[],
  bool lock = true,
  bool allowsOverlaps = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800.0, 1200.0);
  addTearDown(tester.view.reset);
  final store = MemoryCalendarStore<String>(entries: entries);
  addTearDown(store.dispose);
  final controller = CalendarController(view: view, selectedDay: day);
  addTearDown(controller.dispose);
  final creates = <CreateRange>[];
  await tester.pumpWidget(
    MaterialApp(
      home: CalendarView<String>(
        store: store,
        controller: controller,
        clock: () {
          return now;
        },
        editable: true,
        editPolicy: lock
            ? HistoryLockPolicy<String>(
                lockEarlierToday: true,
                allowsOverlaps: allowsOverlaps,
              )
            : UnrestrictedEditPolicy<String>(allowsOverlaps: allowsOverlaps),
        onCreateRange: (range) async {
          creates.add(range);
        },
        addButtonBuilder: (context, details) {
          return GestureDetector(
            onTap: details.onPressed,
            child: Text("add ${details.startMinute}"),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return creates;
}

/// The add button of Agenda's gap on [day] from [start].
Finder addIn(DateTime day, int start) {
  return find.descendant(
    of: find.byKey(dayListGapKey(day, start)),
    matching: find.textContaining("add "),
  );
}

/// The global rect of the Day grid's slot starting at [minute].
Rect slotRect(WidgetTester tester, int minute) {
  final grid = tester.widget<TimedGrid<String>>(find.byType(TimedGrid<String>));
  final board = tester.widget<Board<GridKey, GridShape<String>>>(
    find.byType(Board<GridKey, GridShape<String>>),
  );
  final firstSlotRow =
      board.controller.rows.axis.trackCount -
      grid.hours.slotCountOf(grid.slotMinutes) -
      1;
  final viewport = tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
  final rect = viewport.rectOfCell(
    firstSlotRow + (minute - grid.hours.start) ~/ grid.slotMinutes,
    1,
  )!;
  return viewport.localToGlobal(rect.topLeft) & rect.size;
}

/// Drags a create on the Day grid from its slot starting at [from] to its
/// slot starting at [to], by way of the point halfway, and releases it.
Future<void> dragSlots(WidgetTester tester, int from, int to) async {
  final start = slotRect(tester, from).center;
  final end = slotRect(tester, to).center;
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(Offset.lerp(start, end, 0.5)!);
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group("on the 25-hour day", skip: longDaySkip, () {
    CreateRange secondSlot() {
      return CreateRange(
        start: secondHalfPastOne,
        end: secondHalfPastOne.add(const Duration(minutes: 15)),
      );
    }

    testWidgets("CV30 under the lock at the second 01:30, Agenda's add "
        "creates from the second 01:30", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.agenda,
        day: day,
        now: secondHalfPastOne,
      );
      await tester.tap(addIn(day, 0));
      await tester.pumpAndSettle();
      expect(creates, <CreateRange>[secondSlot()]);
    });

    testWidgets("CV31 under the lock at the second 01:30, Month's long press "
        "creates from the second 01:30", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.month,
        day: day,
        now: secondHalfPastOne,
      );
      await tester.longPress(find.byKey(monthStripKey(day)));
      await tester.pumpAndSettle();
      expect(creates, <CreateRange>[secondSlot()]);
    });

    testWidgets("CV32 under the lock at the second 01:30, a tap on Day's "
        "01:30 row creates from the second 01:30", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.day,
        day: day,
        now: secondHalfPastOne,
      );
      await tester.tapAt(slotRect(tester, 90).center);
      await tester.pumpAndSettle();
      expect(creates, <CreateRange>[secondSlot()]);
    });

    /// An entry from the first 01:45 to 02:00, 75 minutes, drawn on the
    /// 01:45 row alone, which holds the whole of the second 01:00 to 02:00.
    CalendarEntry<String> across() {
      final day = longDayStart;
      return entryOf(
        "across",
        day.add(const Duration(minutes: 105)),
        day.add(const Duration(minutes: 180)),
      );
    }

    testWidgets("CV34 under the lock at the second 01:30, a tap on Day's "
        "01:30 row creates nothing where an entry from the first 01:45 to "
        "02:00 holds that time", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.day,
        day: day,
        now: secondHalfPastOne,
        entries: <CalendarEntry<String>>[across()],
        allowsOverlaps: false,
      );
      await tester.tapAt(slotRect(tester, 90).center);
      await tester.pumpAndSettle();
      expect(creates, isEmpty);
    });

    testWidgets("CV35 under the lock at the second 01:30, Agenda offers no "
        "add before an entry from the first 01:45 to 02:00, and its add "
        "after it creates at 02:00", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.agenda,
        day: day,
        now: secondHalfPastOne,
        entries: <CalendarEntry<String>>[across()],
      );
      expect(addIn(day, 0), findsNothing);
      await tester.tap(addIn(day, 120));
      await tester.pumpAndSettle();
      expect(creates, <CreateRange>[
        CreateRange(
          start: day.add(const Duration(minutes: 180)),
          end: day.add(const Duration(minutes: 195)),
        ),
      ]);
    });

    /// An entry from 00:00 to the second 01:15, 135 minutes, drawn on the
    /// rows to 01:15, which holds the whole of the first 01:15 to 02:00.
    CalendarEntry<String> folds() {
      final day = longDayStart;
      return entryOf("folds", day, day.add(const Duration(minutes: 135)));
    }

    testWidgets("CV36 a tap on Day's 01:30 row creates nothing where an "
        "entry from 00:00 to the second 01:15 holds that time", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.day,
        day: day,
        now: at(day, 0, 30),
        entries: <CalendarEntry<String>>[folds()],
        lock: false,
        allowsOverlaps: false,
      );
      await tester.tapAt(slotRect(tester, 90).center);
      await tester.pumpAndSettle();
      expect(creates, isEmpty);
    });

    testWidgets("CV37 Agenda's add after an entry from 00:00 to the second "
        "01:15 creates at 02:00, the first slot that entry leaves free", (
      tester,
    ) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.agenda,
        day: day,
        now: at(day, 0, 30),
        entries: <CalendarEntry<String>>[folds()],
        lock: false,
      );
      expect(find.text("add 75"), findsNothing);
      await tester.tap(addIn(day, 75));
      await tester.pumpAndSettle();
      expect(creates, <CreateRange>[
        CreateRange(
          start: day.add(const Duration(minutes: 180)),
          end: day.add(const Duration(minutes: 195)),
        ),
      ]);
    });

    testWidgets("CV38 a create dragged from Day's 02:00 row up to its 01:15 "
        "row, past an entry from 00:00 to the second 01:15, holds at 02:00", (
      tester,
    ) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.day,
        day: day,
        now: at(day, 0, 30),
        entries: <CalendarEntry<String>>[folds()],
        lock: false,
        allowsOverlaps: false,
      );
      await dragSlots(tester, 120, 75);
      expect(creates, <CreateRange>[
        CreateRange(
          start: day.add(const Duration(minutes: 180)),
          end: day.add(const Duration(minutes: 195)),
        ),
      ]);
    });

    testWidgets("CV39 a create dragged from Day's 00:45 row down to its 01:45 "
        "row, before an entry from the second 01:00 to 01:30, reaches the "
        "first 01:45", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.day,
        day: day,
        now: at(day, 0, 30),
        entries: <CalendarEntry<String>>[
          entryOf(
            "later",
            day.add(const Duration(minutes: 120)),
            day.add(const Duration(minutes: 150)),
          ),
        ],
        lock: false,
        allowsOverlaps: false,
      );
      await dragSlots(tester, 45, 105);
      expect(creates, <CreateRange>[
        CreateRange(
          start: day.add(const Duration(minutes: 45)),
          end: day.add(const Duration(minutes: 105)),
        ),
      ]);
    });

    testWidgets("CV40 under the lock at the second 01:00, a create dragged "
        "from Day's 01:30 row up to its 01:00 row, after an entry from 00:30 "
        "to the first 01:15, starts at the second 01:00", (tester) async {
      final day = longDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.day,
        day: day,
        now: day.add(const Duration(minutes: 120)),
        entries: <CalendarEntry<String>>[
          entryOf(
            "earlier",
            day.add(const Duration(minutes: 30)),
            day.add(const Duration(minutes: 75)),
          ),
        ],
      );
      await dragSlots(tester, 90, 60);
      expect(creates, <CreateRange>[
        CreateRange(
          start: day.add(const Duration(minutes: 120)),
          end: day.add(const Duration(minutes: 165)),
        ),
      ]);
    });
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    testWidgets("CV33 after an entry ending at 01:45, Agenda's add creates "
        "at 03:00, the first slot whose start and end the clock reads", (
      tester,
    ) async {
      final day = shortDayStart;
      final creates = await pumpCalendar(
        tester,
        view: CalendarViewKind.agenda,
        day: day,
        now: at(day, 0, 10),
        entries: <CalendarEntry<String>>[
          entryOf("early", at(day, 0, 30), at(day, 1, 45)),
        ],
        lock: false,
      );
      expect(find.text("add 180"), findsOneWidget);
      await tester.tap(addIn(day, 105));
      await tester.pumpAndSettle();
      expect(creates, <CreateRange>[
        CreateRange(start: at(day, 3), end: at(day, 3, 15)),
      ]);
    });
  });
}
