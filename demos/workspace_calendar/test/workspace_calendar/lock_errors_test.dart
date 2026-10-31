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

/// A policy that holds every item as one in progress, its start fixed and
/// its end resizable, and admits only a change to a timed item.
final class _HeldTimedOnly extends CalendarEditPolicy<String> {
  const _HeldTimedOnly();

  @override
  bool mayMove(CalendarEntry<String> entry, CalendarNow now) {
    return false;
  }

  @override
  CalendarResizeEdges resizableEdges(
    CalendarEntry<String> entry,
    CalendarNow now,
  ) {
    return CalendarResizeEdges.end;
  }

  @override
  bool admitsChange(
    CalendarEntry<String> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
    return !isAllDay;
  }
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
      lockErrorsOf(
        lock,
        now,
        null,
        shape(monday, 9 * 60, 10 * 60),
        isAllDay: false,
      ),
      <String, String>{"start": "Past days are locked."},
    );
    expect(
      lockErrorsOf(
        lock,
        now,
        null,
        shape(tuesday, 9 * 60, 10 * 60),
        isAllDay: false,
      ),
      <String, String>{"start": "The start can't be in the past."},
    );
    expect(
      lockErrorsOf(
        lock,
        now,
        stored(shape(tuesday, 8 * 60, 9 * 60)),
        shape(tuesday, 8 * 60, 9 * 60 + 15),
        isAllDay: false,
      ),
      <String, String>{"start": "Past items are locked."},
    );
    expect(
      lockErrorsOf(
        lock,
        now,
        running,
        shape(tuesday, 10 * 60 + 15, 11 * 60),
        isAllDay: false,
      ),
      <String, String>{
        "start": "An item in progress keeps its start.",
        "end": "The end can't be in the past.",
      },
    );
    expect(
      lockErrorsOf(
        lock,
        now,
        running,
        shape(tuesday, 10 * 60, 13 * 60),
        isAllDay: false,
      ),
      isEmpty,
    );
    expect(
      lockErrorsOf(
        const UnrestrictedEditPolicy<String>(),
        now,
        null,
        shape(monday, 9 * 60, 10 * 60),
        isAllDay: false,
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
        isAllDay: false,
      ),
      <String, String>{"start": "Past days are locked."},
    );
  });

  test("LE3 of an item in progress, a change of kind is keyed start with its "
      "own message, and the end is asked with the stored kind", () {
    const policy = _HeldTimedOnly();
    final now = CalendarNow(time: DateTime(2026, 4, 21, 11, 7), today: tuesday);
    final from = stored(shape(tuesday, 0, 24 * 60));
    expect(
      lockErrorsOf(
        policy,
        now,
        from,
        shape(tuesday, 0, 24 * 60),
        isAllDay: false,
      ),
      isEmpty,
    );
    const keepsKind = <String, String>{
      "start": "An item in progress keeps its All day setting.",
    };
    expect(
      lockErrorsOf(
        policy,
        now,
        from,
        shape(tuesday, 0, 24 * 60),
        isAllDay: true,
      ),
      keepsKind,
    );
    expect(
      lockErrorsOf(
        policy,
        now,
        from,
        shape(tuesday, 0, 48 * 60),
        isAllDay: true,
      ),
      keepsKind,
    );
  });
}
