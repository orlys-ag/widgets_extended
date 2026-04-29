/// Immutable inputs for declarative `SectionedSliverList` construction.
library;

class SectionInput<SKey, IKey, Section, Item> {
  SectionInput({
    required this.key,
    required this.section,
    Iterable<ItemInput<IKey, Item>> items = const [],
  }) : items = List<ItemInput<IKey, Item>>.unmodifiable(items);

  /// Stable identity for this section across rebuilds.
  final SKey key;

  /// User payload for the section header.
  final Section section;

  /// Items belonging to this section, in render order.
  ///
  /// The constructor accepts any `Iterable` (allowing direct hand-off of
  /// `where`/`map` chains without a `.toList()`) and materializes it once
  /// into an unmodifiable list. The materialization is necessary because
  /// the underlying tree sync needs random access.
  final List<ItemInput<IKey, Item>> items;
}

class ItemInput<IKey, Item> {
  const ItemInput({required this.key, required this.item});

  /// Stable identity for this item across rebuilds.
  final IKey key;

  /// User payload.
  final Item item;
}
