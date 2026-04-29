/// Verifies that `SectionedListController.moveItemInSection` works
/// when a sibling is mid-pending-deletion.
///
/// The current implementation builds `siblings` from `itemsOf(parentKey)`
/// which includes pending-deletion entries, then passes that list to
/// `reorderItems` → `_tree.reorderChildren`, which validates the
/// orderedKeys against the LIVE child set (excluding pending-deletion).
/// The lengths mismatch and an ArgumentError is thrown.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("moveItemInSection works with a pending-deletion sibling "
      "in the same section", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "s",
        section: "S",
        items: const [
          ItemInput(key: "a", item: "A"),
          ItemInput(key: "b", item: "B"),
          ItemInput(key: "c", item: "C"),
        ],
      ),
    ]);
    // Items must be in the visible order for `remove(animate=true)` to
    // actually start an exit animation (otherwise it's an immediate
    // purge). Expand the section so they enter _order.
    controller.expandSection("s", animate: false);

    // Remove 'b' with animation → pending-deletion.
    controller.removeItem("b", animate: true);
    await tester.pump(const Duration(milliseconds: 80));

    // 'b' is still in itemsOf (pending-deletion sits in the children list).
    expect(controller.itemsOf("s"), contains("b"));

    // Now try to move 'c' to the front. moveItemInSection builds the
    // sibling list from itemsOf (which still has 'b'), then calls
    // reorderItems which validates against the LIVE list (no 'b').
    // Length mismatch → ArgumentError.
    expect(
      () => controller.moveItemInSection("c", 0),
      returnsNormally,
      reason: "moveItemInSection should handle pending-deletion siblings "
          "by filtering them out of the proposed order before passing to "
          "reorderItems. Currently it includes 'b' in the order list, "
          "and reorderItems' length-check rejects.",
    );

    // Drain the animation.
    await tester.pumpAndSettle();
  });

  testWidgets("moveSection works with a pending-deletion sibling section",
      (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "a",
        section: "A",
      ),
      SectionInput<String, String, String, String>(
        key: "b",
        section: "B",
      ),
      SectionInput<String, String, String, String>(
        key: "c",
        section: "C",
      ),
    ]);

    controller.removeSection("b", animate: true);
    await tester.pump(const Duration(milliseconds: 80));

    expect(controller.sections, contains("b"),
        reason: "'b' should still be in sections during exit");

    // moveSection has the same shape: reads `sections` (all roots
    // including pending-deletion), removes the moved key, inserts at
    // index, calls reorderSections → reorderRoots → throws if the list
    // includes pending-deletion entries.
    expect(
      () => controller.moveSection("c", 0),
      returnsNormally,
      reason: "moveSection should handle pending-deletion sibling "
          "sections by filtering them out of the proposed order.",
    );

    await tester.pumpAndSettle();
  });
}
