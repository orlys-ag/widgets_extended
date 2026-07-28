/// Orchestrates drag-and-drop reorder over a [TreeController]-backed
/// [SliverTree]: gesture lifecycle, drop-target resolution, autoscroll near
/// viewport edges, and FLIP slide animation on commit.
///
/// The controller is **stateless when idle** — it holds no per-frame state
/// outside an active drag. A drag session begins with [startDrag], receives
/// pointer updates via [updateDrag], and ends with [endDrag] (commit) or
/// [cancelDrag] (no-op). Only one session can be active at a time.
///
/// This file owns the PUBLIC API, policy (`canReorder`/`canAcceptDrop`,
/// autoscroll/dwell/slide tuning), the notification channels, and the
/// COMMIT SCRIPT. Everything else is delegated to the session
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
/// that need to repaint per-pointer-move (like the built-in drop
/// indicator) subscribe here instead of polling per-frame.
class TreeReorderController<TKey> extends ChangeNotifier {
  TreeReorderController({
    required this.treeController,
    required TickerProvider vsync,
    this.canReorder,
    this.canAcceptDrop,
    this.slideDuration = const Duration(milliseconds: 220),
    this.slideCurve = Curves.easeOutCubic,
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
  final bool Function({
    required TKey movingKey,
    TKey? newParent,
    int? index,
  })? canAcceptDrop;

  /// Duration of the FLIP slide animation on commit.
  final Duration slideDuration;

  /// Curve of the FLIP slide animation.
  final Curve slideCurve;

  /// Height in pixels from each viewport edge within which the pointer
  /// triggers autoscroll. Velocity ramps linearly from 0 at the zone's
  /// inner edge to [autoScrollMaxVelocity] at the viewport edge.
  final double autoScrollEdgeZone;

  /// Peak autoscroll velocity in logical pixels per second.
  final double autoScrollMaxVelocity;

  /// How long the pointer must dwell on an `into` target that is
  /// collapsed (and has live children to reveal) before the target
  /// auto-expands — the conventional hover-to-open tree affordance.
  ///
  /// `null` or [Duration.zero] disables auto-expand. The dwell re-arms
  /// on every target change and is cancelled by session end.
  final Duration? autoExpandDelay;

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

  /// The currently-dragged key, or `null` if no drag is active.
  TKey? get draggedKey => _session?.draggedKey;

  /// The current drop target, or `null` if the pointer is outside any row
  /// or every candidate slot is a cycle.
  ///
  /// A target whose slot equals the dragged row's current position IS
  /// valid ("returns here" feedback — the indicator/gap shows the original
  /// slot instead of going dark); [endDrag] detects it and commits
  /// nothing, behaving like [cancelDrag].
  TreeDropTarget<TKey>? get currentTarget => _session?.currentTarget;

  /// The render port of the active drag session, or `null` when idle.
  ///
  /// For presentation-layer consumers: the semantic [TreeDropTarget]
  /// carries sliver-local geometry, and converting it to viewport scroll
  /// space needs [ReorderRenderPort.precedingScrollExtent]. The built-in
  /// drop indicator reads this on every repaint.
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
  /// preferred depth (e.g. `x ~/ indentPerDepth` — the widget layer owns
  /// the pixel constant); the resolver clamps it to the legal candidate
  /// chain when a below-zone drop sits at a subtree right-boundary. Omit
  /// it to always resolve at the deepest legal level.
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
    final session = DragSession<TKey>(
      draggedKey: key,
      renderPort: renderPort,
      pointerSpace: pointerSpace,
      probe: probe,
      pointerGlobal: pointerGlobal,
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
        duration: slideDuration,
        curve: slideCurve,
      );
    }
    if (settleFromRelease) {
      session.settler = DropSettler<TKey>(
        treeController: treeController,
        space: pointerSpace,
        pointerGlobal: () => session.pointerGlobal,
        grabDy: () => probe.grabDy,
        draggedKey: key,
        duration: slideDuration,
        curve: slideCurve,
      );
    }
    _session = session;
    // Pin the dragged row against stale eviction for the session's
    // lifetime: the drag gesture lives on the row's own GestureDetector,
    // so autoscrolling it out of the cache region would otherwise evict
    // the row, its end/cancel callbacks would never fire, and the session
    // (plus the autoscroll ticker) would run forever.
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

  /// Re-resolves through the session's single choreography site and fires
  /// the coalesced [ChangeNotifier] channel iff the semantic target
  /// changed. Notification stays controller-owned.
  void _resolveAndNotify(DragSession<TKey> session) {
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
    // target would throw out of a GestureDetector callback with the
    // session permanently stuck, and a baseline staged before validation
    // would be consumed by nobody — first-wins staging then blocks every
    // subsequent slide stage until an unrelated layout flushes it.
    session.resolveTargetOnly();
    final target = session.currentTarget;
    final dragged = session.draggedKey;
    final bool valid;
    if (target == null) {
      valid = false;
    } else if (treeController.getNodeData(dragged) == null ||
        treeController.isPendingDeletion(dragged)) {
      valid = false;
    } else {
      final parentKey = target.parentKey;
      if (parentKey == null) {
        valid = true;
      } else {
        valid = treeController.getNodeData(parentKey) != null &&
            !treeController.isPendingDeletion(parentKey) &&
            parentKey != dragged &&
            !_resolver.isStrictDescendantOf(parentKey, dragged);
      }
    }
    if (!valid) {
      cancelDrag();
      return;
    }

    // Current-position drop: the resolver now reports the dragged row's
    // own slot as a valid target ("returns here" feedback), but committing
    // it must mutate NOTHING — and must stage NO baseline (an unconsumed
    // baseline is exactly the protocol violation the expiry backstop
    // guards against). cancelDrag is the precise semantic: settle-back
    // glide, make-room release, clean teardown.
    if (treeController.getParent(dragged) == target!.parentKey &&
        target.indexInFinalList ==
            treeController.getIndexInParent(dragged)) {
      cancelDrag();
      return;
    }

    // The autoscroll ticker stops in detachAll(commit) below; endDrag is
    // synchronous, so no tick can interleave before then.

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
    session.renderPort.beginSlideBaseline(
      duration: slideDuration,
      curve: slideCurve,
      // Proxy drop-settle: the dragged row's FLIP starts at the release
      // position (null when no settler, or scrollable gone → classic
      // old-slot FLIP).
      baselineYOverrides: session.settler?.baselineOverrides(),
    );

    // Make-room handoff: the baseline above captured the SHIFTED painted
    // positions (preview offsets ride the composed slide-delta read).
    // Snap the preview away now, BEFORE the mutation — the consume-time
    // snapshot then reads clean post-mutation structural positions, and
    // rows already previewing at their destination get ~zero FLIP deltas
    // (no jump, no double animation). This ordering is why the snap is a
    // named commit-script op rather than part of teardown.
    session.makeRoomDriver?.snapForCommit();

    try {
      final currentParent = treeController.getParent(dragged);
      // `target` was promoted non-null by the current-position check above.
      final sameParent = currentParent == target.parentKey;

      if (sameParent) {
        // Build the live final sibling list — reorderChildren/reorderRoots
        // reject lists containing pending-deletion entries and re-append them
        // internally after validating the live ordering.
        final liveSiblings = target.parentKey == null
            ? treeController.liveRootKeys
            : treeController.getLiveChildren(target.parentKey as TKey);
        liveSiblings.remove(dragged);
        final insertAt = target.indexInFinalList.clamp(0, liveSiblings.length);
        liveSiblings.insert(insertAt, dragged);

        if (target.parentKey == null) {
          // Drag commit: the reorderable widget owns the drop animation, so
          // keep the structural commit a snap to avoid double-animating the
          // item.
          treeController.reorderRoots(liveSiblings, animate: false);
        } else {
          treeController.reorderChildren(
            target.parentKey as TKey,
            liveSiblings,
            animate: false,
          );
        }
      } else {
        // Cross-parent: moveNode's `index` is the position in the new
        // parent's final child list — exactly indexInFinalList.
        treeController.moveNode(
          dragged,
          target.parentKey,
          index: target.indexInFinalList,
        );
      }
    } finally {
      // The re-resolve + validation above makes the commit's throwing
      // paths unreachable, so an exception here is a genuine invariant
      // violation — let it propagate, but never leave the session stuck.
      session.detachAll(SessionExit.commit);
      _pointerPosition.value = null;
      _session = null;
      notifyListeners();
    }
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
        a.targetPaintedY == b.targetPaintedY &&
        a.targetExtent == b.targetExtent;
  }

}
