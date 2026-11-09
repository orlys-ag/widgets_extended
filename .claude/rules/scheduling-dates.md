---
paths:
  - "lib/scheduling/dates/*.dart"
  - "lib/scheduling/dates/**/*.dart"
---

# scheduling architecture: dates

The contract of the dates layer. The layer's imports are in `scheduling.md`'s table, and the conventions every layer follows in `scheduling.md` and `shared-calendar-conventions.md`.

- **Civil dates.** A date is a `DateTime` at local midnight, or the first
  instant a zone's clock reads that date, compared by its year, month and
  day. A day step builds the date from the stepped day; a day number counts
  the days from the epoch to the UTC date of the same year, month and day,
  so each civil day has one number whatever its length.
- **Values.** Month grids (`CalendarMonthGrid`), weekday sets (the first
  weekday and the weekdays shown, in order) and day hours (the minutes a
  calendar shows and schedules in) are immutable values, and
  `CalendarHourLabelFormat` names the clock a time of day is written on.
- **Helpers.** `CalendarDates` offers the layer's helpers as static members
  that hold their bodies. A helper the barrel does not offer is internal: a
  top-level declaration the barrel does not show, or a private static of
  `CalendarDates`.
