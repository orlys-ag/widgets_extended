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
- **Hours.** The store holds the calendar's one copy of its hours, which
  its writes must lie in; a set of other hours notifies.
- **Writes.** An entry has one write in flight at most, and a write on an
  entry that has one sends nothing and fails. Every write completes once
  it is stored, or fails to its caller; a failed move, resize or delete
  shows the stored entry again.
- **Freshness.** `invalidate` and `refresh` take entries to have changed at
  their source, so the store answers those days anew.
- **The caching store** reads through a data source by days. A read's
  answer is what the source stored on its days when the read was sent, and
  replaces what the store holds there, except what a later read, a write
  confirmed since or a change announced since told it: one clock orders
  reads and writes sent, writes confirmed and changes announced. An entry
  a read forgets that also lay on read days outside it leaves those days
  changed. A failed read leaves its unread days unread, so the next read
  that covers them reads them again; a failed read the shown range waits
  on leaves it loading while another read in flight covers its unread
  days. A day once read stays read; a changed day keeps showing what the
  store holds while it is read again in the background, at once where the
  shown range holds it and otherwise once a show or a prefetch covers it,
  and the load status does not change. No read is sent for a changed day
  a read in flight covers; one more follows once that read answers. A
  stream of `CalendarSourceChange`s, when given, is applied as it arrives:
  a put or a removal without a read, a change of days as an `invalidate`,
  and a change of all, or an error on the stream, as an `invalidate` of
  every day. A write's answer that a change announced or a read answered
  since the write was sent contradicts is not stored; the entry's days are
  read again. A grid move or resize shows the requested entry, pending,
  until the data source answers; a delete and an update show the stored
  entry pending; a create shows nothing until the entry is stored.
- **The in-memory store** holds the entries the host gives it, and is
  always loaded. It applies each write within the call, so none is
  pending. It is its entries' source, so `invalidate` and `refresh` do
  nothing.
