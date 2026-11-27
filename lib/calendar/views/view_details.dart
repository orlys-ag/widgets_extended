/// What the views report, as values: a tap on an entry, an edit or a
/// delete request from a card, and the sizes a pinch zooms to.
library;

import 'package:flutter/foundation.dart';

import '../../scheduling/scheduling.dart';

/// A tap on an entry: the [entry] as the reader stores it
/// ([CalendarEntryReader.storedEntry]), and whether it is [editable], the
/// view in edit mode and its edit policy letting it be edited
/// ([CalendarEditPolicy.mayEdit]).
@immutable
final class CalendarEntryTapDetails<T> {
  /// A tap on [entry], [editable] or not.
  const CalendarEntryTapDetails({required this.entry, required this.editable});

  /// The stored entry, without a pending move's requested time.
  final CalendarEntry<T> entry;

  /// Whether a host's form may change the entry: the view is in edit mode
  /// and its edit policy lets the entry be edited
  /// ([CalendarEditPolicy.mayEdit]).
  final bool editable;
}

/// An edit request from a card: the [entry] as the reader stores it
/// ([CalendarEntryReader.storedEntry]).
@immutable
final class CalendarEditRequestDetails<T> {
  /// A request to edit [entry].
  const CalendarEditRequestDetails({required this.entry});

  /// The stored entry, without a pending move's requested time.
  final CalendarEntry<T> entry;
}

/// A delete request from a card: the [entry] as the reader stores it
/// ([CalendarEntryReader.storedEntry]).
@immutable
final class CalendarDeleteRequestDetails<T> {
  /// A request to delete [entry].
  const CalendarDeleteRequestDetails({required this.entry});

  /// The stored entry, without a pending move's requested time.
  final CalendarEntry<T> entry;
}

/// The sizes a pinch zooms a timed grid to: its least slot height and its
/// least day width, lengths in logical pixels, neither a position.
@immutable
final class CalendarGridZoomDetails {
  /// A zoom to [minSlotHeight] and [minDayWidth].
  const CalendarGridZoomDetails({
    required this.minSlotHeight,
    required this.minDayWidth,
  });

  /// The least height of one slot, in logical pixels.
  final double minSlotHeight;

  /// The least width of a day column, in logical pixels.
  final double minDayWidth;
}

/// The sizes a pinch zooms a month board to: its week scale, a ratio, and
/// its least day width, a length in logical pixels, neither a position.
@immutable
final class CalendarMonthZoomDetails {
  /// A zoom to [weekScale] and [minDayWidth].
  const CalendarMonthZoomDetails({
    required this.weekScale,
    required this.minDayWidth,
  });

  /// How many times its share of the board's height a week rests at, at
  /// least 1.
  final double weekScale;

  /// The least width of a day, in logical pixels.
  final double minDayWidth;
}
