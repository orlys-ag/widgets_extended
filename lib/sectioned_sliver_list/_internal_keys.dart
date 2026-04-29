/// Internal sealed wrapper types used to keep section keys, item keys,
/// section payloads, and item payloads in disjoint domains within a
/// single underlying [TreeController].
///
/// Not exported from the package barrel.
///
/// The wrappers are necessary because `SectionedSliverList` allows the
/// section-key type and the item-key type to be the same (e.g., both
/// `String`). Without the wrappers, `_SectionKey("a")` and
/// `_ItemKey("a")` would collide as map keys in the underlying tree's
/// node registry. The wrappers also let the node payload be either a
/// section or an item without forcing the user to write a sealed union.
library;

sealed class SecKey<SKey, IKey> {
  const SecKey();
}

final class SectionKey<SKey, IKey> extends SecKey<SKey, IKey> {
  const SectionKey(this.value);

  final SKey value;

  @override
  bool operator ==(Object other) {
    return other is SectionKey<SKey, IKey> && other.value == value;
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

final class ItemKey<SKey, IKey> extends SecKey<SKey, IKey> {
  const ItemKey(this.value);

  final IKey value;

  @override
  bool operator ==(Object other) {
    return other is ItemKey<SKey, IKey> && other.value == value;
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
}

final class ItemPayload<Section, Item> extends SecPayload<Section, Item> {
  const ItemPayload(this.value);

  final Item value;
}
