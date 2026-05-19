/// Regression: an imperative `removeItem` / `removeSection` followed by
/// a `setSections` that mirrors the controller's current live state back
/// must not silently undo the deletion.
///
/// The bug this guards against: the sync controller's retained-branch
/// auto-cancelling pending-deletion nodes via
/// `insertRoot(preservePendingSubtreeState: true)`, which would fire on
/// every imperative remove if the mirror naturally included the still-
/// present pending row. Live-by-default queries keep the pending row out
/// of the mirror.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("imperative removeItem + live-mirror setSections honors "
      "the deletion", (tester) async {
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
    expect(controller.hasItem("b"), isTrue);

    // Imperative remove with animation. 'b' enters pending-deletion.
    controller.removeItem("b", animate: true);

    // Mirror the live state back via setSections. With live-by-default
    // queries, 'b' is not in the mirror.
    final liveSections = controller.sectionKeys();
    final liveItemsBySection = {
      for (final s in liveSections) s: controller.itemKeysOf(s),
    };
    controller.setSections(
      liveSections,
      itemsOf: (s) => liveItemsBySection[s] ?? const [],
    );

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasItem("b"), isFalse,
        reason: "Imperative removeItem followed by a live-mirror setSections "
            "must purge 'b'.");
    expect(controller.itemKeysOf("s"), equals(["a", "c"]));
  });

  testWidgets("imperative removeSection + live-mirror setSections "
      "honors the deletion", (tester) async {
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
    final liveSections = controller.sectionKeys();
    controller.setSections(
      liveSections,
      itemsOf: (_) => const [],
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasSection("b"), isFalse);
    expect(controller.sectionKeys(), equals(["a", "c"]));
  });
}
