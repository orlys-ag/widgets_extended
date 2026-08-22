/// Internal: per-drag session infrastructure for `TreeReorderController`:
/// [SessionExit], [PointerSample] and [PointerSpace], [DragProbe], and
/// [DragSession] itself. The behavior collaborators the session fans out
/// to live in `_drag_session_behaviors.dart`.
///
/// [PointerSpace] is the ONLY component that touches the scrollable:
/// every coordinate conversion and every liveness question goes through
/// it, and its reads are NULLABLE. A null sample means the scrollable's
/// `State` is unmounted, at which point even reading `.context` throws,
/// so the nullability forces every consumer to handle the defunct case at
/// the type level.
///
/// Class names are public despite the underscore-prefixed file: Dart
/// makes an underscore-prefixed CLASS name library-private, which would
/// hide it from the headless unit tests. Internality comes from barrel
/// non-export instead, as with `DropZoneResolver` and
/// `ReorderPreviewEngine`.
library;

import 'package:flutter/widgets.dart';

import '_drag_session_behaviors.dart';
import '_drop_zone_resolver.dart';
import 'animation_style.dart';
import 'reorder_render_port.dart';

/// How a drag session ended. Collaborator teardown dispatches on this:
/// e.g. the make-room gap releases ANIMATED on [cancel] (rows glide
/// home), SNAPS on [dispose] (nothing left to animate against), and does
/// nothing on [commit] (the commit script already snapped it before the
/// mutation).
enum SessionExit { commit, cancel, dispose }

/// One pointer conversion: everything the drag pipeline derives from a
/// pointer position, computed from a SINGLE viewport lookup per event.
///
/// - [sliverY]: sliver-local y, the space
///   [ReorderRenderPort.findRowAtPaintedY] consumes (first tree row at
///   0). Differs from viewport scroll space by the tree sliver's
///   `precedingScrollExtent`.
/// - [sliverX]: viewport-local x, identical to sliver-local x for a
///   vertical-axis tree. Consumed by the depth hint.
/// - [viewportDy] / [viewportHeight]: viewport-local vertical position
///   and extent, consumed by autoscroll edge-zone evaluation.
typedef PointerSample = ({
  double sliverX,
  double sliverY,
  double viewportDy,
  double viewportHeight,
});

/// Coordinate conversion + liveness for one drag session. See library
/// docs for the nullable-read contract.
class PointerSpace<TKey> {
  PointerSpace({
    required ScrollableState scrollable,
    required ReorderRenderPort<TKey> renderPort,
  }) : _scrollable = scrollable,
       _renderPort = renderPort;

  final ScrollableState _scrollable;
  final ReorderRenderPort<TKey> _renderPort;

  /// Whether the scrollable is still mounted. Prefer consuming the
  /// nullability of [sample]/[position] over branching on this directly.
  bool get isLive => _scrollable.mounted;

  /// The scroll position, or `null` when the scrollable is unmounted.
  ScrollPosition? get position {
    if (!_scrollable.mounted) {
      return null;
    }
    return _scrollable.position;
  }

  /// Converts [globalPointer] into every coordinate the drag pipeline
  /// needs, or `null` when the scrollable is unmounted (or its viewport
  /// box is detached mid-teardown).
  PointerSample? sample(Offset globalPointer) {
    if (!_scrollable.mounted) {
      return null;
    }
    final box = _scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      return null;
    }
    final local = box.globalToLocal(globalPointer);
    return (
      sliverX: local.dx,
      sliverY:
          _scrollable.position.pixels +
          local.dy -
          _renderPort.precedingScrollExtent,
      viewportDy: local.dy,
      viewportHeight: box.size.height,
    );
  }
}

/// The session's resolution core: the ONE owner of grab geometry and the
/// ONE site that turns a [PointerSample] into a [TreeDropTarget]. Both
/// the per-event pipeline ([DragSession.resolve]) and `endDrag`'s commit
/// re-resolution go through [resolveTarget], so the committed slot is
/// always the slot the feedback showed.
class DragProbe<TKey> {
  DragProbe({
    required ReorderRenderPort<TKey> renderPort,
    required DropZoneResolver<TKey> resolver,
    required TKey draggedKey,
    required int Function(double sliverLocalX)? depthForPointerX,
  }) : _renderPort = renderPort,
       _resolver = resolver,
       _draggedKey = draggedKey,
       _depthForPointerX = depthForPointerX;

  final ReorderRenderPort<TKey> _renderPort;
  final DropZoneResolver<TKey> _resolver;
  final TKey _draggedKey;

  /// Optional mapper from pointer x to a preferred depth. Null disables
  /// x-aware depth selection: the resolver then always picks the deepest
  /// legal level.
  final int Function(double sliverLocalX)? _depthForPointerX;

  /// Drag-proxy grab geometry, captured once by [captureGrab]: the
  /// pointer's offset within the dragged row (so the floating preview
  /// doesn't jump to the pointer) and the row's extent (to size the
  /// preview). Read by the public `dragProxyGeometry` getter and the
  /// settler's release-anchor math.
  double get grabDy => _grabDy;
  double get grabRowExtent => _grabRowExtent;
  double _grabDy = 0.0;
  double _grabRowExtent = 0.0;

  /// Touch-first probe offset: shifts slot resolution from the raw
  /// pointer to the PROXY MIDPOINT, `grabRowExtent / 2 - grabDy`. On
  /// touch there is no visible cursor, so the card in hand is the only
  /// thing the user can steer by and selection has to track it. Non-zero
  /// only when the caller enables the midpoint probe (make-room plus
  /// release-settle, where the anchor IS the visible floating card) and
  /// the grab capture succeeded. A session constant, so the whole
  /// resolution pipeline simply probes at `pointer + probeDy`.
  ///
  /// Derived invariant: at drag start the probe is the dragged row's OWN
  /// midpoint, because the grab position cancels out, so every probed
  /// session begins on the current-position target.
  double get probeDy => _probeDy;
  double _probeDy = 0.0;

  /// Captures grab geometry once at session start against the start
  /// sample.
  ///
  /// Asks the render port where the DRAGGED KEY is painted rather than
  /// what row sits under the pointer. The two differ at a sticky header:
  /// a pinned header paints in its pinned band while its structural
  /// offset has scrolled away above, so
  /// [ReorderRenderPort.findRowAtPaintedY] would answer with whatever
  /// content is scrolled UNDERNEATH the pinned strip, and the capture
  /// would take that foreign row's offset and extent.
  ///
  /// Addressing the key directly leaves no "wrong row" case, so a located
  /// row is always trustworthy geometry and [midpointProbe] applies
  /// whenever it is requested. The one failure left is an unlocatable
  /// (unmounted) row, which zeroes the record: there is no trustworthy
  /// extent to report either, and a zero extent is already the drag
  /// proxy's "size to your content" signal.
  void captureGrab({
    required PointerSample start,
    required bool midpointProbe,
  }) {
    final bounds = _renderPort.paintedRowBounds(_draggedKey);
    if (bounds == null) {
      _grabDy = 0.0;
      _grabRowExtent = 0.0;
      return;
    }
    _grabDy = (start.sliverY - bounds.paintedOffset).clamp(0.0, bounds.extent);
    _grabRowExtent = bounds.extent;
    if (midpointProbe) {
      _probeDy = bounds.extent / 2 - _grabDy;
    }
  }

  /// Finds the live row under the probe via
  /// [ReorderRenderPort.findRowAtPaintedY] and hands classification to
  /// the [DropZoneResolver]. Pending-deletion rows are vanishing and
  /// cannot be valid drop targets; the lookup skips them.
  ///
  /// One probe for the whole resolution: row lookup, zone classification
  /// and dwell all read `sample.sliverY + probeDy` (the proxy midpoint
  /// when the midpoint probe is on, the raw pointer otherwise). The
  /// x-depth hint stays on pointer x, which the vertical shift does not
  /// affect.
  ///
  /// A `null` [sample] means the scrollable is gone: returns [previous]
  /// unchanged (no event can change what the user sees anyway; teardown
  /// paths handle the session's end).
  ///
  /// **The make-room gap.** A probe ABOVE the hovered row's painted band
  /// cannot happen while rows are contiguous, so it means exactly one
  /// thing: the probe is inside the gap the preview has opened, and the
  /// row the scan answered with is the one BELOW that gap (the scans hit
  /// on `scrollY < painted + extent`, with no lower bound). The gap IS
  /// the slot [previous] is previewing, so that is the honest answer;
  /// re-classifying against the row below it is what made a downward
  /// "into" drag commit as a sibling. The x-depth hint is deliberately
  /// not re-evaluated there: a gap has no row to anchor a candidate
  /// chain on, so horizontal movement changes nothing until the pointer
  /// leaves the gap.
  TreeDropTarget<TKey>? resolveTarget({
    required PointerSample? sample,
    required TreeDropTarget<TKey>? previous,
  }) {
    if (sample == null) {
      return previous;
    }
    final probeY = sample.sliverY + _probeDy;

    final hovered = _renderPort.findRowAtPaintedY(probeY);
    if (hovered == null) {
      return null;
    }

    // See "The make-room gap" above. The index equality is what keeps
    // this to the preview's own gap: the row directly below the gap is
    // the row at `gapVisibleIndex` in the current visible order, whether
    // the gap sits before the dragged block (rows at/after it shifted
    // down) or after it (rows in `[draggedEnd, gapIndex)` shifted up).
    // Any other above-the-band probe (a FLIP slide in flight, an
    // edge-ghost base, a stale `previous` after an external mutation)
    // falls through to normal classification.
    if (previous != null &&
        probeY < hovered.paintedOffset &&
        previous.gapVisibleIndex ==
            _resolver.treeController.getVisibleIndex(hovered.key)) {
      return previous;
    }

    return _resolver.resolve(
      draggedKey: _draggedKey,
      targetKey: hovered.key,
      targetPaintedY: hovered.paintedOffset,
      targetExtent: hovered.extent,
      pointerY: probeY,
      preferredDepth: _depthForPointerX?.call(sample.sliverX),
    );
  }
}

/// Per-drag state held only while a drag is active. It owns the two
/// consolidation sites: [resolve] (the ONE choreography site) and
/// [detachAll] (the ONE teardown site, dispatched on [SessionExit]).
/// Behaviors are reached by direct calls, with no interface and no
/// registration list. Notification channels stay with the controller:
/// this class never notifies listeners.
class DragSession<TKey> {
  DragSession({
    required this.draggedKey,
    required this.renderPort,
    required this.pointerSpace,
    required this.probe,
    required this.pointerGlobal,
    required this.commitSlideSpec,
  });

  /// Commit-slide timing, resolved from the tree controller's
  /// `animationStyle.reorderSlide` ONCE at session start, so a mid-drag
  /// restyle never retimes a live session; the next drag picks it up.
  /// Consumed by the commit script's baseline staging.
  final TreeAnimationSpec commitSlideSpec;

  final TKey draggedKey;
  final ReorderRenderPort<TKey> renderPort;

  /// The session's ONLY route to coordinates and scrollable liveness: a
  /// null [PointerSpace.sample] means the scrollable is gone, and every
  /// consumer handles it.
  final PointerSpace<TKey> pointerSpace;

  /// The resolution core and the ONE owner of grab geometry + probeDy.
  /// `dragProxyGeometry` and the settler read through it.
  final DragProbe<TKey> probe;

  /// Behavior collaborators, assigned by `startDrag` right after
  /// construction, because they need the session's identity for their
  /// callbacks. [makeRoomDriver] is null when the session runs without
  /// make-room, [settler] when it runs without a proxy: absence IS the
  /// mode flag.
  late final AutoScroller<TKey> autoScroller;
  late final DwellExpander<TKey> dwell;
  MakeRoomDriver<TKey>? makeRoomDriver;
  DropSettler<TKey>? settler;

  /// Latest pointer position in global coordinates. Updated on every
  /// `TreeReorderController.updateDrag` call so the autoscroll ticker
  /// can re-evaluate without extra callback plumbing.
  Offset pointerGlobal;

  /// The scroll position this session subscribed to and the listener it
  /// subscribed with. Held so teardown detaches the SAME pair even if
  /// `scrollable.position` is swapped mid-drag.
  ScrollPosition? _subscribedPosition;
  VoidCallback? _scrollListener;

  /// The slot the last resolution landed on, and the slot a commit uses.
  /// Null when no row sits under the probe, but deliberately HELD when
  /// the scrollable is gone, since [DragProbe.resolveTarget] returns the
  /// previous target rather than dropping it.
  TreeDropTarget<TKey>? currentTarget;

  /// Subscribes [listener] to [position] for the session's lifetime:
  /// wheel/trackpad/second-finger scrolls move content under a
  /// stationary pointer, and the autoscroll ticker's own `jumpTo`
  /// notifies this same listener, giving one re-resolution path for every
  /// scroll source. [detachAll] unsubscribes.
  void subscribeScroll(ScrollPosition position, VoidCallback listener) {
    _subscribedPosition = position;
    _scrollListener = listener;
    position.addListener(listener);
  }

  /// THE choreography site: one [PointerSpace.sample] per event (the
  /// single viewport lookup), the probe's resolution core, then every
  /// behavior in a fixed order. A new behavior joins the pipeline by one
  /// edit here. Re-entrant only from a behavior's ASYNC callback, meaning
  /// the dwell fire, never synchronously from inside this sequence.
  void resolve() {
    final sample = pointerSpace.sample(pointerGlobal);
    currentTarget = probe.resolveTarget(
      sample: sample,
      previous: currentTarget,
    );
    dwell.onTargetResolved(currentTarget);
    makeRoomDriver?.onTargetResolved(currentTarget);
    autoScroller.evaluate(sample);
  }

  /// Target-only re-resolution for the commit script: the same probe core
  /// as [resolve], so the committed slot is always the slot the feedback
  /// showed, but WITHOUT the behavior fan-out. Syncing the behaviors at
  /// commit time could re-target the make-room gap between the FLIP
  /// baseline capture and its snap, corrupting the slide.
  void resolveTargetOnly() {
    currentTarget = probe.resolveTarget(
      sample: pointerSpace.sample(pointerGlobal),
      previous: currentTarget,
    );
  }

  /// THE teardown site: every behavior's release, dispatched on [exit],
  /// then the session-common resources, being the scroll subscription and
  /// the dragged row's eviction pin. A new behavior joins teardown by one
  /// edit here.
  ///
  /// The commit's make-room SNAP is deliberately absent: it must precede
  /// the mutation, so the commit script owns it. The pointer channel is
  /// controller-owned and nulled by the caller.
  void detachAll(SessionExit exit) {
    autoScroller.detach(exit);
    final listener = _scrollListener;
    if (listener != null) {
      _subscribedPosition?.removeListener(listener);
    }
    _subscribedPosition = null;
    _scrollListener = null;
    dwell.detach(exit);
    makeRoomDriver?.detach(exit);
    settler?.detach(exit);
    renderPort.unpinNode(draggedKey);
  }
}
