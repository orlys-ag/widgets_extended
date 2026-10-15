/// Runs the workspace calendar demo, on today's date and the seeded mock
/// API, from this package's directory:
///
///     flutter run
library;

import 'package:flutter/material.dart';

import 'workspace_calendar_example.dart';

void main() {
  runApp(const WorkspaceCalendarApp());
}

/// The workspace calendar as a whole app.
class WorkspaceCalendarApp extends StatelessWidget {
  const WorkspaceCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WorkspaceCalendarExample(),
    );
  }
}
