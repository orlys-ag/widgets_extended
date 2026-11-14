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
  // What about a drag-mode for agenda view that allows re-scheduling through the drag?
  // As you drag, the time would change, but the real issue is how to correctly communicate to the user that
  // the time is changing (since agenda view does not draw all hours) in a visually clear and pleasing way.

  // FEAT: SEPARATE DRAWN SLOT LENGTH FROM BOOKING SLOT LENGTH
  // zoom in/out: slot length must be larger,
  // separate booking slot length from view slot length
  // goal is to declutter zoomed out views that draw too many hour labels and cell slots

  // access calendar from within workspace; Luisa has started some designs
  //
  // remove edit toggle; make behavior = always on
  // card colors: based on lookups that have associated colors
  //  will have picker to select lookup field (which determines color)
  //  FAB should default to today; user can change date
  //
  // Custom color coding per user, saved to device?\
  // Have a list of users to assign tasks, risks, and requests to, etc.?
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WorkspaceCalendarExample(),
    );
  }
}
