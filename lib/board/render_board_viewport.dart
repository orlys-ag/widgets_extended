/// The board's L3 render object: a two-axis viewport that lays out one
/// child per lattice CELL, sizes content-sized tracks from what those
/// cells measure, and holds the scroll anchor still while it does.
///
/// It reads the animation coordinator throughout: the tick router decides
/// per dispatch whether a tick lays out or only paints, the animated
/// geometry reads answer what a track and an item PAINT while a resize is
/// in flight, and the item paint pass composes the per-item offset.
/// RETENTION IS OBTAINING, never keep-alive: an exiting item's child and
/// the drag pin's are obtained on every layout, and nothing here writes
/// `parentData.keepAlive`.
///
/// COORDINATE SPACES. Three, and
/// mixing them is invisible at scroll offset 0:
///
/// - TRACK space: `(row, col)` plus a fraction into a track.
/// - BOARD CONTENT space: pixels along one axis from that axis's LEADING
///   edge, which is what `BoardAxis.offsetOf` returns. NORMALIZED, meaning
///   axis reversal is NOT applied.
/// - VIEWPORT PAINT space: content space minus that axis's
///   `ViewportOffset.pixels`, with reversal applied.
///
/// `TwoDimensionalViewportParentData.layoutOffset` is written in
/// NORMALIZED content-minus-scroll space, because
/// `computeAbsolutePaintOffsetFor`
/// (`widgets/two_dimensional_viewport.dart:1626`) is what applies
/// reversal. Every `Offset` and `Rect` on `BoardRenderPort` is viewport
/// paint space, so those members apply it themselves.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '_board_axis.dart';
import '_board_span.dart';
import 'board_animation_style.dart';
import 'board_background.dart';
import 'board_controller.dart';
import 'board_render_port.dart';

/// The render object behind `Board`.
///
/// ONE type parameter: layout never reads an item's payload, so the
/// controller is held key-only as `BoardController<TKey, Object?>`, which
/// is the shape `tree_reorder_controller.dart:92` uses for the same
/// reason. The typed `TItem` view stays in the delegate, which `Board`'s
/// `State` owns.
class RenderBoardViewport<TKey> extends RenderTwoDimensionalViewport
    implements BoardRenderPort<TKey>, BoardGeometryView {
  /// Creates a board viewport driven by [controller].
  ///
  /// The seven `super.` parameters are `RenderTwoDimensionalViewport`'s
  /// seven required ones (`widgets/two_dimensional_viewport.dart:535`)
  /// forwarded unchanged. `scrollCacheExtent` is deliberately absent: the
  /// base declares it optional, and the inherited getter, backing field
  /// and setter survive untouched, so a caller holding a
  /// [RenderBoardViewport] can still set one.
  RenderBoardViewport({
    required BoardController<TKey, Object?> controller,
    required BoardBackgroundPainter? background,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    required super.childManager,
    super.clipBehavior,
  }) : _controller = controller,
       _background = background;

  /// Consecutive STAGNANT placement passes one `layoutChildSequence`
  /// may run before it gives up: passes that neither settled nor measured
  /// a previously unmeasured track. A pass that measures IS the
  /// termination argument working and resets this; such passes are
  /// bounded by the track count, and a far jump onto a heavily
  /// mis-estimated band legitimately needs more than any small constant
  /// of them, because every correction and clamp relocates the window.
  /// Reaching the cap reports that the argument failed: an extent
  /// oscillating between passes of one layout.
  static const int _maxCorrectionPasses = 5;

  /// Whether the current placement pass recorded a FIRST measurement.
  /// Written by the sizing sweep, read by the loop's stagnation counter.
  bool _passMeasuredNewTrack = false;

  BoardController<TKey, Object?> _controller;

  BoardBackgroundPainter? _background;

  /// The background painter, run as the FIRST paint pass. It costs no
  /// render children: [paint] calls it directly on the canvas.
  BoardBackgroundPainter? get background {
    return _background;
  }

  /// Repaints when the painter appears, disappears, changes type, or
  /// reports [BoardBackgroundPainter.shouldRepaint] against the old one.
  set background(BoardBackgroundPainter? value) {
    if (identical(value, _background)) {
      return;
    }
    final old = _background;
    _background = value;
    if (value == null ||
        old == null ||
        value.runtimeType != old.runtimeType ||
        value.shouldRepaint(old)) {
      markNeedsPaint();
    }
  }

  /// The controller this render object lays out.
  BoardController<TKey, Object?> get controller {
    return _controller;
  }

  /// Swaps the controller. The single re-bind site.
  ///
  /// Unsubscribes from the old controller, subscribes to the new one when
  /// attached, drops every content-axis measurement and dirties layout.
  /// It deliberately does NOT clear the retention map: the first layout
  /// after the swap releases every entry through the head release, whose
  /// reads the new controller's reader answers false.
  set controller(BoardController<TKey, Object?> value) {
    if (identical(value, _controller)) {
      return;
    }
    final wasSubscribed = _subscribed;
    if (wasSubscribed) {
      _unsubscribe();
    }
    _controller = value;
    if (wasSubscribed) {
      _subscribe();
    }
    _resetMeasurements();
    // The reset above rewrote the new controller's settled extents, and
    // its animator's shift prefix may have captured the old ones: an
    // axis INSTANCE can be shared between two controllers, which is the
    // construction the swap case in `board_lifecycle_test.dart` builds.
    value.invalidateAnimatedShifts();
    markNeedsLayout();
  }

  /// Debug-only: corrections applied across this render object's life.
  ///
  /// Justified against asserting on the painted anchor alone, which is the
  /// correctness assertion and is made separately, but which cannot tell
  /// an implementation that never corrects from one that does.
  int debugCorrectionCount = 0;

  /// Debug-only: layouts this render object has performed. A paint-only
  /// tick is pinned on it staying flat; a settle that must still lay out
  /// is pinned on it advancing.
  int debugPerformLayoutCount = 0;

  /// Debug-only: successful slide installs, read through the controller
  /// where the engine lives.
  int get debugSlideInstallCount {
    return _controller.debugSlideInstallCount;
  }

  /// Debug-only: placement passes the LAST `layoutChildSequence` needed.
  /// 1 means no correction was required.
  ///
  /// A LAST-VALUE field, not a maximum, which is why a case that reads it
  /// has to script a sweep and take the worst rather than read it once.
  /// Promoted from the kept trial probe's `debugLastPassCount`, whose
  /// meaning it keeps verbatim.
  int debugLastCorrectionPassCount = 0;

  /// Vicinities already obtained during the CURRENT `layoutChildSequence`.
  ///
  /// Cleared ONCE at `layoutChildSequence` entry and never per pass:
  /// `buildOrObtainChildFor` is not idempotent within a pass, and for an
  /// already-built vicinity it routes to `_reuseChild`
  /// (`widgets/two_dimensional_viewport.dart:1496`), which removes the
  /// element from the old map and asserts it was still there
  /// (`widgets/two_dimensional_viewport.dart:373`). Serving a repeat from
  /// `getChildFor` (`widgets/two_dimensional_viewport.dart:901`) keeps the
  /// bookkeeping the first call performed, because
  /// `_activeChildrenForLayoutPass` is cleared only at `performLayout`
  /// entry (`widgets/two_dimensional_viewport.dart:1332`).
  final Set<ChildVicinity> _obtainedThisLayout = <ChildVicinity>{};

  /// The PER-AXIS animation magnitudes the last layout WIDENED its
  /// obtain window by, and recorded: a slide's lead composed with the
  /// held make-room offsets, and its extent where that reaches further.
  ///
  /// The widen and the record are one statement site, in
  /// [layoutChildSequence]; written without the widening half the gate
  /// that reads it can never fire. Its reader is the bound comparison in
  /// [_handleAnimationTick] below. Magnitudes, so numerically identical
  /// in content and viewport paint space.
  ({double dx, double dy}) _admittedOffsetBound = (dx: 0.0, dy: 0.0);

  /// Resolved extents, keyed by CONTENT-axis track, for the pass that is
  /// running. Cleared at the head of every pass; a field rather than a
  /// local so a pass allocates nothing.
  final Map<int, double> _contentTrackExtents = <int, double>{};

  /// The cross index of the cell each [_contentTrackExtents] entry came
  /// from, parallel to it and cleared with it.
  final Map<int, int> _contentTrackArgMax = <int, int>{};

  /// Per CONTENT track, the tallest CELL measurement taken since this
  /// record was last dropped, and the cross index of the cell it came
  /// from.
  ///
  /// A pass obtains only the cross axis's window, so without it a tall
  /// cell scrolled out sideways would shrink its track, and everything
  /// past the track would move while the user scrolls the other way. The
  /// sizing step takes the larger of a track's window maximum and this,
  /// and a pass that measures the recorded cell again, or finds it
  /// building nothing, REPLACES the record with its window's, so a cell
  /// that shrinks in view lowers its track. One entry per track, not per
  /// cell: where the recorded cell shrinks in view while a cell taller
  /// than the window's sits out of view, the track falls back to the
  /// window until that cell returns, the price of memory that does not
  /// grow with every cell ever visited.
  ///
  /// Valid for the cell content and the measuring constraints it was
  /// taken under: dropped by [invalidateCellMeasurements], by
  /// [_resetMeasurements], and when [_cellRecordKey] changes.
  final Map<int, ({double extent, int cross})> _cellRecord =
      <int, ({double extent, int cross})>{};

  /// The tracks whose recorded cell the running pass measured again or
  /// found building nothing. Cleared at the head of every pass.
  final Set<int> _recordRemeasured = <int>{};

  /// The axis instances and alignments [_cellRecord] was measured under:
  /// a measurement depends on its cell's content and on the measuring
  /// constraints, which are a function of these (see
  /// [_measuringConstraints]).
  Object? _cellRecordKey;

  /// The item a drag session holds, or null when no session is live. At
  /// most one, because at most one session is live.
  ///
  /// Written only by [pinItem] and [unpinItem], which a drag session calls
  /// at its start and in its single teardown. What CONSUMES it is
  /// [_obtainRetained], which re-derives the key's vicinity from its id's
  /// CURRENT ordinal on every layout and obtains it, so a rank shift
  /// under a live drag cannot strand the pin on a stale vicinity; an item
  /// an axis swap left outside the lattice is simply not obtained.
  TKey? _pinnedDragKey;

  /// Vicinity of every child retained for an exit animation, to the
  /// exiting item id that caused it. RETENTION IS OBTAINING: every entry
  /// is obtained on every layout, which keeps its element mounted
  /// through the ordinary active-child path, and RELEASE is ceasing to
  /// obtain, after which the next layout unmounts it through the same
  /// path every unused child takes. Nothing here ever writes
  /// `parentData.keepAlive`: a child flagged into the base's keep-alive
  /// bucket while also live in its children map is detached TWICE by the
  /// base's `detach`, which is a debug crash on any teardown or
  /// GlobalKey move. Entries are dropped by the sweep's release case;
  /// the MAP is cleared only by [dispose].
  final Map<ChildVicinity, int> _retainedExits = <ChildVicinity, int>{};

  /// Content-axis tracks whose settled extent the last sizing step wrote
  /// from an enter/exit RAMP rather than a settled measurement: the
  /// latch that makes the ramp's end record once without installing a
  /// resize for its own last tick.
  final Set<int> _rampWroteRows = <int>{};
  final Set<int> _rampWroteCols = <int>{};

  /// Content-axis tracks whose settled extent the last sizing step wrote
  /// from a MAKE-ROOM contribution, an offset's or a slot's alike. The
  /// hand-off arm does not ask which kind vanished: a snap hands both
  /// kinds on to the same published clock.
  final Set<int> _makeRoomWroteRows = <int>{};
  final Set<int> _makeRoomWroteCols = <int>{};

  /// The engine generations the last layout ran against, recorded at the
  /// END of `layoutChildSequence` so every pass of one layout compares
  /// against the same values.
  int _laidOutMakeRoomGeneration = 0;
  int _laidOutSnapGeneration = 0;

  /// The window's first track per axis, from the last obtain walk: the
  /// animated accumulation anchors THERE at its settled offset, which is
  /// what keeps a resize before the window invisible.
  int _shiftFloorRow = 0;
  int _shiftFloorCol = 0;

  /// The three prior-tick mirrors of the animation-listener routing: a
  /// settle tick reads idle on every level, so only the prior tick's
  /// levels can route it to the one layout that reads the settled state.
  bool _priorTickHadLayoutDriving = false;
  bool _priorTickHadOffsets = false;
  bool _priorTickHadExtent = false;

  /// Whether `layoutChildSequence` is running, written by it alone. Read
  /// by the cell surface's poke, which dirties layout outside one and
  /// sets its flag alone inside one, and by [invalidateCellMeasurements],
  /// which asserts on it.
  bool _inLayout = false;

  /// Opt-in staleness check for the cell measurement cache, off by
  /// default. When true, every layout re-measures every cell whose cached
  /// extent it would otherwise use and reports, through
  /// [FlutterError.reportError], one [FlutterError] naming every cell
  /// whose extent moved. It reads and never writes the cache, so a
  /// debug build with it on shows the same geometry as a release build.
  /// A cell whose content animates its own size trips it on every frame
  /// of that animation by design, which is why it is a diagnostic to turn
  /// on when tracks look wrong and not a guard to leave on.
  /// While a staleness persists the report repeats on every layout,
  /// because the check heals nothing.
  static bool debugCheckCellMeasurements = false;

  /// The stale cells [debugCheckCellMeasurements] found this layout, one
  /// entry per cell, reported ONCE at the end of the pass loop and
  /// cleared there. Debug-only; null in release.
  List<String>? _debugStaleCells;

  /// The content tracks holding an intra-track item cluster with no lane
  /// axis this layout, reported ONCE at the end of the pass loop and
  /// cleared there, for the reason the stale-cell report gives.
  /// Debug-only; null in release.
  Set<int>? _debugClusterTracks;

  /// Cell vicinities the LAST layout obtained whose builder returned
  /// null, written once per layout by the positioning sweep.
  ///
  /// The gate on the selection and item-data handlers. A cell that built
  /// null holds no element and therefore no host, so neither relay can
  /// reach its builder and the only way it is ever asked again is a
  /// layout that obtains it; `buildOrObtainChildFor` rebuilds a vicinity
  /// holding no child on every layout that obtains it
  /// (`widgets/two_dimensional_viewport.dart:1490`). Above zero the two
  /// handlers relayout as they always did; at zero they do not, because
  /// every mounted child that can change reaches its builder through its
  /// own host.
  ///
  /// ITEM vicinities that built null are deliberately not counted: the
  /// item arm of the delegate's builder returns null for a null
  /// `itemBuilder`, a missing ordinal, a released id and a null payload,
  /// and none of the four reads the selection or a payload's contents,
  /// so no dispatch on either channel can change its answer.
  int _nullCellCount = 0;

  bool _subscribed = false;

  /// The bottom plane: cells in unfrozen tracks. Cleared and rebuilt exactly
  /// once per `layoutChildSequence`, in the final positioning sweep, never
  /// per pass: appended per pass, a vicinity obtained by two passes paints
  /// twice; cleared per pass, a pass-1-only child drops out of paint AND
  /// its hit-test mirror.
  final List<RenderBox> _cellPaintOrder = <RenderBox>[];

  /// Items, in three planes one after another: the SCROLLED items, then
  /// the BAND items (pinned on one axis) from [_bandItemStart], then the
  /// CORNER items (pinned on both) from [_cornerItemStart]. Inside a plane,
  /// laned items by lane then id and non-laned items last, so they paint
  /// above the laned stack in their track.
  final List<RenderBox> _itemPaintOrder = <RenderBox>[];
  int _bandItemStart = 0;
  int _cornerItemStart = 0;

  /// Cells in frozen tracks: the BAND cells (frozen on one axis), then
  /// the CORNER cells (frozen on both) from [_cornerCellStart]. The
  /// corner must outpaint the two bands because a band cell scrolled
  /// along its unfrozen axis can slide into the corner rectangle.
  ///
  /// The six planes, bottom to top: scrolled cells, scrolled items, band
  /// cells, band items, corner cells, corner items. A band item overlaps
  /// only its own band's cells, which it must cover, and corner cells,
  /// which must cover it, so the order is total; hit-testing and
  /// [itemAt] walk its exact reverse.
  final List<RenderBox> _frozenPaintOrder = <RenderBox>[];
  int _cornerCellStart = 0;

  /// Item child back to its store id, for the paint-time animation shift
  /// and for [applyPaintTransform]'s mirror of it. Rebuilt in the same
  /// sweep as the paint lists.
  final Map<ChildVicinity, int> _vicinityToItemId = <ChildVicinity, int>{};

  /// The painted rect of each entry of [_itemPaintOrder], parallel to it,
  /// filled ONCE at the head of every [paint] and read by the clip
  /// decision and the item paint pass.
  ///
  /// A field rather than a local so a paint allocates nothing, and
  /// scoped to one `paint` call rather than to a layout: an item's
  /// painted rect moves on paint-only ticks, so hit-testing and [itemAt]
  /// evaluate live and never read this.
  final List<Rect> _itemPaintRects = <Rect>[];

  /// Whether the last sweep positioned any child extending outside the
  /// viewport box, which is what gates the paint clip. The base class
  /// keeps its own private equivalent that only its own `paint` reads;
  /// overriding `paint` means owning both the flag and the clip layer.
  bool _hasVisualOverflow = false;

  final LayerHandle<ClipRectLayer> _clipRectLayer =
      LayerHandle<ClipRectLayer>();

  int _firstVisibleRow = 0;
  int _lastVisibleRow = -1;
  int _firstVisibleCol = 0;
  int _lastVisibleCol = -1;

  /// First SCROLLED row track showing in [scrolledRegion], the viewport
  /// minus its frozen bands. The four window bounds are overwritten once
  /// per `layoutChildSequence`, from the settling pass's window, and
  /// describe what is VISIBLE rather than the wider obtain window: a
  /// track wholly under a band is left out, and a frozen track is
  /// reported by [frozenTracksOf] instead. An axis with nothing visible
  /// reports `first` 0 and `last` -1.
  @override
  int get firstVisibleRow {
    return _firstVisibleRow;
  }

  /// Last SCROLLED row track showing in [scrolledRegion]. See
  /// [firstVisibleRow].
  @override
  int get lastVisibleRow {
    return _lastVisibleRow;
  }

  /// First SCROLLED column track showing in [scrolledRegion]. See
  /// [firstVisibleRow].
  @override
  int get firstVisibleCol {
    return _firstVisibleCol;
  }

  /// Last SCROLLED column track showing in [scrolledRegion]. See
  /// [firstVisibleRow].
  @override
  int get lastVisibleCol {
    return _lastVisibleCol;
  }

  // -----------------------------------------------------------------
  // Lifecycle: the subscribe, unsubscribe and port-registration sites.
  // -----------------------------------------------------------------

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _subscribe();
  }

  @override
  void detach() {
    super.detach();
    _unsubscribe();
  }

  /// Subscribes to the controller's three channels and its selection
  /// notifier, and registers this render object as its port. Idempotent, because a `GlobalKey` move
  /// detaches and reattaches.
  ///
  /// Subscriber and actor are the same object: every one of the three
  /// callbacks does render-object work, which is why this lives here and
  /// not on `Board`'s `State`.
  void _subscribe() {
    if (_subscribed) {
      return;
    }
    _subscribed = true;
    _controller.addStructuralListener(_handleStructuralChange);
    _controller.addItemDataListener(_handleItemDataChange);
    _controller.addAnimationListener(_handleAnimationTick);
    _controller.selection.addListener(_handleSelectionChanged);
    _controller.attachRenderPort(this);
  }

  /// The single unsubscribe site. Idempotent for the same reason.
  void _unsubscribe() {
    if (!_subscribed) {
      return;
    }
    _subscribed = false;
    _controller.removeStructuralListener(_handleStructuralChange);
    _controller.removeItemDataListener(_handleItemDataChange);
    _controller.removeAnimationListener(_handleAnimationTick);
    _controller.selection.removeListener(_handleSelectionChanged);
    _controller.detachRenderPort(this);
  }

  /// A selection change. A MOUNTED cell or item rebuilds through its host
  /// in the widget layer, which the `Board` state's relay reaches, and
  /// nothing in layout reads the selection, so a mounted child needs no
  /// delegate rebuild.
  ///
  /// The relayout is for a cell whose builder returned NULL: it holds no
  /// child, so no host and no relay reach it, and
  /// `buildOrObtainChildFor` rebuilds a vicinity holding no child on
  /// every layout that obtains it
  /// (`widgets/two_dimensional_viewport.dart:1490`), which is the cost
  /// such a cell already pays per scroll. It is GATED on there being
  /// one: a board with none has nothing here that a layout would
  /// discover, and in range selection this handler fires once per cell
  /// the pointer crosses.
  ///
  /// Re-measurement is NOT a reason to relayout here. A cell whose
  /// height depends on the selection rebuilds through its host, and that
  /// rebuild pokes its measurement surface, which schedules the layout
  /// itself; see [_requestRemeasure].
  void _handleSelectionChanged() {
    if (_nullCellCount > 0) {
      markNeedsLayout();
    }
  }

  /// A structural change relays out, and rebuilds every obtained child
  /// unless no built child's builder output changed.
  ///
  /// Null and a non-empty set both take the delegate rebuild, which is the
  /// only route to a child's builder the viewport's private element leaves
  /// open (R-7). An EMPTY set says no ITEM's rendered inputs changed, and
  /// takes the cheaper route unless [_builtVicinityChangedOwner]: the key
  /// set speaks of items, and the vicinity a child is built at is this
  /// object's scheme, not the controller's.
  void _handleStructuralChange(Set<TKey>? affectedKeys) {
    markNeedsLayout(
      withDelegateRebuild:
          affectedKeys == null ||
          affectedKeys.isNotEmpty ||
          _builtVicinityChangedOwner(),
    );
  }

  /// Whether an item vicinity the last layout built now resolves, through
  /// the lookup the delegate's builder uses, to a DIFFERENT item.
  ///
  /// A removal shifts every later item on its primary start track down
  /// one ordinal, and notifies an empty set, since no remaining item's
  /// inputs changed. Without a delegate rebuild the base REUSES the child
  /// already at a vicinity (`widgets/two_dimensional_viewport.dart:1489`),
  /// so the item shifting into the removed one's vicinity would be shown
  /// by the removed one's element, and its own element, obtained by
  /// nobody, unmounted. A vicinity that now resolves to NO item is not a
  /// remap: nothing obtains it again. [_vicinityToItemId] is the record,
  /// written by every item obtain, the retained exits' and the drag
  /// pin's included, and the lookups are total, so a record made for a
  /// swapped-out controller answers without throwing (a swap through
  /// `Board` replaces the delegate, which rebuilds regardless).
  bool _builtVicinityChangedOwner() {
    final columnCount = _controller.columns.axis.trackCount;
    for (final entry in _vicinityToItemId.entries) {
      final owner = _controller.itemIdAtOrdinal(
        entry.key.yIndex,
        entry.key.xIndex - columnCount,
      );
      if (owner >= 0 && owner != entry.value) {
        return true;
      }
    }
    return false;
  }

  /// A payload-only write. The item's host and the hosts of the cells its
  /// span covers rebuild through the `Board` state's relay.
  ///
  /// The relayout is for a cell that built NULL and so has no host, and
  /// is gated on there being one, for the reason
  /// [_handleSelectionChanged] gives. Re-measurement is not a reason
  /// either: a payload that changes a cell's intrinsic size does so
  /// through that cell's builder, whose host's rebuild pokes the
  /// measurement surface.
  void _handleItemDataChange(TKey key) {
    if (_nullCellCount > 0) {
      markNeedsLayout();
    }
  }

  /// An animation tick.
  ///
  /// The five-branch routing. The callback carries no payload, so the
  /// discriminators are the level reads plus the two prior-tick mirrors,
  /// written unconditionally at the bottom so a tick that matches no
  /// branch still advances them.
  ///
  /// 1. Layout-driving now OR on the prior tick: relayout. The flag is
  ///    the COMPOSED one, the coordinator's layout-driving union widened
  ///    by make-room motion and by relane slides ON A CONTENT-SIZED LANE
  ///    AXIS, where a gap or a re-laned neighbour moves a track's
  ///    extent. A relane slide is lead-only there, so without the
  ///    disjunct it would take arm 4 while the sizing step, which runs
  ///    only inside layout, read its lead at the install layout and the
  ///    settle layout alone: the track's edge would hold and pop. The
  ///    prior-tick disjunct IS the latch: a settle tick's record is
  ///    already gone, and this is the one layout that reads the settled
  ///    extent and progress.
  /// 2. The make-room generation moved, on a content-sized lane axis or
  ///    on any board holding a held EXTENT preview: relayout. A
  ///    SNAPPED slot-only install carries no motion and displaces
  ///    nobody, so no other arm can fire for it, and the same arm
  ///    carries that gap's close; a settled extent preview's re-target
  ///    is the other case with no motion to route it.
  /// 3. Offsets just went idle: one relayout, to re-narrow the window
  ///    the admitted bound widened.
  /// 4. A held extent just VANISHED WITHOUT MOTION: one relayout, to
  ///    return every child laid out at a previewed size to its
  ///    structural one. The commit snap clears the extents before it
  ///    notifies, so arm 2 cannot see them, and a settled preview has
  ///    no motion for arm 1's latch; when the report mutates, the
  ///    mutation's own layout covers this, and when it declines or
  ///    mutates nothing, this arm is the one route.
  /// 5. Offsets active: relayout only past the admitted bound, repaint
  ///    otherwise.
  /// 6. Otherwise nothing.
  ///
  /// On a FIXED lane axis this router never CLASSIFIES make-room OFFSET
  /// or SLOT motion as layout-driving; a held EXTENT in motion is
  /// layout-driving on every axis, through the coordinator's union. That
  /// is a claim about the classification and not about every make-room
  /// tick: a gap that displaces a neighbour still lays out through the
  /// admitted-bound arm, because a held offset ramping up exceeds the
  /// bound the last layout recorded.
  void _handleAnimationTick() {
    final anim = _controller.anim;
    final contentAxis = _contentAxis;
    final laneAxisIsContent =
        contentAxis != null && _controller.laneAxis == contentAxis;
    final hasLayoutDriving =
        anim.hasLayoutDrivingAnimations ||
        (laneAxisIsContent && (anim.hasMakeRoomMotion || anim.hasRelaneActive));
    final hasOffsets = anim.hasActiveOffsets;
    if (hasLayoutDriving || _priorTickHadLayoutDriving) {
      markNeedsLayout();
    } else if ((laneAxisIsContent || anim.hasMakeRoomExtent) &&
        anim.makeRoomGeneration != _laidOutMakeRoomGeneration) {
      markNeedsLayout();
    } else if (_priorTickHadOffsets && !hasOffsets) {
      markNeedsLayout();
    } else if (_priorTickHadExtent && !anim.hasMakeRoomExtent) {
      markNeedsLayout();
    } else if (hasOffsets) {
      final bound = anim.composedOffsetBound;
      if (bound.dx > _admittedOffsetBound.dx ||
          bound.dy > _admittedOffsetBound.dy) {
        markNeedsLayout();
      } else {
        markNeedsPaint();
      }
    }
    _priorTickHadLayoutDriving = hasLayoutDriving;
    _priorTickHadOffsets = hasOffsets;
    _priorTickHadExtent = anim.hasMakeRoomExtent;
  }

  /// Every child of this viewport carries a [_BoardChildParentData], so
  /// the measurement cache has somewhere to live.
  ///
  /// The base's own override installs a plain
  /// `TwoDimensionalViewportParentData`
  /// (`widgets/two_dimensional_viewport.dart:870`) and its `parentDataOf`
  /// is documented to accept a subclass of it
  /// (`widgets/two_dimensional_viewport.dart:880`), which is what makes
  /// widening it here legal rather than a side channel.
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BoardChildParentData) {
      child.parentData = _BoardChildParentData();
    }
  }

  /// The viewport half of a cell surface's poke: mark the cell for
  /// re-measurement, and schedule the layout that will do it.
  ///
  /// [top] is the child this viewport holds, which the surface found by
  /// walking its own ancestry. TWO ARMS, and the discriminator is
  /// whether a layout is running:
  ///
  /// - Outside one, the flag alone would sit unread until something else
  ///   laid this object out, which after the channel handlers stopped
  ///   relaying out may be never. So it also dirties layout.
  /// - Inside one, the poke came from a delegate rebuild running in
  ///   `buildOrObtainChildFor`, and the measure step reads the flag
  ///   later in the same pass, so the flag alone is enough. Dirtying
  ///   from inside a layout would be a re-entrant mark of a node already
  ///   being laid out.
  ///
  /// A board with no content axis returns at once: nothing there is
  /// measured, so a rebuild has nothing to re-measure and a fixed board
  /// pays nothing at all for this mechanism.
  void _requestRemeasure(RenderBox top) {
    if (_contentAxis == null) {
      return;
    }
    final data = top.parentData;
    if (data is! _BoardChildParentData) {
      return;
    }
    data.remeasure = true;
    if (!_inLayout) {
      markNeedsLayout();
    }
  }

  /// The whole-board arm of the cell measurement cache's invalidation:
  /// sets every mounted child's `remeasure` flag and dirties layout. The
  /// port member `BoardController.invalidateCellMeasurements` forwards
  /// to.
  ///
  /// `visitChildren` walks the sibling chain and then the keep-alive
  /// bucket (`widgets/two_dimensional_viewport.dart:940`); this board
  /// writes no `keepAlive`, so the walk is the set the last layout
  /// reified. An item child gets the flag too, inertly: the flag's one
  /// reader is the cell measure step, which an item never reaches.
  ///
  /// Asserts outside a layout. Inside one the call would be SILENT
  /// rather than loud: a layout callback is a context the framework's
  /// mutation guard permits (`rendering/object.dart:2342`), and
  /// `markNeedsLayout` returns early while `_needsLayout` is true
  /// (`rendering/object.dart:2662`), which it is for the whole of
  /// `performLayout`, so the request would be dropped.
  @override
  void invalidateCellMeasurements() {
    assert(
      !_inLayout,
      "invalidateCellMeasurements was called during the board's layout, "
      "which drops the request silently. Call it from an event handler, "
      "a post-frame callback, or the build phase, not from a cell or "
      "item builder or from the first build of a cell's content.",
    );
    visitChildren((child) {
      final data = child.parentData;
      if (data is _BoardChildParentData) {
        data.remeasure = true;
      }
    });
    // A cell out of view has no child to flag, and the app says content
    // changed: its recorded measurement goes too.
    _cellRecord.clear();
    markNeedsLayout();
  }

  /// The measurement half of a controller swap's reset: extents measured
  /// against one item set are not evidence about another, so a swap drops
  /// every measurement on the axes it is about to lay out.
  ///
  /// The animation half arrives with the coordinator; the span index and
  /// the lane assignments belong to the controller, and a freshly
  /// assigned controller carries its own.
  void _resetMeasurements() {
    _cellRecord.clear();
    final rowAxis = _controller.rows.axis;
    if (rowAxis is LazyContentAxis) {
      rowAxis.resetMeasurements();
    }
    final columnAxis = _controller.columns.axis;
    if (columnAxis is LazyContentAxis) {
      columnAxis.resetMeasurements();
    }
  }

  // -----------------------------------------------------------------
  // Layout.
  // -----------------------------------------------------------------

  @override
  void performLayout() {
    debugPerformLayoutCount += 1;
    super.performLayout();
  }

  @override
  void layoutChildSequence() {
    // The one writer of the in-layout flag. Its reader is the cell
    // surface's poke, which takes the flag-only arm inside a layout
    // because the measure step has not yet read the flag it sets.
    _inLayout = true;
    _paintListsCurrent = false;
    try {
      _layoutChildSequenceBody();
      _paintListsCurrent = true;
    } finally {
      _inLayout = false;
    }
  }

  /// Whether the paint lists hold exactly the children of the last
  /// layout. False from the start of a `layoutChildSequence` until its
  /// body returns: a layout that THROWS leaves the lists from the sweep
  /// before it while the base, which rebuilds its sibling chain only
  /// after this method returns, leaves that chain empty. The semantics
  /// walk defers to the base's while this is false.
  bool _paintListsCurrent = false;

  /// The controller and the two axis configs the last layout ran with,
  /// which [_anchorSwappedAxes] compares the next layout's against.
  BoardController<TKey, Object?>? _laidOutController;
  BoardAxisConfig? _laidOutRows;
  BoardAxisConfig? _laidOutColumns;

  /// A NEW AXIS under the same controller, a zoom for instance, keeps the
  /// scrolled region's leading edge on the same place in the lattice: the
  /// track-space coordinate there under the old config is put there under
  /// the new one, by a `correctBy` the pass loop's `applyContentDimensions`
  /// then settles, as it settles the content axis's corrections. Not on a
  /// controller swap, a new model rather than a zoom, and not for a config
  /// that keeps its axis instance.
  void _anchorSwappedAxes() {
    final rows = _controller.rows;
    final columns = _controller.columns;
    if (identical(_laidOutController, _controller)) {
      final oldRows = _laidOutRows;
      if (oldRows != null && !identical(oldRows.axis, rows.axis)) {
        _anchorSwappedAxis(
          verticalOffset,
          oldRows,
          rows,
          viewportDimension.height,
        );
      }
      final oldColumns = _laidOutColumns;
      if (oldColumns != null && !identical(oldColumns.axis, columns.axis)) {
        _anchorSwappedAxis(
          horizontalOffset,
          oldColumns,
          columns,
          viewportDimension.width,
        );
      }
    }
    _laidOutController = _controller;
    _laidOutRows = rows;
    _laidOutColumns = columns;
  }

  /// Content space throughout, the offset plus the leading band, which is
  /// direction agnostic: the band sits at the content's leading edge
  /// whichever way the axis paints. The target is clamped into the new
  /// axis's scroll range, the one [_applyContentDimensions] applies, so a
  /// lattice that shrank past the anchor ends scrolled to its end.
  void _anchorSwappedAxis(
    ViewportOffset offset,
    BoardAxisConfig old,
    BoardAxisConfig next,
    double viewportExtent,
  ) {
    final oldAxis = old.axis;
    final newAxis = next.axis;
    if (!offset.hasPixels ||
        oldAxis.trackCount == 0 ||
        newAxis.trackCount == 0) {
      return;
    }
    final oldBand = old.leadingBandExtent;
    final newBand = next.leadingBandExtent;
    final content = offset.pixels + oldBand;
    final track = oldAxis.trackAt(content);
    final extent = oldAxis.extentOf(track);
    final into = extent > 0.0
        ? ((content - oldAxis.offsetOf(track)) / extent).clamp(0.0, 1.0)
        : 0.0;
    final anchor = (track + into).clamp(0.0, newAxis.trackCount.toDouble());
    final target = (newAxis.offsetOfFraction(anchor) - newBand).clamp(
      0.0,
      math.max(0.0, newAxis.totalExtent - viewportExtent),
    );
    final correction = target - offset.pixels;
    if (correction.abs() >= precisionErrorTolerance) {
      offset.correctBy(correction);
    }
  }

  void _layoutChildSequenceBody() {
    _anchorSwappedAxes();
    _obtainedThisLayout.clear();
    _builtNothing.clear();
    // Cleared at ENTRY, not in the sweep: the item OBTAIN writes it and
    // the sweep, the paint walks and applyPaintTransform read it.
    _vicinityToItemId.clear();
    // ARM 1 of the lane flush: resolution precedes track sizing, so the
    // cluster term below never reads a stale laneCount.
    _controller.flushLanesForLayout();
    final recordKey = (
      _controller.rows.axis,
      _controller.columns.axis,
      _controller.rows.alignment,
      _controller.columns.alignment,
    );
    if (recordKey != _cellRecordKey) {
      _cellRecord.clear();
      _cellRecordKey = recordKey;
    }

    // The WINDOW RULE's two terms, read ONCE per `layoutChildSequence`.
    // Both are per-axis content-space magnitudes.
    final cache = _resolveCacheTerms();
    final bound = _composedOffsetBound();
    // The widen-and-record PAIR: the same numbers the obtain window is
    // widened by are recorded here, in the same statement site.
    _admittedOffsetBound = bound;
    final inset = (dx: cache.dx + bound.dx, dy: cache.dy + bound.dy);

    var passes = 0;
    var stagnantPasses = 0;
    var settled = false;
    while (true) {
      passes += 1;
      _passMeasuredNewTrack = false;
      final correction = _obtainMeasureAndSize(inset);
      if (correction.abs() >= precisionErrorTolerance) {
        // Content space, on the content-sized axis. Only that axis can
        // measure, so only that axis can drift.
        _contentViewportOffset!.correctBy(correction);
        debugCorrectionCount += 1;
      } else if (_applyContentDimensions()) {
        settled = true;
      }
      if (settled) {
        break;
      }
      if (_passMeasuredNewTrack) {
        stagnantPasses = 0;
      } else {
        stagnantPasses += 1;
        if (stagnantPasses >= _maxCorrectionPasses) {
          break;
        }
      }
    }
    debugLastCorrectionPassCount = passes;
    assert(() {
      final stale = _debugStaleCells;
      if (stale == null || stale.isEmpty) {
        return true;
      }
      _debugStaleCells = null;
      // REPORTED, not thrown, and ONCE per layout. The base runs
      // `layoutChildSequence`, which calls this method, between its child
      // manager's `_startLayout` and `_endLayout`: `_buildChild` and
      // `_reuseChild` file every child the pass claims in the element's
      // pending maps, and only `_endLayout` swaps them in. A throw from
      // inside `layoutChildSequence` skips `_endLayout`, which leaves those
      // children unreachable from the element tree and the next layout's
      // `_startLayout` failing its assert. A report reaches the same handler
      // a throw would and leaves the pass to finish; one per layout, because
      // a stale app value usually leaves every mounted cell stale at once.
      FlutterError.reportError(
        FlutterErrorDetails(
          library: "widgets_extended board",
          context: ErrorDescription(
            "while checking the cell measurement cache",
          ),
          exception: FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary(
              "${stale.length} cell(s) measure differently from their "
              "cached measurement on the content axis.",
            ),
            ErrorDescription(
              "A cell is measured when its host rebuilds and not "
              "otherwise; a widget the cell builder returned changed size "
              "without the host rebuilding, so its track kept the extent "
              "it had. Stale cells: ${stale.join("; ")}.",
            ),
            ErrorHint(
              "Call BoardController.invalidateCellMeasurements() after "
              "changing what the cell's content consumes, or rebuild the "
              "cell by writing the payload of an item covering it. "
              "RenderBoardViewport.debugCheckCellMeasurements is on, "
              "which is what reported this.",
            ),
          ]),
        ),
      );
      return true;
    }());
    assert(() {
      final tracks = _debugClusterTracks;
      if (tracks == null || tracks.isEmpty) {
        return true;
      }
      _debugClusterTracks = null;
      // Reported, not thrown, for the stale-cell report's reason; once
      // per layout and again on every layout while the data stands.
      FlutterError.reportError(
        FlutterErrorDetails(
          library: "widgets_extended board",
          context: ErrorDescription("while sizing the content-sized axis"),
          exception: FlutterError(
            "A content-sized axis holds an intra-track item cluster on "
            "track(s) ${(tracks.toList()..sort()).join(", ")} and no axis "
            "carries a laneExtent: the cluster can neither grow its track "
            "nor stack along the other axis. Give one axis's config a "
            "laneExtent, or keep items off the content axis.",
          ),
        ),
      );
      return true;
    }());

    if (!settled) {
      // At the ceiling, lay out at the last attempted offset. Both offsets
      // still need dimensions, or the frame paints against a position that
      // has none.
      _applyContentDimensions();
      // Reported, not thrown, for the stale-cell report's reason, so the
      // retention and positioning below still run. Once per layout that
      // reaches the ceiling.
      assert(() {
        FlutterError.reportError(
          FlutterErrorDetails(
            library: "widgets_extended board",
            context: ErrorDescription("while running the placement passes"),
            exception: FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary(
                "RenderBoardViewport ran $_maxCorrectionPasses consecutive "
                "STAGNANT placement passes without settling.",
              ),
              ErrorDescription(
                "A stagnant pass measures no previously unmeasured track "
                "and still does not settle. Reaching the ceiling means a "
                "track's resolved extent is moving between passes of ONE "
                "layout, or applyContentDimensions kept clamping the "
                "position with nothing left to measure.",
              ),
              ErrorHint(
                "A cap that is reached is a convergence defect, not a slow "
                "path. debugLastCorrectionPassCount reports the count and "
                "debugCorrectionCount the corrections applied.",
              ),
            ]),
            stack: StackTrace.current,
            informationCollector: () {
              final creator = debugCreator;
              return <DiagnosticsNode>[
                if (creator != null) DiagnosticsDebugCreator(creator),
                describeForError(
                  "The following RenderObject was being laid out when the "
                  "ceiling was reached",
                ),
              ];
            },
          ),
        );
        return true;
      }());
    }

    // Retention is obtaining: exit-retained vicinities and the drag
    // pin's stay active children wherever the window went, positioned at
    // their structural rects, which the base's per-child isVisible skip
    // keeps unpainted outside the viewport.
    _obtainRetained();
    // One positioning sweep over EVERY vicinity obtained during this
    // call, not over the final window: a correction moves the window, so a
    // child obtained by pass 1 can fall outside pass 2's range while still
    // being active for the frame.
    _positionObtainedChildren();
    _sweepRetention();
    // AFTER the pass loop, so every pass of one layout compared against
    // the same values.
    _laidOutMakeRoomGeneration = _controller.anim.makeRoomGeneration;
    _laidOutSnapGeneration = _controller.anim.makeRoomSnapGeneration;
  }

  void _obtainRetained() {
    final anim = _controller.anim;
    // Entries whose id settled release NOW, before the obtain, so the
    // frame the settle-scheduled layout runs is the frame the child
    // unmounts. An id whose span left the lattice releases too: an axis
    // swap can shrink the lattice under a retained exit, the laned
    // geometry arm reads the raw start track, and the window rule's own
    // promise is that an out-of-lattice span is never laid out.
    _retainedExits.removeWhere((vicinity, id) {
      return !anim.isExitingItem(id) || _outOfLattice(id);
    });
    if (_retainedExits.isNotEmpty) {
      // Re-key every entry to its id's CURRENT vicinity: a rank insert
      // on the exiting item's start track shifts its ordinal mid-exit,
      // and obtaining the recorded vicinity would build whatever item
      // holds that ordinal now, unmounting the exiting child and mapping
      // the new occupant's child to the exiting id. An exiting id keeps
      // its slot until settle, so both reads below are safe.
      final columnCount = _controller.columns.axis.trackCount;
      final rekeyed = <ChildVicinity, int>{};
      for (final id in _retainedExits.values) {
        final vicinity = ChildVicinity(
          xIndex: columnCount + _controller.vicinityOrdinalOfId(id),
          yIndex: _controller.primaryStartOfId(id),
        );
        rekeyed[vicinity] = id;
      }
      _retainedExits
        ..clear()
        ..addAll(rekeyed);
    }
    for (final entry in _retainedExits.entries) {
      final child = _obtainOnce(entry.key);
      if (child != null) {
        _vicinityToItemId[entry.key] = entry.value;
      }
    }
    final pinnedKey = _pinnedDragKey;
    if (pinnedKey != null) {
      final id = _controller.idOfKey(pinnedKey);
      // The same lattice guard as the release above: a pin whose item an
      // axis swap stranded is simply not obtained, and the next layout
      // unmounts its child through the ordinary unused-child path.
      if (id >= 0 && !_outOfLattice(id)) {
        final vicinity = ChildVicinity(
          xIndex:
              _controller.columns.axis.trackCount +
              _controller.vicinityOrdinalOfId(id),
          yIndex: _controller.primaryStartOfId(id),
        );
        final child = _obtainOnce(vicinity);
        if (child != null) {
          _vicinityToItemId[vicinity] = id;
        }
      }
    }
  }

  /// Whether [id]'s span starts past either axis's current track count,
  /// which only an axis swap can produce mid-flight.
  bool _outOfLattice(int id) {
    return _controller.startIndexOfId(id, Axis.vertical) >=
            _controller.rows.axis.trackCount ||
        _controller.startIndexOfId(id, Axis.horizontal) >=
            _controller.columns.axis.trackCount;
  }

  /// The retention bookkeeping: every obtained EXITING item is recorded,
  /// overwriting any older id at the vicinity, which is what makes id
  /// recycling a non-event; releases happened at the top of
  /// [_obtainRetained].
  /// Walks the ITEM map rather than the whole obtain set: only an item
  /// vicinity can carry an exiting id, and the obtain wrote exactly the
  /// item vicinities into that map, so the two enumerate the same
  /// entries while this one skips every cell and hashes nothing.
  void _sweepRetention() {
    final anim = _controller.anim;
    _vicinityToItemId.forEach((vicinity, id) {
      if (anim.isExitingItem(id)) {
        _retainedExits[vicinity] = id;
      }
    });
  }

  /// The ANIMATED geometry reads: settled unless a trackResize is in
  /// flight, in which case a track's painted extent comes from the
  /// animator and every following track's painted offset shifts by the
  /// in-flight difference. Every consumer that must agree with what
  /// paints goes through these three; the correction anchor and
  /// `applyContentDimensions` deliberately do not.
  double _animatedOffsetOf(Axis axisEnum, BoardAxis axis, int track) {
    final settled = axis.offsetOf(track);
    if (!_controller.anim.hasActiveTrackResize) {
      return settled;
    }
    return settled + _shiftTo(axisEnum, track);
  }

  /// The shift `animatedOffsetShiftBetween` returns for [track] on [axis]
  /// from this layout's floor.
  ///
  /// A plain forward. The animator answers from a prefix over its
  /// in-flight tracks, so this costs two binary searches whether it is
  /// called from inside a layout or from a port query between frames;
  /// the per-layout memo that used to sit here was one cache too many
  /// once the source itself stopped walking.
  double _shiftTo(Axis axis, int track) {
    final floor = axis == Axis.vertical ? _shiftFloorRow : _shiftFloorCol;
    return _controller.animatedOffsetShiftBetween(axis, floor, track);
  }

  double _animatedExtentOf(Axis axisEnum, BoardAxis axis, int track) {
    if (!_controller.anim.hasActiveTrackResize) {
      return axis.extentOf(track);
    }
    return _controller.anim.animatedExtentOf(axisEnum, track);
  }

  int _animatedTrackAt(Axis axisEnum, BoardAxis axis, double content) {
    if (!_controller.anim.hasActiveTrackResize) {
      return axis.trackAt(content);
    }
    var lo = 0;
    var hi = axis.trackCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_animatedOffsetOf(axisEnum, axis, mid) <= content) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// One placement pass: obtain the window's cells, lay them out, size the
  /// content-sized axis's tracks from what they measured, and return the
  /// scroll correction that holds the anchor still.
  ///
  /// Returns a content-space correction on the content-sized axis, or 0.0
  /// when no axis measures or no measured track is on screen to anchor on.
  double _obtainMeasureAndSize(({double dx, double dy}) inset) {
    final rowsConfig = _controller.rows;
    final columnsConfig = _controller.columns;
    final rowAxis = rowsConfig.axis;
    final columnAxis = columnsConfig.axis;
    final extent = viewportDimension;

    // Content space, both axes.
    final scrollY = verticalOffset.pixels;
    final scrollX = horizontalOffset.pixels;
    final topVisible = scrollY;
    final bottomVisible = scrollY + extent.height;
    final leftVisible = scrollX;
    final rightVisible = scrollX + extent.width;
    final topObtain = topVisible - inset.dy;
    final bottomObtain = bottomVisible + inset.dy;
    final leftObtain = leftVisible - inset.dx;
    final rightObtain = rightVisible + inset.dx;

    // THE ANCHOR IS THE FIRST ALREADY-MEASURED TRACK IN THE VISIBLE
    // RANGE, not the first track in it. That distinction is the whole
    // correction: scrolling into new territory reveals never-measured
    // tracks, and anchoring on one of those computes zero every time,
    // because its own offset depends only on tracks before it that this
    // pass never touched. Both sides of the subtraction are SETTLED
    // geometry, which is what keeps an in-flight track resize from
    // fighting a correction.
    final contentAxis = _contentAxis;
    final anchorConfig = contentAxis == null
        ? null
        : (contentAxis == Axis.vertical ? rowsConfig : columnsConfig);
    final anchorAxis = anchorConfig?.axis;
    var anchorTrack = -1;
    var anchorBefore = 0.0;
    if (anchorAxis != null) {
      // Searched in the UNFROZEN region: a track under a band is not what
      // the user sees, and holding it still holds nothing visible.
      final region = _unfrozenNormalized(contentAxis!);
      final pixels = contentAxis == Axis.vertical ? scrollY : scrollX;
      anchorTrack = _firstMeasuredTrackIn(
        anchorAxis,
        pixels + region.lo,
        pixels + region.hi,
      );
      if (anchorTrack >= 0) {
        // Held relative to the LEADING BAND's end: a band that grows
        // pushes the scrolled content down with it rather than scrolling
        // it underneath, so the offset held is the anchor's minus the
        // band's.
        anchorBefore =
            anchorAxis.offsetOf(anchorTrack) - anchorConfig!.leadingBandExtent;
      }
    }

    _contentTrackExtents.clear();
    _contentTrackArgMax.clear();
    _recordRemeasured.clear();
    // OBTAIN-AND-SIZE TO A FIXED POINT. Sizing shrinks estimate-sized
    // tracks, which recomputes the window's track range from the new
    // offsets and can reveal tracks the previous round never walked; on a
    // fresh board with oversized estimates that revelation happens with a
    // ZERO correction (nothing measured before the pass means no anchor),
    // so without this inner loop the pass would settle with visible
    // tracks unbuilt, permanently. Each round either obtains at least one
    // new vicinity or stops, so the round count is bounded by the
    // obtainable set; the obtain-once set makes re-walks cheap.
    while (true) {
      final obtainedBefore = _obtainedThisLayout.length;
      final firstRow = _animatedTrackAt(
        Axis.vertical,
        rowAxis,
        math.max(0.0, topObtain),
      );
      final firstCol = _animatedTrackAt(
        Axis.horizontal,
        columnAxis,
        math.max(0.0, leftObtain),
      );
      // Anchor the animated accumulation at this pass's window entry;
      // last write wins, which is the settling pass's.
      _shiftFloorRow = firstRow;
      _shiftFloorCol = firstCol;
      // The scrolled window, then the three frozen extensions: frozen
      // rows under the scrolled columns, frozen columns beside the
      // scrolled rows, and the frozen-by-frozen corner. A frozen track is
      // pinned to the viewport whatever the scroll offset is, so its
      // cells must be obtained even when the track lies far outside the
      // scrolled window; overlaps dedupe through the obtain-once set.
      for (var row = firstRow; row < rowAxis.trackCount; row++) {
        if (_animatedOffsetOf(Axis.vertical, rowAxis, row) >= bottomObtain) {
          break;
        }
        for (var col = firstCol; col < columnAxis.trackCount; col++) {
          if (_animatedOffsetOf(Axis.horizontal, columnAxis, col) >=
              rightObtain) {
            break;
          }
          _obtainAndMeasureCell(
            rowsConfig,
            columnsConfig,
            row,
            col,
            contentAxis,
          );
        }
      }
      for (final row in rowsConfig.frozenTracks) {
        for (var col = firstCol; col < columnAxis.trackCount; col++) {
          if (columnAxis.offsetOf(col) >= rightObtain) {
            break;
          }
          _obtainAndMeasureCell(
            rowsConfig,
            columnsConfig,
            row,
            col,
            contentAxis,
          );
        }
      }
      for (final col in columnsConfig.frozenTracks) {
        for (var row = firstRow; row < rowAxis.trackCount; row++) {
          if (rowAxis.offsetOf(row) >= bottomObtain) {
            break;
          }
          _obtainAndMeasureCell(
            rowsConfig,
            columnsConfig,
            row,
            col,
            contentAxis,
          );
        }
      }
      for (final row in rowsConfig.frozenTracks) {
        for (final col in columnsConfig.frozenTracks) {
          _obtainAndMeasureCell(
            rowsConfig,
            columnsConfig,
            row,
            col,
            contentAxis,
          );
        }
      }
      _obtainItems(
        rowAxis,
        columnAxis,
        topObtain: topObtain,
        bottomObtain: bottomObtain,
        leftObtain: leftObtain,
        rightObtain: rightObtain,
      );
      if (anchorAxis != null) {
        _sizeContentTracks(anchorAxis);
        // THE SETTLED-WRITE INVALIDATION. Every `recordMeasurement` in
        // this file sits inside the step above, and the animator's shift
        // prefix captures settled extents, so this is the one site that
        // has to tell it. The installs and finalizes beside them need no
        // telling: those move the animator's own state and it bumps its
        // generation for itself.
        _controller.invalidateAnimatedShifts();
      }
      if (_obtainedThisLayout.length == obtainedBefore) {
        break;
      }
    }
    _recordVisibleWindow();

    if (anchorAxis == null || anchorTrack < 0) {
      return 0.0;
    }
    return anchorAxis.offsetOf(anchorTrack) -
        anchorConfig!.leadingBandExtent -
        anchorBefore;
  }

  /// The TRACK SIZING step: writes this pass's resolved extents into the
  /// content-sized axis.
  ///
  /// Four arms per track. A first measurement replaces the estimate and
  /// clears every latch set. A RAMPING contributor, or one holding a
  /// make-room delta or a RELANE lead, records per pass and maintains
  /// both latch sets symmetrically, each against its own condition. The
  /// latch's end either RECORDS the residue or, when the SNAP generation
  /// moved and the engine published the discarded motion's clock,
  /// continues the track from where it paints on that clock. A changed
  /// settled extent records the target and installs the resize that
  /// animates toward it.
  ///
  /// A trackResize state in flight needs no hand-in on any arm: it holds
  /// a RESIDUAL over the settled extent rather than a target, so every
  /// record here shows at once and the residual keeps decaying under it
  /// (see `_track_resize_animator.dart`).
  void _sizeContentTracks(BoardAxis axis) {
    final contentAxis = _contentAxis!;
    final config = contentAxis == Axis.vertical
        ? _controller.rows
        : _controller.columns;
    final laneAxisIsContent = _controller.laneAxis == contentAxis;
    final ramps = contentAxis == Axis.vertical
        ? _rampWroteRows
        : _rampWroteCols;
    final makeRoomLatch = contentAxis == Axis.vertical
        ? _makeRoomWroteRows
        : _makeRoomWroteCols;
    final anim = _controller.anim;
    for (final entry in _contentTrackExtents.entries) {
      final track = entry.key;
      var to = entry.value;
      // The CELL term, folded with the record of cells out of the window:
      // the window's maximum replaces the record when it is at least as
      // tall, or when this pass measured the recorded cell again.
      final record = _cellRecord[track];
      if (record == null ||
          to >= record.extent ||
          _recordRemeasured.contains(track)) {
        _cellRecord[track] = (extent: to, cross: _contentTrackArgMax[track]!);
      } else {
        to = record.extent;
      }
      var contributorRamping = false;
      var makeRoomContributes = false;
      if (laneAxisIsContent) {
        // The item-cluster term: the track must hold its deepest
        // cluster's lanes, each member's ceiling SCALED by its enter/exit
        // ramp and SHIFTED by the two intra-track numbers paint adds to
        // the same member, its held make-room delta and its RELANE
        // slide's lead, so the track's edge is a function of what paints.
        // Zero members and no slot contribute NO term; an itemless track
        // keeps its cells-only measurement. NO MEMBER IS SKIPPED, the
        // lifted one included: nothing collapses the dragged item's
        // in-place widget, so the track must keep holding it, and the
        // engine answers a zero delta for a lifted id anyway.
        // Lane resolution ran at the layout head.
        final members = _controller.laneBucketMembersOn(track);
        var deepest = 0.0;
        var seen = false;
        for (final member in members) {
          seen = true;
          if (anim.isEnteringItem(member) || anim.isExitingItem(member)) {
            contributorRamping = true;
          }
          // Content space, on the lane axis; a delta is the same number
          // in both spaces.
          final delta = contentAxis == Axis.vertical
              ? anim.makeRoomDeltaOf(member).dy
              : anim.makeRoomDeltaOf(member).dx;
          // A RELANE lead is the second number paint adds to a member's
          // lane origin: an intra-track shift, so it belongs to THIS
          // track's term. A cross-track slide never reaches here, which
          // is what the relane mark decides and what keeps the reader's
          // "the term must not compose non-relane slides" rule whole.
          final relane = contentAxis == Axis.vertical
              ? anim.relaneDeltaOf(member).dy
              : anim.relaneDeltaOf(member).dx;
          if (delta != 0.0 || relane != 0.0) {
            makeRoomContributes = true;
          }
          // A LANE BAND measure and not an extent: the band's position
          // (the lane origin plus the two intra-track LEAD numbers paint
          // adds) plus the band's SIZE, the member's stored span, scaled
          // by its ramp. It reads no in-flight extent, so it agrees with
          // paint AT REST and can lag it while an extent animates on a
          // different clock.
          final ceiling =
              _controller.laneOfId(member) * config.laneExtent! +
              delta +
              relane +
              anim.enterExitProgressOf(member) *
                  _controller.laneSpanOfId(member) *
                  config.laneExtent!;
          if (ceiling > deepest) {
            deepest = ceiling;
          }
        }
        for (final slot in anim.makeRoomSlotsOn(track)) {
          // A PROSPECTIVE lane occupancy: the enter/exit formula with the
          // slot's value in the role of progress. On the lifted item's
          // own track its member ceiling and its slot can both appear and
          // the max takes one or the other, never their sum.
          seen = true;
          makeRoomContributes = true;
          final ceiling = (slot.lane + slot.value) * config.laneExtent!;
          if (ceiling > deepest) {
            deepest = ceiling;
          }
        }
        if (seen) {
          final term = deepest + config.lanePadding;
          if (term > to) {
            to = term;
          }
        }
      }
      // COLLECTED here and REPORTED after the pass loop, never thrown
      // from inside it: see [_debugStaleCells]'s report for what a throw
      // here strands.
      assert(() {
        if (_controller.laneAxis == null &&
            _controller.debugHasIntraTrackItemOn(track)) {
          (_debugClusterTracks ??= <int>{}).add(track);
        }
        return true;
      }());
      if (!axis.isMeasured(track)) {
        // A FIRST measurement replacing an estimate: record, install
        // nothing. Making that transition invisible is what the
        // correction loop is for, and an install here would fight it on
        // every scroll into new territory. EVERY latch set drops the
        // track: a first measurement is not a hand-off and must not
        // become one on the next pass, and a controller swap can reach
        // this arm with latch entries standing.
        axis.recordMeasurement(track, to);
        _passMeasuredNewTrack = true;
        ramps.remove(track);
        makeRoomLatch.remove(track);
        continue;
      }
      if (contributorRamping || makeRoomContributes) {
        // The ramp or the gap IS this track's animation: `to` already
        // carries it and changes every tick, so record and latch. An
        // install here would re-target a resize once per tick and leave
        // layout dirty for a resize duration after the settle. A resize
        // already in flight for the track stays: its residual is over
        // the settled extent this records, so the term shows at once and
        // the residual finishes under it on its own clock.
        axis.recordMeasurement(track, to);
        // SYMMETRIC, not add-only: a track can lose one kind of
        // contribution while another keeps it on this arm, and an entry
        // carried past the pass that stopped contributing would make the
        // hand-off read the wrong kind as having vanished.
        if (contributorRamping) {
          ramps.add(track);
        } else {
          ramps.remove(track);
        }
        if (makeRoomContributes) {
          makeRoomLatch.add(track);
        } else {
          makeRoomLatch.remove(track);
        }
        continue;
      }
      final endedRamp = ramps.remove(track);
      final endedMakeRoom = makeRoomLatch.remove(track);
      if (endedRamp || endedMakeRoom) {
        // The frame a latch ENDED. A natural settle leaves a residue of
        // at most one tick's motion, which RECORDS: an install would keep
        // layout dirty for a resize duration. A SNAP that discarded
        // motion is the other way here: the engine bumped its snap
        // generation and published the discarded motion's remaining
        // clock and curve tail, the drag layer is continuing every
        // displaced neighbour's painted position on that clock, and a
        // residue worth acting on continues the track's edge on the same
        // clock, growth and shrink alike, so the edge and the content
        // inside it arrive together. A growth is not recorded either:
        // the landing item is gliding in from the proxy for the whole
        // dropSettle window, and the remaining make-room time is at most
        // one make-room duration, which the default style makes the same
        // window. The install rides the makeRoom family, whose kill
        // switch is the one that governs the motion being continued.
        //
        // `painted` is read BEFORE the record, which moves the settled
        // extent it is measured from. The install decides the rest: a
        // residue within tolerance is no motion and drops any state the
        // track still holds, since the track already paints its new
        // extent, and a zero family refuses. No natural settle installs:
        // a state still in flight there keeps its residual over the new
        // record.
        final painted = anim.animatedExtentOf(contentAxis, track);
        final handOff = anim.makeRoomSnapGeneration != _laidOutSnapGeneration
            ? anim.makeRoomHandOff
            : null;
        axis.recordMeasurement(track, to);
        if (handOff != null) {
          _controller.animateTrackResize(
            contentAxis,
            track,
            painted,
            family: BoardAnimationFamily.makeRoom,
            duration: handOff.remaining,
            curve: handOff.curve,
          );
        }
        continue;
      }
      // Compared against what the axis WOULD STORE, not against the raw
      // measurement: `recordMeasurement` floors at `minTrackExtent`, so a
      // sub-floor track (an empty content-sized track, which is legal
      // input) differs from its stored extent by the whole floor on every
      // pass and would be re-recorded forever. The correction is zero
      // either way, so this is the "one comparison per measurement"
      // pricing and not a correctness fix.
      final stored = to < axis.minTrackExtent ? axis.minTrackExtent : to;
      if ((stored - axis.extentOf(track)).abs() > precisionErrorTolerance) {
        // Capture `from` FIRST: it is the currently PAINTED extent, so a
        // re-target mid-resize composes from where the track is; captured
        // after the write it would read the new settled extent, under
        // any residual still in flight, which is not what painted. The
        // record then makes the axis the settled truth, and the install
        // (which the forwarder routes to the animator, and which a zero
        // family refuses, landing the change this frame while a state of
        // another family keeps decaying over it) must not touch layout,
        // notification or the animation channel from inside layout; its
        // first dispatch is its first tick.
        final from = anim.animatedExtentOf(contentAxis, track);
        axis.recordMeasurement(track, to);
        _controller.animateTrackResize(contentAxis, track, from);
      }
    }
  }

  /// One cell of the obtain pass: obtain, measure, and feed the
  /// content-sized track's running maximum. Cell vicinities are
  /// `(col, row)`, which is injective; the item band starts past every
  /// cell column and lands with the item plane.
  void _obtainAndMeasureCell(
    BoardAxisConfig rowsConfig,
    BoardAxisConfig columnsConfig,
    int row,
    int col,
    Axis? contentAxis,
  ) {
    final child = _obtainOnce(ChildVicinity(xIndex: col, yIndex: row));
    if (child == null) {
      // A recorded cell that now builds nothing no longer holds its
      // track.
      if (contentAxis != null) {
        final track = contentAxis == Axis.vertical ? row : col;
        final cross = contentAxis == Axis.vertical ? col : row;
        if (_cellRecord[track]?.cross == cross) {
          _recordRemeasured.add(track);
        }
      }
      return;
    }
    if (contentAxis == null) {
      // Nothing on this board is measured, so the placement layout the
      // sweep runs is the only layout this cell needs. Measuring here
      // too would lay every cell out twice per layout to feed a track
      // sizing step that never runs.
      return;
    }
    // THE MEASUREMENT CACHE. A cell is measured on the layout that first
    // obtains it, on the layout after its host rebuilt, and on a layout
    // whose measuring constraints differ from the ones the cached value
    // was taken under; on every other layout the cached extent is used
    // and the child is not laid out at all.
    //
    // What that buys: the placement layout in the sweep passes tight
    // constraints under `stretch`, and a measuring layout passes loose
    // ones on the content axis, so measuring every layout made the two
    // alternate and the framework's equal-constraints early return
    // (`rendering/object.dart:2848`) never fired. A scroll now runs no
    // cell layout at all.
    //
    // What it costs is stated at `board_views.dart`: a cell that changes
    // size without rebuilding is not re-measured until it does. A cell
    // laid out tight is its own relayout boundary
    // (`rendering/object.dart:2847`), so its dirtiness never reached
    // this render object anyway; what changes is that a later layout no
    // longer picks the new size up incidentally.
    final data = child.parentData! as _BoardChildParentData;
    final measuring = _measuringConstraints(
      rowsConfig,
      columnsConfig,
      row,
      col,
    );
    if (data.remeasure ||
        data.measured == null ||
        data.measuredUnder != measuring) {
      child.layout(measuring, parentUsesSize: true);
      data
        ..measured = contentAxis == Axis.vertical
            ? child.size.height
            : child.size.width
        ..measuredUnder = measuring
        ..remeasure = false;
    } else {
      // THE OPT-IN STALENESS CHECK, in the arm that uses the cache and
      // only there. It reads and never writes: a check that healed the
      // cache would make a stale board correct in debug and wrong in
      // release.
      assert(() {
        if (!debugCheckCellMeasurements) {
          return true;
        }
        child.layout(measuring, parentUsesSize: true);
        final fresh = contentAxis == Axis.vertical
            ? child.size.height
            : child.size.width;
        if ((fresh - data.measured!).abs() > precisionErrorTolerance) {
          (_debugStaleCells ??= <String>[]).add(
            "row $row, column $col: cached ${data.measured}, measures "
            "$fresh",
          );
        }
        return true;
      }());
    }
    // The CELL contribution to the track's intrinsic extent: the maximum
    // over the cells of that track this pass obtained, which the sizing
    // step folds with [_cellRecord]. The item-cluster term lands with the
    // item plane.
    final track = contentAxis == Axis.vertical ? row : col;
    final cross = contentAxis == Axis.vertical ? col : row;
    final measured = data.measured!;
    final current = _contentTrackExtents[track];
    if (current == null || measured > current) {
      _contentTrackExtents[track] = measured;
      _contentTrackArgMax[track] = cross;
    }
    if (_cellRecord[track]?.cross == cross) {
      _recordRemeasured.add(track);
    }
  }

  /// Reused per layout by [_obtainItems]; a field so the obtain set query
  /// allocates nothing per frame.
  final List<int> _itemIdScratch = <int>[];

  /// Obtains the item children whose spans intersect the obtain window.
  ///
  /// Item vicinities are `(colCount + ordinal, primary start track)`,
  /// which is injective because the ordinal is a dense per-track rank
  /// over distinct ids. The vicinity-to-id map is written HERE and read
  /// by the sweep, both paint walks and `applyPaintTransform`.
  void _obtainItems(
    BoardAxis rowAxis,
    BoardAxis columnAxis, {
    required double topObtain,
    required double bottomObtain,
    required double leftObtain,
    required double rightObtain,
  }) {
    if (rowAxis.trackCount == 0 || columnAxis.trackCount == 0) {
      return;
    }
    final rowStart = _animatedTrackAt(
      Axis.vertical,
      rowAxis,
      math.max(0.0, topObtain),
    );
    final rowEnd = _animatedTrackAt(
      Axis.vertical,
      rowAxis,
      math.min(rowAxis.totalExtent, math.max(0.0, bottomObtain)) -
          precisionErrorTolerance,
    );
    final colStart = _animatedTrackAt(
      Axis.horizontal,
      columnAxis,
      math.max(0.0, leftObtain),
    );
    final colEnd = _animatedTrackAt(
      Axis.horizontal,
      columnAxis,
      math.min(columnAxis.totalExtent, math.max(0.0, rightObtain)) -
          precisionErrorTolerance,
    );
    _itemIdScratch.clear();
    _controller.itemIdsInRectIncludingExiting(
      rowStart,
      rowEnd + 1,
      colStart,
      colEnd + 1,
      _itemIdScratch,
    );
    // The BANDS, as frozen cells are obtained: a pinned item paints in
    // its band whatever the scroll offset, so it must be obtained even
    // when its tracks lie far outside the scrolled window. Frozen rows
    // against the window's columns, frozen columns against its rows, and
    // the corners; a board with no band runs none of these, and an id two
    // queries both return is obtained once below.
    final rowBands = _bandRangesOf(_controller.rows);
    final colBands = _bandRangesOf(_controller.columns);
    for (final rows in rowBands) {
      _controller.itemIdsInRectIncludingExiting(
        rows.start,
        rows.end,
        colStart,
        colEnd + 1,
        _itemIdScratch,
      );
      for (final cols in colBands) {
        _controller.itemIdsInRectIncludingExiting(
          rows.start,
          rows.end,
          cols.start,
          cols.end,
          _itemIdScratch,
        );
      }
    }
    for (final cols in colBands) {
      _controller.itemIdsInRectIncludingExiting(
        rowStart,
        rowEnd + 1,
        cols.start,
        cols.end,
        _itemIdScratch,
      );
    }
    final columnCount = columnAxis.trackCount;
    for (final id in _itemIdScratch) {
      final vicinity = ChildVicinity(
        xIndex: columnCount + _controller.vicinityOrdinalOfId(id),
        yIndex: _controller.primaryStartOfId(id),
      );
      final child = _obtainOnce(vicinity);
      if (child == null) {
        continue;
      }
      _vicinityToItemId[vicinity] = id;
    }
  }

  /// An item's content-space leading edge and extent on [axis], the
  /// two-arm rule: a LANED item on the lane axis takes its track's edge
  /// plus the lane term and its whole lane BAND, the slice multiplied by
  /// its lane span, for its extent (its own fractions on that axis are
  /// ignored, because its position inside the track is decided by its
  /// lane); everything else takes the exact fractional endpoints, which
  /// is the only arm that consumes them.
  ///
  /// THE ONE SITE THAT ADDS THE IN-FLIGHT EXTENT DELTA, on every arm,
  /// before the enter/exit ramp multiplies. Layout's tight constraints
  /// and `rectOfItem` both read this rule, so a child is laid out at the
  /// size the port reports; splitting them would report one size and
  /// paint another. The delta is SIGNED, a growth carrying a negative
  /// one, so the floor is on the SUM and never on the delta alone. The
  /// LEAD takes no such term: a slide's lead is the paint shift.
  ({double lead, double extent}) _itemSpanGeometry(
    int id,
    Axis axis,
    BoardPin pin,
  ) {
    final config = axis == Axis.vertical
        ? _controller.rows
        : _controller.columns;
    // A PINNED axis reads settled track offsets, exactly as its band's
    // frozen cells do (`_frozenNormalizedPosition`): a track resize in
    // flight shifts the scrolled lattice, not the band.
    final pinned = pin != BoardPin.none;
    final boardAxis = config.axis;
    final extentDelta = axis == Axis.vertical
        ? _controller.anim.extentDeltaOf(id).dy
        : _controller.anim.extentDeltaOf(id).dx;
    final laned = _controller.laneAxis == axis && _controller.isLanedId(id);
    if (laned) {
      // Clamped exactly as the fractional arm below clamps: an axis swap
      // can strand a live span past the lattice, and these reads must
      // stay total for every consumer, rectOfItem included.
      final track = math.min(
        _controller.startIndexOfId(id, axis),
        boardAxis.trackCount,
      );
      final lane = _controller.laneOfId(id);
      final laneCount = _controller.laneCountOfId(id);
      final laneSpan = _controller.laneSpanOfId(id);
      final trackLead = pinned
          ? boardAxis.offsetOf(track)
          : _animatedOffsetOf(axis, boardAxis, track);
      final laneExtent = config.laneExtent;
      final padding = config.lanePadding;
      if (boardAxis.acceptsMeasurements) {
        // Content-sized lane axis: fixed slices from the padded edge; the
        // track grew to hold them through the cluster term. The item
        // takes its whole BAND, the span multiplying INSIDE the floor and
        // BEFORE the ramp, so the delta and the progress compose exactly
        // as they did on one slice. The extent ramps with the item's own
        // enter/exit progress.
        return (
          lead: trackLead + padding + lane * laneExtent!,
          extent:
              math.max(0.0, laneExtent * laneSpan + extentDelta) *
              _controller.anim.enterExitProgressOf(id),
        );
      }
      // Fixed lane axis: the track's extent past the padding is divided
      // evenly among the cluster's lanes.
      // Floored at zero: a lanePadding wider than the track would
      // otherwise hand layout a negative tight constraint. A clamped
      // out-of-lattice track has no extent at all.
      final trackExtent = track >= boardAxis.trackCount
          ? 0.0
          : boardAxis.extentOf(track);
      final slice = math.max(0.0, trackExtent - padding) / laneCount;
      return (
        // The lead reads the SETTLED slice and takes NO span: the lane
        // origin is the item's OWN lane's, and is where the item's own
        // animated extent does not reach.
        lead: trackLead + padding + lane * slice,
        extent:
            math.max(0.0, slice * laneSpan + extentDelta) *
            _controller.anim.enterExitProgressOf(id),
      );
    }
    final startTrack = axis == Axis.vertical
        ? _controller.rowStartTrackOfId(id)
        : _controller.colStartTrackOfId(id);
    final endTrack = axis == Axis.vertical
        ? _controller.rowEndTrackOfId(id)
        : _controller.colEndTrackOfId(id);
    var lead = boardAxis.offsetOfFraction(
      math.min(startTrack, boardAxis.trackCount.toDouble()),
    );
    var trail = boardAxis.offsetOfFraction(
      math.min(endTrack, boardAxis.trackCount.toDouble()),
    );
    if (!pinned && _controller.anim.hasActiveTrackResize) {
      lead += _shiftTo(axis, trackIndexOf(startTrack));
      trail += _shiftTo(axis, trackIndexOf(endTrack));
    }
    var extent = math.max(0.0, trail - lead + extentDelta);
    if (axis == (_controller.laneAxis ?? _controller.primaryAxis)) {
      // The third form of the scaled lane-axis extent: a non-laned item
      // on the lane axis ramps over its own full extent. The span axis
      // is never scaled; a chip entering a week row grows in height, not
      // in day count. With NO lane axis the PRIMARY axis takes its place,
      // or an item entering or leaving such a board would show nothing
      // for the whole ramp and then pop: on a gantt, rows primary and
      // time across, a bar grows in thickness and not in duration.
      extent *= _controller.anim.enterExitProgressOf(id);
    }
    return (lead: lead, extent: extent);
  }

  /// The half-open track ranges of [config]'s frozen bands, leading then
  /// trailing, as [BoardAxisConfigBands] bounds them; empty for an axis
  /// with no band.
  List<({int start, int end})> _bandRangesOf(BoardAxisConfig config) {
    final count = config.axis.trackCount;
    final lead = config.leadingBandEnd;
    final trailFrom = config.trailingBandStart;
    return <({int start, int end})>[
      if (lead > 0) (start: 0, end: lead),
      if (trailFrom < count) (start: trailFrom, end: count),
    ];
  }

  /// A frozen track's NORMALIZED position, pinned to the viewport: a
  /// leading track sits at the sum of the frozen extents before it, which
  /// for a contiguous leading band is `offsetOf(track)` with no scroll
  /// term; a trailing track sits at the viewport extent minus the summed
  /// extents from it to the end. Reversal is applied downstream by
  /// `computeAbsolutePaintOffsetFor`, exactly as for scrolled cells.
  double _frozenNormalizedPosition(
    BoardAxisConfig config,
    int track,
    double viewportExtent,
  ) {
    final axis = config.axis;
    if (track < config.leadingBandEnd) {
      return axis.offsetOf(track);
    }
    return viewportExtent - (axis.totalExtent - axis.offsetOf(track));
  }

  /// An item's NORMALIZED lead on [axis] from its content-space [lead]:
  /// the lead minus the scroll offset where it scrolls, and where its
  /// [pin] holds it, the position its band's cells take
  /// ([_frozenNormalizedPosition]): its content offset in the leading
  /// band, and the viewport extent minus what follows it in the trailing
  /// one.
  double _normalizedItemLead(Axis axis, BoardPin pin, double lead) {
    final vertical = axis == Axis.vertical;
    switch (pin) {
      case BoardPin.none:
        return lead -
            (vertical ? verticalOffset.pixels : horizontalOffset.pixels);
      case BoardPin.leading:
        return lead;
      case BoardPin.trailing:
        final config = vertical ? _controller.rows : _controller.columns;
        final viewport = vertical
            ? viewportDimension.height
            : viewportDimension.width;
        return viewport - (config.axis.totalExtent - lead);
    }
  }

  /// Obtains a child at most once per `layoutChildSequence`, reading it
  /// back through [_liveChildFor] on any later request in the same call.
  RenderBox? _obtainOnce(ChildVicinity vicinity) {
    if (_obtainedThisLayout.add(vicinity)) {
      final child = buildOrObtainChildFor(vicinity);
      return _builtNothing.contains(vicinity) ? null : child;
    }
    return _liveChildFor(vicinity);
  }

  /// The child at [vicinity] for the layout that is running, or null when
  /// there is none or when its builder answered null this layout.
  ///
  /// The second arm is the stale child: on a delegate rebuild the element
  /// returns early for a null widget
  /// (`widgets/two_dimensional_viewport.dart:339-342`), so the base hands
  /// back the child ALREADY at the vicinity (`:1489-1505`), which the
  /// child manager drops only after this layout's sequence returns. The
  /// base skips it when it links its children (`:1424`); this object's
  /// paint lists, measurements and null-cell count are built inside the
  /// sequence and must skip it too.
  RenderBox? _liveChildFor(ChildVicinity vicinity) {
    if (_builtNothing.contains(vicinity)) {
      return null;
    }
    return getChildFor(vicinity);
  }

  /// The vicinities whose builder answered null in the layout that is
  /// running, which [noteBuiltNothing] writes and [_liveChildFor] reads.
  /// Cleared at the head of every `layoutChildSequence`.
  final Set<ChildVicinity> _builtNothing = <ChildVicinity>{};

  /// Internal-use channel for the board's delegate builder; not part of
  /// the supported surface. Records that the builder answered null for
  /// [vicinity], so a child left there from an earlier layout is not read
  /// back as this layout's; see [_liveChildFor].
  void noteBuiltNothing(ChildVicinity vicinity) {
    _builtNothing.add(vicinity);
  }

  /// The final positioning sweep. Every obtained vicinity gets a
  /// `layoutOffset` before `layoutChildSequence` returns, computed from
  /// the SETTLED axis state and the SETTLED scroll position.
  ///
  /// It also re-lays out each cell at its now-resolved track extent, which
  /// is what `TrackAlignment.stretch` means on a content-sized axis. A
  /// child whose constraints did not change and which is not dirty returns
  /// from `layout` without doing work.
  void _positionObtainedChildren() {
    final rowsConfig = _controller.rows;
    final columnsConfig = _controller.columns;
    final rowAxis = rowsConfig.axis;
    final columnAxis = columnsConfig.axis;
    final scrollY = verticalOffset.pixels;
    final scrollX = horizontalOffset.pixels;
    final extent = viewportDimension;
    // The one reset site for the paint lists: cleared and rebuilt exactly
    // once per `layoutChildSequence`, never per pass. The item map is NOT
    // cleared here; the obtain wrote it and this sweep reads it.
    _cellPaintOrder.clear();
    _itemPaintOrder.clear();
    _frozenPaintOrder.clear();
    _hasVisualOverflow = false;
    final corner = <RenderBox>[];
    final itemEntries =
        <({int plane, bool laned, int lane, int id, RenderBox child})>[];
    // The one write site of the null-cell count; see the field.
    final cellColumns = columnAxis.trackCount;
    _nullCellCount = 0;
    for (final vicinity in _obtainedThisLayout) {
      final child = _liveChildFor(vicinity);
      if (child == null) {
        // A vicinity that built nothing. A CELL one is what the two
        // channel handlers gate on: it holds no host, so no relay can
        // reach its builder and only a layout can ask it again. An ITEM
        // one is not counted, per the field's doc.
        if (vicinity.xIndex < cellColumns) {
          _nullCellCount += 1;
        }
        continue;
      }
      final itemId = _vicinityToItemId[vicinity];
      if (itemId != null) {
        // An ITEM child: exact rect on both axes from the two-arm
        // geometry rule, positioned with its band on an axis where it is
        // PINNED and with the scroll offset elsewhere, so the band covers
        // an item that merely scrolls beneath it.
        final pinV = _controller.pinOfId(itemId, Axis.vertical);
        final pinH = _controller.pinOfId(itemId, Axis.horizontal);
        final vertical = _itemSpanGeometry(itemId, Axis.vertical, pinV);
        final horizontal = _itemSpanGeometry(itemId, Axis.horizontal, pinH);
        child.layout(
          BoxConstraints.tightFor(
            width: horizontal.extent,
            height: vertical.extent,
          ),
          parentUsesSize: true,
        );
        final data = parentDataOf(child) as _BoardChildParentData;
        data
          ..layoutOffset = Offset(
            _normalizedItemLead(Axis.horizontal, pinH, horizontal.lead),
            _normalizedItemLead(Axis.vertical, pinV, vertical.lead),
          )
          ..pinnedVertical = pinV != BoardPin.none
          ..pinnedHorizontal = pinH != BoardPin.none;
        itemEntries.add((
          plane:
              (pinV == BoardPin.none ? 0 : 1) + (pinH == BoardPin.none ? 0 : 1),
          laned: _controller.isLanedId(itemId),
          lane: _controller.laneOfId(itemId),
          id: itemId,
          child: child,
        ));
        continue;
      }
      final row = vicinity.yIndex;
      final col = vicinity.xIndex;
      assert(
        row < rowAxis.trackCount && col < columnAxis.trackCount,
        "RenderBoardViewport obtained the vicinity $vicinity, which is "
        "outside the cell lattice. Every obtained vicinity must be "
        "placeable, because updateChildPaintData asserts on a null "
        "layoutOffset.",
      );
      // The two animated extents, read ONCE and used three times each:
      // the placement constraints, the alignment surplus, and nothing
      // else in this arm.
      final trackWidth = _animatedExtentOf(Axis.horizontal, columnAxis, col);
      final trackHeight = _animatedExtentOf(Axis.vertical, rowAxis, row);
      child.layout(
        _placementConstraints(
          rowsConfig,
          columnsConfig,
          trackWidth,
          trackHeight,
        ),
        parentUsesSize: true,
      );
      final rowFrozen = rowsConfig.isFrozenTrack(row);
      final colFrozen = columnsConfig.isFrozenTrack(col);
      // Content space: the track's leading edge plus the alignment's share
      // of whatever surplus the cell left in the track. A frozen track
      // replaces the content-minus-scroll term with a viewport-pinned one
      // on ITS axis only; a header row still scrolls with its columns.
      final shiftY = _alignmentShift(
        rowsConfig.alignment,
        trackHeight - child.size.height,
      );
      final shiftX = _alignmentShift(
        columnsConfig.alignment,
        trackWidth - child.size.width,
      );
      final normalizedY = rowFrozen
          ? _frozenNormalizedPosition(rowsConfig, row, extent.height) + shiftY
          : _animatedOffsetOf(Axis.vertical, rowAxis, row) + shiftY - scrollY;
      final normalizedX = colFrozen
          ? _frozenNormalizedPosition(columnsConfig, col, extent.width) + shiftX
          : _animatedOffsetOf(Axis.horizontal, columnAxis, col) +
                shiftX -
                scrollX;
      // NORMALIZED space, not viewport paint space:
      // computeAbsolutePaintOffsetFor applies reversal from here.
      (parentDataOf(child) as _BoardChildParentData)
        ..layoutOffset = Offset(normalizedX, normalizedY)
        ..pinnedVertical = rowFrozen
        ..pinnedHorizontal = colFrozen;
      if (normalizedX < 0.0 ||
          normalizedY < 0.0 ||
          normalizedX + child.size.width > extent.width ||
          normalizedY + child.size.height > extent.height) {
        _hasVisualOverflow = true;
      }
      if (rowFrozen && colFrozen) {
        corner.add(child);
      } else if (rowFrozen || colFrozen) {
        _frozenPaintOrder.add(child);
      } else {
        _cellPaintOrder.add(child);
      }
    }
    // Corner cells outpaint the two bands; see the field's doc.
    _cornerCellStart = _frozenPaintOrder.length;
    _frozenPaintOrder.addAll(corner);
    // The item planes in order, and inside each: laned items by lane then
    // id, and non-laned items LAST, so an item painting across its whole
    // lane-axis extent sits above the laned stack and, through the reverse
    // hit-test walk, takes the pointer over it. A plain (lane, id) order
    // buries it: exclusion from laning stores lane 0.
    itemEntries.sort((a, b) {
      if (a.plane != b.plane) {
        return a.plane.compareTo(b.plane);
      }
      if (a.laned != b.laned) {
        return a.laned ? -1 : 1;
      }
      final byLane = a.lane.compareTo(b.lane);
      if (byLane != 0) {
        return byLane;
      }
      return a.id.compareTo(b.id);
    });
    _bandItemStart = itemEntries.length;
    _cornerItemStart = itemEntries.length;
    for (var i = itemEntries.length - 1; i >= 0; i--) {
      final plane = itemEntries[i].plane;
      if (plane >= 1) {
        _bandItemStart = i;
      }
      if (plane == 2) {
        _cornerItemStart = i;
      }
    }
    for (final entry in itemEntries) {
      _itemPaintOrder.add(entry.child);
    }
  }

  /// Constraints a cell is MEASURED under.
  ///
  /// The content-sized axis is unbounded here, because its track extent is
  /// what this pass is resolving; the fixed axis resolves first and
  /// supplies a tight constraint under `stretch` and a loose one
  /// otherwise; it can resolve first because at most one axis is
  /// content-sized.
  BoxConstraints _measuringConstraints(
    BoardAxisConfig rowsConfig,
    BoardAxisConfig columnsConfig,
    int row,
    int col,
  ) {
    final double minWidth;
    final double maxWidth;
    if (columnsConfig.axis.acceptsMeasurements) {
      minWidth = 0.0;
      maxWidth = double.infinity;
    } else {
      maxWidth = columnsConfig.axis.extentOf(col);
      minWidth = columnsConfig.alignment == TrackAlignment.stretch
          ? maxWidth
          : 0.0;
    }
    final double minHeight;
    final double maxHeight;
    if (rowsConfig.axis.acceptsMeasurements) {
      minHeight = 0.0;
      maxHeight = double.infinity;
    } else {
      maxHeight = rowsConfig.axis.extentOf(row);
      minHeight = rowsConfig.alignment == TrackAlignment.stretch
          ? maxHeight
          : 0.0;
    }
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  /// Constraints a cell is PLACED under, once both axes' track extents are
  /// resolved. `stretch` is tight at the track extent, so there is no
  /// surplus to place; the other three are loose and get the surplus
  /// through [_alignmentShift].
  ///
  /// The two ANIMATED EXTENTS are passed in rather than read here: its
  /// one caller, the cell arm of the positioning sweep, needs the same
  /// two numbers for the alignment shift below it, and on a content
  /// -sized axis each read is two Fenwick prefix sums.
  BoxConstraints _placementConstraints(
    BoardAxisConfig rowsConfig,
    BoardAxisConfig columnsConfig,
    double width,
    double height,
  ) {
    return BoxConstraints(
      minWidth: columnsConfig.alignment == TrackAlignment.stretch ? width : 0.0,
      maxWidth: width,
      minHeight: rowsConfig.alignment == TrackAlignment.stretch ? height : 0.0,
      maxHeight: height,
    );
  }

  /// The leading-edge shift a cell takes inside its track. Consumed at
  /// exactly this one site, and never applied to items.
  double _alignmentShift(TrackAlignment alignment, double surplus) {
    if (surplus <= 0.0) {
      return 0.0;
    }
    switch (alignment) {
      case TrackAlignment.stretch:
      case TrackAlignment.start:
        return 0.0;
      case TrackAlignment.center:
        return surplus / 2.0;
      case TrackAlignment.end:
        return surplus;
    }
  }

  /// The first track in `[from, to)` whose extent is already measured, or
  /// -1 when there is none. Content space on both bounds.
  int _firstMeasuredTrackIn(BoardAxis axis, double from, double to) {
    if (axis.trackCount == 0) {
      return -1;
    }
    final config = identical(axis, _controller.rows.axis)
        ? _controller.rows
        : _controller.columns;
    for (
      var track = axis.trackAt(math.max(0.0, from));
      track < axis.trackCount;
      track++
    ) {
      if (axis.offsetOf(track) >= to) {
        return -1;
      }
      // A frozen track cannot anchor: its painted position is pinned to
      // the viewport edge, so holding its content-space offset still
      // holds nothing the user sees still while every unfrozen row
      // shifts. Frozen tracks are always obtained and measured, so on a
      // content-sized axis with a frozen band one would otherwise win.
      if (config.isFrozenTrack(track)) {
        continue;
      }
      if (axis.isMeasured(track)) {
        return track;
      }
    }
    return -1;
  }

  /// Records the four visible bounds: the SCROLLED tracks that show in
  /// the unfrozen region, [scrolledRegion]. A track wholly under a frozen
  /// band shows nowhere, and a frozen track is reported by
  /// `frozenTracksOf` instead, so no track is in both.
  void _recordVisibleWindow() {
    final rows = _visibleScrolledTracks(Axis.vertical);
    final cols = _visibleScrolledTracks(Axis.horizontal);
    _firstVisibleRow = rows.first;
    _lastVisibleRow = rows.last;
    _firstVisibleCol = cols.first;
    _lastVisibleCol = cols.last;
  }

  /// The scrolled tracks of [axis] that intersect its unfrozen interval,
  /// through the animated geometry they paint with; `(0, -1)` when none
  /// does.
  ({int first, int last}) _visibleScrolledTracks(Axis axis) {
    final vertical = axis == Axis.vertical;
    final config = vertical ? _controller.rows : _controller.columns;
    final boardAxis = config.axis;
    final lead = config.leadingBandEnd;
    final trailFrom = config.trailingBandStart;
    final region = _unfrozenNormalized(axis);
    if (trailFrom <= lead || region.hi <= region.lo) {
      return (first: 0, last: -1);
    }
    final pixels = vertical ? verticalOffset.pixels : horizontalOffset.pixels;
    final first = math.max(
      lead,
      _animatedTrackAt(axis, boardAxis, math.max(0.0, pixels + region.lo)),
    );
    final last = math.min(
      trailFrom - 1,
      _animatedTrackAt(
        axis,
        boardAxis,
        math.max(0.0, pixels + region.hi - precisionErrorTolerance),
      ),
    );
    if (last < first) {
      return (first: 0, last: -1);
    }
    return (first: first, last: last);
  }

  /// Gives BOTH offsets content dimensions, on every layout including an
  /// empty board, and reports whether both accepted them.
  ///
  /// A false return means `correctForNewDimensions` clamped `pixels`
  /// (`widgets/scroll_position.dart:655`) and the frame would otherwise
  /// paint against a superseded offset, so the loop treats it as another
  /// round. Neither call is skipped when the other fails: both
  /// offsets must receive dimensions. The maximum is clamped at zero,
  /// because `applyContentDimensions` asserts
  /// `minScrollExtent <= maxScrollExtent`.
  bool _applyContentDimensions() {
    final extent = viewportDimension;
    final verticalAccepted = verticalOffset.applyContentDimensions(
      0.0,
      math.max(0.0, _controller.rows.axis.totalExtent - extent.height),
    );
    final horizontalAccepted = horizontalOffset.applyContentDimensions(
      0.0,
      math.max(0.0, _controller.columns.axis.totalExtent - extent.width),
    );
    return verticalAccepted && horizontalAccepted;
  }

  /// The axis layout may feed measurements back into, or null when
  /// neither is content-sized. The controller asserts at most one.
  Axis? get _contentAxis {
    if (_controller.rows.axis.acceptsMeasurements) {
      return Axis.vertical;
    }
    if (_controller.columns.axis.acceptsMeasurements) {
      return Axis.horizontal;
    }
    return null;
  }

  /// The offset of the content-sized axis, which is the only one a
  /// correction can move.
  ViewportOffset? get _contentViewportOffset {
    switch (_contentAxis) {
      case Axis.vertical:
        return verticalOffset;
      case Axis.horizontal:
        return horizontalOffset;
      case null:
        return null;
    }
  }

  /// The CACHE term of the window rule, resolved per axis.
  ///
  /// The base class stores `scrollCacheExtent` and never applies it, so a
  /// board that did not read it would have no cache region at all. The
  /// framework's resolver is library-private, so this resolves the value
  /// from the two public members the sealed class declares, `style`
  /// (`rendering/viewport.dart:61`) and `value`
  /// (`rendering/viewport.dart:70`). A pixel style is the same count on
  /// both axes; a viewport style is that multiple of THAT axis's own
  /// viewport extent, which is the one place a one-dimensional resolver
  /// has no answer.
  ({double dx, double dy}) _resolveCacheTerms() {
    final cacheExtent = scrollCacheExtent;
    switch (cacheExtent.style) {
      case CacheExtentStyle.pixel:
        return (dx: cacheExtent.value, dy: cacheExtent.value);
      case CacheExtentStyle.viewport:
        final extent = viewportDimension;
        return (
          dx: cacheExtent.value * extent.width,
          dy: cacheExtent.value * extent.height,
        );
    }
  }

  /// The ANIMATION term of the window rule: the per-axis magnitudes of
  /// the composed offsets in flight, each folded with the extent delta
  /// where an animated trailing edge reaches further than the lead. The
  /// window is widened by it and [_admittedOffsetBound] records it in the
  /// same statement site, so the pair is whole.
  ({double dx, double dy}) _composedOffsetBound() {
    return _controller.anim.composedOffsetBound;
  }

  // -----------------------------------------------------------------
  // Paint and hit-test. Six planes (see [_frozenPaintOrder]); hit-testing
  // walks the exact reverse, and applyPaintTransform mirrors the same
  // per-item shift paint applies.
  // -----------------------------------------------------------------

  /// The paint-only shift an item child is drawn at, beyond its
  /// `paintOffset`: the coordinator's composed offset, a slide's LEAD
  /// plus the held make-room delta, CONVERTED to paint space.
  ///
  /// The coordinator's offset is a content-space delta (a FLIP lead is
  /// the captured content lead minus the current one), while
  /// `paintOffset` is already reversed by the base
  /// (`widgets/two_dimensional_viewport.dart:1626`, which puts a child
  /// at `viewportDimension - (layoutOffset + size)` on a reversed axis).
  /// Adding the raw delta to it would move the child the wrong way on a
  /// reversed axis, so this is the ONE site that converts a per-item
  /// delta from content to paint space; [contentDeltaFromPaint] is the
  /// same involution offered to the drag layer for the reverse trip.
  ///
  /// FIVE sites read it and they must agree, or a child is drawn at one
  /// place and found at another: [_paintedRectOf], which the item paint
  /// pass, the item hit-test walk, [itemAt]'s painted-rect probe and the
  /// clip decision in [paint] all read, [applyPaintTransform], and
  /// [paintedRectOfItem].
  Offset _paintShiftOf(ChildVicinity vicinity) {
    final id = _vicinityToItemId[vicinity];
    if (id == null) {
      return Offset.zero;
    }
    return _paintShiftOfId(id);
  }

  /// [_paintShiftOf] by item id, for the port's key-addressed reader.
  Offset _paintShiftOfId(int id) {
    return contentDeltaFromPaint(_controller.anim.offsetOfItem(id));
  }

  /// Per-axis negation under reversal. An involution, so the one
  /// function converts a delta either way.
  @override
  Offset contentDeltaFromPaint(Offset paintDelta) {
    return Offset(
      horizontalAxisDirection == AxisDirection.left
          ? -paintDelta.dx
          : paintDelta.dx,
      verticalAxisDirection == AxisDirection.up
          ? -paintDelta.dy
          : paintDelta.dy,
    );
  }

  @override
  Offset leadingCornerOf(Rect paintRect) {
    return Offset(
      horizontalAxisDirection == AxisDirection.left
          ? paintRect.right
          : paintRect.left,
      verticalAxisDirection == AxisDirection.up
          ? paintRect.bottom
          : paintRect.top,
    );
  }

  /// The rect an item child PAINTS at: its `paintOffset` composed with
  /// [_paintShiftOf], and its laid-out size. The ONE producer of that
  /// rect; the item paint gate, the item hit-test gate, [itemAt] and the
  /// clip decision read it. Reads `paintOffset!` exactly as the paint
  /// walk does: every child in a paint list has been positioned by the
  /// base's `updateChildPaintData` before paint runs. [itemAt] keeps its
  /// own null guard in front, because it is the one reader that can meet
  /// a child obtained this layout but not yet positioned.
  Rect _paintedRectOf(RenderBox child) {
    final childParentData = parentDataOf(child);
    return (childParentData.paintOffset! +
            _paintShiftOf(childParentData.vicinity)) &
        child.size;
  }

  /// Whether an item child paints this frame: its PAINTED rect overlaps
  /// the viewport. The base's `isVisible` is computed from the
  /// structural `layoutOffset` at layout, and the shift moves on
  /// paint-only ticks, so a lead-only slide across the viewport edge
  /// would otherwise stop painting the moment its structural rect left
  /// while its painted one was still inside. The paint walk and the
  /// hit-test walk read THIS predicate and no other, so an item paints
  /// exactly where it can be tapped. Cells and frozen children carry no
  /// shift and keep the base's flag.
  bool _paintsItem(RenderBox child) {
    return _paintedRectOf(child).overlaps(Offset.zero & viewportDimension);
  }

  /// Whether any item child's PAINTED rect is not wholly inside the
  /// viewport: the item half of the clip decision in [paint]. Reads the
  /// scratch [paint] filled, so it evaluates no rect of its own.
  bool _anyItemPaintsOutsideViewport() {
    final extent = viewportDimension;
    for (final rect in _itemPaintRects) {
      if (rect.left < 0.0 ||
          rect.top < 0.0 ||
          rect.right > extent.width ||
          rect.bottom > extent.height) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_cellPaintOrder.isEmpty &&
        _itemPaintOrder.isEmpty &&
        _frozenPaintOrder.isEmpty) {
      // A board that overflowed and then emptied must not keep the last
      // clip layer alive in the handle. The background still paints: the
      // painter reads whatever bounds the last layout recorded and
      // decides. The bounds are usually empty here, but a builder that
      // returns null for every visible cell empties the lists while the
      // bounds stay real.
      _clipRectLayer.layer = null;
      _paintBackground(context, offset);
      return;
    }
    // THE PAINTED-RECT SCRATCH, filled once for this call. An item's
    // painted rect is its paint offset composed with the coordinator's
    // animation offset, which costs a vicinity lookup and two engine
    // reads with a curve evaluation each; the overflow test, the
    // visibility gate and the paint offset all want it, so it is
    // computed here rather than three times per item.
    //
    // Valid for THIS call only. Hit-testing and `itemAt` deliberately
    // read live: a tick between a paint and a pointer event moves the
    // shift, and a stale rect would find an item where it no longer
    // paints.
    _itemPaintRects.clear();
    for (final child in _itemPaintOrder) {
      _itemPaintRects.add(_paintedRectOf(child));
    }
    // The layout flag counts cells only: the positioning sweep's item arm
    // `continue`s before the overflow test. Items are decided HERE, at
    // paint, because their shift moves on paint-only ticks with no
    // layout: a drop-settle glide from a proxy released outside the
    // viewport starts outside it, and a lattice smaller than its
    // viewport has no overflowing cell to raise the flag for it.
    //
    // `clipBehavior` is read FIRST, so a board that does not clip runs
    // no overflow test at all.
    if (clipBehavior != Clip.none &&
        (_hasVisualOverflow || _anyItemPaintsOutsideViewport())) {
      _clipRectLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & viewportDimension,
        _paintPlanes,
        clipBehavior: clipBehavior,
        oldLayer: _clipRectLayer.layer,
      );
    } else {
      _clipRectLayer.layer = null;
      _paintPlanes(context, offset);
    }
  }

  void _paintPlanes(PaintingContext context, Offset offset) {
    _paintBackground(context, offset);
    _paintCells(context, offset, _cellPaintOrder, 0, _cellPaintOrder.length);
    _paintItems(context, offset, 0, _bandItemStart);
    _paintCells(context, offset, _frozenPaintOrder, 0, _cornerCellStart);
    _paintItems(context, offset, _bandItemStart, _cornerItemStart);
    _paintCells(
      context,
      offset,
      _frozenPaintOrder,
      _cornerCellStart,
      _frozenPaintOrder.length,
    );
    _paintItems(context, offset, _cornerItemStart, _itemPaintOrder.length);
  }

  void _paintCells(
    PaintingContext context,
    Offset offset,
    List<RenderBox> cells,
    int from,
    int to,
  ) {
    for (var i = from; i < to; i++) {
      final child = cells[i];
      final childParentData = parentDataOf(child);
      if (childParentData.isVisible) {
        context.paintChild(child, offset + childParentData.paintOffset!);
      }
    }
  }

  void _paintItems(PaintingContext context, Offset offset, int from, int to) {
    final viewport = Offset.zero & viewportDimension;
    for (var i = from; i < to; i++) {
      final child = _itemPaintOrder[i];
      // The PAINTED rect gates, not the base's `isVisible`: see
      // [_paintsItem]. Read from the scratch, so this loop and the
      // overflow test above share one evaluation per item.
      final rect = _itemPaintRects[i];
      if (rect.overlaps(viewport)) {
        context.paintChild(child, offset + rect.topLeft);
      }
    }
  }

  /// The SEMANTICS walk, in PAINT order: the six planes of
  /// [_frozenPaintOrder]'s doc, bottom to top, as [_paintPlanes] draws
  /// them.
  ///
  /// The base walks the sibling chain, which is sorted by vicinity
  /// (`widgets/two_dimensional_viewport.dart:949-960`), and a semantics
  /// node's hit-test order is its child list reversed
  /// (`semantics/semantics.dart:4064-4071`). On the chain a frozen header
  /// came BEFORE the content cell scrolled under it, and an item before a
  /// later row's cell it covers, so explore-by-touch found the covered
  /// node. Reading order is not this list's: with a text direction in
  /// scope the framework sorts the children geometrically
  /// (`semantics/semantics.dart:4234-4240`).
  ///
  /// The SET is the base's: the chain holds the children obtained this
  /// layout, and the final sweep files every non-null one in exactly one
  /// list. Nothing here writes keep-alive, so there is no bucket to
  /// leave out. After a layout that threw, the lists are the previous
  /// sweep's and the chain is empty, so the base's walk runs instead
  /// ([_paintListsCurrent]).
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_paintListsCurrent) {
      super.visitChildrenForSemantics(visitor);
      return;
    }
    assert(() {
      var chain = 0;
      visitChildren((child) {
        chain += 1;
      });
      final listed =
          _cellPaintOrder.length +
          _itemPaintOrder.length +
          _frozenPaintOrder.length;
      if (chain != listed) {
        throw FlutterError(
          "RenderBoardViewport's semantics walk lists $listed children "
          "and the viewport holds $chain. The paint lists are rebuilt by "
          "the final positioning sweep of every layout and must hold "
          "every child that layout kept.",
        );
      }
      return true;
    }());
    _cellPaintOrder.forEach(visitor);
    for (var i = 0; i < _bandItemStart; i++) {
      visitor(_itemPaintOrder[i]);
    }
    for (var i = 0; i < _cornerCellStart; i++) {
      visitor(_frozenPaintOrder[i]);
    }
    for (var i = _bandItemStart; i < _cornerItemStart; i++) {
      visitor(_itemPaintOrder[i]);
    }
    for (var i = _cornerCellStart; i < _frozenPaintOrder.length; i++) {
      visitor(_frozenPaintOrder[i]);
    }
    for (var i = _cornerItemStart; i < _itemPaintOrder.length; i++) {
      visitor(_itemPaintOrder[i]);
    }
  }

  /// Where [child] can be SEEN, for the semantics pass, which flags a
  /// node hidden when its rect misses this (`rendering/object.dart:6719-6729`).
  ///
  /// Null under [Clip.none]: a render object that clips with a `Clip`
  /// must describe no clip when it does not clip
  /// (`rendering/object.dart:3747-3750`). Otherwise the viewport on each
  /// axis [child] is PINNED on, and the scrolled region between the
  /// frozen bands on each axis it scrolls on, because the bands paint
  /// over whatever scrolls under them. That is `RenderViewport`'s rule for
  /// the content under a pinned header (`rendering/viewport.dart:886-933`)
  /// on both axes: a cell outside the viewport, a content cell under a
  /// header band, and a header cell slid under the corner are hidden; a
  /// corner cell is not.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    if (clipBehavior == Clip.none) {
      return null;
    }
    final viewport = Offset.zero & viewportDimension;
    final data = child.parentData;
    if (data is! _BoardChildParentData) {
      return viewport;
    }
    final region = scrolledRegion;
    return Rect.fromLTRB(
      data.pinnedHorizontal ? viewport.left : region.left,
      data.pinnedVertical ? viewport.top : region.top,
      data.pinnedHorizontal ? viewport.right : region.right,
      data.pinnedVertical ? viewport.bottom : region.bottom,
    );
  }

  /// Which children's semantics nodes are KEPT: the viewport grown by the
  /// cache region on both axes, the region layout builds. A node inside it
  /// and outside [describeApproximatePaintClip] is kept flagged hidden,
  /// which a screen reader's implicit scrolling moves onto; without this
  /// the semantics clip falls back to the paint clip
  /// (`rendering/object.dart:6700-6701`), which empties such a node's
  /// rect, and a node with an empty rect is dropped from its parent's
  /// children (`rendering/object.dart:6246`,
  /// `semantics/semantics.dart:2907`).
  /// `RenderViewport` grows its own along its one axis
  /// (`rendering/viewport.dart:938-960`).
  @override
  Rect? describeSemanticsClip(RenderObject? child) {
    final cache = _resolveCacheTerms();
    final size = viewportDimension;
    return Rect.fromLTRB(
      -cache.dx,
      -cache.dy,
      size.width + cache.dx,
      size.height + cache.dy,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Exact reverse of the paint walk, so the child drawn on top is the
    // child that takes the pointer; see [_frozenPaintOrder] for the six
    // planes.
    return _hitTestItems(
          result,
          position,
          _cornerItemStart,
          _itemPaintOrder.length,
        ) ||
        _hitTestCells(
          result,
          position,
          _frozenPaintOrder,
          _cornerCellStart,
          _frozenPaintOrder.length,
        ) ||
        _hitTestItems(result, position, _bandItemStart, _cornerItemStart) ||
        _hitTestCells(
          result,
          position,
          _frozenPaintOrder,
          0,
          _cornerCellStart,
        ) ||
        _hitTestItems(result, position, 0, _bandItemStart) ||
        _hitTestCells(
          result,
          position,
          _cellPaintOrder,
          0,
          _cellPaintOrder.length,
        );
  }

  bool _hitTestCells(
    BoxHitTestResult result,
    Offset position,
    List<RenderBox> cells,
    int from,
    int to,
  ) {
    for (var i = to - 1; i >= from; i--) {
      final child = cells[i];
      final childParentData = parentDataOf(child);
      if (childParentData.isVisible &&
          _hitTestChild(
            child,
            result,
            position,
            childParentData.paintOffset!,
          )) {
        return true;
      }
    }
    return false;
  }

  bool _hitTestItems(
    BoxHitTestResult result,
    Offset position,
    int from,
    int to,
  ) {
    for (var i = to - 1; i >= from; i--) {
      final child = _itemPaintOrder[i];
      // An EXITING item takes no pointer, as `itemAt` finds none: the
      // model no longer holds it, and the pointer reaches what lies
      // under it.
      final id = _vicinityToItemId[parentDataOf(child).vicinity];
      if (id != null && _controller.anim.isExitingItem(id)) {
        continue;
      }
      // The same predicate and the same rect the paint walk reads, so an
      // item is found exactly where it is drawn.
      if (_paintsItem(child) &&
          _hitTestChild(
            child,
            result,
            position,
            _paintedRectOf(child).topLeft,
          )) {
        return true;
      }
    }
    return false;
  }

  /// Hit-tests one child drawn at [paintOffset]; the caller has already
  /// decided the child paints, by the base's flag for a cell or a frozen
  /// child and by [_paintsItem] for an item.
  bool _hitTestChild(
    RenderBox child,
    BoxHitTestResult result,
    Offset position,
    Offset paintOffset,
  ) {
    return result.addWithPaintOffset(
      offset: paintOffset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return child.hitTest(result, position: transformed);
      },
    );
  }

  /// Mirrors the paint pass exactly, including the per-item shift, so
  /// `localToGlobal` and semantics rects report where a child is drawn
  /// rather than where its `paintOffset` alone would put it.
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final childParentData = parentDataOf(child);
    final paintOffset =
        childParentData.paintOffset! + _paintShiftOf(childParentData.vicinity);
    transform.translateByDouble(paintOffset.dx, paintOffset.dy, 0.0, 1.0);
  }

  /// Reveals against the viewport the user can see into, which is the
  /// viewport minus its frozen bands, and never scrolls on an axis where
  /// the child is PINNED, since a frozen cell or a pinned item is on
  /// screen at every offset there.
  ///
  /// Built on the base's own answer for alignment 0, the offset that puts
  /// the rect's leading edge at the viewport's leading edge
  /// (`widgets/two_dimensional_viewport.dart:1024-1097`): the leading
  /// band's extent is subtracted from it, and [alignment] spreads the rect
  /// across the unfrozen extent rather than the whole one.
  @override
  RevealedOffset getOffsetToReveal(
    RenderObject target,
    double alignment, {
    Rect? rect,
    Axis? axis,
  }) {
    final resolvedAxis = axis ?? mainAxis;
    final vertical = resolvedAxis == Axis.vertical;
    var child = target;
    while (child.parent != this) {
      child = child.parent!;
    }
    final data = child.parentData! as _BoardChildParentData;
    final pixels = vertical ? verticalOffset.pixels : horizontalOffset.pixels;
    final current = MatrixUtils.transformRect(
      target.getTransformTo(this),
      rect ?? target.paintBounds,
    );
    if (vertical ? data.pinnedVertical : data.pinnedHorizontal) {
      return RevealedOffset(offset: pixels, rect: current);
    }
    final base = super.getOffsetToReveal(
      target,
      0.0,
      rect: rect,
      axis: resolvedAxis,
    );
    final region = _unfrozenNormalized(resolvedAxis);
    final extent = vertical ? current.height : current.width;
    final spare = math.max(0.0, region.hi - region.lo - extent);
    final offset = base.offset - region.lo - spare * alignment;
    // `current` is where the rect paints at `pixels`; at `offset` the
    // content has moved by the difference toward the axis's leading side.
    final moved = pixels - offset;
    final revealed = switch (vertical
        ? verticalAxisDirection
        : horizontalAxisDirection) {
      AxisDirection.up => current.translate(0.0, -moved),
      AxisDirection.down => current.translate(0.0, moved),
      AxisDirection.left => current.translate(-moved, 0.0),
      AxisDirection.right => current.translate(moved, 0.0),
    };
    return RevealedOffset(offset: offset, rect: revealed);
  }

  @override
  void dispose() {
    // Safe only here: after dispose the object is no longer usable. A
    // detach or a controller swap must both leave the map alone, so a
    // retained exit survives both and its release stays reachable.
    _retainedExits.clear();
    _clipRectLayer.layer = null;
    super.dispose();
  }

  // -----------------------------------------------------------------
  // BoardRenderPort. Every Offset and Rect here is VIEWPORT PAINT space.
  // -----------------------------------------------------------------

  @override
  bool get isLaidOut {
    return hasSize;
  }

  @override
  bool drivesController(Object boardController) {
    return identical(boardController, _controller);
  }

  @override
  Offset globalToPaintLocal(Offset global) {
    return globalToLocal(global);
  }

  @override
  void pinItem(TKey key) {
    _pinnedDragKey = key;
  }

  @override
  void unpinItem(TKey key) {
    if (_pinnedDragKey == key) {
      _pinnedDragKey = null;
    }
  }

  @override
  ({int row, int col})? cellAt(Offset local) {
    if (!hasSize) {
      return null;
    }
    final row = _trackCoordinateAt(Axis.vertical, local.dy, clamp: false);
    final col = _trackCoordinateAt(Axis.horizontal, local.dx, clamp: false);
    if (row == null || col == null) {
      return null;
    }
    return (
      row: row.floor().clamp(0, _controller.rows.axis.trackCount - 1),
      col: col.floor().clamp(0, _controller.columns.axis.trackCount - 1),
    );
  }

  @override
  ({int row, int col})? frozenCellAt(Offset local) {
    if (!hasSize) {
      return null;
    }
    // A cell of a band: the point is in a band on at least one axis, and
    // the other axis resolves through the same mapping, so a pointer in
    // the header band lands on the header cell of the column under it.
    if (!_inFrozenBand(Axis.vertical, local.dy) &&
        !_inFrozenBand(Axis.horizontal, local.dx)) {
      return null;
    }
    return cellAt(local);
  }

  /// Whether the paint-space coordinate [paint] on [axis] lies inside one
  /// of that axis's frozen bands as they paint.
  bool _inFrozenBand(Axis axis, double paint) {
    final region = _unfrozenNormalized(axis);
    final normalized = _normalizedFromPaint(axis, paint);
    final viewport = axis == Axis.vertical
        ? viewportDimension.height
        : viewportDimension.width;
    return (normalized >= 0.0 && normalized < region.lo) ||
        (normalized >= region.hi && normalized < viewport);
  }

  /// THE POINT MAPPING: the fractional track coordinate (the track plus
  /// the fraction into it) that PAINTS under the paint-space coordinate
  /// [paint] on [axis]. Every point query on the port reads it, so a
  /// selection, a drop and a probe agree with each other and with paint.
  ///
  /// Three regions along the axis, in NORMALIZED space ([scrolledRegion]
  /// in paint space): the leading band's tracks inside `[0, lo)`, where
  /// frozen cells paint at their content offsets; the trailing band's
  /// inside `[hi, viewport)`, pinned to the trailing edge; and between
  /// them the SCROLLED tracks, the normalized coordinate plus the scroll
  /// offset read through the ANIMATED geometry, exactly as those cells are
  /// laid out mid track resize. A band reads settled offsets, as its cells
  /// do.
  ///
  /// [clamp] true answers for every coordinate: a point past a band's
  /// viewport edge takes that band's outer end, and the scrolled region is
  /// clamped into the unfrozen tracks, which with no band is
  /// `[0, trackCount]`. False answers null wherever no track paints: past
  /// the viewport beside a band, past either end of the lattice, and in
  /// the gap a short lattice leaves above a trailing band.
  double? _trackCoordinateAt(Axis axis, double paint, {required bool clamp}) {
    final vertical = axis == Axis.vertical;
    final config = vertical ? _controller.rows : _controller.columns;
    final boardAxis = config.axis;
    final count = boardAxis.trackCount;
    if (count == 0) {
      return null;
    }
    final lead = config.leadingBandEnd;
    final trailFrom = config.trailingBandStart;
    final viewport = vertical
        ? viewportDimension.height
        : viewportDimension.width;
    final region = _unfrozenNormalized(axis);
    final normalized = _normalizedFromPaint(axis, paint);
    if (lead > 0 && normalized < region.lo) {
      if (normalized < 0.0 && !clamp) {
        return null;
      }
      return _settledCoordinateOf(boardAxis, math.max(0.0, normalized));
    }
    if (trailFrom < count && normalized >= region.hi) {
      if (normalized >= viewport && !clamp) {
        return null;
      }
      final content =
          boardAxis.totalExtent - (viewport - math.min(normalized, viewport));
      return _settledCoordinateOf(boardAxis, content);
    }
    final pixels = vertical ? verticalOffset.pixels : horizontalOffset.pixels;
    final content = normalized + pixels;
    final track = _animatedTrackAt(axis, boardAxis, math.max(0.0, content));
    final trackLead = _animatedOffsetOf(axis, boardAxis, track);
    final trackExtent = _animatedExtentOf(axis, boardAxis, track);
    final coordinate = trackExtent <= 0.0
        ? track.toDouble()
        : track + (content - trackLead) / trackExtent;
    if (!clamp) {
      if (coordinate < lead || coordinate >= trailFrom) {
        return null;
      }
      return coordinate;
    }
    return coordinate.clamp(lead.toDouble(), trailFrom.toDouble());
  }

  /// The settled track coordinate of the content-space [content], clamped
  /// into `[0, trackCount]`.
  double _settledCoordinateOf(BoardAxis axis, double content) {
    if (content <= 0.0) {
      return 0.0;
    }
    if (content >= axis.totalExtent) {
      return axis.trackCount.toDouble();
    }
    final track = axis.trackAt(content);
    return track + (content - axis.offsetOf(track)) / axis.extentOf(track);
  }

  /// The NORMALIZED interval `[lo, hi]` the scrolled tracks show through
  /// on [axis]: the viewport minus its two frozen bands, each band's
  /// extent settled as its cells are placed. Empty (`lo == hi`) when the
  /// bands fill the viewport.
  ({double lo, double hi}) _unfrozenNormalized(Axis axis) {
    final vertical = axis == Axis.vertical;
    final config = vertical ? _controller.rows : _controller.columns;
    final viewport = vertical
        ? viewportDimension.height
        : viewportDimension.width;
    final leading = config.leadingBandExtent;
    final trailing = config.trailingBandExtent;
    final lo = math.min(leading, viewport);
    final hi = math.max(lo, viewport - trailing);
    return (lo: lo, hi: hi);
  }

  @override
  Rect get scrolledRegion {
    if (!hasSize) {
      return Rect.zero;
    }
    final v = _unfrozenNormalized(Axis.vertical);
    final h = _unfrozenNormalized(Axis.horizontal);
    final size = viewportDimension;
    final upward = verticalAxisDirection == AxisDirection.up;
    final leftward = horizontalAxisDirection == AxisDirection.left;
    return Rect.fromLTRB(
      leftward ? size.width - h.hi : h.lo,
      upward ? size.height - v.hi : v.lo,
      leftward ? size.width - h.lo : h.hi,
      upward ? size.height - v.lo : v.hi,
    );
  }

  /// A paint-space POINT's normalized viewport coordinate: reversal
  /// undone, no scroll term. The frozen bands live in this space.
  double _normalizedFromPaint(Axis axis, double paint) {
    switch (axis) {
      case Axis.vertical:
        if (verticalAxisDirection == AxisDirection.down) {
          return paint;
        }
        return viewportDimension.height - paint;
      case Axis.horizontal:
        if (horizontalAxisDirection == AxisDirection.right) {
          return paint;
        }
        return viewportDimension.width - paint;
    }
  }

  /// Paint pass 0: the background painter, directly on the canvas,
  /// translated to this render object's origin so the painter works in
  /// viewport-paint space.
  void _paintBackground(PaintingContext context, Offset offset) {
    final background = _background;
    if (background == null) {
      return;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    background.paint(canvas, this);
    canvas.restore();
  }

  @override
  Iterable<int> frozenTracksOf(Axis axis) {
    final config = axis == Axis.vertical
        ? _controller.rows
        : _controller.columns;
    return config.frozenTracks;
  }

  @override
  Rect visibleCellRect(int row, int col) {
    final rowsConfig = _controller.rows;
    final columnsConfig = _controller.columns;
    final rowAxis = rowsConfig.axis;
    final columnAxis = columnsConfig.axis;
    final rowFrozen =
        row >= 0 && row < rowAxis.trackCount && rowsConfig.isFrozenTrack(row);
    final colFrozen =
        col >= 0 &&
        col < columnAxis.trackCount &&
        columnsConfig.isFrozenTrack(col);
    assert(
      (rowFrozen || (row >= _firstVisibleRow && row <= _lastVisibleRow)) &&
          (colFrozen || (col >= _firstVisibleCol && col <= _lastVisibleCol)),
      "visibleCellRect($row, $col) is outside the visible bounds, rows "
      "$_firstVisibleRow..$_lastVisibleRow, cols "
      "$_firstVisibleCol..$_lastVisibleCol, and not in a frozen band.",
    );
    return _cellRect(row, col, rowFrozen: rowFrozen, colFrozen: colFrozen);
  }

  /// Where cell `(row, col)` paints, both indices in range: a frozen
  /// track where its frozen children paint (the normalized viewport-pinned
  /// position of `_positionObtainedChildren`, through the reversal rule
  /// `computeAbsolutePaintOffsetFor` applies to a layoutOffset), and a
  /// scrolled one at its animated offset. The one computation behind
  /// [visibleCellRect] and [rectOfCell].
  Rect _cellRect(
    int row,
    int col, {
    required bool rowFrozen,
    required bool colFrozen,
  }) {
    final rowsConfig = _controller.rows;
    final columnsConfig = _controller.columns;
    final rowAxis = rowsConfig.axis;
    final columnAxis = columnsConfig.axis;
    final width = _animatedExtentOf(Axis.horizontal, columnAxis, col);
    final height = _animatedExtentOf(Axis.vertical, rowAxis, row);
    return Rect.fromLTWH(
      colFrozen
          ? _paintFromNormalized(
              Axis.horizontal,
              _frozenNormalizedPosition(
                columnsConfig,
                col,
                viewportDimension.width,
              ),
              width,
            )
          : _paintFromContent(
              Axis.horizontal,
              _animatedOffsetOf(Axis.horizontal, columnAxis, col),
              width,
            ),
      rowFrozen
          ? _paintFromNormalized(
              Axis.vertical,
              _frozenNormalizedPosition(
                rowsConfig,
                row,
                viewportDimension.height,
              ),
              height,
            )
          : _paintFromContent(
              Axis.vertical,
              _animatedOffsetOf(Axis.vertical, rowAxis, row),
              height,
            ),
      width,
      height,
    );
  }

  /// Paint-space start of a NORMALIZED viewport span (no scroll term, the
  /// space the frozen bands live in): the normalized value unreversed, and
  /// the viewport extent minus the span's far edge reversed, which is the
  /// expression `computeAbsolutePaintOffsetFor` applies to a frozen
  /// child's layoutOffset (`widgets/two_dimensional_viewport.dart:1626-1640`).
  double _paintFromNormalized(Axis axis, double normalized, double extent) {
    switch (axis) {
      case Axis.vertical:
        if (verticalAxisDirection == AxisDirection.down) {
          return normalized;
        }
        return viewportDimension.height - (normalized + extent);
      case Axis.horizontal:
        if (horizontalAxisDirection == AxisDirection.right) {
          return normalized;
        }
        return viewportDimension.width - (normalized + extent);
    }
  }

  @override
  Rect? rectOfCell(int row, int col) {
    if (!hasSize) {
      return null;
    }
    final rowsConfig = _controller.rows;
    final columnsConfig = _controller.columns;
    if (row < 0 || row >= rowsConfig.axis.trackCount) {
      return null;
    }
    if (col < 0 || col >= columnsConfig.axis.trackCount) {
      return null;
    }
    return _cellRect(
      row,
      col,
      rowFrozen: rowsConfig.isFrozenTrack(row),
      colFrozen: columnsConfig.isFrozenTrack(col),
    );
  }

  @override
  TKey? itemAt(Offset local) {
    if (!hasSize) {
      return null;
    }
    // The topmost item under the pointer, down the planes in the order
    // hit-testing walks them. A frozen cell painted over the point ends
    // the walk: the band hides every item beneath it. Items animating out
    // and the dragged item are passed over: neither can be a tap target
    // or a drop target.
    TKey? itemIn(int from, int to) {
      for (var i = to - 1; i >= from; i--) {
        final child = _itemPaintOrder[i];
        final childParentData = parentDataOf(child);
        if (childParentData.paintOffset == null) {
          continue;
        }
        // The painted rect, the same one hit-testing reads: a probe must
        // agree with what paints, held gaps included.
        if (_paintedRectOf(child).contains(local)) {
          final id = _vicinityToItemId[childParentData.vicinity];
          if (id == null) {
            continue;
          }
          if (_controller.anim.isExitingItem(id) ||
              _controller.isDraggingId(id)) {
            continue;
          }
          return _controller.keyOfId(id);
        }
      }
      return null;
    }

    bool coveredByFrozen(int from, int to) {
      for (var i = to - 1; i >= from; i--) {
        final child = _frozenPaintOrder[i];
        final childParentData = parentDataOf(child);
        if (childParentData.isVisible &&
            (childParentData.paintOffset! & child.size).contains(local)) {
          return true;
        }
      }
      return false;
    }

    final corner = itemIn(_cornerItemStart, _itemPaintOrder.length);
    if (corner != null) {
      return corner;
    }
    if (coveredByFrozen(_cornerCellStart, _frozenPaintOrder.length)) {
      return null;
    }
    final band = itemIn(_bandItemStart, _cornerItemStart);
    if (band != null) {
      return band;
    }
    if (coveredByFrozen(0, _cornerCellStart)) {
      return null;
    }
    return itemIn(0, _bandItemStart);
  }

  @override
  Rect? rectOfItem(TKey key) {
    if (!hasSize) {
      return null;
    }
    final id = _controller.idOfKey(key);
    if (id < 0) {
      return null;
    }
    final pinV = _controller.pinOfId(id, Axis.vertical);
    final pinH = _controller.pinOfId(id, Axis.horizontal);
    final vertical = _itemSpanGeometry(id, Axis.vertical, pinV);
    final horizontal = _itemSpanGeometry(id, Axis.horizontal, pinH);
    return Rect.fromLTWH(
      _paintFromNormalized(
        Axis.horizontal,
        _normalizedItemLead(Axis.horizontal, pinH, horizontal.lead),
        horizontal.extent,
      ),
      _paintFromNormalized(
        Axis.vertical,
        _normalizedItemLead(Axis.vertical, pinV, vertical.lead),
        vertical.extent,
      ),
      horizontal.extent,
      vertical.extent,
    );
  }

  @override
  Rect? paintedRectOfItem(TKey key) {
    final rect = rectOfItem(key);
    if (rect == null) {
      return null;
    }
    // Total over live keys rather than mounted children: the drag layer
    // captures every key the make-room preview holds, mounted or not,
    // and [rectOfItem]'s extent is the extent the geometry rule lays the
    // child out at, so this is [_paintedRectOf] for a mounted child and
    // the rect that child would paint at otherwise.
    return rect.shift(_paintShiftOfId(_controller.idOfKey(key)));
  }

  /// On a zero-track axis this returns (0, 0), which is not a cell: there
  /// is no legal drop cell on an empty lattice, the signature is
  /// non-nullable, and the drag layer cannot start a drag on an empty
  /// board anyway. Callers that can see an empty board gate on trackCount.
  @override
  ({int row, int col}) resolveDropCell(Offset local) {
    if (!hasSize) {
      return (row: 0, col: 0);
    }
    // NEAREST, not containment: the fractional track-space coordinate is
    // rounded by the same rule BoardSnap.track's quantize applies, so
    // the cell route and the trackSpaceAt route agree on where an anchor
    // between two boundaries lands. Both read the one point mapping.
    final row = _trackCoordinateAt(Axis.vertical, local.dy, clamp: true);
    final col = _trackCoordinateAt(Axis.horizontal, local.dx, clamp: true);
    return (
      row: row == null
          ? 0
          : row.round().clamp(0, _controller.rows.axis.trackCount - 1),
      col: col == null
          ? 0
          : col.round().clamp(0, _controller.columns.axis.trackCount - 1),
    );
  }

  @override
  ({double row, double col})? trackSpaceAt(Offset local) {
    if (!hasSize) {
      return null;
    }
    final row = _trackCoordinateAt(Axis.vertical, local.dy, clamp: true);
    final col = _trackCoordinateAt(Axis.horizontal, local.dx, clamp: true);
    if (row == null || col == null) {
      return null;
    }
    return (row: row, col: col);
  }

  @override
  ScrollPosition? get verticalPosition {
    final offset = verticalOffset;
    return offset is ScrollPosition ? offset : null;
  }

  @override
  ScrollPosition? get horizontalPosition {
    final offset = horizontalOffset;
    return offset is ScrollPosition ? offset : null;
  }

  /// The LEADING frozen band's total extent on [axis]: what a scroll
  /// target must be inset by to land below the band. 0.0 with no frozen
  /// tracks, which is also what a board with no port reports, so a caller
  /// cannot tell the two apart.
  @override
  double frozenInsetOf(Axis axis) {
    final config = axis == Axis.vertical
        ? _controller.rows
        : _controller.columns;
    return config.leadingBandExtent;
  }

  /// Viewport-paint-space LEADING edge of a content-space interval. Under
  /// reversal the leading edge is the far side of the interval, which is
  /// why this takes the extent and [_normalizedFromPaint], which maps a
  /// point, does not.
  double _paintFromContent(Axis axis, double contentStart, double extent) {
    switch (axis) {
      case Axis.vertical:
        final local = contentStart - verticalOffset.pixels;
        if (verticalAxisDirection == AxisDirection.down) {
          return local;
        }
        return viewportDimension.height - (local + extent);
      case Axis.horizontal:
        final local = contentStart - horizontalOffset.pixels;
        if (horizontalAxisDirection == AxisDirection.right) {
          return local;
        }
        return viewportDimension.width - (local + extent);
    }
  }
}

/// The viewport's parent data: the base's, widened by the per-cell
/// MEASUREMENT CACHE the measure step reads and writes.
///
/// Three fields and one rule between them (the measure step is the only
/// writer of the first two, and the surface's poke the only writer of
/// the third). They sit here rather than in a map keyed by vicinity
/// because a child's parent data moves with the child: a vicinity that
/// is re-keyed by an ordinal shift carries its measurement along, and a
/// child that unmounts takes its entry with it, so nothing has to be
/// swept.
class _BoardChildParentData extends TwoDimensionalViewportParentData {
  /// The child's extent along the content-sized axis under
  /// [measuredUnder], or null when it has never been measured. A null is
  /// what makes a newly obtained vicinity measure on its first layout.
  double? measured;

  /// The measuring constraints [measured] was taken under. Compared by
  /// VALUE, which is what re-measures a cell whose fixed-axis track
  /// changed extent, or whose alignment stopped tightening it, without
  /// either needing a flag of its own.
  BoxConstraints? measuredUnder;

  /// Set by the cell surface's poke and cleared by the measurement that
  /// answers it. The cell's host rebuilt, so its builder may have
  /// returned content of a different size.
  bool remeasure = false;

  /// Whether the child is pinned to the viewport on each axis: a cell in
  /// a frozen track, or an item wholly inside a frozen band. Written by
  /// the positioning sweep, read by `getOffsetToReveal`, for which a
  /// pinned axis needs no scroll.
  bool pinnedVertical = false;
  bool pinnedHorizontal = false;
}

/// A cell's measurement TRIGGER: a proxy the cell host wraps its content
/// in, whose widget calls [requestRemeasure] on every host rebuild.
///
/// It exists because a rebuild is not otherwise observable from here. A
/// cell is laid out tight by the positioning sweep, which makes it a
/// relayout boundary (`rendering/object.dart:2847`) whose dirtiness
/// stops at itself (`rendering/object.dart:2667`); a proxy that
/// overrode `markNeedsLayout` would never see one. What does happen on
/// every host rebuild is `RenderObjectElement.update`'s call to
/// `updateRenderObject` (`widgets/framework.dart:6837`), because the
/// host hands down a fresh widget instance, and that is the signal this
/// class turns into a re-measurement.
///
/// Public only because it is named by a widget in another library of
/// this module; the barrel exports `RenderBoardViewport` alone, so it is
/// unreachable from app code.
class RenderBoardCellSurface extends RenderProxyBox {
  /// Marks this cell for re-measurement on the enclosing board's next
  /// layout, and schedules that layout unless one is already running.
  ///
  /// Walks up to the [RenderBoardViewport], keeping the last node before
  /// it: that node is the child the viewport holds and owns the parent
  /// data the cache lives in. The walk is one or two hops, the delegate's
  /// `RepaintBoundary` (`widgets/scroll_delegate.dart:1122`) being the
  /// only thing that can sit between, and it is a walk rather than a
  /// stored reference because a `GlobalKey` move can re-parent a cell
  /// between boards.
  ///
  /// A detached surface, or one with no board above it, returns having
  /// done nothing: neither can be showing a measured cell.
  void requestRemeasure() {
    if (!attached) {
      return;
    }
    RenderObject top = this;
    RenderObject? node = parent;
    while (node != null && node is! RenderBoardViewport) {
      top = node;
      node = node.parent;
    }
    if (node is! RenderBoardViewport || top is! RenderBox) {
      return;
    }
    node._requestRemeasure(top);
  }
}
