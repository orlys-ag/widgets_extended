/// The overlap rule over entry times: days that meet and half-open minute
/// ranges that meet.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/overlap.dart';

CalendarEntryTime timeOf(int firstDay, int start, int end, {int days = 1}) {
  return (firstDay: firstDay, dayCount: days, start: start, end: end);
}

void main() {
  test("O1 times overlap only on days they share", () {
    expect(timesOverlap(timeOf(10, 600, 660), timeOf(11, 600, 660)), isFalse);
    final multi = timeOf(10, 600, 660, days: 3);
    expect(timesOverlap(multi, timeOf(12, 630, 690)), isTrue);
    expect(timesOverlap(timeOf(12, 630, 690), multi), isTrue);
    expect(timesOverlap(multi, timeOf(13, 630, 690)), isFalse);
    expect(timesOverlap(timeOf(13, 630, 690), multi), isFalse);
  });

  test("O2 minute ranges are half-open", () {
    void expectEither(CalendarEntryTime a, CalendarEntryTime b, bool meet) {
      expect(timesOverlap(a, b), meet, reason: "$a and $b");
      expect(timesOverlap(b, a), meet, reason: "$b and $a");
    }

    expectEither(timeOf(10, 600, 660), timeOf(10, 660, 720), false);
    expectEither(timeOf(10, 600, 661), timeOf(10, 660, 720), true);
    expectEither(timeOf(10, 600, 660), timeOf(10, 600, 660), true);
    expectEither(timeOf(10, 600, 720), timeOf(10, 630, 690), true);
  });

  test("O3 multi-day times whose days meet overlap only where their "
      "minutes meet", () {
    final morning = timeOf(10, 540, 600, days: 3);
    expect(timesOverlap(morning, timeOf(12, 600, 660, days: 2)), isFalse);
    expect(timesOverlap(morning, timeOf(12, 570, 660, days: 2)), isTrue);
    expect(timesOverlap(timeOf(12, 570, 660, days: 2), morning), isTrue);
    expect(timesOverlap(morning, timeOf(8, 480, 540, days: 5)), isFalse);
    expect(timesOverlap(morning, timeOf(8, 480, 545, days: 5)), isTrue);
  });
}
