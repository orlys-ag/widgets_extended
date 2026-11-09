/// The edit policy: the permissive answers a policy overriding nothing
/// gives, the unrestricted policy's equality, the time a policy answers
/// at, the policy of all of several, the day limit policy, the policy
/// forbidding overlaps, the per-pair answer on overlaps with the
/// candidate it takes, and which policies refuse every overlap.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/history_lock_policy.dart';

import '../dst_days.dart';
import '../store/zone_support.dart';

/// A Tuesday.
final DateTime tuesday = DateTime(2026, 4, 21);

final DateTime monday = DateTime(2026, 4, 20);
final DateTime wednesday = DateTime(2026, 4, 22);

/// [day] at [hour], [minute] and [second] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0, int second = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute, second);
}

CalendarEntry<String> entryOf(
  String id,
  DateTime start,
  DateTime end, {
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: isAllDay,
  );
}

/// A policy that overrides nothing.
final class _Plain extends CalendarEditPolicy<String> {
  const _Plain();
}

/// A policy that overrides only [allowsOverlaps], to false.
final class _Forbidding extends CalendarEditPolicy<String> {
  const _Forbidding();

  @override
  bool get allowsOverlaps {
    return false;
  }
}

/// A policy giving the answers it is made with, recording each ask in
/// [log] as its [name] and the member's, and the kind of each
/// [admitsChange] ask in [kinds], where given, as its [name] and "all-day"
/// or "timed". Its [mayOverlap] refuses the other entries whose ids
/// [refused] holds, whatever [overlaps] is, and its [refusesEveryOverlap]
/// answers [refusesEvery], whatever [mayOverlap] answers. Compared by
/// identity.
final class _Answering extends CalendarEditPolicy<String> {
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
    this.kinds,
    this.refused = const <String>{},
    this.refusesEvery = false,
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
  final List<String>? kinds;
  final Set<String> refused;
  final bool refusesEvery;

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
    CalendarNow now, {
    required bool isAllDay,
  }) {
    log.add("$name.admitsChange");
    kinds?.add("$name ${isAllDay ? "all-day" : "timed"}");
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

  @override
  bool get refusesEveryOverlap {
    log.add("$name.refusesEveryOverlap");
    return refusesEvery;
  }

  @override
  bool mayOverlap(
    CalendarOverlapCandidate<String> candidate,
    CalendarEntry<String> other,
  ) {
    log.add("$name.mayOverlap");
    return !refused.contains(other.id);
  }
}

/// A policy whose move answer throws a [StateError].
final class _Throwing extends CalendarEditPolicy<String> {
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
      policy.admitsChange(
        past,
        at(monday, 7),
        at(monday, 8),
        now,
        isAllDay: false,
      ),
      isTrue,
    );
    expect(
      policy.admitsChange(
        past,
        at(monday, 8),
        at(monday, 10),
        now,
        isAllDay: false,
      ),
      isTrue,
    );
    expect(policy.earliestStartOn(monday, now), monday);
    expect(policy.dayLimit, isNull);
    expect(policy.allowsOverlaps, isTrue);
  });

  test("EP2 two unrestricted policies are equal with equal hash codes, and "
      "one allows overlaps and limits no day count", () {
    const constant = UnrestrictedEditPolicy<String>();
    // ignore: prefer_const_constructors
    final built = UnrestrictedEditPolicy<String>();
    expect(built, constant);
    expect(built.hashCode, constant.hashCode);
    expect(constant.allowsOverlaps, isTrue);
    expect(constant.dayLimit, isNull);
  });

  test("EP20 a policy that does not override the per-pair answer gives its "
      "answer on overlaps for a pair that shares time: the unrestricted "
      "policy, the history lock and the day limit allow it, and one "
      "overriding only the answer on overlaps, to false, refuses it", () {
    final booked = entryOf("booked", at(tuesday, 9), at(tuesday, 10));
    final moved = entryOf("moved", at(tuesday, 8), at(tuesday, 9));
    final candidates = <CalendarOverlapCandidate<String>>[
      CalendarOverlapCandidate<String>(
        start: at(tuesday, 9, 30),
        end: at(tuesday, 10, 30),
        entry: moved,
      ),
      CalendarOverlapCandidate<String>(
        start: at(tuesday, 9, 30),
        end: at(tuesday, 9, 45),
      ),
    ];
    for (final candidate in candidates) {
      // Setup sanity: the pair shares time.
      expect(
        NoOverlapsPolicy.rangeSharesTime(
          candidate.start,
          candidate.end,
          booked,
        ),
        isTrue,
      );
      for (final policy in <CalendarEditPolicy<String>>[
        const UnrestrictedEditPolicy<String>(),
        const HistoryLockPolicy<String>(),
        const HistoryLockPolicy<String>(lockEarlierToday: true),
        DayLimitPolicy<String>(2),
      ]) {
        expect(
          policy.mayOverlap(candidate, booked),
          isTrue,
          reason: "$policy, $candidate",
        );
      }
      expect(
        const _Forbidding().mayOverlap(candidate, booked),
        isFalse,
        reason: "$candidate",
      );
    }
  });

  test("EP22 a candidate holds its times and the entry it changes, with its "
      "payload, and none for a create; equal candidates are equal with "
      "equal hash codes; and each one built counts once in a debug "
      "build", () {
    final moved = CalendarEntry<String>(
      id: "moved",
      start: at(tuesday, 8),
      end: at(tuesday, 9),
      title: "moved",
      color: const Color(0xFF336699),
      payload: "tentative",
    );
    final before = debugOverlapCandidateCount;
    final move = CalendarOverlapCandidate<String>(
      start: at(tuesday, 9),
      end: at(tuesday, 10),
      entry: moved,
    );
    final create = CalendarOverlapCandidate<String>(
      start: at(tuesday, 9),
      end: at(tuesday, 10),
    );
    expect(debugOverlapCandidateCount - before, 2);
    expect(move.start, at(tuesday, 9));
    expect(move.end, at(tuesday, 10));
    expect(move.entry, same(moved));
    expect(move.entry!.payload, "tentative");
    expect(create.entry, isNull);

    CalendarOverlapCandidate<String> movedAgain() {
      return CalendarOverlapCandidate<String>(
        start: at(tuesday, 9),
        end: at(tuesday, 10),
        entry: CalendarEntry<String>(
          id: "moved",
          start: at(tuesday, 8),
          end: at(tuesday, 9),
          title: "moved",
          color: const Color(0xFF336699),
          payload: "tentative",
        ),
      );
    }

    final again = movedAgain();
    expect(debugOverlapCandidateCount - before, 3);
    // Setup sanity: equal entries, not the same one.
    expect(identical(again.entry, moved), isFalse);
    expect(again, move);
    expect(again.hashCode, move.hashCode);
    final createAgain = CalendarOverlapCandidate<String>(
      start: at(tuesday, 9),
      end: at(tuesday, 10),
    );
    expect(createAgain, create);
    expect(createAgain.hashCode, create.hashCode);
    expect(create, isNot(move));
    expect(move, isNot(create));
    expect(
      CalendarOverlapCandidate<String>(
        start: at(tuesday, 9, 15),
        end: at(tuesday, 10),
      ),
      isNot(create),
    );
    expect(
      CalendarOverlapCandidate<String>(
        start: at(tuesday, 9),
        end: at(tuesday, 10, 15),
      ),
      isNot(create),
    );
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

  test(
    "RC8 a CalendarNow takes a UTC time as its local time, the same "
    "instant",
    skip: offUtcSkip,
    () {
      final time = offUtcTime!.add(const Duration(seconds: 30));
      final local = CalendarNow(time: time, today: tuesday);
      final fromUtc = CalendarNow(time: time.toUtc(), today: tuesday);
      expect(fromUtc.time.isUtc, isFalse);
      expect(fromUtc.time, time);
      expect(fromUtc, local);
      expect(fromUtc.timeOnToday, local.timeOnToday);
    },
  );

  test(
    "RC22 a CalendarNow still reads a UTC today by its year, month and "
    "day, not as its local time",
    skip: offUtcSkip,
    () {
      final today = offUtcTime!.toUtc();
      expect(
        CalendarNow(time: offUtcTime!, today: today).today,
        DateTime(today.year, today.month, today.day),
      );
    },
  );

  group("on the 25-hour day", skip: longDaySkip, () {
    test("RC9 a UTC time of the repeated stretch's second pass keeps that "
        "occurrence", () {
      final now = CalendarNow(
        time: secondHalfPastOne.toUtc(),
        today: longDayStart,
      );
      expect(now.time, secondHalfPastOne);
      expect(now.timeOnToday, secondHalfPastOne);
    });
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    test("RC9 a UTC time past the skipped hour keeps its instant", () {
      final time = shortDayStart.add(const Duration(hours: 2, minutes: 30));
      expect(
        CalendarNow(time: time.toUtc(), today: shortDayStart).timeOnToday,
        time,
      );
    });

    test("EP19 a today pinned to the day, whose clock skips the time of day "
        "of the reading, takes for timeOnToday the first minute after the "
        "skip, whatever the reading's seconds", () {
      final three = shortDayStart.add(const Duration(hours: 2));
      expect(
        CalendarNow(time: at(tuesday, 2, 30), today: shortDayStart).timeOnToday,
        three,
      );
      expect(
        CalendarNow(
          time: at(tuesday, 2, 59, 30),
          today: shortDayStart,
        ).timeOnToday,
        three,
      );
    });
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
        both.admitsChange(
          entry,
          at(tuesday, 11),
          at(tuesday, 12),
          now,
          isAllDay: false,
        ),
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
          policy.admitsChange(
            entry,
            at(tuesday, 11),
            at(tuesday, 12),
            now,
            isAllDay: false,
          ),
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
        refusing.admitsChange(
          entry,
          at(tuesday, 11),
          at(tuesday, 12),
          now,
          isAllDay: false,
        ),
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
        nothing.admitsChange(
          entry,
          at(monday, 7),
          at(monday, 8),
          now,
          isAllDay: false,
        ),
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
      final forbidding = NoOverlapsPolicy<String>();
      // ignore: prefer_const_constructors
      final allowing = UnrestrictedEditPolicy<String>();
      final policy = CalendarEditPolicy<String>.all(
        <CalendarEditPolicy<String>>[forbidding, allowing],
      );
      final same = CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
        const NoOverlapsPolicy<String>(),
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

    test("EP11 two of the same policies under other type arguments are "
        "unequal either way round", () {
      const member = UnrestrictedEditPolicy<String>();
      final ofObjects = CalendarEditPolicy<Object>.all(
        <CalendarEditPolicy<Object>>[member],
      );
      final ofStrings = CalendarEditPolicy<String>.all(
        <CalendarEditPolicy<String>>[member],
      );
      expect(ofObjects, isNot(ofStrings));
      expect(ofStrings, isNot(ofObjects));
    });

    test("EP18 passes the kind of each change to each of its policies in "
        "turn", () {
      final kinds = <String>[];
      final both = CalendarEditPolicy<String>.all(<_Answering>[
        _Answering("a", log, kinds: kinds),
        _Answering("b", log, kinds: kinds),
      ]);
      expect(
        both.admitsChange(entry, tuesday, wednesday, now, isAllDay: true),
        isTrue,
      );
      expect(
        both.admitsChange(entry, tuesday, wednesday, now, isAllDay: false),
        isTrue,
      );
      expect(kinds, <String>["a all-day", "b all-day", "a timed", "b timed"]);
    });

    test("EP21 lets a pair share time only where every policy that limits "
        "overlaps does: it asks them in order, reading each one's answer on "
        "overlaps, up to the first refusal, and never asks one whose answer "
        "on overlaps is true", () {
      final x = entryOf("X", at(tuesday, 9), at(tuesday, 10));
      final y = entryOf("Y", at(tuesday, 9), at(tuesday, 10));
      final candidate = CalendarOverlapCandidate<String>(
        start: at(tuesday, 9, 30),
        end: at(tuesday, 9, 45),
      );
      final refusingX = _Answering(
        "refusing",
        log,
        overlaps: false,
        refused: const <String>{"X"},
      );
      final mixed = CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
        const UnrestrictedEditPolicy<String>(),
        refusingX,
      ]);
      expect(mixed.mayOverlap(candidate, x), isFalse);
      expect(mixed.mayOverlap(candidate, y), isTrue);

      expect(
        CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
          const NoOverlapsPolicy<String>(),
          const UnrestrictedEditPolicy<String>(),
        ]).mayOverlap(candidate, y),
        isFalse,
      );
      expect(
        CalendarEditPolicy<String>.all(
          const <CalendarEditPolicy<String>>[],
        ).mayOverlap(candidate, x),
        isTrue,
      );

      final ordered = CalendarEditPolicy<String>.all(<_Answering>[
        _Answering("first", log, overlaps: false),
        _Answering(
          "second",
          log,
          overlaps: false,
          refused: const <String>{"X"},
        ),
        _Answering("third", log, overlaps: false),
      ]);
      log.clear();
      expect(ordered.mayOverlap(candidate, x), isFalse);
      expect(log, <String>[
        "first.allowsOverlaps",
        "first.mayOverlap",
        "second.allowsOverlaps",
        "second.mayOverlap",
      ]);
      log.clear();
      expect(ordered.mayOverlap(candidate, y), isTrue);
      expect(log, <String>[
        "first.allowsOverlaps",
        "first.mayOverlap",
        "second.allowsOverlaps",
        "second.mayOverlap",
        "third.allowsOverlaps",
        "third.mayOverlap",
      ]);

      final lax = _Answering("lax", log, refused: const <String>{"X"});
      // Setup sanity: asked alone, it refuses X.
      expect(lax.mayOverlap(candidate, x), isFalse);
      log.clear();
      expect(
        CalendarEditPolicy<String>.all(<_Answering>[
          lax,
        ]).mayOverlap(candidate, x),
        isTrue,
      );
      expect(log, <String>["lax.allowsOverlaps"]);
    });
  });

  group("the day limit policy", () {
    test("EP12 limits a range to its days and nothing else: it moves, "
        "resizes both edges, edits, deletes and admits every change, lets a "
        "new entry start from a day's start and allows overlaps", () {
      final policy = DayLimitPolicy<String>(3);
      final now = CalendarNow(time: at(tuesday, 11, 7), today: tuesday);
      final past = entryOf("past", at(monday, 9), at(monday, 10));
      expect(policy.dayLimit, 3);
      expect(policy.mayMove(past, now), isTrue);
      expect(policy.mayEdit(past, now), isTrue);
      expect(policy.mayDelete(past, now), isTrue);
      expect(policy.resizableEdges(past, now), CalendarResizeEdges.both);
      expect(
        policy.admitsChange(
          past,
          at(monday, 7),
          at(monday, 8),
          now,
          isAllDay: false,
        ),
        isTrue,
      );
      expect(policy.earliestStartOn(monday, now), monday);
      expect(policy.allowsOverlaps, isTrue);
    });

    test("EP13 two of the same limit are equal with equal hash codes; one "
        "of another limit, or under another type argument either way "
        "round, is not; and a limit under 1 throws an ArgumentError", () {
      var limit = 2;
      final policy = DayLimitPolicy<String>(limit);
      final same = DayLimitPolicy<String>(limit);
      expect(same, policy);
      expect(same.hashCode, policy.hashCode);
      expect(DayLimitPolicy<String>(limit + 1), isNot(policy));
      final ofObjects = DayLimitPolicy<Object>(limit);
      expect(ofObjects, isNot(policy));
      expect(policy, isNot(ofObjects));
      limit = 0;
      expect(
        () {
          return DayLimitPolicy<String>(limit);
        },
        throwsA(
          isArgumentError.having((error) => error.name, "name", "dayLimit"),
        ),
      );
    });

    test("EP14 combined with the policy forbidding overlaps, it gives that "
        "policy's answer and its own day limit", () {
      final policy = CalendarEditPolicy<String>.all(
        <CalendarEditPolicy<String>>[
          const NoOverlapsPolicy<String>(),
          DayLimitPolicy<String>(2),
        ],
      );
      expect(policy.dayLimit, 2);
      expect(policy.allowsOverlaps, isFalse);
    });
  });

  group("the policy forbidding overlaps", () {
    test("EP15 forbids overlaps and nothing else: it moves, resizes both "
        "edges, edits, deletes and admits every change, lets a new entry "
        "start from a day's start and limits no day count", () {
      const policy = NoOverlapsPolicy<String>();
      final now = CalendarNow(time: at(tuesday, 11, 7), today: tuesday);
      final past = entryOf("past", at(monday, 9), at(monday, 10));
      expect(policy.allowsOverlaps, isFalse);
      expect(policy.mayMove(past, now), isTrue);
      expect(policy.mayEdit(past, now), isTrue);
      expect(policy.mayDelete(past, now), isTrue);
      expect(policy.resizableEdges(past, now), CalendarResizeEdges.both);
      expect(
        policy.admitsChange(
          past,
          at(monday, 7),
          at(monday, 8),
          now,
          isAllDay: false,
        ),
        isTrue,
      );
      expect(policy.earliestStartOn(monday, now), monday);
      expect(policy.dayLimit, isNull);
    });

    test("EP16 two are equal with equal hash codes; one under another type "
        "argument, or the unrestricted policy, is not, either way "
        "round", () {
      const policy = NoOverlapsPolicy<String>();
      // ignore: prefer_const_constructors
      final built = NoOverlapsPolicy<String>();
      expect(built, policy);
      expect(built.hashCode, policy.hashCode);
      const ofObjects = NoOverlapsPolicy<Object>();
      expect(ofObjects, isNot(policy));
      expect(policy, isNot(ofObjects));
      const unrestricted = UnrestrictedEditPolicy<String>();
      expect(unrestricted, isNot(policy));
      expect(policy, isNot(unrestricted));
    });

    test("EP17 its test of two entries, of any payload types: two timed "
        "entries whose instants meet share time, two that only touch do "
        "not, nor does an all-day entry with a timed one", () {
      final nine = entryOf("nine", at(tuesday, 9), at(tuesday, 10));
      final half = entryOf("half", at(tuesday, 9, 30), at(tuesday, 10, 30));
      final ten = entryOf("ten", at(tuesday, 10), at(tuesday, 11));
      final allDay = CalendarEntry<int>(
        id: "day",
        start: tuesday,
        end: wednesday,
        title: "day",
        color: const Color(0xFF336699),
        payload: 1,
        isAllDay: true,
      );
      expect(NoOverlapsPolicy.entriesShareTime(nine, half), isTrue);
      expect(NoOverlapsPolicy.entriesShareTime(nine, ten), isFalse);
      expect(NoOverlapsPolicy.entriesShareTime(allDay, nine), isFalse);
    });
  });

  test("EP23 only the policy forbidding overlaps refuses every overlap, and "
      "the policy of all of several does where one of its policies whose "
      "answer on overlaps is false does, asking none after it", () {
    final log = <String>[];
    final single = <String, CalendarEditPolicy<String>>{
      "plain": const _Plain(),
      "forbidding": const _Forbidding(),
      "unrestricted": const UnrestrictedEditPolicy<String>(),
      "day limit": DayLimitPolicy<String>(1),
      "lock": const HistoryLockPolicy<String>(),
      "lock of earlier today": const HistoryLockPolicy<String>(
        lockEarlierToday: true,
      ),
      "no overlaps": const NoOverlapsPolicy<String>(),
    };
    expect(
      <String, bool>{
        for (final MapEntry(key: name, value: policy) in single.entries)
          name: policy.refusesEveryOverlap,
      },
      <String, bool>{
        "plain": false,
        "forbidding": false,
        "unrestricted": false,
        "day limit": false,
        "lock": false,
        "lock of earlier today": false,
        "no overlaps": true,
      },
    );

    CalendarEditPolicy<String> all(List<CalendarEditPolicy<String>> policies) {
      return CalendarEditPolicy<String>.all(policies);
    }

    expect(
      all(<CalendarEditPolicy<String>>[
        const NoOverlapsPolicy<String>(),
        const HistoryLockPolicy<String>(),
      ]).refusesEveryOverlap,
      isTrue,
      reason: "no overlaps, then the lock",
    );
    expect(
      all(<CalendarEditPolicy<String>>[
        const HistoryLockPolicy<String>(),
        const NoOverlapsPolicy<String>(),
      ]).refusesEveryOverlap,
      isTrue,
      reason: "the lock, then no overlaps",
    );
    expect(
      all(const <CalendarEditPolicy<String>>[]).refusesEveryOverlap,
      isFalse,
      reason: "none",
    );
    expect(
      all(<CalendarEditPolicy<String>>[
        const HistoryLockPolicy<String>(),
        DayLimitPolicy<String>(1),
      ]).refusesEveryOverlap,
      isFalse,
      reason: "the lock, then a day limit",
    );
    expect(
      all(<CalendarEditPolicy<String>>[
        _Answering("a", log, refusesEvery: true),
        _Answering("b", log, overlaps: false),
      ]).refusesEveryOverlap,
      isFalse,
      reason: "one allowing overlaps that claims to refuse every one",
    );
    log.clear();
    expect(
      all(<CalendarEditPolicy<String>>[
        _Answering("a", log, overlaps: false, refusesEvery: true),
        _Answering("b", log),
      ]).refusesEveryOverlap,
      isTrue,
      reason: "one forbidding overlaps that refuses every one",
    );
    expect(log, isNot(contains("b.refusesEveryOverlap")));
  });

  group("time zones", () {
    setUpAll(ensureZones);

    test("PE1 a CalendarNow and an overlap candidate compare by instant where "
        "either carries a zone", () {
      final on = DateTime(2025, 7, 16, 10, 7);
      final end = DateTime(2025, 7, 16, 11, 7);
      final zone = zoneAtDeviceOffset(on);
      final plainNow = CalendarNow(time: on, today: DateTime(2025, 7, 16));
      final zonedNow = CalendarNow(
        time: tz.TZDateTime.from(on, zone),
        today: tz.TZDateTime.from(DateTime(2025, 7, 16), zone),
      );
      expect(plainNow == zonedNow, isTrue);
      expect(zonedNow == plainNow, isTrue);
      expect(zonedNow.hashCode, plainNow.hashCode);

      final plainCandidate = CalendarOverlapCandidate<String>(
        start: on,
        end: end,
      );
      final zonedCandidate = CalendarOverlapCandidate<String>(
        start: tz.TZDateTime.from(on, zone),
        end: tz.TZDateTime.from(end, zone),
      );
      expect(plainCandidate == zonedCandidate, isTrue);
      expect(zonedCandidate == plainCandidate, isTrue);
      expect(zonedCandidate.hashCode, plainCandidate.hashCode);

      final utcCandidate = CalendarOverlapCandidate<String>(
        start: on.toUtc(),
        end: end.toUtc(),
      );
      expect(utcCandidate == plainCandidate, isFalse);
      expect(plainCandidate == utcCandidate, isFalse);
    });
  });
}
