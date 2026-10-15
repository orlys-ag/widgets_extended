/// The demo's entry point runs the calendar over the default mock. It reads
/// the clock, so only what does not depend on the date is checked.
library;

import 'package:workspace_calendar/workspace_calendar_example.dart';
import 'package:workspace_calendar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("P1 the entry point runs the demo on the default mock", (
    tester,
  ) async {
    await tester.pumpWidget(const WorkspaceCalendarApp());
    expect(find.byType(WorkspaceCalendarExample), findsOneWidget);
    final loading = find.byKey(const ValueKey<String>("day-list-loading"));
    await tester.pump(const Duration(milliseconds: 599));
    expect(loading, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(loading, findsNothing);
  });
}
