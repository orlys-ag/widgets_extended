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

/// Whether the range from [start] to [end] shares time with [other]: never
/// for an all-day [other], which shares time with nothing, and otherwise
/// where their instants meet ([timesOverlap]).
bool rangeSharesTime<T>(DateTime start, DateTime end, CalendarEntry<T> other) {
  if (other.isAllDay) {
    return false;
  }
  return timesOverlap(start, end, other.start, other.end);
}

/// Whether [a] and [b] share time: never where either is all-day, and
/// otherwise where their instants meet.
bool entriesShareTime<T>(CalendarEntry<T> a, CalendarEntry<T> b) {
  if (a.isAllDay) {
    return false;
  }
  return rangeSharesTime(a.start, a.end, b);
}
