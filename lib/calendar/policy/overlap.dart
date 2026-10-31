/// The overlap rule: whether two ranges of time, or two entries, share
/// time.
library;

import '../entries/calendar_entry.dart';

/// Whether the half-open ranges `[aStart, aEnd)` and `[bStart, bEnd)` of
/// instants meet.
bool timesOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) {
  return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
}

/// Whether the timed range from [start] to [end] shares time with [other]:
/// never for an all-day [other] ([CalendarEntry.isAllDay]), which shares
/// time with nothing, and otherwise where their instants meet
/// ([timesOverlap]). The range is read as timed whatever its times, from a
/// day start to a day start too, so a caller passes only a timed range: an
/// all-day one shares time with nothing ([entriesShareTime]).
bool rangeSharesTime<T>(DateTime start, DateTime end, CalendarEntry<T> other) {
  if (other.isAllDay) {
    return false;
  }
  return timesOverlap(start, end, other.start, other.end);
}

/// Whether [a] and [b] share time: never where either is all-day
/// ([CalendarEntry.isAllDay]), and otherwise where their instants meet.
bool entriesShareTime<T>(CalendarEntry<T> a, CalendarEntry<T> b) {
  if (a.isAllDay) {
    return false;
  }
  return rangeSharesTime(a.start, a.end, b);
}
