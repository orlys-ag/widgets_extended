---
paths:
  - "lib/calendar/*.dart"
  - "lib/calendar/**/*.dart"
  - "test/calendar/*.dart"
  - "test/calendar/**/*.dart"
---

# calendar architecture

Normative for `lib/calendar/`, the calendar module: `CalendarView`, a calendar of Agenda, Day, Week and Month views on the board and sliver_tree modules. This rule holds the module's layers and the conventions every layer follows; each layer's contract is in the rule that names its directory:

| Layer | Directory | Rule | Holds |
|---|---|---|---|
| Dates | `lib/calendar/dates/` | `calendar-dates.md` | Civil dates on the local wall clock: day numbers, month grids, weekday sets, day hours |
| Entries | `lib/calendar/entries/` | `calendar-entries.md` | `CalendarEntry<T>` and the data-source contract |
| Policy | `lib/calendar/policy/` | `calendar-policy.md` | The rules that limit edits: the overlap rule, the history lock, `CalendarEditPolicy`, `CalendarEditRules` |
| Store | `lib/calendar/store/` | `calendar-store.md` | `CalendarStore`, the in-memory store, and the caching store over a data source |
| Presentation | `lib/calendar/presentation/` | `calendar-presentation.md` | `CalendarThemeData`, `CalendarTheme`, `CalendarLocalizations`, the builder signatures, and the day badges' kinds |
| Views | `lib/calendar/views/` | `calendar-views.md` | Week's and Day's timed grid, the month board, Agenda's day list, the week strip, the month picker, day cells, entry cards, the pinch |
| Composition | `lib/calendar/composition/` | `calendar-composition.md` | `CalendarView`, `CalendarController`, the header, view switching, the folding calendar card, the default chrome |

## Conventions that cut across every layer

- **Imports run up the table.** A layer's files import the module's files
  only from their own layer and the layers above it in the table. A type
  that several layers read sits in the earliest of them. The module reaches
  the board and sliver_tree modules through their barrels,
  `lib/board/board.dart` and `lib/sliver_tree/sliver_tree.dart`, never
  through the package barrel, `lib/widgets_extended.dart`.
- **Material in composition only.** No file under `lib/calendar/` outside
  `lib/calendar/composition/` imports `package:flutter/material.dart`, or a
  library that exports it; the other layers build on the widgets layer.
- **The demo's own code stays in the demo.** The module holds nothing that
  `demos/workspace_calendar/` owns: no item type, item schema or validation
  of the demo's JSON envelope, no JSON API or mock of one, no item form, no
  Harbor colour value, and no settings sheet, calendar bar or app bar. Code
  enters `lib/calendar/` only once it follows this rule and the two above.
- **Days are civil days.** Every day step and day count goes through the
  dates layer and runs on the local wall clock: a day is a year, a month and
  a day, a step changes the day, and nothing steps a day by a 24-hour
  `Duration`, so a day of 23 or 25 hours at a DST change is one day.
- **One barrel.** `lib/calendar/calendar.dart` is the module's public
  surface and exports through explicit `show` clauses; anything it does not
  show is internal, whatever its name.
- **The public API grows by additions.** Each class the barrel shows says
  how a host builds on it: one a host extends (`CalendarController`,
  `CalendarStore` and its two stores, `CalendarEditPolicy`,
  `CalendarLocalizations` and its English default) is `base`,
  `CalendarDataSource` is an `interface`, the widgets are neither, and
  every other class is `final` or `sealed`. A later release adds to the
  API without breaking a host: a member added to a `base` class has a
  default, a field added to a class is a getter or an optional named
  parameter, a new ability of a data source is a new interface, no shown
  type gains a type parameter, and no shown enum or sealed class gains a
  value or a subtype, which a host's exhaustive `switch` would miss, so a
  new arrangement of a view is a parameter, not a new `CalendarViewKind`.
- **Tests mirror the layers.** A test of a layer's code sits in the
  matching directory under `test/calendar/`, and a test that needs entries
  supplies them through the in-memory store.

## Vocabulary

- **Entry**: one `CalendarEntry<T>`, carrying the host's payload `T`.
- **All-day entry**: an entry that covers whole local days, from a midnight
  to a midnight; any other entry is timed.
- **Piece**: the part of a timed entry on one day, which Week and Day draw
  as one block.
- **Slot**: the step the timed grid's rows and the gestures snap to.
- **Lane**: the board's overlap lanes, in which entries sharing a day's time
  sit side by side.
- **Pending write**: a write in flight on an entry, which marks the entry
  pending and takes no other write on it; `calendar-store.md` gives what
  each write shows meanwhile.
- **Data source**: the host's asynchronous reads and writes under the
  caching store.
- **Calendar card**: Agenda's and Day's month under the header, which folds
  into the week strip.
