/// Core types for the sliver tree system.
library;

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
