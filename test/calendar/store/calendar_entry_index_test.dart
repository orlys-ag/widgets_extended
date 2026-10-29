/// The entry index under both stores: filing a batch of entries under the
/// days it holds open.
library;

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';

/// An entry on the 21 April 2026 plus [dayOffset] days, from [start] to
/// [end] minutes after its midnight.
CalendarEntry<String> task(
  String id,
  int start,
  int end, {
  int dayOffset = 0,
  String title = "Task",
}) {
  return CalendarEntry<String>(
    id: id,
    start: DateTime(2026, 4, 21 + dayOffset, 0, start),
    end: DateTime(2026, 4, 21 + dayOffset, 0, end),
    title: title,
    color: const Color(0xFF3060C0),
    payload: "task",
  );
}

/// The [dayNumber] of the 21 April 2026 plus [offset] days.
int day(int offset) {
  return dayNumber(DateTime(2026, 4, 21 + offset));
}

/// The ids filed under [dayOffset]'s day, in order.
List<String> idsOn(CalendarEntryIndex<String> index, int dayOffset) {
  return <String>[
    for (final entry in index.storedOn(day(dayOffset))) entry.id!,
  ];
}

void main() {
  test("IX1 putAll files entries given in any order under each open day, "
      "in order among those it holds, and files none under a closed "
      "day", () {
    final index = CalendarEntryIndex<String>(opensEveryDay: false);
    index.open(<int>[day(0)]);
    index.put(task("a", 600, 660));
    index.put(task("c", 840, 900));

    index.putAll(<CalendarEntry<String>>[
      task("e", 960, 1020),
      task("b", 720, 780),
      task("d", 900, 960),
      task("z", 540, 600),
      task("x", 600, 660, dayOffset: 1),
    ]);
    expect(idsOn(index, 0), <String>["z", "a", "b", "c", "d", "e"]);
    expect(idsOn(index, 1), isEmpty);
    expect(index.stored("x"), task("x", 600, 660, dayOffset: 1));
  });

  test("IX2 putAll unfiles the entries it replaces, and stores the last of "
      "those sharing an id", () {
    final index = CalendarEntryIndex<String>(opensEveryDay: false);
    index.open(<int>[day(0), day(1)]);
    index.put(task("x", 600, 660));

    final later = task("y", 720, 780, title: "Later");
    index.putAll(<CalendarEntry<String>>[
      task("x", 600, 660, dayOffset: 1),
      task("y", 540, 600),
      later,
    ]);
    expect(idsOn(index, 0), <String>["y"]);
    expect(index.storedOn(day(0)).single, later);
    expect(idsOn(index, 1), <String>["x"]);
  });

  test("IX3 put and putAll show the entry of a pending id that shows "
      "none", () {
    for (final batch in <bool>[false, true]) {
      final index = CalendarEntryIndex<String>(opensEveryDay: false);
      index.open(<int>[day(0)]);
      index.lock("p", null);
      final entry = task("p", 600, 660);

      if (batch) {
        index.putAll(<CalendarEntry<String>>[entry]);
      } else {
        index.put(entry);
      }
      expect(index.entriesOn(day(0)), <CalendarShownEntry<String>>[
        CalendarShownEntry<String>(entry, pending: true),
      ], reason: batch ? "putAll" : "put");
    }
  });

  test("IX4 with opensEveryDay, putAll opens the days its entries cover "
      "and closes a day its replacements empty", () {
    final index = CalendarEntryIndex<String>(opensEveryDay: true);
    index.put(task("a", 600, 660));

    index.putAll(<CalendarEntry<String>>[
      task("a", 600, 660, dayOffset: 2),
      task("c", 720, 780, dayOffset: 1),
      task("b", 540, 600, dayOffset: 1),
    ]);
    expect(index.isOpen(day(0)), isFalse);
    expect(idsOn(index, 1), <String>["b", "c"]);
    expect(idsOn(index, 2), <String>["a"]);
  });

  test("IX5 a pending id locked with no entry shows the stored entry as "
      "put and forget change it; one locked with an entry keeps it", () {
    final index = CalendarEntryIndex<String>(opensEveryDay: false);
    index.open(<int>[day(0), day(1)]);
    index.put(task("a", 600, 660));
    index.lock("a", null);

    final moved = task("a", 600, 660, dayOffset: 1);
    index.put(moved);
    expect(index.entriesOn(day(1)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(moved, pending: true),
    ]);
    index.forget("a");
    expect(index.entriesOn(day(1)), isEmpty);

    index.release("a");
    final requested = task("a", 720, 780);
    index.lock("a", requested);
    index.put(moved);
    expect(index.entriesOn(day(0)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(requested, pending: true),
    ]);

    index.lock("b", null);
    index.clear();
    index.open(<int>[day(0)]);
    final kept = task("b", 720, 780);
    index.lock("b", kept);
    index.put(task("b", 600, 660));
    expect(index.entriesOn(day(0)), <CalendarShownEntry<String>>[
      CalendarShownEntry<String>(kept, pending: true),
    ]);
  });
}
