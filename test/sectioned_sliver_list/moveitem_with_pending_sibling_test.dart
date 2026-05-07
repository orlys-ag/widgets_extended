/// Verifies that `moveItemInSection` and `moveSection` work when a
/// sibling is mid-pending-deletion.
///
/// The implementations build their proposed reorder list from the LIVE
/// query (`itemKeysOf` / `sectionKeys`), which excludes pending-deletion.
/// Without this, the reorderChildren / reorderRoots length-check would
/// reject the proposed order whenever a sibling is mid-exit-animation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("moveItemInSection works with a pending-deletion sibling "
      "in the same section", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["s"],
      itemsOf: (_) => const ["a", "b", "c"],
    );
    controller.expandSection("s", animate: false);

    controller.removeItem("b", animate: true);
    await tester.pump(const Duration(milliseconds: 80));

    // 'b' is still in allItemKeysOf during exit, but excluded from
    // itemKeysOf (live).
    expect(controller.allItemKeysOf("s"), contains("b"));
    expect(controller.itemKeysOf("s"), isNot(contains("b")));

    expect(
      () => controller.moveItemInSection("c", 0),
      returnsNormally,
      reason: "moveItemInSection must filter pending-deletion siblings out "
          "of the proposed order — itemKeysOf is live-by-default.",
    );

    await tester.pumpAndSettle();
  });

  testWidgets("moveSection works with a pending-deletion sibling section",
      (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["a", "b", "c"],
      itemsOf: (_) => const [],
    );

    controller.removeSection("b", animate: true);
    await tester.pump(const Duration(milliseconds: 80));

    expect(controller.allSectionKeys, contains("b"));
    expect(controller.sectionKeys, isNot(contains("b")));

    expect(
      () => controller.moveSection("c", 0),
      returnsNormally,
      reason: "moveSection must filter pending-deletion sibling sections "
          "out of the proposed order.",
    );

    await tester.pumpAndSettle();
  });
}
