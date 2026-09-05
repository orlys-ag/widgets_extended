/// Configuration and report value types for the board module: the two
/// nullable feature configs (`BoardDragConfig`, `BoardSelectionConfig`),
/// `BoardSnap` with `BoardSnapMode`, the selection and resize enums, and
/// [BoardSelection], the VALUE a selection change reports.
library;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '_board_span.dart';

/// How a selection gesture behaves.
enum BoardSelectionMode { none, cell, range }

/// Which resize handles a drag config accepts. Set-valued POLICY; the
/// per-session single value is `BoardDragKind`, fixed at `startDrag`.
enum BoardResizeEdges { none, leading, trailing, both }

/// Which of [BoardSnap]'s three constructors made a value.
enum BoardSnapMode { track, fraction, free }

/// How a drag or selection coordinate quantizes, in TRACK space.
@immutable
class BoardSnap {
  /// Snaps to whole tracks.
  const BoardSnap.track() : mode = BoardSnapMode.track, fraction = null;

  /// Snaps to multiples of [fraction] of a track. `0.25` snaps to
  /// quarter tracks.
  const BoardSnap.fraction(double this.fraction)
    : mode = BoardSnapMode.fraction;

  /// No quantization at all.
  const BoardSnap.free() : mode = BoardSnapMode.free, fraction = null;

  /// Which constructor made this value.
  final BoardSnapMode mode;

  /// The quantum, non-null exactly when [mode] is
  /// [BoardSnapMode.fraction].
  final double? fraction;

  /// Quantizes a track-space coordinate: `track` to the NEAREST integer,
  /// `fraction` to the nearest multiple of [fraction], `free` unchanged.
  double quantize(double trackSpace) {
    switch (mode) {
      case BoardSnapMode.track:
        return trackSpace.roundToDouble();
      case BoardSnapMode.fraction:
        return (trackSpace / fraction!).roundToDouble() * fraction!;
      case BoardSnapMode.free:
        return trackSpace;
    }
  }
}

/// Adds to or replaces the built-in per-item semantics actions.
typedef BoardSemanticsActionsBuilder<TKey> =
    Map<CustomSemanticsAction, VoidCallback> Function(
      TKey itemKey,
      Map<CustomSemanticsAction, VoidCallback> builtIn,
    );

/// When and how far a refused move may slide onto nearby free space.
///
/// It acts ONLY on a refusal, so it does nothing at all without a
/// [BoardDragConfig.canDropAt] that issues one: the board has no opinion
/// of its own about whether two items may share a cell, and overlapping
/// spans are laned rather than rejected. Setting this and leaving the
/// predicate null is inert, not an error.
///
/// The gate has TWO terms and only the second is configurable. The first
/// is that the refused box must MEET an occupant, so a refusal for a
/// reason the board cannot see, a business rule of the app's own, never
/// slides anything.
@immutable
class BoardDropFit {
  /// Creates a fit policy. The defaults help a box that is at least half
  /// free and search one track on each axis.
  const BoardDropFit({
    this.minFreeFraction = 0.5,
    this.rowRadius = 1.0,
    this.colRadius = 1.0,
  }) : assert(minFreeFraction >= 0.0 && minFreeFraction <= 1.0),
       assert(rowRadius >= 0.0),
       assert(colRadius >= 0.0);

  /// The share of the refused box, by content-space AREA, that must be
  /// free of other items before the board will slide it.
  ///
  /// 1.0 disables the nudge while leaving the policy present, the two
  /// gate terms being unsatisfiable together; 0.0 is the other endpoint,
  /// admitting every refusal that is an overlap however little of the box
  /// survives it. Both ends are legal because the first term still holds
  /// the feature to overlaps.
  final double minFreeFraction;

  /// How far the search may slide the placement along the ROW axis, in
  /// tracks. Zero pins the axis, which is what a calendar wants on its
  /// day axis: slide within the day, never to another day.
  final double rowRadius;

  /// The same along the COLUMN axis. The two are separate because the
  /// useful configuration is asymmetric; see [rowRadius].
  final double colRadius;
}

/// Policy for the drag layer. Its PRESENCE on `Board.drag` is fixed at
/// widget creation; [enabled] is what may change at runtime.
class BoardDragConfig<TKey> {
  const BoardDragConfig({
    required this.onItemMoved,
    this.onItemResized,
    this.enabled = true,
    this.canDrag,
    this.canDropAt,
    this.dropFit,
    this.snap = const BoardSnap.track(),
    this.resizeEdges = BoardResizeEdges.none,
    this.primaryResizeEdges = BoardResizeEdges.none,
    this.buildDefaultDragHandles = true,
    this.dragProxyBuilder,
    this.semanticsActionsBuilder,
    this.hapticsOnDrag = false,
    this.autoScrollEdgeZone = 48.0,
    this.autoScrollMaxVelocity = 1200.0,
  });

  /// The COMMIT report for a move. The board reports; the app mutates.
  final void Function(TKey key, BoardSpan span) onItemMoved;

  /// The commit report for a resize. A null one REFUSES every resize
  /// drag at `startDrag`, because a resize this config could not report
  /// would move pixels and then vanish.
  final void Function(TKey key, BoardSpan span)? onItemResized;

  final bool enabled;
  final bool Function(TKey key)? canDrag;
  final bool Function(TKey key, BoardSpan span)? canDropAt;

  /// Whether a move [canDropAt] refuses may slide onto nearby free
  /// space, and how far. Null, the default, refuses as before; see
  /// [BoardDropFit], which still fires only on a [canDropAt] refusal.
  final BoardDropFit? dropFit;

  final BoardSnap snap;

  /// Which resize handles this config accepts on the SPAN axis, the
  /// non-primary one: the column axis on every board whose column axis
  /// is not content-sized, since the row axis is primary there.
  final BoardResizeEdges resizeEdges;

  /// Which resize handles this config accepts on the PRIMARY axis: the
  /// row axis unless the column axis is content-sized. A time grid whose
  /// rows are time gives this `trailing` so an event's bottom edge drags
  /// its end. Defaults to `none`, which leaves the span axis the only
  /// resize axis; the default handles build a strip per admitted edge on
  /// each axis.
  final BoardResizeEdges primaryResizeEdges;
  final bool buildDefaultDragHandles;
  final Widget Function(BuildContext, TKey, Widget)? dragProxyBuilder;
  final BoardSemanticsActionsBuilder<TKey>? semanticsActionsBuilder;
  final bool hapticsOnDrag;
  final double autoScrollEdgeZone;
  final double autoScrollMaxVelocity;
}

/// Policy for the selection gesture path.
class BoardSelectionConfig {
  const BoardSelectionConfig({
    required this.onChanged,
    this.enabled = true,
    this.mode = BoardSelectionMode.range,
    this.snap = const BoardSnap.track(),
  });

  final void Function(BoardSelection selection) onChanged;
  final bool enabled;
  final BoardSelectionMode mode;
  final BoardSnap snap;
}

/// A rectangular cell selection: an anchor cell, a focus cell, and the
/// enclosed rectangle they denote.
///
/// The two corners are null TOGETHER or not at all, which is what makes
/// [isEmpty] a single test. The empty form is [BoardSelection.none], and it
/// is what `BoardController.selection` holds before any `setSelection`.
///
/// The four bounds expose the ENCLOSED rectangle rather than only the two
/// corners, so a caller painting the range, and a caller feeding
/// `BoardController.itemsIn`, do not each re-derive it. [rowEnd] and
/// [colEnd] are EXCLUSIVE, which is the module's convention everywhere
/// else: a span occupies the half-open interval
/// `[startTrackOn(axis), endTrackOn(axis))` and `itemsIn` takes half-open
/// track ranges. A single-cell selection at `(2, 3)` therefore reports
/// [rowStart] 2, [rowEnd] 3, [colStart] 3, [colEnd] 4.
@immutable
class BoardSelection {
  /// Creates a selection from two corners, which are null together or not
  /// at all. Neither corner has to lead the other on either axis: the
  /// bounds below sort them.
  const BoardSelection({required this.anchor, required this.focus})
    : assert(
        (anchor == null) == (focus == null),
        "BoardSelection: anchor and focus are null together or not at "
        "all; the empty form is BoardSelection.none().",
      );

  /// The empty selection. Both corners are null, [isEmpty] is true,
  /// [contains] is false everywhere and [cells] is empty.
  const BoardSelection.none() : anchor = null, focus = null;

  /// Where the selection started. Null exactly when [isEmpty].
  final ({int row, int col})? anchor;

  /// Where the selection currently reaches. Null exactly when [isEmpty].
  final ({int row, int col})? focus;

  /// Whether this selection denotes no cell at all.
  bool get isEmpty {
    return anchor == null;
  }

  /// Leading row of the enclosed rectangle, INCLUSIVE. Legal only when
  /// [isEmpty] is false.
  int get rowStart {
    assert(!isEmpty, "BoardSelection.rowStart on an empty selection");
    return anchor!.row < focus!.row ? anchor!.row : focus!.row;
  }

  /// Trailing row of the enclosed rectangle, EXCLUSIVE. Legal only when
  /// [isEmpty] is false.
  int get rowEnd {
    assert(!isEmpty, "BoardSelection.rowEnd on an empty selection");
    return (anchor!.row > focus!.row ? anchor!.row : focus!.row) + 1;
  }

  /// Leading column of the enclosed rectangle, INCLUSIVE. Legal only when
  /// [isEmpty] is false.
  int get colStart {
    assert(!isEmpty, "BoardSelection.colStart on an empty selection");
    return anchor!.col < focus!.col ? anchor!.col : focus!.col;
  }

  /// Trailing column of the enclosed rectangle, EXCLUSIVE. Legal only when
  /// [isEmpty] is false.
  int get colEnd {
    assert(!isEmpty, "BoardSelection.colEnd on an empty selection");
    return (anchor!.col > focus!.col ? anchor!.col : focus!.col) + 1;
  }

  /// Whether the enclosed rectangle covers cell `(row, col)`. False
  /// everywhere on an empty selection, which is the one case that does NOT
  /// assert: the empty selection is an ordinary value a cell view asks
  /// about on every build.
  bool contains(int row, int col) {
    if (isEmpty) {
      return false;
    }
    return row >= rowStart && row < rowEnd && col >= colStart && col < colEnd;
  }

  /// Every cell of the enclosed rectangle, row-major. Empty on an empty
  /// selection. Lazy and re-iterable: it holds no state of its own, so a
  /// caller may walk it more than once.
  Iterable<({int row, int col})> get cells sync* {
    if (isEmpty) {
      return;
    }
    for (var row = rowStart; row < rowEnd; row++) {
      for (var col = colStart; col < colEnd; col++) {
        yield (row: row, col: col);
      }
    }
  }

  /// VALUE equality over both corners. Required, not decorative: the
  /// controller holds the selection in a `ValueNotifier`, which suppresses
  /// a dispatch exactly when `new == old`, and the render object's
  /// listener answers every dispatch with a full delegate rebuild. Without
  /// this, an equal-but-distinct write costs that rebuild for nothing.
  @override
  bool operator ==(Object other) {
    return other is BoardSelection &&
        other.anchor == anchor &&
        other.focus == focus;
  }

  @override
  int get hashCode {
    return Object.hash(anchor, focus);
  }

  @override
  String toString() {
    if (isEmpty) {
      return "BoardSelection.none()";
    }
    return "BoardSelection(anchor: (${anchor!.row}, ${anchor!.col}), "
        "focus: (${focus!.row}, ${focus!.col}))";
  }
}
