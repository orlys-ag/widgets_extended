---
paths:
  - "lib/calendar/presentation/*.dart"
  - "lib/calendar/presentation/**/*.dart"
---

# calendar architecture: presentation

The contract of the calendar's theme and builder signatures. The conventions every layer follows are in `calendar.md`.

- **Imports**: of Flutter, `package:flutter/widgets.dart` and the libraries
  below it.
- **`CalendarThemeData`** is immutable and holds every colour, text style,
  motion duration and curve, and icon the views draw. `CalendarTheme.of`
  reads the nearest `CalendarTheme`, and the theme's built-in values where
  there is none.
- **Builder signatures** for Week's and Day's blocks, Month's chips,
  Agenda's cards, and the loading and failure states: each takes the
  context and the entry or the state it builds.
