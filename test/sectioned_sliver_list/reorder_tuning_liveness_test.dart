/// The sectioned counterpart of the sliver_tree tuning-liveness repros:
/// `SectionedReorderBridge.updateDragTunings` pushes the LIVE config's
/// drag tunings (`autoExpandDelay`, `autoScrollEdgeZone`,
/// `autoScrollMaxVelocity`) onto the reorder controller's mutable
/// fields. Both sectioned widget forms call it from `didUpdateWidget`,
/// so a rebuilt config's tunings reach the controller and are captured
/// by the next drag session.
///
/// Repro-test methodology: on pre-fix code the controller fields were
/// final and seeded once at bridge construction, so no later config
/// value could ever reach them (and `updateDragTunings` did not exist).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sectioned_sliver_list/_reorder_bridge.dart';
import 'package:widgets_extended/sectioned_sliver_list/sectioned_list_controller.dart';
import 'package:widgets_extended/sectioned_sliver_list/sectioned_reorder_config.dart';

void main() {
  testWidgets("updateDragTunings pushes the live config onto the controller", (
    tester,
  ) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (section) {
        return section;
      },
      itemKeyOf: (item) {
        return item;
      },
    );
    var config = const SectionedReorderConfig<String, String, String>();
    final bridge = SectionedReorderBridge<String, String, String>(
      controller: controller,
      configOf: () {
        return config;
      },
      requireCallbacks: false,
      vsync: tester,
    );
    addTearDown(() {
      bridge.dispose();
      controller.dispose();
    });

    expect(
      bridge.reorderController.autoExpandDelay,
      const Duration(milliseconds: 700),
      reason: "setup: construction seeds the config's tunings",
    );
    expect(bridge.reorderController.autoScrollEdgeZone, 48.0);
    expect(bridge.reorderController.autoScrollMaxVelocity, 1200.0);

    config = const SectionedReorderConfig<String, String, String>(
      autoExpandDelay: Duration(milliseconds: 150),
      autoScrollEdgeZone: 80.0,
      autoScrollMaxVelocity: 600.0,
    );
    bridge.updateDragTunings();

    expect(
      bridge.reorderController.autoExpandDelay,
      const Duration(milliseconds: 150),
      reason: "updateDragTunings must push the live config's new values",
    );
    expect(bridge.reorderController.autoScrollEdgeZone, 80.0);
    expect(bridge.reorderController.autoScrollMaxVelocity, 600.0);
  });
}
