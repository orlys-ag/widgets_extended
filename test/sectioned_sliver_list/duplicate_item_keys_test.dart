/// Verifies that `SectionedSliverList` rejects duplicate item keys
/// across sections at sync time. The internal tree representation uses
/// `ItemKey<SKey, IKey>(value)` for items, so an item with key `"x"`
/// in section A and another item with key `"x"` in section B would
/// collide in the underlying TreeController's nid registry.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("setSections with duplicate item keys across sections "
      "throws or is detected, not silently corrupted", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Two sections, each containing an item with key "x". The underlying
    // tree only allows one node per key, so this is an inconsistent
    // input that should be rejected.
    bool threw = false;
    try {
      controller.setSections([
        SectionInput<String, String, String, String>(
          key: "a",
          section: "A",
          items: const [ItemInput(key: "x", item: "From A")],
        ),
        SectionInput<String, String, String, String>(
          key: "b",
          section: "B",
          items: const [ItemInput(key: "x", item: "From B")],
        ),
      ]);
    } catch (e) {
      threw = true;
    }

    if (!threw) {
      // If it didn't throw, it must at least not silently corrupt
      // state. Verify the controller's view of items.
      final aItems = controller.itemsOf("a");
      final bItems = controller.itemsOf("b");
      // At minimum, "x" cannot appear in BOTH sections — the underlying
      // tree only has one node per key.
      expect(
        !(aItems.contains("x") && bItems.contains("x")),
        isTrue,
        reason: "Item 'x' was registered under BOTH sections 'a' and 'b' "
            "— the underlying TreeController has a single node per key, "
            "so this state is impossible. Either setSections corrupted "
            "the tree or the validation is missing.",
      );
    }
  });
}
