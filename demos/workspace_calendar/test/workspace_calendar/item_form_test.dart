/// The item form's page of cards and its times: its start and end dates
/// and times, the slot length they step by, and its All day switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
/// [policy] and its day pickers' weeks starting on [firstColumn], and opens
/// it.
Future<void> openForm(
  WidgetTester tester,
  CalendarStore<ItemPayload> store, {
  int slotMinutes = CalendarDates.defaultSlotMinutes,
  CalendarEditPolicy<ItemPayload> policy =
      const UnrestrictedEditPolicy<ItemPayload>(),
  DateTime? now,
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
                      today: wednesday,
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

/// The strip that holds the summary card: the nearest [ColoredBox] around
/// the card.
Finder summaryStripFinder() {
  return find
      .ancestor(
        of: find.byKey(formSummaryCardKey),
        matching: find.byType(ColoredBox),
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
    expect(formDateShows("Start date", "2026-04-22"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);

    await tester.tap(allDaySwitch());
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
      "column it is given: Start date's week row opens on Sunday", (
    tester,
  ) async {
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

  testWidgets("FC1 the form's page is the scheduling part, the summary's "
      "outlined card and the item's part, in that order between the heading "
      "and the actions, with no card around the scheduling and the item's "
      "parts", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    final keys = <Key>[
      formSchedulingCardKey,
      formSummaryCardKey,
      formItemCardKey,
    ];
    for (final key in keys) {
      expect(find.byKey(key), findsOneWidget, reason: "$key");
    }
    // The summary keeps its card, outlined.
    expect(tester.widget(find.byKey(formSummaryCardKey)), isA<Card>());
    final summaryShape = tester
        .widget<Material>(
          find
              .descendant(
                of: find.byKey(formSummaryCardKey),
                matching: find.byType(Material),
              )
              .first,
        )
        .shape;
    expect(
      summaryShape,
      isA<OutlinedBorder>().having(
        (shape) {
          return shape.side.style;
        },
        "side's style",
        BorderStyle.solid,
      ),
    );
    for (final part in <Finder>[
      find.byType(ScheduleSection),
      fieldFinder("Title"),
    ]) {
      expect(
        find.ancestor(of: part, matching: find.byType(Card)),
        findsNothing,
        reason: "$part",
      );
    }
    // The item's fields span its part, which pads them by nothing.
    final itemPart = tester.getRect(find.byKey(formItemCardKey));
    final title = tester.getRect(fieldFinder("Title"));
    expect(title.left, itemPart.left);
    expect(title.right, itemPart.right);
    final cards = <Rect>[
      for (final key in keys) tester.getRect(find.byKey(key)),
    ];
    for (var index = 1; index < cards.length; index++) {
      expect(cards[index - 1].top, lessThan(cards[index].top));
      expect(cards[index - 1].bottom, lessThanOrEqualTo(cards[index].top));
    }
    for (final (key, part) in <(Key, Finder)>[
      (formSchedulingCardKey, find.byType(ScheduleSection)),
      (formSummaryCardKey, find.byType(ScheduleSummary)),
      (formItemCardKey, fieldFinder("Title")),
    ]) {
      expect(
        find.descendant(of: find.byKey(key), matching: part),
        findsOneWidget,
        reason: "$key",
      );
    }
    expect(
      tester.getRect(find.text("Edit Task")).bottom,
      lessThanOrEqualTo(cards.first.top),
    );
    final page = pageFinder();
    expect(
      tester.getRect(saveFinder()).top,
      greaterThanOrEqualTo(tester.getRect(page).bottom),
    );
  });

  testWidgets("FC2 the page's padding lies inside its scroll view: the page "
      "spans the sheet's width, its cards keep 24 pixels from the sheet's "
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

  testWidgets("FP1 the summary card scrolls with the page until the "
      "scheduling card has gone, then stays at the page's top on a strip of "
      "the sheet's colour while the item card moves under it", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    final page = tester.getRect(pageFinder());
    final position = tester.state<ScrollableState>(pageFinder()).position;
    final summary = find.byKey(formSummaryCardKey);
    final scheduling = find.byKey(formSchedulingCardKey);
    // The page's offset at which the strip's top, 12 pixels above the card,
    // reaches the page's top.
    final pinsAt = tester.getRect(summary).top - 12.0 - page.top;
    // Setup sanity: the page scrolls well past that offset.
    expect(position.maxScrollExtent, greaterThan(pinsAt + 24.0));

    position.jumpTo(pinsAt / 2.0);
    await tester.pump();
    expect(
      tester.getRect(summary).top,
      tester.getRect(scheduling).bottom + 12.0,
    );

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final pinned = tester.getRect(summary);
    expect(pinned.top, page.top + 12.0);
    expect(
      tester.getRect(find.byKey(formItemCardKey)).top,
      lessThan(pinned.bottom),
    );
    expect(
      tester.getRect(summaryStripFinder()),
      Rect.fromLTRB(page.left, page.top, page.right, pinned.bottom + 12.0),
    );
    final sheet = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Material),
        )
        .first;
    expect(
      tester.widget<ColoredBox>(summaryStripFinder()).color,
      tester.widget<Material>(sheet).color,
    );
  });

  testWidgets("FP2 the summary card scrolls away with the page where its "
      "strip would take more than half of the page, as when a keyboard "
      "shrinks the page", (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400.0, 600.0);
    addTearDown(tester.view.reset);
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    final position = tester.state<ScrollableState>(pageFinder()).position;
    final summary = find.byKey(formSummaryCardKey);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    // Setup sanity: on the whole screen the strip fits, and the card pins.
    expect(
      tester.getRect(summary).top,
      tester.getRect(pageFinder()).top + 12.0,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 400.0);
    await tester.pumpAndSettle();
    final page = tester.getRect(pageFinder());
    // Setup sanity: the keyboard leaves the page less than twice the strip.
    expect(
      page.height,
      lessThan(2.0 * (tester.getRect(summary).height + 24.0)),
    );
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(tester.getRect(summary).bottom, lessThanOrEqualTo(page.top));
  });

  testWidgets("FP3 a field that the pinned summary card hides scrolls out "
      "below its strip when it takes focus", (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400.0, 560.0);
    addTearDown(tester.view.reset);
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 22, 10)),
      ],
    );
    addTearDown(store.dispose);
    await openForm(tester, store);
    final page = tester.getRect(pageFinder());
    final position = tester.state<ScrollableState>(pageFinder()).position;
    final summary = find.byKey(formSummaryCardKey);
    final input = find.descendant(
      of: fieldFinder("Title"),
      matching: find.byType(EditableText),
    );
    // Brings the title's input as near to 24 pixels below the page's top as
    // the page scrolls.
    position.jumpTo(
      (position.pixels + tester.getRect(input).top - page.top - 24.0).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    await tester.pump();
    final stripBottom = page.top + 12.0 + tester.getRect(summary).height + 12.0;
    // Setup sanity: the card is pinned, and its strip covers the input.
    expect(tester.getRect(summary).top, page.top + 12.0);
    expect(tester.getRect(input).top, lessThan(stripBottom));

    tester.state<EditableTextState>(input).requestKeyboard();
    await tester.pumpAndSettle();
    expect(tester.getRect(input).top, greaterThanOrEqualTo(stripBottom));
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
