/// The edit policy: the permissive answers a policy overriding nothing
/// gives, the unrestricted policy's equality, the time a policy answers
/// at, and the policy of all of several.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';

/// A Tuesday.
final DateTime tuesday = DateTime(2026, 4, 21);

final DateTime monday = DateTime(2026, 4, 20);
final DateTime wednesday = DateTime(2026, 4, 22);

/// [day] at [hour], [minute] and [second] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0, int second = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute, second);
}

CalendarEntry<String> entryOf(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// A policy that overrides nothing.
class _Plain extends CalendarEditPolicy<String> {
  const _Plain();
}

/// A policy giving the answers it is made with, recording each ask in
/// [log] as its [name] and the member's. Compared by identity.
class _Answering extends CalendarEditPolicy<String> {
  const _Answering(
    this.name,
    this.log, {
    this.moves = true,
    this.edges = CalendarResizeEdges.both,
    this.edits = true,
    this.deletes = true,
    this.admits = true,
    this.earliest = _dayItself,
    this.limit,
    this.overlaps = true,
  });

  final String name;
  final List<String> log;
  final bool moves;
  final CalendarResizeEdges edges;
  final bool edits;
  final bool deletes;
  final bool admits;

  /// The earliest start this policy gives a day.
  final DateTime? Function(DateTime day) earliest;

  final int? limit;
  final bool overlaps;

  static DateTime? _dayItself(DateTime day) {
    return day;
  }

  @override
  bool mayMove(CalendarEntry<String> entry, CalendarNow now) {
    log.add("$name.mayMove");
    return moves;
  }

  @override
  CalendarResizeEdges resizableEdges(
    CalendarEntry<String> entry,
    CalendarNow now,
  ) {
    log.add("$name.resizableEdges");
    return edges;
  }

  @override
  bool mayEdit(CalendarEntry<String> entry, CalendarNow now) {
    log.add("$name.mayEdit");
    return edits;
  }

  @override
  bool mayDelete(CalendarEntry<String> entry, CalendarNow now) {
    log.add("$name.mayDelete");
    return deletes;
  }

  @override
  bool admitsChange(
    CalendarEntry<String> entry,
    DateTime start,
    DateTime end,
    CalendarNow now,
  ) {
    log.add("$name.admitsChange");
    return admits;
  }

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    log.add("$name.earliestStartOn");
    return earliest(day);
  }

  @override
  int? get dayLimit {
    log.add("$name.dayLimit");
    return limit;
  }

  @override
  bool get allowsOverlaps {
    log.add("$name.allowsOverlaps");
    return overlaps;
  }
}

/// A policy whose move answer throws a [StateError].
class _Throwing extends CalendarEditPolicy<String> {
  const _Throwing();

  @override
  bool mayMove(CalendarEntry<String> entry, CalendarNow now) {
    throw StateError("mayMove");
  }
}

void main() {
  test("EP1 a const policy overriding nothing moves, resizes both edges, "
      "edits, deletes and admits every change, lets a new entry start from "
      "a day's start, limits no day count and allows overlaps", () {
    const policy = _Plain();
    final now = CalendarNow(time: at(tuesday, 11, 7), today: tuesday);
    final past = entryOf("past", at(monday, 9), at(monday, 10));
    expect(policy.mayMove(past, now), isTrue);
    expect(policy.mayEdit(past, now), isTrue);
    expect(policy.mayDelete(past, now), isTrue);
    final edges = policy.resizableEdges(past, now);
    expect(edges, CalendarResizeEdges.both);
    expect((edges.hasStart, edges.hasEnd), (true, true));
    // A move into the past, and a resize of the start.
    expect(
      policy.admitsChange(past, at(monday, 7), at(monday, 8), now),
      isTrue,
    );
    expect(
      policy.admitsChange(past, at(monday, 8), at(monday, 10), now),
      isTrue,
    );
    expect(policy.earliestStartOn(monday, now), monday);
    expect(policy.dayLimit, isNull);
    expect(policy.allowsOverlaps, isTrue);
  });

  test("EP2 two unrestricted policies are equal with equal hash codes, one "
      "forbidding overlaps is not, and the default allows overlaps and "
      "limits no day count", () {
    const constant = UnrestrictedEditPolicy<String>();
    // ignore: prefer_const_constructors
    final built = UnrestrictedEditPolicy<String>();
    expect(built, constant);
    expect(built.hashCode, constant.hashCode);
    const forbidding = UnrestrictedEditPolicy<String>(allowsOverlaps: false);
    expect(forbidding, isNot(constant));
    expect(constant, isNot(forbidding));
    expect(constant.allowsOverlaps, isTrue);
    expect(forbidding.allowsOverlaps, isFalse);
    expect(constant.dayLimit, isNull);
  });

  test("EP3 a CalendarNow takes today to its midnight, rounds the time of "
      "day on today up to a whole minute, and compares by its time and "
      "today", () {
    CalendarNow nowAt(DateTime time, [DateTime? today]) {
      return CalendarNow(time: time, today: today ?? tuesday);
    }

    expect(nowAt(at(tuesday, 11, 7), at(tuesday, 15)).today, tuesday);
    expect(nowAt(at(tuesday, 11, 7)).timeOnToday, at(tuesday, 11, 7));
    expect(nowAt(at(tuesday, 11, 7, 30)).timeOnToday, at(tuesday, 11, 8));
    expect(
      nowAt(DateTime(2026, 4, 21, 11, 7, 0, 0, 1)).timeOnToday,
      at(tuesday, 11, 8),
    );
    expect(nowAt(at(tuesday, 23, 59, 30)).timeOnToday, wednesday);
    // The host pins today to Wednesday while the clock reads Tuesday.
    expect(
      nowAt(at(tuesday, 11, 7, 30), wednesday).timeOnToday,
      at(wednesday, 11, 8),
    );
    final now = nowAt(at(tuesday, 11, 7, 30));
    final same = nowAt(at(tuesday, 11, 7, 30), at(tuesday, 9));
    expect(same, now);
    expect(same.hashCode, now.hashCode);
    expect(nowAt(at(tuesday, 11, 7, 31)), isNot(now));
    expect(nowAt(at(tuesday, 11, 7, 30), wednesday), isNot(now));
  });

  group("the policy of all of several", () {
    final log = <String>[];
    final entry = entryOf("entry", at(tuesday, 9), at(tuesday, 10));
    final now = CalendarNow(time: at(tuesday, 8), today: tuesday);
    final open = _Answering("open", log);
    final shut = _Answering(
      "shut",
      log,
      moves: false,
      edits: false,
      deletes: false,
      admits: false,
      overlaps: false,
    );

    setUp(log.clear);

    test("EP5 allows a move, an edit, a delete, a change and overlaps only "
        "where each of its policies does", () {
      final both = CalendarEditPolicy<String>.all(<_Answering>[open, open]);
      expect(both.mayMove(entry, now), isTrue);
      expect(both.mayEdit(entry, now), isTrue);
      expect(both.mayDelete(entry, now), isTrue);
      expect(
        both.admitsChange(entry, at(tuesday, 11), at(tuesday, 12), now),
        isTrue,
      );
      expect(both.allowsOverlaps, isTrue);
      for (final members in <List<_Answering>>[
        <_Answering>[open, shut],
        <_Answering>[shut, open],
      ]) {
        final policy = CalendarEditPolicy<String>.all(members);
        final reason = members
            .map((member) {
              return member.name;
            })
            .join(", ");
        expect(policy.mayMove(entry, now), isFalse, reason: reason);
        expect(policy.mayEdit(entry, now), isFalse, reason: reason);
        expect(policy.mayDelete(entry, now), isFalse, reason: reason);
        expect(
          policy.admitsChange(entry, at(tuesday, 11), at(tuesday, 12), now),
          isFalse,
          reason: reason,
        );
        expect(policy.allowsOverlaps, isFalse, reason: reason);
      }
    });

    test("EP6 resizes only the edges each of its policies gives", () {
      const both = CalendarResizeEdges.both;
      const start = CalendarResizeEdges.start;
      const end = CalendarResizeEdges.end;
      const none = CalendarResizeEdges.none;
      for (final (first, second, edges)
          in <(CalendarResizeEdges, CalendarResizeEdges, CalendarResizeEdges)>[
            (both, both, both),
            (both, end, end),
            (start, both, start),
            (start, end, none),
            (end, end, end),
            (both, none, none),
          ]) {
        final policy = CalendarEditPolicy<String>.all(<_Answering>[
          _Answering("first", log, edges: first),
          _Answering("second", log, edges: second),
        ]);
        expect(
          policy.resizableEdges(entry, now),
          edges,
          reason: "$first and $second",
        );
      }
    });

    test("EP7 gives the latest earliest start of its policies, none where "
        "one gives none, and the least day limit they give", () {
      DateTime? earliestOf(List<DateTime?> answers) {
        return CalendarEditPolicy<String>.all(<_Answering>[
          for (final answer in answers)
            _Answering(
              "member",
              log,
              earliest: (day) {
                return answer;
              },
            ),
        ]).earliestStartOn(tuesday, now);
      }

      expect(earliestOf(<DateTime?>[tuesday, at(tuesday, 9)]), at(tuesday, 9));
      expect(
        earliestOf(<DateTime?>[at(tuesday, 11), at(tuesday, 9)]),
        at(tuesday, 11),
      );
      expect(earliestOf(<DateTime?>[at(monday, 22), tuesday]), tuesday);
      expect(earliestOf(<DateTime?>[at(tuesday, 9), wednesday]), wednesday);
      expect(earliestOf(<DateTime?>[at(tuesday, 9), null]), isNull);
      expect(earliestOf(<DateTime?>[null, at(tuesday, 9)]), isNull);

      int? limitOf(List<int?> limits) {
        return CalendarEditPolicy<String>.all(<_Answering>[
          for (final limit in limits) _Answering("member", log, limit: limit),
        ]).dayLimit;
      }

      expect(limitOf(<int?>[null, null]), isNull);
      expect(limitOf(<int?>[3, null]), 3);
      expect(limitOf(<int?>[null, 3]), 3);
      expect(limitOf(<int?>[3, 2]), 2);
      expect(limitOf(<int?>[2, 3]), 2);
    });

    test("EP8 asks its policies in order and no further than the first "
        "answer that settles its own", () {
      final refusing = CalendarEditPolicy<String>.all(<_Answering>[shut, open]);
      expect(refusing.mayMove(entry, now), isFalse);
      expect(refusing.mayEdit(entry, now), isFalse);
      expect(refusing.mayDelete(entry, now), isFalse);
      expect(
        refusing.admitsChange(entry, at(tuesday, 11), at(tuesday, 12), now),
        isFalse,
      );
      expect(refusing.allowsOverlaps, isFalse);
      expect(log, <String>[
        "shut.mayMove",
        "shut.mayEdit",
        "shut.mayDelete",
        "shut.admitsChange",
        "shut.allowsOverlaps",
      ]);

      log.clear();
      final opening = CalendarEditPolicy<String>.all(<_Answering>[open, shut]);
      expect(opening.mayMove(entry, now), isFalse);
      expect(log, <String>["open.mayMove", "shut.mayMove"]);

      log.clear();
      final edges = CalendarEditPolicy<String>.all(<_Answering>[
        _Answering("start", log, edges: CalendarResizeEdges.start),
        _Answering("end", log, edges: CalendarResizeEdges.end),
        _Answering("both", log),
      ]);
      expect(edges.resizableEdges(entry, now), CalendarResizeEdges.none);
      expect(log, <String>["start.resizableEdges", "end.resizableEdges"]);

      log.clear();
      final closing = CalendarEditPolicy<String>.all(<_Answering>[
        _Answering(
          "closed",
          log,
          earliest: (day) {
            return null;
          },
        ),
        open,
      ]);
      expect(closing.earliestStartOn(tuesday, now), isNull);
      expect(log, <String>["closed.earliestStartOn"]);

      log.clear();
      final limits = CalendarEditPolicy<String>.all(<_Answering>[
        _Answering("one", log, limit: 1),
        open,
      ]);
      expect(limits.dayLimit, 1);
      expect(log, <String>["one.dayLimit", "open.dayLimit"]);
    });

    test("EP9 of no policies limits nothing", () {
      final nothing = CalendarEditPolicy<String>.all(
        const <CalendarEditPolicy<String>>[],
      );
      expect(nothing.mayMove(entry, now), isTrue);
      expect(nothing.resizableEdges(entry, now), CalendarResizeEdges.both);
      expect(nothing.mayEdit(entry, now), isTrue);
      expect(nothing.mayDelete(entry, now), isTrue);
      expect(
        nothing.admitsChange(entry, at(monday, 7), at(monday, 8), now),
        isTrue,
      );
      expect(nothing.earliestStartOn(tuesday, now), tuesday);
      expect(nothing.dayLimit, isNull);
      expect(nothing.allowsOverlaps, isTrue);
    });

    test("EP10 two of equal policies in the same order are equal with "
        "equal hash codes; it keeps the policies it was made of; and a "
        "throw of a policy it asks throws out of it", () {
      // ignore: prefer_const_constructors
      final forbidding = UnrestrictedEditPolicy<String>(allowsOverlaps: false);
      // ignore: prefer_const_constructors
      final allowing = UnrestrictedEditPolicy<String>();
      final policy = CalendarEditPolicy<String>.all(
        <CalendarEditPolicy<String>>[forbidding, allowing],
      );
      final same = CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
        const UnrestrictedEditPolicy<String>(allowsOverlaps: false),
        const UnrestrictedEditPolicy<String>(),
      ]);
      expect(same, policy);
      expect(same.hashCode, policy.hashCode);
      expect(
        CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
          allowing,
          forbidding,
        ]),
        isNot(policy),
      );
      expect(
        CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
          forbidding,
        ]),
        isNot(policy),
      );

      final members = <CalendarEditPolicy<String>>[shut];
      final kept = CalendarEditPolicy<String>.all(members);
      members[0] = open;
      expect(kept.mayMove(entry, now), isFalse);

      expect(() {
        return CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
          open,
          const _Throwing(),
        ]).mayMove(entry, now);
      }, throwsA(isA<StateError>()));
    });
  });
}
