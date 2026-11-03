/// The range a create gesture picks: the times it takes, in
/// [CalendarEntry]'s order, the kind it stores, its equality and text, and
/// the members its class declares.
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';

import '../class_source.dart';

/// [minute] minutes after [day]'s midnight.
DateTime at(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, 0, minute);
}

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

void main() {
  test("RC11 a create range throws CalendarEntry's ArgumentError for the "
      "first rule its times break, in CalendarEntry's order, its message "
      "naming a range", () {
    final wednesday = DateTime(2026, 4, 22);
    final start = at(tuesday, 600);
    final end = at(tuesday, 660);
    const second = Duration(seconds: 1);
    const millisecond = Duration(milliseconds: 1);
    const microsecond = Duration(microseconds: 1);
    final cases =
        <({DateTime start, DateTime end, bool isAllDay, String? breaks})>[
          (start: start.toUtc(), end: end, isAllDay: false, breaks: "start"),
          (start: start, end: end.toUtc(), isAllDay: false, breaks: "end"),
          (
            start: start.add(second),
            end: end,
            isAllDay: false,
            breaks: "start",
          ),
          (start: start, end: end.add(second), isAllDay: false, breaks: "end"),
          (
            start: start.add(millisecond),
            end: end,
            isAllDay: false,
            breaks: "start",
          ),
          (
            start: start,
            end: end.add(millisecond),
            isAllDay: false,
            breaks: "end",
          ),
          (
            start: start.add(microsecond),
            end: end,
            isAllDay: false,
            breaks: "start",
          ),
          (
            start: start,
            end: end.add(microsecond),
            isAllDay: false,
            breaks: "end",
          ),
          (start: start, end: start, isAllDay: false, breaks: "end"),
          (start: end, end: start, isAllDay: false, breaks: "end"),
          (
            start: at(tuesday, 60),
            end: wednesday,
            isAllDay: true,
            breaks: "start",
          ),
          (
            start: tuesday,
            end: at(wednesday, 60),
            isAllDay: true,
            breaks: "end",
          ),
          // Two rules broken, of different names: the earlier rule names it.
          (
            start: start.add(second),
            end: end.toUtc(),
            isAllDay: false,
            breaks: "end",
          ),
          (
            start: start.toUtc(),
            end: end.add(second),
            isAllDay: false,
            breaks: "start",
          ),
          (
            start: at(wednesday, 60),
            end: tuesday,
            isAllDay: true,
            breaks: "end",
          ),
          (start: start, end: end, isAllDay: false, breaks: null),
          (start: tuesday, end: wednesday, isAllDay: true, breaks: null),
        ];
    ArgumentError? errorOf(void Function() make) {
      try {
        make();
        return null;
      } on ArgumentError catch (error) {
        return error;
      }
    }

    for (final times in cases) {
      final reason = "$times";
      final rangeError = errorOf(() {
        CalendarCreateRange(
          start: times.start,
          end: times.end,
          isAllDay: times.isAllDay,
        );
      });
      final entryError = errorOf(() {
        CalendarEntry<String>(
          start: times.start,
          end: times.end,
          isAllDay: times.isAllDay,
          title: "range",
          color: const Color(0xFF336699),
          payload: "range",
        );
      });
      // The case breaks the rule it names for an entry.
      expect(entryError?.name, times.breaks, reason: reason);
      expect(rangeError?.name, times.breaks, reason: reason);
      expect(
        rangeError?.invalidValue,
        entryError?.invalidValue,
        reason: reason,
      );
      expect(
        rangeError?.message,
        (entryError?.message as String?)
            ?.replaceFirst("An entry", "A range")
            .replaceFirst("all-day entry", "all-day range"),
        reason: reason,
      );
    }
  });

  test("TR11 a create range stores its kind: false by default, compared by "
      "equality and named by toString", () {
    final timed = CalendarCreateRange(start: monday, end: tuesday);
    final allDay = CalendarCreateRange(
      start: monday,
      end: tuesday,
      isAllDay: true,
    );
    expect(timed.isAllDay, isFalse);
    expect(allDay.isAllDay, isTrue);
    expect(timed, isNot(allDay));
    expect(timed, CalendarCreateRange(start: monday, end: tuesday));
    expect(allDay.toString(), contains(", all day"));
    expect(timed.toString(), isNot(contains("all day")));
  });

  test("TR5 the CalendarCreateRange class declares no member of the day, "
      "minute and day-count time", () {
    final body = classBody(
      File("lib/scheduling/entries/calendar_entry.dart").readAsStringSync(),
      "CalendarCreateRange",
    );
    bool declares(String name) {
      return RegExp(
        "(final|get)\\s+(int|DateTime)?\\s*$name\\b",
      ).hasMatch(body);
    }

    expect(declares("start") || declares("day"), isTrue);
    for (final name in const <String>[
      "day",
      "startMinute",
      "endMinute",
      "dayCount",
    ]) {
      expect(declares(name), isFalse, reason: name);
    }
  });
}
