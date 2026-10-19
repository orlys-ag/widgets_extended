/// The overlap rule: whether two entry times share time.
library;

import '../entries/calendar_entry.dart';

/// Whether [a] and [b] share time: their days meet and their half-open
/// minute ranges `[start, end)` meet.
bool timesOverlap(CalendarEntryTime a, CalendarEntryTime b) {
  final daysMeet =
      a.firstDay < b.firstDay + b.dayCount &&
      b.firstDay < a.firstDay + a.dayCount;
  final minutesMeet = a.start < b.end && b.start < a.end;
  return daysMeet && minutesMeet;
}
