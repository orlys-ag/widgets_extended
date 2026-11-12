---
paths:
  - "lib/scheduling/policy/*.dart"
  - "lib/scheduling/policy/**/*.dart"
---

# scheduling architecture: policy

The contract of the rules that limit edits. The layer's imports are in `scheduling.md`'s table, and the conventions every layer follows in `scheduling.md` and `shared-calendar-conventions.md`.

- **Stateless answers.** A policy answers from the entries, the times and
  the boundary it is given, and holds no store and no widget.
- **The overlap rule** decides whether two entries share time. It is the
  statics of `NoOverlapsPolicy`: `timesOverlap`, `rangeSharesTime` and
  `entriesShareTime`.
- **Combined policies.** `CalendarEditPolicy.all` allows only what each of
  its policies allows: each answer is the strictest of theirs.
- **Single-purpose policies.** `DayLimitPolicy` limits only the days a
  gesture's range covers, and `NoOverlapsPolicy` forbids only overlaps;
  each gives its limit to the policies it is combined with.
- **The edit rules** (`CalendarEditRules`) join a policy with the hours and
  the slot length a calendar schedules in, reading the policy's day limit
  and its answer on overlaps once, when made. They answer whether the hours
  and the policy admit a change's times, where the day limit holds a range,
  and which slot a create takes.
- **The schedule check** (`CalendarScheduleCheck`) decides nothing
  itself: every rule it reports is an answer of the edit rules or their
  policy, and it names which answer refused, as a
  `CalendarScheduleProblem`, a class hierarchy the module grows.
- **The history lock** keeps the past as it is: before its boundary, the
  start of today or the time of day now rounded up to a whole minute, no
  entry moves, resizes or is created. An entry that ends at the boundary or
  before it neither changes, in its times or its kind, nor is deleted; of
  one that starts before it and ends after it, only the end changes, never
  to the boundary or before it, its kind stays, and it is not deleted.
