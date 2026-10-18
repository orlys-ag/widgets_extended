---
paths:
  - "lib/calendar/entries/*.dart"
  - "lib/calendar/entries/**/*.dart"
---

# calendar architecture: entries

The contract of `CalendarEntry<T>` and the data-source contract. The conventions every layer follows are in `calendar.md`.

- **Imports**: `dart:ui` for `Color`, and of Flutter only
  `package:flutter/foundation.dart`.
- **`CalendarEntry<T>`** is immutable: an id, its time, a title, a colour,
  and a payload of the host's type `T`. An id names one entry in a store.
- **The data-source contract**: asynchronous reads of the entries covering a
  range of days, and writes that create, replace or delete one entry. A read
  or write completes with what it stored, or fails with an error.
