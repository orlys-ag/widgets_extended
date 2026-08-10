/// Views handed to `headerBuilder` / `itemBuilder` callbacks.
///
/// Read these properties directly in your builder: a row is rebuilt
/// whenever its own rendered inputs change (expansion, payload, item
/// count, sibling position), so no wrapper widget or extra subscription
/// is needed to keep them fresh.
library;

import 'sectioned_list_controller.dart';

/// Rich view of a visible section header passed to a header builder.
class SectionView<K extends Object, Section, Item> {
  const SectionView({
    required this.key,
    required this.section,
    required this.itemCount,
    required this.isExpanded,
    required this.isCollapsible,
    required this.controller,
  });

  /// Unique identifier for this section.
  final K key;

  /// User payload for the section header.
  final Section section;

  /// Total items currently belonging to this section, regardless of
  /// expansion state. Visible count is `isExpanded ? itemCount : 0`.
  final int itemCount;

  /// Whether the section is currently expanded.
  final bool isExpanded;

  /// Whether the user can toggle this section's expansion. `false`
  /// when the parent widget was created with `collapsible: false`.
  ///
  /// Advisory only — the [expand] / [collapse] / [toggle] shortcuts on
  /// this view always pass through to the controller regardless of this
  /// flag. Use it to decide whether to render a chevron, not to gate
  /// state mutations.
  final bool isCollapsible;

  /// The controller backing this view, available as an escape hatch.
  /// Convenience methods on this view delegate to the controller.
  final SectionedListController<K, Section, Item> controller;

  /// Expands this section.
  void expand({bool animate = true}) {
    controller.expandSection(key, animate: animate);
  }

  /// Collapses this section.
  void collapse({bool animate = true}) {
    controller.collapseSection(key, animate: animate);
  }

  /// Toggles expansion.
  void toggle({bool animate = true}) {
    controller.toggleSection(key, animate: animate);
  }

  /// Replaces this section's payload. Asserts that the section still
  /// exists.
  void update(Section section) {
    controller.updateSection(key, section);
  }

  /// Removes this section (and all its items).
  void remove({bool animate = true}) {
    controller.removeSection(key, animate: animate);
  }

  /// Adds [item] under this section. Forwards to
  /// [SectionedListController.addItem].
  void addItem(Item item, {int? index, bool animate = true}) {
    controller.addItem(item, toSection: key, index: index, animate: animate);
  }
}

/// Rich view of a visible item passed to an item builder.
class ItemView<K extends Object, Section, Item> {
  const ItemView({
    required this.key,
    required this.item,
    required this.sectionKey,
    required this.section,
    required this.indexInSection,
    required this.controller,
  });

  /// Unique identifier for this item.
  final K key;

  /// User payload.
  final Item item;

  /// Identifier of the section this item belongs to.
  final K sectionKey;

  /// Section payload, resolved for convenience.
  final Section section;

  /// Position among siblings in the section, 0-based, in live-list
  /// space (skipping pending-deletion siblings).
  final int indexInSection;

  /// The controller backing this view.
  final SectionedListController<K, Section, Item> controller;

  /// Replaces this item's payload. Asserts that the item still exists.
  void update(Item item) {
    controller.updateItem(key, item);
  }

  /// Removes this item.
  void remove({bool animate = true}) {
    controller.removeItem(key, animate: animate);
  }

  /// Moves this item to [section] and/or [index]. Forwards directly to
  /// [SectionedListController.moveItem]:
  ///
  ///   - [section] non-null: reparents under that section (at [index], or
  ///     appended when [index] is null)
  ///   - [section] null, [index] non-null: reorders within the current
  ///     section
  ///   - both null: no-op
  ///
  /// Both forms run a paint-only FLIP slide when [animate] is true (the
  /// default). See [SectionedListController.moveItem] for exactly what
  /// slides on each path.
  void moveTo({K? section, int? index, bool animate = true}) {
    controller.moveItem(
      key,
      toSection: section,
      index: index,
      animate: animate,
    );
  }
}
