/// What a create gesture reports: the range it picked, where its mark is
/// on screen, and whether the user chose the range's length.
library;

import 'package:flutter/widgets.dart';

import '../../scheduling/scheduling.dart';

/// A create a calendar's gesture picked in edit mode: the [range] of time,
/// the [globalRect] the create's mark covers on screen when it is
/// reported, and whether the user chose the range's length
/// ([userChoseLength]).
@immutable
final class CalendarCreateDetails {
  /// A create of [range], marked at [globalRect], whose length the user
  /// chose where [userChoseLength] is true.
  const CalendarCreateDetails({
    required this.range,
    required this.globalRect,
    required this.userChoseLength,
  });

  /// The time the gesture picked.
  final CalendarCreateRange range;

  /// Where the create's mark is on screen when the create is reported, in
  /// global logical pixels, as a pointer event's `globalPosition` is: in
  /// Week and Day, the rect of the slots the range marks in the column
  /// where the gesture ended, from the store's hours' start at the
  /// earliest to their end at the latest, or of the strip cell it marks
  /// there; in Agenda, the gap row whose add button was pressed; and in
  /// Month, the long-pressed day. Where Week's or Day's board gives no rect
  /// for those cells, as when a build of the grid threw before the gesture
  /// was let go, it is the empty rect at the pointer where the gesture was
  /// let go.
  ///
  /// A snapshot: it does not follow a later scroll or layout, and a part of
  /// the marked slots scrolled out of view lies past the view.
  final Rect globalRect;

  /// Whether the user chose the range's length: true where a gesture in
  /// Week or Day let go of a range from one slot or strip cell to another,
  /// and false where the calendar chose the one slot or day: a tap, a hold
  /// or a drag let go on the slot or strip cell it began on, a drag that
  /// the entries around it held on that slot, Agenda's add button and
  /// Month's long press.
  final bool userChoseLength;

  @override
  bool operator ==(Object other) {
    return other is CalendarCreateDetails &&
        other.range == range &&
        other.globalRect == globalRect &&
        other.userChoseLength == userChoseLength;
  }

  @override
  int get hashCode {
    return Object.hash(range, globalRect, userChoseLength);
  }

  @override
  String toString() {
    return "CalendarCreateDetails($range, at $globalRect"
        "${userChoseLength ? ", length chosen" : ""})";
  }
}

/// [local], a rect in [box]'s coordinates, in global logical pixels: the
/// rect between its top-left and bottom-right corners, each mapped through
/// [RenderBox.localToGlobal].
Rect globalRectOf(RenderBox box, Rect local) {
  return Rect.fromPoints(
    box.localToGlobal(local.topLeft),
    box.localToGlobal(local.bottomRight),
  );
}
