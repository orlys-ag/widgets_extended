/// Tests for reparenting a node whose subtree is mid-exit (pending-deletion).
///
/// The controller composes two animations on the moved row:
///   1. extent reverses from its current shrinking value back to full
///      (driven by the standalone ticker), and
///   2. a FLIP slide lerps Y/X from the row's last painted position to its
///      new structural position (driven by the slide engine).
///
/// Together these produce a smooth "the row continues from where it was, but
/// now lives under a new parent" transition instead of the snap-to-full-
/// height-then-jump behaviour of the prior `_cancelAnimationStateForSubtree`
/// path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

Widget _harness(
  TreeController<String, String> controller, {
  double height = 600,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 20.0),
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
}

void main() {
  group("reparent during exit — visible source, visible destination", () {
    testWidgets("extent reverses to enter while slide installs Y delta", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots(<TreeNode<String, String>>[
        const TreeNode<String, String>(key: "A", data: "A"),
        const TreeNode<String, String>(key: "B", data: "B"),
        const TreeNode<String, String>(key: "x", data: "x"),
      ]);
      // expand() is a no-op on a node with no children, so B needs a
      // placeholder before it can be expanded. Phase B's case 1
      // (reverse exit) requires the destination's ancestor chain to be
      // expanded.
      controller.setChildren("B", <TreeNode<String, String>>[
        const TreeNode<String, String>(key: "b1", data: "b1"),
      ]);
      controller.expand(key: "B", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      final fullExtent = controller.getEstimatedExtent("x");
      expect(fullExtent, 48.0);

      // Start an animated remove on x.
      controller.remove(key: "x", animate: true);
      expect(controller.isPendingDeletion("x"), isTrue);

      // The standalone ticker's first callback sets its baseline time
      // (dt=0). A priming `pump(1ms)` establishes the baseline; the
      // following `pump(199ms)` then actually advances progress.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 199));

      // Sanity: standalone exit is in flight, extent is shrinking.
      final exitState = controller.getAnimationState("x");
      expect(exitState, isNotNull);
      expect(exitState!.type, AnimationType.exiting);
      final extentDuringExit = controller.getCurrentExtent("x");
      expect(
        extentDuringExit,
        lessThan(fullExtent),
        reason: "x is mid-shrink",
      );
      expect(
        extentDuringExit,
        greaterThan(0.0),
        reason: "x has not finished shrinking yet",
      );

      // Capture the row's current painted Y so we can verify the slide
      // installs against it (rather than against the post-mutation Y).
      final paintedYBeforeMove = tester
          .getTopLeft(find.byKey(const ValueKey("row-x")))
          .dy;

      // Reparent x to be the FIRST child of B. moveNode now composes the
      // extent reversal with the FLIP slide. (index: 0 is required —
      // appending x to B's end leaves it at the same scroll-space Y as
      // its prior root position, producing a zero-delta slide.)
      controller.moveNode(
        "x",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // Pending-deletion is cleared so finalize won't purge x.
      expect(controller.isPendingDeletion("x"), isFalse);

      // Standalone state has flipped from exiting → entering, with the
      // start extent equal to where the exit left off (no jump to 0
      // and no jump to full).
      final reverseState = controller.getAnimationState("x");
      expect(reverseState, isNotNull);
      expect(
        reverseState!.type,
        AnimationType.entering,
        reason: "exit reverses to enter so the row regrows from current",
      );
      expect(
        reverseState.startExtent,
        closeTo(extentDuringExit, 1.0),
        reason: "enter starts from the exit's last extent — no extent jump",
      );

      // FLIP slide is active for x, anchored to the pre-move painted Y.
      expect(
        controller.hasActiveSlides,
        isTrue,
        reason: "moveNode staged a slide baseline; consume installed it",
      );
      expect(
        controller.getSlideDelta("x"),
        isNot(0.0),
        reason: "x's slide delta = old painted Y minus new structural Y",
      );

      // x is now structurally a child of B.
      expect(controller.getParent("x"), "B");

      // Drive both animations to completion. Settles cleanly.
      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("x"), 0.0);
      expect(controller.getCurrentExtent("x"), closeTo(fullExtent, 0.001));
      expect(find.byKey(const ValueKey("row-x")), findsOneWidget);

      // Sanity: the slide brought x to its new structural Y.
      final paintedYAfterSettle = tester
          .getTopLeft(find.byKey(const ValueKey("row-x")))
          .dy;
      expect(paintedYAfterSettle, isNot(paintedYBeforeMove));
    });
  });

  group("reparent during exit — visible source, collapsed destination", () {
    testWidgets("exit continues to extent 0 with pending-deletion cleared", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots(<TreeNode<String, String>>[
        const TreeNode<String, String>(key: "A", data: "A"),
        const TreeNode<String, String>(key: "B", data: "B"),
        const TreeNode<String, String>(key: "x", data: "x"),
      ]);
      controller.setChildren("A", <TreeNode<String, String>>[
        const TreeNode<String, String>(key: "a1", data: "a1"),
      ]);
      // A stays collapsed by default.

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Start animated remove on x, pump to mid-exit (priming pump for
      // standalone ticker baseline + timed pump for actual progress).
      controller.remove(key: "x", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 199));
      expect(
        controller.getAnimationState("x")?.type,
        AnimationType.exiting,
      );

      // Reparent x to A (which is collapsed). x is now structurally
      // hidden, so case 2 applies: keep the standalone exit running so
      // the row shrinks away smoothly without jumping; clear pending-
      // deletion so finalize preserves the structural data under A.
      controller.moveNode("x", "A", animate: true);
      await tester.pump();

      expect(controller.getParent("x"), "A");
      expect(
        controller.isPendingDeletion("x"),
        isFalse,
        reason: "case 2 clears pending-deletion so finalize skips purge",
      );
      expect(
        controller.getAnimationState("x")?.type,
        AnimationType.exiting,
        reason: "case 2 leaves the exit animation running",
      );

      // Drive to settle. x's structural data survives under A but the
      // row is not in visible order (A is collapsed).
      await tester.pumpAndSettle();
      expect(
        controller.getNodeData("x"),
        isNotNull,
        reason: "structural data preserved by case 2",
      );
      expect(controller.visibleNodes.contains("x"), isFalse);
      expect(find.byKey(const ValueKey("row-x")), findsNothing);

      // Expanding A reveals x at full extent (it's just a hidden member of
      // A's subtree now; expand uses the standard insert path).
      controller.expand(key: "A", animate: false);
      await tester.pump();
      expect(controller.visibleNodes.contains("x"), isTrue);
    });
  });

  group("reparent during exit — whole subtree exiting", () {
    testWidgets(
      "root and visible descendants reverse coherently; hidden descendants left alone",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        // Tree: dest (expanded with placeholder); P > [c, d] (P expanded).
        // Will move P under dest. dest's expansion is needed so the moved
        // subtree's ancestor chain is expanded post-move (case 1).
        controller.setRoots(<TreeNode<String, String>>[
          const TreeNode<String, String>(key: "dest", data: "dest"),
          const TreeNode<String, String>(key: "P", data: "P"),
        ]);
        controller.setChildren("dest", <TreeNode<String, String>>[
          const TreeNode<String, String>(key: "d1", data: "d1"),
        ]);
        controller.setChildren("P", <TreeNode<String, String>>[
          const TreeNode<String, String>(key: "c", data: "c"),
          const TreeNode<String, String>(key: "d", data: "d"),
        ]);
        controller.expand(key: "dest", animate: false);
        controller.expand(key: "P", animate: false);

        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Remove the whole P subtree.
        controller.remove(key: "P", animate: true);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 199));
        for (final k in <String>["P", "c", "d"]) {
          expect(controller.isPendingDeletion(k), isTrue);
          expect(
            controller.getAnimationState(k)?.type,
            AnimationType.exiting,
          );
        }
        final extentMidExit = <String, double>{
          "P": controller.getCurrentExtent("P"),
          "c": controller.getCurrentExtent("c"),
          "d": controller.getCurrentExtent("d"),
        };
        for (final v in extentMidExit.values) {
          expect(v, lessThan(48.0));
          expect(v, greaterThan(0.0));
        }

        // Reparent P under dest as its FIRST child (so P actually moves
        // upward in the visible order — appending after d1 would leave
        // P at roughly the same Y and produce no slide).
        controller.moveNode("P", "dest", index: 0, animate: true);
        await tester.pump();

        for (final k in <String>["P", "c", "d"]) {
          expect(
            controller.isPendingDeletion(k),
            isFalse,
            reason: "$k's pending-deletion cleared after reparent",
          );
          final state = controller.getAnimationState(k);
          expect(
            state?.type,
            AnimationType.entering,
            reason: "$k's exit reverses to enter (case 1)",
          );
          expect(
            state!.startExtent,
            closeTo(extentMidExit[k]!, 1.0),
            reason: "$k's enter starts from its mid-exit extent",
          );
        }
        expect(controller.hasActiveSlides, isTrue);

        await tester.pumpAndSettle();
        for (final k in <String>["P", "c", "d"]) {
          expect(controller.getCurrentExtent(k), closeTo(48.0, 0.001));
          expect(find.byKey(ValueKey("row-$k")), findsOneWidget);
        }
        expect(controller.getParent("P"), "dest");
        expect(controller.getParent("c"), "P");
        expect(controller.getParent("d"), "P");
      },
    );
  });

  group("reparent during exit — same-parent re-insert regression", () {
    // Pre-existing path: insert(parentKey:, preservePendingSubtreeState: true)
    // cancels the deletion in place. The sync controller's same-parent branch
    // still routes to insert (not moveNode), so this path must keep working
    // after the simplification.
    testWidgets("re-syncing the same parent during exit cancels in place", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots(<TreeNode<String, String>>[
        const TreeNode<String, String>(key: "A", data: "A"),
      ]);
      controller.setChildren("A", <TreeNode<String, String>>[
        const TreeNode<String, String>(key: "x", data: "x"),
      ]);
      controller.expand(key: "A", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.remove(key: "x", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 199));
      final extentMidExit = controller.getCurrentExtent("x");
      expect(extentMidExit, lessThan(48.0));
      expect(extentMidExit, greaterThan(0.0));

      // Cancel the deletion in place via insert with the preserve flag.
      controller.insert(
        parentKey: "A",
        node: const TreeNode<String, String>(key: "x", data: "x"),
        preservePendingSubtreeState: true,
      );
      await tester.pump();

      expect(controller.isPendingDeletion("x"), isFalse);
      expect(
        controller.getAnimationState("x")?.type,
        AnimationType.entering,
      );
      expect(
        controller.getAnimationState("x")!.startExtent,
        closeTo(extentMidExit, 1.0),
      );
      expect(controller.getParent("x"), "A");

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("row-x")), findsOneWidget);
    });
  });

  group("reparent during exit — via SyncedSliverTree", () {
    // End-to-end: the sync controller's reparent branch now routes
    // pending-deletion nodes through moveNode (Phase B) instead of the old
    // insertRoot(preservePendingSubtreeState: true) path. The user-visible
    // contract is that an exiting node, when re-synced under a different
    // parent mid-animation, smoothly composes its extent reversal with the
    // FLIP slide.
    testWidgets(
      "TreeSyncController routes mid-exit reparent through moveNode",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        final sync = TreeSyncController<String, String>(
          treeController: controller,
        );
        addTearDown(sync.dispose);

        // Initial: A; B (with placeholder so it can be expanded); x. B
        // expanded so when x reparents under B, x's ancestor chain is
        // expanded and Phase B reverses the exit (case 1) instead of
        // letting it play out (case 2).
        sync.syncRoots(
          <TreeNode<String, String>>[
            const TreeNode<String, String>(key: "A", data: "A"),
            const TreeNode<String, String>(key: "B", data: "B"),
            const TreeNode<String, String>(key: "x", data: "x"),
          ],
          childrenOf: (key) {
            if (key == "B") {
              return <TreeNode<String, String>>[
                const TreeNode<String, String>(key: "b1", data: "b1"),
              ];
            }
            return const <TreeNode<String, String>>[];
          },
          animate: false,
        );
        controller.expand(key: "B", animate: false);

        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Imperatively remove x to start the exit animation, then
        // resync with x living under B. The sync controller sees x as
        // "missing from desired roots, present under B's children" and
        // (post-refactor) routes through moveNode.
        controller.remove(key: "x", animate: true);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 199));
        expect(controller.isPendingDeletion("x"), isTrue);
        final extentMidExit = controller.getCurrentExtent("x");

        sync.syncRoots(
          <TreeNode<String, String>>[
            const TreeNode<String, String>(key: "A", data: "A"),
            const TreeNode<String, String>(key: "B", data: "B"),
          ],
          // x first under B so the move actually shifts its scroll-space
          // Y (otherwise a tail-append would land x where it already is
          // and produce a zero-delta slide).
          childrenOf: (key) {
            if (key == "B") {
              return <TreeNode<String, String>>[
                const TreeNode<String, String>(key: "x", data: "x"),
                const TreeNode<String, String>(key: "b1", data: "b1"),
              ];
            }
            return const <TreeNode<String, String>>[];
          },
          animate: true,
        );
        await tester.pump();

        expect(controller.getParent("x"), "B");
        expect(controller.isPendingDeletion("x"), isFalse);
        expect(
          controller.getAnimationState("x")?.type,
          AnimationType.entering,
          reason: "moveNode Phase B reversed the exit",
        );
        expect(
          controller.getAnimationState("x")!.startExtent,
          closeTo(extentMidExit, 1.0),
        );
        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "moveNode staged a FLIP slide; consume installed it",
        );

        await tester.pumpAndSettle();
        expect(controller.hasActiveSlides, isFalse);
        expect(find.byKey(const ValueKey("row-x")), findsOneWidget);
      },
    );
  });
}
