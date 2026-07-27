/// Audit repro for finding f44 (plans/sliver_tree_review_2026_07_plan.md):
///
/// `TreeReorderController.endDrag` does not revalidate the drag session
/// against the current tree state and has no exception safety. If the
/// dragged node becomes pending-deletion mid-drag (e.g. an animated
/// `remove` driven by a server update), the same-parent commit path builds
/// a sibling list containing the non-live dragged key and
/// `reorderRoots`/`reorderChildren` throw ArgumentError. Because
/// `_session = null` / `notifyListeners()` sit after the mutation with no
/// try/finally, the session is left permanently stuck (isDragging true).
///
/// These tests assert the EXPECTED (correct) behavior: endDrag must
/// complete without throwing (degrading to a cancel when the session is
/// stale) and must always clear the session. They FAIL on current code if
/// and only if the bug is real.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Minimal SliverTree harness matching tree_reorder_controller_test.dart.
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

/// Converts a scroll-space y to a global pointer offset using the
/// scrollable's viewport render box so TreeReorderController's
/// `_pointerToScrollSpaceY` reverses it correctly.
Offset _scrollYToGlobal(ScrollableState scrollable, double scrollY) {
  final viewport = scrollable.context.findRenderObject() as RenderBox;
  final viewportLocalY = scrollY - scrollable.position.pixels;
  return viewport.localToGlobal(
    Offset(viewport.size.width / 2, viewportLocalY),
  );
}

/// Builds the f44 scenario: roots [a, b, c] (50px rows), a drag of "a"
/// resolved to below-"c" (a real same-parent root reorder), then an
/// animated `remove(key: "a")` mid-drag so the dragged key becomes
/// pending-deletion while the stale drop target is retained.
Future<TreeReorderController<String, String>> _setUpStaleDragSession(
  WidgetTester tester,
  TreeController<String, String> controller,
) async {
  controller.setRoots([
    TreeNode(key: "a", data: "A"),
    TreeNode(key: "b", data: "B"),
    TreeNode(key: "c", data: "C"),
  ]);

  final reorder = TreeReorderController<String, String>(
    treeController: controller,
    vsync: tester,
  );
  addTearDown(reorder.dispose);

  await tester.pumpWidget(_Harness(controller: controller).build());
  await tester.pump(const Duration(milliseconds: 400));

  final render = _findRender(tester);
  final scrollable = _findScrollable(tester);

  // Rows: a[0..50], b[50..100], c[100..150]. Pointer at y=145 is the
  // bottom third of "c" → zone below-c, parentKey null, a genuine
  // same-parent root reorder (indexInFinalList = 2).
  reorder.startDrag(
    key: "a",
    renderObject: render,
    scrollable: scrollable,
    indentPerDepth: 24.0,
    pointerGlobal: _scrollYToGlobal(scrollable, 145.0),
  );

  // Sanity: the drop target actually resolved — endDrag must take the
  // commit path, not the null-target cancel path.
  expect(reorder.currentTarget, isNotNull,
      reason: "setup: drop target below 'c' must resolve");
  expect(reorder.currentTarget?.zone, TreeDropZone.below,
      reason: "setup: expected below-'c' zone");
  expect(reorder.currentTarget?.targetKey, "c",
      reason: "setup: expected target row 'c'");
  expect(reorder.currentTarget?.parentKey, isNull,
      reason: "setup: same-parent root reorder expected");

  // Mid-drag, the app removes the dragged node with an animated exit
  // (300ms controller duration): "a" becomes pending-deletion, so
  // liveRootKeys excludes it, while the session retains its stale target.
  controller.remove(key: "a");
  await tester.pump(const Duration(milliseconds: 50));
  expect(controller.isPendingDeletion("a"), isTrue,
      reason: "setup: dragged key must be pending-deletion mid-drag");
  expect(reorder.isDragging, isTrue,
      reason: "setup: the drag session must still be active");

  return reorder;
}

/// Pumps the remaining exit animation with bounded pumps (no
/// pumpAndSettle — the scene may keep scheduling frames if state is
/// stuck).
Future<void> _drainAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("f44: endDrag while dragged node is pending-deletion", () {
    testWidgets(
      "endDrag completes without throwing when the dragged node became "
      "pending-deletion mid-drag",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        final reorder = await _setUpStaleDragSession(tester, controller);

        // EXPECTED behavior: endDrag revalidates the stale session and
        // degrades to a cancel — it must not let ArgumentError escape the
        // gesture callback. On current code this throws ArgumentError from
        // reorderRoots ("must contain exactly the current live root keys")
        // because the built list [b, c, a] contains the non-live key "a".
        expect(
          () {
            reorder.endDrag();
          },
          returnsNormally,
          reason: "endDrag must not throw when the dragged node was removed "
              "mid-drag; it should degrade to a cancel",
        );

        await _drainAnimations(tester);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      "endDrag always clears the session (isDragging false) even when the "
      "dragged node became pending-deletion mid-drag",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        final reorder = await _setUpStaleDragSession(tester, controller);

        // Swallow whatever endDrag throws — this test pins the aftermath:
        // the session must be cleared no matter what, otherwise the row
        // stays dimmed, the indicator overlay stays mounted, and the next
        // drop is silently lost until the next startDrag's cancelDrag.
        try {
          reorder.endDrag();
        } catch (_) {
          // Ignored: the sibling test asserts the no-throw contract.
        }

        expect(reorder.isDragging, isFalse,
            reason: "endDrag must clear the session even on a stale drag; "
                "a stuck session leaves the UI dimmed with the indicator "
                "overlay mounted");
        expect(reorder.draggedKey, isNull,
            reason: "no dragged key should remain after endDrag returns");

        await _drainAnimations(tester);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
