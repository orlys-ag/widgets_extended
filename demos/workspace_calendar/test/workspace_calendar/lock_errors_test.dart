/// The item form's errors for a change the history lock refuses.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/policy/history_lock.dart';
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

void main() {
  test("LE1 lockErrorsOf answers each refusal with the form's message, "
      "keyed start and end as the form's fields and the envelope are, and "
      "nothing the lock admits", () {
    // 11:07 on Tuesday: after 08:00 to 09:00 ends, while 10:00 to 12:00
    // runs.
    final lock = HistoryLock.of(
      lockPast: true,
      lockEarlierToday: true,
      today: tuesday,
      now: DateTime(2026, 4, 21, 11, 7),
    );
    final running = shape(tuesday, 10 * 60, 12 * 60);
    expect(
      lockErrorsOf(lock, null, shape(monday, 9 * 60, 10 * 60)),
      <String, String>{"start": "Past days are locked."},
    );
    expect(
      lockErrorsOf(lock, null, shape(tuesday, 9 * 60, 10 * 60)),
      <String, String>{"start": "The start can't be in the past."},
    );
    expect(
      lockErrorsOf(
        lock,
        shape(tuesday, 8 * 60, 9 * 60),
        shape(tuesday, 8 * 60, 9 * 60 + 15),
      ),
      <String, String>{"start": "Past items are locked."},
    );
    expect(
      lockErrorsOf(lock, running, shape(tuesday, 10 * 60 + 15, 11 * 60)),
      <String, String>{
        "start": "An item in progress keeps its start.",
        "end": "The end can't be in the past.",
      },
    );
    expect(
      lockErrorsOf(lock, running, shape(tuesday, 10 * 60, 13 * 60)),
      isEmpty,
    );
    expect(
      lockErrorsOf(HistoryLock.none, null, shape(monday, 9 * 60, 10 * 60)),
      isEmpty,
    );
  });
}
