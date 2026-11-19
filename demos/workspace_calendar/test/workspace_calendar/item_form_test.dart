/// The item form's page and its times: its start and end dates and times,
/// the slot length they step by, and its All day switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/views/week_strip.dart'
    show WeekStrip, weekStripDayKey;
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';
import 'package:workspace_calendar/workspace_calendar/schedule_section.dart';

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
/// "item-1", its times stepping by [slotMinutes], its Save checked by
/// [policy] at [now] on [today], Wednesday where they are null, and its day
/// pickers' weeks starting on [firstColumn], and opens it.
Future<void> openForm(
  WidgetTester tester,
  CalendarStore<ItemPayload> store, {
  int slotMinutes = CalendarDates.defaultSlotMinutes,
  CalendarEditPolicy<ItemPayload> policy =
      const UnrestrictedEditPolicy<ItemPayload>(),
  DateTime? now,
  DateTime? today,
  int firstColumn = 0,
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
                      today: today ?? wednesday,
                    );
                  },
                  hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
                  slotMinutes: slotMinutes,
                  firstColumn: firstColumn,
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

/// The open form's page: the scroll view between its heading and its
/// actions, around the scroll views of its text fields.
Finder pageFinder() {
  return find
      .descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      )
      .first;
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

  testWidgets("IF1 the form shows All day, a Start row and an End row, each "
      "with its day and time, and All day hides the times and saves "
      "day starts", (tester) async {
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
    for (final label in <String>["Start", "End", "All day"]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(timeFieldFinder("Start time"), findsOneWidget);
    expect(timeFieldFinder("End time"), findsOneWidget);
    expect(formDateShows("Start date", "2026-04-22"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);

    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(timeFieldFinder("Start time"), findsNothing);
    expect(timeFieldFinder("End time"), findsNothing);
    expect(formDateFinder("Start date"), findsOneWidget);
    expect(formDateFinder("End date"), findsOneWidget);

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
    expect(allDaySwitch(), findsOneWidget);
    expect(formAllDayOn(), isFalse);

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
    expect(allDaySwitch(), findsOneWidget);
    expect(formAllDayOn(), isFalse);

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
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(allDaySwitch(), findsOneWidget);
  });

  testWidgets("IF6 the form's day pickers start their weeks on the first "
      "column it is given: the Start row's picker's week row opens on "
      "Sunday", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store, firstColumn: 6);
    await openDayPicker(tester, "Start date");
    final weekRow = find.descendant(
      of: dayPickerFinder("Start date"),
      matching: find.byType(WeekStrip<ItemPayload>),
    );
    final row = tester.getRect(weekRow);
    Rect cellOf(DateTime day) {
      return tester.getRect(
        find.descendant(
          of: weekRow,
          matching: find.byKey(weekStripDayKey(day)),
        ),
      );
    }

    expect(
      cellOf(DateTime(2026, 4, 19)).left,
      moreOrLessEquals(row.left, epsilon: 0.5),
    );
    expect(
      cellOf(DateTime(2026, 4, 25)).right,
      moreOrLessEquals(row.right, epsilon: 0.5),
    );
  });

  testWidgets("FC1 the form's page is the scheduling part and the item's "
      "part, 12 pixels apart, between the heading and the actions, and the "
      "sheet holds no card", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    for (final (key, part) in <(Key, Finder)>[
      (formSchedulingCardKey, find.byType(ScheduleSection)),
      (formItemCardKey, fieldFinder("Title")),
    ]) {
      expect(find.byKey(key), findsOneWidget, reason: "$key");
      expect(
        find.descendant(of: find.byKey(key), matching: part),
        findsOneWidget,
        reason: "$key",
      );
    }
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
    // The item's fields span its part, which pads them by nothing.
    final itemPart = tester.getRect(find.byKey(formItemCardKey));
    final title = tester.getRect(fieldFinder("Title"));
    expect(title.left, itemPart.left);
    expect(title.right, itemPart.right);
    final scheduling = tester.getRect(find.byKey(formSchedulingCardKey));
    expect(itemPart.top, scheduling.bottom + 12.0);
    expect(
      tester.getRect(find.byType(ScheduleHeading)).bottom,
      lessThanOrEqualTo(scheduling.top),
    );
    final page = pageFinder();
    expect(
      tester.getRect(saveFinder()).top,
      greaterThanOrEqualTo(tester.getRect(page).bottom),
    );
  });

  testWidgets("FC2 the page's padding lies inside its scroll view: the page "
      "spans the sheet's width, its parts keep 24 pixels from the sheet's "
      "sides, and a drag that starts beside them scrolls it", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    // The sheet's Material, which a wide screen centres at its widest.
    final sheet = tester.getRect(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    final page = tester.getRect(pageFinder());
    expect(page.left, sheet.left);
    expect(page.right, sheet.right);
    final card = find.byKey(formSchedulingCardKey);
    final before = tester.getRect(card);
    expect(before.left, sheet.left + 24.0);
    expect(before.right, sheet.right - 24.0);
    // Setup sanity: the page holds more than its view shows.
    expect(
      tester.getRect(find.byKey(formItemCardKey)).bottom,
      greaterThan(page.bottom),
    );

    await tester.dragFrom(
      Offset(sheet.left + 8.0, page.center.dy),
      const Offset(0.0, -120.0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(card).top, lessThan(before.top));
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

  group("the passes of a repeated stretch", () {
    setUpAll(tz_data.initializeTimeZones);

    /// The instant [utc] on New York's clock, whose clock reads 01:00 to
    /// 02:00 twice on 2026-11-01, going back at 06:00Z.
    tz.TZDateTime inNewYork(DateTime utc) {
      return tz.TZDateTime.from(utc, tz.getLocation("America/New_York"));
    }

    /// [time]'s instant as a plain UTC time.
    DateTime utcOf(DateTime time) {
      return DateTime.fromMicrosecondsSinceEpoch(
        time.microsecondsSinceEpoch,
        isUtc: true,
      );
    }

    /// A store zoned New York holding the task "item-1" from [start] to
    /// [end], given in UTC, that adds each item it writes to [writes].
    MemoryCalendarStore<ItemPayload> storeInNewYork(
      DateTime start,
      DateTime end, {
      List<CalendarItem?>? writes,
    }) {
      return MemoryCalendarStore<ItemPayload>(
        entries: <CalendarItem>[task(inNewYork(start), inNewYork(end))],
        zone: tz.getLocation("America/New_York"),
        onChanged: (old, entry) {
          writes?.add(entry);
        },
      );
    }

    /// Opens the form of [store]'s item at 09:00 on 2026-10-30 in New York.
    Future<void> openBeforeTheChange(
      WidgetTester tester,
      CalendarStore<ItemPayload> store,
    ) {
      final newYork = tz.getLocation("America/New_York");
      return openForm(
        tester,
        store,
        slotMinutes: 15,
        now: tz.TZDateTime(newYork, 2026, 10, 30, 9),
        today: tz.TZDateTime(newYork, 2026, 10, 30),
      );
    }

    testWidgets("IF7 an item from 01:30 EST to 03:00 EST saved unchanged is "
        "written at the same instants", (tester) async {
      final writes = <CalendarItem?>[];
      final store = storeInNewYork(
        DateTime.utc(2026, 11, 1, 6, 30),
        DateTime.utc(2026, 11, 1, 8),
        writes: writes,
      );
      addTearDown(store.dispose);
      await openBeforeTheChange(tester, store);
      // Setup sanity: the form shows the item's wall times.
      expect(timeFieldShows("Start time", "01:30"), findsOneWidget);
      expect(timeFieldShows("End time", "03:00"), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(utcOf(writes.single!.start), DateTime.utc(2026, 11, 1, 6, 30));
      expect(utcOf(writes.single!.end), DateTime.utc(2026, 11, 1, 8));
    });

    testWidgets("IF8 the end picker of an item from 01:30 EDT to 01:15 EST "
        "offers the later-pass ends before the start's wall time", (
      tester,
    ) async {
      final store = storeInNewYork(
        DateTime.utc(2026, 11, 1, 5, 30),
        DateTime.utc(2026, 11, 1, 6, 15),
      );
      addTearDown(store.dispose);
      await openBeforeTheChange(tester, store);
      // Setup sanity: the end reads 01:15.
      expect(timeFieldShows("End time", "01:15"), findsOneWidget);
      await openTimePicker(tester, "End time");
      final ends = offeredTimes(tester, "End time");
      expect(ends, containsAll(<int>[60, 75]));
      expect(ends, isNot(contains(45)));

      await pickTime(tester, "End time", "01:00");
      // Setup sanity: the pick took.
      expect(timeFieldShows("End time", "01:00"), findsOneWidget);
      await openTimePicker(tester, "End time");
      expect(offeredTimes(tester, "End time"), containsAll(<int>[60, 75]));
    });

    testWidgets("IF9 the zone box names the offset at a later-pass start", (
      tester,
    ) async {
      final store = storeInNewYork(
        DateTime.utc(2026, 11, 1, 6, 30),
        DateTime.utc(2026, 11, 1, 8),
      );
      addTearDown(store.dispose);
      await openBeforeTheChange(tester, store);
      expect(
        find.descendant(
          of: find.byKey(scheduleZoneKey),
          matching: find.text(
            const DefaultCalendarLocalizations().utcOffset(-300),
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
