---
paths:
  - "lib/scheduling/*.dart"
  - "lib/scheduling/**/*.dart"
  - "test/scheduling/*.dart"
  - "test/scheduling/**/*.dart"
  - "lib/calendar/*.dart"
  - "lib/calendar/**/*.dart"
  - "test/calendar/*.dart"
  - "test/calendar/**/*.dart"
---

# Conventions the scheduling and calendar modules share

Normative for `lib/scheduling/` and `lib/calendar/`, beside each module's own rule, `scheduling.md` and `calendar.md`.

## Conventions

- **Shown helpers.** A top-level function or constant a module's barrel
  shows has `calendar` in its name; any other helper is a static member of
  a class it shows.
- **The public API grows by additions.** A later release adds to a
  module's API so that a host's code still compiles: a member added to a
  `base` class has a default, which breaks only a host subclass that
  declares a member of the same name; a field added to a class is a getter
  or an optional named parameter; no shown type gains a type parameter;
  and no shown enum or sealed class gains a value or a subtype, which a
  host's exhaustive `switch` would miss.
- **Days are civil days.** Every day step and day count in either module
  goes through the dates layer of `lib/scheduling/` and runs on the local
  wall clock or the clock of the zone a time carries: a day is a year, a
  month and a day, a step changes the day, and nothing steps a day by a
  24-hour `Duration`, so a day of 23 or 25 hours at a DST change is one day.
- **The demo's data code stays in the demo.** Neither module holds an item
  type, an item schema or a validation of the demo's JSON envelope, nor a
  JSON API or a mock of one.
- **Tests mirror the layers.** A test of a layer's code sits in the
  matching directory under its module's test directory, and a test that
  needs entries supplies them through the in-memory store.

## Vocabulary

- **Entry**: one `CalendarEntry<T>`, carrying the host's payload `T`.
- **All-day entry**: an entry whose `isAllDay` is true, which covers whole
  local days from the local midnight of its start to that of its end, an
  exclusive end; any other entry is timed, whatever its times.
- **Pending write**: a write in flight on an entry, which marks the entry
  pending and takes no other write on it; `scheduling-store.md` gives what
  each write shows meanwhile.
- **Data source**: the host's asynchronous reads and writes under the
  caching store.
- **Wall minute**: a time on the wall-clock coordinate, as its clock reads
  it: its day number times the minutes of a day, plus its minutes after
  midnight (`CalendarDates.wallMinuteOf`), so the start of a day whose
  clock skips its midnight lies at the minute its clock starts at.
