/// Element for [SliverTree] that manages child element lifecycle.
library;

import 'package:flutter/widgets.dart';

import 'render_sliver_tree.dart';
import 'sliver_tree_widget.dart';

// ════════════════════════════════════════════════════════════════════════════
// CHILD MANAGER INTERFACE
// ════════════════════════════════════════════════════════════════════════════

/// Interface for managing child render objects in [RenderSliverTree].
///
/// Implemented by [SliverTreeElement] to allow the render object to
/// request child creation/removal during layout.
abstract class TreeChildManager<TKey> {
  /// Creates or updates the child for the given node.
  void createChild(TKey nodeId);

  /// Removes the child for the given node, from inside the render object's
  /// layout, so the frame that removes it also disposes its element.
  void removeChild(TKey nodeId);

  /// Called when layout starts.
  void didStartLayout();

  /// Called when layout finishes.
  void didFinishLayout();
}

// ════════════════════════════════════════════════════════════════════════════
// ELEMENT
// ════════════════════════════════════════════════════════════════════════════

/// Element for [SliverTree] that creates and manages child elements.
///
/// Uses nodeId-based storage for straightforward element lifecycle management.
class SliverTreeElement<TKey, TData> extends RenderObjectElement
    implements TreeChildManager<TKey> {
  /// Creates a sliver tree element.
  SliverTreeElement(SliverTree<TKey, TData> super.widget);

  @override
  SliverTree<TKey, TData> get widget => super.widget as SliverTree<TKey, TData>;

  @override
  RenderSliverTree<TKey, TData> get renderObject =>
      super.renderObject as RenderSliverTree<TKey, TData>;

  /// Child elements by nodeId.
  final Map<TKey, Element> _children = {};

  /// Whether we're currently in a layout callback.
  bool _inLayout = false;

  /// Keys whose mounted widget may be stale and needs refresh.
  ///
  /// Populated by four sources:
  ///   - [update] (parent rebuild): every mounted key is queued so rows
  ///     pick up the new `nodeBuilder` closure / captured parent state.
  ///   - [_onStructuralChange]: null affectedKeys queues every mounted
  ///     key; a non-empty set queues only the listed mounted keys.
  ///   - [_onNodeDataChanged]: queues the single affected mounted key.
  ///   - [didChangeDependencies]: every mounted key is queued, because
  ///     rows share this element as their BuildContext, so any inherited
  ///     widget any row reads dirties every mounted row.
  ///
  /// Consumed lazily in [createChild] during the next layout: cache-
  /// region and sticky children are rebuilt there; off-screen queued
  /// entries wait until they re-enter the cache region (refreshed on
  /// re-entry) or until stale eviction fires (discarded).
  ///
  /// This bounds refresh work by "what the viewport actually needs this
  /// frame" instead of walking `_children.keys` unconditionally on every
  /// parent rebuild. Without this bound, an external listener that
  /// rebuilds SliverTree's ancestor (e.g. `ListenableBuilder` on the
  /// controller) would cause `update` to rebuild every mounted row,
  /// including off-screen descendants that are moments away from
  /// stale-eviction. See `sliver_tree_widget_test.dart` regressions.
  final Set<TKey> _dirtyKeys = {};

  /// Whether the last animation tick observed
  /// [TreeController.hasActiveAnimations] as true. Used by
  /// [_onAnimationTick] so the settle tick (where the
  /// controller has already cleared animation state before notifying) still
  /// triggers [RenderObject.markNeedsLayout]. Without this, completed extent
  /// animations would never relayout and the render would remain at the
  /// partial animated value instead of the final settled extent.
  bool _priorTickHadAnimations = false;

  /// Mirror of [_priorTickHadAnimations] for slides. Used so the
  /// settle tick of a slide-only animation still triggers a relayout,
  /// the render object's Step 0a / 0b ghost-cleanup runs only inside
  /// `performLayout`, and without a final layout pass after settle,
  /// settled ghost entries would linger until the next unrelated
  /// layout (scroll, structural mutation, etc.).
  bool _priorTickHadSlides = false;

  /// FLIP-only companion to [_priorTickHadSlides].
  ///
  /// The composed mirror above cannot see a FLIP settle that happens
  /// while a make-room preview is held: a preview offset is HELD, so
  /// `hasActiveSlides` stays true from a drag's first resolve to its
  /// release, the composed transition never fires, and the ghost-cleanup
  /// layout never runs for the whole drag. Ghosts are FLIP artifacts, so
  /// their cleanup has to observe the FLIP transition specifically.
  bool _priorTickHadFlipSlides = false;

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.childManager = this;
    widget.controller.addStructuralListener(_onStructuralChange);
    widget.controller.addAnimationListener(_onAnimationTick);
    widget.controller.addNodeDataListener(_onNodeDataChanged);
  }

  @override
  void unmount() {
    widget.controller.removeStructuralListener(_onStructuralChange);
    widget.controller.removeAnimationListener(_onAnimationTick);
    widget.controller.removeNodeDataListener(_onNodeDataChanged);
    super.unmount();
  }

  /// Hot reload: re-run [SliverTree.nodeBuilder] for every mounted row.
  ///
  /// `Element.reassemble` marks this element dirty and recurses into the
  /// rows, but neither step re-invokes the builder, whose closure body is
  /// what a reload replaces. When the ancestor hands down a fresh
  /// `SliverTree`, [update]'s parent-rebuild queue covers it; when it
  /// hands down the IDENTICAL instance (`AnimatedBuilder`,
  /// `ValueListenableBuilder` and `AnimatedTheme` all pass `child`
  /// through), `Element.updateChild` short-circuits and [update] never
  /// runs, so the cause queues its own keys here, per the rule stated in
  /// [performRebuild]. Rows refresh in place through [createChild]'s
  /// `updateChild`, which is hot reload's contract: a row whose widget
  /// type is unchanged keeps its `State`, a changed type is re-inflated.
  /// Reload-only; no cost in any other frame.
  @override
  void reassemble() {
    super.reassemble();
    if (_children.isEmpty) {
      return;
    }
    _dirtyKeys.addAll(_children.keys);
    renderObject.markNeedsLayout();
  }

  @override
  void update(SliverTree<TKey, TData> newWidget) {
    final oldWidget = widget;
    super.update(newWidget);

    if (oldWidget.controller != newWidget.controller) {
      oldWidget.controller.removeStructuralListener(_onStructuralChange);
      oldWidget.controller.removeAnimationListener(_onAnimationTick);
      oldWidget.controller.removeNodeDataListener(_onNodeDataChanged);
      newWidget.controller.addStructuralListener(_onStructuralChange);
      newWidget.controller.addAnimationListener(_onAnimationTick);
      newWidget.controller.addNodeDataListener(_onNodeDataChanged);
      renderObject.controller = newWidget.controller;
      // Old-controller keys are meaningless under the new controller;
      // drop the queue and let createChild rebuild against fresh data.
      // A key only the old controller has keeps its Element here and its
      // RenderBox there, with no live nodeData: the render object keeps
      // its children across the swap (see its controller setter), and the
      // layout that setter marks drops both through [removeChild].
      _dirtyKeys.clear();
    }

    // Parent rebuild: the `nodeBuilder` closure may have captured new
    // state. Queue every mounted row for lazy refresh and trigger a
    // layout pass, retained rows rebuild in [createChild] within the
    // same frame; off-screen rows wait for re-entry or discard. This
    // bounds the rebuild fan-out to the retained set (roughly the cache
    // region), not the full mounted set. See [_dirtyKeys] doc.
    _dirtyKeys.addAll(_children.keys);
    renderObject.markNeedsLayout();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fourth [_dirtyKeys] producer. Rows build with THIS element as their
    // BuildContext (see [createChild]), so every inherited read a
    // nodeBuilder performs registers here; a Theme / MediaQuery /
    // DefaultTextStyle change means every mounted row's builder output
    // may differ. Same lazy shape as [update]: queue, mark layout, let
    // [createChild] rebuild the cache-region and sticky rows the next
    // layout reaches (see [_dirtyKeys]). NOT only the cache region:
    // sticky headers the cache region rejected are force-created too
    // (the sticky block's force-create measurement in
    // `RenderSliverTree.performLayout`).
    if (_children.isEmpty) {
      return;
    }
    _dirtyKeys.addAll(_children.keys);
    renderObject.markNeedsLayout();
  }

  @override
  // ignore: unnecessary_overrides
  void performRebuild() {
    super.performRebuild();
    // Deliberately queues NOTHING. Two causes mark this element dirty:
    //
    //   - [didChangeDependencies], which has already added every mounted
    //     key to [_dirtyKeys] and called `markNeedsLayout` by the time
    //     the build phase reaches here (`markNeedsBuild` only enqueues;
    //     framework.dart:5386-5390). Nothing is left to do.
    //   - `Element.reassemble`, which calls `markNeedsBuild()`
    //     (framework.dart:3754-3759) and reaches this element through
    //     [reassemble]'s `super` call; [reassemble] has queued every
    //     mounted key and marked layout by then, whichever instance the
    //     ancestor hands down (a fresh `SliverTree` additionally runs
    //     [update], whose queue is the same set). Nothing is left to do.
    //
    // The parent-rebuild path does not reach this method at all:
    // `RenderObjectElement.update` calls the private `_performRebuild()`
    // (framework.dart:6813), not this override, so [update] owns its own
    // queueing.
    //
    // RULE: a future `markNeedsBuild()` on this element queues its own
    // keys at its own call site. Landing here queues nothing, and the
    // next layout finds every mounted row clean, because [createChild]
    // early-returns for an existing, non-dirty key.
  }

  /// Handles structural notifications from the controller.
  ///
  /// [affectedKeys] semantics (set by the controller):
  ///   - `null`: scope unknown; every mounted row may need refresh.
  ///     Queued lazily; consumed in [createChild] for retained rows.
  ///   - empty set: structural change occurred but no mounted row's
  ///     builder output changed (new rows first-build via [createChild],
  ///     removed rows go through [removeChild]); only relayout is
  ///     required. Nothing
  ///     is added to [_dirtyKeys]; avoiding this queue is what keeps an
  ///     external `ChangeNotifier` subscriber that rebuilds SliverTree's
  ///     ancestor from amplifying the empty-set notify into a refresh
  ///     sweep over off-screen descendants.
  ///   - non-empty set: queue exactly the listed mounted keys.
  void _onStructuralChange(Set<TKey>? affectedKeys) {
    renderObject.markNeedsLayout();

    if (affectedKeys == null) {
      _dirtyKeys.addAll(_children.keys);
      return;
    }

    if (affectedKeys.isEmpty) {
      return;
    }

    for (final key in affectedKeys) {
      if (_children.containsKey(key)) {
        _dirtyKeys.add(key);
      }
    }
  }

  /// Called on pure animation ticks (no structural change).
  ///
  /// Routes to [RenderObject.markNeedsLayout] for extent animations
  /// (enter/exit/bulk/op-group), because those change structural layout.
  ///
  /// Routes to [RenderObject.markNeedsPaint] for slide-only ticks: slide
  /// is paint-only; structural layout is unchanged and marking layout dirty
  /// would trigger an unnecessary relayout every frame.
  ///
  /// The completion tick of an extent animation fires **after** the
  /// controller has cleared its state (so [TreeController.hasActiveAnimations]
  /// is already false). We still need a final relayout to settle the final
  /// extent, which is why [_priorTickHadAnimations] is checked: if the
  /// previous tick saw active animations, the current tick is the settle
  /// tick and must relayout even though the flag is now false.
  ///
  /// Slide-only ticks are routed to [RenderObject.markNeedsPaint]: slides
  /// are paint-only by contract. The build window is computed at the
  /// install layout with overreach = max |delta| and only shrinks
  /// thereafter, so no new rows need building mid-slide, and scrolling
  /// during a slide triggers layout through the viewport anyway. A full
  /// relayout per slide tick would amplify the per-frame layout cost of
  /// every FLIP reorder.
  ///
  /// Layout IS marked on the slide settle transition
  /// (`_priorTickHadSlides && !hasSlides`): that one pass runs the ghost
  /// cleanup (Step 0a / 0b in the render object's performLayout,
  /// including the `clearAll`-when-idle branch). The slide engine makes
  /// the transition observable by firing one extra notify AFTER its
  /// settle-frame cleanup (the pre-cleanup notify still carries
  /// `hasActiveSlides == true` per the zero-delta-paint contract).
  void _onAnimationTick() {
    final c = widget.controller;
    final active = c.hasActiveAnimations;
    final hasSlides = c.hasActiveSlides;
    final hasFlipSlides = c.hasActiveFlipSlides;
    if (active || _priorTickHadAnimations) {
      // Extent animations (enter/exit/bulk/op-group) change structural
      // layout; _priorTickHadAnimations covers their settle tick, which
      // fires after the controller cleared its state.
      renderObject.markNeedsLayout();
    } else if ((_priorTickHadFlipSlides && !hasFlipSlides) ||
        (_priorTickHadSlides && !hasSlides)) {
      // Settle transition: one final layout for ghost cleanup.
      //
      // EITHER transition, deliberately, and this must stay a single
      // branch with an OR rather than two markNeedsLayout sites:
      //
      // - The FLIP disjunct is the one ghost cleanup needs. Without it, a
      //   FLIP settle under a held preview schedules nothing and settled
      //   ghosts survive the entire drag.
      // - The composed disjunct still covers a preview settling with no
      //   FLIP active (a drag release with no commit). Dropping it would
      //   leave that tick matching no branch at all, since the
      //   paint-only branch below also requires `hasSlides`, and the
      //   post-settle layout, whose end evicts the rows the slides kept
      //   (`RenderSliverTree._evictUnretainedChildren`), would disappear.
      //
      // With no preview in play the two disjuncts flip on the same tick,
      // so one branch means one layout and the exact per-slide layout
      // counts stay unchanged (pinned by `slide_paint_only_test.dart`).
      renderObject.markNeedsLayout();
    } else if (hasSlides) {
      if (c.composedSlideAbsDeltaBound > renderObject.admittedSlideBound) {
        // The composed offsets now reach further than the window the
        // last layout admitted against, so a row may be painting inside
        // the cache region from a structural position that was never
        // built (a make-room preview whose lift exceeds the cache
        // extent is the case that showed it: blank space where the
        // shifted rows belong). One layout re-admits. The preview's
        // contribution to the bound is TERMINAL, so a retarget costs
        // exactly this one layout, not one per tick.
        renderObject.markNeedsLayout();
      } else {
        // Pure slide tick: paint-only.
        renderObject.markNeedsPaint();
      }
    }
    _priorTickHadAnimations = active;
    _priorTickHadSlides = hasSlides;
    _priorTickHadFlipSlides = hasFlipSlides;
  }

  /// Called when a single node's data changed (via [TreeController.updateNode])
  /// without any structural mutation. Queues a targeted rebuild of just
  /// that row, consumed lazily by [createChild] during the next layout.
  void _onNodeDataChanged(TKey key) {
    // Node not mounted: nothing to refresh. Don't queue or schedule a
    // layout, otherwise we'd do a no-op pass for every off-screen update.
    if (!_children.containsKey(key)) return;
    _dirtyKeys.add(key);
    renderObject.markNeedsLayout();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TREE CHILD MANAGER
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void didStartLayout() {
    _inLayout = true;
  }

  @override
  void didFinishLayout() {
    _inLayout = false;
  }

  @override
  void createChild(TKey nodeId) {
    assert(_inLayout, 'createChild must be called during layout');
    final existing = _children[nodeId];
    // Three cases handled here:
    //   1. No existing element: build a fresh widget via [nodeBuilder].
    //   2. Existing element, queued as dirty by a prior update / notify:
    //      rebuild with a fresh widget so the row picks up any new state
    //      captured by the `nodeBuilder` closure or new controller data.
    //   3. Existing element, not dirty: no-op; this is the hot path
    //      every layout hits for already-mounted cache-region keys.
    final needsRefresh = existing != null && _dirtyKeys.remove(nodeId);
    if (existing != null && !needsRefresh) {
      return;
    }
    owner!.buildScope(this, () {
      final nodeData = widget.controller.getNodeData(nodeId);
      if (nodeData == null) {
        return;
      }
      final depth = widget.controller.getDepth(nodeId);
      Widget childWidget = widget.nodeBuilder(this, nodeId, depth);
      if (widget.addRepaintBoundaries) {
        childWidget = RepaintBoundary(child: childWidget);
      }
      final element = updateChild(existing, childWidget, nodeId);
      if (element != null) {
        _children[nodeId] = element;
      } else if (existing != null) {
        _children.remove(nodeId);
      }
    });
  }

  /// Drops the element of [nodeId], which deactivates it inside the
  /// render object's layout, so the frame's [BuildOwner.finalizeTree]
  /// disposes it before the next pointer event can reach it.
  @override
  void removeChild(TKey nodeId) {
    assert(_inLayout, 'removeChild must be called during layout');
    final element = _children.remove(nodeId);
    _dirtyKeys.remove(nodeId);
    if (element == null) {
      return;
    }
    owner!.buildScope(this, () {
      updateChild(element, null, nodeId);
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RENDER OBJECT CHILD MANAGEMENT
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void insertRenderObjectChild(RenderBox child, Object slot) {
    renderObject.insertChild(child, slot as TKey);
  }

  @override
  void moveRenderObjectChild(RenderBox child, Object oldSlot, Object newSlot) {
    // NodeIds don't change, this shouldn't happen
    assert(oldSlot == newSlot);
  }

  @override
  void removeRenderObjectChild(RenderBox child, Object slot) {
    renderObject.removeChild(child, slot as TKey);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ELEMENT TREE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final element in _children.values) {
      visitor(element);
    }
  }

  @override
  void forgetChild(Element child) {
    final nodeId = child.slot as TKey?;
    if (nodeId != null) {
      _children.remove(nodeId);
    }
    super.forgetChild(child);
  }
}
