/// Verifies the sync semantics for pending-deletion nodes when their
/// key reappears in a subsequent `setSections`/`setItems` call.
///
/// The retained-branch in `syncRoots`/`syncChildren` does NOT auto-
/// cancel pending-deletion nodes — that policy would silently undo
/// imperative `removeItem`/`removeSection` calls in the common
/// "controller mutates → setState → widget rebuilds → mirror" pattern,
/// where the mirror naturally includes the still-present pending row.
///
/// Callers that genuinely intend to cancel mid-animation should either:
///   • mirror through `liveSections` / `liveItemsOf` so the pending
///     row drops out of the mirror, then re-add via `setSections` (the
///     toAdd branch's existing `preservePendingSubtreeState` path
///     handles cancellation cleanly); or
///   • call `addSection` / `addItem` / `insertRoot` directly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("imperative removeSection followed by a setSections that "
      "DOES NOT include the section continues the deletion", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 100),
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
    ]);

    controller.removeSection("b", animate: true);
    // Pass the live-mirror immediately (excludes pending 'b'). This is
    // what the example does on setState rebuild.
    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "a",
        section: "A",
      ),
    ]);

    // Pump multiple frames to let the standalone exit animation run to
    // completion. Single pump fires only one tick (with dt=0 on first
    // tick), so we need several frames for the dt-based progress to
    // accumulate.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasSection("b"), isFalse,
        reason: "After remove + live-mirror sync + animation, 'b' should "
            "be purged.");
    expect(controller.sections, equals(["a"]));
  });

  testWidgets("declarative re-include via addSection cancels a pending "
      "deletion mid-animation", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 100),
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
    ]);

    // Step 1: remove 'b' via setSections.
    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "a",
        section: "A",
      ),
    ]);
    // Pump partway through the animation.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Step 2: caller intends to cancel — uses addSection (which routes
    // through insertRoot's pending-deletion cancellation path).
    controller.addSection(
      SectionInput<String, String, String, String>(
        key: "b",
        section: "B",
      ),
    );

    // Drain past the original animation duration.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasSection("b"), isTrue,
        reason: "addSection on a pending-deletion key cancels the "
            "deletion via insertRoot's existing logic — 'b' survives.");
  });
}
