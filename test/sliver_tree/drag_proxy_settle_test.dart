/// Drop-settle repro: with the drag proxy enabled, releasing a drag must
/// animate the dragged row FROM THE RELEASE POSITION (where the floating
/// proxy was — pointer minus grab offset) into its final slot, not from
/// its pre-drag slot. The proxy visually "becomes" the row mid-flight.
///
/// Mechanism under test: the commit overrides the dragged row's FLIP
/// baseline entry to the release position, so the existing slide engine
/// carries it hand → slot (composing with sibling slides / make-room
/// handoff). Cancel installs the mirror slide back to the original slot.
///
/// Repro-test methodology: on pre-fix code the commit slide starts at the
/// OLD slot (delta = old − new) and cancel installs no slide at all —
/// both expectations here fail.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Future<({TreeController<String, String> tree, TreeReorderController<String> reorder})>
    _mount(WidgetTester tester) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationDuration: const Duration(milliseconds: 200),
    animationCurve: Curves.linear,
  );
  tree.setRoots([
    for (var i = 0; i < 6; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
    slideDuration: const Duration(milliseconds: 200),
    slideCurve: Curves.linear,
  );
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
    tree.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              showDragProxy: true,
              nodeBuilder: (context, key, depth, wrap) {
                return wrap(
                  longPressToDrag: true,
                  child: SizedBox(
                    key: ValueKey("row-$key"),
                    height: 50,
                    child: Text(key),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (tree: tree, reorder: reorder);
}

void main() {
  testWidgets(
    "committed drop slides the dragged row from the RELEASE position, "
    "not from its pre-drag slot",
    (tester) async {
      final h = await _mount(tester);

      // Grab r0 at its center (grab offset 25 within the 50px row), drag
      // to y=295 — the bottom of r5 (250..300) → below-r5, final index 5,
      // structural destination y = 250.
      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 295));
      await tester.pump();
      expect(h.reorder.currentTarget?.indexInFinalList, 5,
          reason: "setup: below-r5 is final index 5 for dragged r0");

      await gesture.up();
      await tester.pump();

      expect(h.tree.liveRootKeys.last, "r0",
          reason: "setup: the drop committed r0 to the last slot");

      // The release position was pointer 295 − grab 25 = 270. The new
      // structural slot is 250. The commit slide must start the row at
      // 270 (delta +20) — where the proxy was — NOT at its old slot 0
      // (delta −250).
      final delta = h.tree.getSlideDelta("r0");
      expect(
        delta,
        closeTo(20.0, 1.0),
        reason: "the dragged row must take over exactly where the proxy "
            "was released (270) and glide to its slot (250); a delta of "
            "≈−250 means it is running the old-slot reparent slide",
      );

      await tester.pumpAndSettle();
      expect(h.tree.getSlideDelta("r0"), 0.0,
          reason: "the settle completes at the structural slot");
    },
  );

  testWidgets(
    "cancelled drag slides the dragged row from the release position "
    "back to its original slot",
    (tester) async {
      final h = await _mount(tester);

      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 295));
      await tester.pump();
      expect(h.reorder.isDragging, isTrue, reason: "setup: session active");

      h.reorder.cancelDrag();
      await tester.pump();

      expect(h.tree.liveRootKeys.first, "r0",
          reason: "setup: cancel commits nothing");

      // Release position 270, original slot 0 → the return glide starts
      // the row at 270 (delta +270). Pre-fix: no slide at all (0.0) — the
      // proxy vanishes at the pointer and the row pops back in place.
      final delta = h.tree.getSlideDelta("r0");
      expect(
        delta,
        closeTo(270.0, 1.0),
        reason: "the cancelled row must glide back from the proxy's "
            "release position instead of popping into place",
      );

      await tester.pumpAndSettle();
      expect(h.tree.getSlideDelta("r0"), 0.0);

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    "unmounting the whole scrollable mid-drag must not throw from the "
    "backstop's settle glide",
    (tester) async {
      // The cancel-path settle converts the release pointer through the
      // SCROLLABLE's render object. When the entire tree (scrollable
      // included) is swapped out mid-drag, the deactivate backstop's
      // post-frame cancelDrag runs against a defunct element — the glide
      // must be skipped, not thrown.
      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      tree.setRoots([
        for (var i = 0; i < 4; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        slideDuration: const Duration(milliseconds: 200),
        slideCurve: Curves.linear,
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
        reorder.dispose();
        tree.dispose();
      });

      final showTree = ValueNotifier<bool>(true);
      addTearDown(showTree.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showTree,
              builder: (context, show, _) => show
                  ? CustomScrollView(
                      slivers: [
                        SliverReorderableTree<String, String>(
                          controller: tree,
                          reorderController: reorder,
                          showDragProxy: true,
                          makeRoomOnDrag: true,
                          nodeBuilder: (context, key, depth, wrap) {
                            return wrap(
                              longPressToDrag: true,
                              child: SizedBox(
                                key: ValueKey("row-$key"),
                                height: 50,
                                child: Text(key),
                              ),
                            );
                          },
                        ),
                      ],
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 145));
      await tester.pump();
      expect(reorder.isDragging, isTrue, reason: "setup: session active");

      // Swap the ENTIRE scrollable out mid-drag.
      showTree.value = false;
      await tester.pump();
      // Post-frame backstop fires here.
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: "the settle glide must be skipped against a defunct "
              "scrollable, not thrown from the post-frame backstop");
      expect(reorder.isDragging, isFalse,
          reason: "the session must still be cancelled cleanly");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "without a proxy the classic old-slot reparent slide is preserved",
    (tester) async {
      // No showDragProxy: nothing was visually at the pointer, so sliding
      // from the release position would be wrong — the pre-existing
      // behavior (FLIP from the old slot) must remain.
      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      tree.setRoots([
        for (var i = 0; i < 6; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        slideDuration: const Duration(milliseconds: 200),
        slideCurve: Curves.linear,
      );
      addTearDown(() {
        reorder.dispose();
        tree.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  nodeBuilder: (context, key, depth, wrap) {
                    return wrap(
                      longPressToDrag: true,
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 295));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(tree.liveRootKeys.last, "r0");
      expect(
        tree.getSlideDelta("r0"),
        closeTo(-250.0, 1.0),
        reason: "proxy-less drops keep the classic FLIP from the old slot "
            "(0 → 250 ⇒ start delta −250)",
      );
      await tester.pumpAndSettle();
    },
  );
}
