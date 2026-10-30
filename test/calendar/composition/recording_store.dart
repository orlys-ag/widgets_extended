/// The store the composition tests hand a calendar to see the ranges it
/// asks for: an in-memory store whose `show` records the ask and notifies.
library;

import 'package:flutter/scheduler.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';

typedef DayRange = ({DateTime first, DateTime last});

/// An in-memory store that records each range it is asked to show and
/// the scheduler's phase at the ask, and notifies within each call, as a
/// caching store does for a range other than the one it shows; a calendar
/// asks again only for a range that moved.
final class RecordingStore extends MemoryCalendarStore<String> {
  RecordingStore({super.entries, super.hours});

  final List<DayRange> shows = <DayRange>[];
  final List<SchedulerPhase> phases = <SchedulerPhase>[];

  @override
  void show(DateTime first, DateTime last) {
    shows.add((first: first, last: last));
    phases.add(SchedulerBinding.instance.schedulerPhase);
    notifyListeners();
  }
}
