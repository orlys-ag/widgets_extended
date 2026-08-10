/// Orchestrates drag-and-drop reorder over a [TreeController]-backed
/// [SliverTree]: gesture lifecycle, drop-target resolution, autoscroll near
/// viewport edges, and FLIP slide animation on commit.
///
/// The controller holds no PER-FRAME state outside an active drag (the
/// monotonic [TreeReorderController.dragGeneration] survives idleness by
/// design). A drag session begins with [startDrag], receives
/// pointer updates via [updateDrag], and ends with [endDrag] (commit) or
/// [cancelDrag] (no-op). Only one session can be active at a time.
///
/// This file owns the PUBLIC API, policy (`canReorder`/`canAcceptDrop`,
/// autoscroll/dwell tuning), the notification channels, and the
/// COMMIT SCRIPT. Animation timing is NOT owned here: the drag
/// animations read the tree controller's `animationStyle`
/// (`reorderSlide` for the commit FLIP, `effectiveMakeRoom` for the
/// gap, `effectiveDropSettle` for the proxy glides), resolved once per
/// session at `startDrag`. Everything else is delegated to the session
/// architecture:
///
/// - `DragSession` (`_drag_session.dart`) — per-drag state; the single
///   `resolve()` choreography site and the single `detachAll(SessionExit)`
///   teardown site.
/// - `PointerSpace` — the ONLY component touching the scrollable; every
///   read is nullable (null = defunct scrollable) and every pointer event
///   costs exactly one viewport lookup.
/// - `DragProbe` — grab geometry + the touch-first probe shift + the
///   resolution core over [DropZoneResolver] (`_drop_zone_resolver.dart`).
/// - Behavior collaborators (`_drag_session_behaviors.dart`) —
///   `AutoScroller` (per-session ticker), `DwellExpander`,
///   `MakeRoomDriver`, `DropSettler`.
///
/// Render-layer access goes exclusively through [ReorderRenderPort] — this
/// package never lets reorder code touch the concrete render object.
/// Coordinate space is exclusively **sliver-local scroll-space** (distance
/// from the start of the sliver's scroll extent, matching
/// [SliverTreeParentData.layoutOffset]).
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '_drag_session.dart';
import '_drag_session_behaviors.dart';
import '_drop_zone_resolver.dart';
import 'reorder_render_port.dart';
import 'tree_controller.dart';

export '_drop_zone_resolver.dart' show TreeDropTarget, TreeDropZone;

/// Controls a drag-and-drop reorder over a [TreeController].
///
/// Not usable with a comparator-based controller (auto-sort would
/// override user order) — the constructor throws [ArgumentError] in that
/// case.
///
/// Extends [ChangeNotifier]: listeners are notified whenever
/// [currentTarget] changes or the drag session begins/ends. Consumers
/// that need to repaint per-pointer-move subscribe here instead of
/// polling per-frame; the per-move [pointerPosition] channel exists for
/// those that must follow the pointer itself.
class TreeReorderController<TKey> extends ChangeNotifier {
  TreeReorderController({
    required this.treeController,
    required TickerProvider vsync,
    this.canReorder,
    this.canAcceptDrop,
    this.onReorder,
    this.autoScrollEdgeZone = 48.0,
    this.autoScrollMaxVelocity = 1200.0,
    this.autoExpandDelay = const Duration(milliseconds: 700),
  }) {
    // Runtime check in all build modes — asserts disappear in release.
    // hasComparator, not comparator: reading the comparator getter through
    // this class's covariant `TreeController<TKey, Object?>` view throws a
    // TypeError (TData appears contravariantly in its function type).
    if (treeController.hasComparator) {
      throw ArgumentError.value(
        treeController,
        "treeController",
        "TreeReorderController is incompatible with a comparator-based "
            "TreeController: comparator auto-sort would override drag order. "
            "Pass a controller with comparator: null, or remove the comparator.",
      );
    }
    _vsync = vsync;
  }

  /// The tree controller to mutate on drop.
  ///
  /// Typed on the key only — reorder orchestration never reads node data,
  /// so any `TreeController<TKey, *>` is accepted.
  final TreeController<TKey, Object?> treeController;

  /// If set, rows for which this returns false cannot be dragged.
  final bool Function(TKey key)? canReorder;

  /// If set, rejected drop targets are filtered out. Receives the dragged
  /// key, the candidate new parent, and the final-list index.
  final bool Function({required TKey movingKey, TKey? newParent, int? index})?
  canAcceptDrop;

  /// Reports every committed reorder, whatever initiated it: a pointer
  /// drop, [moveTo], or one of the four semantic moves.
  ///
  /// `index` follows the package's live-space FINAL-list convention: the
  /// position among the destination's live children AFTER `key` has been
  /// removed from wherever it was. A same-parent downward move therefore
  /// reports one less than a caller computing against the pre-removal
  /// list would expect.
  ///
  /// Fires exactly once per commit, and never for a refused or no-op
  /// move. On the drag path it fires after the session has been torn
  /// down and before the session-end notification, so a synchronous
  /// `setState` here cannot land mid-commit.
  ///
  /// This is the only way to observe a reorder that did not come from a
  /// pointer. Assistive technology drives the semantic moves directly,
  /// and without this a consumer holding authoritative data would never
  /// hear about them.
  final void Function(TKey key, TKey? newParent, int index)? onReorder;

  /// Height in pixels from each viewport edge within which the pointer
  /// triggers autoscroll. Velocity ramps linearly from 0 at the zone's
  /// inner edge to [autoScrollMaxVelocity] at the viewport edge.
  ///
  /// Mutable at runtime. Captured once per drag session at [startDrag]
  /// (the same per-session policy as the animation style), so a change
  /// never retunes a live drag; the next drag picks it up.
  double autoScrollEdgeZone;

  /// Peak autoscroll velocity in logical pixels per second.
  ///
  /// Mutable at runtime; captured per drag session, see
  /// [autoScrollEdgeZone].
  double autoScrollMaxVelocity;

  /// How long the pointer must dwell on an `into` target that is
  /// collapsed (and has live children to reveal) before the target
  /// auto-expands, the conventional hover-to-open tree affordance.
  ///
  /// `null` or [Duration.zero] disables auto-expand. The dwell re-arms
  /// on every target change and is cancelled by session end.
  ///
  /// Mutable at runtime; captured per drag session, see
  /// [autoScrollEdgeZone].
  Duration? autoExpandDelay;

  /// Zone semantics, shared with commit-time re-validation. Late so it can
  /// capture the final [treeController]/[canAcceptDrop] fields.
  late final DropZoneResolver<TKey> _resolver = DropZoneResolver<TKey>(
    treeController: treeController,
    canAcceptDrop: canAcceptDrop,
  );

  DragSession<TKey>? _session;

  /// Vsync for the per-session autoscroll ticker; the ticker itself lives
  /// in each session's [AutoScroller].
  late final TickerProvider _vsync;

  /// Whether a drag is currently in flight.
  bool get isDragging => _session != null;

  /// Monotonically increasing identity for drag sessions.
  ///
  /// Starts at 0 and increments by exactly one each time [startDrag]
  /// INSTALLS a session, before that call's session-start notification.
  /// Never decreases and never repeats, so it answers "is this still the
  /// drag that was in flight when I scheduled this?", which [isDragging]
  /// and [draggedKey] cannot: the same node dragged twice is
  /// indistinguishable through them.
  ///
  /// Deferred work captures the value and re-reads it later; a mismatch
  /// means the callback has been outlived by its session. That single
  /// compare covers a replacement session ([startDrag] cancels a live one
  /// first, so a listener sees `isDragging` go false then true inside one
  /// call), a start that BAILS after that cancel (which notifies false
  /// with no matching true, and consumes no generation), and callbacks
  /// arriving after a later session has both begun and ended.
  ///
  /// Not incremented by [endDrag], [cancelDrag] or [dispose]: it
  /// identifies the session, not its transitions.
  int get dragGeneration => _dragGeneration;
  int _dragGeneration = 0;

  /// The currently-dragged key, or `null` if no drag is active.
  TKey? get draggedKey => _session?.draggedKey;

  /// The current drop target, or `null` if the pointer is outside any row
  /// or every candidate slot is a cycle.
  ///
  /// A target whose slot equals the dragged row's current position IS
  /// valid: the "returns here" feedback shows the gap at the original
  /// slot instead of going dark. [endDrag] detects it and commits
  /// nothing, behaving like [cancelDrag].
  TreeDropTarget<TKey>? get currentTarget => _session?.currentTarget;

  /// The render port of the active drag session, or `null` when idle.
  ///
  /// For presentation-layer consumers: the semantic [TreeDropTarget]
  /// carries sliver-local geometry, and converting it to viewport scroll
  /// space needs [ReorderRenderPort.precedingScrollExtent].
  ReorderRenderPort<TKey>? get renderPort => _session?.renderPort;

  /// Per-pointer-move channel: the latest global pointer position, `null`
  /// when idle. A drag proxy must reposition on EVERY move, whereas the
  /// [ChangeNotifier] channel deliberately coalesces to semantic target
  /// changes — two channels, two contracts.
  ValueListenable<Offset?> get pointerPosition => _pointerPosition;
  final ValueNotifier<Offset?> _pointerPosition = ValueNotifier<Offset?>(null);

  /// The active session's grab geometry: the pointer's dy within the
  /// dragged row at start, and that row's extent. `null` when idle.
  /// Presentation consumers position the proxy at `pointer − grabDy`.
  ({double grabDy, double rowExtent})? get dragProxyGeometry {
    final session = _session;
    if (session == null) {
      return null;
    }
    return (
      grabDy: session.probe.grabDy,
      rowExtent: session.probe.grabRowExtent,
    );
  }

  /// Begins a drag session for [key].
  ///
  /// [renderPort] is the render surface currently displaying
  /// [treeController] (the `RenderSliverTree`). [scrollable] is the
  /// ancestor scrollable whose viewport clips the tree — used for
  /// pointer → scroll-space conversion and autoscroll.
  ///
  /// Returns `true` when the session started. Returns `false` — starting
  /// nothing — when [canReorder] refuses [key], or when [renderPort] has
  /// not been laid out yet (no painted rows to resolve against). A policy
  /// refusal is a normal runtime answer, not misuse, so it is a return
  /// value rather than an exception.
  ///
  /// [depthForPointerX] maps the pointer's sliver-local x to an UNCLAMPED
  /// preferred depth (e.g. `x ~/ indentWidth` — the widget layer owns
  /// the pixel constant); the resolver clamps it to the legal candidate
  /// chain when a below-zone drop sits at a subtree right-boundary. Omit
  /// it to always resolve at the deepest legal level.
  ///
  /// [proxyCrossOffset] reports the floating drag proxy's VISUAL cross
  /// offset, in sliver cross space, sampled at settle-glide install time
  /// (release, cancel, or the dead-commit fallback) so the proxy-to-row
  /// handoff starts exactly where the card visually is, even when
  /// released mid-animation. Presentation-supplied, following the
  /// [depthForPointerX] precedent. Omit it (imperative drags with no
  /// proxy) and the glides carry no x motion while the commit baseline
  /// preserves the captured x — the classic y-only handoff. Only
  /// consulted when [settleFromRelease] builds a settler.
  ///
  /// When [makeRoom] AND [settleFromRelease] are BOTH set (touch-first
  /// make-room mode), slot resolution probes at the PROXY MIDPOINT
  /// (`pointer + rowExtent/2 − grabDy`, a session constant) instead of
  /// the raw pointer: on touch there is no visible cursor, so selection
  /// tracks the card in hand regardless of where it was grabbed. Every
  /// other configuration resolves at the raw pointer.
  ///
  /// Throws [ArgumentError] for genuine wiring misuse: [renderPort] not
  /// driven by [treeController] (cross-controller drag is out of scope).
  bool startDrag({
    required TKey key,
    required ReorderRenderPort<TKey> renderPort,
    required ScrollableState scrollable,
    required Offset pointerGlobal,
    int Function(double sliverLocalX)? depthForPointerX,
    double Function()? proxyCrossOffset,
    bool makeRoom = false,
    bool settleFromRelease = false,
  }) {
    if (!renderPort.drivesController(treeController)) {
      throw ArgumentError.value(
        renderPort,
        "renderPort",
        "renderPort must be driven by the same TreeController passed to "
            "TreeReorderController. Cross-controller drag is not supported.",
      );
    }
    if (!renderPort.isLaidOut) {
      return false;
    }
    if (canReorder != null && !canReorder!(key)) {
      return false;
    }
    if (_session != null) {
      cancelDrag();
    }
    final pointerSpace = PointerSpace<TKey>(
      scrollable: scrollable,
      renderPort: renderPort,
    );
    final startSample = pointerSpace.sample(pointerGlobal);
    if (startSample == null) {
      // The scrollable is unmounted or its viewport is detached — there
      // is nothing to drag within, so refuse like any other policy check.
      return false;
    }
    // The probe is the single owner of grab geometry + probeDy; capture
    // runs once here against the start sample.
    final probe = DragProbe<TKey>(
      renderPort: renderPort,
      resolver: _resolver,
      draggedKey: key,
      depthForPointerX: depthForPointerX,
    );
    probe.captureGrab(
      start: startSample,
      midpointProbe: makeRoom && settleFromRelease,
    );
    // Per-session animation resolution: the tree controller's style is
    // read ONCE here — a mid-drag restyle never retimes a live session;
    // the next drag picks it up.
    final style = treeController.animationStyle;
    final session = DragSession<TKey>(
      draggedKey: key,
      renderPort: renderPort,
      pointerSpace: pointerSpace,
      probe: probe,
      pointerGlobal: pointerGlobal,
      commitSlideSpec: style.reorderSlide,
    );
    // Behavior collaborators capture the session's identity in their
    // callbacks, hence assignment after construction.
    session.autoScroller = AutoScroller<TKey>(
      vsync: _vsync,
      space: pointerSpace,
      pointerGlobal: () => session.pointerGlobal,
      edgeZone: autoScrollEdgeZone,
      maxVelocity: autoScrollMaxVelocity,
    );
    session.dwell = DwellExpander<TKey>(
      treeController: treeController,
      delay: autoExpandDelay,
      sessionLive: () => identical(_session, session),
      requestResolve: () => _resolveAndNotify(session),
    );
    if (makeRoom) {
      session.makeRoomDriver = MakeRoomDriver<TKey>(
        treeController: treeController,
        draggedKey: key,
        duration: style.effectiveMakeRoom.duration,
        curve: style.effectiveMakeRoom.curve,
      );
    }
    if (settleFromRelease) {
      session.settler = DropSettler<TKey>(
        treeController: treeController,
        space: pointerSpace,
        pointerGlobal: () => session.pointerGlobal,
        grabDy: () => probe.grabDy,
        draggedKey: key,
        duration: style.effectiveDropSettle.duration,
        curve: style.effectiveDropSettle.curve,
        proxyCrossOffset: proxyCrossOffset,
      );
    }
    _dragGeneration++;
    _session = session;
    // Pin the dragged row against stale eviction for the session's
    // lifetime: the drag gesture's recognizer lives on the row's own
    // `State`, so autoscrolling it out of the cache region would otherwise
    // evict the row, its `Drag`'s end/cancel would never fire, and the
    // session (plus the autoscroll ticker) would run forever.
    renderPort.pinNode(key);
    session.subscribeScroll(scrollable.position, _onScrollPositionChanged);
    _pointerPosition.value = pointerGlobal;
    // One choreography site: probe + resolver + every behavior — the
    // make-room gap of a session born over a valid slot opens here, and
    // the edge-zone-at-start autoscroll evaluation runs here too.
    session.resolve();
    // Drag session just started; currentTarget may have become non-null.
    notifyListeners();
    return true;
  }

  /// Scroll listener, subscribed only while a session is active: content
  /// moved under the (possibly stationary) pointer, so the resolved
  /// target may have changed even though no pointer event fired.
  void _onScrollPositionChanged() {
    final session = _session;
    if (session == null) {
      return;
    }
    _resolveAndNotify(session);
  }

  /// Re-resolves through [DragSession.resolve] and fires the coalesced
  /// [ChangeNotifier] channel iff the semantic target changed, AND
  /// enforces [canReorder] for the life of the drag.
  ///
  /// Policy enforcement lives here rather than in `updateDrag`, which is
  /// where it was first written and where it did nothing. `updateDrag`
  /// only fires on pointer events, and the case that needs enforcing is a
  /// drag whose row has autoscrolled out of the cache region: the row is
  /// held mounted by the drag pin but never rebuilt, so the widget
  /// layer's build-time and deactivate backstops are both mute, and a
  /// finger parked in the autoscroll edge zone produces no pointer events
  /// at all. Measured, that placement ran zero times in sixty frames of
  /// exactly that scenario. Every re-resolution trigger funnels through
  /// HERE instead: pointer moves, scroll notifications (which is what
  /// autoscroll produces), and the dwell timer.
  ///
  /// Edge-triggered, not polled: an idle drag with no movement and no
  /// scrolling costs nothing.
  ///
  /// Deliberately synchronous. Unlike the widget layer's backstop, which
  /// must defer because `build` and `deactivate` run in
  /// `persistentCallbacks`, every phase reaching this method is idle or
  /// `transientCallbacks`. `ScrollPosition.setPixels` asserts it never
  /// notifies during `persistentCallbacks`, and the layout-driven
  /// correction path does not notify at all.
  ///
  /// RESIDUAL, worth knowing: a pointer parked OUTSIDE the autoscroll
  /// edge zone with the row off-screen re-resolves nothing, so a refusal
  /// there is not noticed until the next pointer event or the lift. The
  /// consequences are cosmetic (the gap, pin and proxy stay up); the drop
  /// itself is still refused by `_canCommit`. Closing it would need a
  /// per-frame poll or a listenable policy, both worse than the symptom.
  void _resolveAndNotify(DragSession<TKey> session) {
    // Stale on ENTRY: `updateDrag` publishes the `pointerPosition`
    // channel, which is app code, before calling this.
    if (!identical(_session, session)) {
      return;
    }

    if (canReorder != null && !canReorder!(session.draggedKey)) {
      // The policy is app code too, and may have ended this session or
      // started another. A verdict about THIS session must never cancel
      // a different one.
      if (identical(_session, session)) {
        cancelDrag();
      }
      return;
    }
    if (!identical(_session, session)) {
      return;
    }
    final previous = session.currentTarget;
    session.resolve();
    if (!_targetsEqual(previous, session.currentTarget)) {
      notifyListeners();
    }
  }

  /// Updates the pointer position. Re-resolves the drop target and starts
  /// / stops the autoscroll ticker as needed.
  void updateDrag(Offset pointerGlobal) {
    final session = _session;
    if (session == null) {
      return;
    }
    session.pointerGlobal = pointerGlobal;
    _pointerPosition.value = pointerGlobal;
    _resolveAndNotify(session);
  }

  /// Commits the drop: mutates [treeController] (via [TreeController.moveNode],
  /// [TreeController.reorderChildren], or [TreeController.reorderRoots]) and
  /// starts the FLIP slide animation to interpolate old → new positions.
  ///
  /// If no valid target is currently resolved, behaves like [cancelDrag].
  ///
  /// The slide is installed IN-FRAME by the sliver render object: this
  /// method asks the render port to capture a baseline of current painted
  /// offsets BEFORE mutating the controller; the next `performLayout`
  /// (triggered by that mutation) snapshots the post-mutation offsets and
  /// installs a FLIP slide from baseline → current. The paint pass of the
  /// same frame then renders rows at their prior painted position and
  /// slides them toward their new structural position smoothly — no
  /// one-frame "jump to new position, then slide back" flicker.
  void endDrag() {
    final session = _session;
    if (session == null) {
      return;
    }

    // Re-resolve against CURRENT tree state, then validate, BEFORE staging
    // the FLIP baseline. The last pointer-move's target may be stale: with
    // server-driven updates the dragged node or the target parent can have
    // become pending-deletion (or been purged) since. Committing a stale
    // target would throw out of a gesture callback with the session
    // permanently stuck, and a baseline staged before validation
    // would be consumed by nobody — first-wins staging then blocks every
    // subsequent slide stage until an unrelated layout flushes it.
    session.resolveTargetOnly();
    final target = session.currentTarget;
    final dragged = session.draggedKey;
    if (target == null) {
      cancelDrag();
      return;
    }
    final commitAllowed = _canCommit(dragged, target.parentKey);
    // `_canCommit` runs `canReorder`, which is app code. If it tore this
    // session down, everything below (baseline staging, the make-room
    // snap, `_applyMove`, and `detachAll` in the `finally`) would run
    // against a session that no longer exists: a second `detachAll`
    // double-disposes the autoscroll ticker and throws out of the
    // `finally`, which skips `_fireOnReorder` entirely. The tree gets
    // mutated and the app is never told.
    if (!identical(_session, session)) {
      return;
    }
    if (!commitAllowed) {
      cancelDrag();
      return;
    }

    // Current-position drop: the resolver now reports the dragged row's
    // own slot as a valid target ("returns here" feedback), but committing
    // it must mutate NOTHING — and must stage NO baseline (an unconsumed
    // baseline is exactly the protocol violation the expiry backstop
    // guards against). cancelDrag is the precise semantic: settle-back
    // glide, make-room release, clean teardown.
    // Compare the RESOLVED index, the way `moveTo` does. The resolver
    // never emits an out-of-range one today, so this is equivalence
    // rather than a fix; it stops the guard drifting from `_applyMove`'s
    // clamp for whatever calls this next.
    if (treeController.getParent(dragged) == target.parentKey &&
        target.indexInFinalList.clamp(
              0,
              (target.parentKey == null
                      ? treeController.liveRootCount
                      : treeController.liveChildCount(
                          target.parentKey as TKey,
                        )) -
                  1,
            ) ==
            treeController.getIndexInParent(dragged)) {
      cancelDrag();
      return;
    }

    // The autoscroll ticker stops in detachAll(commit) below; endDrag is
    // synchronous, so no tick can interleave before then.

    // Dead-commit-slide settle fallback: when the commit FLIP cannot run
    // (its reorderSlide family is zeroed — captured or live) but the
    // drop-settle family is live and a proxy settler exists, the handoff
    // glide is installed DIRECTLY after the mutation instead of riding a
    // baseline override. The baseline MUST NOT be staged in this mode
    // (and the mutation must not self-stage): a dead baseline's consume
    // runs the slide engine's disabled clear-all and would wipe the
    // just-installed glide one frame later.
    final style = treeController.animationStyle;
    final useSettleFallback =
        (session.commitSlideSpec.duration == Duration.zero ||
            style.reorderSlide.duration == Duration.zero) &&
        session.settler != null &&
        style.effectiveDropSettle.duration != Duration.zero;

    // Stage the FLIP baseline BEFORE mutating. The render object's next
    // performLayout consumes it and installs the slide in-frame, avoiding
    // the post-frame gap that would flicker each moved row at its
    // destination for one frame.
    //
    // Proxy drop-settle: overriding the dragged row's baseline entry to
    // the RELEASE position (pointer − grab offset — exactly where the
    // floating proxy is at this instant) carries the row from the user's
    // hand into its new slot, instead of replaying the old-slot →
    // new-slot reparent slide underneath the vanishing proxy.
    if (!useSettleFallback) {
      session.renderPort.beginSlideBaseline(
        duration: session.commitSlideSpec.duration,
        curve: session.commitSlideSpec.curve,
        // Proxy drop-settle: the dragged row's FLIP starts at the release
        // position (null when no settler, or scrollable gone → classic
        // old-slot FLIP). The override's x is the proxy's visual cross
        // offset, or null (preserve the captured x) when the session has
        // no proxy cross-offset source.
        baselineOverrides: session.settler?.baselineOverrides(),
      );
    }

    // Make-room handoff: the baseline above captured the SHIFTED painted
    // positions (preview offsets ride the composed slide-delta read).
    // Snap the preview away now, BEFORE the mutation — the consume-time
    // snapshot then reads clean post-mutation structural positions, and
    // rows already previewing at their destination get ~zero FLIP deltas
    // (no jump, no double animation). This ordering is why the snap is a
    // named commit-script op rather than part of teardown.
    session.makeRoomDriver?.snapForCommit();

    ({TKey key, TKey? newParent, int index})? committed;
    try {
      // Same-parent drops keep the structural commit a SNAP: the
      // reorderable widget owns the drop animation, so animating here
      // would double-animate the row. Cross-parent keeps moveNode's own
      // baseline self-staging except in the settle fallback, where it
      // carries the same dead-consume hazard as the skipped staging
      // above (on the normal path it is first-wins-shadowed by it).
      final sameParent = treeController.getParent(dragged) == target.parentKey;
      committed = _applyMove(
        dragged,
        target.parentKey,
        target.indexInFinalList,
        animate: sameParent ? false : !useSettleFallback,
      );
      if (useSettleFallback) {
        // No pending-baseline guard needed since the disabled-mode
        // split: a foreign same-frame baseline's consume RE-BASES the
        // glide instead of clearing it (zero-family installs create no
        // motion but never destroy other families' motion). The
        // fallback e2e pins (glide install / frame survival) police
        // this script's own no-staging rule.
        session.settler?.glideIntoCommittedSlot();
      }
    } finally {
      // The re-resolve + validation above makes the commit's throwing
      // paths unreachable, so an exception here is a genuine invariant
      // violation — let it propagate, but never leave the session stuck.
      session.detachAll(SessionExit.commit);
      _pointerPosition.value = null;
      _session = null;
      // Report AFTER teardown, so a synchronous setState in the handler
      // cannot land mid-commit and a throwing handler cannot leave a
      // session stuck, and BEFORE the session-end notification, which
      // this must not suppress. A throwing MUTATION leaves `committed`
      // null and fires nothing, which is correct: no commit happened.
      try {
        if (committed != null) {
          _fireOnReorder(committed);
        }
      } finally {
        notifyListeners();
      }
    }
  }

  /// Whether [key] may legally become a child of [newParent], ignoring
  /// position. Shared by the drag commit script and [moveTo] so the two
  /// cannot drift: [canReorder], existence, pending-deletion on both
  /// ends, self-parent, and the cycle check.
  ///
  /// [canReorder] belongs here rather than only at `startDrag`, because
  /// [moveTo] is a second way in. Without it a programmatic or
  /// assistive-technology move could reposition a row the policy says is
  /// immovable, and the only gate would be presentation.
  bool _canCommit(TKey key, TKey? newParent) {
    if (canReorder != null && !canReorder!(key)) {
      return false;
    }
    if (treeController.getNodeData(key) == null ||
        treeController.isPendingDeletion(key)) {
      return false;
    }
    if (newParent == null) {
      return true;
    }
    return treeController.getNodeData(newParent) != null &&
        !treeController.isPendingDeletion(newParent) &&
        newParent != key &&
        !_resolver.isStrictDescendantOf(newParent, key);
  }

  /// THE mutation site. Picks the mutation shape from the keys alone and
  /// returns the triple it committed, with the index RESOLVED: callers
  /// report that rather than their own argument, so an out-of-range
  /// request cannot be published as though it were a real position.
  ///
  /// Deliberately does NOT notify: [endDrag] must report after its
  /// session teardown, while [moveTo] reports immediately, so the two
  /// orderings are the callers' business and the notification has exactly
  /// one implementation ([_fireOnReorder]).
  ///
  /// [index] is live-space and names the position in the FINAL sibling
  /// list, after [key] has been removed from wherever it was.
  ({TKey key, TKey? newParent, int index}) _applyMove(
    TKey key,
    TKey? newParent,
    int index, {
    required bool animate,
  }) {
    final sameParent = treeController.getParent(key) == newParent;
    if (sameParent) {
      // reorderChildren/reorderRoots reject lists containing
      // pending-deletion entries and re-append them internally after
      // validating the live ordering.
      //
      // Copied rather than used in place: `getLiveChildren` returns a
      // `const []` for an absent or empty child list, and mutating that
      // throws. Both current callers have already established that `key`
      // is a live child here, so the list cannot be empty, but this
      // method's contract is "unchecked" and the next caller will not
      // know that.
      final liveSiblings = List<TKey>.of(
        newParent == null
            ? treeController.liveRootKeys
            : treeController.getLiveChildren(newParent),
      );
      liveSiblings.remove(key);
      final insertAt = index.clamp(0, liveSiblings.length);
      liveSiblings.insert(insertAt, key);
      if (newParent == null) {
        treeController.reorderRoots(liveSiblings, animate: animate);
      } else {
        treeController.reorderChildren(
          newParent,
          liveSiblings,
          animate: animate,
        );
      }
      return (key: key, newParent: newParent, index: insertAt);
    }
    // Cross-parent: moveNode's `index` is already the position in the new
    // parent's final child list.
    treeController.moveNode(key, newParent, index: index, animate: animate);
    return (key: key, newParent: newParent, index: index);
  }

  /// The single [onReorder] invocation site.
  void _fireOnReorder(({TKey key, TKey? newParent, int index}) move) {
    onReorder?.call(move.key, move.newParent, move.index);
  }

  /// Commits a programmatic move of [key] under [newParent] at [index],
  /// exactly as a pointer drop would: same mutation choice, same
  /// live-space final-list index convention, same [onReorder] report.
  ///
  /// Returns false, mutating and notifying NOTHING, when:
  ///
  /// - a drag session is active (see below);
  /// - [key] is absent or pending deletion;
  /// - [newParent] is absent, pending deletion, [key] itself, or one of
  ///   [key]'s descendants;
  /// - [canAcceptDrop] rejects the destination;
  /// - [key] already occupies that slot.
  ///
  /// **Refused during a drag on purpose.** Mutating structure underneath
  /// a live session leaves it resolving against painted offsets that
  /// predate the change, collides with the commit script's first-wins
  /// FLIP baseline, and can strand the make-room gap on a slot that no
  /// longer exists. Callers that genuinely want to interrupt a drag
  /// should [cancelDrag] first.
  bool moveTo(
    TKey key,
    TKey? newParent, {
    required int index,
    bool animate = true,
  }) {
    if (_session != null) {
      return false;
    }
    if (!_canCommit(key, newParent)) {
      return false;
    }
    // Resolve the index the way [_applyMove] will, so an out-of-range
    // request that clamps onto the node's current slot is recognised as
    // the no-op it is rather than reported as a move.
    final sameParent = treeController.getParent(key) == newParent;
    final int destinationLength = newParent == null
        ? treeController.liveRootCount
        : treeController.liveChildCount(newParent);
    // The FINAL list excludes `key` only when it is already there.
    final effectiveIndex = index.clamp(
      0,
      sameParent ? destinationLength - 1 : destinationLength,
    );
    if (sameParent && treeController.getIndexInParent(key) == effectiveIndex) {
      return false;
    }
    if (canAcceptDrop != null &&
        !canAcceptDrop!(
          movingKey: key,
          newParent: newParent,
          index: effectiveIndex,
        )) {
      return false;
    }
    _fireOnReorder(
      _applyMove(key, newParent, effectiveIndex, animate: animate),
    );
    return true;
  }

  /// Moves [key] one position earlier among its live siblings.
  ///
  /// One of the four moves exposed to assistive technology, where pointer
  /// drags are unusable. Each returns whether it committed, applies
  /// [canAcceptDrop], and reports through [onReorder], exactly as
  /// [moveTo] does.
  bool moveUp(TKey key) {
    return _moveBySiblingDelta(key, -1);
  }

  /// Moves [key] one position later among its live siblings. See [moveUp].
  bool moveDown(TKey key) {
    return _moveBySiblingDelta(key, 1);
  }

  bool _moveBySiblingDelta(TKey key, int delta) {
    final index = treeController.getIndexInParent(key);
    if (index < 0) {
      return false;
    }
    final parent = treeController.getParent(key);
    final liveCount = parent == null
        ? treeController.liveRootCount
        : treeController.liveChildCount(parent);
    final target = index + delta;
    if (target < 0 || target >= liveCount) {
      return false;
    }
    return moveTo(key, parent, index: target);
  }

  /// Moves [key] out of its parent, to sit directly after that parent
  /// among its grandparent's children. See [moveUp].
  bool moveOut(TKey key) {
    if (treeController.getIndexInParent(key) < 0) {
      return false;
    }
    final parent = treeController.getParent(key);
    if (parent == null) {
      return false;
    }
    return moveTo(
      key,
      treeController.getParent(parent),
      index: treeController.getIndexInParent(parent) + 1,
    );
  }

  /// Moves [key] in as the last child of its previous live sibling.
  /// See [moveUp].
  bool moveIntoPrevious(TKey key) {
    final index = treeController.getIndexInParent(key);
    if (index <= 0) {
      return false;
    }
    final parent = treeController.getParent(key);
    final previous = treeController.liveSiblingAt(parent, index - 1);
    if (previous == null) {
      return false;
    }
    return moveTo(
      key,
      previous,
      index: treeController.liveChildCount(previous),
    );
  }

  /// Aborts the current drag without mutating the tree.
  void cancelDrag() {
    final session = _session;
    if (session == null) {
      return; // Per-session ticker: no session ⇒ nothing can be ticking.
    }
    session.detachAll(SessionExit.cancel);
    _pointerPosition.value = null;
    _session = null;
    notifyListeners();
  }

  /// Tears down any active session (its collaborators own their tickers
  /// and timers). Call from the owning widget's `dispose`.
  @override
  void dispose() {
    final session = _session;
    if (session != null) {
      session.detachAll(SessionExit.dispose);
      _pointerPosition.value = null;
      _session = null;
    }
    _pointerPosition.dispose();
    super.dispose();
  }

  /// Value-equality for two drop targets so we only notify on real changes
  /// (pointer moves that cross a zone or row boundary), not on every
  /// pointer event that produces a structurally identical target.
  static bool _targetsEqual<TKey>(
    TreeDropTarget<TKey>? a,
    TreeDropTarget<TKey>? b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return a.targetKey == b.targetKey &&
        a.zone == b.zone &&
        a.parentKey == b.parentKey &&
        a.indexInFinalList == b.indexInFinalList &&
        a.depth == b.depth &&
        // Not implied by the fields above: a dwell auto-expand under a
        // stationary pointer changes where the gap opens without changing
        // the semantic slot. Included for value-equality honesty on a
        // type this method claims to compare structurally; the preview
        // does not depend on it, since the driver installs outside this
        // gate and re-installation is governed by the geometry memo.
        a.gapVisibleIndex == b.gapVisibleIndex &&
        a.targetPaintedY == b.targetPaintedY &&
        a.targetExtent == b.targetExtent;
  }
}
