/// The kinds of entry the badges on the calendar card's days mark, and the
/// kind of each entry.
library;

import 'package:flutter/widgets.dart';

import '../entries/calendar_entry.dart';

/// One kind of entry a day's badges mark: the fill of its dot, and its
/// name in what a screen reader hears for the day. Two kinds are equal
/// when their [color] and [label] are.
@immutable
final class CalendarBadgeKind {
  /// The kind whose dot is [color], named [label].
  const CalendarBadgeKind({required this.color, required this.label});

  /// The fill of the kind's dot.
  final Color color;

  /// The kind's name in what a screen reader hears for a day that has it,
  /// as in "Thursday, April 23, has Task, Meeting".
  final String label;

  @override
  bool operator ==(Object other) {
    return other is CalendarBadgeKind &&
        other.color == color &&
        other.label == label;
  }

  @override
  int get hashCode {
    return Object.hash(color, label);
  }

  @override
  String toString() {
    return "CalendarBadgeKind($label, $color)";
  }
}

/// The badges on the days of Agenda's and Day's calendar card: a dot for
/// each kind of entry a day shows, where without them a day with entries
/// carries one dot in the [CalendarThemeData.primary] colour.
///
/// A day carries a dot for each of [kinds] that [kindOf] answers for one
/// of its shown entries, in the order of [kinds], and after them one in
/// the primary colour where [kindOf] answers null for one. The dots run
/// along the rim of the day's circle, 30 degrees apart, their middle at
/// the circle's top right, where a lone dot sits; a circle draws the first
/// four, and a screen reader hears every kind the day has, the primary
/// dot's as "other items", or as "items" where it is the day's only dot.
///
/// The days read their badges again when the store notifies and when they
/// are given badges not identical to the last, so a host keeps one
/// instance rather than making one in each build.
@immutable
final class CalendarDayBadges<T> {
  /// The badges of [kinds], each entry's kind as [kindOf] answers it.
  const CalendarDayBadges({required this.kinds, required this.kindOf});

  /// The kinds, in the order their dots run.
  final List<CalendarBadgeKind> kinds;

  /// The kind of [entry], one of [kinds], or null for the primary dot. A
  /// kind [kinds] does not hold fails an assertion in a debug build, and
  /// is taken for null in a release one.
  final CalendarBadgeKind? Function(CalendarEntry<T> entry) kindOf;
}
