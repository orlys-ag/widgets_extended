part of 'board_controller.dart';

/// The controller's INTERNAL surface: the id-keyed reads, the layout
/// reads, the drag and animation channels, the render object's
/// registration and the debug counters that the render object, the
/// widget, the drag controller and the tests drive the board through.
///
/// Not part of the supported surface, and not shown by the barrel
/// (`board.dart`), so an app importing the package does not see these
/// members; code in this package imports `board_controller.dart` itself.
/// A part of that library, so each member reads the controller's private
/// state as it did when it was declared on the class.
extension BoardControllerInternals<TKey, TItem>
    on BoardController<TKey, TItem> {
  // ---------------------------------------------------------------------
  // Render-facing reads, id-keyed.
  //
  // The board's analogue of the tree's `*Nid` variants. They exist because
  // the render object, the views and the drag controller are separate
  // libraries from the store, so no consumer can reach a dense array
  // directly. None of them hashes a key or allocates.
  //
  // They are id-keyed and scalar-returning on purpose: layout touches
  // every obtained item every frame, so a span-returning accessor would
  // allocate one value object per item per frame.
  //
  // There is deliberately no `isExitingId`: the exiting bit's one read API
  // is the animation reader's, and a second one here would be a second
  // normative site for the same fact.
  // ---------------------------------------------------------------------

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

  /// Debug-only: lane-axis bucket member reads, forwarded from the
  /// resolver for the same reason as [debugLaneBucketResolveCount].
  int get debugLaneBucketMemberReadCount {
    return _lanes.debugBucketMemberReadCount;
  }

  set debugLaneBucketMemberReadCount(int value) {
    _lanes.debugBucketMemberReadCount = value;
  }

  /// Whether [id]'s span covers cell `(row, col)` by the span index's own
  /// two rules, so a per-cell listener rebuilds exactly when [itemsAt]
  /// would list the item. Internal-use, like [keyOfId].
  bool idCoversCell(int id, int row, int col) {
    return _spanIndex.coversCell(id, row, col);
  }

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

  /// The enter/exit ramp of [id]'s incarnation as an animation, the one
  /// `BoardItemView.presence` carries.
  Animation<double> presenceOfId(int id) {
    return _anim.presenceOf(id);
  }

  /// The stored INTEGER row start component of [id]: the span's
  /// `rowStart` as written. Not a track index; a start one ulp below a
  /// whole track is in the next track, which [startIndexOfId] answers.
  int rowStartOfId(int id) {
    return _store.rowStartOf(id);
  }

  /// Integer row span of [id]. Track space.
  int rowSpanOfId(int id) {
    return _store.rowSpanOf(id);
  }

  /// The stored INTEGER column start component of [id]; see
  /// [rowStartOfId].
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

  /// [id]'s lane span. Flushes first; see [laneOfId].
  int laneSpanOfId(int id) {
    _ensureLanesResolved();
    return _store.laneSpanOf(id);
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
    return _store.startIndexOf(id, _spanIndex.primaryAxis);
  }

  /// The track [id] STARTS in on [axis], by the one start rule
  /// (`trackIndexOf`). Internal-use: the render's laned geometry and its
  /// lattice test read this and never the integer start component, which
  /// is one track early for a start one ulp below an integer.
  int startIndexOfId(int id, Axis axis) {
    return _store.startIndexOf(id, axis);
  }

  /// The id at [ordinal] on primary start track [track], or
  /// [BoardStore.noId]. The widget's builder resolves an item vicinity
  /// back to its item through this; internal-use in the same sense the
  /// rest of this block is.
  int itemIdAtOrdinal(int track, int ordinal) {
    return _spanIndex.idAtOrdinal(track, ordinal);
  }

  /// Which frozen band [id] is PINNED in on [axis]: the one its span
  /// lies wholly inside there, or [BoardPin.none]. Internal-use, and the
  /// ONE site of the rule: the render object positions a pinned item with
  /// its band, the FLIP install corrects a lead for a pin that changed,
  /// and a drag measures the item's anchor in the lattice it pins in.
  ///
  /// A LANED item on the lane axis occupies its whole lane-axis track, so
  /// that track decides; any other item's exact interval does. This
  /// chooses the interval, and [bandHolding], the one site of the
  /// interval test, says which band holds it, within the tolerance, so a
  /// span that meets a band's edge and one that crosses it are told
  /// apart. A span stranded past a shrunken lattice is in no band.
  BoardPin pinOfId(int id, Axis axis) {
    final config = axis == Axis.vertical ? _rows : _columns;
    final count = config.axis.trackCount;
    final lead = config.leadingBandEnd;
    final trailFrom = config.trailingBandStart;
    if (lead == 0 && trailFrom >= count) {
      return BoardPin.none;
    }
    final double start;
    final double end;
    if (_lanes.laneAxis == axis && _lanes.isLaned(id)) {
      start = _store.startIndexOf(id, axis).toDouble();
      end = start + 1.0;
    } else {
      start = _store.startTrackOf(id, axis);
      end = _store.endTrackOf(id, axis);
    }
    final band = bandHolding(
      start,
      end,
      leadingBandEnd: lead,
      trailingBandStart: trailFrom,
      trackCount: count,
    );
    if (band == null) {
      return BoardPin.none;
    }
    // The leading band starts below `lead` and the trailing one at or
    // above it; comparing the start with 0 would read a trailing band
    // that covers the whole axis as leading.
    return band.start < lead ? BoardPin.leading : BoardPin.trailing;
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
  /// inside the single integer track [track], its start placed by the
  /// start rule ([trackIndexOf]) and its end padded by the tolerance. The
  /// render object's content-axis sizing assert reads it; nothing on a
  /// release path does.
  bool debugHasIntraTrackItemOn(int track) {
    var found = false;
    assert(() {
      found = _spanIndex.hasIntraTrackItemOn(track);
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
  /// while an off family under the live style dominates them. [relane]
  /// declares the correction an intra-track shift, which a committed
  /// RESIZE's is (it corrects onto the de-lane hold) and a committed
  /// move's is not (it runs from the proxy).
  void animateDropSettle(
    TKey key,
    Offset delta, {
    required Duration duration,
    required Curve curve,
    Offset extentDelta = Offset.zero,
    bool relane = false,
  }) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "animateDropSettle");
    _anim.slide.animateSlideFrom(
      id,
      delta,
      family: BoardAnimationFamily.dropSettle,
      duration: duration,
      curve: curve,
      extentDelta: extentDelta,
      relane: relane,
    );
  }

  /// Internal-use channel for the drag layer; not part of the supported
  /// surface. Runs [body] with BOTH halves of every neighbour relane
  /// install suppressed, lead and extent, in every door: inside a
  /// commit's report the preview has already moved those neighbours and
  /// sized them to their prospective slices, and the make-room hand-off
  /// owns their landing, so a second lead or a second extent would fight
  /// it. The written item's own FLIP is not suppressed; the drop-settle
  /// glide's continuation cancels it from painted truth.
  ///
  /// Restores the PRIOR value rather than false, so a nested call and a
  /// throwing body both leave the flag as they found it. A mutation an
  /// app makes inside its report beyond the reported span, re-laning or
  /// resizing a neighbour the preview never held, steps that neighbour;
  /// accepted.
  T withoutRelaneSlides<T>(T Function() body) {
    _assertNotDisposed();
    final saved = _relaneSlidesSuppressed;
    _relaneSlidesSuppressed = true;
    try {
      return body();
    } finally {
      _relaneSlidesSuppressed = saved;
    }
  }

  /// Internal-use channel for the render object; not part of the
  /// supported surface. The one route from the track-sizing step of
  /// layout to the resize animator, which lives in a library the render
  /// object cannot name: a resize of [track] from the painted extent
  /// [from] to the settled extent the axis already stores, which the
  /// caller records first. Forwards and decides nothing: [family],
  /// [duration] and [curve] are the sizing step's, and the hand-off arm
  /// is the one caller that passes them.
  void animateTrackResize(
    Axis axis,
    int track,
    double from, {
    BoardAnimationFamily family = BoardAnimationFamily.trackResize,
    Duration? duration,
    Curve? curve,
  }) {
    _anim.trackResize.animateTrackResize(
      axis,
      track,
      from,
      family: family,
      duration: duration,
      curve: curve,
    );
  }

  /// Internal-use channel for the drag layer; not part of the supported
  /// surface. The COMMIT HAND-OFF's continuation for one displaced
  /// neighbour: a slide starting [delta] from the item's structural
  /// position, which the drag layer computes as where the item painted
  /// before the snap minus where it rests after the report's mutation,
  /// riding the slide engine under the makeRoom family with the snap's
  /// remaining [duration] and curve tail. [extentDelta] is the same
  /// continuation for the item's EXTENT, the painted size before the snap
  /// minus the size it rests at after the mutation, so a neighbour whose
  /// slice the preview held finishes shrinking or widening on the same
  /// clock. Composes onto any slide the mutation installed, so the item
  /// never leaves its painted rectangle.
  void animateMakeRoomHandOff(
    TKey key,
    Offset delta, {
    required Duration duration,
    required Curve curve,
    Offset extentDelta = Offset.zero,
  }) {
    _assertNotDisposed();
    final id = _liveIdOrThrow(key, "animateMakeRoomHandOff");
    _anim.slide.animateSlideFrom(
      id,
      delta,
      family: BoardAnimationFamily.makeRoom,
      duration: duration,
      curve: curve,
      extentDelta: extentDelta,
      // Intra-track by the snap's own premise: the mutation reassigned
      // the displaced neighbours' structure by exactly the amounts the
      // preview held them at, so this correction moves each within its
      // own lane-axis track and the track's term may read it.
      relane: true,
    );
  }

  /// Internal-use channel for the drag layer; not part of the supported
  /// surface. The keys holding a make-room offset OR extent this instant,
  /// for the commit's painted-truth capture before the snap.
  List<TKey> get makeRoomHeldKeys {
    _assertNotDisposed();
    final keys = <TKey>[];
    for (final id in _anim.makeRoom.activeIds) {
      final key = keyOfId(id);
      if (key != null) {
        keys.add(key);
      }
    }
    return keys;
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

  /// Internal-use channel for the render object; not part of the
  /// supported surface. Drops the resize animator's shift prefix, which
  /// captures SETTLED extents and so cannot survive a write to one.
  ///
  /// Every other invalidation the prefix needs rides a state mutation or
  /// a restyle, which the animator sees for itself; a settled write is
  /// the one event that reaches the axis and not the animator, and
  /// layout's `recordMeasurement` is its only site. Forwards and decides
  /// nothing.
  void invalidateAnimatedShifts() {
    _anim.trackResize.invalidateShiftCache();
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

  /// The narrow read interface the render layer binds to. Read off the
  /// controller and never injected separately, so there is exactly one
  /// binding to swap on a controller swap.
  BoardAnimationReader<TKey> get anim {
    return _anim;
  }
}
