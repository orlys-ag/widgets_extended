/// The room the calendar keeps at its bottom ([CalendarView.bottomPadding]
/// on top of the inset its [MediaQuery] pads by): where Week's and Day's
/// last slot and Month's last week end, the row counting the entries after
/// the hours, what the views' builders read of the inset, and the values
/// the calendar refuses.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

final DateTime thursday = DateTime(2026, 4, 23);

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// An entry from [start] to [end] minutes after [day]'s midnight.
CalendarEntry<String> entryOf(String id, DateTime day, int start, int end) {
  return CalendarEntry<String>(
    id: id,
    start: DateTime(day.year, day.month, day.day, 0, start),
    end: DateTime(day.year, day.month, day.day, 0, end),
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// The inset the view's [MediaQuery] reports at the screen's bottom.
const double safeInset = 34.0;

/// The room the host asks for past [safeInset].
const double hostPadding = 40.0;

/// Lays the test out in a view [height] tall and 800 wide, at one
/// physical pixel per logical one, with [inset] at its bottom.
void useView(WidgetTester tester, {double height = 600.0, double inset = 0.0}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(800.0, height);
  tester.view.padding = FakeViewPadding(bottom: inset);
  addTearDown(tester.view.reset);
}

/// The vertical scroll position of the grid or the board of type [view].
ScrollPosition verticalOf(WidgetTester tester, Type view) {
  final states = tester.stateList<ScrollableState>(
    find.descendant(
      of: find.byType(view),
      matching: find.byWidgetPredicate((widget) {
        return widget is Scrollable;
      }),
    ),
  );
  return states.firstWhere((state) {
    return state.position.axis == Axis.vertical;
  }).position;
}

/// Scrolls the vertical position of [view] to its end.
Future<void> scrollToEnd(WidgetTester tester, Type view) async {
  final position = verticalOf(tester, view);
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  late MemoryCalendarStore<String> store;

  tearDown(() {
    store.dispose();
  });

  Future<CalendarController> pumpCalendar(
    WidgetTester tester, {
    required CalendarViewKind view,
    double bottomPadding = 0.0,
    CalendarController? controller,
    CalendarBlockBuilder<String>? blockBuilder,
    CalendarChipBuilder<String>? chipBuilder,
    bool editable = false,
  }) async {
    final shown =
        controller ?? CalendarController(view: view, selectedDay: thursday);
    if (controller == null) {
      addTearDown(shown.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: CalendarView<String>(
          store: store,
          controller: shown,
          clock: fixedClock,
          editable: editable,
          bottomPadding: bottomPadding,
          blockBuilder: blockBuilder,
          chipBuilder: chipBuilder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return shown;
  }

  testWidgets("BP1 Week's grid scrolls its last slot up past the inset and "
      "the host's padding", (tester) async {
    store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("late", thursday, 23 * 60 + 45, 24 * 60),
      ],
    );
    final grid = TimedGrid<String>;
    useView(tester);
    final controller = await pumpCalendar(tester, view: CalendarViewKind.week);
    await scrollToEnd(tester, grid);
    final plainExtent = verticalOf(tester, grid).maxScrollExtent;
    final plainBottom = tester.getRect(find.byKey(blockKey("late", thursday)));
    expect(plainExtent, greaterThan(0.0));

    useView(tester, inset: safeInset);
    await pumpCalendar(
      tester,
      view: CalendarViewKind.week,
      controller: controller,
      bottomPadding: hostPadding,
    );
    await scrollToEnd(tester, grid);
    expect(
      verticalOf(tester, grid).maxScrollExtent,
      moreOrLessEquals(plainExtent + safeInset + hostPadding),
    );
    expect(
      tester.getRect(find.byKey(blockKey("late", thursday))).bottom,
      moreOrLessEquals(plainBottom.bottom - safeInset - hostPadding),
    );
  });

  testWidgets("BP2 Day's grid, whose slots stretch to its height, ends its "
      "last slot the inset and the host's padding higher", (tester) async {
    store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("late", thursday, 23 * 60 + 45, 24 * 60),
      ],
    );
    useView(tester, height: 2400.0);
    final controller = await pumpCalendar(tester, view: CalendarViewKind.day);
    final plain = tester.getRect(find.byKey(blockKey("late", thursday)));
    expect(verticalOf(tester, TimedGrid<String>).maxScrollExtent, 0.0);

    useView(tester, height: 2400.0, inset: safeInset);
    await pumpCalendar(
      tester,
      view: CalendarViewKind.day,
      controller: controller,
      bottomPadding: hostPadding,
    );
    expect(verticalOf(tester, TimedGrid<String>).maxScrollExtent, 0.0);
    expect(
      tester.getRect(find.byKey(blockKey("late", thursday))).bottom,
      moreOrLessEquals(plain.bottom - safeInset - hostPadding),
    );
  });

  testWidgets("BP3 the row counting the entries after the hours stays its "
      "height, above the inset and the host's padding, which a block's "
      "move reads as that row", (tester) async {
    store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("evening", thursday, 19 * 60, 20 * 60),
        entryOf("review", thursday, 17 * 60, 17 * 60 + 30),
      ],
      hours: CalendarDayHours(8 * 60, 18 * 60),
    );
    useView(tester);
    final controller = await pumpCalendar(tester, view: CalendarViewKind.week);
    final plain = tester.getRect(find.byKey(hiddenBelowKey(thursday)));
    expect(plain.bottom, moreOrLessEquals(600.0));

    useView(tester, inset: safeInset);
    await pumpCalendar(
      tester,
      view: CalendarViewKind.week,
      controller: controller,
      bottomPadding: hostPadding,
      editable: true,
    );
    final padded = tester.getRect(find.byKey(hiddenBelowKey(thursday)));
    expect(padded.height, moreOrLessEquals(plain.height));
    expect(padded.bottom, moreOrLessEquals(600.0 - safeInset - hostPadding));
    await scrollToEnd(tester, TimedGrid<String>);
    expect(
      tester.getRect(find.byKey(hiddenBelowKey(thursday))).bottom,
      moreOrLessEquals(600.0 - safeInset - hostPadding),
    );
    // A move reads the row under its pointer ([TimedGrid]'s crossing),
    // which a debug build checks against the board's own cells; here,
    // inside the padding, past the notice's own height from the bottom.
    final move = await tester.startGesture(
      tester.getCenter(find.byKey(blockKey("review", thursday))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await move.moveTo(Offset(padded.center.dx, padded.bottom + 20.0));
    await tester.pump();
    await move.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("BP4 Month's weeks fit above the inset and the host's "
      "padding, and scrolled to its end so does its last week", (tester) async {
    store = MemoryCalendarStore<String>();
    final lastDay = CalendarMonthGrid.of(thursday).lastDay;
    useView(tester);
    final controller = await pumpCalendar(tester, view: CalendarViewKind.month);
    final plain = tester.getRect(find.byKey(monthDayKey(lastDay)));
    expect(plain.bottom, moreOrLessEquals(600.0, epsilon: 1.0));

    useView(tester, inset: safeInset);
    await pumpCalendar(
      tester,
      view: CalendarViewKind.month,
      controller: controller,
      bottomPadding: hostPadding,
    );
    expect(
      tester.getRect(find.byKey(monthDayKey(lastDay))).bottom,
      moreOrLessEquals(plain.bottom - safeInset - hostPadding, epsilon: 0.05),
    );

    controller.monthWeekScale = 2.0;
    await tester.pumpAndSettle();
    await scrollToEnd(tester, MonthBoard<String>);
    expect(verticalOf(tester, MonthBoard<String>).maxScrollExtent, isPositive);
    expect(
      tester.getRect(find.byKey(monthDayKey(lastDay))).bottom,
      moreOrLessEquals(plain.bottom - safeInset - hostPadding, epsilon: 0.05),
    );
  });

  testWidgets("BP5 the views' builders read no bottom inset, which the "
      "calendar pads by itself", (tester) async {
    store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("standup", thursday, 9 * 60, 10 * 60),
      ],
    );
    useView(tester, inset: safeInset);
    final insets = <double>[];
    Widget blockBuilder(
      BuildContext context,
      CalendarShownEntry<String> entry,
      CalendarBlockDetails details,
    ) {
      insets.add(MediaQuery.paddingOf(context).bottom);
      return const SizedBox.expand();
    }

    Widget chipBuilder(
      BuildContext context,
      CalendarShownEntry<String> entry,
      CalendarChipDetails details,
    ) {
      insets.add(MediaQuery.paddingOf(context).bottom);
      return const SizedBox.expand();
    }

    for (final view in <CalendarViewKind>[
      CalendarViewKind.week,
      CalendarViewKind.day,
      CalendarViewKind.month,
    ]) {
      insets.clear();
      await pumpCalendar(
        tester,
        view: view,
        blockBuilder: blockBuilder,
        chipBuilder: chipBuilder,
      );
      expect(insets, isNotEmpty, reason: "$view");
      expect(insets, everyElement(0.0), reason: "$view");
    }
  });

  testWidgets("BP6 a padding that is negative or not finite throws an "
      "ArgumentError naming bottomPadding", (tester) async {
    store = MemoryCalendarStore<String>();
    for (final padding in <double>[-1.0, double.nan, double.infinity]) {
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarView<String>(
            store: store,
            clock: fixedClock,
            bottomPadding: padding,
          ),
        ),
      );
      final error = tester.takeException();
      expect(error, isA<ArgumentError>(), reason: "$padding");
      expect((error as ArgumentError).name, "bottomPadding");
    }
  });
}
