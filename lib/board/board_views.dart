/// The two builder signatures a `Board` takes and the two view objects
/// they receive.
///
/// Builders take a VIEW OBJECT, never a parameter list, following
/// `synced_sliver_tree.dart:34`, and the view carries mutation shortcuts
/// as `views.dart:133` does.
library;

import 'package:flutter/widgets.dart';

import '_board_span.dart';
import 'board_config.dart';
import 'board_controller.dart';

/// Builds the widget for one lattice CELL, or null to build nothing there.
///
/// Null is what makes a sparse board cost nothing: the delegate returns
/// null when its builder does (`widgets/scroll_delegate.dart:1118`) and
/// `buildOrObtainChildFor` returns null when no child landed
/// (`widgets/two_dimensional_viewport.dart:1498`), so an empty cell costs
/// no element, no render object and no paint.
///
/// WHEN THE BOARD CALLS THIS AGAIN. A structural change that reaches the
/// cell rebuilds it through the viewport's delegate. A payload write
/// rebuilds the cell only when the written item COVERS it, by the same
/// rule [BoardCellView.items] lists it. A selection change rebuilds the
/// cell only when its own [BoardCellView.isSelected] flipped. A read the
/// builder makes outside the view's members, a non-covering item's
/// payload or the selection's shape, is not tracked. A cell that built
/// null holds no element, so it is asked again on every layout instead.
///
/// WHEN THE BOARD MEASURES THE RESULT. On a board with a content-sized
/// axis, a cell's own extent feeds its track's, and the board measures a
/// cell when this builder is called for it and not otherwise. The
/// condition is the cell's HOST rebuilding. A widget this returns that
/// changes size without one, an animating box, an image that resolves
/// late, a font that loads, does not move its track; and neither does
/// one that rebuilds on its OWN, reading an inherited value in its
/// build, because that rebuild stops below the host. Rebuild the cell to
/// apply such a change: write the payload of an item covering it, or
/// drive the size from something this builder reads. When what changed
/// is app-wide and the board cannot observe it, a theme or a text scale,
/// call [BoardController.invalidateCellMeasurements]. On a board with no
/// content-sized axis nothing is measured and the question does not
/// arise.
///
/// A content-sized track is as tall as the tallest cell measured in it,
/// including cells since scrolled out along the other axis, so scrolling
/// sideways never changes a row's height; measuring such a cell again,
/// or finding it building nothing, replaces its measurement.
/// [BoardController.invalidateCellMeasurements] forgets them all.
///
/// A cell that builds null contributes nothing to its content-sized
/// track. When none of a track's cells builds anything,
/// `LazyContentAxis.estimate` stands in for them, and the track grows
/// past it only where its lane cluster needs more. A widget that takes
/// no extent measures zero, so a track of such cells rests at
/// `LazyContentAxis.minTrackExtent`.
typedef BoardCellBuilder<TKey, TItem> =
    Widget? Function(BuildContext context, BoardCellView<TKey, TItem> cell);

/// Builds the widget for one ITEM.
///
/// THE ITEM KEEPS ITS `State`. An item's vicinity moves when an insertion
/// or removal re-ranks it among the items starting on its primary track,
/// when it moves to another primary track, and when the column count
/// changes; the board keys each item's child by the item's key, and the
/// framework retrieves an old element by KEY before it tries the vicinity
/// (`widgets/two_dimensional_viewport.dart:357-369`), so the element, and
/// every `State` under the widget returned here, follows the item. An id
/// the board recycles for another item gets a fresh element.
///
/// WHEN THE BOARD CALLS THIS AGAIN. A structural change that reaches the
/// item rebuilds it through the viewport's delegate. A payload write to
/// the item's own key rebuilds it. A selection change rebuilds it only
/// when the selection's intersection with the item's cell range changed;
/// the view carries no selection member, and a read of the selection
/// through the controller outside that rule is not tracked.
typedef BoardItemBuilder<TKey, TItem> =
    Widget Function(BuildContext context, BoardItemView<TKey, TItem> item);

/// What a [BoardCellBuilder] is handed: one cell's coordinates plus the
/// controller, and the reads and the one mutation a cell needs.
///
/// [items] and [isSelected] are GETTERS rather than captured values, so a
/// builder reads them at build time and a caller holding a view does not
/// hold a stale answer.
@immutable
class BoardCellView<TKey, TItem> {
  /// Creates a view of cell `(row, col)` on [controller].
  const BoardCellView({
    required this.row,
    required this.col,
    required this.isFrozen,
    required this.controller,
  });

  /// The cell's row track. Track space.
  final int row;

  /// The cell's column track. Track space.
  final int col;

  /// Whether either of this cell's tracks is inside a frozen band. Read
  /// off the axis configs; the render object derives its frozen geometry
  /// from the same numbers.
  final bool isFrozen;

  /// The controller every member here resolves through.
  final BoardController<TKey, TItem> controller;

  /// The live keys whose span covers this cell. Fresh list per call, and
  /// it excludes items that are animating out.
  List<TKey> get items {
    return controller.itemsAt(row, col);
  }

  /// Whether this cell lies inside the current selection.
  bool get isSelected {
    return controller.isSelected(row, col);
  }

  /// Collapses the selection onto this cell.
  void select() {
    controller.setSelection(
      BoardSelection(anchor: (row: row, col: col), focus: (row: row, col: col)),
    );
  }
}

/// What a [BoardItemBuilder] is handed: one item's identity, payload and
/// resolved geometry, plus the controller and the three mutations an item
/// needs.
///
/// Every value here but [presence] is CAPTURED at construction rather than
/// resolved on read, because the site that constructs it is layout, which
/// has just read them from the controller and would otherwise pay for
/// them again per build. [presence] is an [Animation], read live.
@immutable
class BoardItemView<TKey, TItem> {
  /// Creates a view of the item [key] holds on [controller].
  const BoardItemView({
    required this.key,
    required this.item,
    required this.span,
    required this.lane,
    required this.laneCount,
    required this.laneSpan,
    required this.isDragging,
    required this.presence,
    required this.controller,
  });

  /// The item's key.
  final TKey key;

  /// The item's payload.
  final TItem item;

  /// The item's span. Track space.
  final BoardSpan span;

  /// The item's lane within its lane-axis track, as `controller.laneOf`
  /// reports it after the lane flush. 0 when the board has no lane axis.
  final int lane;

  /// The number of lanes the item's cluster resolved to, as
  /// `controller.laneCountOf` reports it. 1 when the board has no lane
  /// axis.
  final int laneCount;

  /// The number of consecutive lanes the item occupies, counting upward
  /// from [lane], as `controller.laneSpanOf` reports it. 1 when the
  /// board has no lane axis and when the lane above the item is taken.
  final int laneSpan;

  /// Whether a drag session currently holds this item.
  ///
  /// True in the DRAG PROXY's build. FALSE in the lattice build even
  /// while a session runs: that item comes from the viewport's delegate,
  /// and a session edge fires no structural notification, so nothing
  /// rebuilds it at the lift or the commit; a payload write to the item
  /// mid-session rebuilds it through its host with the flag true. The
  /// board's own treatment of the item left behind is
  /// `BoardDragConfig.draggedItemOpacity`; an app giving it one of its
  /// own tracks the session through `BoardDragConfig.onDragStart` and
  /// `BoardDragConfig.onDragEnd`.
  final bool isDragging;

  /// The item's enter/exit ramp: the value the board scales the item's
  /// extent by as it arrives and leaves, on the `itemEnterExit` family's
  /// clock and curve. It rises from 0 to 1 while the item enters
  /// ([AnimationStatus.forward]), falls to 0 while it leaves
  /// ([AnimationStatus.reverse]), and is 1 at rest
  /// ([AnimationStatus.completed]); once the item has left the board it
  /// is 0 and [AnimationStatus.dismissed]. A key re-added while it leaves
  /// turns back to [AnimationStatus.forward] from where it had reached.
  /// Under a zero `itemEnterExit` family it is 1 for the item's whole
  /// time on the board.
  ///
  /// A transition built on it runs WITH the board's own growth, which it
  /// does not replace: `FadeTransition(opacity: view.presence, ...)` fades
  /// the item in and out as it grows and shrinks. Every build of one item
  /// hands the same object, so the transition keeps its listener across a
  /// rebuild.
  final Animation<double> presence;

  /// The controller the three mutations below run against.
  final BoardController<TKey, TItem> controller;

  /// Writes a new payload, which fires the item-data channel only.
  void update(TItem item) {
    controller.updateItem(key, item);
  }

  /// Removes the item.
  void remove() {
    controller.removeItem(key);
  }

  /// Moves the item to [span], keeping its extent.
  void moveTo(BoardSpan span) {
    controller.moveItem(key, span);
  }
}
