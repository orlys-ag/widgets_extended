/// The day list: the rows it lays out for a day's entries, its gaps and
/// its banners outside the hours, and a card drawn again for a new
/// payload.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';

typedef ShownItem = CalendarShownEntry<String>;

/// 09:00 on April 21 2026.
DateTime nineOClock() {
  return DateTime(2026, 4, 21, 9);
}

/// An entry with the id and title [id] on April 22 from [start] to [end]
/// minutes after midnight, as the calendar shows it.
ShownItem entryAt(String id, int start, int end) {
  return ShownItem(
    CalendarEntry<String>(
      id: id,
      start: DateTime(2026, 4, 22, 0, start),
      end: DateTime(2026, 4, 22, 0, end),
      title: id,
      color: const Color(0xFF336699),
      payload: id,
    ),
    pending: false,
  );
}

/// [dayListRowsOf] of [entries] on April 22 in [hours], in edit mode
/// unless not [editable], each item as its id, each gap as its start and
/// end, and each banner as "before" or "after" and its count.
List<Object> rowsOf(
  List<ShownItem> entries, {
  DayHours hours = DayHours.allDay,
  bool editable = true,
}) {
  return <Object>[
    for (final row in dayListRowsOf(
      DateTime(2026, 4, 22),
      entries,
      hours,
      editable: editable,
    ))
      switch (row) {
        DayListEntry(:final entry) => entry.id,
        DayListGap(:final start, :final end) => (start, end),
        DayListHidden(:final count, :final above) => (
          above ? "before" : "after",
          count,
        ),
        _ => throw StateError("$row is not an item, a gap or a banner."),
      },
  ];
}

void main() {
  test("L6 the rows put one gap row for each run of the calendar's hours "
      "that no item covers, before the item that ends it or last", () {
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 8 * 60, 9 * 60),
        entryAt("b", 10 * 60, 11 * 60),
        entryAt("c", 13 * 60, 14 * 60),
      ]),
      <Object>[
        (0, 8 * 60),
        "a",
        (9 * 60, 10 * 60),
        "b",
        (11 * 60, 13 * 60),
        "c",
        (14 * 60, 24 * 60),
      ],
    );
    // Minutes an item covers have no row, though a later item ends first.
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 8 * 60, 11 * 60),
        entryAt("b", 9 * 60, 10 * 60),
        entryAt("c", 12 * 60, 13 * 60),
      ]),
      <Object>[
        (0, 8 * 60),
        "a",
        "b",
        (11 * 60, 12 * 60),
        "c",
        (13 * 60, 24 * 60),
      ],
    );
    // A gap starts where an item ends, between whole hours too, and items
    // that touch or start together have none between them.
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 8 * 60, 9 * 60 + 15),
        entryAt("b", 11 * 60, 12 * 60),
        entryAt("c", 11 * 60, 11 * 60 + 30),
        entryAt("d", 12 * 60, 13 * 60),
      ]),
      <Object>[
        (0, 8 * 60),
        "a",
        (9 * 60 + 15, 11 * 60),
        "b",
        "c",
        "d",
        (13 * 60, 24 * 60),
      ],
    );
    // Only the calendar's hours have gaps, so an item reaching past them
    // makes none past them, and one wholly outside them none at all.
    const office = DayHours(8 * 60, 18 * 60);
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 7 * 60, 9 * 60),
        entryAt("b", 17 * 60, 19 * 60),
      ], hours: office),
      <Object>["a", (9 * 60, 17 * 60), "b"],
    );
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 6 * 60, 7 * 60),
        entryAt("b", 19 * 60, 20 * 60),
      ], hours: office),
      <Object>[("before", 1), (8 * 60, 18 * 60), ("after", 1)],
    );
  });

  test("L18 an item wholly outside the hours has no row: a banner first "
      "counts those before them and one last those after them, in edit "
      "mode and out of it, and in edit mode a day with no item inside the "
      "hours has one gap row across them", () {
    const office = DayHours(8 * 60, 18 * 60);
    final entries = <ShownItem>[
      entryAt("a", 6 * 60, 7 * 60),
      entryAt("b", 7 * 60, 8 * 60),
      entryAt("c", 7 * 60, 9 * 60),
      entryAt("e", 12 * 60, 13 * 60),
      entryAt("d", 18 * 60, 19 * 60),
    ];
    expect(rowsOf(entries, hours: office, editable: false), <Object>[
      ("before", 2),
      "c",
      "e",
      ("after", 1),
    ]);
    expect(rowsOf(entries, hours: office), <Object>[
      ("before", 2),
      "c",
      (9 * 60, 12 * 60),
      "e",
      (13 * 60, 18 * 60),
      ("after", 1),
    ]);
    expect(rowsOf(const <ShownItem>[], hours: office), <Object>[
      (8 * 60, 18 * 60),
    ]);
    expect(rowsOf(const <ShownItem>[], editable: false), isEmpty);
  });

  testWidgets("BA10 a write that changes only an entry's payload runs its "
      "card builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      start: DateTime(2026, 4, 21, 10),
      end: DateTime(2026, 4, 21, 11),
      title: "Note",
      color: const Color(0xFF336699),
      payload: "first",
    );
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[note],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DayList<String>(
          store: store,
          weekdays: WeekdaySet.all,
          format: HourLabelFormat.twentyFourHour,
          hours: DayHours.allDay,
          editable: false,
          selectedDay: day,
          today: day,
          now: now,
          onTopDay: (day) {},
          onCreateRange: (range) {},
          onEdit: (id) {},
          onDelete: (id) {},
          cardBuilder: (context, entry, details) {
            calls.add(entry);
            return Text(entry.entry.payload);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(entryCardKey("note-1"));
    expect(
      find.descendant(of: card, matching: find.text("first")),
      findsOneWidget,
    );
    final before = calls.length;

    await store.update(note.copyWith(payload: "second"));
    await tester.pumpAndSettle();
    expect(calls.length, greaterThan(before));
    expect(calls.last.pending, isFalse);
    expect(calls.last.entry.payload, "second");
    expect(
      find.descendant(of: card, matching: find.text("second")),
      findsOneWidget,
    );
  });
}
