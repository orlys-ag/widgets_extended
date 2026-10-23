/// CalendarEntry's fields, value semantics, copy, asserts and all-day
/// rule, the members it does not declare, and the data-source contract's
/// signatures.
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';

import '../dst_days.dart';

/// A payload compared by its text, never by identity.
@immutable
class Note {
  const Note(this.text);

  final String text;

  @override
  bool operator ==(Object other) {
    return other is Note && other.text == text;
  }

  @override
  int get hashCode {
    return text.hashCode;
  }
}

const Color blue = Color(0xFF2050A0);
const Color red = Color(0xFFA02020);

/// An entry whose fields default to one set of values, its payload built
/// anew on each call: Tuesday April 21 2026, 10:00 to 11:00.
CalendarEntry<Note> entry({
  String? id = "entry-1",
  DateTime? start,
  DateTime? end,
  String title = "Review",
  Color color = blue,
  String note = "agenda",
}) {
  return CalendarEntry<Note>(
    id: id,
    start: start ?? DateTime(2026, 4, 21, 10),
    end: end ?? DateTime(2026, 4, 21, 11),
    title: title,
    color: color,
    payload: Note(note),
  );
}

/// The body of the class [name] declares in [source], comments dropped, to
/// its matching brace.
String classBody(String source, String name) {
  final code = source
      .replaceAll(RegExp(r"/\*[\s\S]*?\*/"), "")
      .replaceAll(RegExp(r"//[^\n]*"), "");
  final start = code.indexOf(RegExp("class $name\\b"));
  expect(start, isNot(-1), reason: name);
  final open = code.indexOf("{", start);
  var depth = 1;
  var at = open + 1;
  while (depth > 0) {
    final char = code[at];
    if (char == "{") {
      depth++;
    } else if (char == "}") {
      depth--;
    }
    at++;
  }
  return code.substring(open + 1, at - 1);
}

/// Whether [body] declares a member named [name]: a field, a getter or a
/// method.
bool declares(String body, String name) {
  return RegExp(
    "(final|get|bool|int|String|DateTime|Iterable<int>|CalendarEntryTime)"
    "\\s+$name\\b",
  ).hasMatch(body);
}

/// A data source implementing the contract's members with the contract's
/// own signatures, so a change to a signature that an implementing class
/// cannot follow stops this file compiling.
class StringSource implements CalendarDataSource<String> {
  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}

void main() {
  test("ET1 an entry holds the six fields it is given", () {
    final start = DateTime(2026, 4, 21, 9, 10);
    final end = DateTime(2026, 4, 22, 1, 50);
    final made = entry(start: start, end: end);
    expect(made.id, "entry-1");
    expect(made.start, start);
    expect(made.end, end);
    expect(made.title, "Review");
    expect(made.color, blue);
    expect(made.payload, const Note("agenda"));
  });

  test("ET2 two entries are equal when every field is, the payload by its "
      "own ==", () {
    final a = entry();
    final b = entry();
    expect(identical(a.payload, b.payload), isFalse);
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    final others = <String, CalendarEntry<Note>>{
      "id": entry(id: "entry-2"),
      "start": entry(start: DateTime(2026, 4, 21, 10, 5)),
      "end": entry(end: DateTime(2026, 4, 22, 11)),
      "title": entry(title: "Retro"),
      "color": entry(color: red),
      "payload": entry(note: "minutes"),
    };
    for (final MapEntry(key: field, value: other) in others.entries) {
      expect(a == other, isFalse, reason: field);
      expect(a.hashCode == other.hashCode, isFalse, reason: field);
    }
  });

  test("ET3 copyWith replaces each field given and keeps the others", () {
    final original = entry();
    final copy = original.copyWith(
      id: "entry-2",
      start: DateTime(2026, 4, 23, 9),
      end: DateTime(2026, 4, 24, 9, 30),
      title: "Retro",
      color: red,
    );
    expect(copy.id, "entry-2");
    expect(copy.start, DateTime(2026, 4, 23, 9));
    expect(copy.end, DateTime(2026, 4, 24, 9, 30));
    expect(copy.title, "Retro");
    expect(copy.color, red);
    expect(identical(copy.payload, original.payload), isTrue);

    final kept = original.copyWith();
    expect(kept, original);
    expect(identical(kept.payload, original.payload), isTrue);
    const payload = Note("minutes");
    expect(
      identical(original.copyWith(payload: payload).payload, payload),
      isTrue,
    );
  });

  group("the constructor asserts", () {
    final start = DateTime(2026, 4, 21, 10);
    final end = DateTime(2026, 4, 21, 11);

    test("none for a whole-minute local range", () {
      expect(() => entry(start: start, end: end), returnsNormally);
    });

    test("ET4 a UTC start", () {
      expect(
        () => entry(start: DateTime.utc(2026, 4, 21, 10)),
        throwsAssertionError,
      );
    });

    test("ET5 a UTC end", () {
      expect(
        () => entry(end: DateTime.utc(2026, 4, 21, 23)),
        throwsAssertionError,
      );
    });

    test("ET6 a second on the start", () {
      expect(
        () => entry(start: start.add(const Duration(seconds: 1))),
        throwsAssertionError,
      );
    });

    test("ET7 a second on the end", () {
      expect(
        () => entry(end: end.add(const Duration(seconds: 1))),
        throwsAssertionError,
      );
    });

    test("ET8 a millisecond on the start", () {
      expect(
        () => entry(start: start.add(const Duration(milliseconds: 1))),
        throwsAssertionError,
      );
    });

    test("ET9 a millisecond on the end", () {
      expect(
        () => entry(end: end.add(const Duration(milliseconds: 1))),
        throwsAssertionError,
      );
    });

    test("ET10 a microsecond on the start", () {
      expect(
        () => entry(start: start.add(const Duration(microseconds: 1))),
        throwsAssertionError,
      );
    });

    test("ET11 a microsecond on the end", () {
      expect(
        () => entry(end: end.add(const Duration(microseconds: 1))),
        throwsAssertionError,
      );
    });

    test("ET12 an end equal to the start", () {
      expect(() => entry(start: start, end: start), throwsAssertionError);
    });

    test("ET13 an end before the start", () {
      expect(() => entry(start: end, end: start), throwsAssertionError);
    });
  });

  test("ET14 isAllDay holds from a day start to a day start only", () {
    final day = DateTime(2026, 4, 21);
    expect(entry(start: day, end: DateTime(2026, 4, 22)).isAllDay, isTrue);
    expect(entry(start: day, end: DateTime(2026, 4, 24)).isAllDay, isTrue);
    expect(
      entry(
        start: DateTime(2026, 4, 21, 9),
        end: DateTime(2026, 4, 22, 9),
      ).isAllDay,
      isFalse,
    );
    expect(
      entry(start: day, end: DateTime(2026, 4, 21, 0, 30)).isAllDay,
      isFalse,
    );
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    test("ET15 its start to the next day's start is all-day", () {
      final day = shortDayStart;
      expect(addDays(day, 1).difference(day), const Duration(hours: 23));
      expect(entry(start: day, end: addDays(day, 1)).isAllDay, isTrue);
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    test("ET15 its start to the next day's start is all-day", () {
      final day = longDayStart;
      expect(addDays(day, 1).difference(day), const Duration(hours: 25));
      expect(entry(start: day, end: addDays(day, 1)).isAllDay, isTrue);
    });
  });

  test("ET16 the CalendarEntry class declares no member of the day, minute "
      "and day-count time", () {
    final body = classBody(
      File("lib/calendar/entries/calendar_entry.dart").readAsStringSync(),
      "CalendarEntry",
    );
    // The search finds a member the class does declare.
    expect(declares(body, "title"), isTrue);
    for (final name in const <String>[
      "day",
      "startMinute",
      "endMinute",
      "dayCount",
      "time",
      "coversDay",
      "dayNumbers",
    ]) {
      expect(declares(body, name), isFalse, reason: name);
    }
  });

  test("DS1 the data-source contract's signatures", () {
    // Compile-time only: each tear-off, read through the contract, must be
    // assignable to the contract's exact function type, so a contract that
    // narrows a parameter type or widens a return type stops this file
    // compiling, and StringSource catches the other changes.
    final CalendarDataSource<String> source = StringSource();
    final Future<List<CalendarEntry<String>>> Function(
      DateTime first,
      DateTime last,
    )
    read = source.read;
    final Future<CalendarEntry<String>> Function(CalendarEntry<String> draft)
    create = source.create;
    final Future<CalendarEntry<String>> Function(CalendarEntry<String> entry)
    replace = source.replace;
    final Future<void> Function(String id) delete = source.delete;
    <Object>[read, create, replace, delete];
  });
}
