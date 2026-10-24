/// The badges on the days of the week strip and the month strip: the kinds
/// a day's entries have, in the kinds' order, and the primary dot for the
/// entries of no kind or where the strip is given no kinds; the dots along
/// the circle's rim about its top right, four at most, and what a screen
/// reader hears; the caching store's marker gate; and when a day reads and
/// builds its badges again.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/month_strip.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

const CalendarBadgeKind task = CalendarBadgeKind(
  color: Color(0xFF1F4E8C),
  label: "Task",
);
const CalendarBadgeKind meeting = CalendarBadgeKind(
  color: Color(0xFF1F7A72),
  label: "Meeting",
);
const CalendarBadgeKind away = CalendarBadgeKind(
  color: Color(0xFF5B5FA8),
  label: "Out of office",
);
const CalendarBadgeKind deadline = CalendarBadgeKind(
  color: Color(0xFFC2503A),
  label: "Deadline",
);

/// The kind of each payload; "other" has none.
const Map<String, CalendarBadgeKind> kindsByPayload =
    <String, CalendarBadgeKind>{
      "task": task,
      "meeting": meeting,
      "away": away,
      "deadline": deadline,
    };

final CalendarDayBadges<String> badges = CalendarDayBadges<String>(
  kinds: kindsByPayload.values.toList(),
  kindOf: (entry) {
    return kindsByPayload[entry.payload];
  },
);

const CalendarThemeData theme = CalendarThemeData();

DateTime april(int day) {
  return DateTime(2026, 4, day);
}

/// An hour from [hour] on [day], of [payload]'s kind.
CalendarEntry<String> entryOf(
  String id,
  DateTime day,
  int hour,
  String payload,
) {
  return CalendarEntry<String>(
    id: id,
    start: DateTime(day.year, day.month, day.day, hour),
    end: DateTime(day.year, day.month, day.day, hour + 1),
    title: id,
    color: const Color(0xFF336699),
    payload: payload,
  );
}

/// The week of April 20 2026: Tuesday the 21st holds an entry of no kind;
/// Wednesday the 22nd one of each kind, in the reverse of the kinds'
/// order; Thursday the 23rd a meeting before a task; Friday the 24th one
/// of each kind and one of none; Saturday the 25th nothing; Sunday the
/// 26th a task, an absence and a deadline.
List<CalendarEntry<String>> weekEntries() {
  return <CalendarEntry<String>>[
    entryOf("t-other", april(21), 9, "other"),
    entryOf("w-deadline", april(22), 8, "deadline"),
    entryOf("w-away", april(22), 9, "away"),
    entryOf("w-meeting", april(22), 10, "meeting"),
    entryOf("w-task", april(22), 11, "task"),
    entryOf("th-meeting", april(23), 9, "meeting"),
    entryOf("th-task", april(23), 10, "task"),
    entryOf("f-task", april(24), 8, "task"),
    entryOf("f-meeting", april(24), 9, "meeting"),
    entryOf("f-away", april(24), 10, "away"),
    entryOf("f-deadline", april(24), 11, "deadline"),
    entryOf("f-other", april(24), 12, "other"),
    entryOf("s-task", april(26), 8, "task"),
    entryOf("s-away", april(26), 9, "away"),
    entryOf("s-deadline", april(26), 10, "deadline"),
  ];
}

/// A week strip on April 21 2026, 350 px wide, over [entries], under
/// [dayBadges].
Future<void> pumpWeek(
  WidgetTester tester, {
  required List<CalendarEntry<String>> entries,
  CalendarDayBadges<String>? dayBadges,
}) async {
  final store = MemoryCalendarStore<String>(entries: entries);
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 350.0,
          child: WeekStrip<String>(
            store: store,
            selectedDay: april(21),
            today: april(21),
            weekdays: WeekdaySet.all,
            onSelectDay: (day) {},
            onBrowse: (day) {},
            dayBadges: dayBadges,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The circle of the week strip's [day].
Rect circleOf(WidgetTester tester, DateTime day) {
  return tester.getRect(
    find
        .descendant(
          of: find.byKey(weekStripDayKey(day)),
          matching: find.byType(Container),
        )
        .first,
  );
}

BoxDecoration badgeOf(WidgetTester tester, DateTime day, int index) {
  return tester
          .widget<DecoratedBox>(find.byKey(dayBadgeKey(day, index)))
          .decoration
      as BoxDecoration;
}

/// Where the centre of the badge at [index] of [count] lies from the
/// centre of its circle: on the rim through a lone badge's centre, 11.5 px
/// in from the circle's top and right, at 30 degrees apart about it.
Offset arcOffset(int index, int count) {
  final degrees = 45.0 + (index - (count - 1) / 2.0) * 30.0;
  final radians = degrees * math.pi / 180.0;
  const radius = 11.5 * math.sqrt2;
  return Offset(radius * math.sin(radians), -radius * math.cos(radians));
}

void expectArc(WidgetTester tester, DateTime day, int count) {
  final centre = circleOf(tester, day).center;
  for (var index = 0; index < count; index++) {
    final at = tester.getRect(find.byKey(dayBadgeKey(day, index))).center;
    final expected = centre + arcOffset(index, count);
    expect(
      at.dx,
      moreOrLessEquals(expected.dx, epsilon: 1e-6),
      reason: "badge $index of $count, across",
    );
    expect(
      at.dy,
      moreOrLessEquals(expected.dy, epsilon: 1e-6),
      reason: "badge $index of $count, down",
    );
  }
}

/// A data source each of whose reads waits until the test answers it,
/// with the entries covering its days.
class HeldReads implements CalendarDataSource<String> {
  HeldReads(this.entries);

  final List<CalendarEntry<String>> entries;

  final List<({DateTime first, VoidCallback answer})> reads =
      <({DateTime first, VoidCallback answer})>[];

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final from = dayNumber(first);
    final to = dayNumber(last);
    final completer = Completer<List<CalendarEntry<String>>>();
    reads.add((
      first: first,
      answer: () {
        completer.complete(<CalendarEntry<String>>[
          for (final entry in entries)
            if (dayNumber(entry.start) <= to && dayNumber(entry.start) >= from)
              entry,
        ]);
      },
    ));
    return completer.future;
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
  group("dayBadgesOf", () {
    test("DB1 without kinds gives a day with entries the primary dot alone, "
        "and a day without none", () {
      final store = MemoryCalendarStore<String>(entries: weekEntries());
      addTearDown(store.dispose);
      expect(dayBadgesOf(store, april(22), null), <CalendarBadgeKind?>[null]);
      expect(dayBadgesOf(store, april(25), null), isEmpty);
    });

    test("DB2 gives each kind a day's entries have once, in the kinds' "
        "order, then the primary dot for the entries of no kind", () {
      final store = MemoryCalendarStore<String>(entries: weekEntries());
      addTearDown(store.dispose);
      expect(dayBadgesOf(store, april(23), badges), <CalendarBadgeKind?>[
        task,
        meeting,
      ]);
      expect(dayBadgesOf(store, april(22), badges), <CalendarBadgeKind?>[
        task,
        meeting,
        away,
        deadline,
      ]);
      expect(dayBadgesOf(store, april(24), badges), <CalendarBadgeKind?>[
        task,
        meeting,
        away,
        deadline,
        null,
      ]);
      expect(dayBadgesOf(store, april(21), badges), <CalendarBadgeKind?>[null]);
      expect(dayBadgesOf(store, april(25), badges), isEmpty);
    });

    test("DB3 gives nothing to a day the caching store shows no marker for, "
        "though it holds the day's entries", () async {
      final source = HeldReads(<CalendarEntry<String>>[
        entryOf("a", april(21), 9, "task"),
        entryOf("b", DateTime(2026, 5, 12), 9, "meeting"),
      ]);
      final store = CachingCalendarStore<String>(dataSource: source);
      addTearDown(store.dispose);
      store.show(april(20), april(26));
      store.prefetch(DateTime(2026, 5, 11), DateTime(2026, 5, 17));
      expect(source.reads, hasLength(2));
      // The prefetch answers while the shown week still loads.
      source.reads[1].answer();
      await Future<void>.delayed(Duration.zero);
      final may12 = DateTime(2026, 5, 12);
      expect(store.entriesOn(may12), hasLength(1), reason: "filed");
      expect(store.dayHasShownEntries(may12), isFalse, reason: "no marker");
      expect(dayBadgesOf(store, may12, badges), isEmpty);

      source.reads[0].answer();
      await Future<void>.delayed(Duration.zero);
      expect(dayBadgesOf(store, may12, badges), <CalendarBadgeKind?>[meeting]);
      expect(dayBadgesOf(store, april(21), badges), <CalendarBadgeKind?>[task]);
    });

    test("DB4 a kind the kinds do not hold fails an assertion", () {
      final store = MemoryCalendarStore<String>(
        entries: <CalendarEntry<String>>[entryOf("a", april(21), 9, "task")],
      );
      addTearDown(store.dispose);
      final stray = CalendarDayBadges<String>(
        kinds: const <CalendarBadgeKind>[meeting],
        kindOf: (entry) {
          return task;
        },
      );
      expect(() {
        dayBadgesOf(store, april(21), stray);
      }, throwsAssertionError);
    });
  });

  testWidgets("DB5 a day builds again when a store change or new badges "
      "change its badges, and not for a store change that leaves them", (
    tester,
  ) async {
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[entryOf("a", april(21), 9, "task")],
    );
    addTearDown(store.dispose);
    final built = <List<CalendarBadgeKind?>>[];
    Future<void> pumpUnder(CalendarDayBadges<String>? dayBadges) {
      return tester.pumpWidget(
        DayMarkerListener<String>(
          store: store,
          day: april(21),
          badges: dayBadges,
          builder: (context, badges) {
            built.add(badges);
            return const SizedBox.shrink();
          },
        ),
      );
    }

    await pumpUnder(badges);
    expect(built, <List<CalendarBadgeKind?>>[
      <CalendarBadgeKind?>[task],
    ]);

    await store.create(entryOf("b", april(21), 11, "task"));
    await tester.pump();
    expect(built, hasLength(1), reason: "a second task");

    await store.create(entryOf("c", april(21), 13, "meeting"));
    await tester.pump();
    expect(built.last, <CalendarBadgeKind?>[task, meeting]);
    expect(built, hasLength(2), reason: "a first meeting");

    await pumpUnder(null);
    expect(built.last, <CalendarBadgeKind?>[null], reason: "no kinds");
    await pumpUnder(badges);
    expect(built.last, <CalendarBadgeKind?>[task, meeting], reason: "kinds");
  });

  testWidgets("DB6 the week strip draws a day's kinds along the circle's "
      "rim about its top right, 30 degrees apart, 9 px wide for one or two "
      "and 7 px for more, ringed in the surface colour, 1.5 px or 1 px "
      "wide", (tester) async {
    await pumpWeek(tester, entries: weekEntries(), dayBadges: badges);
    Size sizeOf(DateTime day, int index) {
      return tester.getSize(find.byKey(dayBadgeKey(day, index)));
    }

    expectArc(tester, april(23), 2);
    expect(badgeOf(tester, april(23), 0).color, task.color);
    expect(badgeOf(tester, april(23), 1).color, meeting.color);
    expect(find.byKey(dayBadgeKey(april(23), 2)), findsNothing);
    expect(sizeOf(april(23), 0), const Size(9.0, 9.0));
    expect(sizeOf(april(23), 1), const Size(9.0, 9.0));
    expect((badgeOf(tester, april(23), 1).border! as Border).top.width, 1.5);

    expectArc(tester, april(26), 3);
    expect(
      <Color?>[
        for (var index = 0; index < 3; index++)
          badgeOf(tester, april(26), index).color,
      ],
      <Color>[task.color, away.color, deadline.color],
    );
    for (var index = 0; index < 3; index++) {
      expect(sizeOf(april(26), index), const Size(7.0, 7.0));
    }

    expectArc(tester, april(22), 4);
    expect(
      <Color?>[
        for (var index = 0; index < 4; index++)
          badgeOf(tester, april(22), index).color,
      ],
      <Color>[task.color, meeting.color, away.color, deadline.color],
    );
    for (var index = 0; index < 4; index++) {
      expect(
        (badgeOf(tester, april(22), index).border! as Border).top.color,
        theme.surface,
        reason: "badge $index's ring",
      );
      expect(sizeOf(april(22), index), const Size(7.0, 7.0));
      expect(
        (badgeOf(tester, april(22), index).border! as Border).top.width,
        1.0,
        reason: "badge $index's ring",
      );
    }
  });

  testWidgets("DB7 a circle draws its first four badges, a lone one at its "
      "top right corner, and a screen reader hears every kind", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpWeek(tester, entries: weekEntries(), dayBadges: badges);
    String labelOf(DateTime day) {
      return tester.getSemantics(find.byKey(weekStripDayKey(day))).label;
    }

    expectArc(tester, april(24), 4);
    expect(badgeOf(tester, april(24), 3).color, deadline.color);
    expect(find.byKey(dayBadgeKey(april(24), 4)), findsNothing);
    expect(
      labelOf(april(24)),
      "Friday, April 24, has Task, Meeting, Out of office, Deadline, other "
      "items",
    );
    expect(labelOf(april(23)), "Thursday, April 23, has Task, Meeting");

    expect(badgeOf(tester, april(21), 0).color, theme.primary);
    expect(
      tester.getRect(find.byKey(dayBadgeKey(april(21)))),
      Rect.fromLTRB(
        circleOf(tester, april(21)).right - 9.0,
        circleOf(tester, april(21)).top,
        circleOf(tester, april(21)).right,
        circleOf(tester, april(21)).top + 9.0,
      ),
    );
    expect(find.byKey(dayBadgeKey(april(21), 1)), findsNothing);
    expect(labelOf(april(21)), "Tuesday, April 21, has items");
    expect(find.byKey(dayBadgeKey(april(25))), findsNothing);
    expect(labelOf(april(25)), "Saturday, April 25");

    // Without kinds every day with entries carries the primary dot alone.
    await pumpWeek(tester, entries: weekEntries());
    expect(badgeOf(tester, april(22), 0).color, theme.primary);
    expect(
      tester.getRect(find.byKey(dayBadgeKey(april(22)))).topRight,
      circleOf(tester, april(22)).topRight,
    );
    expect(find.byKey(dayBadgeKey(april(22), 1)), findsNothing);
    expect(labelOf(april(22)), "Wednesday, April 22, has items");
    semantics.dispose();
  });

  testWidgets("DB8 the month strip's days and, mid-fold, the days of the "
      "months beside it carry their kinds", (tester) async {
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("a", april(23), 9, "meeting"),
        entryOf("b", april(23), 10, "task"),
        entryOf("c", DateTime(2026, 3, 31), 9, "deadline"),
      ],
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 350.0,
            child: MonthStrip<String>(
              store: store,
              month: DateTime(2026, 4),
              selectedDay: april(21),
              today: april(21),
              weekdays: WeekdaySet.all,
              rowHeight: 48.0,
              collapse: const AlwaysStoppedAnimation<double>(0.5),
              onSelectDay: (day) {},
              onBrowse: (day) {},
              dayBadges: badges,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    List<List<CalendarBadgeKind?>> badgesOn(
      DateTime day, {
      required bool inMonth,
    }) {
      return <List<CalendarBadgeKind?>>[
        for (final cell in tester.widgetList<DayCell>(
          find.byWidgetPredicate((widget) {
            return widget is DayCell &&
                widget.day == day &&
                widget.inMonth == inMonth;
          }),
        ))
          cell.badges,
      ];
    }

    expect(badgesOn(april(23), inMonth: true), <List<CalendarBadgeKind?>>[
      <CalendarBadgeKind?>[task, meeting],
    ]);
    // March 31 2026, a Tuesday, opens April's first week.
    expect(
      badgesOn(DateTime(2026, 3, 31), inMonth: false),
      <List<CalendarBadgeKind?>>[
        <CalendarBadgeKind?>[deadline],
      ],
    );
  });
}
