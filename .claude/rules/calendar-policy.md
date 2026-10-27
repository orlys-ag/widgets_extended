---
paths:
  - "lib/calendar/policy/*.dart"
  - "lib/calendar/policy/**/*.dart"
---

# calendar architecture: policy

The contract of the rules that limit edits. The conventions every layer follows are in `calendar.md`.

- **Imports**: of Flutter, only `package:flutter/foundation.dart`.
- **Stateless answers.** A policy answers from the entries, the times and
  the boundary it is given, and holds no store and no widget.
- **The overlap rule** decides whether two entries share time.
- **Combined policies.** `CalendarEditPolicy.all` allows only what each of
  its policies allows: each answer is the strictest of theirs.
- **The day limit** (`DayLimitPolicy`) limits only the days a gesture's
  range covers, and gives that limit to the policies it is combined with.
- **The edit rules** (`CalendarEditRules`) join a policy with the hours and
  the slot length a calendar schedules in, reading the policy's day limit
  and its answer on overlaps once, when made. They answer whether the hours
  and the policy admit a change's times, where the day limit holds a range,
  and which slot a create takes.
- **The history lock** keeps the past as it is: before its boundary, the
  start of today or the time of day now rounded up to a whole minute, no
  entry moves, resizes or is created. An entry that ends at the boundary or
  before it neither changes nor is deleted; of the times of one that starts
  before it and ends after it, only the end changes, never to the boundary
  or before it, and it is not deleted.
