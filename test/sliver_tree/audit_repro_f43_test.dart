import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Audit repro for finding f43:
///
/// Cross-parent drop passes a live-space index (`indexInFinalList`, computed
/// from the live-space [TreeController.getIndexInParent]) straight to
/// [TreeController.moveNode], which inserts into the FULL sibling list
/// (including pending-deletion entries). When the destination parent has an
/// exiting (pending-deletion) sibling ordered before the drop position, the
/// dropped node lands one slot too high.
///
/// Expected (correct) behavior asserted here: dropping "w" ABOVE "z" while
/// sibling "x" is mid-exit must produce live order [y, w, z] under P, and
/// the persistent order after the exit completes must be [y, w, z].
class _Harness {
  _Harness({required this.controller});

  final TreeController<String, String> controller;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey(key),
                  height: 50,
                  child: Text("$key (d=$depth)"),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

ScrollableState _findScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable));
}

RenderSliverTree<String, String> _findRender(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

/// Bounded settle: pumps fixed frames instead of pumpAndSettle so a scene
/// that never settles cannot hang the test.
Future<void> _pumpBounded(WidgetTester tester,
    {int frames = 30,
    Duration step = const Duration(milliseconds: 50)}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    "f43: cross-parent drop above a live sibling lands at the correct live "
    "position even while an earlier sibling is animating out",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "P", data: "P"),
        TreeNode(key: "w", data: "W"),
      ]);
      controller.setChildren("P", [
        TreeNode(key: "x", data: "X"),
        TreeNode(key: "y", data: "Y"),
        TreeNode(key: "z", data: "Z"),
      ]);
      controller.expand(key: "P");

      final reorder = TreeReorderController<String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      // Let the initial expand animation finish (bounded).
      await _pumpBounded(tester);

      // Settled rows: P(0..50), x(50..100), y(100..150), z(150..200),
      // w(200..250).
      expect(controller.getChildren("P"), ["x", "y", "z"]);

      // Start removing "x" with a 300ms exit animation and stop mid-flight.
      controller.remove(key: "x");
      await tester.pump(const Duration(milliseconds: 150));

      // Sanity: "x" is pending-deletion but still present in the FULL list;
      // the LIVE list is [y, z].
      expect(controller.isPendingDeletion("x"), true,
          reason: "setup: x must be mid-exit for the repro");
      expect(controller.getChildren("P"), ["x", "y", "z"],
          reason: "setup: full list still contains pending-deletion x");
      expect(controller.getLiveChildren("P"), ["y", "z"],
          reason: "setup: live list excludes pending-deletion x");

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      // Aim the pointer at the top third of row "z" (zone = above). Derive
      // the position from z's actual on-screen rect so the repro does not
      // depend on the exact exit-animation progress.
      final zRect = tester.getRect(find.byKey(const ValueKey("z")));
      final pointer = Offset(zRect.center.dx, zRect.top + 5.0);

      // Drag root "w" and hover above "z" — a cross-parent drop (w is a
      // root; the destination parent is P).
      reorder.startDrag(
        key: "w",
        renderPort: render,
        scrollable: scrollable,
        pointerGlobal: pointer,
      );

      // Sanity: the resolved target must be the exact path under test —
      // above-z, parent P, live-space index 1 (live siblings [y, z]).
      final target = reorder.currentTarget;
      expect(target, isNotNull, reason: "setup: pointer must resolve a target");
      expect(target!.zone, TreeDropZone.above, reason: "setup: above z");
      expect(target.targetKey, "z", reason: "setup: hovering row z");
      expect(target.parentKey, "P", reason: "setup: destination parent P");
      expect(target.indexInFinalList, 1,
          reason: "setup: live index of z among live siblings [y, z]");

      reorder.endDrag();

      // EXPECTED (correct) behavior: "w" was dropped above "z", so the live
      // order under P must be [y, w, z]. The bug inserts the live-space
      // index 1 into the FULL list [x(pending), y, z], producing
      // [x, w, y, z] -> live [w, y, z]: w lands above y instead of above z.
      expect(controller.getLiveChildren("P"), ["y", "w", "z"],
          reason: "w was dropped above z; it must sit between y and z");

      // Let the exit animation and the FLIP slide finish (bounded), then
      // verify the wrong order does not merely self-heal after x's purge.
      await _pumpBounded(tester);
      expect(controller.isPendingDeletion("x"), false);
      expect(controller.getChildren("P"), ["y", "w", "z"],
          reason: "after x purges, the persistent order must be [y, w, z]");
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
