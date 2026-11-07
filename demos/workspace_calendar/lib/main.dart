/// CALENDAR EXAMPLE
library;

import 'package:flutter/material.dart';

import 'workspace_calendar_example.dart';

void main() {
  runApp(const WorkspaceCalendarApp());
}

/// The workspace calendar as a whole app.
class WorkspaceCalendarApp extends StatelessWidget {
  const WorkspaceCalendarApp({super.key});
  // Missing features:
  // - Handle multi-day with indicator(s), etc.
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WorkspaceCalendarExample(),
    );
  }
}
