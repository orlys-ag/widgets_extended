/// The signatures of the builders a calendar view draws its entries, its
/// add button and its loading and failure states through, and the values
/// each builder takes beside the context.
library;

import 'package:flutter/widgets.dart';

import '../store/calendar_store.dart';

/// The height of the strip a card builder draws across a card's top for
/// [CalendarCardDetails.startsAt], and across its bottom for
/// [CalendarCardDetails.endsAt], in logical pixels of the card's own space.
/// Agenda's day list places its current-time marker between a card's strips
/// and predicts the height of a row it has not built by it.
const double calendarCardStripExtent = 25.0;

/// Builds the content of a block of Week's or Day's timed grid: everything
/// inside the box the grid gives [entry], its pending state included.
///
/// The grid calls it only in a widget's build, which the board may run
/// inside its layout, so the builder marks no ancestor dirty. It calls it
/// when the block's box is first built, and again only when [entry],
/// [details] or the grid's builder parameter changes, an inherited widget
/// the builder read notifies, or a hot reload reassembles the grid; not
/// when anything else the builder reads changes. The grid keeps the
/// block's gestures, handles and semantics around the output.
typedef CalendarBlockBuilder<T> =
    Widget Function(
      BuildContext context,
      CalendarShownEntry<T> entry,
      CalendarBlockDetails details,
    );

/// Builds the content of a bar of Month's board, in its chip or card form:
/// everything inside the lane the board gives [entry], its pending state
/// included.
///
/// The board calls it only in a widget's build, which the board may run
/// inside its layout, so the builder marks no ancestor dirty. It calls it
/// when the bar's box is first built, and again only when [entry],
/// [details] or the board's builder parameter changes, an inherited widget
/// the builder read notifies, or a hot reload reassembles the board; not
/// when anything else the builder reads changes. The board keeps the bar's
/// semantics node and its tap around the output.
typedef CalendarChipBuilder<T> =
    Widget Function(
      BuildContext context,
      CalendarShownEntry<T> entry,
      CalendarChipDetails details,
    );

/// Builds the card of [entry] in a row of Agenda's day list: everything
/// inside the box the list gives it, its pending state, its strips and any
/// menu of [CalendarCardDetails.onEdit] and [CalendarCardDetails.onDelete]
/// included.
///
/// The list calls it only in a widget's build, which the sliver tree may
/// run inside its layout, so the builder marks no ancestor dirty. It calls
/// it on each build of the row's card slot, which is each build of the
/// list.
typedef CalendarCardBuilder<T> =
    Widget Function(
      BuildContext context,
      CalendarShownEntry<T> entry,
      CalendarCardDetails details,
    );

/// Builds the button of a gap of Agenda's day list that adds an entry
/// there, filling the square the list gives it, and calling
/// [CalendarAddButtonDetails.onPressed] for a press.
///
/// The list calls it only in a widget's build, which the sliver tree may
/// run inside its layout, so the builder marks no ancestor dirty. It calls
/// it on each build of the gap's row, which is each build of the list. The
/// list labels the square for a screen reader.
typedef CalendarAddButtonBuilder =
    Widget Function(BuildContext context, CalendarAddButtonDetails details);

/// Builds what a view shows while the days of [state] are read: on the
/// cover over a timed grid or the month board, or in a row of Agenda's day
/// list, as [CalendarLoadingState.site] names.
///
/// A view calls it only in a widget's build, which the board, the sliver
/// tree and a view's [LayoutBuilder] may run inside their layout, so the
/// builder marks no ancestor dirty. It calls it on each build of the cover
/// or the row that holds it.
typedef CalendarLoadingBuilder =
    Widget Function(BuildContext context, CalendarLoadingState state);

/// Builds what a view shows when the read of the days of [state] failed:
/// on the cover over a timed grid or the month board, or in a row of
/// Agenda's day list, as [CalendarFailureState.site] names.
///
/// A view calls it only in a widget's build, which the board, the sliver
/// tree and a view's [LayoutBuilder] may run inside their layout, so the
/// builder marks no ancestor dirty. It calls it on each build of the cover
/// or the row that holds it.
typedef CalendarFailureBuilder =
    Widget Function(BuildContext context, CalendarFailureState state);

/// What the timed grid decides about one block's appearance, which a
/// [CalendarBlockBuilder] draws from. A block shows one piece of its
/// entry: the part of it on the block's day.
@immutable
final class CalendarBlockDetails {
  /// The block's form, its room, its cut ends and its continued ends.
  const CalendarBlockDetails({
    required this.detailed,
    required this.tall,
    required this.cutAtStart,
    required this.cutAtEnd,
    this.continuesBefore = false,
    this.continuesAfter = false,
  });

  /// Whether the grid shows one day column, with room for the times and
  /// every line under them.
  final bool detailed;

  /// Whether the block covers three slots or more: room for a second line
  /// on a block that is not [detailed]. Read from the span the board
  /// places the block on, so a block laid out at a new extent each frame
  /// does not rebuild for it.
  final bool tall;

  /// Whether the block's piece starts before the grid's hours on its day,
  /// which the grid then cuts off. A piece that starts at its day's start
  /// because its entry began on an earlier day is cut only where the hours
  /// start after midnight; [continuesBefore] tells that it continues.
  final bool cutAtStart;

  /// Whether the block's piece ends after the grid's hours on its day,
  /// which the grid then cuts off, as [cutAtStart] does at its start.
  final bool cutAtEnd;

  /// Whether the block's entry has a part on an earlier day than the
  /// block's.
  final bool continuesBefore;

  /// Whether the block's entry has a part on a later day than the
  /// block's.
  final bool continuesAfter;

  @override
  bool operator ==(Object other) {
    return other is CalendarBlockDetails &&
        other.detailed == detailed &&
        other.tall == tall &&
        other.cutAtStart == cutAtStart &&
        other.cutAtEnd == cutAtEnd &&
        other.continuesBefore == continuesBefore &&
        other.continuesAfter == continuesAfter;
  }

  @override
  int get hashCode {
    return Object.hash(
      detailed,
      tall,
      cutAtStart,
      cutAtEnd,
      continuesBefore,
      continuesAfter,
    );
  }

  @override
  String toString() {
    return "CalendarBlockDetails(detailed: $detailed, tall: $tall, "
        "cutAtStart: $cutAtStart, cutAtEnd: $cutAtEnd, continuesBefore: "
        "$continuesBefore, continuesAfter: $continuesAfter)";
  }
}

/// What the month board decides about one bar's appearance, which a
/// [CalendarChipBuilder] draws from.
@immutable
final class CalendarChipDetails {
  /// The bar's form and its continued ends.
  const CalendarChipDetails({
    required this.card,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  /// Whether the days are large enough for the card form: a bar one card
  /// lane tall, with room for the times under the title. Otherwise the
  /// bar is a chip, one lane tall.
  final bool card;

  /// Whether the entry covers days before the bar's week.
  final bool continuesBefore;

  /// Whether the entry covers days after the bar's week.
  final bool continuesAfter;

  @override
  bool operator ==(Object other) {
    return other is CalendarChipDetails &&
        other.card == card &&
        other.continuesBefore == continuesBefore &&
        other.continuesAfter == continuesAfter;
  }

  @override
  int get hashCode {
    return Object.hash(card, continuesBefore, continuesAfter);
  }

  @override
  String toString() {
    return "CalendarChipDetails(card: $card, continuesBefore: "
        "$continuesBefore, continuesAfter: $continuesAfter)";
  }
}

/// What Agenda's day list hands one card, which a [CalendarCardBuilder]
/// draws from. Compared by identity: the list makes one on each build of
/// the card's slot.
@immutable
final class CalendarCardDetails {
  /// The card's strips and the actions the list offers on its entry.
  const CalendarCardDetails({
    this.startsAt,
    this.endsAt,
    this.onEdit,
    this.onDelete,
  });

  /// The time the row's piece of the entry, its part on the row's day,
  /// starts at as the list writes it, for a piece that starts before the
  /// list's hours on that day; null for one that starts inside them.
  final String? startsAt;

  /// The time the row's piece of the entry ends at as the list writes it,
  /// for a piece that ends after the list's hours on the row's day; null
  /// for one that ends inside them.
  final String? endsAt;

  /// Requests an edit of the entry; null where the list offers none.
  final VoidCallback? onEdit;

  /// Requests the entry's delete; null where the list offers none.
  final VoidCallback? onDelete;
}

/// Where a gap's add button of Agenda's day list adds an entry, which a
/// [CalendarAddButtonBuilder] draws from.
@immutable
final class CalendarAddButtonDetails {
  /// The button that adds an entry at [startMinute] on [day].
  const CalendarAddButtonDetails({
    required this.day,
    required this.startMinute,
    required this.onPressed,
  });

  /// The day the gap lies in, at local midnight.
  final DateTime day;

  /// The minute after midnight a press adds an entry at.
  final int startMinute;

  /// Adds the entry; the builder calls it for a press.
  final VoidCallback onPressed;
}

/// Where a view shows a loading or a failure state.
enum CalendarStateSite {
  /// Centred on the cover over a timed grid or the month board, which takes
  /// every press while the days are not ready.
  cover,

  /// A row of Agenda's day list under the day's header, given the row's
  /// width and a height: 24 for loading and at least 48 for failure, the
  /// heights the list predicts for a row a reveal passes without building
  /// it.
  dayRow,
}

/// The days a view waits on a read of, which a [CalendarLoadingBuilder]
/// draws from.
@immutable
final class CalendarLoadingState {
  /// The read of the days from [first] to [last] at [site].
  const CalendarLoadingState({
    required this.site,
    required this.first,
    required this.last,
  });

  /// Where the view shows the state.
  final CalendarStateSite site;

  /// The first day being read, at local midnight.
  final DateTime first;

  /// The last day being read, at local midnight; [first] in a row.
  final DateTime last;
}

/// The days whose read failed, which a [CalendarFailureBuilder] draws
/// from.
@immutable
final class CalendarFailureState {
  /// The failed read of the days from [first] to [last] at [site].
  const CalendarFailureState({
    required this.site,
    required this.first,
    required this.last,
    required this.error,
    required this.retry,
  });

  /// Where the view shows the state.
  final CalendarStateSite site;

  /// The first day whose read failed, at local midnight.
  final DateTime first;

  /// The last day whose read failed, at local midnight; [first] in a row.
  final DateTime last;

  /// The error the store's read failed with, as the store holds it; null
  /// for a day whose read failed while the range the view shows is ready.
  final Object? error;

  /// Reads those days again.
  final VoidCallback retry;
}
