/// The timed grid's own parameters: the weekdays, hours, hour format and
/// least sizes it lays out from, and the edit mode and lock choices its
/// drags follow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

/// [grid] in a box of [size] at the top left, under no calendar theme.
Widget boxed(Size size, TimedGrid<String> grid) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: size.width, height: size.height, child: grid),
    ),
  );
}

/// Pumps [grid] [boxed] at [size], in a view of that size.
Future<void> pumpBoxed(
  WidgetTester tester,
  Size size,
  TimedGrid<String> grid,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(boxed(size, grid));
}

/// The grid's viewport: the one board keyed by entry id strings.
RenderBoardViewport<String> viewportOf(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

void main() {
  testWidgets("TG1 a timed grid shows the weekdays and hours, labels the "
      "hours in the format and sizes its cells from the least sizes its "
      "parameters give it, and fits again when they change", (tester) async {
    const size = Size(300.0, 400.0);
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final now = ValueNotifier<DateTime>(DateTime(2026, 4, 21, 9));
    addTearDown(now.dispose);
    TimedGrid<String> grid({
      required HourLabelFormat format,
      required double minSlotHeight,
    }) {
      return TimedGrid<String>(
        store: store,
        firstDay: monday,
        dayCount: 7,
        selectedDay: tuesday,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenItem: (id) {},
        onCreate: (range) async {},
        weekdays: WeekdaySet.workweek,
        hours: const DayHours(8 * 60, 18 * 60),
        hourLabelFormat: format,
        minDayWidth: 100.0,
        minSlotHeight: minSlotHeight,
      );
    }

    await pumpBoxed(
      tester,
      size,
      grid(format: HourLabelFormat.twelveHour, minSlotHeight: 20.0),
    );
    await tester.pumpAndSettle();
    final viewport = viewportOf(tester);
    // The gutter and the five weekdays of the seven days.
    expect(viewport.rectOfCell(2, 5), isNotNull);
    expect(viewport.rectOfCell(2, 6), isNull);
    // The day header, the room above, the 40 slots from 08:00 to 18:00 and
    // the room below.
    expect(viewport.rectOfCell(42, 1), isNotNull);
    expect(viewport.rectOfCell(43, 1), isNull);
    // The box's shares, 244 / 5 px across and under 10 px down, are below
    // both least sizes.
    expect(viewport.rectOfCell(2, 1)!.size, const Size(100.0, 20.0));
    expect(find.bySemanticsLabel("8 AM"), findsOneWidget);
    expect(find.bySemanticsLabel("08:00"), findsNothing);

    await tester.pumpWidget(
      boxed(
        size,
        grid(format: HourLabelFormat.twentyFourHour, minSlotHeight: 20.0),
      ),
    );
    expect(find.bySemanticsLabel("08:00"), findsOneWidget);
    expect(find.bySemanticsLabel("8 AM"), findsNothing);
    expect(viewport.rectOfCell(2, 1)!.size, const Size(100.0, 20.0));

    await tester.pumpWidget(
      boxed(
        size,
        grid(format: HourLabelFormat.twentyFourHour, minSlotHeight: 24.0),
      ),
    );
    expect(viewport.rectOfCell(2, 1)!.size, const Size(100.0, 24.0));
  });

  testWidgets("TG2 a timed grid takes drags only when editable, and holds "
      "the blocks its lock choices hold", (tester) async {
    const size = Size(400.0, 800.0);
    CalendarEntry<String> entry(String id, DateTime day, int start, int end) {
      return CalendarEntry<String>(
        id: id,
        day: day,
        startMinute: start,
        endMinute: end,
        title: id,
        color: const Color(0xFF336699),
        payload: id,
      );
    }

    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entry("past", monday, 9 * 60, 10 * 60),
        entry("ended", tuesday, 8 * 60, 9 * 60),
        entry("running", tuesday, 10 * 60, 12 * 60),
        entry("later", tuesday, 14 * 60, 15 * 60),
      ],
    );
    addTearDown(store.dispose);
    // After ended ends, while running runs and before later starts.
    final now = ValueNotifier<DateTime>(DateTime(2026, 4, 21, 11, 7));
    addTearDown(now.dispose);
    TimedGrid<String> grid({
      required bool editable,
      required bool lockPast,
      required bool lockEarlierToday,
    }) {
      return TimedGrid<String>(
        store: store,
        firstDay: monday,
        dayCount: 2,
        selectedDay: tuesday,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenItem: (id) {},
        onCreate: (range) async {},
        editable: editable,
        lockPast: lockPast,
        lockEarlierToday: lockEarlierToday,
        hours: const DayHours(8 * 60, 16 * 60),
      );
    }

    bool dragEnabled() {
      return tester
          .widget<Board<String, CalendarShownEntry<String>>>(
            find.byType(Board<String, CalendarShownEntry<String>>),
          )
          .drag!
          .enabled;
    }

    Finder handleOf(String id) {
      return find.descendant(
        of: find.byKey(blockKey(id)),
        matching: find.byType(BoardDelayedDragHandle),
      );
    }

    const ids = <String>["past", "ended", "running", "later"];
    Map<String, bool> handlesEnabled() {
      return <String, bool>{
        for (final id in ids)
          id: tester.widget<BoardDelayedDragHandle>(handleOf(id)).enabled,
      };
    }

    await pumpBoxed(
      tester,
      size,
      grid(editable: true, lockPast: true, lockEarlierToday: true),
    );
    await tester.pumpAndSettle();
    for (final id in ids) {
      expect(handleOf(id), findsOneWidget, reason: id);
    }
    expect(dragEnabled(), isTrue);
    expect(handlesEnabled(), <String, bool>{
      "past": false,
      "ended": false,
      "running": false,
      "later": true,
    });

    await tester.pumpWidget(
      boxed(
        size,
        grid(editable: true, lockPast: true, lockEarlierToday: false),
      ),
    );
    expect(dragEnabled(), isTrue);
    expect(handlesEnabled(), <String, bool>{
      "past": false,
      "ended": true,
      "running": true,
      "later": true,
    });

    await tester.pumpWidget(
      boxed(
        size,
        grid(editable: true, lockPast: false, lockEarlierToday: true),
      ),
    );
    expect(dragEnabled(), isTrue);
    expect(handlesEnabled(), <String, bool>{
      "past": true,
      "ended": true,
      "running": true,
      "later": true,
    });

    await tester.pumpWidget(
      boxed(
        size,
        grid(editable: false, lockPast: true, lockEarlierToday: true),
      ),
    );
    expect(dragEnabled(), isFalse);
    expect(handlesEnabled(), <String, bool>{
      "past": true,
      "ended": true,
      "running": true,
      "later": true,
    });
  });
}
