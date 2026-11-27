---
paths:
  - "lib/calendar/views/*.dart"
  - "lib/calendar/views/**/*.dart"
---

# calendar architecture: views

The contract of the four views and their parts. The conventions every layer follows are in `calendar.md` and `shared-calendar-conventions.md`.

- **Imports**: of Flutter, `package:flutter/widgets.dart` and the libraries
  below it; the scheduling module, through
  `lib/scheduling/scheduling.dart`; and the board and sliver_tree modules.
- **Reads.** A view reads entries only through a `CalendarStore`, every
  colour, text style, motion and icon from `CalendarTheme`, and every word
  from `CalendarLocalizations`. It builds entry content and the loading and
  failure states through the presentation layer's builders, and takes its
  edit limits from the scheduling module's `CalendarEditPolicy` and
  `CalendarEditRules`.
- **Reader calls.** A view calls a reader method that can notify, such as
  `prefetch` or `retry`, from a gesture or after the frame, never during
  build or layout. A view asks its reader for the days it shows only after
  the frame; the timed grid and the month board ask after the frame that
  brings them those days, a new reader or a new zone, and judge their
  loading and failure states from those days alone.
- **No UI of its own.** A view opens no route, dialog or form: it reports a
  tap on an entry, a create range, a move or resize request, and edit and
  delete requests through callbacks.
- **Standalone.** A view takes what it reads through its constructor and the
  inherited theme and localizations, never from the composition layer's
  state, so each view can be exposed on its own.
