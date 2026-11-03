/// Agenda's day list on start and end: a timed entry listed under each day
/// it covers with that day's part of it, all-day entries above the timed
/// ones, the local zone's DST days listed once, the history lock read on
/// start and end, a gap shorter than a slot offering no add button, and the
/// slot an add button creates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';

import '../../scheduling/dst_days.dart';

typedef Shown = CalendarShownEntry<String>;

final DateTime sunday = DateTime(2026, 4, 19);
final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

/// [day] at [hour] and [minute] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

CalendarEntry<String> entryOf(
  String id,
  DateTime start,
  DateTime end, {
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: isAllDay,
  );
}

/// [dayListRowsOf] of [store]'s entries on [day], each entry's row as its
/// id, its piece's minutes and whether it is all-day, each gap as its
/// start and end.
List<Object> rowsOf(
  CalendarStore<String> store,
  DateTime day, {
  CalendarDayHours hours = CalendarDayHours.allDay,
  bool editable = false,
}) {
  return <Object>[
    for (final row in dayListRowsOf(
      day,
      store.entriesOn(day),
      hours,
      editable: editable,
    ))
      switch (row) {
        DayListEntry(:final entry, :final start, :final end, :final allDay) => (
          entry.id,
          start,
          end,
          allDay,
        ),
        DayListGap(:final start, :final end) => (start, end),
        DayListHidden(:final count, :final above) => (
          above ? "before" : "after",
          count,
        ),
        _ => throw StateError("$row is not an entry, a gap or a banner."),
      },
  ];
}

/// A store holding [entries], disposed at the test's end.
MemoryCalendarStore<String> storeOf(List<CalendarEntry<String>> entries) {
  final store = MemoryCalendarStore<String>(entries: entries);
  addTearDown(store.dispose);
  return store;
}

/// Pumps the day list over [store] on [day], with [editPolicy] and slots of
/// [slotMinutes], in edit mode unless not [editable]; [cards] records the
/// details each card is built with, [creates] each create an add button
/// reports, and an add button reads "add" and its minute.
Future<void> pumpList(
  WidgetTester tester,
  CalendarStore<String> store,
  DateTime day, {
  CalendarEditPolicy<String>? editPolicy,
  bool editable = true,
  int slotMinutes = 15,
  Map<String, List<CalendarCardDetails>>? cards,
  List<CalendarCreateRange>? creates,
}) async {
  final now = ValueNotifier<CalendarNow>(
    CalendarNow(time: at(day, 9), today: day),
  );
  addTearDown(now.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(600.0, 2400.0);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: DayList<String>(
        key: UniqueKey(),
        store: store,
        weekdays: CalendarWeekdaySet.all,
        format: CalendarHourLabelFormat.twentyFourHour,
        hours: CalendarDayHours.allDay,
        slotMinutes: slotMinutes,
        editable: editable,
        editPolicy: editPolicy,
        selectedDay: day,
        now: now,
        onTopDay: (day) {},
        onCreateRange: (range) {
          creates?.add(range);
        },
        onEdit: (id) {},
        onDelete: (id) {},
        cardBuilder: (context, entry, details) {
          if (cards != null) {
            (cards[entry.id] ??= <CalendarCardDetails>[]).add(details);
          }
          return Text("card ${entry.id}");
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
}

void main() {
  testWidgets("AG1 Monday 22:00 to Tuesday 02:00 is listed under both days, "
      "labelled 22:00-24:00 and 00:00-02:00", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(tuesday, 2)),
    ]);
    expect(rowsOf(store, monday), <Object>[("night", 1320, 1440, false)]);
    expect(rowsOf(store, tuesday), <Object>[("night", 0, 120, false)]);

    await pumpList(tester, store, monday);
    final times = find.byKey(dayListTimeKey("night"));
    expect(times, findsNWidgets(2));
    expect(
      find.descendant(of: times, matching: find.text("22:00-24:00")),
      findsOneWidget,
    );
    expect(
      find.descendant(of: times, matching: find.text("00:00-02:00")),
      findsOneWidget,
    );
    // The two rows sit in the order of their days.
    expect(
      tester.getTopLeft(find.text("22:00-24:00")).dy <
          tester.getTopLeft(find.text("00:00-02:00")).dy,
      isTrue,
    );
  });

  test("AG2 all-day entries are listed above the day's timed entries", () {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("late", at(sunday, 23), at(monday, 1)),
      entryOf("all-day", monday, tuesday, isAllDay: true),
      entryOf("trip", sunday, at(tuesday, 0), isAllDay: true),
      entryOf("talk", at(monday, 9), at(monday, 10)),
    ]);
    expect(rowsOf(store, monday), <Object>[
      ("trip", 0, 1440, true),
      ("all-day", 0, 1440, true),
      ("late", 0, 60, false),
      ("talk", 540, 600, false),
    ]);
    expect(rowsOf(store, monday, editable: true), <Object>[
      ("trip", 0, 1440, true),
      ("all-day", 0, 1440, true),
      ("late", 0, 60, false),
      (60, 540),
      ("talk", 540, 600, false),
      (600, 1440),
    ]);
  });

  testWidgets("AG5 under lockPast, the card of yesterday 22:00 to today "
      "02:00 offers no Delete, while a later entry's does", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(tuesday, 2)),
      entryOf("later", at(tuesday, 10), at(tuesday, 11)),
    ]);
    final cards = <String, List<CalendarCardDetails>>{};
    await pumpList(
      tester,
      store,
      tuesday,
      editPolicy: const HistoryLockPolicy<String>(),
      cards: cards,
    );
    expect(cards["night"], isNotEmpty);
    for (final details in cards["night"]!) {
      expect(details.onDelete, isNull);
      expect(details.onEdit, isNotNull);
    }
    expect(cards["later"]!.last.onDelete, isNotNull);
  });

  testWidgets("AG6 at slot 15, a gap of 10 minutes between entries ending "
      "at 09:50 and starting at 10:00 offers no add button", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("first", at(tuesday, 9), at(tuesday, 9, 50)),
      entryOf("second", at(tuesday, 10), at(tuesday, 11)),
    ]);
    expect(rowsOf(store, tuesday, editable: true), <Object>[
      (0, 540),
      ("first", 540, 590, false),
      (590, 600),
      ("second", 600, 660, false),
      (660, 1440),
    ]);
    await pumpList(tester, store, tuesday);
    expect(find.byKey(dayListGapKey(tuesday, 590)), findsOneWidget);
    expect(find.text("add 590"), findsNothing);
    expect(find.text("add 660"), findsOneWidget);
  });

  testWidgets("AG4 at slot 30 Agenda's add button reports 30 minutes, and "
      "a gap shorter than 30 minutes offers none", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("first", at(tuesday, 9), at(tuesday, 9, 40)),
      entryOf("second", at(tuesday, 10), at(tuesday, 11)),
    ]);
    final creates = <CalendarCreateRange>[];
    await pumpList(tester, store, tuesday, slotMinutes: 30, creates: creates);
    // The 20 minutes from 09:40 hold no 30-minute slot.
    expect(find.byKey(dayListGapKey(tuesday, 580)), findsOneWidget);
    expect(find.text("add 580"), findsNothing);
    await tester.tap(find.text("add 660"));
    await tester.pumpAndSettle();
    expect(creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(tuesday, 11), end: at(tuesday, 11, 30)),
    ]);
  });

  testWidgets("AG8 a timed entry from Tuesday's start to Wednesday's is "
      "listed as a timed row at 00:00, with its length on the chip", (
    tester,
  ) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("whole", tuesday, DateTime(2026, 4, 22)),
    ]);
    expect(rowsOf(store, tuesday), <Object>[("whole", 0, 1440, false)]);

    await pumpList(tester, store, tuesday);
    final time = find.byKey(dayListTimeKey("whole"));
    expect(
      find.descendant(of: time, matching: find.text("00:00")),
      findsOneWidget,
    );
    expect(
      find.descendant(of: time, matching: find.text("All day")),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(dayListDurationKey("whole")),
        matching: find.text(
          const DefaultCalendarLocalizations().duration(1440),
        ),
      ),
      findsOneWidget,
    );
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    testWidgets("AG3 the day is listed once with its entries", (tester) async {
      final day = shortDayStart;
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("all-day", day, CalendarDates.addDays(day, 1), isAllDay: true),
        entryOf("early", at(day, 1, 30), at(day, 3, 30)),
      ]);
      expect(rowsOf(store, day), <Object>[
        ("all-day", 0, 1440, true),
        ("early", 90, 210, false),
      ]);
      expect(rowsOf(store, CalendarDates.addDays(day, 1)), isEmpty);
      await pumpList(tester, store, day, editable: false);
      expect(find.byKey(dayListHeaderKey(day)), findsOneWidget);
      expect(find.text("card early"), findsOneWidget);
      expect(find.text("card all-day"), findsOneWidget);
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    testWidgets("AG3 the day is listed once with its entries", (tester) async {
      final day = longDayStart;
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("all-day", day, CalendarDates.addDays(day, 1), isAllDay: true),
        entryOf(
          "repeated",
          secondHalfPastOne,
          secondHalfPastOne.add(const Duration(minutes: 30)),
        ),
      ]);
      expect(rowsOf(store, day), <Object>[
        ("all-day", 0, 1440, true),
        ("repeated", 90, 120, false),
      ]);
      await pumpList(tester, store, day, editable: false);
      expect(find.byKey(dayListHeaderKey(day)), findsOneWidget);
      expect(find.text("card repeated"), findsOneWidget);
      expect(find.text("card all-day"), findsOneWidget);
    });

    testWidgets("AG7 00:30 to the second 02:30 is listed to 02:30, and the "
        "first 01:30 to the second 01:15 from 01:30 to 02:15", (tester) async {
      final day = longDayStart;
      final store = storeOf(<CalendarEntry<String>>[
        // 180 minutes, over the repeated hour.
        entryOf("spans", at(day, 0, 30), at(day, 2, 30)),
        // 45 minutes, whose end's wall time is before its start's.
        entryOf(
          "folds",
          day.add(const Duration(minutes: 90)),
          secondHalfPastOne.subtract(const Duration(minutes: 15)),
        ),
      ]);
      expect(rowsOf(store, day, editable: true), <Object>[
        (0, 30),
        ("spans", 30, 150, false),
        ("folds", 90, 135, false),
        (150, 1440),
      ]);
      await pumpList(tester, store, day);
      expect(find.byKey(dayListGapKey(day, 150)), findsOneWidget);
      expect(find.text("card folds"), findsOneWidget);
    });
  });

  group(
    "on the day whose clock skips its midnight",
    skip: skippedMidnightSkip,
    () {
      testWidgets("AG9 an entry from the day's start is listed from 01:00, "
          "the minute its clock starts at, and reads 01:00", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("early", day, at(day, 2)),
          entryOf("whole", day, CalendarDates.addDays(day, 1)),
        ]);
        expect(rowsOf(store, day), <Object>[
          ("early", 60, 120, false),
          ("whole", 60, 1440, false),
        ]);
        await pumpList(tester, store, day, editable: false);
        for (final id in <String>["early", "whole"]) {
          expect(
            find.descendant(
              of: find.byKey(dayListTimeKey(id)),
              matching: find.text("01:00"),
            ),
            findsOneWidget,
            reason: id,
          );
        }
      });

      testWidgets("AG10 in edit mode, the skipped minutes before an entry at "
          "01:00 are a gap from 00:00 with no add button", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("early", day, at(day, 2)),
        ]);
        expect(rowsOf(store, day, editable: true), <Object>[
          (0, 60),
          ("early", 60, 120, false),
          (120, 1440),
        ]);
        await pumpList(tester, store, day);
        final skipped = find.byKey(dayListGapKey(day, 0));
        expect(skipped, findsOneWidget);
        // Guard: red when a gap with no slot builds an add button at its
        // start.
        expect(
          find.descendant(of: skipped, matching: find.textContaining("add")),
          findsNothing,
        );
        // Guard: red when no gap builds an add button.
        expect(
          find.descendant(
            of: find.byKey(dayListGapKey(day, 120)),
            matching: find.text("add 120"),
          ),
          findsOneWidget,
        );
      });

      testWidgets("AG11 in edit mode, the add button before an entry later "
          "in the day is labelled at 01:00 and creates the day's first slot", (
        tester,
      ) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final handle = tester.ensureSemantics();
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("talk", at(day, 9), at(day, 10)),
        ]);
        final creates = <CalendarCreateRange>[];
        await pumpList(tester, store, day, creates: creates);
        // Anchored: the add's semantics node also takes the label of the
        // "add" text inside it, after its own.
        expect(
          find.bySemanticsLabel(RegExp(r"^Add an item at 01:00(\n|$)")),
          findsOneWidget,
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(dayListGapKey(day, 0)),
            matching: find.text("add 60"),
          ),
        );
        await tester.pumpAndSettle();
        // Guard: red when the add reports a range other than its slot.
        expect(creates, <CalendarCreateRange>[
          CalendarCreateRange(
            start: day,
            end: day.add(const Duration(minutes: 15)),
          ),
        ]);
        handle.dispose();
      });
    },
  );

  group(
    "on the day whose clock repeats its midnight",
    skip: repeatedMidnightSkip,
    () {
      testWidgets("AG12 an entry from the day before ending at the later "
          "00:00 is listed on that day from 00:00 to 01:00", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("late", at(before, 23), laterMidnight),
        ]);
        expect(rowsOf(store, day), <Object>[("late", 0, 60, false)]);
      });
    },
  );
}
