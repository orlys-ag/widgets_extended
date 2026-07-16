/// Regression test for audit item 6.4: the slide engine's completion
/// cleanup guard (`_slideByNid[nid] != originalEntry`) was written for
/// "listener re-installed a new slide on the same nid" — but composition
/// mutates the entry IN PLACE, so the guard passed for the exact scenario
/// it targeted: a same-tick composition onto a completed entry was
/// deleted immediately, silently killing the freshly retargeted slide
/// (the row snaps to its structural position).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

Future<void> _primeScheduler(WidgetTester tester) async {
  await tester.pumpWidget(const Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox.expand(),
  ));
}

void main() {
  testWidgets(
    "a slide composed during the completion tick's notify survives the "
    "tick's cleanup",
    (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 60),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // On the completion tick (delta snapped to 0, hasActiveSlides still
      // true, notify fired BEFORE cleanup), synchronously retarget the
      // same key — composition mutates the completed entry in place.
      bool retargeted = false;
      controller.addAnimationListener(() {
        if (!retargeted &&
            controller.hasActiveSlides &&
            controller.getSlideDelta("a") == 0.0) {
          retargeted = true;
          controller.animateSlideFromOffsets(
            {"a": (y: 40.0, x: 0.0)},
            {"a": (y: 0.0, x: 0.0)},
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
          );
        }
      });

      controller.animateSlideFromOffsets(
        {"a": (y: 60.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 60),
        curve: Curves.linear,
      );
      await tester.pump();

      // Pump until the first slide completes and the listener retargets.
      for (int i = 0; i < 12 && !retargeted; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(retargeted, isTrue,
          reason: "setup: the completion-tick notify must have fired with "
              "delta snapped to 0");

      expect(
        controller.hasActiveSlides,
        isTrue,
        reason: "the freshly retargeted slide must survive the completion "
            "tick's cleanup — in-place composition must not be mistaken "
            "for the entry that just completed",
      );
      expect(controller.getSlideDelta("a"), isNot(0.0),
          reason: "the retargeted slide carries the new 40px delta");

      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("a"), 0.0);
    },
  );
}
