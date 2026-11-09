---
paths:
  - "lib/scheduling/*.dart"
  - "lib/scheduling/**/*.dart"
  - "test/scheduling/*.dart"
  - "test/scheduling/**/*.dart"
---

# scheduling architecture

Normative for `lib/scheduling/`, the scheduling module: the experimental scheduling core the calendar builds on. This rule holds the module's layers and its own conventions; the conventions it shares with the calendar are in `shared-calendar-conventions.md`, and each layer's contract is in the rule that names its directory:

| Layer | Directory | Rule | Imports | Holds |
|---|---|---|---|---|
| Dates | `lib/scheduling/dates/` | `scheduling-dates.md` | Of Flutter, only `package:flutter/foundation.dart`; of packages, `calendar_dates.dart` alone imports `package:timezone/timezone.dart` and re-exports its `Location` and `TZDateTime` to the layers above; of the module, nothing outside this layer | `CalendarDates`, day numbers, wall minutes, month grids, weekday sets, day hours and the hour label format |
| Entries | `lib/scheduling/entries/` | `scheduling-entries.md` | `dart:ui` for `Color`, and of Flutter only `package:flutter/foundation.dart` | `CalendarEntry<T>`, `CalendarCreateRange` and the data-source contract |
| Policy | `lib/scheduling/policy/` | `scheduling-policy.md` | Of Flutter, only `package:flutter/foundation.dart` | The overlap rule, the history lock, `CalendarEditPolicy`, `CalendarEditRules` |
| Store | `lib/scheduling/store/` | `scheduling-store.md` | Of Flutter, only `package:flutter/foundation.dart` | `CalendarStore` and its two stores |

## Conventions of the module

- **Imports run up the table.** A layer's files import the module's files
  only from their own layer and the layers above it in the table, by
  relative paths, and nothing under `lib/calendar/`, `lib/board/`,
  `lib/sliver_tree/` or `lib/sectioned_sliver_list/`, nor
  `lib/widgets_extended.dart`.
- **No user-facing words.** The module holds no user-facing words: a
  `toString` or an error message is for developers, and a module that
  builds on it owns its localizations.
- **One barrel.** `lib/scheduling/scheduling.dart` is the module's public
  surface and exports through explicit `show` clauses; anything it does not
  show is internal, whatever its name. A static member it offers holds its
  body rather than forwarding to a top-level function.
- **The public API grows only by additions,** made as
  `shared-calendar-conventions.md` states. Each class the barrel shows says
  how a host builds on it: `CalendarStore`, its two stores and
  `CalendarEditPolicy` are `base`, `CalendarDataSource` is an `interface`,
  and every other class is `final` or `sealed`. A vocabulary that will
  grow, such as item kinds, refusal reasons, resource kinds or recurrence
  rules, is a class hierarchy later code extends, never an enum or a sealed
  class, which can never gain a value or a subtype. A new ability of a data
  source is a new interface. Package timezone's `Location` is the one foreign
  type on the public surface, as a store's zone; no barrel shows it, so a
  host imports `package:timezone` itself.
- **The core's tests run on the core alone.** No file under
  `test/scheduling/dates/`, `entries/`, `policy/` or `store/`, nor
  `test/scheduling/dst_days.dart` or `test/scheduling/class_source.dart`,
  imports anything of `lib/calendar/`, the package barrel, `lib/board/`,
  `lib/sliver_tree/`, `lib/sectioned_sliver_list/` or a file under
  `test/calendar/`.
- **Code enters the module** only once it follows these conventions and
  `shared-calendar-conventions.md`'s rule on the demo's data code.
