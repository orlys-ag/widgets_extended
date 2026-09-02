/// Internal: the animation coordinator, the facade over the four source
/// objects (the slide engine also carries dropSettle), and the read
/// interface the render layer binds to.
///
/// The coordinator is the SINGLE writer of the store's entering and
/// exiting bits: the two installers set them, `retireExitNow` sets the
/// exiting bit for a synchronous retire, and `finalizeEnterExit` is the
/// only code that clears either bit or returns an exiting id to the free
/// list.
///
/// Not exported from the module barrel; the reader interface is a public
/// name in the same sense the session classes elsewhere in this package
/// are.
library;

import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '_board_span.dart';
import '_board_store.dart';
import '_item_enter_exit_animator.dart';
import '_item_slide_engine.dart';
import '_make_room_engine.dart';
import '_overlap_lanes.dart';
import '_span_index.dart';
import '_track_resize_animator.dart';
import 'board_animation_style.dart';

/// The narrow read interface the render layer binds to. Read off the
/// controller and never injected separately, so there is exactly one
/// binding to swap.
abstract interface class BoardAnimationReader<TKey> {
  /// Union of the coordinator's LAYOUT-DRIVING sources: trackResize,
  /// itemEnterExit, and a slide record holding an EXTENT delta, which
  /// changes the child's constraints per tick. Excludes a slide's LEAD,
  /// which is paint-only, and makeRoom and a slide's RELANE mark, whose
  /// classification the RENDER decides: their motion moves a track's
  /// extent on a content-sized lane axis and nowhere else, so the render
  /// composes [hasMakeRoomMotion] and [hasRelaneActive] with that
  /// predicate itself rather than reading them here.
  bool get hasLayoutDrivingAnimations;

  /// Union of the PAINT-ONLY sources: a slide's LEAD (which carries
  /// dropSettle glides) composed with the held makeRoom offsets. A
  /// slide's extent is layout-driving and is not here.
  bool get hasActiveOffsets;

  /// Composed paint-only offset for an item, both axes symmetric.
  Offset offsetOfItem(int itemId);

  /// PER-AXIS magnitudes over the active set, independently: for each
  /// id the larger of `|lead|` and `|lead + extent|` per axis, so an
  /// item shrinking from a painted rectangle larger than its structural
  /// one is still obtained while its trailing edge lies past the
  /// structural window. Both are non-negative and neither is a position.
  /// Two numbers, not one, because a single magnitude widening both axes
  /// multiplies the admitted child AREA. Layout records the bounds it
  /// admitted; a tick exceeding either forces layout.
  ({double dx, double dy}) get composedOffsetBound;

  /// Animated extent of a track during a trackResize; the settled extent
  /// otherwise.
  double animatedExtentOf(Axis axis, int track);

  bool get hasActiveTrackResize;

  /// TOTAL over int: false for any id this reader holds no record for,
  /// including an id past the per-id arrays' current length. Never
  /// asserts and never ranges out.
  bool isEnteringItem(int itemId);
  bool isExitingItem(int itemId);

  /// 0 to 1 while entering; from the value the ramp held when the exit
  /// was installed down to 0 while exiting; and exactly 1 for a settled
  /// live item. Layout MULTIPLIES the item's lane-axis extent and its
  /// intrinsic track-sizing contribution by this.
  double enterExitProgressOf(int itemId);

  /// Any held make-room offset or slot is unsnapped with clock below 1.
  /// The render's tick router composes it with the content-sized lane
  /// predicate; the track-sizing latch reads the CONTRIBUTION instead, so
  /// a snapped gap still latches.
  bool get hasMakeRoomMotion;

  /// Bumped by every make-room install, release and per-id clear. The
  /// render lays out when it differs from the value it last laid out
  /// against, which is the only route a SNAPPED slot-only install has.
  int get makeRoomGeneration;

  /// Bumped exactly when a snap arm publishes a non-null
  /// [makeRoomHandOff]: it discarded an offset or a slot that was still
  /// mid-motion. Never by a per-id clear, which is a removal and not a
  /// snap.
  int get makeRoomSnapGeneration;

  /// The hand-off the last make-room snap published: the clock left on
  /// the unsnapped motion it discarded and the curve tail to run it on,
  /// or null when that snap discarded nothing unsnapped. Read by the
  /// render's track-sizing hand-off arm and by the drag layer's commit,
  /// which continue the discarded motion on it.
  MakeRoomHandOff? get makeRoomHandOff;

  /// The held make-room delta ALONE, both axes, zero for no entry.
  /// [offsetOfItem] composes it with slides; the track-sizing term must
  /// not compose non-relane slides, whose leads can be cross-track, and
  /// reads [relaneDeltaOf] for the ones that cannot.
  Offset makeRoomDeltaOf(int itemId);

  /// The prospective lane occupancies on lane-axis track [track].
  /// `value` is in `[0, 1]`.
  Iterable<({int lane, double value})> makeRoomSlotsOn(int track);

  /// The in-flight EXTENT delta for an item, `dx` on the horizontal axis
  /// and `dy` on the vertical, a content-space LENGTH per axis the
  /// painted extent adds to the structural one. Zero for an id with no
  /// record, at one boolean's cost when the engine holds none.
  Offset extentDeltaOf(int itemId);

  /// The lead delta of a RELANE record, zero for every other record and
  /// for no record: an intra-track shift on the lane axis, which is what
  /// lets the track-sizing term add it to its own track's extent.
  Offset relaneDeltaOf(int itemId);

  /// Whether any relane record stands. The render composes it with its
  /// content-sized lane axis predicate, exactly as it composes
  /// [hasMakeRoomMotion].
  bool get hasRelaneActive;
}

/// The facade. Owns the four sources, the bit writes, the settle handler
/// and the animation-listener dispatch.
class BoardAnimationCoordinator<TKey> implements BoardAnimationReader<TKey> {
  BoardAnimationCoordinator({
    required TickerProvider vsync,
    required BoardStore<TKey, Object?> store,
    required SpanIndex spanIndex,
    required OverlapLaneResolver lanes,
    required BoardAnimationStyle Function() styleOf,
    required List<VoidCallback> listeners,
    required void Function(Set<TKey> affected) fireStructural,
    required double Function(Axis axis, int track) settledExtentOf,
    required Axis? Function() laneAxisOf,
    required Map<int, ({int lane, int laneCount})> Function(
      int draggedId,
      BoardSpan prospective,
    )
    dryRunOf,
    required double Function(int id, int lane, int laneCount) laneOriginOfId,
    required int Function(int id) laneOfId,
    required int Function(int id) laneCountOfId,
  }) : _store = store,
       _spanIndex = spanIndex,
       _lanes = lanes,
       _fireStructural = fireStructural,
       _listeners = listeners {
    trackResize = TrackResizeAnimator(
      vsync: vsync,
      styleOf: styleOf,
      settledExtentOf: settledExtentOf,
      onTick: notifyCoalesced,
    );
    enterExit = ItemEnterExitAnimator(
      vsync: vsync,
      styleOf: styleOf,
      isExitingOf: isExitingItem,
      onSettle: finalizeEnterExit,
      onTick: notifyCoalesced,
    );
    slide = ItemSlideEngine(
      vsync: vsync,
      styleOf: styleOf,
      notifyNow: notifyNow,
    );
    makeRoom = MakeRoomEngine(
      vsync: vsync,
      styleOf: styleOf,
      notifyNow: notifyNow,
      laneAxisOf: laneAxisOf,
      dryRunOf: dryRunOf,
      laneOriginOfId: laneOriginOfId,
      laneOfId: laneOfId,
      laneCountOfId: laneCountOfId,
    );
  }

  final BoardStore<TKey, Object?> _store;
  final SpanIndex _spanIndex;
  final OverlapLaneResolver _lanes;
  final void Function(Set<TKey> affected) _fireStructural;

  /// The controller-owned listener list; dispatch machinery lives here so
  /// the coalescing state has one owner.
  final List<VoidCallback> _listeners;

  late final TrackResizeAnimator trackResize;
  late final ItemEnterExitAnimator enterExit;
  late final ItemSlideEngine slide;
  late final MakeRoomEngine makeRoom;

  bool _dispatchScheduled = false;

  // ------------------------------------------------------------ reader

  @override
  bool get hasLayoutDrivingAnimations {
    return trackResize.hasActive ||
        enterExit.hasActive ||
        slide.hasExtentActive;
  }

  @override
  bool get hasActiveOffsets {
    return slide.hasActive || makeRoom.hasActive;
  }

  @override
  Offset offsetOfItem(int itemId) {
    return slide.deltaOf(itemId) + makeRoom.deltaOf(itemId);
  }

  @override
  ({double dx, double dy}) get composedOffsetBound {
    var dx = 0.0;
    var dy = 0.0;
    void fold(int id) {
      final offset = offsetOfItem(id);
      // The item's painted LEADING edge sits `offset` from its
      // structural one and its painted TRAILING edge `offset + extent`,
      // so both edges are inside a window widened by the larger
      // magnitude. One site: this is the number layout widens the obtain
      // window by and records.
      final extent = slide.extentDeltaOf(id);
      final leadX = offset.dx.abs();
      final trailX = (offset.dx + extent.dx).abs();
      final maxX = leadX > trailX ? leadX : trailX;
      if (maxX > dx) {
        dx = maxX;
      }
      final leadY = offset.dy.abs();
      final trailY = (offset.dy + extent.dy).abs();
      final maxY = leadY > trailY ? leadY : trailY;
      if (maxY > dy) {
        dy = maxY;
      }
    }

    slide.activeIds.forEach(fold);
    makeRoom.activeIds.forEach(fold);
    return (dx: dx, dy: dy);
  }

  @override
  double animatedExtentOf(Axis axis, int track) {
    return trackResize.animatedExtentOf(axis, track);
  }

  @override
  bool get hasActiveTrackResize {
    return trackResize.hasActive;
  }

  @override
  bool get hasMakeRoomMotion {
    return makeRoom.hasMotion;
  }

  @override
  int get makeRoomGeneration {
    return makeRoom.generation;
  }

  @override
  int get makeRoomSnapGeneration {
    return makeRoom.snapGeneration;
  }

  @override
  MakeRoomHandOff? get makeRoomHandOff {
    return makeRoom.handOff;
  }

  @override
  Offset makeRoomDeltaOf(int itemId) {
    return makeRoom.deltaOf(itemId);
  }

  @override
  Iterable<({int lane, double value})> makeRoomSlotsOn(int track) {
    return makeRoom.slotsOn(track);
  }

  /// The two per-item slide reads, behind ONE boolean: an idle board
  /// pays that boolean per read and never a map lookup, which matters
  /// because the geometry rule makes two per item child per layout.
  @override
  Offset extentDeltaOf(int itemId) {
    if (!slide.hasActive) {
      return Offset.zero;
    }
    return slide.extentDeltaOf(itemId);
  }

  @override
  Offset relaneDeltaOf(int itemId) {
    if (!slide.hasActive) {
      return Offset.zero;
    }
    return slide.relaneDeltaOf(itemId);
  }

  @override
  bool get hasRelaneActive {
    return slide.hasRelaneActive;
  }

  @override
  bool isEnteringItem(int itemId) {
    if (itemId < 0 || itemId >= _store.capacity) {
      return false;
    }
    return _store.isEntering(itemId);
  }

  @override
  bool isExitingItem(int itemId) {
    if (itemId < 0 || itemId >= _store.capacity) {
      return false;
    }
    return _store.isExiting(itemId);
  }

  @override
  double enterExitProgressOf(int itemId) {
    return enterExit.progressOf(itemId);
  }

  // -------------------------------------------------------- installers

  /// Installs an enter ramp and sets the entering bit, in one site, so
  /// the bit and the record cannot disagree.
  void animateEnter(int id) {
    _store.setFlag(id, BoardStore.enteringBit, true);
    enterExit.animateEnter(id, family: BoardAnimationFamily.itemEnterExit);
  }

  /// Installs an exit ramp from [from] and sets the exiting bit, in one
  /// site. [from] is 1 for a settled item and the captured ramp value for
  /// a mid-enter removal.
  void animateExit(int id, {required double from}) {
    _store.setFlag(id, BoardStore.exitingBit, true);
    enterExit.animateExit(
      id,
      family: BoardAnimationFamily.itemEnterExit,
      from: from,
    );
  }

  /// The one synchronous retire door: sets the exiting bit and finalizes
  /// in the same statement, so the handler sees exactly the state a
  /// settled exit hands it. Setting an already-set bit is idempotent,
  /// which is what lets the re-add door share this path.
  void retireExitNow(int id, {bool deliver = true}) {
    _store.setFlag(id, BoardStore.exitingBit, true);
    finalizeEnterExit(id, deliver: deliver);
  }

  /// The completion handler: the ONLY code that clears the entering or
  /// exiting bit, and the ONLY code that returns an exiting id to the
  /// free list.
  ///
  /// EXIT branch, in order: de-register from both indices (marking the
  /// lane bucket dirty), clear the bit, then on the DELIVERED arm flush,
  /// drain minus the retired key, release, fire; on the DEFERRED arm
  /// ([deliver] false: a mutator entry whose own notification drains
  /// later, or dispose) release first and let the drain's null-key filter
  /// drop the retired id. ENTER branch: clear the bit, drop the record,
  /// stop.
  void finalizeEnterExit(int id, {bool deliver = true}) {
    final exiting = _store.isExiting(id);
    final entering = _store.isEntering(id);
    assert(
      exiting != entering,
      "finalizeEnterExit($id): exiting $exiting, entering $entering. "
      "Exactly one bit must be set; neither means a caller reached the "
      "handler without going through an installer or retireExitNow, and "
      "both is the state the mid-enter removal ordering exists to make "
      "unreachable.",
    );
    if (entering) {
      _store.setFlag(id, BoardStore.enteringBit, false);
      enterExit.clearForId(id);
      return;
    }
    final key = _store.keyOf(id);
    _spanIndex.deregister(id);
    _lanes.deregisterItem(id);
    _store.setFlag(id, BoardStore.exitingBit, false);
    if (deliver) {
      _lanes.ensureResolved();
      final affected = <TKey>{};
      for (final changed in _lanes.drainLaneChangedIds()) {
        final changedKey = _store.keyOf(changed);
        if (changedKey != null) {
          affected.add(changedKey);
        }
      }
      if (key != null) {
        affected.remove(key);
        _store.release(key);
      }
      clearForId(id);
      _fireStructural(affected);
      return;
    }
    if (key != null) {
      _store.release(key);
    }
    clearForId(id);
  }

  /// Resets every per-id animation record. Ids are recycled off a LIFO
  /// free list, so this runs on the release path (from the handler above)
  /// and on the allocation path when the store reports a recycled id;
  /// without both, a recycled id paints a fresh item at a dead one's
  /// residual delta.
  void clearForId(int id) {
    slide.clearForId(id);
    makeRoom.clearForId(id);
    enterExit.clearForId(id);
  }

  // ---------------------------------------------------------- dispatch

  /// Coalesced to one dispatch per frame: inside the transient-callbacks
  /// phase (where every tick runs) the dispatch defers to a microtask, so
  /// several sources ticking in one frame notify once; outside it there
  /// is nothing to coalesce and it dispatches synchronously.
  void notifyCoalesced() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.transientCallbacks) {
      if (_dispatchScheduled) {
        return;
      }
      _dispatchScheduled = true;
      scheduleMicrotask(() {
        if (!_dispatchScheduled) {
          return;
        }
        _dispatchScheduled = false;
        _dispatch();
      });
      return;
    }
    _dispatch();
  }

  /// Uncoalesced dispatch, for the two engines whose settle notify
  /// carries a synchronous ordering contract. It satisfies any pending
  /// coalesced dispatch, whose microtask then no-ops.
  void notifyNow() {
    _dispatchScheduled = false;
    _dispatch();
  }

  void _dispatch() {
    if (_listeners.isEmpty) {
      return;
    }
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// Finalizes every in-flight enter and exit without notifying (the
  /// listener lists are already required empty at dispose), then disposes
  /// the four tickers.
  void dispose() {
    final inFlight = <int>[];
    for (final id in _store.ids) {
      if (_store.isExiting(id) || _store.isEntering(id)) {
        inFlight.add(id);
      }
    }
    for (final id in inFlight) {
      finalizeEnterExit(id, deliver: false);
    }
    trackResize.dispose();
    enterExit.dispose();
    slide.dispose();
    makeRoom.dispose();
  }
}
