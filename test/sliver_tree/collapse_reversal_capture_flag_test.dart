import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Repro for the lead recorded in L27's audit trail: the collapse-side
/// reversals (`collapse` Path 1 and the `collapseAll` mirror) write a
/// genuine capture of the pre-reversal painted extent into
/// `targetExtent` without setting `targetIsCaptured`, so the next
/// `setFullExtent` whose measurement differs re-targets the member onto
/// the new full extent and the collapsing row jumps up mid-collapse.
///
/// Cases 3 and 4 guard the fix's other half: once the collapse side sets
/// the flag, the expand-side reversals must clear it unconditionally
/// (their target is the natural full reference), or a resize during a
/// second reversal would animate toward a stale full.
void main() {
  TreeController<String, String> makeController(WidgetTester tester) {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// Mounts r > [c0, c1, c2] with r collapsed, then runs `expand("r")` to
  /// its midpoint (150 ms of 300), where the rows have been measured at
  /// 100 px and paint at 50 px.
  Future<ValueNotifier<double>> mountMidExpand(
    WidgetTester tester,
    TreeController<String, String> controller,
  ) async {
    final c0Height = ValueNotifier<double>(100.0);
    addTearDown(c0Height.dispose);
    controller.setRoots([const TreeNode(key: "r", data: "R")]);
    controller.setChildren("r", [
      const TreeNode(key: "c0", data: "C0"),
      const TreeNode(key: "c1", data: "C1"),
      const TreeNode(key: "c2", data: "C2"),
    ]);
    await tester.pumpWidget(
      _Harness(controller: controller, c0Height: c0Height),
    );
    await tester.pump();

    controller.expand(key: "r");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      controller.getCurrentExtent("c0"),
      closeTo(50.0, 0.5),
      reason:
          "setup sanity: c0 must be mid-expand at half of its measured "
          "100 px (an unmeasured row would sit at half the 48 px default)",
    );
    return c0Height;
  }

  /// Resizes c0 to 160 px and pumps one 16 ms frame so the row is
  /// re-measured through the sliver's layout.
  Future<void> resizeC0(WidgetTester tester, ValueNotifier<double> h) async {
    h.value = 160.0;
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getSize(find.byKey(const ValueKey("row-c0"))).height,
      160.0,
      reason: "setup sanity: the resize must reach the row's layout",
    );
  }

  testWidgets(
    "case 1: collapse Path 1 keeps its captured terminus across a resize",
    (tester) async {
      final controller = makeController(tester);
      final c0Height = await mountMidExpand(tester, controller);

      controller.collapse(key: "r");
      expect(
        controller.isExiting("c0"),
        isTrue,
        reason: "setup sanity: the collapse must reverse the expand group",
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(45.0, 0.5),
        reason: "setup sanity: 30 ms into the reversal, 50 px shrinks to 45",
      );

      await resizeC0(tester, c0Height);
      // Value 0.9 minus 16/300: the capture of 50 stays the terminus.
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(50.0 * (0.9 - 16.0 / 300.0), 1.0),
        reason:
            "the collapse must keep shrinking from its captured 50 px; a "
            "re-target onto the new 160 px full extent pops the row up",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "case 2: the collapseAll mirror keeps its captured terminus across a "
    "resize",
    (tester) async {
      final controller = makeController(tester);
      final c0Height = await mountMidExpand(tester, controller);

      controller.collapseAll();
      expect(
        controller.isExiting("c0"),
        isTrue,
        reason: "setup sanity: collapseAll must re-pend the expand group",
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(45.0, 0.5),
        reason: "setup sanity: 30 ms into the reversal, 50 px shrinks to 45",
      );

      await resizeC0(tester, c0Height);
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(50.0 * (0.9 - 16.0 / 300.0), 1.0),
        reason:
            "the collapse must keep shrinking from its captured 50 px; a "
            "re-target onto the new 160 px full extent pops the row up",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "case 3: expand Path 1 after a collapse reversal follows a resize",
    (tester) async {
      final controller = makeController(tester);
      final c0Height = await mountMidExpand(tester, controller);

      controller.collapse(key: "r");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // Reverse again: start = the 45 px capture, target = the 100 px
      // full reference, value reset to 0.
      controller.expand(key: "r");
      expect(
        controller.isExiting("c0"),
        isFalse,
        reason: "setup sanity: the expand must un-pend the group",
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(45.0 + 55.0 * 0.1, 0.5),
        reason: "setup sanity: 30 ms into the re-expand, 45 grows toward 100",
      );

      await resizeC0(tester, c0Height);
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(45.0 + 115.0 * (0.1 + 16.0 / 300.0), 1.0),
        reason:
            "the expand's target is a natural full reference, so the "
            "resize to 160 px must re-target it; a flag left set by the "
            "earlier collapse reversal would hold the stale 100 px",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "case 4: the expandAll merged branch after the collapseAll mirror "
    "follows a resize",
    (tester) async {
      final controller = makeController(tester);
      final c0Height = await mountMidExpand(tester, controller);

      controller.collapseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      controller.expandAll();
      expect(
        controller.isExiting("c0"),
        isFalse,
        reason: "setup sanity: expandAll must un-pend the survivors",
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(45.0 + 55.0 * 0.1, 0.5),
        reason: "setup sanity: 30 ms into the re-expand, 45 grows toward 100",
      );

      await resizeC0(tester, c0Height);
      expect(
        controller.getCurrentExtent("c0"),
        closeTo(45.0 + 115.0 * (0.1 + 16.0 / 300.0), 1.0),
        reason:
            "the expand's target is a natural full reference, so the "
            "resize to 160 px must re-target it; a flag left set by the "
            "earlier collapseAll mirror would hold the stale 100 px",
      );
      await tester.pumpAndSettle();
    },
  );
}

class _Harness extends StatelessWidget {
  const _Harness({required this.controller, required this.c0Height});

  final TreeController<String, String> controller;
  final ValueNotifier<double> c0Height;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                if (key == "c0") {
                  return ValueListenableBuilder<double>(
                    valueListenable: c0Height,
                    builder: (context, height, child) {
                      return SizedBox(
                        key: const ValueKey("row-c0"),
                        height: height,
                      );
                    },
                  );
                }
                return SizedBox(key: ValueKey("row-$key"), height: 100.0);
              },
            ),
          ],
        ),
      ),
    );
  }
}
