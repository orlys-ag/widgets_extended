/// Verifies sync semantics for pending-deletion nodes when their key
/// reappears in a subsequent `setSections` / `setItems`.
///
/// The retained-branch in `syncRoots` / `syncChildren` does NOT auto-
/// cancel pending-deletion nodes — that policy would silently undo
/// imperative `removeItem` / `removeSection` calls in patterns that
/// mirror the controller back through `setSections`.
///
/// Callers that intend to cancel mid-animation should either:
///   • mirror through live queries (`sectionKeys` / `itemKeysOf`) so
///     the pending row drops out of the mirror; the toAdd branch's
///     `preservePendingSubtreeState` path then handles cancellation
///     cleanly via re-add; OR
///   • call `addSection` / `addItem` directly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("imperative removeSection followed by setSections that "
      "DOES NOT include the section continues the deletion", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["a", "b"],
      itemsOf: (_) => const [],
    );

    controller.removeSection("b", animate: true);
    // Live mirror immediately — excludes pending 'b'.
    controller.setSections(
      ["a"],
      itemsOf: (_) => const [],
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasSection("b"), isFalse,
        reason: "After remove + live-mirror sync + animation, 'b' should "
            "be purged.");
    expect(controller.sectionKeys, equals(["a"]));
  });

  testWidgets("declarative re-include via addSection cancels a pending "
      "deletion mid-animation", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["a", "b"],
      itemsOf: (_) => const [],
    );

    controller.setSections(
      ["a"],
      itemsOf: (_) => const [],
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    controller.addSection("b");

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasSection("b"), isTrue,
        reason: "addSection on a pending-deletion key cancels the "
            "deletion via insertRoot's existing logic.");
  });
}
