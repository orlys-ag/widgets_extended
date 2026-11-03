---
paths:
  - "lib/scheduling/entries/*.dart"
  - "lib/scheduling/entries/**/*.dart"
---

# scheduling architecture: entries

The contract of `CalendarEntry<T>`, `CalendarCreateRange` and the data-source contract. The layer's imports are in `scheduling.md`'s table, and the conventions every layer follows in `scheduling.md` and `shared-calendar-conventions.md`.

- **`CalendarEntry<T>`** is immutable: an id, its start and end, whether
  it is all-day, a title, a colour and a payload of the host's type `T`;
  its constructor throws an `ArgumentError` for a time it does not take, in
  every build. An id names one entry in a store.
- **`CalendarCreateRange`** is the range of time a create gesture picks,
  all-day or timed; its constructor throws an `ArgumentError`, in every
  build, naming the first of `CalendarEntry`'s time rules its times break,
  in `CalendarEntry`'s order, so an entry of its times constructs.
- **The data-source contract**: asynchronous reads of the entries covering a
  range of days, and writes that create, replace or delete one entry. A read
  or write completes with what it stored, or fails with an error.
- **Source changes**: a `CalendarSourceChange` is a change the source
  announces, an entry put or removed, a range of days changed, or every
  entry changed. A stream of them delivers them in the order the source
  made them, with an every-entry change after any stretch in which it may
  have missed one. The stream is separate from the data source, so a
  source without one still serves.
