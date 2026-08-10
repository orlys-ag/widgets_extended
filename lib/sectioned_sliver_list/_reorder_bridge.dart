/// The boundary between `SectionedReorderConfig`'s kind-paired members
/// and the tree layer's three singular controller callbacks.
///
/// This is the whole of the module's non-obvious reorder code: keys cross
/// wrapped (`SectionKey` / `ItemKey`) and must arrive at user callbacks
/// unwrapped, and the two-level invariant has to be enforced somewhere a
/// caller cannot widen it.
library;

import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import '../sliver_tree/tree_reorder_controller.dart';
import '_internal_keys.dart';
import 'sectioned_list_controller.dart';
import 'sectioned_reorder_config.dart';

/// Move an item to the end of the section above it.
///
/// Module-level and const, not built per row: `CustomSemanticsAction`
/// interns identifiers in static maps with no removal path, so a label
/// that varied per row would leak one entry per distinct string for the
/// life of the process.
const CustomSemanticsAction kMoveToPreviousSection = CustomSemanticsAction(
  label: "Move to previous section",
);

/// Move an item to the top of the section below it.
const CustomSemanticsAction kMoveToNextSection = CustomSemanticsAction(
  label: "Move to next section",
);

/// Builds and owns the single `TreeReorderController<SecKey<K>>` that
/// backs a sectioned list, translating between it and the config.
class SectionedReorderBridge<K extends Object, Section, Item> {
  SectionedReorderBridge({
    required this.controller,
    required SectionedReorderConfig<K, Section, Item> Function() configOf,
    required bool requireCallbacks,
    required TickerProvider vsync,
  }) : _configOf = configOf,
       _requireCallbacks = requireCallbacks {
    reorderController = TreeReorderController<SecKey<K>>(
      treeController: controller.treeController,
      vsync: vsync,
      canReorder: _canReorder,
      canAcceptDrop: _canAcceptDrop,
      onReorder: _onReorder,
      autoExpandDelay: _config.autoExpandDelay,
      autoScrollEdgeZone: _config.autoScrollEdgeZone,
      autoScrollMaxVelocity: _config.autoScrollMaxVelocity,
    );
  }

  final SectionedListController<K, Section, Item> controller;

  /// Read through a closure, not captured: the config's CONTENTS are live
  /// across rebuilds even though the controller's own policy fields are
  /// final and capture these forwarders once.
  ///
  /// The drag tunings (`autoExpandDelay`, `autoScrollEdgeZone`,
  /// `autoScrollMaxVelocity`) live on the controller's MUTABLE fields
  /// rather than behind these forwarders, so a changed value reaches it
  /// only when the owner calls [updateDragTunings].
  final SectionedReorderConfig<K, Section, Item> Function() _configOf;

  /// Whether a kind needs its callback to count as enabled. True in the
  /// declarative form, where the props are authoritative and a drop that
  /// nothing records is silently undone by the next diff. False in
  /// `.controlled`, where the controller IS the truth and the callbacks
  /// are informational.
  final bool _requireCallbacks;

  late final TreeReorderController<SecKey<K>> reorderController;

  /// The live config. Public because the renderer reads presentation off
  /// it: pairing a nullable `reorder` field beside a nullable `bridge`
  /// field invited them to disagree, and one of the two orders crashed.
  SectionedReorderConfig<K, Section, Item> get config {
    return _configOf();
  }

  SectionedReorderConfig<K, Section, Item> get _config {
    return config;
  }

  /// One instance for the lifetime of the bridge.
  ///
  /// A method TEAR-OFF is not `identical` across evaluations, so passing
  /// `bridge.semanticsActions` directly would hand the inherited scope a
  /// fresh closure on every build and rebuild every visible row on every
  /// ancestor rebuild, which is the storm the scope's identity gate
  /// exists to avoid.
  late final Map<CustomSemanticsAction, VoidCallback> Function(
    SecKey<K>,
    Map<CustomSemanticsAction, VoidCallback>,
  )
  semanticsActionsBuilder = semanticsActions;

  void dispose() {
    reorderController.dispose();
  }

  /// Pushes the config's drag tunings onto the controller's mutable
  /// fields. Owners call this from `didUpdateWidget`; each value is
  /// captured per drag session at drag start, so a change applies from
  /// the next drag rather than retuning a live one.
  void updateDragTunings() {
    final config = _config;
    reorderController
      ..autoExpandDelay = config.autoExpandDelay
      ..autoScrollEdgeZone = config.autoScrollEdgeZone
      ..autoScrollMaxVelocity = config.autoScrollMaxVelocity;
  }

  /// Whether this kind of drag is switched on at all. In the declarative
  /// form the flag alone cannot enable it.
  bool itemsEnabled() {
    final config = _config;
    if (!config.reorderItems) {
      return false;
    }
    return !_requireCallbacks || config.onItemReorder != null;
  }

  bool sectionsEnabled() {
    final config = _config;
    if (!config.reorderSections) {
      return false;
    }
    return !_requireCallbacks || config.onSectionReorder != null;
  }

  bool _canReorder(SecKey<K> key) {
    final config = _config;
    return switch (key) {
      ItemKey<K>(:final value) =>
        itemsEnabled() && (config.canDragItem?.call(value) ?? true),
      SectionKey<K>(:final value) =>
        sectionsEnabled() && (config.canDragSection?.call(value) ?? true),
    };
  }

  /// SHAPE first, then the caller. An item is legal only under a section;
  /// a section only at root; nothing under an item. A destination the
  /// invariant rejects is never offered to the caller's callback, so a
  /// caller can narrow but never widen.
  bool _canAcceptDrop({
    required SecKey<K> movingKey,
    SecKey<K>? newParent,
    int? index,
  }) {
    final config = _config;
    switch (movingKey) {
      case ItemKey<K>(:final value):
        if (newParent is! SectionKey<K>) {
          return false;
        }
        // A null index is a SHAPE-ONLY query, and the kind check above
        // has already answered it in full.
        // `TreeReorderConfig.canAcceptDrop` documents that a policy may
        // do exactly this.
        //
        // An `assert(index != null)` was tried here and removed, because
        // it was wrong three ways: it contradicted that public contract,
        // it contradicted this very comment, and its message ("bypasses
        // canAcceptItemDrop") is false whenever that policy is unset --
        // the common case, since `?? true` below makes the two paths
        // identical. A tripwire that fires when nothing is wrong is one
        // that people learn to delete.
        if (index == null) {
          return true;
        }
        return config.canAcceptItemDrop?.call(value, newParent.value, index) ??
            true;
      case SectionKey<K>(:final value):
        if (newParent != null) {
          return false;
        }
        // Shape-only query, already answered in full above. See the
        // item branch for why this is not asserted.
        if (index == null) {
          return true;
        }
        return config.canAcceptSectionDrop?.call(value, index) ?? true;
    }
  }

  /// Contributes the two cross-section moves to an ITEM row.
  ///
  /// Under the two-level invariant the built-in four collapse to "move
  /// up" and "move down" within the item's own section: "move out" asks
  /// whether an item may live at root, and "move into previous sibling"
  /// whether it may nest under another item, and both are refused. So
  /// cross-section reparenting would be reachable by pointer and by
  /// nothing else, which WCAG 2.2 SC 2.5.7 forbids.
  ///
  /// Section rows get nothing: up and down at root is already their
  /// complete legal vocabulary.
  Map<CustomSemanticsAction, VoidCallback> semanticsActions(
    SecKey<K> key,
    Map<CustomSemanticsAction, VoidCallback> builtIn,
  ) {
    if (key is! ItemKey<K>) {
      return builtIn;
    }
    final section = controller.treeController.getParent(key);
    if (section is! SectionKey<K>) {
      return builtIn;
    }
    // Non-allocating throughout: this runs on EVERY item row build, and
    // the list-shaped queries copy a whole sibling list to be indexed
    // once and discarded.
    final tree = controller.treeController;
    final sectionIndex = tree.getIndexInParent(section);
    if (sectionIndex < 0) {
      return builtIn;
    }
    final config = _config;
    final sectionCount = tree.liveRootCount;
    final previous = sectionIndex > 0
        ? tree.liveSiblingAt(null, sectionIndex - 1)
        : null;
    final next = sectionIndex < sectionCount - 1
        ? tree.liveSiblingAt(null, sectionIndex + 1)
        : null;

    final allowPrevious =
        previous is SectionKey<K> &&
        (config.canAcceptItemDrop?.call(
              key.value,
              previous.value,
              tree.liveChildCount(previous),
            ) ??
            true);
    final allowNext =
        next is SectionKey<K> &&
        (config.canAcceptItemDrop?.call(key.value, next.value, 0) ?? true);
    if (!allowPrevious && !allowNext) {
      // Nothing to contribute: hand back the original rather than a copy.
      return builtIn;
    }

    final actions = <CustomSemanticsAction, VoidCallback>{...builtIn};
    if (allowPrevious) {
      actions[kMoveToPreviousSection] = () {
        _moveToSection(key.value, before: true);
      };
    }
    if (allowNext) {
      actions[kMoveToNextSection] = () {
        _moveToSection(key.value, before: false);
      };
    }
    return actions;
  }

  /// Recomputes the destination at INVOCATION time, so a stale action
  /// degrades to a no-op rather than a wrong move.
  ///
  /// The indices are deliberately asymmetric: previous APPENDS to the
  /// section above, next PREPENDS to the one below, so the row lands
  /// adjacent to where it was in document order and repeated invocations
  /// walk the list monotonically. Symmetric index 0 would teleport it to
  /// the top of the section above. It also matches the built-ins, where
  /// "move out" inserts after the parent and "move into previous"
  /// appends. Not a strict inverse, deliberately.
  void _moveToSection(K itemKey, {required bool before}) {
    final tree = controller.treeController;
    final section = tree.getParent(ItemKey<K>(itemKey));
    if (section is! SectionKey<K>) {
      return;
    }
    final index = tree.getIndexInParent(section);
    final targetIndex = before ? index - 1 : index + 1;
    if (index < 0 || targetIndex < 0 || targetIndex >= tree.liveRootCount) {
      return;
    }
    final targetKey = tree.liveSiblingAt(null, targetIndex);
    if (targetKey is! SectionKey<K>) {
      return;
    }
    final target = targetKey.value;
    // COMMIT FIRST, then reveal. Expanding up front mutated structure
    // even when the move was then refused, and `moveTo` refuses on four
    // paths, one of which is "a drag is in flight" -- reachable here
    // because the Semantics wrapper deliberately stays outside the
    // Opacity that hides the dragged row, so these actions are live for
    // the whole gesture.
    final moved = reorderController.moveTo(
      ItemKey<K>(itemKey),
      targetKey,
      index: before ? tree.liveChildCount(targetKey) : 0,
    );
    if (!moved) {
      return;
    }
    // Reveal the destination, as the pointer path does on dwell.
    if (!controller.isExpanded(target)) {
      controller.expandSection(target, animate: false);
    }
  }

  void _onReorder(SecKey<K> key, SecKey<K>? newParent, int index) {
    final config = _config;
    if (key is ItemKey<K> && newParent is SectionKey<K>) {
      config.onItemReorder?.call(key.value, newParent.value, index);
      return;
    }
    if (key is SectionKey<K> && newParent == null) {
      config.onSectionReorder?.call(key.value, index);
      return;
    }
    // Any other pairing means the shape policy was bypassed. Assert
    // rather than silently dropping the report, which is the failure mode
    // this whole channel exists to eliminate.
    assert(
      false,
      "SectionedReorderBridge received an impossible commit: "
      "$key under $newParent. The two-level invariant should have "
      "refused this destination.",
    );
  }
}
