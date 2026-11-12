/// CALENDAR EXAMPLE
library;

import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'workspace_calendar_example.dart';

void main() {
  // The zones the time zone sheet lists and a store draws on.
  tz.initializeTimeZones();
  runApp(const WorkspaceCalendarApp());
}

/// The workspace calendar as a whole app.
class WorkspaceCalendarApp extends StatelessWidget {
  const WorkspaceCalendarApp({super.key});
  // defaults:
  // make AM/PM default for hour labels
  // slot length = 30m default
  //
  // change: item type: tasks, risks, requests

  // zoom in/out: slot length must be larger,
  // separate booking slot length from view slot length
  // goal is to declutter zoomed out views that draw too many hour labels and cell slots

  // access calendar from within workspace; Luisa has started some designs
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: WorkspaceCalendarExample());
  }
}
