/// Verifies that re-syncing a [SectionedListController] with identical
/// section/item payloads doesn't trigger spurious `updateNode` calls
/// at the tree-controller level.
///
/// The internal `SectionPayload` / `ItemPayload` wrappers override `==`
/// to compare by wrapped value (not wrapper identity). Without that,
/// `TreeNode.==` (which compares `data` via `==`) would always report
/// data as changed on every sync, and `TreeSyncController` would fire
/// `updateNode` for every retained row.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("setSections with identical payloads does not fire "
      "spurious node-data notifications", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["s1"],
      itemsOf: (_) => const ["i1", "i2"],
    );

    final fires = <String>[];
    controller.addSectionPayloadListener(fires.add);
    controller.addItemPayloadListener(fires.add);

    // Re-sync with IDENTICAL payloads.
    controller.setSections(
      ["s1"],
      itemsOf: (_) => const ["i1", "i2"],
    );

    expect(
      fires,
      isEmpty,
      reason: "setSections with identical payloads fired ${fires.length} "
          "node-data notifications. SectionPayload/ItemPayload must "
          "compare wrapped values (not wrapper identity) so retained "
          "rows aren't refreshed on every sync.",
    );
  });

  testWidgets("setItems with identical payloads does not fire spurious "
      "node-data notifications", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["s1"],
      itemsOf: (_) => const ["i1", "i2"],
    );

    final fires = <String>[];
    controller.addItemPayloadListener(fires.add);

    controller.setItems("s1", const ["i1", "i2"]);

    expect(
      fires,
      isEmpty,
      reason: "setItems with identical payloads fired ${fires.length} "
          "notifications.",
    );
  });
}
