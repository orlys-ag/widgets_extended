/// Core types for the sliver tree system.
library;

import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart' show AnimationController, Curve, Curves;
import 'package:flutter/rendering.dart' show ParentData;

// ════════════════════════════════════════════════════════════════════════════
// ANIMATION TYPES
// ════════════════════════════════════════════════════════════════════════════

/// The type of animation a node is currently undergoing.
enum AnimationType {
  /// Node is appearing (from insert or parent expand).
  entering,

  /// Node is disappearing (from remove or parent collapse).
  exiting,

  /// Node is sliding from an old scroll-space offset toward its new one
  /// (FLIP animation on reorder). Paint-only: structural extent is unchanged.
  sliding,
}

/// How [TreeController.animateScrollToKey] handles ancestors of the target
/// key that are currently collapsed.
enum AncestorExpansionMode {
  /// Do not expand any ancestors. If any ancestor of the target is
  /// collapsed, [TreeController.animateScrollToKey] returns false without
  /// scrolling.
  none,

  /// Expand every collapsed ancestor synchronously (no animation) before
  /// starting the scroll. The layout settles immediately, then the scroll
  /// animates to the final position.
  immediate,

  /// Animate the expansion of collapsed ancestors and run the scroll
  /// concurrently with it. Each animation tick, the scroll tracks the
  /// target's current (animated) offset so it stays synchronized with
  /// the layout as ancestors grow.
  animated,
}

/// Animation state for a single node (standalone animations only).
///
/// Only nodes that are actively animating via individual expand/collapse have
/// an [AnimationState]. Bulk operations (expandAll/collapseAll) track nodes
/// directly in [AnimationGroup] sets without creating AnimationState objects.
/// Once animation completes, the state is removed.
class AnimationState {
  AnimationState({
    required this.type,
    required this.startExtent,
    required this.targetExtent,
    this.progress = 0.0,
    this.triggeringAncestorId,
    this.speedMultiplier = 1.0,
  }) : currentExtent = startExtent;

  /// The type of animation.
  final AnimationType type;

  /// The extent (height) at animation start. Mutable to allow updates
  /// when the actual size is measured.
  double startExtent;

  /// The extent (height) at animation end. Mutable to allow updates
  /// when the actual size is measured.
  double targetExtent;

  /// Animation progress from 0.0 to 1.0.
  double progress;

  /// The interpolated current extent.
  double currentExtent;

  /// If this animation was triggered by an ancestor expanding/collapsing,
  /// this is that ancestor's ID. Used to coordinate grouped animations.
  final Object? triggeringAncestorId;

  /// Speed multiplier for proportional timing on cross-group transitions.
  /// Values > 1.0 make the animation complete proportionally faster.
  final double speedMultiplier;

  /// Whether this animation has completed.
  bool get isComplete => progress >= 1.0;

  /// Updates [currentExtent] based on [progress] and an optional [curve].
  void updateExtent([Curve curve = Curves.linear]) {
    final t = curve.transform(progress.clamp(0.0, 1.0));
    currentExtent = lerpDouble(startExtent, targetExtent, t)!;
  }

  @override
  String toString() =>
      "AnimationState($type, progress: ${progress.toStringAsFixed(2)}, "
      "extent: ${currentExtent.toStringAsFixed(1)})";
}

/// Slide animation state for a single node in a FLIP-style reorder.
///
/// Unlike [AnimationState], which interpolates **extent** (size) and is
/// applied at layout, [SlideAnimation] interpolates **offset delta** and is
/// applied at paint. The node's structural position is always its
/// post-mutation offset; [currentDelta] shifts only the painted pixels so
/// the node visually slides from its old position toward its new one.
///
/// [startDelta] = old scroll-space offset - new scroll-space offset (the
/// distance the node appears to travel). [currentDelta] = lerp(startDelta,
/// 0, curve(progress)); when progress reaches 1, currentDelta is snapped
/// to exactly 0.0 (see [TreeController]'s slide tick handler).
class SlideAnimation<TKey> {
  SlideAnimation({
    required this.startDelta,
    required this.curve,
    this.progress = 0.0,
  }) : currentDelta = startDelta;

  /// Initial scroll-space delta: old painted offset minus new structural
  /// offset. Positive means the node appears above its final position at
  /// t=0; negative means below.
  double startDelta;

  /// Animation progress from 0.0 to 1.0. Driven by a shared slide
  /// [AnimationController] in [TreeController].
  double progress;

  /// The curve applied to the progress when computing [currentDelta].
  Curve curve;

  /// The interpolated current delta, applied at paint time as a vertical
  /// translation. Snapped to exactly 0.0 at completion.
  double currentDelta;

  /// Whether this animation has completed.
  bool get isComplete => progress >= 1.0;
}

/// Shared animation controller for bulk expand/collapse operations.
///
/// Uses an [AnimationController] for smooth forward/reverse transitions.
/// - controller.value represents visibility: 0 = hidden, 1 = visible
/// - forward() for expanding, reverse() for collapsing
/// - Interrupting just changes direction, value continues smoothly
class AnimationGroup<TKey> {
  AnimationGroup({
    required this.controller,
    required this.curve,
  });

  /// The animation controller driving this group.
  final AnimationController controller;

  /// The curve applied to the animation.
  final Curve curve;

  /// Gets the curved animation value.
  double get value => curve.transform(controller.value);

  /// Keys of nodes in this animation group.
  /// extent = full * value for all members.
  final Set<TKey> members = {};

  /// Keys that should be removed from visible order when animation
  /// completes at value = 0 (i.e., nodes that are collapsing out).
  final Set<TKey> pendingRemoval = {};

  /// Whether this group has any members.
  bool get isEmpty => members.isEmpty;

  /// Total member count.
  int get memberCount => members.length;

  /// Disposes the animation controller.
  void dispose() {
    controller.dispose();
  }
}

/// Per-node extent data within an [OperationGroup].
///
/// Convention: [startExtent] corresponds to controller value = 0 (collapsed),
/// [targetExtent] corresponds to controller value = 1 (expanded).
/// - Fresh expand: startExtent = 0, targetExtent = full extent
/// - Nodes joining mid-animation: startExtent = 0, targetExtent = captured extent
class NodeGroupExtent {
  NodeGroupExtent({required this.startExtent, required this.targetExtent});

  /// Extent when the controller value is 0 (collapsed state).
  double startExtent;

  /// Extent when the controller value is 1 (expanded state).
  /// A value of -1.0 means unknown (will be resolved from measured size).
  double targetExtent;

  /// Computes the interpolated extent for the given curved value.
  ///
  /// If [targetExtent] is unknown (-1.0), uses [fullExtent] proportionally.
  /// Otherwise lerps between [startExtent] and [targetExtent].
  double computeExtent(double curvedValue, double fullExtent) {
    if (targetExtent == -1.0) {
      // Unknown target: use proportional full extent
      return fullExtent * curvedValue;
    }
    return lerpDouble(startExtent, targetExtent, curvedValue)!;
  }
}

/// Animation group for a single expand/collapse operation.
///
/// Each call to [TreeController.expand] or [TreeController.collapse] creates
/// an [OperationGroup] with its own [AnimationController]. This provides
/// automatic proportional timing on reversal — collapsing a 60%-done expand
/// takes 60% of the duration, not 100%.
class OperationGroup<TKey> {
  OperationGroup({
    required this.controller,
    required this.curve,
    required this.operationKey,
  });

  /// The animation controller driving this group.
  final AnimationController controller;

  /// The curve applied to the animation.
  final Curve curve;

  /// The node whose expand/collapse created this group.
  final TKey operationKey;

  /// Gets the curved animation value.
  double get curvedValue => curve.transform(controller.value);

  /// Per-node extent data for members of this group.
  final Map<TKey, NodeGroupExtent> members = {};

  /// Keys that should be removed from visible order when animation
  /// completes at value = 0 (nodes that are collapsing out).
  final Set<TKey> pendingRemoval = {};

  /// Disposes the animation controller.
  void dispose() {
    controller.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// NODE DATA
// ════════════════════════════════════════════════════════════════════════════

/// User-provided data for a tree node.
///
/// This is a simple wrapper that holds the node's unique ID and arbitrary data.
/// The tree controller manages the structural relationships (parent, children, depth).
class TreeNode<TKey, TData> {
  const TreeNode({required this.key, required this.data});

  /// Unique identifier for this node.
  final TKey key;

  /// User payload.
  final TData data;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TreeNode<TKey, TData> &&
            key == other.key &&
            data == other.data;
  }

  @override
  int get hashCode {
    return Object.hash(key, data);
  }

  @override
  String toString() {
    return "TreeNode(key: $key, data: $data)";
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PARENT DATA
// ════════════════════════════════════════════════════════════════════════════

/// Parent data for children of [RenderSliverTree].
///
/// Stores layout information computed during [RenderSliverTree.performLayout].
class SliverTreeParentData extends ParentData {
  /// The node ID this child represents.
  Object? nodeId;

  /// Offset from the start of the sliver's scroll extent.
  double layoutOffset = 0.0;

  /// Horizontal indent based on node depth.
  double indent = 0.0;

  /// The visible extent (height) of this child, accounting for animation.
  /// May be less than the child's actual size during enter/exit animations.
  double visibleExtent = 0.0;

  @override
  String toString() {
    return "SliverTreeParentData(nodeId: $nodeId, "
        "offset: $layoutOffset, indent: $indent, "
        "visibleExtent: $visibleExtent)";
  }
}

/// Snapshot of the controller's bulk-animation state at a single point in
/// time, fetched as one unit so render-layer hot paths can avoid the four
/// separate getter calls (`isBulkAnimating`, `bulkAnimationValue`,
/// `bulkAnimationGeneration`, `isBulkMember`) that would otherwise be
/// needed each layout.
///
/// `isValid` is true exactly when a bulk animation group exists and has
/// active members. Read [value] / [generation] / [containsMember] only on
/// a valid snapshot — on an invalid snapshot they hold zero defaults.
class BulkAnimationData<TKey> {
  const BulkAnimationData._({
    required this.isValid,
    required this.value,
    required this.generation,
    required this.memberCount,
    required Set<TKey>? members,
    required Set<TKey>? pendingRemoval,
    required Uint8List? bulkMemberByNid,
  }) : _members = members,
       _pendingRemoval = pendingRemoval,
       _bulkMemberByNid = bulkMemberByNid;

  static const BulkAnimationData<Never> _inactiveSentinel =
      BulkAnimationData<Never>._(
        isValid: false,
        value: 0.0,
        generation: 0,
        memberCount: 0,
        members: null,
        pendingRemoval: null,
        bulkMemberByNid: null,
      );

  /// The "no bulk animation active" snapshot. Returns a const-shared
  /// sentinel cast to [TKey] — no allocation per call. Safe to cache once
  /// per controller. Soundness: every field on the sentinel that depends
  /// on [TKey] is null, so [containsMember] never inspects the cast set.
  static BulkAnimationData<TKey> inactive<TKey>() =>
      _inactiveSentinel as BulkAnimationData<TKey>;

  /// Constructs a snapshot from the controller's current bulk state.
  /// Internal use only — call [TreeController.bulkAnimationData]. Holds
  /// references to the underlying sets; does not copy or union them, so
  /// no per-frame allocation beyond the snapshot record itself.
  static BulkAnimationData<TKey> snapshot<TKey>({
    required double value,
    required int generation,
    required Set<TKey> members,
    required Set<TKey> pendingRemoval,
    required Uint8List bulkMemberByNid,
  }) {
    return BulkAnimationData<TKey>._(
      isValid: true,
      value: value,
      generation: generation,
      // Mirrors AnimationGroup.memberCount semantics — the count of
      // currently-animating bulk members. NOT a union with pendingRemoval:
      // collapse paths populate both sets with the SAME keys (a member
      // that is also marked for post-animation removal), so summing the
      // two would double-count. Callers that need to know whether a
      // specific key is tracked should call `containsMember` instead.
      memberCount: members.length,
      members: members,
      pendingRemoval: pendingRemoval,
      bulkMemberByNid: bulkMemberByNid,
    );
  }

  /// Whether a bulk animation group is currently active. When false, every
  /// other field carries a zero / empty default.
  final bool isValid;

  /// Curved animation value (0..1) for the bulk group. Zero on an invalid
  /// snapshot.
  final double value;

  /// Monotonic counter that bumps whenever the bulk group is created,
  /// destroyed, or its member set changes. Render-layer caches keyed by
  /// position-indexed cumulatives use this as the staleness signature.
  final int generation;

  /// Live member count on the source group — mirrors
  /// `AnimationGroup.memberCount`. **Does not** add pendingRemoval, since
  /// collapse paths populate both sets with overlapping keys (the
  /// to-be-removed members are also live during the animation). Callers
  /// that need a per-key membership check should use [containsMember].
  final int memberCount;

  final Set<TKey>? _members;
  final Set<TKey>? _pendingRemoval;
  final Uint8List? _bulkMemberByNid;

  /// Whether [key] is a member of the bulk group (in either the live
  /// member set or the pending-removal set). Always false on an invalid
  /// snapshot.
  bool containsMember(TKey key) {
    final m = _members;
    if (m != null && m.contains(key)) return true;
    final p = _pendingRemoval;
    return p != null && p.contains(key);
  }

  /// Nid-keyed equivalent of [containsMember]: O(1) array read instead of
  /// HashMap probe. Always returns false on an invalid snapshot. Caller
  /// must guarantee [nid] is live.
  bool containsMemberNid(int nid) {
    final mirror = _bulkMemberByNid;
    if (mirror == null) return false;
    if (nid < 0 || nid >= mirror.length) return false;
    return mirror[nid] != 0;
  }
}

/// Computed sticky header position for a single node.
///
/// Created during layout, consumed during paint and hit-test.
class StickyHeaderInfo<TKey> {
  StickyHeaderInfo({
    required this.nodeId,
    required this.pinnedY,
    required this.extent,
    required this.indent,
  });

  /// The node ID of the sticky header.
  final TKey nodeId;

  /// Y offset relative to the viewport top where this header paints.
  final double pinnedY;

  /// Full (non-animated) extent of the header.
  final double extent;

  /// Horizontal indent for this header's depth.
  final double indent;
}
