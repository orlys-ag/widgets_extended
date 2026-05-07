/// Internal sealed wrapper types used to keep section keys, item keys,
/// section payloads, and item payloads in disjoint domains within a
/// single underlying [TreeController].
///
/// Not exported from the package barrel.
///
/// The wrappers are necessary because `SectionedSliverList` allows the
/// section-key type and the item-key type to share a single user-facing
/// type parameter [K]. Without the wrappers, `_SectionKey("a")` and
/// `_ItemKey("a")` would collide as map keys in the underlying tree's
/// node registry. The wrappers also let the node payload be either a
/// section or an item without forcing the user to write a sealed union.
library;

sealed class SecKey<K> {
  const SecKey();
}

final class SectionKey<K> extends SecKey<K> {
  const SectionKey(this.value);

  final K value;

  @override
  bool operator ==(Object other) {
    return other is SectionKey<K> && other.value == value;
  }

  @override
  int get hashCode {
    return Object.hash(SectionKey, value);
  }

  @override
  String toString() {
    return "SectionKey($value)";
  }
}

final class ItemKey<K> extends SecKey<K> {
  const ItemKey(this.value);

  final K value;

  @override
  bool operator ==(Object other) {
    return other is ItemKey<K> && other.value == value;
  }

  @override
  int get hashCode {
    return Object.hash(ItemKey, value);
  }

  @override
  String toString() {
    return "ItemKey($value)";
  }
}

sealed class SecPayload<Section, Item> {
  const SecPayload();
}

final class SectionPayload<Section, Item> extends SecPayload<Section, Item> {
  const SectionPayload(this.value);

  final Section value;

  /// Compares the wrapped section value, NOT wrapper identity. Two
  /// distinct wrapper instances around the same `Section` value must be
  /// equal — otherwise [TreeNode.==] (which delegates to `data.==`)
  /// would always report data as changed on every sync, forcing
  /// `TreeSyncController` to fire `updateNode` for every retained
  /// section header on every rebuild.
  @override
  bool operator ==(Object other) {
    return other is SectionPayload<Section, Item> && other.value == value;
  }

  @override
  int get hashCode {
    return Object.hash(SectionPayload, value);
  }

  @override
  String toString() {
    return "SectionPayload($value)";
  }
}

final class ItemPayload<Section, Item> extends SecPayload<Section, Item> {
  const ItemPayload(this.value);

  final Item value;

  /// Compares the wrapped item value, NOT wrapper identity. See the
  /// rationale on [SectionPayload.==].
  @override
  bool operator ==(Object other) {
    return other is ItemPayload<Section, Item> && other.value == value;
  }

  @override
  int get hashCode {
    return Object.hash(ItemPayload, value);
  }

  @override
  String toString() {
    return "ItemPayload($value)";
  }
}
