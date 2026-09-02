/// The board's L2 controller: the single owner of item state, of the two
/// spatial indices over it, of the three notification channels and of the
/// selection value.
///
/// Deliberately carries no animation source yet. The members that route
/// to one (`anim`, `previewMakeRoomGap`, `releaseMakeRoomPreview`,
/// `animateDropSettle`, `animateTrackResize`), the three scroll members
/// and `markDragging` arrive with the components they reach, so this file
/// declares none of them yet.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '_board_animation_coordinator.dart';
import '_board_scroll_orchestrator.dart';
import '_board_axis.dart';
import '_board_span.dart';
import '_board_store.dart';
import '_overlap_lanes.dart';
import '_span_index.dart';
import 'board_animation_style.dart';
import 'board_config.dart';
import 'board_render_port.dart';

/// Owns one board's items and answers every question about them.
///
/// Two type parameters and no more: [TKey] identifies an item and [TItem]
/// is the caller's payload. There is no per-cell payload type, because a
/// cell is a lattice position rather than a stored thing.
///
/// Three notification channels, whose contract is the tree's:
///
/// - [addStructuralListener] takes a nullable key set. `null` means the
///   scope is unknown and the listener should do a full refresh; an EMPTY
///   set means a structural change occurred but no built child's builder
///   output changed, so only relayout and child collection are needed; a
///   NON-EMPTY set means exactly these keys may differ. The inputs are a
///   built child's RENDERED inputs, which for a board are its payload, its
///   span, its lane and its lane count, not only the span: a lane change
///   with an unchanged span is a change and is the one an implementer
///   drops.
/// - [addItemDataListener] fires for a payload-only write. [updateItem] is
///   the only mutator that fires it, because it is the only one that
///   writes the payload without writing a span. Structural SUBSUMES data:
///   no single mutation fires both for one key.
/// - [addAnimationListener] ticks while animations run. It has no producer
///   until the animation sources land.
///
/// Inside [runBatch] the first two coalesce to one dispatch at batch exit
/// and the third is NOT deferred; see [runBatch].
class BoardController<TKey, TItem> {
  /// Creates a controller over the [rows] and [columns] configs.
  ///
  /// Asserts at most one content-sized axis and at most one axis carrying
  /// a `laneExtent`. Both are re-asserted by the [rows] and [columns]
  /// setters, which are the runtime route to the same violation.
  ///
  /// [vsync] is the [TickerProvider] the five animation sources tick
  /// against. It is required here so the constructor's shape is settled
  /// before those sources exist; nothing in this step holds a ticker, and
  /// the field that stores it lands with the first source rather than
  /// sitting here unread.
  BoardController({
    required TickerProvider vsync,
    required BoardAxisConfig rows,
    required BoardAxisConfig columns,
    required TKey Function(TItem) keyOf,
    BoardAnimationStyle animationStyle = const BoardAnimationStyle(),
  }) : _rows = rows,
       _columns = columns,
       _keyOf = keyOf,
       _animationStyle = animationStyle {
    assert(_debugValidateConfigs(rows, columns));
    assert(animationStyle.debugValidate());
    _spanIndex = SpanIndex(
      store: _store,
      primaryAxis: _derivePrimaryAxis(rows, columns),
    );
    _lanes = OverlapLaneResolver(
      store: _store,
      laneAxis: _deriveLaneAxis(rows, columns),
    );
    _spanIndex.laneAxis = _lanes.laneAxis;
    _anim = BoardAnimationCoordinator<TKey>(
      vsync: vsync,
      store: _store,
      spanIndex: _spanIndex,
      lanes: _lanes,
      styleOf: () {
        return _animationStyle;
      },
      listeners: _animationListeners,
      fireStructural: _fireStructural,
      settledExtentOf: (axis, track) {
        final config = axis == Axis.vertical ? _rows : _columns;
        return config.axis.extentOf(track);
      },
      laneAxisOf: () {
        return _lanes.laneAxis;
      },
      dryRunOf: _dryRunLanes,
      laneOriginOfId: _laneOriginOfId,
      laneOfId: laneOfId,
      laneCountOfId: laneCountOfId,
    );
    _orchestrator = BoardScrollOrchestrator<TKey>(
      portOf: () {
        return _renderPort;
      },
      rowsOf: () {
        return _rows;
      },
      columnsOf: () {
        return _columns;
      },
    );
  }

  final BoardStore<TKey, TItem> _store = BoardStore<TKey, TItem>();

  late final SpanIndex _spanIndex;

  late final OverlapLaneResolver _lanes;

  late final BoardAnimationCoordinator<TKey> _anim;

  late final BoardScrollOrchestrator<TKey> _orchestrator;

  final TKey Function(TItem) _keyOf;

  final ValueNotifier<BoardSelection> _selection =
      ValueNotifier<BoardSelection>(const BoardSelection.none());

  final List<void Function(Set<TKey>?)> _structuralListeners =
      <void Function(Set<TKey>?)>[];

  final List<void Function(TKey)> _itemDataListeners = <void Function(TKey)>[];

  final List<VoidCallback> _animationListeners = <VoidCallback>[];

  BoardAxisConfig _rows;

  BoardAxisConfig _columns;

  BoardAnimationStyle _animationStyle;

  /// Open [runBatch] scopes. Above zero, the structural and item-data
  /// channels are deferred to the outermost exit.
  int _batchDepth = 0;

  /// Open BULK registration scopes: [runBatch] and [setItems]. Above zero,
  /// a registration APPENDS to its buckets and marks them pending instead
  /// of doing a sorted insert, and the outermost exit sorts each pending
  /// bucket once.
  int _bulkDepth = 0;

  bool _batchStructural = false;

  bool _batchStructuralUnknown = false;

  Set<TKey> _batchAffected = <TKey>{};

  final Set<TKey> _batchDataKeys = <TKey>{};

  /// The render object driving this controller, or null when no board is
  /// mounted on it or its render object is detached. Written only by
  /// [attachRenderPort], [detachRenderPort] and [dispose].
  BoardRenderPort<TKey>? _renderPort;

  bool _disposed = false;

  /// The row axis config. Assigning a new one re-derives the primary and
  /// lane axes and fires a full-refresh structural notification.
  BoardAxisConfig get rows {
    _assertNotDisposed();
    return _rows;
  }

  set rows(BoardAxisConfig value) {
    _assertNotDisposed();
    assert(_debugValidateConfigs(value, _columns));
    if (identical(value, _rows)) {
      return;
    }
    _rows = value;
    _resetSwappedAxis(value);
    _reconfigureAxes(Axis.vertical);
  }

  /// The column axis config. See [rows].
  BoardAxisConfig get columns {
    _assertNotDisposed();
    return _columns;
  }

  set columns(BoardAxisConfig value) {
    _assertNotDisposed();
    assert(_debugValidateConfigs(_rows, value));
    if (identical(value, _columns)) {
      return;
    }
    _columns = value;
    _resetSwappedAxis(value);
    _reconfigureAxes(Axis.horizontal);
  }

  /// Timing and easing for every animation family. Immutable; restyle by
  /// assigning a new instance.
  BoardAnimationStyle get animationStyle {
    _assertNotDisposed();
    return _animationStyle;
  }

  set animationStyle(BoardAnimationStyle value) {
    _assertNotDisposed();
    assert(value.debugValidate());
    final old = _animationStyle;
    _animationStyle = value;
    // The two ROOT-family transitions this setter owns. itemSlide to
    // zero PURGES: the family is paint-only, so dropping a delta lands
    // the item at its structural position. trackResize to zero
    // FINALIZES instead: the family is layout-driving and an abandoned
    // state would strand a partial extent, so each state lands at the
    // target the axis already stores. The other three families need no
    // arm: dropSettle rides the purged engine, itemEnterExit is driven
    // past 1 by the tick-time zero guard and retired through its normal
    // handler, and makeRoom's held gap is not motion.
    if (old.itemSlide.duration != Duration.zero &&
        value.itemSlide.duration == Duration.zero) {
      _anim.slide.purgeActive();
      _anim.notifyNow();
    }
    if (old.trackResize.duration != Duration.zero &&
        value.trackResize.duration == Duration.zero) {
      final hadStates = _anim.trackResize.hasActive;
      _anim.trackResize.finalizeAll();
      _anim.notifyNow();
      if (hadStates) {
        // Before the resize's FIRST tick no mirror has latched, so the
        // notify alone cannot route a relayout and the cells stay
        // painted at the captured origins; an empty structural dirties
        // layout without naming a key.
        _notifyStructural(<TKey>{});
      }
    }
  }

  /// The axis items are laned ON: the one whose config carries a non-null
  /// `laneExtent`, or null when neither does.
  ///
  /// It governs LANE GEOMETRY only. It is NOT the bucketing key and NOT
  /// the item vicinity's yIndex; that is the PRIMARY axis, which is the
  /// content-sized axis when one exists and the row axis otherwise, and is
  /// never null. A null lane axis is the spreadsheet and gantt
  /// configuration: nothing is ever laned, every item keeps lane 0 of 1,
  /// and nothing else is left undefined.
  Axis? get laneAxis {
    _assertNotDisposed();
    return _lanes.laneAxis;
  }

  /// The axis whose integer track indexes item vicinities and span-index
  /// buckets: the content-sized axis when one exists, and the row axis
  /// otherwise. Never null, and distinct from [laneAxis]; see its doc for
  /// why the two must not be collapsed.
  ///
  /// Reads the span index's live value, which the axis setters re-derive,
  /// so a swap that moves content-sizedness is reflected here immediately.
  Axis get primaryAxis {
    _assertNotDisposed();
    return _spanIndex.primaryAxis;
  }

  /// Debug-only: lane-axis buckets the lane flush has actually resolved,
  /// whichever arm called it.
  ///
  /// A FORWARDER, not a second counter. The only code that knows a bucket
  /// was processed is the resolver's own per-bucket loop, so the storage
  /// and the increment are there; this controller sees one flush call, not
  /// the number of buckets it processed, and a call-counting field here
  /// would pass the very implementation the counter exists to reject, one
  /// that re-resolves every bucket on every layout.
  int get debugLaneBucketResolveCount {
    return _lanes.debugBucketResolveCount;
  }

  // ---------------------------------------------------------------------
  // Caller-facing reads, TKey-keyed.
  //
  // Every one of these EXCLUDES items that are animating out: an exiting
  // item is gone from the model even though it is still painting. They do
  // NOT exclude a dragged item, which is still in the model. Each returns
  // an EAGERLY materialized result, because the span index's
  // de-duplication set is reused across queries and a lazy walk would be
  // corrupted by the very next one.
  // ---------------------------------------------------------------------

  /// The live keys whose span covers cell `(row, col)`. Fresh list per
  /// call.
  List<TKey> itemsAt(int row, int col) {
    return itemsIn(row, row + 1, col, col + 1);
  }

  /// The live keys whose span intersects the half-open track rect. Fresh
  /// list per call.
  List<TKey> itemsIn(int rowStart, int rowEnd, int colStart, int colEnd) {
    _assertNotDisposed();
    final ids = _spanIndex.itemsInRect(rowStart, rowEnd, colStart, colEnd);
    final keys = <TKey>[];
    for (final id in ids) {
      final key = _store.keyOf(id);
      if (key != null) {
        keys.add(key);
      }
    }
    return keys;
  }

  /// [key]'s span, or null when it is not in the live set.
  BoardSpan? spanOf(TKey key) {
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return null;
    }
    return _store.spanOf(id);
  }

  /// [key]'s payload, or null when it is not in the live set.
  TItem? itemOf(TKey key) {
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return null;
    }
    return _store.dataOf(id);
  }

  /// [key]'s lane within its lane-axis track, or 0 when it is not in the
  /// live set or is not laned. Flushes dirty lane buckets first, so the
  /// value is observable on the frame of the mutation that changed it and
  /// without a layout.
  int laneOf(TKey key) {
    _ensureLanesResolved();
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return 0;
    }
    return _store.laneOf(id);
  }

  /// The number of lanes [key]'s cluster resolved to, or 1 when it is not
  /// in the live set or is not laned. Flushes first; see [laneOf].
  int laneCountOf(TKey key) {
    _ensureLanesResolved();
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return 1;
    }
    return _store.laneCountOf(id);
  }

  /// Whether [key] is in the live set. False for a key whose only
  /// incarnation is animating out.
  bool contains(TKey key) {
    return _liveIdOf(key) != BoardStore.noId;
  }

  /// Whether [key] is the item a drag session currently holds.
  bool isDragging(TKey key) {
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return false;
    }
    return _store.isDragging(id);
  }

  // ---------------------------------------------------------------------
  // Render-facing reads, id-keyed.
  //
  // The board's analogue of the tree's `*Nid` variants. They exist because
  // the render object, the views and the drag controller are separate
  // libraries from the store, so no consumer can reach a dense array
  // directly. They are public members of an exported class, which the
  // barrel cannot hide, and are internal-use-only. None of them hashes a
  // key or allocates.
  //
  // They are id-keyed and scalar-returning on purpose: layout touches
  // every obtained item every frame, so a span-returning accessor would
  // allocate one value object per item per frame.
  //
  // There is deliberately no `isExitingId`: the exiting bit's one read API
  // is the animation reader's, and a second one here would be a second
  // normative site for the same fact.
  // ---------------------------------------------------------------------

  /// The id for [key], or -1 when it is not registered. Unlike the
  /// TKey-keyed reads this does NOT exclude an exiting item, which the
  /// render layer must keep until its exit settles.
  int idOfKey(TKey key) {
    return _store.idOf(key);
  }

  /// The key for [id], or null for a released id.
  TKey? keyOfId(int id) {
    return _store.keyOf(id);
  }

  /// Leading row track of [id]. Track space.
  int rowStartOfId(int id) {
    return _store.rowStartOf(id);
  }

  /// Integer row span of [id]. Track space.
  int rowSpanOfId(int id) {
    return _store.rowSpanOf(id);
  }

  /// Leading column track of [id]. Track space.
  int colStartOfId(int id) {
    return _store.colStartOf(id);
  }

  /// Integer column span of [id]. Track space.
  int colSpanOfId(int id) {
    return _store.colSpanOf(id);
  }

  /// Leading row fraction of [id]. Track space.
  double rowFractionOfId(int id) {
    return _store.rowFractionOf(id);
  }

  /// Leading column fraction of [id]. Track space.
  double colFractionOfId(int id) {
    return _store.colFractionOf(id);
  }

  /// Trailing row span fraction of [id]. Track space.
  double rowSpanFractionOfId(int id) {
    return _store.rowSpanFractionOf(id);
  }

  /// Trailing column span fraction of [id]. Track space.
  double colSpanFractionOfId(int id) {
    return _store.colSpanFractionOf(id);
  }

  /// [id]'s lane. Flushes dirty lane buckets first, exactly as [laneOf]
  /// does.
  int laneOfId(int id) {
    _ensureLanesResolved();
    return _store.laneOf(id);
  }

  /// [id]'s lane count. Flushes first; see [laneOfId].
  int laneCountOfId(int id) {
    _ensureLanesResolved();
    return _store.laneCountOf(id);
  }

  /// Whether [id] is the item a drag session currently holds.
  bool isDraggingId(int id) {
    return _store.isDragging(id);
  }

  /// [id]'s exact track-space endpoints on the row axis, half-open. The
  /// four endpoint reads below are what the geometry rule's fractional
  /// arm consumes; scalar-returning for the same per-frame reason as the
  /// rest of this block.
  double rowStartTrackOfId(int id) {
    return _store.startTrackOf(id, Axis.vertical);
  }

  double rowEndTrackOfId(int id) {
    return _store.endTrackOf(id, Axis.vertical);
  }

  double colStartTrackOfId(int id) {
    return _store.startTrackOf(id, Axis.horizontal);
  }

  double colEndTrackOfId(int id) {
    return _store.endTrackOf(id, Axis.horizontal);
  }

  /// [id]'s vicinity ordinal: its rank among the items sharing its
  /// primary START track. The item vicinity's xIndex component.
  int vicinityOrdinalOfId(int id) {
    return _spanIndex.ordinalOf(id);
  }

  /// [id]'s primary START track: the item vicinity's yIndex component.
  int primaryStartOfId(int id) {
    return _store.startTrackOf(id, _spanIndex.primaryAxis).floor();
  }

  /// The id at [ordinal] on primary start track [track], or
  /// [BoardStore.noId]. The widget's builder resolves an item vicinity
  /// back to its item through this; internal-use in the same sense the
  /// rest of this block is.
  int itemIdAtOrdinal(int track, int ordinal) {
    return _spanIndex.idAtOrdinal(track, ordinal);
  }

  /// Whether [id] satisfies the laning criterion. Reads the resolver's
  /// single predicate, which is also phase agreement: no second
  /// implementation of the criterion exists to disagree with it.
  bool isLanedId(int id) {
    return _lanes.isLaned(id);
  }

  /// The largest resolved lane count among the laned items of lane-axis
  /// bucket [track], or 0 when the bucket is absent or empty. The
  /// item-cluster term of intrinsic track sizing reads this.
  int maxLaneCountInBucket(int track) {
    _ensureLanesResolved();
    return _lanes.maxLaneCountInBucket(track);
  }

  /// A read-only view of one lane-axis bucket's members, or an empty
  /// list for an absent bucket. Internal-use for the sizing sweep's
  /// scaled cluster term and the resize install site's contributor walk.
  List<int> laneBucketMembersOn(int track) {
    return _lanes.laneBucketMembers(track);
  }

  /// The payload for [id], or null for a released slot. Id-space so the
  /// builder can resolve an EXITING item, which the key-space reads
  /// exclude while its exit still paints.
  TItem? itemOfId(int id) {
    if (id < 0 || id >= _store.capacity) {
      return null;
    }
    return _store.dataOf(id);
  }

  /// The span for [id], rebuilt from the stored components. Same
  /// id-space reasoning as [itemOfId].
  BoardSpan spanOfId(int id) {
    return BoardSpan(
      rowStart: _store.rowStartOf(id),
      colStart: _store.colStartOf(id),
      rowSpan: _store.rowSpanOf(id),
      colSpan: _store.colSpanOf(id),
      rowFraction: _store.rowFractionOf(id),
      colFraction: _store.colFractionOf(id),
      rowSpanFraction: _store.rowSpanFractionOf(id),
      colSpanFraction: _store.colSpanFractionOf(id),
    );
  }

  /// Debug-only: whether any item's interval on the PRIMARY axis lies
  /// inside the single integer track [track]. The render object's
  /// content-axis sizing assert reads it; nothing on a release path
  /// does.
  bool debugHasIntraTrackItemOn(int track) {
    var found = false;
    assert(() {
      for (final id in _store.ids) {
        final start = _store.startTrackOf(id, _spanIndex.primaryAxis);
        final end = _store.endTrackOf(id, _spanIndex.primaryAxis);
        if (start >= track &&
            end <= track + 1 + precisionErrorTolerance &&
            start < track + 1) {
          found = true;
          break;
        }
      }
      return true;
    }());
    return found;
  }

  /// ARM 1 of the lane flush: the head of `layoutChildSequence` calls
  /// this so lane resolution precedes track sizing, which is the
  /// resolve-then-size order a stale laneCount would silently violate by
  /// one frame. Internal-use.
  void flushLanesForLayout() {
    _ensureLanesResolved();
  }

  /// The layout obtain set: item ids intersecting the half-open track
  /// rect, INCLUDING ids whose exiting bit is set.
  ///
  /// APPENDS into [into], which the render object owns and reuses, and
  /// returns it, so the per-layout path allocates nothing. [itemsIn] is
  /// the exiting-EXCLUDING, freshly-materialized form.
  List<int> itemIdsInRectIncludingExiting(
    int rowStart,
    int rowEnd,
    int colStart,
    int colEnd,
    List<int> into,
  ) {
    _assertNotDisposed();
    return _spanIndex.itemsInRectIncludingExiting(
      rowStart,
      rowEnd,
      colStart,
      colEnd,
      into,
    );
  }

  // ---------------------------------------------------------------------
  // Selection.
  //
  // The controller is the single OWNER of selection state, because a cell
  // view carries only its coordinates and its controller, and because the
  // selection CONFIG is policy plus a report and a const config cannot
  // hold state. [selection] is a `ValueListenable`, not a fourth
  // notification channel.
  // ---------------------------------------------------------------------

  /// The current selection. `BoardSelection.none()` until the first
  /// [setSelection].
  ValueListenable<BoardSelection> get selection {
    _assertNotDisposed();
    return _selection;
  }

  /// The single writer of [selection].
  void setSelection(BoardSelection value) {
    _assertNotDisposed();
    _selection.value = value;
  }

  /// Whether cell `(row, col)` lies inside the current selection.
  bool isSelected(int row, int col) {
    _assertNotDisposed();
    return _selection.value.contains(row, col);
  }

  // ---------------------------------------------------------------------
  // Mutators.
  //
  // An unknown key throws a `StateError` in all build modes, with a debug
  // assert first.
  //
  // The four SPAN mutators are `addItem`, `setItems`, `moveItem` and
  // `resizeItem`; `updateItem` is payload-only, which is why the data
  // channel and the structural channel are separate. Every one of the four
  // obeys the DE-REGISTER BEFORE WRITING THE SPAN ordering, at
  // [_applySpan].
  // ---------------------------------------------------------------------

  /// Replaces the whole live set, diffed against it by key.
  ///
  /// A key in both keeps its id, and its payload is overwritten and its
  /// key named only when the incoming payload DIFFERS by the caller's
  /// `TItem` equality; its span likewise takes the new value only when it
  /// differs, through the same path [moveItem] and [resizeItem] use. A key only in [placements] enters and a key only in
  /// the live set exits, through the same paths [addItem] and [removeItem]
  /// take: this is not a separate door into the enter and exit machinery.
  ///
  /// A duplicate key inside one call is caller error and throws. The check
  /// runs over the whole argument BEFORE any mutation, so a throw leaves
  /// the board untouched and there is nothing to notify.
  ///
  /// Uses the BULK registration path: N sorted inserts into one bucket
  /// would be quadratic in shifts on exactly the input a bulk call
  /// carries, so registrations APPEND and each touched bucket is sorted
  /// once at the exit. That exit sort is in a `finally`, so a throwing
  /// call cannot leave a bucket appended-but-unsorted.
  void setItems(Iterable<BoardPlacement<TItem>> placements) {
    _assertNotDisposed();
    final desired = <TKey, BoardPlacement<TItem>>{};
    for (final placement in placements) {
      final key = _keyOf(placement.item);
      if (desired.containsKey(key)) {
        _throwDuplicateKey("setItems", key);
      }
      desired[key] = placement;
    }
    _bulkDepth++;
    try {
      final exiting = <TKey>[];
      for (final id in _store.ids) {
        if (_store.isExiting(id)) {
          continue;
        }
        final key = _store.keyOf(id);
        if (key != null && !desired.containsKey(key)) {
          exiting.add(key);
        }
      }
      final affected = <TKey>{};
      for (final key in exiting) {
        _exitOrRetire(key, _store.idOf(key), notify: false);
      }
      for (final entry in desired.entries) {
        final key = entry.key;
        final placement = entry.value;
        final existing = _liveIdOf(key);
        if (existing == BoardStore.noId) {
          _retireGhostOf(key);
          final id = _store.allocate(key);
          if (_store.lastAllocationWasRecycled) {
            _anim.clearForId(id);
          }
          _store.setData(id, placement.item);
          // No de-registration step: a fresh id has no previous span.
          _store.setSpan(id, placement.span);
          _spanIndex.register(id, bulk: true);
          _lanes.registerItem(id);
          if (_animationStyle.effectiveItemEnterExit.duration !=
              Duration.zero) {
            _anim.animateEnter(id);
          }
          affected.add(key);
          continue;
        }
        if (_store.dataOf(existing) != placement.item) {
          _store.setData(existing, placement.item);
          affected.add(key);
        }
        if (!_spanEquals(existing, placement.span)) {
          _cancelDragIfDragged(existing);
          _applySpan(existing, placement.span);
          affected.add(key);
        }
      }
      // A clean no-op diff notifies nothing: nothing retired, nothing
      // entered, nothing changed, and the lane accumulator drains empty.
      // An EMPTY delivered set is reserved for real structural changes
      // whose builder output is unchanged; a re-sync of identical data is
      // not one.
      if (affected.isEmpty && exiting.isEmpty) {
        if (_batchDepth > 0) {
          // Inside a batch the exit drain decides; an empty contribution
          // adds nothing to the batch set and need not force a dispatch.
        } else {
          _ensureLanesResolved();
          final laneFallout = _drainLaneChangedKeys();
          if (laneFallout.isNotEmpty) {
            _fireStructural(laneFallout);
          }
        }
      } else {
        _notifyStructural(affected);
      }
    } finally {
      _bulkDepth--;
      if (_bulkDepth == 0) {
        _spanIndex.flushPendingSorts();
      }
    }
  }

  /// Adds one item at [span]. A key already in the live set is caller
  /// error and throws.
  void addItem(TItem item, BoardSpan span) {
    _assertNotDisposed();
    final key = _keyOf(item);
    if (_liveIdOf(key) != BoardStore.noId) {
      _throwDuplicateKey("addItem", key);
    }
    _retireGhostOf(key);
    final id = _store.allocate(key);
    if (_store.lastAllocationWasRecycled) {
      // A recycled id must not carry the previous occupant's animation
      // records; the release path clears too, and the registry idiom
      // requires both.
      _anim.clearForId(id);
    }
    _store.setData(id, item);
    // No de-registration step: a fresh id has no previous span.
    _store.setSpan(id, span);
    _spanIndex.register(id, bulk: _bulkDepth > 0);
    _lanes.registerItem(id);
    if (_animationStyle.effectiveItemEnterExit.duration != Duration.zero) {
      _anim.animateEnter(id);
    }
    _notifyStructural(<TKey>{key});
  }

  /// Removes [key] from the live set: synchronously under a zero
  /// itemEnterExit, and through an exit ramp otherwise. A key removed
  /// while its own enter is in flight exits from where it currently is,
  /// and never carries both direction bits.
  void removeItem(TKey key) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "removeItem");
    _exitOrRetire(key, id, notify: true);
  }

  /// The shared removal route for [removeItem] and [setItems]'s exits.
  void _exitOrRetire(TKey key, int id, {required bool notify}) {
    _cancelDragIfDragged(id);
    if (_store.isEntering(id)) {
      // Capture the ramp BEFORE the record is dropped: read afterwards
      // it answers 1 and the item pops to full extent before shrinking.
      final r = _anim.enterExitProgressOf(id);
      // Directly, NOT through retireExitNow: the handler's ENTER branch
      // clears the live entering bit first, which is the only ordering
      // under which a following bit-0 set leaves exactly one bit set.
      _anim.finalizeEnterExit(id);
      if (r <= precisionErrorTolerance) {
        // The enter never ticked: retire synchronously, install nothing.
        _retireItem(key, id, notify: notify);
        return;
      }
      _anim.animateExit(id, from: r);
      if (notify) {
        _notifyStructural(<TKey>{});
      }
      return;
    }
    if (_animationStyle.effectiveItemEnterExit.duration == Duration.zero) {
      _retireItem(key, id, notify: notify);
      return;
    }
    _anim.animateExit(id, from: 1.0);
    if (notify) {
      _notifyStructural(<TKey>{});
    }
  }

  /// The re-add door: a key whose previous incarnation is still exiting
  /// retires it NOW, not gated on the family, so the fresh enter gets a
  /// fresh id. The retire defers its delivery; the caller's own
  /// notification drains the fallout.
  void _retireGhostOf(TKey key) {
    final ghost = _store.idOf(key);
    if (ghost != BoardStore.noId && _store.isExiting(ghost)) {
      _batchAffected.remove(key);
      _anim.retireExitNow(ghost, deliver: false);
    }
  }

  /// Overwrites [key]'s payload and nothing else.
  ///
  /// The ONLY mutator that fires the item-data channel, and the only one
  /// that writes the payload without writing a span. It fires
  /// unconditionally rather than on a difference, because the caller
  /// asking for it is the signal; [setItems] compares instead, because it
  /// is a diff.
  void updateItem(TKey key, TItem item) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "updateItem");
    assert(
      _keyOf(item) == key,
      "BoardController.updateItem: keyOf(item) is ${_keyOf(item)}, not "
      "$key. Rewriting one key's slot with another key's payload would "
      "leave the key-to-id map naming the wrong item.",
    );
    _store.setData(id, item);
    _notifyItemData(key);
  }

  /// Moves [key] to [span].
  ///
  /// [duration] and [curve] resolve a null against the `itemSlide`
  /// family, at the slide install, which lands with the animation
  /// sources; this step writes the span and notifies.
  void moveItem(TKey key, BoardSpan span, {Duration? duration, Curve? curve}) {
    _assertNotDisposed();
    _writeSpan(key, span, "moveItem", duration: duration, curve: curve);
  }

  /// Resizes [key] to [span]. See [moveItem] for [duration] and [curve].
  ///
  /// The two mutators write the same eight arrays through the same
  /// ordering and differ only in the slide they install, which is why they
  /// share [_writeSpan] rather than one calling the other: neither is a
  /// special case of the other and a caller reading a stack trace should
  /// see the name it called.
  void resizeItem(
    TKey key,
    BoardSpan span, {
    Duration? duration,
    Curve? curve,
  }) {
    _assertNotDisposed();
    _writeSpan(key, span, "resizeItem", duration: duration, curve: curve);
  }

  /// Runs [body] with the structural and item-data channels coalesced into
  /// one dispatch at the outermost exit.
  ///
  /// Per-channel contract, which is the tree's:
  ///
  /// - STRUCTURAL: deferred. Fires once on exit with the union of affected
  ///   keys. One in-batch `null` is a POISON PILL: it forces the exit
  ///   notification to `null` even if every other in-batch call carried a
  ///   set.
  /// - ITEM DATA: deferred, deduplicated by key, and fired after the
  ///   structural one. A key that was both structurally and data-mutated
  ///   gets both, because the structural-subsumes-data rule is about ONE
  ///   mutation and a batch is many.
  /// - ANIMATION: NOT deferred. Ticks fire on their own vsync schedule and
  ///   a batch body is synchronous, so nothing about batching reaches
  ///   them; deferring them would also defer the uncoalesced settle
  ///   notify, whose whole contract is that it is synchronous.
  ///
  /// The notifications fire even when [body] throws, so listeners always
  /// see the post-batch state, and the exception propagates after them.
  /// The bulk registration flush is in the same `finally` for the same
  /// reason.
  void runBatch(void Function() body) {
    _assertNotDisposed();
    _batchDepth++;
    _bulkDepth++;
    try {
      body();
    } finally {
      _bulkDepth--;
      if (_bulkDepth == 0) {
        _spanIndex.flushPendingSorts();
      }
      _batchDepth--;
      if (_batchDepth == 0) {
        _flushBatchNotifications();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Render port registration.
  //
  // Internal-use channel for the render object; not part of the supported
  // surface. Public because it crosses a library boundary, in the same
  // sense the id-keyed reads above are. The one binding through which the
  // scroll orchestrator reaches the two `ScrollPosition`s; it and the
  // identity test below are the stored port's only readers.
  // ---------------------------------------------------------------------

  /// Internal-use channel for [BoardDragController]; not part of the
  /// supported surface. The single writer of the `dragging` flag in both
  /// directions, and the single site that registers and clears the
  /// mutation-cancel hook that rides it: `dragging: true` stores
  /// [onMutationCancel] (at most one is ever held, because at most one
  /// session is live); `dragging: false` clears the bit AND the hook in
  /// the same call, which is what stops a stale hook firing into a
  /// torn-down session.
  void markDragging(
    TKey key, {
    required bool dragging,
    VoidCallback? onMutationCancel,
  }) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "markDragging");
    _store.setFlag(id, BoardStore.draggingBit, dragging);
    _onMutationCancel = dragging ? onMutationCancel : null;
  }

  /// The mutation-cancel hook a live drag session registered, invoked by
  /// the four span mutators when they touch the dragged key.
  VoidCallback? _onMutationCancel;

  /// The mutation-cancel rule: a mutation that removes or re-spans the
  /// dragged key cancels the session BEFORE the mutation proceeds, by
  /// running the hook, which performs the ordinary cancel path and clears
  /// the bit through [markDragging].
  void _cancelDragIfDragged(int id) {
    if (!_store.isDragging(id)) {
      return;
    }
    final hook = _onMutationCancel;
    if (hook != null) {
      hook();
    }
  }

  /// Internal-use channel for the drag layer and for tests; not part of
  /// the supported surface. The declared ROUTE to the make-room engine's
  /// `previewGap`: [prospective] is the SPAN the drag resolves to, never
  /// the hovered cell, and a null [duration] or [curve] resolves there
  /// against `effectiveMakeRoom`, which keeps the kill-switch disjunction
  /// two-termed.
  void previewMakeRoomGap({
    required TKey draggedKey,
    required BoardSpan prospective,
    bool lifted = false,
    Duration? duration,
    Curve? curve,
  }) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(draggedKey, "previewMakeRoomGap");
    _anim.makeRoom.previewGap(
      draggedId: id,
      prospective: prospective,
      lifted: lifted,
      duration: duration,
      curve: curve,
    );
  }

  /// Releases every held make-room offset. See [previewMakeRoomGap].
  void releaseMakeRoomPreview({Duration? duration, Curve? curve}) {
    _assertNotDisposed();
    _anim.makeRoom.releasePreview(duration: duration, curve: curve);
  }

  /// Internal-use channel for the drag layer; not part of the supported
  /// surface. The drop-settle glide, riding the slide engine with its own
  /// family; [duration] and [curve] are the session's captured spec,
  /// while the family's zero kill switch reads the live style.
  void animateDropSettle(
    TKey key,
    Offset delta, {
    required Duration duration,
    required Curve curve,
  }) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "animateDropSettle");
    _anim.slide.animateSlideFrom(
      id,
      delta,
      family: BoardAnimationFamily.dropSettle,
      duration: duration,
      curve: curve,
    );
  }

  /// Internal-use channel for the render object; not part of the
  /// supported surface. The one route from the track-sizing step of
  /// layout to the resize animator, which lives in a library the render
  /// object cannot name. Forwards and decides nothing.
  void animateTrackResize(Axis axis, int track, double from, double to) {
    _anim.trackResize.animateTrackResize(axis, track, from, to);
  }

  /// Internal-use channel for the render object; not part of the
  /// supported surface. The track-sizing step's make-room latch EDGE
  /// hands the track's in-flight resize in here, because from that pass
  /// on the extent is TERM-DRIVEN and a state in flight would make paint
  /// read the animator instead of the recorded term. Forwards and decides
  /// nothing.
  void finalizeTrackResize(Axis axis, int track) {
    _anim.trackResize.finalizeTrack(axis, track);
  }

  /// Debug-only: the id whose prospective make-room occupancy the slots
  /// carry, or null. Non-null exactly while a slot exists, which is the
  /// only observable separating a leaked lifecycle key from a clean one.
  int? get debugMakeRoomLiftedId {
    return _anim.makeRoom.liftedId;
  }

  /// Debug-only: successful slide installs, for the reflow contract.
  int get debugSlideInstallCount {
    return _anim.slide.debugInstallCount;
  }

  /// Internal-use channel for the render object; not part of the
  /// supported surface. The OFFSET half of the animated axis read: how
  /// far [track] paints from its settled offset given resizes in flight
  /// between the window's first track and it.
  double animatedOffsetShiftBetween(Axis axis, int fromTrack, int track) {
    return _anim.trackResize.offsetShiftBetween(axis, fromTrack, track);
  }

  /// Scrolls both axes so cell `(row, col)` lands aligned, below the
  /// frozen bands when [avoidFrozenTracks] is true. Completes true only
  /// when BOTH axes' legs landed; false when either leg was superseded
  /// by a later call on that axis, when no render object is attached
  /// (a registered port that has not laid out yet costs one frame's
  /// wait first), or when the port went away mid-scroll. The landing is
  /// re-derived by a post-frame settle snap, because a driven scroll
  /// overwrites in-layout corrections with absolute values.
  Future<bool> animateScrollToCell(
    int row,
    int col, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.linear,
    double rowAlignment = 0.0,
    double colAlignment = 0.0,
    bool avoidFrozenTracks = true,
  }) {
    _assertNotDisposed();
    return _orchestrator.animateScrollToCell(
      row,
      col,
      duration: duration,
      curve: curve,
      rowAlignment: rowAlignment,
      colAlignment: colAlignment,
      avoidFrozenTracks: avoidFrozenTracks,
    );
  }

  /// Jumps both axes to cell `(row, col)`. No port is a no-op; a port
  /// that has not laid out gets one deferred post-frame jump.
  void jumpToCell(int row, int col, {bool avoidFrozenTracks = true}) {
    _assertNotDisposed();
    _orchestrator.jumpToCell(
      row,
      col,
      avoidFrozenTracks: avoidFrozenTracks,
    );
  }

  /// The extent of the LEADING frozen band on [axis], measured from the
  /// leading viewport edge; 0.0 with no frozen tracks there, and 0.0
  /// with no render object attached, which a caller cannot tell apart
  /// and does not need to.
  double frozenInsetOf(Axis axis) {
    _assertNotDisposed();
    return _orchestrator.frozenInsetOf(axis);
  }

  /// Registers [port] as the render object driving this controller.
  ///
  /// Called from `RenderBoardViewport.attach`, and idempotent, because a
  /// `GlobalKey` move detaches and reattaches. A second registration by a
  /// DIFFERENT render object replaces the first, which is the order a
  /// `GlobalKey` move produces: the new render object attaches before the
  /// old one detaches.
  void attachRenderPort(BoardRenderPort<TKey> port) {
    _assertNotDisposed();
    _renderPort = port;
  }

  /// Clears the registration [attachRenderPort] made, and ONLY when the
  /// registered port IS [port].
  ///
  /// The identity test is what keeps a `GlobalKey` move from clearing a
  /// live binding: the new render object has already registered by the
  /// time the old one detaches.
  void detachRenderPort(BoardRenderPort<TKey> port) {
    if (identical(_renderPort, port)) {
      // In-flight scroll legs complete false rather than waiting on a
      // ScrollPosition that is no longer in a tree.
      _orchestrator.cancelInFlight();
      _renderPort = null;
    }
  }

  // ---------------------------------------------------------------------
  // Channels.
  // ---------------------------------------------------------------------

  /// Subscribes to structural changes. See the class doc for what the key
  /// set's three shapes mean.
  void addStructuralListener(void Function(Set<TKey>? affectedKeys) l) {
    _assertNotDisposed();
    _structuralListeners.add(l);
  }

  /// Unsubscribes a listener added by [addStructuralListener].
  void removeStructuralListener(void Function(Set<TKey>? affectedKeys) l) {
    _structuralListeners.remove(l);
  }

  /// Subscribes to payload-only writes.
  void addItemDataListener(void Function(TKey key) l) {
    _assertNotDisposed();
    _itemDataListeners.add(l);
  }

  /// Unsubscribes a listener added by [addItemDataListener].
  void removeItemDataListener(void Function(TKey key) l) {
    _itemDataListeners.remove(l);
  }

  /// Subscribes to animation ticks.
  void addAnimationListener(VoidCallback l) {
    _assertNotDisposed();
    _animationListeners.add(l);
  }

  /// Unsubscribes a listener added by [addAnimationListener].
  void removeAnimationListener(VoidCallback l) {
    _animationListeners.remove(l);
  }

  /// Releases everything this controller owns.
  ///
  /// The ordered teardown script has five steps; the first three tear down
  /// the scroll orchestrator, the in-flight enters and exits, and the four
  /// tickers, and land with those components. Steps 4 and 5 are here:
  /// drop the three listener lists and dispose the selection notifier,
  /// then mark the controller disposed. Most public members assert on
  /// that flag; the deliberate carve-outs are the id-keyed hot-path reads
  /// (no per-call assert on the layout path) and the removal-side
  /// teardown members (`remove*Listener`, [detachRenderPort]), which must
  /// stay callable while a render object tears down against a controller
  /// that went first.
  ///
  /// Disposing a controller a mounted board still uses is caller error,
  /// and the assert below is what catches it: a live board holds a
  /// structural listener for as long as it is attached.
  void dispose() {
    _assertNotDisposed();
    assert(
      _structuralListeners.isEmpty &&
          _itemDataListeners.isEmpty &&
          _animationListeners.isEmpty,
      "BoardController.dispose: ${_structuralListeners.length} structural, "
      "${_itemDataListeners.length} item-data and "
      "${_animationListeners.length} animation listeners are still "
      "registered. A mounted board unsubscribes when it detaches, so a "
      "non-empty list here means something still using this controller is "
      "about to read a disposed one.",
    );
    // The orchestrator first: its in-flight legs complete false before
    // anything they might read is torn down.
    _orchestrator.dispose();
    // Finalize every in-flight enter and exit (no listener can hear it;
    // the assert above requires the lists empty), then the tickers.
    _anim.dispose();
    _structuralListeners.clear();
    _itemDataListeners.clear();
    _animationListeners.clear();
    _selection.dispose();
    _renderPort = null;
    _disposed = true;
  }

  // ---------------------------------------------------------------------
  // Internals.
  // ---------------------------------------------------------------------

  /// The narrow read interface the render layer binds to. Read off the
  /// controller and never injected separately, so there is exactly one
  /// binding to swap on a controller swap.
  BoardAnimationReader<TKey> get anim {
    return _anim;
  }

  /// Resolves every dirty lane bucket and clears the dirty set.
  ///
  /// The door to the resolver's own work, called from two kinds of site:
  /// the start of layout, before track sizing, and the ENTRY of every read
  /// that reports a lane value, which is [laneOf], [laneCountOf],
  /// [laneOfId], [laneCountOfId] and the `affectedKeys` computation.
  /// Both, not one: a layout-head-only flush would make a lane value
  /// unobservable before the first layout, and there is no layout in a
  /// controller-only test at all. The layout arm is the render object's
  /// call to [flushLanesForLayout]; this file carries the read arm.
  ///
  /// Costs one set-empty check when nothing is dirty, which is why the
  /// read entries can afford it unconditionally.
  void _ensureLanesResolved() {
    _lanes.ensureResolved();
  }

  /// The keys whose lane or lane count changed since the last drain.
  ///
  /// Runs AFTER the caller's own [_ensureLanesResolved], and the order is
  /// what makes the pair work: the flush is what puts the current
  /// mutation's changes INTO the accumulator, and this is what takes them
  /// out. Draining rather than reading the dirty-bucket set is the whole
  /// point, because every flush clears that set and a lane read between a
  /// mutation and its notification is ordinary.
  ///
  /// A null key is skipped. That can only be an id released between its
  /// lane change and this drain.
  Set<TKey> _drainLaneChangedKeys() {
    final ids = _lanes.drainLaneChangedIds();
    if (ids.isEmpty) {
      return <TKey>{};
    }
    final keys = <TKey>{};
    for (final id in ids) {
      final key = _store.keyOf(id);
      if (key != null) {
        keys.add(key);
      }
    }
    return keys;
  }

  /// The three ordered steps every span mutator runs.
  ///
  /// DE-REGISTER BEFORE WRITING THE SPAN. Both indices compute the buckets
  /// an id belongs to FROM THE STORE, by reading the id's CURRENT span,
  /// and neither stores the span it registered the id under. Writing first
  /// therefore de-registers from the buckets the item is ABOUT TO occupy
  /// rather than the ones it occupies now, which strands a span-index
  /// entry in every bucket the old span touched and the new one does not,
  /// and leaves the lane resolver's old bucket holding an id that no
  /// longer sits in it.
  void _applySpan(int id, BoardSpan span) {
    _spanIndex.deregister(id);
    _lanes.deregisterItem(id);
    _store.setSpan(id, span);
    _spanIndex.register(id, bulk: _bulkDepth > 0);
    _lanes.registerItem(id);
  }

  void _writeSpan(
    TKey key,
    BoardSpan span,
    String method, {
    Duration? duration,
    Curve? curve,
  }) {
    final id = _liveIdOrThrow(key, method);
    _cancelDragIfDragged(id);
    // The OLD content-space leading corner, captured BEFORE the write:
    // read afterwards it is the new corner and the delta is a silent
    // zero.
    final oldLead = _itemLeadOfId(id);
    final oldFrozen = _isFrozenPrimaryStart(id);
    _applySpan(id, span);
    // The NEW corner reads the POST-mutation lane through the read API,
    // whose entry flush resolves the buckets the write dirtied.
    final newLead = _itemLeadOfId(id);
    final delta = oldLead - newLead;
    // A span whose primary start track is frozen at either endpoint does
    // not share the scroll subtraction, so the content-space difference
    // is not the painted one: install nothing and land without a slide.
    final crossesFrozen = oldFrozen || _isFrozenPrimaryStart(id);
    if (delta != Offset.zero && !crossesFrozen) {
      _anim.slide.animateSlideFrom(
        id,
        delta,
        family: BoardAnimationFamily.itemSlide,
        duration: duration,
        curve: curve,
      );
    }
    _notifyStructural(<TKey>{key});
  }

  /// The item-geometry rule's leading corner in CONTENT space, both axes.
  Offset _itemLeadOfId(int id) {
    return Offset(
      _itemLeadOn(Axis.horizontal, id),
      _itemLeadOn(Axis.vertical, id),
    );
  }

  double _itemLeadOn(Axis axis, int id) {
    final config = axis == Axis.vertical ? _rows : _columns;
    final boardAxis = config.axis;
    if (_lanes.laneAxis == axis && _lanes.isLaned(id)) {
      final track = _store.startTrackOf(id, axis).floor();
      return boardAxis.offsetOf(track) +
          _laneOriginOfId(id, laneOfId(id), laneCountOfId(id));
    }
    final start = _store.startTrackOf(id, axis);
    final clamped = start < boardAxis.trackCount.toDouble()
        ? start
        : boardAxis.trackCount.toDouble();
    return boardAxis.offsetOfFraction(clamped);
  }

  /// The two-mode lane origin, measured from the item's lane-axis
  /// track's leading edge.
  double _laneOriginOfId(int id, int lane, int laneCount) {
    final axis = _lanes.laneAxis;
    if (axis == null) {
      return 0.0;
    }
    final config = axis == Axis.vertical ? _rows : _columns;
    final padding = config.lanePadding;
    if (config.axis.acceptsMeasurements) {
      return padding + lane * config.laneExtent!;
    }
    final track = _store.startTrackOf(id, axis).floor();
    final slice =
        (config.axis.extentOf(track) - padding).clamp(0.0, double.infinity) /
        laneCount;
    return padding + lane * slice;
  }

  bool _isFrozenPrimaryStart(int id) {
    final primary = primaryAxis;
    final config = primary == Axis.vertical ? _rows : _columns;
    final track = _store.startTrackOf(id, primary).floor();
    if (track < config.frozenStart) {
      return true;
    }
    return track >= config.axis.trackCount - config.frozenEnd;
  }

  /// The dry-run lane resolution the make-room gap derives its offsets
  /// from: the dragged item's intervals overridden by [prospective], the
  /// laning predicate applied to it, and nothing written to the model.
  Map<int, ({int lane, int laneCount})> _dryRunLanes(
    int draggedId,
    BoardSpan prospective,
  ) {
    final laneAxis = _lanes.laneAxis;
    if (laneAxis == null) {
      return const <int, ({int lane, int laneCount})>{};
    }
    _ensureLanesResolved();
    final sweepAxis = laneAxis == Axis.vertical
        ? Axis.horizontal
        : Axis.vertical;
    double startOn(Axis axis) {
      return axis == Axis.vertical
          ? prospective.rowStart + prospective.rowFraction
          : prospective.colStart + prospective.colFraction;
    }

    double endOn(Axis axis) {
      return axis == Axis.vertical
          ? prospective.rowStart +
                prospective.rowFraction +
                prospective.rowSpan +
                prospective.rowSpanFraction
          : prospective.colStart +
                prospective.colFraction +
                prospective.colSpan +
                prospective.colSpanFraction;
    }

    return _lanes.resolveDryRun(
      draggedId: draggedId,
      prospectiveLaneStart: startOn(laneAxis),
      prospectiveLaneEnd: endOn(laneAxis),
      prospectiveSweepStart: startOn(sweepAxis),
      prospectiveSweepEnd: endOn(sweepAxis),
    );
  }

  /// Retires one live id SYNCHRONOUSLY, through the coordinator's retire
  /// door, which sets the exiting bit and finalizes in one statement.
  ///
  /// Two arms. Delivered, outside a batch: the handler flushes, drains
  /// minus the retired key, releases last so the surviving neighbours
  /// still resolve, and fires. Deferred, inside a batch or under a
  /// suppressed notification: the release runs first and the caller's
  /// own drain drops the retired id through its null-key filter.
  void _retireItem(TKey key, int id, {required bool notify}) {
    // The retired key must not survive in a set an earlier in-batch
    // mutation, or an earlier step of this same call, put it in. The
    // de-registrations, the bit pair, the release and the delivery all
    // live in the coordinator's retire path, which is the single site
    // that can end an id.
    _batchAffected.remove(key);
    if (!notify || _batchDepth > 0) {
      if (notify) {
        _batchStructural = true;
      }
      // The drain runs at the caller's notification point, which is after
      // this release, so the retiring id's own lane change resolves to a
      // null key and is skipped there rather than named.
      _anim.retireExitNow(id, deliver: false);
      return;
    }
    _anim.retireExitNow(id);
  }

  /// Delivers or defers one mutation's structural notification.
  void _notifyStructural(Set<TKey> affected) {
    if (_batchDepth > 0) {
      _batchStructural = true;
      _batchAffected.addAll(affected);
      return;
    }
    _ensureLanesResolved();
    _fireStructural(affected..addAll(_drainLaneChangedKeys()));
  }

  /// Delivers or defers a FULL-REFRESH structural notification, whose key
  /// set is null.
  ///
  /// Drains the lane-change accumulator and DISCARDS it. No flush clears
  /// the accumulator, so a null notification that skipped the drain would
  /// carry this change's ids into the next mutation's key set, where they
  /// would name keys nothing had touched.
  void _notifyStructuralFull() {
    if (_batchDepth > 0) {
      _batchStructural = true;
      _batchStructuralUnknown = true;
      return;
    }
    _ensureLanesResolved();
    _drainLaneChangedKeys();
    _fireStructural(null);
  }

  void _notifyItemData(TKey key) {
    if (_batchDepth > 0) {
      _batchDataKeys.add(key);
      return;
    }
    _fireItemData(key);
  }

  void _flushBatchNotifications() {
    final structural = _batchStructural;
    final unknown = _batchStructuralUnknown;
    Set<TKey>? affected;
    if (structural) {
      _ensureLanesResolved();
      final drained = _drainLaneChangedKeys();
      if (!unknown) {
        affected = _batchAffected..addAll(drained);
      }
    }
    final dataKeys = _batchDataKeys.toList(growable: false);
    _batchStructural = false;
    _batchStructuralUnknown = false;
    // Replaced rather than cleared: the same instance was just handed to
    // the listeners.
    _batchAffected = <TKey>{};
    _batchDataKeys.clear();
    if (structural) {
      _fireStructural(affected);
    }
    for (final key in dataKeys) {
      _fireItemData(key);
    }
  }

  /// Dispatches to the structural listeners over a copy of the list, so a
  /// listener that unsubscribes from inside its own callback does not
  /// corrupt the iteration. Off the per-frame path, so the copy is
  /// affordable.
  void _fireStructural(Set<TKey>? affected) {
    if (_structuralListeners.isEmpty) {
      return;
    }
    for (final listener in List<void Function(Set<TKey>?)>.of(
      _structuralListeners,
    )) {
      listener(affected);
    }
  }

  void _fireItemData(TKey key) {
    if (_itemDataListeners.isEmpty) {
      return;
    }
    for (final listener in List<void Function(TKey)>.of(_itemDataListeners)) {
      listener(key);
    }
  }

  /// Re-derives both axis identities after an axis config was replaced.
  ///
  /// A new config changes the track count the measurements and the lane
  /// buckets were built against, so state keyed on either is invalidated
  /// rather than migrated. Each index re-keys itself and drops every
  /// bucket when its own axis moved, and the items are re-registered into
  /// the new partition.
  /// A rewrapped, already-measured LazyContentAxis instance arrives
  /// carrying extents measured against the old configuration's lanes and
  /// items; the swap drops them. A fresh instance makes this a no-op.
  void _resetSwappedAxis(BoardAxisConfig config) {
    final axis = config.axis;
    if (axis is LazyContentAxis) {
      axis.resetMeasurements();
    }
  }

  void _reconfigureAxes(Axis swapped) {
    final primary = _derivePrimaryAxis(_rows, _columns);
    if (primary != _spanIndex.primaryAxis) {
      _spanIndex.primaryAxis = primary;
      for (final id in _store.ids) {
        _spanIndex.register(id, bulk: true);
      }
      _spanIndex.flushPendingSorts();
    }
    // Extents animated against one lattice are not evidence about
    // another: land the swapped axis's in-flight resizes at their
    // targets. The other axis's lattice did not change, so its states
    // survive.
    _anim.trackResize.finalizeAll(axis: swapped);
    final lane = _deriveLaneAxis(_rows, _columns);
    if (lane != _lanes.laneAxis) {
      // Every key named a track on an axis that is no longer the lane
      // axis, and which items are laned at all is re-decided by the
      // criterion, so the partition is rebuilt rather than marked dirty.
      _lanes.laneAxis = lane;
      _spanIndex.laneAxis = lane;
      for (final id in _store.ids) {
        _lanes.registerItem(id);
      }
    }
    _notifyStructuralFull();
  }

  /// The PRIMARY axis: the CONTENT-SIZED axis when one exists and the ROW
  /// axis otherwise.
  ///
  /// At most one axis is content-sized, so it is single-valued, and
  /// neither arm can be absent, so it is defined for every legal board.
  /// This is the bucket key of the span index and, later, the item
  /// vicinity's yIndex. It is NOT the lane axis, which may be null.
  static Axis _derivePrimaryAxis(
    BoardAxisConfig rows,
    BoardAxisConfig columns,
  ) {
    if (rows.axis.acceptsMeasurements) {
      return Axis.vertical;
    }
    if (columns.axis.acceptsMeasurements) {
      return Axis.horizontal;
    }
    return Axis.vertical;
  }

  /// The LANE axis: whichever config carries a non-null `laneExtent`, or
  /// null when neither does.
  static Axis? _deriveLaneAxis(BoardAxisConfig rows, BoardAxisConfig columns) {
    if (rows.laneExtent != null) {
      return Axis.vertical;
    }
    if (columns.laneExtent != null) {
      return Axis.horizontal;
    }
    return null;
  }

  static bool _debugValidateConfigs(
    BoardAxisConfig rows,
    BoardAxisConfig columns,
  ) {
    assert(
      !(rows.axis.acceptsMeasurements && columns.axis.acceptsMeasurements),
      "BoardController: at most one axis may be content-sized. Two content "
      "axes are circular: each would have to resolve against the other, "
      "with no termination guarantee.",
    );
    assert(
      rows.laneExtent == null || columns.laneExtent == null,
      "BoardController: at most one axis may carry a laneExtent, and it is "
      "the lane axis. Two would leave the lane axis, and with it every "
      "lane bucket's key, undefined.",
    );
    return true;
  }

  /// [key]'s id, or -1 when it is not in the LIVE set. An exiting item is
  /// still registered and still has an id; it is not live.
  int _liveIdOf(TKey key) {
    _assertNotDisposed();
    final id = _store.idOf(key);
    if (id == BoardStore.noId || _store.isExiting(id)) {
      return BoardStore.noId;
    }
    return id;
  }

  int _liveIdOrThrow(TKey key, String method) {
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      _throwUnknownKey(method, key);
    }
    return id;
  }

  /// Whether [id]'s stored span already equals [span], component by
  /// component. Compares in place rather than materializing a span,
  /// because the diff runs once per key of a bulk call.
  bool _spanEquals(int id, BoardSpan span) {
    return _store.rowStartOf(id) == span.rowStart &&
        _store.rowSpanOf(id) == span.rowSpan &&
        _store.colStartOf(id) == span.colStart &&
        _store.colSpanOf(id) == span.colSpan &&
        _store.rowFractionOf(id) == span.rowFraction &&
        _store.colFractionOf(id) == span.colFraction &&
        _store.rowSpanFractionOf(id) == span.rowSpanFraction &&
        _store.colSpanFractionOf(id) == span.colSpanFraction;
  }

  /// Throws for a key that is not in the live set.
  ///
  /// The debug assert comes first, so the failure surfaces at the call
  /// site during development, and the throw is what release builds take.
  /// The assert's CONDITION throws the [StateError] rather than evaluating
  /// false, so a caller catches the same type in both build modes;
  /// `assert(false, message)` would report an `AssertionError` in debug
  /// and a [StateError] only in release, which is a difference callers
  /// cannot write one `catch` for.
  Never _throwUnknownKey(String method, TKey key) {
    final message =
        "BoardController.$method: no live item with key $key. Query with "
        "contains() when the key's presence is not already guaranteed.";
    assert(() {
      throw StateError(message);
    }());
    throw StateError(message);
  }

  /// Throws for a key that is already in the live set. The other half of
  /// the key-arity rule: the unknown-key case is a key that is known zero
  /// times, this one is a key that is known twice.
  Never _throwDuplicateKey(String method, TKey key) {
    final message =
        "BoardController.$method: key $key is already in the live set. Use "
        "updateItem(), moveItem() or resizeItem() to change an item that "
        "is already on the board.";
    assert(() {
      throw StateError(message);
    }());
    throw StateError(message);
  }

  void _assertNotDisposed() {
    assert(
      !_disposed,
      "BoardController: this controller has been disposed and its state "
      "has been released.",
    );
  }
}
