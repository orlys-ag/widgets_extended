---
paths:
  - "lib/calendar/*.dart"
  - "lib/calendar/**/*.dart"
  - "test/calendar/*.dart"
  - "test/calendar/**/*.dart"
---

# calendar architecture

Normative for `lib/calendar/`, the calendar module: `CalendarView`, a calendar of Agenda, Day, Week and Month views on the scheduling, board and sliver_tree modules. This rule holds the module's layers and its own conventions, those it shares with the scheduling module being in `shared-calendar-conventions.md`; each layer's contract is in the rule that names its directory:

| Layer | Directory | Rule | Holds |
|---|---|---|---|
| Presentation | `lib/calendar/presentation/` | `calendar-presentation.md` | `CalendarThemeData`, `CalendarTheme`, `CalendarLocalizations`, the builder signatures, and the day badges' kinds |
| Views | `lib/calendar/views/` | `calendar-views.md` | Week's and Day's timed grid, the month board, Agenda's day list, the week strip, the month picker, day cells, entry cards, the pinch |
| Composition | `lib/calendar/composition/` | `calendar-composition.md` | `CalendarView`, `CalendarController`, the header, view switching, the folding calendar card, the default chrome, the zone panel |

## Conventions that cut across every layer

- **Imports run up the table.** A layer's files import the module's files
  only from their own layer and the layers above it in the table. A type
  that several layers read sits in the earliest of them. The module
  reaches `lib/scheduling/` only through its barrel,
  `lib/scheduling/scheduling.dart`, and the board and sliver_tree modules
  through theirs, `lib/board/board.dart` and
  `lib/sliver_tree/sliver_tree.dart`, never through the package barrel,
  `lib/widgets_extended.dart`.
- **Material in composition only.** No file under `lib/calendar/` outside
  `lib/calendar/composition/` imports `package:flutter/material.dart`, or a
  library that exports it; the other layers build on the widgets layer.
- **The demo's own code stays in the demo.** The module holds nothing that
  `demos/workspace_calendar/` owns: no item form, no Harbor colour value,
  and no settings sheet, calendar bar or app bar. Code enters
  `lib/calendar/` only once it follows this rule, the two above and
  `shared-calendar-conventions.md`'s rule on the demo's data code.
- **One barrel.** `lib/calendar/calendar.dart` is the module's public
  surface and exports through explicit `show` clauses; anything it does not
  show is internal, whatever its name. It shows every name the scheduling
  barrel shows.
- **The public API grows by additions.** Each class the barrel shows of
  the module's own files says how a host builds on it: one a host extends
  (`CalendarController`, `CalendarLocalizations` and its English default)
  is `base`, the widgets are neither, and every other class the module
  declares is `final` or `sealed`. The function type of a builder or
  callback gains no parameter, so what a release adds to its input is a
  field of the details class it takes, or else a new callback; and a new
  arrangement of a view is a parameter, not a new `CalendarViewKind`.
- **Shared with the scheduling module.** The naming of shown helpers, the
  general rules of API growth, civil days, the demo's data code and tests
  mirroring the layers are conventions `shared-calendar-conventions.md`
  states for both modules.

## Vocabulary

Entry, All-day entry, Pending write, Data source and Wall minute are in
`shared-calendar-conventions.md`.

- **Piece**: the part of a timed entry on one day, which Week and Day draw
  as one block.
- **Slot**: the step the timed grid's rows and the gestures snap to.
- **Lane**: the board's overlap lanes, in which entries sharing a day's time
  sit side by side.
- **Calendar card**: Agenda's and Day's month under the header, which folds
  into the week strip.
