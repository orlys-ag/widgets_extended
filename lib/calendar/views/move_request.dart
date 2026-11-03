/// The move or resize a timed grid's gesture lands, as a value.
library;

import 'package:flutter/foundation.dart';

import '../../scheduling/scheduling.dart';

/// Which gesture landed a [CalendarMoveRequest].
enum CalendarMoveKind {
  /// A block or a bar moved: within the slots, within the all-day strip,
  /// or from one into the other.
  move,

  /// An edge of a block or a bar dragged.
  resize,
}

/// A move or a resize a gesture landed on an entry: the [entry] as stored
/// when it landed, and the [requested] entry, [entry] with the times the
/// gesture gave it and whether it is all-day ([CalendarEntry.isAllDay]): a
/// move or a resize within the slots or within the all-day strip keeps
/// whether the entry is all-day, and a move from one into the other
/// changes it, possibly with the times unchanged.
///
/// `CalendarStore.requestMove` of [requested] writes it, and one of
/// [entry] writes the entry back as it was.
@immutable
final class CalendarMoveRequest<T> {
  /// The [kind] of gesture, a move or a resize, that gives [entry] the
  /// times of [requested] and makes it all-day or timed
  /// ([CalendarEntry.isAllDay]).
  ///
  /// Throws an [ArgumentError], in every build, naming `entry` for an
  /// [entry] with no id, and `requested` for a [requested] whose id is not
  /// [entry]'s. Their other fields are not compared.
  CalendarMoveRequest({
    required this.entry,
    required this.requested,
    required this.kind,
  }) {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError.value(entry, "entry", "A moved entry has an id");
    }
    if (requested.id != id) {
      throw ArgumentError.value(
        requested,
        "requested",
        "A requested entry has its entry's id, $id",
      );
    }
  }

  /// The entry as stored when the gesture landed.
  final CalendarEntry<T> entry;

  /// [entry] with the start, the end and whether it is all-day
  /// ([CalendarEntry.isAllDay]) as the gesture gave them.
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
