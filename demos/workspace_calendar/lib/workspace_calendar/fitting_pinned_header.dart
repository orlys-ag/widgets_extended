/// A header sliver that pins only while it leaves room for the content
/// that scrolls under it.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A sliver that keeps its box [child] at its viewport's leading edge once
/// the content before it has scrolled away, as [PinnedHeaderSliver] does,
/// while the child takes at most [maxViewportFraction] of the viewport's
/// main-axis extent; a larger child scrolls with the content, as in a
/// [SliverToBoxAdapter].
///
/// The choice is made at each layout from the child's laid-out size, so a
/// child that grows, or a viewport that shrinks, such as under a keyboard,
/// takes effect in the same frame. Pinning changes only where the child
/// paints: the content after it lays out in the same place either way, so
/// a child that stops pinning uncovers that content without moving it.
///
/// In a shrink-wrapping viewport the extent compared is the most the
/// viewport may take: [RenderShrinkWrappingViewport] passes its maximum
/// main-axis constraint as [SliverConstraints.viewportMainAxisExtent].
class FittingPinnedHeaderSliver extends StatelessWidget {
  /// A sliver that pins [child] while it takes at most
  /// [maxViewportFraction] of the viewport's extent.
  const FittingPinnedHeaderSliver({
    super.key,
    this.maxViewportFraction = 0.5,
    this.child,
  }) : assert(maxViewportFraction >= 0.0 && maxViewportFraction <= 1.0);

  /// The largest share of the viewport's main-axis extent, from 0 to 1,
  /// that [child] may take and still pin.
  final double maxViewportFraction;

  /// The header.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // The semantics of [PinnedHeaderSliver]: the header is its own node, so
    // that its children can be excluded from scrolling while it pins.
    return _FittingPinnedHeaderSliver(
      maxViewportFraction: maxViewportFraction,
      child: Semantics(container: true, explicitChildNodes: true, child: child),
    );
  }
}

class _FittingPinnedHeaderSliver extends SingleChildRenderObjectWidget {
  const _FittingPinnedHeaderSliver({
    required this.maxViewportFraction,
    super.child,
  });

  final double maxViewportFraction;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFittingPinnedHeaderSliver(
      maxViewportFraction: maxViewportFraction,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFittingPinnedHeaderSliver renderObject,
  ) {
    renderObject.maxViewportFraction = maxViewportFraction;
  }
}

class _RenderFittingPinnedHeaderSliver extends RenderSliverSingleBoxAdapter {
  _RenderFittingPinnedHeaderSliver({required double maxViewportFraction})
    : _maxViewportFraction = maxViewportFraction;

  double get maxViewportFraction {
    return _maxViewportFraction;
  }

  double _maxViewportFraction;

  set maxViewportFraction(double value) {
    if (value == _maxViewportFraction) {
      return;
    }
    _maxViewportFraction = value;
    markNeedsLayout();
  }

  /// Whether the last layout pinned the child.
  bool _pins = false;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    final constraints = this.constraints;
    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final childExtent = switch (constraints.axis) {
      Axis.horizontal => child.size.width,
      Axis.vertical => child.size.height,
    };
    final pins =
        childExtent <= constraints.viewportMainAxisExtent * maxViewportFraction;
    if (pins != _pins) {
      _pins = pins;
      markNeedsSemanticsUpdate();
    }
    final cacheExtent = calculateCacheOffset(
      constraints,
      from: 0.0,
      to: childExtent,
    );
    if (pins) {
      // The geometry of [PinnedHeaderSliver]: the child paints from the
      // sliver's leading edge at any scroll offset, while the layout extent
      // shrinks as the content scrolls past, so what follows moves under
      // the child; its extent obstructs whatever a reveal brings into view
      // after it.
      geometry = SliverGeometry(
        scrollExtent: childExtent,
        paintOrigin: constraints.overlap,
        paintExtent: math.min(
          childExtent,
          constraints.remainingPaintExtent - constraints.overlap,
        ),
        layoutExtent: (childExtent - constraints.scrollOffset).clamp(
          0.0,
          constraints.remainingPaintExtent,
        ),
        maxPaintExtent: childExtent,
        maxScrollObstructionExtent: childExtent,
        cacheExtent: cacheExtent,
        hasVisualOverflow: true,
      );
      (child.parentData! as SliverPhysicalParentData).paintOffset = Offset.zero;
    } else {
      // The geometry of [RenderSliverToBoxAdapter].
      final paintedChildSize = calculatePaintOffset(
        constraints,
        from: 0.0,
        to: childExtent,
      );
      geometry = SliverGeometry(
        scrollExtent: childExtent,
        paintExtent: paintedChildSize,
        cacheExtent: cacheExtent,
        maxPaintExtent: childExtent,
        hitTestExtent: paintedChildSize,
        hasVisualOverflow:
            childExtent > constraints.remainingPaintExtent ||
            constraints.scrollOffset > 0.0,
      );
      setChildParentData(child, constraints, geometry!);
    }
  }

  @override
  double childMainAxisPosition(RenderBox child) {
    if (_pins) {
      return 0.0;
    }
    return super.childMainAxisPosition(child);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final geometry = this.geometry;
    if (_pins &&
        geometry != null &&
        geometry.layoutExtent < geometry.scrollExtent) {
      config.addTagForChildren(RenderViewport.excludeFromScrolling);
    }
  }
}
