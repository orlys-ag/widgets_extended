/// The item form's errors for a change the edit policy refuses.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

/// From [start] to [end] minutes after [day]'s midnight.
({DateTime start, DateTime end}) shape(DateTime day, int start, int end) {
  return (
    start: DateTime(day.year, day.month, day.day, 0, start),
    end: DateTime(day.year, day.month, day.day, 0, end),
  );
}

/// A stored entry of [shape]'s times, a change's from.
CalendarEntry<String> stored(({DateTime start, DateTime end}) shape) {
  return CalendarEntry<String>(
    id: "stored",
    start: shape.start,
    end: shape.end,
    title: "Stored",
    color: const Color(0xFF336699),
    payload: "stored",
  );
}

void main() {
  test("LE1 lockErrorsOf answers each refusal with the form's message, "
      "keyed start and end as the form's fields and the envelope are, and "
      "nothing the lock admits", () {
    // 11:07 on Tuesday: after 08:00 to 09:00 ends, while 10:00 to 12:00
    // runs.
    const lock = HistoryLockPolicy<String>(lockEarlierToday: true);
    final now = CalendarNow(time: DateTime(2026, 4, 21, 11, 7), today: tuesday);
    final running = stored(shape(tuesday, 10 * 60, 12 * 60));
    expect(
      lockErrorsOf(lock, now, null, shape(monday, 9 * 60, 10 * 60)),
      <String, String>{"start": "Past days are locked."},
    );
    expect(
      lockErrorsOf(lock, now, null, shape(tuesday, 9 * 60, 10 * 60)),
      <String, String>{"start": "The start can't be in the past."},
    );
    expect(
      lockErrorsOf(
        lock,
        now,
        stored(shape(tuesday, 8 * 60, 9 * 60)),
        shape(tuesday, 8 * 60, 9 * 60 + 15),
      ),
      <String, String>{"start": "Past items are locked."},
    );
    expect(
      lockErrorsOf(lock, now, running, shape(tuesday, 10 * 60 + 15, 11 * 60)),
      <String, String>{
        "start": "An item in progress keeps its start.",
        "end": "The end can't be in the past.",
      },
    );
    expect(
      lockErrorsOf(lock, now, running, shape(tuesday, 10 * 60, 13 * 60)),
      isEmpty,
    );
    expect(
      lockErrorsOf(
        const UnrestrictedEditPolicy<String>(),
        now,
        null,
        shape(monday, 9 * 60, 10 * 60),
      ),
      isEmpty,
    );
  });

  test("LE2 under the lock of earlier today at Tuesday 23:59:30, whose "
      "boundary is Wednesday's start, a new item at Tuesday 22:00 is on a "
      "locked day", () {
    const lock = HistoryLockPolicy<ItemPayload>(lockEarlierToday: true);
    final now = CalendarNow(
      time: DateTime(2026, 4, 21, 23, 59, 30),
      today: tuesday,
    );
    expect(
      lockErrorsOf<ItemPayload>(
        lock,
        now,
        null,
        shape(tuesday, 22 * 60, 23 * 60),
      ),
      <String, String>{"start": "Past days are locked."},
    );
  });
}
