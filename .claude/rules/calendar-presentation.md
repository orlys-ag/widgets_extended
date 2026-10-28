---
paths:
  - "lib/calendar/presentation/*.dart"
  - "lib/calendar/presentation/**/*.dart"
---

# calendar architecture: presentation

The contract of the calendar's theme, text and builder signatures. The conventions every layer follows are in `calendar.md`.

- **Imports**: of Flutter, `package:flutter/widgets.dart` and the libraries
  below it.
- **`CalendarThemeData`** is immutable and holds every colour, text style,
  motion duration and curve, and icon the views draw. `CalendarTheme.of`
  reads the nearest `CalendarTheme`, and the theme's built-in values where
  there is none.
- **`CalendarLocalizations`** writes every word the calendar shows or a
  screen reader hears, each member a whole label, sentence or hint, so a
  translation orders the words and forms the plurals; a member that
  writes a time of day takes the view's `HourLabelFormat`.
  `CalendarLocalizations.of` reads the instance the nearest
  `Localizations` loaded, and `DefaultCalendarLocalizations`, US English,
  where it loaded none.
- **Builder signatures** for Week's and Day's blocks, Month's chips,
  Agenda's cards, and the loading and failure states: each takes the
  context and the entry or the state it builds.
- **Day badges**: `CalendarDayBadges` holds the host's kinds of entry, each
  a `CalendarBadgeKind` of a colour and a label, and the kind of each
  entry, which the calendar card's days mark with a dot each.
