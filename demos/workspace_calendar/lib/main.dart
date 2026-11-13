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
  //
  // remove edit toggle; make behavior = always on
  // adjust padding of calendar cards
  // card colors: based on lookups that have associated colors
  //  will have picker to select lookup field (which determines color)
  //  FAB should default to today; user can change date
  //
  // Custom color coding per user, saved to device?
  // Have a list of users to assign tasks, risks, and requests to, etc.?
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WorkspaceCalendarExample(),
    );
  }
}
