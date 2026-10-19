/// CalendarEntry's value semantics, time, copy and asserts, and the
/// data-source contract's signatures.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';

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
/// anew on each call.
CalendarEntry<Note> entry({
  String? id = "entry-1",
  DateTime? day,
  int startMinute = 600,
  int endMinute = 660,
  int dayCount = 1,
  String title = "Review",
  Color color = blue,
  String note = "agenda",
}) {
  return CalendarEntry<Note>(
    id: id,
    day: day ?? DateTime(2026, 4, 21),
    startMinute: startMinute,
    endMinute: endMinute,
    dayCount: dayCount,
    title: title,
    color: color,
    payload: Note(note),
  );
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
  test("E1 two entries are equal when every field is, the payload by its "
      "own ==", () {
    final a = entry();
    final b = entry();
    expect(identical(a.payload, b.payload), isFalse);
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    final others = <String, CalendarEntry<Note>>{
      "id": entry(id: "entry-2"),
      "day": entry(day: DateTime(2026, 4, 22)),
      "startMinute": entry(startMinute: 615),
      "endMinute": entry(endMinute: 675),
      "dayCount": entry(dayCount: 2),
      "title": entry(title: "Retro"),
      "color": entry(color: red),
      "payload": entry(note: "minutes"),
    };
    for (final MapEntry(key: field, value: other) in others.entries) {
      expect(a == other, isFalse, reason: field);
    }
  });

  test("E2 the day drops its time, and the time covers the entry's days", () {
    final multi = entry(
      day: DateTime(2026, 4, 21, 13, 5),
      startMinute: 600,
      endMinute: 660,
      dayCount: 3,
    );
    final first = dayNumber(DateTime(2026, 4, 21));
    expect(multi.day, DateTime(2026, 4, 21));
    expect(multi.time, (firstDay: first, dayCount: 3, start: 600, end: 660));
    expect(multi.coversDay(first), isTrue);
    expect(multi.coversDay(first + 2), isTrue);
    expect(multi.coversDay(first - 1), isFalse);
    expect(multi.coversDay(first + 3), isFalse);
    expect(multi.dayNumbers, <int>[first, first + 1, first + 2]);
  });

  test("E3 copyWith replaces each field given and keeps the others", () {
    final original = entry();
    final copy = original.copyWith(
      id: "entry-2",
      day: DateTime(2026, 4, 23),
      startMinute: 540,
      endMinute: 570,
      dayCount: 2,
      title: "Retro",
      color: red,
    );
    expect(copy.id, "entry-2");
    expect(copy.day, DateTime(2026, 4, 23));
    expect(copy.startMinute, 540);
    expect(copy.endMinute, 570);
    expect(copy.dayCount, 2);
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

  test("E4 the constructor asserts the day count and the minutes", () {
    expect(() => entry(dayCount: 0), throwsAssertionError);
    expect(() => entry(startMinute: -15), throwsAssertionError);
    expect(() => entry(startMinute: 600, endMinute: 600), throwsAssertionError);
    expect(() => entry(endMinute: 1455), throwsAssertionError);
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
