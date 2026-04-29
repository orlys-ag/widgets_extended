/// Verifies that re-syncing a [SectionedListController] with identical
/// section/item payloads doesn't trigger spurious `updateNode` calls
/// at the tree-controller level.
///
/// The internal `SectionPayload` / `ItemPayload` wrappers don't override
/// `==`, so `TreeNode.==` (which compares `data` via `==`) falls back to
/// identity for two wrapper instances around the SAME user payload.
/// `TreeSyncController` then thinks the data changed on every sync and
/// fires `updateNode` for every retained row.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("setSections with identical payloads does not fire "
      "spurious node-data notifications", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Initial sync.
    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "s1",
        section: "Section 1",
        items: const [
          ItemInput(key: "i1", item: "Item 1"),
          ItemInput(key: "i2", item: "Item 2"),
        ],
      ),
    ]);

    int dataChangeCount = 0;
    controller.treeController.addNodeDataListener((_) => dataChangeCount++);

    // Re-sync with IDENTICAL payloads (new SectionInput / ItemInput
    // instances wrapping the same String values).
    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "s1",
        section: "Section 1",
        items: const [
          ItemInput(key: "i1", item: "Item 1"),
          ItemInput(key: "i2", item: "Item 2"),
        ],
      ),
    ]);

    expect(
      dataChangeCount,
      0,
      reason:
          "setSections with identical payloads fired $dataChangeCount "
          "node-data notifications. SectionPayload/ItemPayload wrappers "
          "compare by identity by default, so two wrappers around the "
          "same user value look unequal — TreeSyncController then fires "
          "updateNode for every retained row, refreshing every header "
          "and item even when nothing actually changed.",
    );
  });

  testWidgets("setItems with identical payloads does not fire spurious "
      "node-data notifications", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "s1",
        section: "Section 1",
        items: const [
          ItemInput(key: "i1", item: "Item 1"),
          ItemInput(key: "i2", item: "Item 2"),
        ],
      ),
    ]);

    int dataChangeCount = 0;
    controller.treeController.addNodeDataListener((_) => dataChangeCount++);

    controller.setItems("s1", const [
      ItemInput(key: "i1", item: "Item 1"),
      ItemInput(key: "i2", item: "Item 2"),
    ]);

    expect(
      dataChangeCount,
      0,
      reason: "setItems with identical payloads fired $dataChangeCount "
          "node-data notifications.",
    );
  });
}
