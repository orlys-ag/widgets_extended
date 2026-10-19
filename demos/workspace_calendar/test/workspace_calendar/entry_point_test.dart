/// The demo's entry point runs the calendar over the default mock. It reads
/// the clock, so only what does not depend on the date is checked.
library;

import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';
import 'package:workspace_calendar/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("P1 the entry point runs the demo on the default mock", (
    tester,
  ) async {
    await tester.pumpWidget(const WorkspaceCalendarApp());
    expect(find.byType(WorkspaceCalendarExample), findsOneWidget);
    final loading = find.byKey(dayListLoadingKey(dateOnly(DateTime.now())));
    await tester.pump(const Duration(milliseconds: 599));
    expect(loading, findsOneWidget);
    // The read lands, and the row leaves over the list's motion.
    await tester.pump(const Duration(milliseconds: 1));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(loading, findsNothing);
  });
}
