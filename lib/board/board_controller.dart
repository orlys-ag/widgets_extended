/// The board's L2 controller: the single owner of item state, of the two
/// spatial indices over it, of the three notification channels, of the
/// selection value, and of the two collaborators it delegates to, the
/// animation coordinator and the scroll orchestrator.
///
/// The coordinator owns the four animation sources and is the single
/// writer of the store's entering and exiting bits; the members that
/// reach it are `anim`, `previewMakeRoomGap`, `releaseMakeRoomPreview`,
/// `animateDropSettle`, `animateMakeRoomHandOff` and `animateTrackResize`.
/// The orchestrator answers
/// `animateScrollToCell`, `jumpToCell` and `frozenInsetOf`. The drag
/// state that lives HERE is `markDragging`'s bit and the
/// mutation-cancel hook whose lifetime is the bit's.
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

part '_board_controller_internals.dart';

/// Which frozen band, if any, an item is pinned in on one axis; see
/// `BoardControllerInternals.pinOfId`. Internal-use; the barrel does not
/// export it.
enum BoardPin {
  /// In no band: the item scrolls on this axis.
  none,

  /// Wholly inside the leading band, pinned to the viewport's leading
  /// edge.
  leading,

  /// Wholly inside the trailing band, pinned to the viewport's trailing
  /// edge.
  trailing,
}

/// A settled rectangle captured BEFORE a write, for the FLIP install
/// after it. It rides with its KEY because an id is not identity across
/// a bulk call: ids are recycled off a LIFO free list, so an id one of
/// the call's own retires released can come back allocated to another
/// key, and only the key catches that. Not to the SAME key: `setItems`
/// retires only keys its placements omit and allocates only keys they
/// name that have no id, `addItem` retires nothing, and a key whose exit
/// is running comes back on its own id (`BoardController._resurrect`).
/// `lead` and `extent` are content space; `pinTerm` is, per axis, what
/// the normalized lead is the content lead minus at capture time (see
/// `BoardController._pinTermOf`); `laneTrack` is the lane-axis start
/// track, or null when there is no lane axis, and an install whose track
/// is unchanged is a RELANE, an intra-track shift the track-sizing term
/// may read.
typedef _CapturedRect<TKey> = ({
  TKey key,
  Offset lead,
  Offset extent,
  Offset pinTerm,
  int? laneTrack,
});

/// Owns one board's items and answers every question about them.
///
/// The members here are the supported surface. The ones the render
/// object, the widget and the drag controller drive the board through,
/// id-keyed reads and animation channels among them, are declared in
/// [BoardControllerInternals], which the package barrel does not export.
///
/// Two type parameters and no more: [TKey] identifies an item and [TItem]
/// is the caller's payload. There is no per-cell payload type, because a
/// cell is a lattice position rather than a stored thing.
///
/// Three notification channels, whose contract is the tree's:
///
/// - [addStructuralListener] takes a nullable key set. `null` means the
///   scope is unknown and the listener should do a full refresh; an EMPTY
///   set means a structural change occurred but no item's rendered inputs
///   changed, so an item shown by key needs no rebuild (a removal is one:
///   the removed key is gone rather than changed); a NON-EMPTY set means
///   exactly these keys may differ. The inputs are a
///   built child's RENDERED inputs, which for a board are its payload, its
///   span, its lane and its lane count, not only the span: a lane change
///   with an unchanged span is a change and is the one an implementer
///   drops.
/// - [addItemDataListener] fires for a payload-only write. [updateItem] is
///   the only mutator that fires it, because it is the only one that
///   writes the payload without writing a span. Structural SUBSUMES data:
///   no single mutation fires both for one key.
/// - [addAnimationListener] ticks while animations run. Its producer is
///   the animation coordinator, which coalesces to one dispatch per
///   frame inside the transient-callbacks phase, with an uncoalesced
///   carve-out for the two engines whose settle notify carries a
///   synchronous ordering contract.
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
  /// [vsync] is the [TickerProvider] the four animation sources tick
  /// against. It is FORWARDED to the coordinator and never stored here:
  /// each source creates its own ticker from it, and this class holds no
  /// vsync field.
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
      trackCount: _primaryConfigOf(rows, columns).axis.trackCount,
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
      prospectiveExtentOf: _prospectiveExtentDelta,
      laneOfId: laneOfId,
      laneCountOfId: laneCountOfId,
      captureSettleRelanes: _captureSettleRelanes,
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
  /// lane axes and fires a full-refresh structural notification. A change
  /// to the primary axis's track count re-files the items that reach past
  /// the smaller lattice, and a change of primary axis re-files every
  /// item.
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
    final old = _rows;
    _rows = value;
    _resetSwappedAxis(old, value);
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
    final old = _columns;
    _columns = value;
    _resetSwappedAxis(old, value);
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
    _animationStyle = value;
    // DISABLING A FAMILY STOPS ITS MOTION, here and synchronously, and no
    // other family's: every slide record and every track state whose
    // family the NEW style turns off goes, through `isOff`, so a family
    // left inheriting stops with its root and one set explicitly runs
    // on. A slide record purged lands its item at its structural
    // rectangle; a track state dropped lands the track at the settled
    // extent the axis stores, which is why a layout-driving family can be
    // stopped without stranding a partial extent. Two families need no
    // arm here: itemEnterExit is driven past 1 by its tick-time off
    // guard and retired through its handler, which owns the release, and
    // the make-room engine's held gap is a target, not motion.
    bool off(BoardAnimationFamily family) {
      return value.isOff(family);
    }

    final purged = _anim.slide.purgeWhere(off);
    final finalized = _anim.trackResize.finalizeWhere(off);
    if (purged || finalized) {
      _anim.notifyNow();
      // Before a record's FIRST tick no router mirror has latched, so the
      // notify alone routes neither a layout nor a paint: an extent
      // record would leave the child laid out at the animated size, a
      // lead-only one would leave it painted displaced, and a track
      // state would leave the cells at the extents the install frame
      // gave them. An empty structural dirties layout without naming a
      // key.
      _notifyStructural(<TKey>{});
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

  /// [key]'s lane within its lane-axis track: 0 when it is not laned, and
  /// null when it is not in the live set. Flushes dirty lane buckets first, so the
  /// value is observable on the frame of the mutation that changed it and
  /// without a layout.
  int? laneOf(TKey key) {
    _ensureLanesResolved();
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return null;
    }
    return _store.laneOf(id);
  }

  /// The number of lanes [key]'s cluster resolved to: 1 when it is not
  /// laned, and null when it is not in the live set. Flushes first; see
  /// [laneOf].
  int? laneCountOf(TKey key) {
    _ensureLanesResolved();
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return null;
    }
    return _store.laneCountOf(id);
  }

  /// The number of consecutive lanes [key] occupies, counting upward
  /// from [laneOf]: 1 when it is not laned, and null when it is not in the
  /// live set.
  /// Flushes first; see [laneOf].
  int? laneSpanOf(TKey key) {
    _ensureLanesResolved();
    final id = _liveIdOf(key);
    if (id == BoardStore.noId) {
      return null;
    }
    return _store.laneSpanOf(id);
  }

  /// Whether [key] is in the live set. False for a key whose only
  /// incarnation is animating out.
  bool contains(TKey key) {
    return _liveIdOf(key) != BoardStore.noId;
  }

  /// The number of items in the live set. An item animating out is not
  /// counted, as [contains] does not report it. O(1).
  int get itemCount {
    _assertNotDisposed();
    return _store.liveCount;
  }

  /// The keys of the live set, in no particular order: a new list on each
  /// call, so the caller may mutate the board while walking it. An item
  /// animating out is not listed. O(items).
  List<TKey> get keys {
    _assertNotDisposed();
    return _store.liveKeys();
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
  /// An entering key whose exit is still running therefore comes back as
  /// the same item, its exit reversed, as [addItem] describes.
  ///
  /// A duplicate key inside one call is caller error and throws, and so
  /// is a span [addItem] would refuse. Both checks run over the whole
  /// argument BEFORE any mutation, so a throw leaves the board untouched
  /// and there is nothing to notify. A span outside the lattice is kept,
  /// as [addItem] describes.
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
      // Every placement is checked before anything is written, so a bad
      // one refuses the whole call, as a duplicate key does.
      _checkSpan(placement.span, "setItems");
      final key = _keyOf(placement.item);
      if (desired.containsKey(key)) {
        final message =
            "BoardController.setItems: key $key appears more than once in "
            "the placements. Each placement names one item, by its key; "
            "give each item a key of its own.";
        assert(() {
          throw StateError(message);
        }());
        throw StateError(message);
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
      // CAPTURED BEFORE ANY MUTATION, and installed once after the loop:
      // this call's exits and enters re-lane buckets in caller order and
      // lanes resolve lazily, so a per-placement capture would read a
      // rectangle an earlier placement had already moved.
      final captured =
          <int, _CapturedRect<TKey>>{};
      final reSpanned = <int>{};
      if (_installsSlide(null)) {
        // Every bucket this call disturbs: the tracks a changed span
        // leaves and arrives in, a resurrected key's included, the track
        // an entering placement lands on, and the track an exiting item
        // leaves.
        final laneAxis = _lanes.laneAxis;
        // A SET, not a list: the loop below adds one or two entries per
        // placement and every placement in one laned row names the same
        // track, and `_captureLaneBuckets` walks a bucket once per entry.
        // Its own `containsKey` guard already made the result
        // duplicate-independent, so this is a cost change only.
        final tracks = <int?>{};
        for (final key in exiting) {
          tracks.add(_laneStartTrackOf(_store.idOf(key)));
        }
        for (final entry in desired.entries) {
          var id = _liveIdOf(entry.key);
          if (id == BoardStore.noId) {
            final ghost = _store.idOf(entry.key);
            if (ghost == BoardStore.noId || !_store.isExiting(ghost)) {
              // An ENTERING key disturbs the bucket it arrives in.
              if (laneAxis != null) {
                tracks.add(
                  trackIndexOf(entry.value.span.startTrackOn(laneAxis)),
                );
              }
              continue;
            }
            // A key whose exit is running COMES BACK as the same id
            // ([_resurrect]), so it is captured below exactly as a live
            // item whose span may change.
            id = ghost;
          }
          // AN UNCHANGED SPAN DISTURBS NOTHING, so it names no track and
          // nothing walks its bucket. Lanes are a function of the spans
          // in a bucket, and the only write this call makes to such a
          // key is its payload, which the resolver never reads; a
          // neighbour that IS disturbed is reached through the track of
          // whichever key disturbed it. Without this the commonest
          // `setItems` there is, a re-sync of an unchanged list, walked
          // every laned bucket and read every member's geometry twice.
          if (_spanEquals(id, entry.value.span)) {
            continue;
          }
          // The two buckets a changed span disturbs: the one it leaves
          // and the one it arrives in. Named BEFORE the geometry guard
          // below, because an item whose own geometry cannot be read
          // still moves its neighbours, whose geometry can.
          tracks.add(_laneStartTrackOf(id));
          if (laneAxis != null) {
            tracks.add(trackIndexOf(entry.value.span.startTrackOn(laneAxis)));
          }
          if (!_canReadItemGeometry(id)) {
            continue;
          }
          reSpanned.add(id);
          captured[id] = _captureRect(id, entry.key);
        }
        captured.addAll(_captureLaneBuckets(tracks, skip: reSpanned));
      }
      for (final key in exiting) {
        _exitOrRetire(_store.idOf(key));
      }
      for (final entry in desired.entries) {
        final key = entry.key;
        final placement = entry.value;
        final existing = _liveIdOf(key);
        final ghost = existing == BoardStore.noId ? _store.idOf(key) : existing;
        if (existing == BoardStore.noId &&
            ghost != BoardStore.noId &&
            _store.isExiting(ghost)) {
          _resurrect(ghost, placement.item, placement.span, bulk: true);
          affected.add(key);
          continue;
        }
        if (existing == BoardStore.noId) {
          final id = _store.allocate(key);
          if (_store.lastAllocationWasRecycled) {
            _anim.clearForId(id);
          }
          _store.setData(id, placement.item);
          // No de-registration step: a fresh id has no previous span.
          _store.setSpan(id, placement.span);
          _spanIndex.register(id, bulk: true);
          _lanes.registerItem(id);
          if (!_animationStyle.isOff(BoardAnimationFamily.itemEnterExit)) {
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
          _reSpan(existing, placement.span, bulk: true);
          affected.add(key);
        }
      }
      // One lane resolve serves every install: no site inside the loop
      // above reads a lane.
      captured.forEach((id, rect) {
        if (reSpanned.contains(id) && _store.keyOf(id) == rect.key) {
          _installReSpan(id, rect);
        }
      });
      _installRelanes(
        Map<int, _CapturedRect<TKey>>.fromEntries(
          captured.entries.where((entry) {
            return !reSpanned.contains(entry.key);
          }),
        ),
      );
      // A clean no-op diff notifies nothing: nothing retired, nothing
      // entered, nothing changed, and the lane accumulator drains empty.
      // An EMPTY delivered set is reserved for real structural changes
      // that leave every item's rendered inputs unchanged; a re-sync of
      // identical data is not one.
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
  /// error and throws a `StateError`; a span that breaks one of
  /// [BoardSpan]'s rules (a NaN or out-of-range fraction, a negative start
  /// or no extent), or that has an integer start or span above 2147483647,
  /// the largest the board stores, throws an `ArgumentError`, in release
  /// builds too, before anything is written.
  ///
  /// A span that lies outside the lattice is KEPT, not refused: the axes
  /// can change under the items, so an item starting past the last track
  /// is simply not laid out until the lattice covers it, and one that
  /// runs past it is laid out up to the lattice's end.
  ///
  /// A key whose exit is still running is not in the live set, and adding
  /// it brings that SAME item back: its exit reverses from where it has
  /// reached and it grows back at the pace of a full enter, its payload
  /// becomes [item], and a different [span] is reached by a slide from
  /// where it paints, as [moveItem] would. Under a zero itemEnterExit it
  /// is whole at once.
  void addItem(TItem item, BoardSpan span) {
    _assertNotDisposed();
    _checkSpan(span, "addItem");
    final key = _keyOf(item);
    if (_liveIdOf(key) != BoardStore.noId) {
      _throwDuplicateKey("addItem", key);
    }
    final ghost = _store.idOf(key);
    if (ghost != BoardStore.noId && _store.isExiting(ghost)) {
      _resurrect(ghost, item, span);
      _notifyStructural(<TKey>{key});
      return;
    }
    // Captured BEFORE the register, which re-lanes the bucket the item
    // arrives in.
    final laneAxis = _lanes.laneAxis;
    final neighbours = _installsSlide(null)
        ? _captureLaneBuckets(<int?>[
            laneAxis == null ? null : trackIndexOf(span.startTrackOn(laneAxis)),
          ])
        : null;
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
    if (!_animationStyle.isOff(BoardAnimationFamily.itemEnterExit)) {
      _anim.animateEnter(id);
    }
    if (neighbours != null) {
      // The new id is in no captured bucket: nothing this call did
      // between the capture and the allocation released an id.
      _installRelanes(neighbours);
    }
    _notifyStructural(<TKey>{key});
  }

  /// Removes [key] from the live set: synchronously under an off
  /// itemEnterExit, a key whose own enter is still in flight included,
  /// and through an exit ramp otherwise. Under a live itemEnterExit a key
  /// removed while its own enter is in flight exits from where it
  /// currently is, and never carries both direction bits.
  void removeItem(TKey key) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "removeItem");
    // A SYNCHRONOUS retire re-lanes the survivors at once and they
    // animate; an ANIMATED exit keeps the id registered until its
    // settle, so no survivor's rectangle changes here and the install
    // below finds nothing to do. The settle's own re-lane is captured
    // there, through [_captureSettleRelanes].
    //
    // `setItems`' order: capture SKIPPING the removed id, which is no
    // neighbour of itself; remove WITHOUT notifying; install; notify
    // once. No listener runs between the capture and the install, so one
    // that re-adds a key cannot hand the install a recycled id to slide
    // from a dead rectangle.
    final neighbours = _installsSlide(null)
        ? _captureLaneBuckets(<int?>[_laneStartTrackOf(id)], skip: <int>{id})
        : null;
    _exitOrRetire(id);
    if (neighbours != null) {
      _installRelanes(neighbours);
    }
    _notifyStructural(<TKey>{});
  }

  /// The shared removal route for [removeItem] and [setItems]'s exits.
  void _exitOrRetire(int id) {
    _cancelDragIfDragged(id);
    var from = 1.0;
    if (_store.isEntering(id)) {
      // Capture the ramp BEFORE the record is dropped: read afterwards
      // it answers 1 and the item pops to full extent before shrinking.
      from = _anim.enterExitProgressOf(id);
      // Directly, NOT through retireExitNow: the handler's ENTER branch
      // clears the live entering bit first, which is the only ordering
      // under which a following bit-0 set leaves exactly one bit set.
      _anim.finalizeEnterExit(id);
    }
    // Retire synchronously, installing nothing, when the family is off or
    // the enter never ticked.
    if (_animationStyle.isOff(BoardAnimationFamily.itemEnterExit) ||
        from <= precisionErrorTolerance) {
      _anim.retireExitNow(id);
      return;
    }
    _anim.animateExit(id, from: from);
  }

  /// The re-add door: a key whose exit is running comes back as the SAME
  /// item, the way the tree cancels a pending deletion
  /// (`TreeController._cancelDeletion`). The exit is reversed from the
  /// ramp value it reached ([BoardAnimationCoordinator.reverseExit]), the
  /// payload replaced, and a changed span written through [_reSpan],
  /// which slides the item from the rectangle it paints; nothing is
  /// allocated, so its element and `State` stay. The exiting item kept
  /// its span-index entry and its lane record whole, so it needs no
  /// registration. [bulk] is [setItems]', which captured the item with
  /// its other re-spans. The caller notifies.
  void _resurrect(int id, TItem item, BoardSpan span, {bool bulk = false}) {
    _anim.reverseExit(id);
    _store.setData(id, item);
    if (!_spanEquals(id, span)) {
      _reSpan(id, span, bulk: bulk);
    }
  }

  /// Overwrites [key]'s payload and nothing else. A payload whose key is
  /// not [key] throws a `StateError`, in release builds too.
  ///
  /// The ONLY mutator that fires the item-data channel, and the only one
  /// that writes the payload without writing a span. It fires
  /// unconditionally rather than on a difference, because the caller
  /// asking for it is the signal; [setItems] compares instead, because it
  /// is a diff.
  void updateItem(TKey key, TItem item) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "updateItem");
    final itemKey = _keyOf(item);
    if (itemKey != key) {
      // A StateError in BOTH build modes, as the house's other key errors
      // are: an assert alone let a release build write one key's payload
      // into another key's slot.
      final message =
          "BoardController.updateItem: keyOf(item) is $itemKey, not $key. "
          "Rewriting one key's slot with another key's payload would leave "
          "the key-to-id map naming the wrong item.";
      assert(() {
        throw StateError(message);
      }());
      throw StateError(message);
    }
    _store.setData(id, item);
    _notifyItemData(key);
  }

  /// Moves [key] to [span]. A span [addItem] would refuse throws an
  /// `ArgumentError` and leaves the item, and a drag of it, as they were;
  /// a span outside the lattice is kept, as [addItem] describes.
  ///
  /// [duration] and [curve] time the slide from the rectangle the item
  /// paints now to [span]'s, and a null resolves against the itemSlide
  /// family. A zero or negative [duration], or an off itemSlide family,
  /// moves the item without a slide of its own: the change lands this
  /// frame, and a slide already in flight for the item keeps running from
  /// its new rectangle, on its own clock.
  void moveItem(TKey key, BoardSpan span, {Duration? duration, Curve? curve}) {
    _assertNotDisposed();
    _writeSpan(key, span, "moveItem", duration: duration, curve: curve);
  }

  /// Resizes [key] to [span]. See [moveItem] for [duration] and [curve],
  /// and for the `ArgumentError` a span [addItem] would refuse throws.
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
  ///   structural one, and only for a key still on the board, live or
  ///   animating out, when its turn comes. A key that was both
  ///   structurally and data-mutated gets both, because the
  ///   structural-subsumes-data rule is about ONE mutation and a batch is
  ///   many.
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

  /// The mutation-cancel hook a live drag session registered, invoked by
  /// the four span mutators when they touch the dragged key.
  VoidCallback? _onMutationCancel;

  /// The mutation-cancel rule: a mutation that removes or re-spans the
  /// dragged key cancels the session BEFORE the mutation proceeds, by
  /// running the hook, which performs the ordinary cancel path and clears
  /// the bit through [markDragging].
  ///
  /// The hook runs no `BoardDragConfig` callback: it queues the drag's
  /// `onDragEnd` for after the mutation. The mutators rely on that: no
  /// drag callback can change the store between the ids a mutator reads
  /// before calling this and the writes it makes through them after.
  void _cancelDragIfDragged(int id) {
    if (!_store.isDragging(id)) {
      return;
    }
    final hook = _onMutationCancel;
    if (hook != null) {
      hook();
    }
  }

  bool _relaneSlidesSuppressed = false;

  /// Scrolls both axes so cell `(row, col)` lands aligned inside the
  /// region between the frozen bands when [avoidFrozenTracks] is true,
  /// or inside the viewport otherwise. The alignments follow
  /// `Scrollable.ensureVisible`: 0.0 puts the cell's leading edge on the
  /// region's leading edge, 1.0 its trailing edge on the region's
  /// trailing edge, and 0.5 centres it, per axis.
  ///
  /// Completes true only when BOTH axes' legs landed; false when either
  /// leg was taken over, by a later [animateScrollToCell], [jumpToCell]
  /// or [revealCell] that moves its axis, or by the user scrolling, when
  /// no render object is attached (a registered port that has not laid
  /// out yet costs one frame's wait first), or when the port went away
  /// mid-scroll. The landing is re-derived by a post-frame settle snap,
  /// because a driven scroll overwrites in-layout corrections with
  /// absolute values.
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

  /// Scrolls the LEAST that shows cell `(row, col)` between the frozen
  /// bands: an axis where the cell already shows, or where its track is
  /// frozen, does not move, and a cell larger than the region shows its
  /// leading edge. Instant. A board not yet laid out, and a cell outside
  /// the lattice, are no-ops. An [animateScrollToCell] in flight on an
  /// axis this moves completes false. The board's keyboard navigation
  /// reveals each cell it moves to through this.
  void revealCell(int row, int col) {
    _assertNotDisposed();
    _orchestrator.revealCell(row, col);
  }

  /// Jumps both axes to cell `(row, col)`, its leading edges on the
  /// leading edges of the region between the frozen bands when
  /// [avoidFrozenTracks] is true. No port is a no-op; a port that has
  /// not laid out gets one deferred post-frame jump. An
  /// [animateScrollToCell] in flight completes false.
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

  /// Drops every mounted cell's cached measurement and schedules one
  /// layout that re-measures each, except a cell that shows nothing for a
  /// null builder answer, which still contributes nothing to its track.
  ///
  /// A cell is measured when its host rebuilds and not otherwise, so a
  /// widget the cell builder returns that changes size in its OWN
  /// rebuild, one that reads a theme, a text scale or an inherited value
  /// of the app's, keeps its track at the extent it had. Call this after
  /// changing such a value. It costs one viewport layout plus one
  /// measuring layout per cell it re-measures, which is what every
  /// layout cost before the measurement cache; nothing enforces that it
  /// is called rarely.
  ///
  /// A no-op with no board mounted on this controller. On a board with
  /// no content-sized axis it schedules one layout that measures no
  /// cell. Asserts when called during the board's layout, which includes
  /// a cell or item builder and the first build of a cell's content: a
  /// call there would be dropped silently by the framework.
  void invalidateCellMeasurements() {
    _assertNotDisposed();
    _renderPort?.invalidateCellMeasurements();
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
  ///
  /// A listener that throws is reported through `FlutterError.reportError`
  /// and does not stop the listeners after it; the throw does not reach
  /// the tick, mutation or drag that dispatched the notification.
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

  /// Resolves every dirty lane bucket and clears the dirty set.
  ///
  /// The door to the resolver's own work, called from two kinds of site:
  /// the start of layout, before track sizing, and the ENTRY of every read
  /// that reports a lane value, which is [laneOf], [laneCountOf],
  /// [laneSpanOf], [laneOfId], [laneCountOfId], [laneSpanOfId] and the
  /// `affectedKeys` computation.
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
    // Before `_reSpan`, whose first step cancels a drag of this item: a
    // refused span leaves the board as it was, drag included.
    _checkSpan(span, method);
    _reSpan(id, span, duration: duration, curve: curve);
    _notifyStructural(<TKey>{key});
  }

  /// The three ordered steps of a span change that ANIMATES: capture the
  /// settled rectangle, write, install the rect FLIP from the captured
  /// one to the new one.
  ///
  /// [bulk] runs the write alone, for a caller that captures and
  /// installs once for a whole batch rather than per item; a
  /// per-placement capture inside such a batch would read a rectangle an
  /// earlier placement already re-laned.
  ///
  /// Two guards decide whether anything is captured at all. The install
  /// PREDICATE is the slide engine's own refusal, evaluated once here so
  /// a board under a zero itemSlide family pays no capture. The STRAND
  /// guard is [_canReadItemGeometry], on the old span and again on the
  /// new one.
  void _reSpan(
    int id,
    BoardSpan span, {
    Duration? duration,
    Curve? curve,
    bool bulk = false,
  }) {
    _cancelDragIfDragged(id);
    if (bulk || !_installsSlide(duration) || !_canReadItemGeometry(id)) {
      _applySpan(id, span);
      return;
    }
    final captured = _captureRect(id, _store.keyOf(id) as TKey);
    // The two buckets the write disturbs: the one the item LEAVES and
    // the one it ARRIVES in, the second read off the argument because
    // the capture precedes the write.
    final laneAxis = _lanes.laneAxis;
    final neighbours = _captureLaneBuckets(<int?>[
      captured.laneTrack,
      laneAxis == null ? null : trackIndexOf(span.startTrackOn(laneAxis)),
    ], skip: <int>{id});
    _applySpan(id, span);
    _installReSpan(id, captured, duration: duration, curve: curve);
    _installRelanes(neighbours, duration: duration, curve: curve);
  }

  /// Captures the settled rectangle of every member of the lane buckets
  /// on [tracks], for the install after the write. A null or
  /// out-of-range track contributes nothing, which is the strand guard
  /// applied to a whole bucket; [skip] is the written id, whose own
  /// capture carries its own rule.
  ///
  /// The members are COPIED out of the resolver's live list, which the
  /// write mutates in place.
  Map<int, _CapturedRect<TKey>> _captureLaneBuckets(Iterable<int?> tracks, {Set<int> skip = const <int>{}}) {
    final captured = <int, _CapturedRect<TKey>>{};
    final axis = _lanes.laneAxis;
    if (axis == null) {
      return captured;
    }
    final config = axis == Axis.vertical ? _rows : _columns;
    final trackCount = config.axis.trackCount;
    // RESOLVED FIRST. The walk below reads each member's geometry, and
    // the first read of a dirty bucket resolves it, sorting the very list
    // being walked, so a member was skipped; inside `runBatch` a bucket
    // stays dirty across mutations. Resolving here leaves nothing for a
    // read to do.
    _ensureLanesResolved();
    for (final track in tracks) {
      if (track == null || track < 0 || track >= trackCount) {
        continue;
      }
      for (final id in _lanes.laneBucketMembers(track)) {
        if (skip.contains(id) ||
            captured.containsKey(id) ||
            !_canReadItemGeometry(id)) {
          continue;
        }
        final key = _store.keyOf(id);
        if (key == null) {
          continue;
        }
        captured[id] = _captureRect(id, key);
      }
    }
    return captured;
  }

  /// The coordinator's exit SETTLE capture: called with an exiting [id]
  /// before the settle takes it out of the lane index, it captures the
  /// rectangles of the members of the id's lane bucket and returns the
  /// install to run once the lanes re-resolve, or null when nothing can
  /// animate. The capture and the install are the ones [removeItem]
  /// makes around a synchronous retire; an animated exit re-lanes its
  /// survivors only here, when it settles, which is not a mutation door.
  VoidCallback? _captureSettleRelanes(int id) {
    if (!_installsSlide(null)) {
      return null;
    }
    final neighbours = _captureLaneBuckets(
      <int?>[_laneStartTrackOf(id)],
      skip: <int>{id},
    );
    if (neighbours.isEmpty) {
      return null;
    }
    return () {
      _installRelanes(neighbours);
    };
  }

  /// Installs one RELANE FLIP per captured neighbour whose rectangle the
  /// write changed.
  ///
  /// Two tests decide whether a captured entry still names the item it
  /// was captured from: the id must still map to its captured KEY (an id
  /// recycles off a LIFO free list, so one the call's own retires
  /// released comes back to another key; see [_CapturedRect]), and must
  /// not be the item a drag session holds.
  void _installRelanes(
    Map<int, _CapturedRect<TKey>> captured, {
    Duration? duration,
    Curve? curve,
  }) {
    captured.forEach((id, rect) {
      if (_store.keyOf(id) != rect.key ||
          _store.isDragging(id) ||
          !_canReadItemGeometry(id)) {
        return;
      }
      _installReSpan(
        id,
        rect,
        duration: duration,
        curve: curve,
        neighbour: true,
      );
    });
  }

  /// The install half of [_reSpan], reading the POST-mutation rectangle
  /// through the same two accessors, whose lane reads flush the buckets
  /// the write dirtied.
  void _installReSpan(
    int id,
    _CapturedRect<TKey> captured, {
    Duration? duration,
    Curve? curve,
    bool neighbour = false,
  }) {
    if (!_canReadItemGeometry(id)) {
      return;
    }
    // The lead is the difference of the two NORMALIZED leads, each its
    // content lead minus its pin term, which is the painted difference
    // the render needs: the content difference itself whenever the pin
    // did not change, and the right one when the item entered or left a
    // band between the capture and now. A LENGTH is the same number in
    // every space, so the extent needs no term. BOTH halves of a
    // neighbour's install are suppressed inside a drag commit's report:
    // the preview already moved it and sized it, and the hand-off owns
    // its landing.
    final suppressed = neighbour && _relaneSlidesSuppressed;
    final delta = suppressed
        ? Offset.zero
        : (captured.lead - captured.pinTerm) -
              (_itemLeadOfId(id) - _pinTermOf(id));
    final extentDelta = suppressed
        ? Offset.zero
        : _extentDelta(captured.extent, _itemExtentOfId(id));
    if (delta == Offset.zero && extentDelta == Offset.zero) {
      return;
    }
    final laneTrack = _laneStartTrackOf(id);
    _anim.slide.animateSlideFrom(
      id,
      delta,
      family: BoardAnimationFamily.itemSlide,
      duration: duration,
      curve: curve,
      extentDelta: extentDelta,
      // An item re-laned WITHIN its lane-axis track is a term of that
      // track; one that changed track is not. A neighbour never changed
      // track: the write it is reacting to was another item's.
      relane: neighbour || (laneTrack != null && laneTrack == captured.laneTrack),
    );
  }

  /// Whether an install would be refused anyway, so the capture beside
  /// it is waste. The engine's own rule, read here once.
  bool _installsSlide(Duration? duration) {
    return !_animationStyle.isOff(
      BoardAnimationFamily.itemSlide,
      explicit: duration,
    );
  }

  /// Whether the two geometry reads are legal for [id].
  ///
  /// Their LANED arms index the lane axis unclamped, so an item stranded
  /// past a shrunken lane axis (a legal state the render clamps for on
  /// purpose) would assert. The fractional arms clamp, so an unlaned id
  /// always reads.
  bool _canReadItemGeometry(int id) {
    final axis = _lanes.laneAxis;
    if (axis == null || !_lanes.isLaned(id)) {
      return true;
    }
    final config = axis == Axis.vertical ? _rows : _columns;
    final track = _store.startIndexOf(id, axis);
    return track >= 0 && track < config.axis.trackCount;
  }

  /// [id]'s lane-axis start track, or null when there is no lane axis.
  int? _laneStartTrackOf(int id) {
    final axis = _lanes.laneAxis;
    if (axis == null) {
      return null;
    }
    return _store.startIndexOf(id, axis);
  }

  /// The extent difference with pure floating-point RESIDUE zeroed, per
  /// axis and RELATIVE to the magnitudes compared.
  ///
  /// The fractional arm is a difference of two offsets, each a product
  /// or a prefix sum, so on an axis whose extents are not exactly
  /// representable an equal-width move leaves a residue that scales with
  /// the content offset: an absolute epsilon holds near the origin and
  /// fails far from it, and a residue reaching an install would make
  /// every such move layout-driving. A relative one holds everywhere,
  /// and a genuine extent change of even a millionth of a pixel survives
  /// it.
  Offset _extentDelta(Offset oldExtent, Offset newExtent) {
    return Offset(
      _extentDeltaOn(oldExtent.dx, newExtent.dx),
      _extentDeltaOn(oldExtent.dy, newExtent.dy),
    );
  }

  double _extentDeltaOn(double oldExtent, double newExtent) {
    final delta = oldExtent - newExtent;
    var scale = oldExtent.abs();
    if (newExtent.abs() > scale) {
      scale = newExtent.abs();
    }
    if (scale < 1.0) {
      scale = 1.0;
    }
    return delta.abs() <= precisionErrorTolerance * scale ? 0.0 : delta;
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
      final track = _store.startIndexOf(id, axis);
      return boardAxis.offsetOf(track) +
          _laneOriginOfId(id, laneOfId(id), laneCountOfId(id));
    }
    final start = _store.startTrackOf(id, axis);
    final clamped = start < boardAxis.trackCount.toDouble()
        ? start
        : boardAxis.trackCount.toDouble();
    return boardAxis.offsetOfFraction(clamped);
  }

  /// The item-geometry rule's EXTENT in CONTENT space, both axes: the
  /// mirror of [_itemLeadOfId], arm for arm, and settled for the reason
  /// the lead is.
  Offset _itemExtentOfId(int id) {
    return Offset(
      _itemExtentOn(Axis.horizontal, id),
      _itemExtentOn(Axis.vertical, id),
    );
  }

  double _itemExtentOn(Axis axis, int id) {
    final config = axis == Axis.vertical ? _rows : _columns;
    final boardAxis = config.axis;
    if (_lanes.laneAxis == axis && _lanes.isLaned(id)) {
      // A LANED item on the lane axis takes its lane BAND, not its
      // fractional span: its own slice multiplied by the number of
      // consecutive lanes the resolver gave it. One slice is one lane
      // extent where the axis is content-sized, and the track's extent
      // past the padding divided by the cluster's lane count where it is
      // not. The same two modes [_laneOriginOfId] multiplies by the lane
      // index, and the span enters HERE and never there.
      final span = laneSpanOfId(id);
      if (boardAxis.acceptsMeasurements) {
        return config.laneExtent! * span;
      }
      final track = _store.startIndexOf(id, axis);
      return (boardAxis.extentOf(track) - config.lanePadding).clamp(
            0.0,
            double.infinity,
          ) /
          laneCountOfId(id) *
          span;
    }
    // Both endpoints clamped exactly as the fractional lead arm clamps
    // its start, so an axis swap that strands a span reads total.
    final count = boardAxis.trackCount.toDouble();
    final start = _store.startTrackOf(id, axis);
    final end = _store.endTrackOf(id, axis);
    return boardAxis.offsetOfFraction(end < count ? end : count) -
        boardAxis.offsetOfFraction(start < count ? start : count);
  }

  /// The EXTENT the geometry rule would give [id] under [prospective]
  /// and the dry run's lane assignment, minus the one it gives it now:
  /// what the make-room extent preview holds, for a RESIZE session's own
  /// item and for every dry-run member. A null [prospective] is the
  /// item's own stored span, which is what a neighbour's install passes:
  /// its span is unchanged and only its lane count moves.
  ///
  /// Per axis, and the same two arms the settled read uses. An item
  /// LANED on the lane axis under BOTH spans takes the slice its
  /// prospective lane count gives it minus the slice its stored one
  /// does, both on the stored track, which is the prospective one
  /// whenever this arm runs (a neighbour's span is its own, and a resize
  /// moves one edge while the other pins the track); a span that
  /// crosses between the arms takes each arm's answer on its own side.
  Offset _prospectiveExtentDelta(
    int id,
    BoardSpan? prospective,
    ({int lane, int laneCount, int laneSpan})? assignment,
  ) {
    return Offset(
      _prospectiveExtentOn(Axis.horizontal, id, prospective, assignment),
      _prospectiveExtentOn(Axis.vertical, id, prospective, assignment),
    );
  }

  double _prospectiveExtentOn(
    Axis axis,
    int id,
    BoardSpan? prospective,
    ({int lane, int laneCount, int laneSpan})? assignment,
  ) {
    final config = axis == Axis.vertical ? _rows : _columns;
    final boardAxis = config.axis;
    final isLaneAxis = _lanes.laneAxis == axis;
    final wasLaned = isLaneAxis && _lanes.isLaned(id);
    // The dry run lanes an id exactly when the resolver's own criterion
    // holds for the prospective span, which is what a non-null
    // assignment reports.
    final willBeLaned = isLaneAxis && assignment != null;
    final count = boardAxis.trackCount.toDouble();
    double spanExtent(double start, double end) {
      return boardAxis.offsetOfFraction(end < count ? end : count) -
          boardAxis.offsetOfFraction(start < count ? start : count);
    }

    double lanedExtent(int forLaneCount, int forLaneSpan) {
      if (boardAxis.acceptsMeasurements) {
        return config.laneExtent! * forLaneSpan;
      }
      final track = _store.startIndexOf(id, axis);
      if (track < 0 || track >= boardAxis.trackCount) {
        return 0.0;
      }
      return (boardAxis.extentOf(track) - config.lanePadding).clamp(
            0.0,
            double.infinity,
          ) /
          forLaneCount *
          forLaneSpan;
    }

    // P2: BOTH sides read a span, the stored one and the dry run's. One
    // side alone yields a preview delta that is a pure artifact of the
    // two rules disagreeing, held for the whole hover, and steps the
    // item by that much at the commit.
    final now = wasLaned
        ? lanedExtent(laneCountOfId(id), laneSpanOfId(id))
        : spanExtent(
            _store.startTrackOf(id, axis),
            _store.endTrackOf(id, axis),
          );
    final double next;
    if (willBeLaned) {
      next = lanedExtent(assignment.laneCount, assignment.laneSpan);
    } else if (prospective == null) {
      next = now;
    } else {
      next = spanExtent(
        prospective.startTrackOn(axis),
        prospective.endTrackOn(axis),
      );
    }
    return _extentDeltaOn(next, now);
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
    final track = _store.startIndexOf(id, axis);
    final slice =
        (config.axis.extentOf(track) - padding).clamp(0.0, double.infinity) /
        laneCount;
    return padding + lane * slice;
  }

  /// The settled rectangle of [id], captured for an install after a
  /// write; see [_CapturedRect].
  _CapturedRect<TKey> _captureRect(int id, TKey key) {
    return (
      key: key,
      lead: _itemLeadOfId(id),
      extent: _itemExtentOfId(id),
      pinTerm: _pinTermOf(id),
      laneTrack: _laneStartTrackOf(id),
    );
  }

  /// Per axis, what [id]'s NORMALIZED lead, the one layout positions it
  /// at before reversal, is its content lead minus: the scroll offset
  /// where it scrolls, nothing in a leading frozen band, whose normalized
  /// position is its content offset, and `totalExtent - viewportExtent`
  /// in a trailing one, which is pinned to the viewport's trailing edge.
  /// Read through the port; with none attached nothing paints, and every
  /// term is 0.
  Offset _pinTermOf(int id) {
    return Offset(
      _pinTermOn(Axis.horizontal, id),
      _pinTermOn(Axis.vertical, id),
    );
  }

  double _pinTermOn(Axis axis, int id) {
    final port = _renderPort;
    if (port == null || !port.isLaidOut) {
      return 0.0;
    }
    final vertical = axis == Axis.vertical;
    switch (pinOfId(id, axis)) {
      case BoardPin.leading:
        return 0.0;
      case BoardPin.trailing:
        final config = vertical ? _rows : _columns;
        final viewport = vertical
            ? port.viewportDimension.height
            : port.viewportDimension.width;
        return config.axis.totalExtent - viewport;
      case BoardPin.none:
        final position = vertical
            ? port.verticalPosition
            : port.horizontalPosition;
        return position?.pixels ?? 0.0;
    }
  }

  /// The dry-run lane resolution the make-room gap derives its offsets
  /// from: the dragged item's intervals overridden by [prospective], the
  /// laning predicate applied to it, and nothing written to the model.
  Map<int, ({int lane, int laneCount, int laneSpan})> _dryRunLanes(
    int draggedId,
    BoardSpan prospective,
  ) {
    final laneAxis = _lanes.laneAxis;
    if (laneAxis == null) {
      return const <int, ({int lane, int laneCount, int laneSpan})>{};
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

  /// Whether [key] holds no id: it was retired, or never added. A key
  /// whose exit is still running holds its id.
  bool _isUnregistered(TKey key) {
    return _store.idOf(key) == BoardStore.noId;
  }

  /// Delivers what a batch deferred, dropping the keys retired since they
  /// were collected: the structural set is checked once, before its
  /// dispatch, and each data key just before its own, which therefore
  /// also drops a key a listener this flush has already run retired.
  void _flushBatchNotifications() {
    final structural = _batchStructural;
    final unknown = _batchStructuralUnknown;
    Set<TKey>? affected;
    if (structural) {
      _ensureLanesResolved();
      final drained = _drainLaneChangedKeys();
      if (!unknown) {
        affected = _batchAffected
          ..addAll(drained)
          ..removeWhere(_isUnregistered);
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
      // A structural listener above, or a data listener before this key,
      // may have retired it.
      if (_isUnregistered(key)) {
        continue;
      }
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

  /// A rewrapped, already-measured LazyContentAxis instance arrives
  /// carrying extents measured against the old configuration's lanes and
  /// items; the swap drops them. A fresh instance makes this a no-op.
  ///
  /// Kept when [config] wraps the SAME instance as [old] with the same
  /// lane geometry, the one part of a config the sizing step folds into a
  /// recorded extent (its cluster term): a re-assigned equal config then
  /// leaves the scroll where it was, which a reset cannot, the render's
  /// correction anchoring only on a measured track. Frozen counts and the
  /// alignment reach no recorded extent: a content-sized axis measures
  /// its cells unbounded whatever its alignment, and the fixed axis's
  /// alignment reaches the measuring constraints, whose change the
  /// render's per-cell cache re-measures under.
  void _resetSwappedAxis(BoardAxisConfig old, BoardAxisConfig config) {
    final axis = config.axis;
    if (axis is! LazyContentAxis) {
      return;
    }
    if (identical(axis, old.axis) &&
        config.laneExtent == old.laneExtent &&
        config.lanePadding == old.lanePadding) {
      return;
    }
    axis.resetMeasurements();
  }

  /// Re-derives both axis identities after an axis config was replaced.
  ///
  /// The span index re-files through its `reconfigure`: every item when
  /// the primary axis changed, only the items between the two lattices
  /// when the primary axis's track count changed, and nothing otherwise.
  /// The lane partition, keyed on the lane axis, is rebuilt when that axis
  /// moved, the items re-registered into it.
  void _reconfigureAxes(Axis swapped) {
    _spanIndex.reconfigure(
      primaryAxis: _derivePrimaryAxis(_rows, _columns),
      trackCount: _primaryConfigOf(_rows, _columns).axis.trackCount,
    );
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

  /// The config of the PRIMARY axis [_derivePrimaryAxis] picks.
  static BoardAxisConfig _primaryConfigOf(
    BoardAxisConfig rows,
    BoardAxisConfig columns,
  ) {
    return _derivePrimaryAxis(rows, columns) == Axis.vertical ? rows : columns;
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

  /// Refuses [span] with an `ArgumentError`, in BOTH build modes, when it
  /// breaks one of [BoardSpan]'s constructor rules. Those rules are the
  /// constructor's asserts, stripped in a release build, where a NaN or a
  /// negative extent otherwise reached the index after the key was
  /// registered and stranded it. The list restates the asserts
  /// (`_board_span.dart`), which a const constructor cannot delegate to a
  /// function, with a finite test in front of each fraction.
  ///
  /// It also refuses an integer start or span above
  /// [BoardStore.maxTrackComponent], the largest the store holds, which is
  /// the store's limit rather than one of [BoardSpan]'s rules.
  void _checkSpan(BoardSpan span, String method) {
    for (final axis in Axis.values) {
      final name = axis == Axis.vertical ? "row" : "column";
      final start = span.startOn(axis);
      final fraction = axis == Axis.vertical
          ? span.rowFraction
          : span.colFraction;
      final extent = span.spanOn(axis);
      final extentFraction = axis == Axis.vertical
          ? span.rowSpanFraction
          : span.colSpanFraction;
      String? defect;
      if (start < 0) {
        // assert(rowStart >= 0 && colStart >= 0)
        defect = "a negative $name start";
      } else if (start > BoardStore.maxTrackComponent) {
        defect =
            "a $name start above ${BoardStore.maxTrackComponent}, the largest "
            "the board stores";
      } else if (!fraction.isFinite || fraction < 0.0 || fraction >= 1.0) {
        // assert(rowFraction >= 0.0 && rowFraction < 1.0), and its twin
        defect = "a $name fraction $fraction outside [0, 1)";
      } else if (extent < 0) {
        // assert(rowSpan >= 0 && colSpan >= 0)
        defect = "a negative $name span";
      } else if (extent > BoardStore.maxTrackComponent) {
        defect =
            "a $name span above ${BoardStore.maxTrackComponent}, the largest "
            "the board stores";
      } else if (!extentFraction.isFinite ||
          extentFraction < 0.0 ||
          extentFraction >= 1.0) {
        // assert(rowSpanFraction >= 0.0 && rowSpanFraction < 1.0), twin
        defect = "a $name span fraction $extentFraction outside [0, 1)";
      } else if (!(extent + extentFraction > 0.0)) {
        // assert(rowSpan + rowSpanFraction > 0.0), and its twin
        defect = "no $name extent";
      } else if (!(start + fraction + extent + extentFraction >
          start + fraction)) {
        // The assert that the extent survives at the span's magnitude.
        defect = "a $name extent lost at the span's own magnitude";
      }
      if (defect != null) {
        throw ArgumentError.value(
          span,
          "span",
          "BoardController.$method: $defect",
        );
      }
    }
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
