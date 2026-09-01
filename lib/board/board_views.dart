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
typedef BoardCellBuilder<TKey, TItem> =
    Widget? Function(BuildContext context, BoardCellView<TKey, TItem> cell);

/// Builds the widget for one ITEM.
///
/// AN ORDINAL SHIFT IS A VICINITY CHANGE, and the item's `State` does
/// not survive one: an item vicinity's `xIndex` is the item's rank among
/// the items starting on its primary track, so an insertion or removal
/// that re-ranks the item re-keys its vicinity, and the framework
/// retrieves an old element by KEY first and only then by vicinity
/// (`widgets/two_dimensional_viewport.dart:357`), so a re-ranked item
/// loses its `State` unless the widget returned here carries a
/// `GlobalKey`. A pure lane change re-lanes it in place and keeps it.
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
/// Every value here is CAPTURED at construction rather than resolved on
/// read, because the site that constructs it is layout, which has just
/// read all five from the controller and would otherwise pay for them
/// again per build.
@immutable
class BoardItemView<TKey, TItem> {
  /// Creates a view of the item [key] holds on [controller].
  const BoardItemView({
    required this.key,
    required this.item,
    required this.span,
    required this.lane,
    required this.laneCount,
    required this.isDragging,
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

  /// Whether a drag session currently holds this item.
  final bool isDragging;

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
