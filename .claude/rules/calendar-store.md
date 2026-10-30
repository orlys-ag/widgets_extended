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
  the store's source, a data source or the store itself, has stored it,
  with what the source stored, or fails to its caller; a failed move,
  resize or delete shows the stored entry again.
- **Freshness.** `invalidate` and `refresh` take entries to have changed at
  their source, so the store answers those days anew.
- **The caching store** reads through a data source by days. A read's
  answer is what the source stored on its days when the read was sent, and
  replaces what the store holds there, except what a later read, a write
  confirmed since or a change announced since told it: one clock orders
  reads and writes sent, writes confirmed and changes announced. An entry
  a read forgets that also lay on read days outside it leaves those days
  changed. A failed read leaves its unread days unread, so the next read
  that covers them reads them again, and marks failed each of them that
  no read a show, a retry or a refresh asked for since it was sent
  covers in flight, whether sent or taken over. A mark ends only when a
  read fills the day or a show, a retry or a refresh reads it, which
  each does with a read of its own though a read in flight covers the
  day, since that read may fail as the last one did; a read the store
  sends in the background, such as a prefetch, ends a mark only by
  filling the day, and keeps no failed read from making one. The shown
  range's status follows from its days alone: ready once none is unread,
  failed while an unread one is marked, and loading otherwise, however
  many reads cover its unread days. A retry ends the marks of the shown
  range's days and of the days it is given, and reads them again: the
  marked days with a read of its own, and the rest of their unread and
  changed days as a prefetch does, taking over a read in flight that
  covers the unread ones; as one read where the two spans to read
  overlap or touch.
  A day once read stays read; a changed day keeps showing what the
  store holds while it is read again in the background, at once where the
  shown range holds it and otherwise once a show or a prefetch covers it,
  and a day being changed does not change the load status. A background
  read of the shown range's changed days runs from the first to the last
  of them that no read in flight covers; a shown day changed since the
  read covering it was sent is read once more when that read answers. A
  stream of `CalendarSourceChange`s, when given, is applied as it arrives:
  a put or a removal without a read, a change of days as an `invalidate`,
  and a change of all, or an error on the stream, as an `invalidate` of
  every day. Where a change announced since a write was sent, or a read
  sent since, contradicts the write's answer, the store keeps what it
  holds, and the days of both entries, read or under a read in flight,
  are read again; the read's answer may arrive before the write's or
  after it. A read contradicts the answer where it answers the entry
  otherwise or answers a day the answer covers without the entry, and not
  where it removed the entry from days the answer does not cover. The
  write completes with its data source's answer all the same. A read sent
  later that removed an entry tells nothing of the days it did not cover,
  so an older read's answer of the entry stands, unless a read sent later
  filled a day the answered entry covers, which leaves it unstored and its
  days in the older read to read again. A grid move or resize shows the
  requested entry, pending, until the data source answers; a delete and
  an update show the stored entry pending, as it is stored meanwhile; a
  create shows nothing until the entry is stored.
- **The in-memory store** holds the entries the host gives it, and is
  always loaded. It applies each write within the call, so none is
  pending. It is its entries' source, so `invalidate` and `refresh` do
  nothing.
