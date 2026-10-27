---
paths:
  - "lib/calendar/views/*.dart"
  - "lib/calendar/views/**/*.dart"
---

# calendar architecture: views

The contract of the four views and their parts. The conventions every layer follows are in `calendar.md`.

- **Imports**: of Flutter, `package:flutter/widgets.dart` and the libraries
  below it; and the board and sliver_tree modules.
- **Reads.** A view reads entries only through a `CalendarStore`, and every
  colour, text style, motion and icon from `CalendarTheme`. It builds entry
  content and the loading and failure states through the presentation
  layer's builders, and takes its edit limits from the policy layer.
- **No UI of its own.** A view opens no route, dialog or form: it reports a
  tap on an entry, a create range, a move or resize request, and edit and
  delete requests through callbacks.
- **Standalone.** A view takes what it reads through its constructor and the
  inherited theme, never from the composition layer's state, so each view
  can be exposed on its own.
