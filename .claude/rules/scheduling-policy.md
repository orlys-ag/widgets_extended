---
paths:
  - "lib/scheduling/policy/*.dart"
  - "lib/scheduling/policy/**/*.dart"
---

# scheduling architecture: policy

The contract of the rules that limit edits. The layer's imports are in `scheduling.md`'s table, and the conventions every layer follows in `scheduling.md` and `shared-calendar-conventions.md`.

- **Stateless answers.** A policy answers from the entries, the times and
  the boundary it is given, and holds no store and no widget.
- **The change question.** `refusalsOf` answers a change of a stored
  entry, a `CalendarChange`, with the problems that refuse it, empty where
  it admits it, and is never asked of a create; every ask in the module
  goes to it, and `admitsChange`, a host's convenience that a policy does
  not override and the module never asks, answers whether it is empty; a
  built-in policy answers const lists.
- **The overlap rule** decides whether two entries share time. It is the
  statics of `NoOverlapsPolicy`: `timesOverlap`, `rangeSharesTime` and
  `entriesShareTime`.
- **Combined policies.** `CalendarEditPolicy.all` allows only what each of
  its policies allows: its refusals of a change are those of the first of
  its policies that refuses, and each other answer is the strictest of
  theirs.
- **Single-purpose policies.** `DayLimitPolicy` limits only the days a
  gesture's range covers, and `NoOverlapsPolicy` forbids only overlaps;
  each gives its limit to the policies it is combined with.
- **The edit rules** (`CalendarEditRules`) join a policy with the hours and
  the slot length a calendar schedules in, reading the policy's day limit
  and its answer on overlaps once, when made. They answer whether the hours
  and the policy admit a change's times, where the day limit holds a range,
  and which slot a create takes.
- **The schedule check** (`CalendarScheduleCheck`) decides nothing
  itself: it reports a policy's refusals of a stored entry's change as
  given, and for every other rule names which answer of the edit rules or
  their policy refused, as a `CalendarScheduleProblem`, a class hierarchy
  the module and a host grow.
- **The history lock** keeps the past as it is: before its boundary, the
  start of today or the time of day now rounded up to a whole minute, no
  entry moves, resizes or is created. An entry that ends at the boundary or
  before it neither changes, in its times or its kind, nor is deleted; of
  one that starts before it and ends after it, only the end changes, never
  to the boundary or before it, its kind stays, and it is not deleted. Its
  refusals of a change name why: for an entry from the boundary on, a start
  before it is a past day where it lies before today or the boundary lies
  on a later day than today, and before the earliest start otherwise; for
  one in progress, a moved start, or else a changed kind, each followed by
  an end in the past where the end is at the boundary or before it, which
  alone refuses a change that keeps both; and for one that has ended, any
  change is locked.
