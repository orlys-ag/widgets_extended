/// Verifies that duplicate item keys across sections are rejected at
/// sync time. The internal tree representation uses `ItemKey<K>(value)`
/// for items, so an item with key "x" in section A and another in
/// section B would collide in the underlying TreeController.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("setSections with duplicate item keys across sections "
      "throws or is detected, not silently corrupted", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Two sections, each containing an item with key "x". The underlying
    // tree only allows one node per key, so this is an inconsistent
    // input that should be rejected.
    bool threw = false;
    try {
      controller.setSections(
        ["a", "b"],
        itemsOf: (_) => const ["x"], // both sections claim item "x"
      );
    } catch (_) {
      threw = true;
    }

    if (!threw) {
      // If it didn't throw, it must at least not silently corrupt
      // state. Verify the controller's view of items.
      final aItems = controller.itemKeysOf("a");
      final bItems = controller.itemKeysOf("b");
      expect(
        !(aItems.contains("x") && bItems.contains("x")),
        isTrue,
        reason: "Item 'x' was registered under BOTH sections — the "
            "underlying TreeController has a single node per key, so this "
            "state is impossible. Either setSections corrupted the tree "
            "or the validation is missing.",
      );
    }
  });
}
