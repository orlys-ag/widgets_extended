---
paths:
  - "lib/calendar/composition/*.dart"
  - "lib/calendar/composition/**/*.dart"
---

# calendar architecture: composition

The contract of `CalendarView`, `CalendarController`, the header and the default chrome. The conventions every layer follows are in `calendar.md`.

- **Imports**: of Flutter, `package:flutter/material.dart` and the libraries
  below it; and the board and sliver_tree modules.
- **`CalendarView`** offers in its view menu the views its parameters list,
  opening on the one they name, and builds no `Scaffold` or app bar. Its
  configuration is its parameters, and it shows and schedules in its
  store's hours, keeping none of its own.
- **`CalendarController`** is listenable and holds the view, the selected
  day, the visible range and the zoom sizes, which the host sets and listens
  to.
- **The header** (the title, the chevrons, the view menu and the month
  picker) is built in; a parameter hides it and a builder replaces it.
- **The default chrome**: the defaults for the header's menu and tooltips
  and for the loading and failure states, and the theme's Material adapter,
  which resolves a `ThemeExtension` and the host's `ColorScheme` into the
  `CalendarTheme` above the views.
