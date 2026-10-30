/// The move or resize a timed grid's gesture lands, as a value.
library;

import 'package:flutter/foundation.dart';

import '../entries/calendar_entry.dart';

/// Which gesture landed a [CalendarMoveRequest].
enum CalendarMoveKind {
  /// A block or a bar moved: within the slots, within the all-day strip,
  /// or from one into the other.
  move,

  /// An edge of a block or a bar dragged.
  resize,
}

/// A move or a resize a gesture landed on an entry: the [entry] as stored
/// when it landed, and the [requested] entry, [entry] at the times the
/// gesture gave it.
///
/// `CalendarStore.requestMove` of [requested] writes it, and one of
/// [entry] writes the entry back as it was.
@immutable
final class CalendarMoveRequest<T> {
  /// The [kind] of gesture that gives [entry] the times of [requested].
  const CalendarMoveRequest({
    required this.entry,
    required this.requested,
    required this.kind,
  });

  /// The entry as stored when the gesture landed.
  final CalendarEntry<T> entry;

  /// [entry] with the start and end the gesture gave it.
  final CalendarEntry<T> requested;

  /// Whether a move or a resize landed it.
  final CalendarMoveKind kind;

  @override
  bool operator ==(Object other) {
    return other is CalendarMoveRequest<T> &&
        other.entry == entry &&
        other.requested == requested &&
        other.kind == kind;
  }

  @override
  int get hashCode {
    return Object.hash(entry, requested, kind);
  }

  @override
  String toString() {
    return "CalendarMoveRequest(${kind.name}: ${entry.id} from "
        "${entry.start} to ${entry.end}, to ${requested.start} to "
        "${requested.end})";
  }
}
