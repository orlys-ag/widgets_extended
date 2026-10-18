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
- **The history lock** keeps the past as it is: before its boundary, the
  start of today or the time of day now rounded up to a whole minute, no
  entry moves, resizes or is created. An entry that ends at the boundary or
  before it neither changes nor is deleted; of the times of one that starts
  before it and ends after it, only the end changes, never to the boundary
  or before it, and it is not deleted.
