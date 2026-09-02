/// The board's L3 render object: a two-axis viewport that lays out one
/// child per lattice CELL, sizes content-sized tracks from what those
/// cells measure, and holds the scroll anchor still while it does.
///
/// Not yet present: every animation read, and the drag pin's effect on
/// keep-alive retention. Each site that would otherwise read as an
/// omission says so.
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
  /// The cap is the assert that fires when the argument is wrong: an
  /// extent oscillating between passes of one layout.
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

  /// The PER-AXIS paint-only offset magnitudes the last layout WIDENED its
  /// obtain window by, and recorded.
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

  /// The item a drag session holds, or null when no session is live. At
  /// most one, because at most one session is live.
  ///
  /// Written only by [pinItem] and [unpinItem]. What CONSUMES it is the
  /// keep-alive sweep's pin leg, which retains unconditionally; no drag
  /// layer exists yet to take a pin.
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

  /// The two prior-tick mirrors of the animation-listener routing: a
  /// settle tick reads idle on every level, so only the prior tick's
  /// levels can route it to the one layout that reads the settled state.
  bool _priorTickHadLayoutDriving = false;
  bool _priorTickHadOffsets = false;

  bool _subscribed = false;

  /// Paint plane 1: cells in unfrozen tracks. Cleared and rebuilt exactly
  /// once per `layoutChildSequence`, in the final positioning sweep, never
  /// per pass: appended per pass, a vicinity obtained by two passes paints
  /// twice; cleared per pass, a pass-1-only child drops out of paint AND
  /// its hit-test mirror.
  final List<RenderBox> _cellPaintOrder = <RenderBox>[];

  /// Paint plane 2: items. Laned items by lane then id; non-laned items
  /// last, so they paint above the laned stack in their track.
  final List<RenderBox> _itemPaintOrder = <RenderBox>[];

  /// Paint plane 3: cells in frozen tracks, with cells frozen on BOTH axes
  /// (the corner) last. The corner must outpaint the two bands because a
  /// band cell scrolled along its unfrozen axis can slide into the corner
  /// rectangle.
  final List<RenderBox> _frozenPaintOrder = <RenderBox>[];

  /// Item child back to its store id, for the paint-time animation shift
  /// and for [applyPaintTransform]'s mirror of it. Rebuilt in the same
  /// sweep as the paint lists.
  final Map<ChildVicinity, int> _vicinityToItemId = <ChildVicinity, int>{};

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

  /// First row track intersecting the visible rect. The four window
  /// bounds are overwritten once per `layoutChildSequence`, from the
  /// settling pass's window, and describe the VISIBLE rect rather than the
  /// wider obtain window. An empty axis reports `first` 0 and `last` -1.
  @override
  int get firstVisibleRow {
    return _firstVisibleRow;
  }

  /// Last row track intersecting the visible rect. See [firstVisibleRow].
  @override
  int get lastVisibleRow {
    return _lastVisibleRow;
  }

  /// First column track intersecting the visible rect. See
  /// [firstVisibleRow].
  @override
  int get firstVisibleCol {
    return _firstVisibleCol;
  }

  /// Last column track intersecting the visible rect. See
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

  /// A selection change alters what every cell in the old and new
  /// rectangles builds, and the builders are reachable only through a
  /// delegate rebuild. This listener lives here and not on `Board`'s
  /// `State` because `markNeedsLayout(withDelegateRebuild: true)` is a
  /// render-object call; a `setState` up there reaches nothing, for the
  /// reason documented at the widget's listener comment.
  void _handleSelectionChanged() {
    markNeedsLayout(withDelegateRebuild: true);
  }

  /// A structural change relays out, and rebuilds every obtained child
  /// unless the key set says no built child's builder output changed.
  ///
  /// An EMPTY set means exactly that, so it takes the cheaper route; null
  /// and a non-empty set both take the delegate rebuild, which is the only
  /// route to a child's builder the viewport's private element leaves open
  /// (R-7).
  void _handleStructuralChange(Set<TKey>? affectedKeys) {
    markNeedsLayout(
      withDelegateRebuild: affectedKeys == null || affectedKeys.isNotEmpty,
    );
  }

  /// A payload-only write. R-7: there is no targeted-rebuild hook, so this
  /// rebuilds every obtained child. Accepted for v1; the cost is bounded
  /// by the mounted set, which is viewport-bounded.
  void _handleItemDataChange(TKey key) {
    markNeedsLayout(withDelegateRebuild: true);
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
  ///    by make-room motion ON A CONTENT-SIZED LANE AXIS, where a gap
  ///    moves a track's extent. The disjunct IS the latch: a settle
  ///    tick's record is already gone, and this is the one layout that
  ///    reads the settled extent and progress.
  /// 2. The make-room generation moved on a content-sized lane axis:
  ///    relayout. A SNAPPED slot-only install carries no motion and
  ///    displaces nobody, so no other arm can fire for it, and the same
  ///    arm carries that gap's close.
  /// 3. Offsets just went idle: one relayout, to re-narrow the window
  ///    the admitted bound widened.
  /// 4. Offsets active: relayout only past the admitted bound, repaint
  ///    otherwise.
  /// 5. Otherwise nothing.
  ///
  /// On a FIXED lane axis this router never CLASSIFIES make-room motion
  /// as layout-driving. That is a claim about the classification and not
  /// about every make-room tick: a gap that displaces a neighbour still
  /// lays out through the admitted-bound arm, because a held offset
  /// ramping up exceeds the bound the last layout recorded.
  void _handleAnimationTick() {
    final anim = _controller.anim;
    final contentAxis = _contentAxis;
    final laneAxisIsContent =
        contentAxis != null && _controller.laneAxis == contentAxis;
    final hasLayoutDriving =
        anim.hasLayoutDrivingAnimations ||
        (laneAxisIsContent && anim.hasMakeRoomMotion);
    final hasOffsets = anim.hasActiveOffsets;
    if (hasLayoutDriving || _priorTickHadLayoutDriving) {
      markNeedsLayout();
    } else if (laneAxisIsContent &&
        anim.makeRoomGeneration != _laidOutMakeRoomGeneration) {
      markNeedsLayout();
    } else if (_priorTickHadOffsets && !hasOffsets) {
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
  }

  /// The measurement half of a controller swap's reset: extents measured
  /// against one item set are not evidence about another, so a swap drops
  /// every measurement on the axes it is about to lay out.
  ///
  /// The animation half arrives with the coordinator; the span index and
  /// the lane assignments belong to the controller, and a freshly
  /// assigned controller carries its own.
  void _resetMeasurements() {
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
    _obtainedThisLayout.clear();
    // Cleared at ENTRY, not in the sweep: the item OBTAIN writes it and
    // the sweep, the paint walks and applyPaintTransform read it.
    _vicinityToItemId.clear();
    // ARM 1 of the lane flush: resolution precedes track sizing, so the
    // cluster term below never reads a stale laneCount.
    _controller.flushLanesForLayout();

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

    if (!settled) {
      // Release behaviour at the ceiling: lay out at the last attempted
      // offset. Both offsets still need dimensions, or the frame paints
      // against a position that has none.
      _applyContentDimensions();
      assert(() {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            "RenderBoardViewport ran $_maxCorrectionPasses consecutive "
            "STAGNANT placement passes without settling.",
          ),
          ErrorDescription(
            "A stagnant pass measures no previously unmeasured track and "
            "still does not settle. Reaching the ceiling means a track's "
            "resolved extent is moving between passes of ONE layout, or "
            "applyContentDimensions kept clamping the position with "
            "nothing left to measure.",
          ),
          ErrorHint(
            "A cap that is reached is a convergence defect, not a slow "
            "path. debugLastCorrectionPassCount reports the count and "
            "debugCorrectionCount the corrections applied.",
          ),
        ]);
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
    return _controller.rowStartOfId(id) >=
            _controller.rows.axis.trackCount ||
        _controller.colStartOfId(id) >= _controller.columns.axis.trackCount;
  }

  /// The retention bookkeeping: every obtained EXITING item is recorded,
  /// overwriting any older id at the vicinity, which is what makes id
  /// recycling a non-event; releases happened at the top of
  /// [_obtainRetained].
  void _sweepRetention() {
    final anim = _controller.anim;
    for (final vicinity in _obtainedThisLayout) {
      final id = _vicinityToItemId[vicinity];
      if (id != null && anim.isExitingItem(id)) {
        _retainedExits[vicinity] = id;
      }
    }
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
    final floor = axisEnum == Axis.vertical
        ? _shiftFloorRow
        : _shiftFloorCol;
    return settled +
        _controller.animatedOffsetShiftBetween(axisEnum, floor, track);
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
    final anchorAxis = contentAxis == null
        ? null
        : (contentAxis == Axis.vertical ? rowAxis : columnAxis);
    var anchorTrack = -1;
    var anchorBefore = 0.0;
    if (anchorAxis != null) {
      anchorTrack = _firstMeasuredTrackIn(
        anchorAxis,
        contentAxis == Axis.vertical ? topVisible : leftVisible,
        contentAxis == Axis.vertical ? bottomVisible : rightVisible,
      );
      if (anchorTrack >= 0) {
        anchorBefore = anchorAxis.offsetOf(anchorTrack);
      }
    }

    _contentTrackExtents.clear();
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
      for (final row in _frozenTracksOf(rowsConfig)) {
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
      for (final col in _frozenTracksOf(columnsConfig)) {
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
      for (final row in _frozenTracksOf(rowsConfig)) {
        for (final col in _frozenTracksOf(columnsConfig)) {
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
      }
      if (_obtainedThisLayout.length == obtainedBefore) {
        break;
      }
    }
    _recordVisibleWindow(
      rowAxis,
      columnAxis,
      topVisible: topVisible,
      bottomVisible: bottomVisible,
      leftVisible: leftVisible,
      rightVisible: rightVisible,
    );

    if (anchorAxis == null || anchorTrack < 0) {
      return 0.0;
    }
    return anchorAxis.offsetOf(anchorTrack) - anchorBefore;
  }

  /// The TRACK SIZING step: writes this pass's resolved extents into the
  /// content-sized axis.
  ///
  /// Five arms per track. A first measurement replaces the estimate and
  /// clears every latch set. A RAMPING or MAKE-ROOM CONTRIBUTOR records
  /// per pass and maintains both latch sets symmetrically, each against
  /// its own condition, and at the make-room latch EDGE it hands the
  /// track's in-flight trackResize in: while a make-room latch entry
  /// stands the animator holds no state for that track, or every recorded
  /// term would be invisible until the state was dropped. The latch's
  /// hand-off then either RECORDS the residue or, when the SNAP
  /// generation moved and the engine published the discarded motion's
  /// clock, installs a makeRoom-family resize for a residue past
  /// tolerance on that clock. A changed settled extent records the
  /// target and installs the resize that animates toward it.
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
      var contributorRamping = false;
      var makeRoomContributes = false;
      if (laneAxisIsContent) {
        // The item-cluster term: the track must hold its deepest
        // cluster's lanes, each member's ceiling SCALED by its enter/exit
        // ramp and SHIFTED by the held make-room delta paint adds to the
        // same member, so the track's edge is a function of what paints.
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
          if (delta != 0.0) {
            makeRoomContributes = true;
          }
          final ceiling =
              _controller.laneOfId(member) * config.laneExtent! +
              delta +
              anim.enterExitProgressOf(member) * config.laneExtent!;
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
      assert(() {
        if (_controller.laneAxis == null &&
            _controller.debugHasIntraTrackItemOn(track)) {
          throw FlutterError(
            "A content-sized axis holds an intra-track item cluster on "
            "track $track and no axis carries a laneExtent: the cluster "
            "can neither grow this track nor stack along the other axis. "
            "Give one axis's config a laneExtent, or keep items off the "
            "content axis.",
          );
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
        // layout dirty for a resize duration after the settle.
        //
        // THE TRACK-RESIZE HAND-IN, at the latch EDGE and nowhere else.
        // From this pass on the extent is TERM-DRIVEN, recorded once per
        // pass, while a trackResize in flight makes paint read the
        // animator's captured from and to for both this track's extent
        // and the following tracks' offsets. Nothing re-targets that
        // state while the latch holds, since this arm's `continue` puts
        // the one install site out of reach, so the recorded term would
        // be invisible for the rest of the state's duration and would
        // then pop when the animator dropped it. Finalizing lands the
        // extent the axis already stores. Unconditional at the edge: a
        // track holding no state is a no-op.
        if (makeRoomContributes && !makeRoomLatch.contains(track)) {
          _controller.finalizeTrackResize(contentAxis, track);
        }
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
        // `painted` is read BEFORE the record: the animator holds no
        // state for a latched track, so it answers the settled extent,
        // which the record is about to replace. `stored` is the
        // floor-corrected value, for the reason the ordinary arm below
        // gives.
        final stored = to < axis.minTrackExtent ? axis.minTrackExtent : to;
        final painted = anim.animatedExtentOf(contentAxis, track);
        final handOff = anim.makeRoomSnapGeneration != _laidOutSnapGeneration
            ? anim.makeRoomHandOff
            : null;
        axis.recordMeasurement(track, to);
        if (handOff != null &&
            (stored - painted).abs() > precisionErrorTolerance) {
          _controller.animateTrackResize(
            contentAxis,
            track,
            painted,
            stored,
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
        // re-target mid-resize composes from where the track is;
        // captured after the write it would read the target and animate
        // nothing. The record then makes the axis the settled truth, and
        // the install (which the forwarder routes to the animator, and
        // which a zero family refuses, landing the geometry this frame)
        // must not touch layout, notification or the animation channel
        // from inside layout; its first dispatch is its first tick.
        final from = anim.animatedExtentOf(contentAxis, track);
        axis.recordMeasurement(track, to);
        _controller.animateTrackResize(contentAxis, track, from, stored);
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
      return;
    }
    child.layout(
      _measuringConstraints(rowsConfig, columnsConfig, row, col),
      parentUsesSize: true,
    );
    if (contentAxis == null) {
      return;
    }
    // The CELL contribution to the track's intrinsic extent: the maximum
    // over the cells of that track. The item-cluster term lands with the
    // item plane.
    final track = contentAxis == Axis.vertical ? row : col;
    final measured = contentAxis == Axis.vertical
        ? child.size.height
        : child.size.width;
    final current = _contentTrackExtents[track];
    if (current == null || measured > current) {
      _contentTrackExtents[track] = measured;
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
    final ids = _controller.itemIdsInRectIncludingExiting(
      rowStart,
      rowEnd + 1,
      colStart,
      colEnd + 1,
      _itemIdScratch,
    );
    final columnCount = columnAxis.trackCount;
    for (final id in ids) {
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
  /// plus the lane term and the lane slice for its extent (its own
  /// fractions on that axis are ignored, because its position inside the
  /// track is decided by its lane); everything else takes the exact
  /// fractional endpoints, which is the only arm that consumes them.
  ({double lead, double extent}) _itemSpanGeometry(int id, Axis axis) {
    final config = axis == Axis.vertical ? _controller.rows : _controller.columns;
    final boardAxis = config.axis;
    final laned =
        _controller.laneAxis == axis && _controller.isLanedId(id);
    if (laned) {
      // Clamped exactly as the fractional arm below clamps: an axis swap
      // can strand a live span past the lattice, and these reads must
      // stay total for every consumer, rectOfItem included.
      final track = math.min(
        axis == Axis.vertical
            ? _controller.rowStartOfId(id)
            : _controller.colStartOfId(id),
        boardAxis.trackCount,
      );
      final lane = _controller.laneOfId(id);
      final laneCount = _controller.laneCountOfId(id);
      final trackLead = _animatedOffsetOf(axis, boardAxis, track);
      final laneExtent = config.laneExtent;
      final padding = config.lanePadding;
      if (boardAxis.acceptsMeasurements) {
        // Content-sized lane axis: fixed slices from the padded edge; the
        // track grew to hold them through the cluster term. The extent
        // ramps with the item's own enter/exit progress.
        return (
          lead: trackLead + padding + lane * laneExtent!,
          extent: laneExtent * _controller.anim.enterExitProgressOf(id),
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
        lead: trackLead + padding + lane * slice,
        extent: slice * _controller.anim.enterExitProgressOf(id),
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
    if (_controller.anim.hasActiveTrackResize) {
      final floor = axis == Axis.vertical ? _shiftFloorRow : _shiftFloorCol;
      lead += _controller.animatedOffsetShiftBetween(
        axis,
        floor,
        startTrack.floor(),
      );
      trail += _controller.animatedOffsetShiftBetween(
        axis,
        floor,
        endTrack.floor(),
      );
    }
    var extent = math.max(0.0, trail - lead);
    if (_controller.laneAxis == axis) {
      // The third form of the scaled lane-axis extent: a non-laned item
      // on the lane axis ramps over its own full extent. The span axis
      // is never scaled; a chip entering a week row grows in height, not
      // in day count.
      extent *= _controller.anim.enterExitProgressOf(id);
    }
    return (lead: lead, extent: extent);
  }

  /// The frozen tracks of one axis, leading band then trailing band, each
  /// clamped so the two never overlap on a small axis. Iteration order is
  /// ascending within each band.
  Iterable<int> _frozenTracksOf(BoardAxisConfig config) sync* {
    final count = config.axis.trackCount;
    final lead = math.min(config.frozenStart, count);
    final trailFrom = math.max(lead, count - config.frozenEnd);
    for (var track = 0; track < lead; track++) {
      yield track;
    }
    for (var track = trailFrom; track < count; track++) {
      yield track;
    }
  }

  /// Whether [track] lies in [config]'s leading or trailing frozen band.
  bool _isFrozenTrack(BoardAxisConfig config, int track) {
    final count = config.axis.trackCount;
    final lead = math.min(config.frozenStart, count);
    final trailFrom = math.max(lead, count - config.frozenEnd);
    return track < lead || track >= trailFrom;
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
    final count = axis.trackCount;
    final lead = math.min(config.frozenStart, count);
    if (track < lead) {
      return axis.offsetOf(track);
    }
    return viewportExtent - (axis.totalExtent - axis.offsetOf(track));
  }

  /// Obtains a child at most once per `layoutChildSequence`, reading it
  /// back through `getChildFor` on any later request in the same call.
  RenderBox? _obtainOnce(ChildVicinity vicinity) {
    if (_obtainedThisLayout.add(vicinity)) {
      return buildOrObtainChildFor(vicinity);
    }
    return getChildFor(vicinity);
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
        <({bool laned, int lane, int id, RenderBox child})>[];
    for (final vicinity in _obtainedThisLayout) {
      final child = getChildFor(vicinity);
      if (child == null) {
        continue;
      }
      final itemId = _vicinityToItemId[vicinity];
      if (itemId != null) {
        // An ITEM child: exact rect on both axes from the two-arm
        // geometry rule; never frozen-pinned, so the band covers items
        // scrolled beneath it.
        final vertical = _itemSpanGeometry(itemId, Axis.vertical);
        final horizontal = _itemSpanGeometry(itemId, Axis.horizontal);
        child.layout(
          BoxConstraints.tightFor(
            width: horizontal.extent,
            height: vertical.extent,
          ),
          parentUsesSize: true,
        );
        parentDataOf(child).layoutOffset = Offset(
          horizontal.lead - scrollX,
          vertical.lead - scrollY,
        );
        itemEntries.add((
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
      child.layout(
        _placementConstraints(rowsConfig, columnsConfig, row, col),
        parentUsesSize: true,
      );
      final rowFrozen = _isFrozenTrack(rowsConfig, row);
      final colFrozen = _isFrozenTrack(columnsConfig, col);
      // Content space: the track's leading edge plus the alignment's share
      // of whatever surplus the cell left in the track. A frozen track
      // replaces the content-minus-scroll term with a viewport-pinned one
      // on ITS axis only; a header row still scrolls with its columns.
      final shiftY = _alignmentShift(
        rowsConfig.alignment,
        _animatedExtentOf(Axis.vertical, rowAxis, row) - child.size.height,
      );
      final shiftX = _alignmentShift(
        columnsConfig.alignment,
        _animatedExtentOf(Axis.horizontal, columnAxis, col) -
            child.size.width,
      );
      final normalizedY = rowFrozen
          ? _frozenNormalizedPosition(rowsConfig, row, extent.height) + shiftY
          : _animatedOffsetOf(Axis.vertical, rowAxis, row) + shiftY - scrollY;
      final normalizedX = colFrozen
          ? _frozenNormalizedPosition(columnsConfig, col, extent.width) +
                shiftX
          : _animatedOffsetOf(Axis.horizontal, columnAxis, col) +
                shiftX -
                scrollX;
      // NORMALIZED space, not viewport paint space:
      // computeAbsolutePaintOffsetFor applies reversal from here.
      parentDataOf(child).layoutOffset = Offset(normalizedX, normalizedY);
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
    _frozenPaintOrder.addAll(corner);
    // Plane 2's order: laned items by lane then id, and non-laned items
    // LAST, so an item painting across its whole lane-axis extent sits
    // above the laned stack and, through the reverse hit-test walk, takes
    // the pointer over it. A plain (lane, id) order buries it: exclusion
    // from laning stores lane 0.
    itemEntries.sort((a, b) {
      if (a.laned != b.laned) {
        return a.laned ? -1 : 1;
      }
      final byLane = a.lane.compareTo(b.lane);
      if (byLane != 0) {
        return byLane;
      }
      return a.id.compareTo(b.id);
    });
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
  BoxConstraints _placementConstraints(
    BoardAxisConfig rowsConfig,
    BoardAxisConfig columnsConfig,
    int row,
    int col,
  ) {
    final width = _animatedExtentOf(
      Axis.horizontal,
      columnsConfig.axis,
      col,
    );
    final height = _animatedExtentOf(Axis.vertical, rowsConfig.axis, row);
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
      if (_isFrozenTrack(config, track)) {
        continue;
      }
      if (axis.isMeasured(track)) {
        return track;
      }
    }
    return -1;
  }

  void _recordVisibleWindow(
    BoardAxis rowAxis,
    BoardAxis columnAxis, {
    required double topVisible,
    required double bottomVisible,
    required double leftVisible,
    required double rightVisible,
  }) {
    if (rowAxis.trackCount == 0) {
      _firstVisibleRow = 0;
      _lastVisibleRow = -1;
    } else {
      _firstVisibleRow = _animatedTrackAt(
        Axis.vertical,
        rowAxis,
        math.max(0.0, topVisible),
      );
      _lastVisibleRow = _animatedTrackAt(
        Axis.vertical,
        rowAxis,
        math.max(0.0, bottomVisible - precisionErrorTolerance),
      );
    }
    if (columnAxis.trackCount == 0) {
      _firstVisibleCol = 0;
      _lastVisibleCol = -1;
    } else {
      _firstVisibleCol = _animatedTrackAt(
        Axis.horizontal,
        columnAxis,
        math.max(0.0, leftVisible),
      );
      _lastVisibleCol = _animatedTrackAt(
        Axis.horizontal,
        columnAxis,
        math.max(0.0, rightVisible - precisionErrorTolerance),
      );
    }
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

  /// The ANIMATION term of the window rule: the per-axis magnitudes of the
  /// composed paint-only offsets in flight. The window is widened by it
  /// and [_admittedOffsetBound] records it in the same statement site, so
  /// the pair is whole.
  ({double dx, double dy}) _composedOffsetBound() {
    return _controller.anim.composedOffsetBound;
  }

  // -----------------------------------------------------------------
  // Paint and hit-test. Three planes: cells, items, frozen; hit-testing
  // walks the exact reverse, and applyPaintTransform mirrors the same
  // per-item shift paint applies.
  // -----------------------------------------------------------------

  /// The paint-only shift an item child is drawn at, beyond its
  /// `paintOffset`. Zero until the animation sources land; declared with
  /// its three mirrors (paint, hit-test, [applyPaintTransform]) so the
  /// pairing exists before the first non-zero value does.
  Offset _paintShiftOf(ChildVicinity vicinity) {
    final id = _vicinityToItemId[vicinity];
    if (id == null) {
      return Offset.zero;
    }
    return _controller.anim.offsetOfItem(id);
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
    if (_hasVisualOverflow && clipBehavior != Clip.none) {
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
    for (final child in _cellPaintOrder) {
      final childParentData = parentDataOf(child);
      if (childParentData.isVisible) {
        context.paintChild(child, offset + childParentData.paintOffset!);
      }
    }
    for (final child in _itemPaintOrder) {
      final childParentData = parentDataOf(child);
      if (childParentData.isVisible) {
        context.paintChild(
          child,
          offset +
              childParentData.paintOffset! +
              _paintShiftOf(childParentData.vicinity),
        );
      }
    }
    for (final child in _frozenPaintOrder) {
      final childParentData = parentDataOf(child);
      if (childParentData.isVisible) {
        context.paintChild(child, offset + childParentData.paintOffset!);
      }
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Exact reverse of the paint walk, so the child drawn on top is the
    // child that takes the pointer: frozen (corner first), then items,
    // then cells.
    for (var i = _frozenPaintOrder.length - 1; i >= 0; i--) {
      if (_hitTestChild(_frozenPaintOrder[i], result, position, Offset.zero)) {
        return true;
      }
    }
    for (var i = _itemPaintOrder.length - 1; i >= 0; i--) {
      final child = _itemPaintOrder[i];
      final shift = _paintShiftOf(parentDataOf(child).vicinity);
      if (_hitTestChild(child, result, position, shift)) {
        return true;
      }
    }
    for (var i = _cellPaintOrder.length - 1; i >= 0; i--) {
      if (_hitTestChild(_cellPaintOrder[i], result, position, Offset.zero)) {
        return true;
      }
    }
    return false;
  }

  bool _hitTestChild(
    RenderBox child,
    BoxHitTestResult result,
    Offset position,
    Offset shift,
  ) {
    final childParentData = parentDataOf(child);
    if (!childParentData.isVisible) {
      return false;
    }
    final paintOffset = childParentData.paintOffset! + shift;
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
    final rowAxis = _controller.rows.axis;
    final columnAxis = _controller.columns.axis;
    if (rowAxis.trackCount == 0 || columnAxis.trackCount == 0) {
      return null;
    }
    final contentY = _contentFromPaint(Axis.vertical, local.dy);
    final contentX = _contentFromPaint(Axis.horizontal, local.dx);
    if (contentY < 0.0 || contentY >= rowAxis.totalExtent) {
      return null;
    }
    if (contentX < 0.0 || contentX >= columnAxis.totalExtent) {
      return null;
    }
    return (
      row: _animatedTrackAt(Axis.vertical, rowAxis, contentY),
      col: _animatedTrackAt(Axis.horizontal, columnAxis, contentX),
    );
  }

  @override
  ({int row, int col})? frozenCellAt(Offset local) {
    if (!hasSize) {
      return null;
    }
    final rowsConfig = _controller.rows;
    final columnsConfig = _controller.columns;
    if (rowsConfig.axis.trackCount == 0 ||
        columnsConfig.axis.trackCount == 0) {
      return null;
    }
    final extent = viewportDimension;
    final normalizedY = _normalizedFromPaint(Axis.vertical, local.dy);
    final normalizedX = _normalizedFromPaint(Axis.horizontal, local.dx);
    final frozenRow = _frozenTrackAtNormalized(
      rowsConfig,
      normalizedY,
      extent.height,
    );
    final frozenCol = _frozenTrackAtNormalized(
      columnsConfig,
      normalizedX,
      extent.width,
    );
    if (frozenRow == null && frozenCol == null) {
      return null;
    }
    // The unfrozen coordinate resolves through the scrolled lattice, so a
    // pointer in the header band lands on the header cell of the column
    // currently under it.
    final int row;
    if (frozenRow != null) {
      row = frozenRow;
    } else {
      final contentY = _contentFromPaint(Axis.vertical, local.dy);
      if (contentY < 0.0 || contentY >= rowsConfig.axis.totalExtent) {
        return null;
      }
      row = rowsConfig.axis.trackAt(contentY);
    }
    final int col;
    if (frozenCol != null) {
      col = frozenCol;
    } else {
      final contentX = _contentFromPaint(Axis.horizontal, local.dx);
      if (contentX < 0.0 || contentX >= columnsConfig.axis.totalExtent) {
        return null;
      }
      col = columnsConfig.axis.trackAt(contentX);
    }
    return (row: row, col: col);
  }

  /// The frozen track under a NORMALIZED viewport coordinate, or null when
  /// the coordinate is outside both of [config]'s bands.
  int? _frozenTrackAtNormalized(
    BoardAxisConfig config,
    double normalized,
    double viewportExtent,
  ) {
    final axis = config.axis;
    final count = axis.trackCount;
    final lead = math.min(config.frozenStart, count);
    if (lead > 0 && normalized >= 0.0 && normalized < axis.offsetOf(lead)) {
      return axis.trackAt(normalized);
    }
    final trailFrom = math.max(lead, count - config.frozenEnd);
    if (trailFrom < count) {
      final trailInset = axis.totalExtent - axis.offsetOf(trailFrom);
      if (normalized >= viewportExtent - trailInset &&
          normalized < viewportExtent) {
        return axis.trackAt(axis.totalExtent - (viewportExtent - normalized));
      }
    }
    return null;
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
  Rect visibleCellRect(int row, int col) {
    assert(
      row >= _firstVisibleRow &&
          row <= _lastVisibleRow &&
          col >= _firstVisibleCol &&
          col <= _lastVisibleCol,
      "visibleCellRect($row, $col) is outside the visible bounds, rows "
      "$_firstVisibleRow..$_lastVisibleRow, cols "
      "$_firstVisibleCol..$_lastVisibleCol.",
    );
    final rowAxis = _controller.rows.axis;
    final columnAxis = _controller.columns.axis;
    final width = _animatedExtentOf(Axis.horizontal, columnAxis, col);
    final height = _animatedExtentOf(Axis.vertical, rowAxis, row);
    return Rect.fromLTWH(
      _paintFromContent(
        Axis.horizontal,
        _animatedOffsetOf(Axis.horizontal, columnAxis, col),
        width,
      ),
      _paintFromContent(
        Axis.vertical,
        _animatedOffsetOf(Axis.vertical, rowAxis, row),
        height,
      ),
      width,
      height,
    );
  }

  @override
  Rect? rectOfCell(int row, int col) {
    if (!hasSize) {
      return null;
    }
    final rowAxis = _controller.rows.axis;
    final columnAxis = _controller.columns.axis;
    if (row < 0 || row >= rowAxis.trackCount) {
      return null;
    }
    if (col < 0 || col >= columnAxis.trackCount) {
      return null;
    }
    final width = _animatedExtentOf(Axis.horizontal, columnAxis, col);
    final height = _animatedExtentOf(Axis.vertical, rowAxis, row);
    return Rect.fromLTWH(
      _paintFromContent(
        Axis.horizontal,
        _animatedOffsetOf(Axis.horizontal, columnAxis, col),
        width,
      ),
      _paintFromContent(
        Axis.vertical,
        _animatedOffsetOf(Axis.vertical, rowAxis, row),
        height,
      ),
      width,
      height,
    );
  }

  @override
  TKey? itemAt(Offset local) {
    if (!hasSize) {
      return null;
    }
    // The topmost item under the pointer: plane 2 in exact reverse, the
    // same order hit-testing walks. Excludes items animating out and the
    // dragged item: neither can be a tap target or a drop target.
    for (var i = _itemPaintOrder.length - 1; i >= 0; i--) {
      final child = _itemPaintOrder[i];
      final childParentData = parentDataOf(child);
      final paintOffset = childParentData.paintOffset;
      if (paintOffset == null) {
        continue;
      }
      // Composed with the paint shift, the same offset hit-testing
      // composes: a probe must agree with what paints, held gaps
      // included.
      final rect =
          (paintOffset + _paintShiftOf(childParentData.vicinity)) &
          child.size;
      if (rect.contains(local)) {
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

  @override
  Rect? rectOfItem(TKey key) {
    if (!hasSize) {
      return null;
    }
    final id = _controller.idOfKey(key);
    if (id < 0) {
      return null;
    }
    final vertical = _itemSpanGeometry(id, Axis.vertical);
    final horizontal = _itemSpanGeometry(id, Axis.horizontal);
    return Rect.fromLTWH(
      _paintFromContent(Axis.horizontal, horizontal.lead, horizontal.extent),
      _paintFromContent(Axis.vertical, vertical.lead, vertical.extent),
      horizontal.extent,
      vertical.extent,
    );
  }

  /// On a zero-track axis this returns (0, 0), which is not a cell: there
  /// is no legal drop cell on an empty lattice, the signature is
  /// non-nullable, and the drag layer cannot start a drag on an empty
  /// board anyway. Callers that can see an empty board gate on trackCount.
  @override
  ({int row, int col}) resolveDropCell(Offset local) {
    final rowAxis = _controller.rows.axis;
    final columnAxis = _controller.columns.axis;
    if (!hasSize) {
      return (row: 0, col: 0);
    }
    // NEAREST, not containment: the fractional track-space coordinate is
    // rounded by the same rule BoardSnap.track's quantize applies, so
    // the cell route and the trackSpaceAt route agree on where an anchor
    // between two boundaries lands. Read through the animated geometry,
    // agreeing with what paints.
    return (
      row: _nearestTrack(
        Axis.vertical,
        rowAxis,
        _contentFromPaint(Axis.vertical, local.dy),
      ),
      col: _nearestTrack(
        Axis.horizontal,
        columnAxis,
        _contentFromPaint(Axis.horizontal, local.dx),
      ),
    );
  }

  int _nearestTrack(Axis axisDirection, BoardAxis axis, double content) {
    final count = axis.trackCount;
    if (count == 0 || content <= 0.0) {
      return 0;
    }
    final track = _animatedTrackAt(axisDirection, axis, content);
    final lead = _animatedOffsetOf(axisDirection, axis, track);
    final extent = _animatedExtentOf(axisDirection, axis, track);
    final fraction = extent <= 0.0
        ? track.toDouble()
        : track + (content - lead) / extent;
    return fraction.round().clamp(0, count - 1);
  }

  @override
  ({double row, double col})? trackSpaceAt(Offset local) {
    if (!hasSize) {
      return null;
    }
    final rowAxis = _controller.rows.axis;
    final columnAxis = _controller.columns.axis;
    if (rowAxis.trackCount == 0 || columnAxis.trackCount == 0) {
      return null;
    }
    return (
      row: _trackFractionOf(
        rowAxis,
        _contentFromPaint(Axis.vertical, local.dy),
      ),
      col: _trackFractionOf(
        columnAxis,
        _contentFromPaint(Axis.horizontal, local.dx),
      ),
    );
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
    final config = axis == Axis.vertical ? _controller.rows : _controller.columns;
    final lead = math.min(config.frozenStart, config.axis.trackCount);
    if (lead == 0) {
      return 0.0;
    }
    return config.axis.offsetOf(lead);
  }

  /// Track space of a content-space coordinate: the integer track plus the
  /// fraction into it, clamped into `[0, trackCount]`.
  double _trackFractionOf(BoardAxis axis, double content) {
    if (content <= 0.0) {
      return 0.0;
    }
    if (content >= axis.totalExtent) {
      return axis.trackCount.toDouble();
    }
    final track = axis.trackAt(content);
    return track + (content - axis.offsetOf(track)) / axis.extentOf(track);
  }

  /// Content-space coordinate of a viewport-paint-space one.
  ///
  /// The reversed arm is the inverse of `computeAbsolutePaintOffsetFor`
  /// (`widgets/two_dimensional_viewport.dart:1626`) for a point.
  double _contentFromPaint(Axis axis, double paint) {
    switch (axis) {
      case Axis.vertical:
        if (verticalAxisDirection == AxisDirection.down) {
          return paint + verticalOffset.pixels;
        }
        return verticalOffset.pixels + viewportDimension.height - paint;
      case Axis.horizontal:
        if (horizontalAxisDirection == AxisDirection.right) {
          return paint + horizontalOffset.pixels;
        }
        return horizontalOffset.pixels + viewportDimension.width - paint;
    }
  }

  /// Viewport-paint-space LEADING edge of a content-space interval. Under
  /// reversal the leading edge is the far side of the interval, which is
  /// why this takes the extent and [_contentFromPaint] does not.
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
