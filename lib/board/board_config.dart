/// Configuration and report value types for the board module: the two
/// nullable feature configs (`BoardDragConfig`, `BoardSelectionConfig`),
/// `BoardSnap` with `BoardSnapMode`, the selection and resize enums, and
/// [BoardSelection], the VALUE a selection change reports.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '_board_drop_resolver.dart';
import '_board_span.dart';

/// How a selection gesture behaves.
///
/// `cell` selects the cell a tap lands on. `range` selects the rectangle
/// between the cell a drag starts on and the cell under the pointer: a
/// mouse, stylus or trackpad starts it the moment it moves, and TOUCH
/// after a long press, so an ordinary touch drag over the cells scrolls
/// the board. Pointers of unknown kind, which accessibility services
/// scroll with, are treated as touch.
enum BoardSelectionMode { none, cell, range }

/// Which resize handles a drag config accepts. Set-valued POLICY; the
/// per-session single value is `BoardDragKind`, fixed at `startDrag`.
///
/// `leading` and `trailing` name CONTENT edges: the start and the end of
/// the item's span on the axis. On an axis that runs forward they paint
/// at the item's top or left and its bottom or right; on a reversed axis
/// (`AxisDirection.up` or `AxisDirection.left`) the other way round. The
/// default handles place each band where its edge paints.
enum BoardResizeEdges {
  /// No edge resizes on this axis.
  none,

  /// The start of the item's span resizes.
  leading,

  /// The end of the item's span resizes.
  trailing,

  /// Either end resizes, each from its own handle.
  both,
}

/// Which of [BoardSnap]'s three constructors made a value.
enum BoardSnapMode {
  /// Whole tracks: [BoardSnap.track].
  track,

  /// Multiples of a fraction of a track: [BoardSnap.fraction].
  fraction,

  /// No quantizing: [BoardSnap.free].
  free,
}

/// How a drag or selection coordinate quantizes, in TRACK space.
@immutable
class BoardSnap {
  /// Snaps to whole tracks.
  const BoardSnap.track() : mode = BoardSnapMode.track, fraction = null;

  /// Snaps to multiples of [fraction] of a track. `0.25` snaps to
  /// quarter tracks. The quantum must be positive: [quantize] divides by
  /// it, and a zero would make every quantized value NaN. There is no
  /// upper bound; a quantum above one track is a legal coarse snap.
  const BoardSnap.fraction(double this.fraction)
    : assert(
        fraction > 0.0,
        "BoardSnap.fraction: the quantum must be positive.",
      ),
      mode = BoardSnapMode.fraction;

  /// No quantization at all.
  const BoardSnap.free() : mode = BoardSnapMode.free, fraction = null;

  /// Which constructor made this value.
  final BoardSnapMode mode;

  /// The quantum, non-null exactly when [mode] is
  /// [BoardSnapMode.fraction].
  final double? fraction;

  /// Quantizes a track-space coordinate: `track` to the NEAREST integer,
  /// `fraction` to the nearest multiple of [fraction], `free` unchanged.
  ///
  /// A multiple of [fraction] that lands on a whole track is returned as
  /// that exact integer: in doubles, `k * fraction` can come to one ulp
  /// below it (49 quanta of `1 / 49`, 180 of `0.35`), and a start there
  /// would split into the track before.
  double quantize(double trackSpace) {
    switch (mode) {
      case BoardSnapMode.track:
        return trackSpace.roundToDouble();
      case BoardSnapMode.fraction:
        return snapToTrackEdge(
          (trackSpace / fraction!).roundToDouble() * fraction!,
        );
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
/// A refused item lying wholly past the lattice's end on either axis, as
/// one can once its tracks are removed, paints nowhere, so it is first
/// moved back onto the lattice, before either term of the gate and
/// whatever the radii: to the last placement on that axis that holds it,
/// or, beside a trailing frozen band, the last on the grid the search
/// steps by that starts above that band and shows, where any does. It
/// lands there when [BoardDragConfig.canDropAt] admits it, and the slide
/// starts from there otherwise. That move is not a slide.
///
/// The gate has TWO terms and only the second is configurable. The first
/// is that the refused box must MEET an occupant, so a refusal for a
/// reason the board cannot see, a business rule of the app's own, never
/// slides anything.
///
/// The search steps by the drag's snap quantum, and by whole tracks on
/// the lane axis of a laned item, which moves there by whole tracks.
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

  /// The share of the SEARCH REGION, by content-space AREA, that must be
  /// free of other items before the board will slide the item into it.
  ///
  /// The region is the refused box widened by [rowRadius] and
  /// [colRadius], with, on each axis the search steps along, both ends of
  /// that widening held within the reach of the placements a candidate
  /// may take there: beside a frozen band, those in the box's band, or
  /// those that show where any does. The region covers the box's tracks
  /// that lie in the lattice and is one unbroken run of whole tracks. So,
  /// on an axis the search steps along, tracks hidden under a band count
  /// only where they lie within that reach or between it and the box,
  /// while a track within the radius that no candidate happens to occupy
  /// still counts.
  /// This asks whether the neighbourhood being dropped into is mostly
  /// empty. It deliberately does NOT measure the box: a box on whole
  /// tracks against occupants on whole tracks is either wholly free or
  /// wholly covered and never in between, so a box-share threshold is
  /// unreachable for a single-cell item and no whole-track board would
  /// ever be helped.
  ///
  /// 1.0 asks for a neighbourhood with nothing in it at all, which the
  /// first term then forbids, so it disables the nudge, though not the
  /// move back onto the lattice the class doc describes, while leaving the
  /// policy present; 0.0 is the other endpoint, admitting every refusal
  /// that is an overlap however crowded the surroundings. Both ends are
  /// legal because the first term still holds the feature to overlaps.
  final double minFreeFraction;

  /// How far the search may slide the placement along the ROW axis, in
  /// tracks. Zero pins the axis for the slide, which is what a calendar
  /// wants on its day axis: slide within the day, never to another day.
  /// The move back onto the lattice the class doc describes is not bound
  /// by it.
  final double rowRadius;

  /// The same along the COLUMN axis. The two are separate because the
  /// useful configuration is asymmetric; see [rowRadius].
  final double colRadius;
}

/// Policy for the drag layer.
///
/// A board applies each new instance IN PLACE, so it can be built inline
/// in a parent's `build`: a live drag carries on under the new policy,
/// and only [enabled] turning false, or a resize session the new config
/// can no longer report or admit, cancels one. [enabled] is the runtime
/// switch.
///
/// The board takes keyboard focus when a drag starts, and Escape then
/// cancels the drag, as the pointer's cancel does: nothing is reported
/// and the item returns. The key is consumed, so a route above the board
/// that closes on Escape stays open.
///
/// WHEN THE CALLBACKS RUN. [onDragStart], [onDragTargetChanged] and
/// [onDragEnd] are delivered after the board call that caused them has
/// returned: in a microtask, or earlier, at the start of any pointer
/// release, whether or not it commits. Never inside a `BoardController`
/// mutation, a build, a layout or the frame's finalize, so a handler may
/// mutate the board and call `setState`. A session's [onDragStart] comes
/// first, then its [onDragTargetChanged] calls, then [onItemMoved] or
/// [onItemResized] for a committed drop, then its [onDragEnd]; a later
/// session's [onDragStart] comes after that [onDragEnd]. [onDragEnd] sees
/// the board after the mutation that ended the drag. A throw from one of
/// the three is reported through `FlutterError.reportError` and does not
/// stop the ones after it. [onDragEnd] may run after the board has left
/// the tree, for a drag it ended as it left, so a handler that calls
/// `setState`, or reads a `BoardController` its `State` disposes, checks
/// `mounted` first.
///
/// The reports, [onItemMoved] and [onItemResized], are synchronous,
/// inside the pointer release, so the app's mutation lands before the
/// board animates the drop. The board does not catch a throw from a
/// report, and the drag's [onDragEnd] is still delivered.
///
/// [canDrag] and [canDropAt] are questions, asked synchronously during
/// build as well as during a drag: they must not mutate the board or call
/// `setState`. One that throws is answered as a refusal, and the throw is
/// reported through `FlutterError.reportError`.
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
    this.dragProxyOpacity = 1.0,
    this.draggedItemOpacity = 0.5,
    this.semanticsActionsBuilder,
    this.hapticsOnDrag = false,
    this.autoScrollEdgeZone = 48.0,
    this.autoScrollMaxVelocity = 1200.0,
    this.dragStartDelay = kLongPressTimeout,
    this.resizeHandleExtent = 12.0,
    this.onDragStart,
    this.onDragTargetChanged,
    this.onDragEnd,
  }) : assert(
         resizeHandleExtent > 0.0,
         "resizeHandleExtent is a depth in logical pixels, above zero.",
       ),
       assert(
         dragProxyOpacity >= 0.0 && dragProxyOpacity <= 1.0,
         "dragProxyOpacity is an opacity: 0.0 through 1.0.",
       ),
       assert(
         draggedItemOpacity >= 0.0 && draggedItemOpacity <= 1.0,
         "draggedItemOpacity is an opacity: 0.0 through 1.0.",
       );

  /// The COMMIT report for a move. The board reports; the app mutates.
  final void Function(TKey key, BoardSpan span) onItemMoved;

  /// The commit report for a resize. A null one REFUSES every resize
  /// drag at `startDrag`, because a resize this config could not report
  /// would move pixels and then vanish.
  final void Function(TKey key, BoardSpan span)? onItemResized;

  /// Whether any drag may start. The runtime switch: toggling it keeps
  /// every item's `State`, and turning it false cancels a live session,
  /// reporting nothing.
  final bool enabled;

  /// Whether the item [key] may START a drag. Asked whenever an item's
  /// drag wrapper builds and again at the lift. It gates the lift only: a
  /// session that started stays live when this later refuses its item.
  /// A question, which must not mutate; one that throws refuses, and the
  /// throw is reported (see the class doc).
  final bool Function(TKey key)? canDrag;

  /// Whether the item [key] may land on [span]. Asked for every target
  /// the drag resolves to, again after every structural change to the
  /// board while the drag runs (so an occupant leaving or arriving under
  /// a resting pointer is answered for), and again at the drop; a refused
  /// target shows no gap and commits nothing. A predicate that reads
  /// state the board cannot see is asked again when a new config is
  /// assigned. A question, which must not mutate; one that throws
  /// refuses, with no [dropFit] nudge, and the throw is reported (see the
  /// class doc).
  final bool Function(TKey key, BoardSpan span)? canDropAt;

  /// Whether a move [canDropAt] refuses may slide onto nearby free
  /// space, and how far. Null, the default, refuses as before; see
  /// [BoardDropFit], which still fires only on a [canDropAt] refusal.
  final BoardDropFit? dropFit;

  /// How a drag's target quantizes: a move's start and a resize's dragged
  /// edge, on both axes. A drag leaves an axis where it was until it has
  /// brought the item onto a grid line there or half a step along it;
  /// under `free`, until it moves at all; on the lane axis of a laned
  /// item, until the finger leaves its cell. So pressing a handle, or
  /// lifting an item and letting go, changes nothing (the unchanged span
  /// is still reported), unless [canDropAt] refuses the item where it
  /// is: then nothing is committed, or a [dropFit] may slide a lifted
  /// item to free space nearby. One exception holds under every snap: on
  /// the lane axis a LANED item occupies one track, so it moves there by
  /// whole tracks, landing on the track under the finger.
  final BoardSnap snap;

  /// Which resize handles this config accepts on the SPAN axis, the
  /// non-primary one: the column axis on every board whose column axis
  /// is not content-sized, since the row axis is primary there.
  final BoardResizeEdges resizeEdges;

  /// Which resize handles this config accepts on the PRIMARY axis: the
  /// row axis unless the column axis is content-sized. A time grid whose
  /// rows are time gives this `trailing` so an event's bottom edge drags
  /// its end. Defaults to `none`, which leaves the span axis the only
  /// resize axis; the default handles give each admitted edge on each
  /// axis a band (see [buildDefaultDragHandles]).
  final BoardResizeEdges primaryResizeEdges;

  /// Whether the board builds its own handles on every item. A press
  /// inside an admitted edge's BAND starts a resize of that edge at once;
  /// a band is 12 px deep, and never more than a third of the item on its
  /// axis, so a short item keeps a move zone. A press anywhere else on
  /// the item starts a move after a long press, which leaves touch
  /// scrolling that starts on an item working. False leaves the item's
  /// own `BoardDragHandle`s as the only way to start a drag.
  final bool buildDefaultDragHandles;
  /// Wraps the floating proxy a MOVE shows under the pointer, or null to
  /// show it as built. Called with the dragged key and the default proxy,
  /// the item's own builder output at the item's size, faded by
  /// [dragProxyOpacity] and ignoring pointers; what it returns is placed
  /// at the proxy's top-left corner, in a `Stack` above the board, so the
  /// proxy shares the board's ancestors but not the lattice's clip. A
  /// resize shows no proxy.
  final Widget Function(BuildContext, TKey, Widget)? dragProxyBuilder;

  /// The moved visual's opacity while a move session is live. The
  /// default, 1.0, makes the proxy the opaque half of the pair and
  /// leaves the fading to [draggedItemOpacity].
  final double dragProxyOpacity;

  /// The opacity of the item LEFT BEHIND in the lattice while a MOVE
  /// session holds it. 1.0 leaves it untouched.
  ///
  /// A RESIZE session never dims, whatever this holds: it paints no
  /// proxy, so a faded item would leave nothing at full strength.
  final double draggedItemOpacity;

  /// Adds to or replaces an item's semantics actions. The board builds
  /// four, one track up, down, left and right on the screen, labelled
  /// with `WidgetsLocalizations`' `reorderItemUp`, `reorderItemDown`,
  /// `reorderItemLeft` and `reorderItemRight`, and advertises each only
  /// where the drag policy admits the move.
  ///
  /// There are no built-in RESIZE actions: a resize's unit is the app's,
  /// an hour on a calendar or a column on a planner, and no framework
  /// string names it. Add them here in the app's own words, reporting
  /// through `onItemResized` as a drag would.
  final BoardSemanticsActionsBuilder<TKey>? semanticsActionsBuilder;
  /// Whether a drag's start plays `HapticFeedback.mediumImpact`.
  final bool hapticsOnDrag;

  /// Depth, in logical pixels, of the zone inside each edge of the
  /// scrolled region where a drag's pointer scrolls the board toward
  /// that edge. Measured from the region's edges, so it sits just inside
  /// a frozen band; zero turns autoscroll off.
  final double autoScrollEdgeZone;

  /// Scroll speed, in logical pixels per second, with the pointer at the
  /// edge itself; it ramps linearly from zero at the zone's inner edge.
  final double autoScrollMaxVelocity;

  /// How long a press on an item must rest before its default handle
  /// lifts it; a move past the touch slop within it gives the pointer to
  /// whatever else wants it, the scrollable for instance. The resize
  /// strips start at once. A `BoardDelayedDragHandle` carries its own.
  final Duration dragStartDelay;

  /// The deepest a default resize strip reaches into its item, in logical
  /// pixels; a strip never takes more than a third of the item, so the
  /// move zone between two strips stays at least as deep as either.
  final double resizeHandleExtent;

  /// Called once a drag has started, with the dragged key and whether it
  /// moves or resizes on which edge. The first drop target follows it
  /// through [onDragTargetChanged]. Delivered after the call that started
  /// the drag (see the class doc).
  final void Function(TKey key, BoardDragKind kind)? onDragStart;

  /// Called whenever the drop target differs from the last one reported,
  /// which starts as null: the placement a release would report, or null
  /// where [canDropAt] refuses it. Not called per pointer move, so a label
  /// such as "10:30 to 11:00" rebuilds only when it changes. Delivered
  /// after the call that changed the target (see the class doc).
  final void Function(TKey key, BoardDropTarget? target)?
  onDragTargetChanged;

  /// Called once per drag that ends by a release or a cancel, after the
  /// drop's report: [committed] is whether the drop was reported through
  /// [onItemMoved] or [onItemResized]. Escape, `enabled` turned off, the
  /// board leaving the tree, and a mutation of the dragged item end a
  /// drag uncommitted. Delivered after the call that ended the drag, so
  /// it sees that call's result, and possibly after the board has left
  /// the tree (see the class doc).
  final void Function(TKey key, bool committed)? onDragEnd;
}

/// Policy for the selection gesture path, and for the keyboard: while a
/// selection config is enabled in a mode other than `none`, the board is
/// a Tab stop and moves the selection with the arrow keys, Home, End,
/// Page Up and Page Down, Shift extending a range. See `Board`'s
/// keyboard doc.
class BoardSelectionConfig {
  const BoardSelectionConfig({
    required this.onChanged,
    this.enabled = true,
    this.mode = BoardSelectionMode.range,
    this.snap = const BoardSnap.track(),
    this.autoScrollEdgeZone = 48.0,
    this.autoScrollMaxVelocity = 1200.0,
  });

  /// Called with the new selection on EVERY change of it, whoever made
  /// it: the board's taps, range drags and keys, a cell view's
  /// `select()`, and `BoardController.setSelection`. Once per change: a
  /// write equal to the current selection calls nothing. Unlike a text
  /// field's, which "doesn't run when the TextField's text is changed
  /// programmatically" (`widgets/editable_text.dart:1405-1413`), so an
  /// app that writes the selection from its own state sees its write
  /// here, and must not write it again in response.
  final void Function(BoardSelection selection) onChanged;

  /// Whether the board's selection gestures and keys are active. The
  /// runtime switch: turning it false leaves the current selection as it
  /// is, and toggling it keeps every cell's and item's `State`.
  final bool enabled;

  /// What a gesture selects; see [BoardSelectionMode].
  final BoardSelectionMode mode;

  /// How a gesture's point resolves to a cell. Under a fraction snap the
  /// point is quantized first, which snaps the selection's edges to that
  /// grid; `track` and `free` take the cell the point lies in.
  final BoardSnap snap;

  /// Depth, in logical pixels, of the zone inside each edge of the
  /// scrolled region where a range drag's pointer scrolls the board toward
  /// that edge, extending the range as the cells arrive; zero turns it
  /// off. The same measure as [BoardDragConfig.autoScrollEdgeZone].
  final double autoScrollEdgeZone;

  /// Scroll speed, in logical pixels per second, with a range drag's
  /// pointer at the edge itself; it ramps linearly from zero at the zone's
  /// inner edge.
  final double autoScrollMaxVelocity;
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
  /// a dispatch exactly when `new == old`, and every dispatch that does
  /// get through asks each mounted host whether its own answer changed
  /// and relays the board out when a cell that built null is on screen.
  /// Without this, an equal-but-distinct write costs all of that for
  /// nothing.
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
