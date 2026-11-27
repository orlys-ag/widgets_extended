/// The ask a view holds for the stale days it shows: it hears the days its
/// reader reports stale and, after the frame, reads again those it shows.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import '../../scheduling/scheduling.dart';

/// Hears the days a widget's reader reports stale
/// ([CalendarEntryReader.addStaleDaysListener]) and, after the frame that
/// reports them, reads again each run of those the widget shows that the
/// reader answers [CalendarEntryReader.isStale] for, with one
/// [CalendarEntryReader.prefetch] per run.
///
/// [shownDays] answers the days the widget shows, as day numbers
/// ([CalendarDates.dayNumber]), or null while it shows none. A report is
/// clipped to them as it arrives, and to its first and last days the
/// reader then answers stale, and the span held is clipped to the shown
/// days again when the ask runs, so a day the widget no longer shows by
/// then, as one of the days a rebuild after the report moves it off, is
/// not read. A report of no day the widget shows that the reader answers
/// stale, such as one of a store's shown days, which the store reads again
/// itself, schedules nothing.
///
/// The widget makes one in its state's `initState`, calls [listen] with
/// its reader there and in each `didUpdateWidget`, and calls [dispose] in
/// its state's `dispose`.
final class StaleDaysAsk<T> {
  /// An ask for the stale days of the days [shownDays] answers.
  StaleDaysAsk(this.shownDays);

  /// The days the widget shows, both inclusive, as day numbers; null while
  /// it shows none.
  final ({int first, int last})? Function() shownDays;

  /// The reader [listen] last took.
  CalendarEntryReader<T>? _reader;

  /// The stale days heard since the last ask, as day numbers, within the
  /// days [shownDays] answered as each report arrived; null for none.
  int? _first;
  int? _last;

  /// Whether an ask waits for the end of the frame.
  bool _scheduled = false;

  /// Whether [dispose] ran, after which no ask reads.
  bool _disposed = false;

  /// Listens to [reader]'s stale days. Where [reader] is another object
  /// than the reader it listened to, moves its listener there and drops
  /// the stale days it held, which were the other reader's; the same
  /// reader keeps them, so a rebuild between a report and its frame, as
  /// each pinch move's is, loses no ask.
  void listen(CalendarEntryReader<T> reader) {
    final old = _reader;
    if (identical(reader, old)) {
      return;
    }
    old?.removeStaleDaysListener(_handleStale);
    _reader = reader;
    reader.addStaleDaysListener(_handleStale);
    _first = null;
    _last = null;
  }

  /// Removes the listener and ends the asks.
  void dispose() {
    _disposed = true;
    _reader?.removeStaleDaysListener(_handleStale);
    _reader = null;
    _first = null;
    _last = null;
  }

  /// Takes the reported [days] the widget shows, from the first to the
  /// last of them the reader answers stale, into the span held, and where
  /// no ask waits, asks for them after the frame, since a prefetch can
  /// notify the reader's listeners, which no build or layout may, and asks
  /// for that frame. A reported day the reader does not answer stale is
  /// left out, as the reader reports it again once
  /// [CalendarEntryReader.isStale] comes to answer true for it
  /// ([CalendarEntryReader]).
  void _handleStale(CalendarStaleDays days) {
    final reader = _reader;
    final shown = shownDays();
    if (reader == null || shown == null) {
      return;
    }
    var first = shown.first;
    var last = shown.last;
    final reportedFirst = days.first;
    final reportedLast = days.last;
    if (reportedFirst != null && reportedLast != null) {
      first = math.max(first, CalendarDates.dayNumber(reportedFirst));
      last = math.min(last, CalendarDates.dayNumber(reportedLast));
    }
    final zone = reader.zone;
    bool stale(int day) {
      return reader.isStale(CalendarDates.dateOfDayNumber(day, zone: zone));
    }

    while (first <= last && !stale(first)) {
      first++;
    }
    if (first > last) {
      return;
    }
    while (!stale(last)) {
      last--;
    }
    final heldFirst = _first;
    final heldLast = _last;
    _first = heldFirst == null ? first : math.min(heldFirst, first);
    _last = heldLast == null ? last : math.max(heldLast, last);
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _ask();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Reads each maximal run of the held days the widget still shows that
  /// the reader answers stale, and clears the span. Each day is asked of
  /// after the prefetches of the runs before it, so a read one of them
  /// sends counts as it stands.
  void _ask() {
    final reader = _reader;
    final heldFirst = _first;
    final heldLast = _last;
    _first = null;
    _last = null;
    if (_disposed || reader == null || heldFirst == null || heldLast == null) {
      return;
    }
    final shown = shownDays();
    if (shown == null) {
      return;
    }
    final first = math.max(heldFirst, shown.first);
    final last = math.min(heldLast, shown.last);
    final zone = reader.zone;
    int? runFirst;
    for (var day = first; day <= last; day++) {
      if (reader.isStale(CalendarDates.dateOfDayNumber(day, zone: zone))) {
        runFirst ??= day;
      } else if (runFirst != null) {
        reader.prefetch(
          CalendarDates.dateOfDayNumber(runFirst, zone: zone),
          CalendarDates.dateOfDayNumber(day - 1, zone: zone),
        );
        runFirst = null;
      }
    }
    if (runFirst != null) {
      reader.prefetch(
        CalendarDates.dateOfDayNumber(runFirst, zone: zone),
        CalendarDates.dateOfDayNumber(last, zone: zone),
      );
    }
  }
}
