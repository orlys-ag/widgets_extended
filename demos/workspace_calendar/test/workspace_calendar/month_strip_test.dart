/// The month strip on its own: where each snap brings a fling to rest,
/// and the day a month folds into.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/month_strip.dart';

/// Pumps a strip on April 2026 under [snap], 350 px wide, and returns the
/// months it reports through [MonthStrip.onBrowse].
Future<List<DateTime>> pumpStrip(
  WidgetTester tester,
  MonthStripSnap snap,
) async {
  final browsed = <DateTime>[];
  final store = MemoryCalendarStore<String>();
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
            selectedDay: DateTime(2026, 4, 21),
            today: DateTime(2026, 4, 21),
            weekdays: WeekdaySet.all,
            rowHeight: 48.0,
            collapse: kAlwaysDismissedAnimation,
            onSelectDay: (day) {},
            onBrowse: browsed.add,
            snap: snap,
          ),
        ),
      ),
    ),
  );
  return browsed;
}

void main() {
  group("monthFoldDay", () {
    final today = DateTime(2026, 4, 21);

    test("is the selected day where the month holds it", () {
      expect(
        monthFoldDay(
          DateTime(2026, 4),
          selectedDay: DateTime(2026, 4, 9),
          today: today,
          weekdays: WeekdaySet.all,
        ),
        DateTime(2026, 4, 9),
      );
    });

    test("is today, or the shown day nearest it, where the month holds "
        "today and not the selected day", () {
      expect(
        monthFoldDay(
          DateTime(2026, 4),
          selectedDay: DateTime(2026, 5, 7),
          today: today,
          weekdays: WeekdaySet.all,
        ),
        today,
      );
      // April 25 2026 is a Saturday.
      expect(
        monthFoldDay(
          DateTime(2026, 4),
          selectedDay: DateTime(2026, 5, 7),
          today: DateTime(2026, 4, 25),
          weekdays: WeekdaySet.workweek,
        ),
        DateTime(2026, 4, 27),
      );
    });

    test("is the month's first shown day where it holds neither", () {
      expect(
        monthFoldDay(
          DateTime(2026, 5),
          selectedDay: today,
          today: today,
          weekdays: WeekdaySet.all,
        ),
        DateTime(2026, 5, 1),
      );
      // March 1 2026 is a Sunday.
      expect(
        monthFoldDay(
          DateTime(2026, 3),
          selectedDay: today,
          today: today,
          weekdays: WeekdaySet.workweek,
        ),
        DateTime(2026, 3, 2),
      );
    });
  });

  testWidgets("MS1 under nearest a fast fling passes several months, the "
      "last report naming the month it rests on", (tester) async {
    final browsed = await pumpStrip(tester, MonthStripSnap.nearest);

    await tester.fling(
      find.byType(MonthStrip<String>),
      const Offset(-100.0, 0.0),
      6000.0,
    );
    await tester.pumpAndSettle();
    expect(browsed.last.isAfter(DateTime(2026, 5)), isTrue);
    // At rest on that month: its first day in the top row, in its
    // weekday's column.
    final strip = tester.getRect(find.byType(MonthStrip<String>));
    final first = tester.getRect(find.byKey(dayCellKey(browsed.last)));
    expect(first.top, moreOrLessEquals(strip.top));
    expect(
      first.left,
      moreOrLessEquals(
        strip.left + weekdayColumn(browsed.last) * strip.width / 7,
      ),
    );
  });

  testWidgets("MS2 under next the same fling moves one month", (
    tester,
  ) async {
    final browsed = await pumpStrip(tester, MonthStripSnap.next);

    await tester.fling(
      find.byType(MonthStrip<String>),
      const Offset(-100.0, 0.0),
      6000.0,
    );
    await tester.pumpAndSettle();
    expect(browsed, <DateTime>[DateTime(2026, 5)]);
  });
}
