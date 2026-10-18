---
paths:
  - "lib/calendar/store/*.dart"
  - "lib/calendar/store/**/*.dart"
---

# calendar architecture: store

The contract of `CalendarStore` and its two stores. The conventions every layer follows are in `calendar.md`.

- **Imports**: of Flutter, only `package:flutter/foundation.dart`.
- **`CalendarStore`** is listenable, and answers the entries covering a
  range, the load state of the range the calendar shows, and writes.
- **Writes.** An entry has one write in flight at most, and a write on an
  entry that has one sends nothing and fails. A grid move or resize shows
  the requested entry, pending, until the data source answers; a delete and
  an update show the stored entry pending; a create shows nothing until the
  entry is stored. A move, resize or delete reports its failure through the
  store's write-failure callback, the stored entry showing again; an update
  or a create completes with the stored entry or fails to its caller.
- **The caching store** reads through a data source by days. A day once read
  changes only by a confirmed write: a later read fills only the days not
  read yet. A failed read leaves its days unread, so the next read that
  covers them reads them again.
- **The in-memory store** holds the entries the host gives it, and is
  always loaded.
