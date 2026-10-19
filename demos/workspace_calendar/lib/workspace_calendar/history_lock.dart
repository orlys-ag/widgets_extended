/// The history lock the settings choose: what may change of the items
/// before its boundary, the start of today, or the current minute of it.
library;

import 'package:flutter/foundation.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

import 'calendar_schema.dart';
import 'calendar_settings.dart';

/// How the history lock holds an item.
enum ItemHold {
  /// The item starts at the boundary or after it: it changes freely, but
  /// never to start before the boundary.
  free,

  /// The item starts before the boundary and ends after it: only its end
  /// changes, never to the boundary or before it, and it is not deleted.
  started,

  /// The item ends at the boundary or before it: nothing of it changes,
  /// and it is not deleted.
  locked,
}

/// What [CalendarSettings.lockPast] and [CalendarSettings.lockEarlierToday]
/// keep as it is: the items, and the time for new ones, before a boundary
/// counted in minutes, a [dayNumber] times [minutesPerDay] plus the
/// minutes into that day.
@immutable
class HistoryLock {
  const HistoryLock._(this.boundary);

  /// No lock: every item is free.
  static const HistoryLock none = HistoryLock._(null);

  /// The lock [settings] choose on [today] at [now]: none without
  /// [CalendarSettings.lockPast]; with it, the start of [today], or with
  /// [CalendarSettings.lockEarlierToday] too, [now]'s time of day on
  /// [today], rounded up to a whole minute, since a minute any part of
  /// which has passed is past.
  factory HistoryLock.of(
    CalendarSettings settings, {
    required DateTime today,
    required DateTime now,
  }) {
    if (!settings.lockPast) {
      return none;
    }
    var minute = 0;
    if (settings.lockEarlierToday) {
      final into = Duration(
        seconds: now.second,
        milliseconds: now.millisecond,
        microseconds: now.microsecond,
      );
      minute = now.hour * 60 + now.minute + (into > Duration.zero ? 1 : 0);
    }
    return HistoryLock._(dayNumber(today) * minutesPerDay + minute);
  }

  /// The minute before which items are held, or null without a lock.
  final int? boundary;

  static int _startOf(ItemShape shape) {
    return shape.firstDay * minutesPerDay + shape.start;
  }

  static int _endOf(ItemShape shape) {
    return (shape.firstDay + shape.dayCount - 1) * minutesPerDay + shape.end;
  }

  ItemHold holdOf(ItemShape shape) {
    final boundary = this.boundary;
    if (boundary == null || _startOf(shape) >= boundary) {
      return ItemHold.free;
    }
    return _endOf(shape) > boundary ? ItemHold.started : ItemHold.locked;
  }

  /// Whether the item [from] may become [to]: a free one may not start
  /// before the boundary, a started one keeps its start and ends after the
  /// boundary, and a locked one keeps its times.
  bool admits(ItemShape from, ItemShape to) {
    final boundary = this.boundary;
    if (boundary == null) {
      return true;
    }
    switch (holdOf(from)) {
      case ItemHold.free:
        return _startOf(to) >= boundary;
      case ItemHold.started:
        return _startOf(to) == _startOf(from) && _endOf(to) > boundary;
      case ItemHold.locked:
        return _startOf(to) == _startOf(from) && _endOf(to) == _endOf(from);
    }
  }

  /// Whether a new item may start on [day] at [minute].
  bool admitsStart(DateTime day, int minute) {
    final boundary = this.boundary;
    return boundary == null ||
        dayNumber(day) * minutesPerDay + minute >= boundary;
  }

  /// The first minute of [day] on the [minutesPerSlot] grid a new item may
  /// start at: 0 on a day after the boundary's, and [minutesPerDay] on one
  /// before it, where none may.
  int earliestStartOn(DateTime day) {
    final boundary = this.boundary;
    if (boundary == null) {
      return 0;
    }
    final into = boundary - dayNumber(day) * minutesPerDay;
    if (into <= 0) {
      return 0;
    }
    if (into >= minutesPerDay) {
      return minutesPerDay;
    }
    return (into + minutesPerSlot - 1) ~/ minutesPerSlot * minutesPerSlot;
  }

  /// The item form's errors for [to], a change of the stored [from] or,
  /// where [from] is null, a new item, which the lock refuses, keyed as
  /// `validateItemJson` keys them; empty where the lock admits it.
  Map<String, String> errorsOf(ItemShape? from, ItemShape to) {
    final boundary = this.boundary;
    if (boundary == null || (from != null && admits(from, to))) {
      return const <String, String>{};
    }
    if (from == null || holdOf(from) == ItemHold.free) {
      if (_startOf(to) >= boundary) {
        return const <String, String>{};
      }
      if (to.firstDay < boundary ~/ minutesPerDay) {
        return const <String, String>{"day": "Past days are locked."};
      }
      return const <String, String>{
        "startMinute": "The start can't be in the past.",
      };
    }
    if (holdOf(from) == ItemHold.locked) {
      return const <String, String>{"day": "Past items are locked."};
    }
    return <String, String>{
      if (_startOf(to) != _startOf(from))
        "startMinute": "An item in progress keeps its start.",
      if (_endOf(to) <= boundary) "endMinute": "The end can't be in the past.",
    };
  }

  @override
  bool operator ==(Object other) {
    return other is HistoryLock && other.boundary == boundary;
  }

  @override
  int get hashCode {
    return boundary.hashCode;
  }

  @override
  String toString() {
    return "HistoryLock($boundary)";
  }
}
