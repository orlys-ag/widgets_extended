---
paths:
  - "lib/calendar/dates/*.dart"
  - "lib/calendar/dates/**/*.dart"
---

# calendar architecture: dates

The contract of the dates layer. The conventions every layer follows are in `calendar.md`.

- **Imports**: of Flutter, only `package:flutter/foundation.dart`; of the
  module, nothing outside this layer.
- **Civil dates.** A date is a `DateTime` at local midnight, compared by its
  year, month and day. A day step builds the date from the stepped day; a
  day number counts the days from the epoch to the UTC date of the same
  year, month and day, so each civil day has one number whatever its length.
- **Values.** Month grids, weekday sets (the first weekday and the weekdays
  shown, in order) and day hours (the minutes a calendar shows and
  schedules in) are immutable values.
