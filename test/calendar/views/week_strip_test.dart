/// The week strip on its own: the days it marks selected and today when
/// it is given the day starts of a zone, and the days it opens on around
/// a middle day given.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import '../../scheduling/zones.dart';

/// The instant the zones apart from the device are built at.
final DateTime on = DateTime(2026, 4, 21, 12);

/// The day start, on the clock of the zone [hours] from the device's, of
/// April [day] 2026.
DateTime aprilIn(int hours, int day) {
  return dayOfNumberIn(
    CalendarDates.dayNumber(DateTime(2026, 4, day)),
    zoneApartFromDevice(on, hours),
  );
}

/// The day number of April [day] 2026.
int april(int day) {
  return CalendarDates.dayNumber(DateTime(2026, 4, day));
}

/// The day numbers of the day cells [marks] holds for.
Set<int> cellsWhere(WidgetTester tester, bool Function(DayCell cell) marks) {
  return <int>{
    for (final cell in tester.widgetList<DayCell>(find.byType(DayCell)))
      if (marks(cell)) CalendarDates.dayNumber(cell.day),
  };
}

void main() {
  testWidgets(
    "SZ1 a week strip marks the selected day and today given as a zone's day "
    "starts",
    (tester) async {
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);

      Widget strip({
        DateTime? initialDay,
        required DateTime selectedDay,
        required DateTime today,
      }) {
        return MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 350.0,
              child: WeekStrip<String>(
                store: store,
                selectedDay: selectedDay,
                today: today,
                weekdays: CalendarWeekdaySet.all,
                onSelectDay: (day) {},
                onBrowse: (day) {},
                initialDay: initialDay,
              ),
            ),
          ),
        );
      }

      bool selected(DayCell cell) {
        return cell.isSelected;
      }

      bool today(DayCell cell) {
        return cell.isToday;
      }

      // Opened on a plain day, as `monthFoldDay` gives one.
      final plain = DateTime(2026, 4, 20);
      await tester.pumpWidget(
        strip(
          initialDay: plain,
          selectedDay: aprilIn(6, 21),
          today: aprilIn(6, 23),
        ),
      );
      await tester.pumpAndSettle();
      expect(cellsWhere(tester, selected), <int>{april(21)});
      expect(cellsWhere(tester, today), <int>{april(23)});
      await tester.pumpWidget(
        strip(
          initialDay: plain,
          selectedDay: aprilIn(-6, 22),
          today: aprilIn(-6, 24),
        ),
      );
      await tester.pumpAndSettle();
      expect(cellsWhere(tester, selected), <int>{april(22)});
      expect(cellsWhere(tester, today), <int>{april(24)});

      // Opened on the selected day of one zone, then given another's.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        strip(selectedDay: aprilIn(6, 21), today: aprilIn(6, 23)),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        strip(selectedDay: aprilIn(-6, 22), today: aprilIn(-6, 24)),
      );
      await tester.pumpAndSettle();
      expect(cellsWhere(tester, selected), <int>{april(22)});
      expect(cellsWhere(tester, today), <int>{april(24)});
    },
  );

  testWidgets(
    "SM1 a week strip given initialMiddleDay opens with that day at its "
    "middle, half a week's count of shown days before it, rather than on "
    "a week, and reports no browse as it opens",
    (tester) async {
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      final browsed = <DateTime>[];

      Widget strip(CalendarWeekdaySet weekdays) {
        return MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 350.0,
              child: WeekStrip<String>(
                // A strip keeps its weekdays, so new ones need a new strip.
                key: ValueKey<CalendarWeekdaySet>(weekdays),
                store: store,
                selectedDay: DateTime(2026, 4, 21),
                today: DateTime(2026, 4, 21),
                weekdays: weekdays,
                onSelectDay: (day) {},
                onBrowse: browsed.add,
                initialDay: DateTime(2026, 4, 21),
                initialMiddleDay: DateTime(2026, 4, 24),
              ),
            ),
          ),
        );
      }

      /// The day numbers of the cells lying whole inside the strip, in
      /// order.
      List<int> shown() {
        final bounds = tester.getRect(find.byType(WeekStrip<String>));
        final days = <int>[];
        for (final element in find.byType(DayCell).evaluate()) {
          final box = element.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          if (rect.left >= bounds.left - 0.01 &&
              rect.right <= bounds.right + 0.01) {
            days.add(CalendarDates.dayNumber((element.widget as DayCell).day));
          }
        }
        days.sort();
        return days;
      }

      // Friday April 24 at the middle: Tuesday to Monday, where its week
      // runs from Monday April 20.
      await tester.pumpWidget(strip(CalendarWeekdaySet.all));
      await tester.pumpAndSettle();
      expect(shown(), <int>[for (var day = 21; day <= 27; day++) april(day)]);
      expect(browsed, isEmpty);
      // A drag short of half a day brings no other day to the middle.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(WeekStrip<String>)),
      );
      await gesture.moveBy(const Offset(-(kTouchSlop + 1.0), 0.0));
      await tester.pump();
      await gesture.moveBy(const Offset(-10.0, 0.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(browsed, isEmpty);

      // With the weekend hidden, two shown days on each side of Friday,
      // across the weekend.
      await tester.pumpWidget(strip(CalendarWeekdaySet.workweek));
      await tester.pumpAndSettle();
      expect(shown(), <int>[
        april(22),
        april(23),
        april(24),
        april(27),
        april(28),
      ]);
      expect(browsed, isEmpty);
    },
  );
}
