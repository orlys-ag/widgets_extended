/// The item form's times: its start and end dates and times, the slot
/// length they step by, and its All day switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';

import 'form_driver.dart';
import 'midnight_days.dart';

final DateTime wednesday = DateTime(2026, 4, 22);

/// A Task titled "Write" from [start] to [end], stored as "item-1".
CalendarItem task(DateTime start, DateTime end) {
  return calendarItem(
    id: "item-1",
    type: CalendarItemType.task,
    title: "Write",
    start: start,
    end: end,
    fields: const <String, Object?>{"status": "toDo"},
  );
}

/// Pumps a host over [store] whose one button opens the form of the item
/// "item-1", its times stepping by [slotMinutes] and its Save checked by
/// [policy], and opens it.
Future<void> openForm(
  WidgetTester tester,
  CalendarStore<ItemPayload> store, {
  int slotMinutes = CalendarDates.defaultSlotMinutes,
  CalendarEditPolicy<ItemPayload> policy =
      const UnrestrictedEditPolicy<ItemPayload>(),
  DateTime? now,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showEditForm(
                  context,
                  store: store,
                  id: "item-1",
                  policy: policy,
                  now: () {
                    return CalendarNow(
                      time: now ?? wednesday,
                      today: wednesday,
                    );
                  },
                  hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
                  slotMinutes: slotMinutes,
                );
              },
              child: const Text("Open"),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text("Open"));
  await tester.pumpAndSettle();
}

/// A policy that admits only a change to a timed item, and gives no day an
/// earliest start, so the form keys every change it refuses.
final class _TimedChangesOnly extends CalendarEditPolicy<ItemPayload> {
  const _TimedChangesOnly();

  @override
  bool admitsChange(
    CalendarEntry<ItemPayload> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
    return !isAllDay;
  }

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    return null;
  }
}

void main() {
  testWidgets("R1 a new start time moves the end and keeps the length", (
    tester,
  ) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    await pickTime(tester, "Start time", "11:00");
    expect(timeFieldShows("Start time", "11:00"), findsOneWidget);
    expect(timeFieldShows("End time", "12:00"), findsOneWidget);
  });

  testWidgets("R2 under the history lock a start before now is disabled, "
      "and one after it is not", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 11), DateTime(2026, 4, 22, 12)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(
      tester,
      store,
      policy: const HistoryLockPolicy<ItemPayload>(lockEarlierToday: true),
      now: DateTime(2026, 4, 22, 9, 30),
    );
    await openTimePicker(tester, "Start time");
    expect(timeEnabled(tester, "Start time", "09:00"), isFalse);
    expect(timeEnabled(tester, "Start time", "09:30"), isTrue);
    expect(timeEnabled(tester, "Start time", "11:00"), isTrue);
  });

  testWidgets("R3 an item sharing time with another names it before Save", (
    tester,
  ) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
        calendarItem(
          id: "item-2",
          type: CalendarItemType.task,
          title: "Standup",
          start: DateTime(2026, 4, 22, 9, 30),
          end: DateTime(2026, 4, 22, 10, 30),
          fields: const <String, Object?>{"status": "toDo"},
        ),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    expect(find.textContaining("Standup"), findsOneWidget);
  });

  testWidgets("IF1 the form shows Start date, Start time, End date, End "
      "time and All day, and All day hides the times and saves day starts", (
    tester,
  ) async {
    final writes = <CalendarItem?>[];
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 23, 10)),
      ],
      onChanged: (old, entry) {
        writes.add(entry);
      },
    );
    await openForm(tester, store);
    for (final label in <String>[
      "Start date",
      "Start time",
      "End date",
      "End time",
      "All day",
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text("2026-04-22"), findsOneWidget);
    expect(find.text("2026-04-23"), findsOneWidget);

    await tester.tap(find.text("All day"));
    await tester.pumpAndSettle();
    expect(timeFieldFinder("Start time"), findsNothing);
    expect(timeFieldFinder("End time"), findsNothing);
    expect(find.text("Start date"), findsOneWidget);
    expect(find.text("End date"), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    final saved = writes.single!;
    expect(saved.start, wednesday);
    expect(saved.end, DateTime(2026, 4, 24));
    expect(saved.isAllDay, isTrue);
    store.dispose();
  });

  testWidgets("IF2 the form's times step by the slot length it is given", (
    tester,
  ) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store, slotMinutes: 30);
    await openTimePicker(tester, "Start time");
    final starts = offeredTimes(tester, "Start time");
    expect(starts, containsAll(<int>[9 * 60, 9 * 60 + 30, 10 * 60]));
    expect(starts, isNot(contains(9 * 60 + 15)));
    expect(starts, hasLength(48));
    // On the start day the ends are the slots after the 09:00 start.
    await openTimePicker(tester, "End time");
    final ends = offeredTimes(tester, "End time");
    expect(ends.first, 9 * 60 + 30);
    expect(ends, isNot(contains(9 * 60 + 45)));

    // At the default 15 minutes the form offers the quarter hours.
    await tester.pumpWidget(const SizedBox());
    await openForm(tester, store);
    await openTimePicker(tester, "Start time");
    expect(offeredTimes(tester, "Start time"), contains(9 * 60 + 15));
    expect(offeredTimes(tester, "Start time"), hasLength(96));
  });

  testWidgets("IF3 an entry at 09:10 shows 09:10, and a save that changes "
      "nothing writes 09:10", (tester) async {
    final writes = <CalendarItem?>[];
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9, 10), DateTime(2026, 4, 22, 9, 50)),
      ],
      onChanged: (old, entry) {
        writes.add(entry);
      },
    );
    await openForm(tester, store);
    expect(timeFieldShows("Start time", "09:10"), findsOneWidget);
    expect(timeFieldShows("End time", "09:50"), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, "All day"))
          .selected,
      isFalse,
    );

    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single!.start, DateTime(2026, 4, 22, 9, 10));
    expect(writes.single!.end, DateTime(2026, 4, 22, 9, 50));
    store.dispose();
  });

  testWidgets("IF4 a timed item from a day's start to the next day's opens "
      "with All day off, and Save writes it timed at the same times", (
    tester,
  ) async {
    final writes = <CalendarItem?>[];
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 21), DateTime(2026, 4, 22)),
      ],
      onChanged: (old, entry) {
        writes.add(entry);
      },
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, "All day"))
          .selected,
      isFalse,
    );

    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    final saved = writes.single!;
    expect(saved.isAllDay, isFalse);
    expect(saved.start, DateTime(2026, 4, 21));
    expect(saved.end, DateTime(2026, 4, 22));
  });

  testWidgets("IF5 Save asks the policy with the kind of the item it saves: "
      "a timed item saved unchanged is written, and one switched to All day "
      "is refused", (tester) async {
    final writes = <CalendarItem?>[];
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
      onChanged: (old, entry) {
        writes.add(entry);
      },
    );
    addTearDown(store.dispose);
    const policy = _TimedChangesOnly();
    await openForm(tester, store, policy: policy);
    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single!.isAllDay, isFalse);

    await tester.pumpWidget(const SizedBox());
    await openForm(tester, store, policy: policy);
    await tester.tap(find.text("All day"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(find.widgetWithText(ChoiceChip, "All day"), findsOneWidget);
  });

  group(
    "on the day whose clock skips its midnight",
    skip: skippedMidnightSkip,
    () {
      testWidgets("MD4 a start time of 00:00, which the day's clock skips, "
          "is not saved", (tester) async {
        final day = shortDay!.day;
        expectSkippedMidnight(day);
        final writes = <CalendarItem?>[];
        final store = MemoryCalendarStore<ItemPayload>(
          entries: <CalendarItem>[
            task(day, DateTime(day.year, day.month, day.day, 2)),
          ],
          onChanged: (old, entry) {
            writes.add(entry);
          },
        );
        addTearDown(store.dispose);
        await openForm(tester, store);
        await openTimePicker(tester, "Start time");
        // The picker refuses the start the day's clock skips.
        expect(timeEnabled(tester, "Start time", "00:00"), isFalse);
        tester
            .widget<CalendarTimePicker>(timePickerFinder("Start time"))
            .onChanged!(0);
        await tester.pumpAndSettle();
        // Setup sanity: the start took.
        expect(timeFieldShows("Start time", "00:00"), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, "Save"));
        await tester.pumpAndSettle();
        // Guard: red also when the start converts as an end, which reads
        // 00:00 as the day's start.
        expect(writes, isEmpty);
      });

      testWidgets("MD3 an item ending at the day's start, the 24:00 before, "
          "saved unchanged, is written ending at the day's start", (
        tester,
      ) async {
        final day = shortDay!.day;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final writes = <CalendarItem?>[];
        final store = MemoryCalendarStore<ItemPayload>(
          entries: <CalendarItem>[
            task(DateTime(before.year, before.month, before.day, 23), day),
          ],
          onChanged: (old, entry) {
            writes.add(entry);
          },
        );
        addTearDown(store.dispose);
        await openForm(tester, store);
        await tester.tap(find.widgetWithText(FilledButton, "Save"));
        await tester.pumpAndSettle();
        // Guard: red when the end converts by the clock, which names no
        // time at the skipped 00:00, so the form writes the day before's
        // 24:00 as its own text, which the envelope refuses.
        expect(
          <(DateTime, DateTime)>[
            for (final written in writes) (written!.start, written.end),
          ],
          <(DateTime, DateTime)>[
            (DateTime(before.year, before.month, before.day, 23), day),
          ],
        );
      });
    },
  );
}
