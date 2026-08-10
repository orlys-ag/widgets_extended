/// Drag-and-drop configuration for [SectionedSliverList].
///
/// Everything pairs by KIND. The module has exactly two kinds of drag,
/// and its section and item key domains share one user-facing type
/// parameter `K` (kept disjoint internally by the wrappers in
/// `_internal_keys.dart`), so a single callback taking a bare `K` could
/// not say which one it was being asked about, and when the same value
/// names both it could not be answered at all.
library;

import 'package:flutter/widgets.dart';

import '../sliver_tree/tree_drag_handle.dart';
import 'views.dart';

/// Builds the floating drag preview for a section header.
typedef SectionDragProxyBuilder<K extends Object, Section, Item> =
    Widget Function(
      BuildContext context,
      SectionView<K, Section, Item> view,
      Widget? rowChild,
    );

/// Builds the floating drag preview for an item row.
typedef ItemDragProxyBuilder<K extends Object, Section, Item> =
    Widget Function(
      BuildContext context,
      ItemView<K, Section, Item> view,
      Widget? rowChild,
    );

/// Enables and shapes reordering for a [SectionedSliverList].
///
/// The module installs its own drop policy enforcing the two-level
/// invariant (items only under sections, sections only at root, nothing
/// under an item). The `canAccept*` callbacks compose with it and can
/// only NARROW it: a shape the module rejects is never offered to them.
class SectionedReorderConfig<K extends Object, Section, Item> {
  const SectionedReorderConfig({
    this.reorderItems = true,
    this.reorderSections = false,
    this.onItemReorder,
    this.onSectionReorder,
    this.canDragItem,
    this.canDragSection,
    this.canAcceptItemDrop,
    this.canAcceptSectionDrop,
    this.buildDefaultItemDragHandles = true,
    this.buildDefaultSectionDragHandles = true,
    this.showDragProxy = true,
    this.itemDragProxyBuilder,
    this.sectionDragProxyBuilder,
    this.hapticsOnDrag = false,
    this.autoExpandDelay = const Duration(milliseconds: 700),
    this.autoScrollEdgeZone = 48.0,
    this.autoScrollMaxVelocity = 1200.0,
  });

  /// Whether items can be dragged. Items-only is the zero-configuration
  /// shape, so this defaults on and [reorderSections] defaults off.
  ///
  /// In the DECLARATIVE form a kind is enabled only when its flag is set
  /// AND its callback exists. The flag alone cannot enable it: there, a
  /// drop nothing records is silently undone by the next diff, so a
  /// half-configured kind refuses to start instead. In `.controlled` the
  /// flag alone is enough, because the controller is the source of truth
  /// and there is nothing to record.
  final bool reorderItems;

  /// Whether whole sections can be reordered. See [reorderItems].
  final bool reorderSections;

  /// Reports a committed item move. `index` is live-space and names the
  /// position among [toSection]'s items AFTER the item has been removed
  /// from wherever it was.
  final void Function(K itemKey, K toSection, int index)? onItemReorder;

  /// Reports a committed section move, with its live-space final index
  /// among the sections.
  final void Function(K sectionKey, int index)? onSectionReorder;

  /// Items for which this returns false cannot be dragged.
  ///
  /// A refusal DISARMS the row's handles: their `onPointerDown` is null,
  /// so no recognizer is built and no arena is joined. The row's widget
  /// shape is identical either way, so toggling this never re-inflates
  /// the row.
  final bool Function(K itemKey)? canDragItem;

  /// Sections for which this returns false cannot be dragged.
  final bool Function(K sectionKey)? canDragSection;

  /// Narrows where an item may land. Only consulted for destinations the
  /// two-level invariant already allows, so it never has to re-check that
  /// the destination is a section.
  ///
  /// Also shapes the drop zones on section headers, through the same
  /// `index: 0` probe documented on `TreeReorderConfig.canAcceptDrop`. A
  /// policy that pins a section's first slot withdraws that header's
  /// `into` zone; drops at slots 1..n land by pointing at the section's
  /// items rather than its header.
  final bool Function(K itemKey, K toSection, int index)? canAcceptItemDrop;

  /// Narrows where a section may land among the sections.
  final bool Function(K sectionKey, int index)? canAcceptSectionDrop;

  /// Whether the module wraps each ITEM row in a
  /// [TreeDelayedDragHandle], making the whole row draggable after a long
  /// press. See `TreeReorderConfig.buildDefaultDragHandles`, which this
  /// mirrors.
  ///
  /// Set false and place your own [TreeDragHandle] in `itemBuilder`. The
  /// row is still wrapped either way, so the hide, the drop targeting and
  /// the semantics actions are unaffected.
  final bool buildDefaultItemDragHandles;

  /// The same, for section headers.
  ///
  /// Genuinely per-kind rather than merely symmetric: headers and items
  /// are different affordances, and "drag headers by a grip, drag items
  /// by long-press" is the shape most sectioned lists want, which is
  /// exactly `buildDefaultSectionDragHandles: false` with a
  /// [TreeDragHandle] in `headerBuilder`.
  final bool buildDefaultSectionDragHandles;

  /// Whether to float a preview of the dragged row under the pointer.
  final bool showDragProxy;

  /// Builds the item drag preview. Paired rather than singular because
  /// the tree layer's builder receives the internal wrapped key, which is
  /// not a type a caller can name.
  final ItemDragProxyBuilder<K, Section, Item>? itemDragProxyBuilder;

  /// Builds the section drag preview. See [itemDragProxyBuilder].
  final SectionDragProxyBuilder<K, Section, Item>? sectionDragProxyBuilder;

  /// Opt-in lift and slot-change haptics.
  final bool hapticsOnDrag;

  /// Hover-to-open delay for a collapsed section. Live on rebuild;
  /// captured once per drag session, so a change applies from the next
  /// drag.
  final Duration? autoExpandDelay;

  /// Autoscroll edge band. Live on rebuild; captured per drag session.
  final double autoScrollEdgeZone;

  /// Peak autoscroll velocity. Live on rebuild; captured per drag
  /// session.
  final double autoScrollMaxVelocity;
}
