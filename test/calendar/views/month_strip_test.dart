/// The month strip on its own: where each snap brings a fling to rest,
/// the day a month folds into, and the month it browses back no further
/// than.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/month_strip.dart';

import '../../scheduling/zones.dart';

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
            weekdays: CalendarWeekdaySet.all,
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
          weekdays: CalendarWeekdaySet.all,
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
          weekdays: CalendarWeekdaySet.all,
        ),
        today,
      );
      // April 25 2026 is a Saturday.
      expect(
        monthFoldDay(
          DateTime(2026, 4),
          selectedDay: DateTime(2026, 5, 7),
          today: DateTime(2026, 4, 25),
          weekdays: CalendarWeekdaySet.workweek,
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
          weekdays: CalendarWeekdaySet.all,
        ),
        DateTime(2026, 5, 1),
      );
      // March 1 2026 is a Sunday.
      expect(
        monthFoldDay(
          DateTime(2026, 3),
          selectedDay: today,
          today: today,
          weekdays: CalendarWeekdaySet.workweek,
        ),
        DateTime(2026, 3, 2),
      );
    });

    test("with firstDay is firstDay where the day it would be lies in an "
        "earlier week, and that day where it lies in firstDay's week or "
        "later", () {
      // April 1 2026, a Wednesday, lies in the week from March 30.
      expect(
        monthFoldDay(
          DateTime(2026, 4),
          selectedDay: DateTime(2026, 5, 5),
          today: DateTime(2026, 6, 10),
          weekdays: CalendarWeekdaySet.all,
          firstDay: DateTime(2026, 4, 22),
        ),
        DateTime(2026, 4, 22),
      );
      // April 21 lies before April 23, in its week.
      expect(
        monthFoldDay(
          DateTime(2026, 4),
          selectedDay: DateTime(2026, 4, 21),
          today: DateTime(2026, 6, 10),
          weekdays: CalendarWeekdaySet.all,
          firstDay: DateTime(2026, 4, 23),
        ),
        DateTime(2026, 4, 21),
      );
      expect(
        monthFoldDay(
          DateTime(2026, 4),
          selectedDay: DateTime(2026, 5, 5),
          today: DateTime(2026, 4, 28),
          weekdays: CalendarWeekdaySet.all,
          firstDay: DateTime(2026, 4, 22),
        ),
        DateTime(2026, 4, 28),
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
        strip.left +
            CalendarDates.weekdayColumn(browsed.last) * strip.width / 7,
      ),
    );
  });

  testWidgets("MS4 a month strip given browseFrom opens on its month where "
      "month lies before it, slides back to no earlier month, by a fling or "
      "a new month, and folds into its week where the week it would fold "
      "into starts before it", (tester) async {
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final browsed = <DateTime>[];
    Widget strip(DateTime month, {Animation<double>? collapse}) {
      return MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 350.0,
            child: MonthStrip<String>(
              store: store,
              month: month,
              selectedDay: DateTime(2026, 5, 5),
              today: DateTime(2026, 6, 10),
              weekdays: CalendarWeekdaySet.all,
              rowHeight: 48.0,
              collapse: collapse ?? kAlwaysDismissedAnimation,
              onSelectDay: (day) {},
              onBrowse: browsed.add,
              browseFrom: DateTime(2026, 4, 22),
            ),
          ),
        ),
      );
    }

    /// The top left of [day]'s cell, from the strip's.
    Offset offsetOf(DateTime day) {
      return tester.getTopLeft(find.byKey(dayCellKey(day))) -
          tester.getTopLeft(find.byType(MonthStrip<String>));
    }

    void expectInRange(String step) {
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(MonthStrip<String>),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(
        position.pixels,
        greaterThanOrEqualTo(position.minScrollExtent - 0.01),
        reason: step,
      );
    }

    // April 1 2026 is a Wednesday, in the top row's third column.
    const onApril = Offset(100.0, 0.0);
    await tester.pumpWidget(strip(DateTime(2026, 3)));
    await tester.pumpAndSettle();
    expect(offsetOf(DateTime(2026, 4, 1)), onApril);

    await tester.fling(
      find.byType(MonthStrip<String>),
      const Offset(300.0, 0.0),
      3000.0,
    );
    await tester.pumpAndSettle();
    expect(offsetOf(DateTime(2026, 4, 1)), onApril);
    expect(
      browsed.where((month) {
        return month.isBefore(DateTime(2026, 4));
      }),
      isEmpty,
    );

    await tester.pumpWidget(strip(DateTime(2026, 6)));
    await tester.pumpAndSettle();
    // Setup sanity: a new month later than the limit's slides the strip.
    expect(offsetOf(DateTime(2026, 6, 1)), Offset.zero);
    await tester.pumpWidget(strip(DateTime(2026, 2)));
    for (var frame = 0; frame < 30; frame++) {
      expectInRange("frame $frame");
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(offsetOf(DateTime(2026, 4, 1)), onApril);

    // Folded on April, which holds neither the selected day nor today: its
    // first day's week starts before April 22's.
    await tester.pumpWidget(
      strip(DateTime(2026, 4), collapse: kAlwaysCompleteAnimation),
    );
    await tester.pumpAndSettle();
    expect(offsetOf(DateTime(2026, 4, 22)), const Offset(100.0, 0.0));
  });

  testWidgets("MS2 under next the same fling moves one month", (tester) async {
    final browsed = await pumpStrip(tester, MonthStripSnap.next);

    await tester.fling(
      find.byType(MonthStrip<String>),
      const Offset(-100.0, 0.0),
      6000.0,
    );
    await tester.pumpAndSettle();
    expect(browsed, <DateTime>[DateTime(2026, 5)]);
  });

  testWidgets("MS3 a day isDayEnabled refuses draws disabled and takes no "
      "tap and no arrow key, and with no onSelectDay no day takes either", (
    tester,
  ) async {
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final selected = <DateTime>[];
    // The key downs the strip leaves to the widgets above it.
    final passed = <LogicalKeyboardKey>[];
    final refused = DateTime(2026, 4, 23);
    Widget strip({
      bool Function(DateTime day)? isDayEnabled,
      bool selects = true,
    }) {
      return MaterialApp(
        home: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              passed.add(event.logicalKey);
            }
            return KeyEventResult.ignored;
          },
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 350.0,
              child: MonthStrip<String>(
                store: store,
                month: DateTime(2026, 4),
                selectedDay: DateTime(2026, 4, 22),
                today: DateTime(2026, 4, 21),
                weekdays: CalendarWeekdaySet.all,
                rowHeight: 48.0,
                collapse: kAlwaysDismissedAnimation,
                onSelectDay: selects ? selected.add : null,
                onBrowse: (month) {},
                isDayEnabled: isDayEnabled,
              ),
            ),
          ),
        ),
      );
    }

    Finder cellOf(DateTime day) {
      return find.byKey(dayCellKey(day));
    }

    FocusNode stripNode() {
      return tester
          .widget<Focus>(
            find
                .descendant(
                  of: find.byType(MonthStrip<String>),
                  matching: find.byType(Focus),
                )
                .first,
          )
          .focusNode!;
    }

    await tester.pumpWidget(
      strip(
        isDayEnabled: (day) {
          return day != refused;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DayCell>(cellOf(refused)).enabled, isFalse);
    expect(
      tester.widget<DayCell>(cellOf(DateTime(2026, 4, 24))).enabled,
      isTrue,
    );
    final theme = CalendarTheme.of(
      tester.element(find.byType(MonthStrip<String>)),
    );
    final number = tester.widget<Text>(
      find.descendant(of: cellOf(refused), matching: find.text("23")),
    );
    expect(
      number.style!.color!.a,
      moreOrLessEquals(theme.text.a * theme.disabledOpacity),
    );
    await tester.tap(cellOf(refused));
    await tester.pump();
    expect(selected, isEmpty);
    expect(stripNode().hasFocus, isFalse);

    await tester.tap(cellOf(DateTime(2026, 4, 22)));
    await tester.pump();
    // Setup sanity: the tap on an enabled day reports it and focuses the
    // strip.
    expect(selected, <DateTime>[DateTime(2026, 4, 22)]);
    expect(stripNode().hasFocus, isTrue);
    selected.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected, isEmpty);
    expect(passed, isEmpty);

    await tester.pumpWidget(strip());
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<DayCell>(find.byType(DayCell)).map((cell) {
        return cell.enabled;
      }).toSet(),
      <bool?>{null},
    );

    await tester.pumpWidget(strip(selects: false));
    await tester.pumpAndSettle();
    stripNode().unfocus();
    await tester.pump();
    await tester.tap(cellOf(DateTime(2026, 4, 24)));
    await tester.pump();
    expect(stripNode().hasFocus, isFalse);
    stripNode().requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected, isEmpty);
    expect(passed, <LogicalKeyboardKey>[LogicalKeyboardKey.arrowRight]);
  });

  testWidgets(
    "SZ2 a month strip marks the selected day and today given as a zone's "
    "day starts",
    (tester) async {
      final on = DateTime(2026, 4, 21, 12);
      DateTime aprilIn(int hours, int day) {
        return dayOfNumberIn(
          CalendarDates.dayNumber(DateTime(2026, 4, day)),
          zoneApartFromDevice(on, hours),
        );
      }

      int april(int day) {
        return CalendarDates.dayNumber(DateTime(2026, 4, day));
      }

      Set<int> cellsWhere(bool Function(DayCell cell) marks) {
        return <int>{
          for (final cell in tester.widgetList<DayCell>(find.byType(DayCell)))
            if (marks(cell)) CalendarDates.dayNumber(cell.day),
        };
      }

      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      Widget strip(DateTime selectedDay, DateTime today) {
        return MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 350.0,
              child: MonthStrip<String>(
                store: store,
                month: DateTime(2026, 4),
                selectedDay: selectedDay,
                today: today,
                weekdays: CalendarWeekdaySet.all,
                rowHeight: 48.0,
                collapse: kAlwaysDismissedAnimation,
                onSelectDay: (day) {},
                onBrowse: (month) {},
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(strip(aprilIn(6, 21), aprilIn(6, 23)));
      await tester.pumpAndSettle();
      expect(
        cellsWhere((cell) {
          return cell.isSelected;
        }),
        <int>{april(21)},
      );
      expect(
        cellsWhere((cell) {
          return cell.isToday;
        }),
        <int>{april(23)},
      );
      await tester.pumpWidget(strip(aprilIn(-6, 22), aprilIn(-6, 24)));
      await tester.pumpAndSettle();
      expect(
        cellsWhere((cell) {
          return cell.isSelected;
        }),
        <int>{april(22)},
      );
      expect(
        cellsWhere((cell) {
          return cell.isToday;
        }),
        <int>{april(24)},
      );
    },
  );
}
