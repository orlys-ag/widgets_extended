import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/tree_sync_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';

// Sample the actual rendered layout offsets and visibleExtents for each node.
Map<String, ({double offset, double visibleExtent, double measuredHeight})>
    _sampleRenderState<K>(WidgetTester tester) {
  final result = <String, ({double offset, double visibleExtent, double measuredHeight})>{};
  final render =
      tester.renderObject<RenderSliverTree<String, String>>(find.byType(SliverTree<String, String>));
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    final nodeId = pd.nodeId as String?;
    if (nodeId != null) {
      result[nodeId] = (
        offset: pd.layoutOffset,
        visibleExtent: pd.visibleExtent,
        measuredHeight: child.size.height,
      );
    }
  });
  return result;
}

Widget _buildTree(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (context, key, depth) {
              return SizedBox(
                key: ValueKey(key),
                height: 100,
                child: Text("$key (depth=$depth)"),
              );
            },
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets("rendered extent is smooth across re-insert of leaf", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 300),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);

    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);

    await tester.pumpWidget(_buildTree(controller));
    await tester.pumpAndSettle();

    // Baseline: all three rendered at 100 each.
    final initial = _sampleRenderState(tester);
    expect(initial["a"]!.offset, 0);
    expect(initial["b"]!.offset, 100);
    expect(initial["c"]!.offset, 200);
    expect(initial["b"]!.visibleExtent, 100);

    // Remove 'b'. Exit animation starts.
    controller.remove(key: "b");
    await tester.pump();

    // Advance 150ms → mid-exit for b.
    await tester.pump(const Duration(milliseconds: 150));
    final mid = _sampleRenderState(tester);
    // b should be at ~50 visible extent; c should have shifted up to 150.
    expect(mid["b"]!.visibleExtent, closeTo(50, 2),
        reason: "b should be half-way through exit");
    expect(mid["c"]!.offset, closeTo(150, 2),
        reason: "c should follow b's shrinking");

    // NOW reinsert 'b' as root. Should reverse smoothly.
    controller.insertRoot(TreeNode(key: "b", data: "B"), index: 1);
    await tester.pumpAndSettle();
  });

  testWidgets("rendered extent smooth - direct insertRoot re-insert", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 300),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);

    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);

    await tester.pumpWidget(_buildTree(controller));
    await tester.pumpAndSettle();

    final initial = _sampleRenderState(tester);
    expect(initial["b"]!.offset, 100);

    controller.remove(key: "b");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final mid = _sampleRenderState(tester);
    final midBExtent = mid["b"]!.visibleExtent;
    final midCOffset = mid["c"]!.offset;
    // ignore: avoid_print
    print("Mid-exit: b.extent=$midBExtent, c.offset=$midCOffset");

    // Sample ACROSS the reinsert boundary without a pump in between.
    controller.insertRoot(TreeNode(key: "b", data: "B"), index: 1);
    // Still pre-pump — pumpWidget was the last frame.
    // Force a layout to see what the render layer produces now.
    await tester.pump(Duration.zero);
    final postReinsert = _sampleRenderState(tester);
    final postBExtent = postReinsert["b"]!.visibleExtent;
    final postCOffset = postReinsert["c"]!.offset;
    // ignore: avoid_print
    print("Post-reinsert (pump 0): b.extent=$postBExtent, c.offset=$postCOffset");

    // Critical test: the visible extent of b must not jump.
    expect(postBExtent, closeTo(midBExtent, 2),
        reason: "b's rendered extent jumped from $midBExtent to $postBExtent on reinsert");
    expect(postCOffset, closeTo(midCOffset, 2),
        reason: "c's offset jumped on reinsert");

    // Continue animation and sample each frame.
    final samples = <double>[postBExtent];
    final offsets = <double>[postCOffset];
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      final frame = _sampleRenderState(tester);
      final b = frame["b"];
      final c = frame["c"];
      if (b != null) samples.add(b.visibleExtent);
      if (c != null) offsets.add(c.offset);
    }
    // ignore: avoid_print
    print("b extent samples: $samples");
    // ignore: avoid_print
    print("c offset samples: $offsets");

    // Monotonic increase for b, monotonic increase for c.
    for (int i = 1; i < samples.length; i++) {
      if (samples[i] + 0.5 < samples[i - 1]) {
        fail("b extent non-monotonic: ${samples[i - 1]} -> ${samples[i]}");
      }
    }
    for (int i = 1; i < offsets.length; i++) {
      if (offsets[i] + 0.5 < offsets[i - 1]) {
        fail("c offset non-monotonic: ${offsets[i - 1]} -> ${offsets[i]}");
      }
    }
    await tester.pumpAndSettle();
  });

  testWidgets(
    "rendered extent smooth - re-insert of parent with expanded children (default path)",
    (tester) async {
      // This is the case I suspect causes a visible skip: 'b' has child 'b1'
      // expanded and visible. Remove 'b' → both get exit animations. Reinsert
      // 'b' WITHOUT preservePendingSubtreeState → 'b1' gets yanked out.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      controller.setChildren("b", [TreeNode(key: "b1", data: "B1")]);
      controller.expand(key: "b", animate: false);

      await tester.pumpWidget(_buildTree(controller));
      await tester.pumpAndSettle();

      final initial = _sampleRenderState(tester);
      // ignore: avoid_print
      print("Initial: $initial");
      // Order: a (0), b (100), b1 (200), c (300).
      expect(initial["b1"]!.offset, 200);
      expect(initial["c"]!.offset, 300);

      controller.remove(key: "b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final mid = _sampleRenderState(tester);
      // ignore: avoid_print
      print("Mid-exit: $mid");
      final cOffsetMid = mid["c"]!.offset;
      final b1ExtentMid = mid["b1"]!.visibleExtent;

      // Now reinsert WITHOUT preserveSubtreeState (default).
      controller.insertRoot(TreeNode(key: "b", data: "B"), index: 1);
      await tester.pump(Duration.zero);

      final post = _sampleRenderState(tester);
      // ignore: avoid_print
      print("Post-reinsert: $post");

      // If b1 was yanked out, c's offset would jump UP by b1's current extent.
      final cOffsetPost = post["c"]!.offset;
      final jump = (cOffsetPost - cOffsetMid).abs();
      if (jump > 5) {
        // ignore: avoid_print
        print(
            "DETECTED VISUAL SKIP: c offset jumped from $cOffsetMid to $cOffsetPost (delta=$jump)");
      }
      // The reasonable thing: c should stay roughly where it was.
      // This test DOCUMENTS the current behavior.
      expect(cOffsetPost, closeTo(cOffsetMid, 5),
          reason:
              "c should not visually jump on reinsert. midOffset=$cOffsetMid postOffset=$cOffsetPost. "
              "b1ExtentMid=$b1ExtentMid. If jump is ~$b1ExtentMid, b1 was removed from visible order.");
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "rendered extent smooth - re-insert of parent with expanded children (preserveSubtreeState=true)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      controller.setChildren("b", [TreeNode(key: "b1", data: "B1")]);
      controller.expand(key: "b", animate: false);

      await tester.pumpWidget(_buildTree(controller));
      await tester.pumpAndSettle();

      controller.remove(key: "b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final mid = _sampleRenderState(tester);
      final cOffsetMid = mid["c"]!.offset;
      // ignore: avoid_print
      print("Mid-exit: c.offset=$cOffsetMid");

      controller.insertRoot(
        TreeNode(key: "b", data: "B"),
        index: 1,
        preservePendingSubtreeState: true,
      );
      await tester.pump(Duration.zero);

      final post = _sampleRenderState(tester);
      final cOffsetPost = post["c"]!.offset;
      // ignore: avoid_print
      print("Post-reinsert: c.offset=$cOffsetPost");

      expect(cOffsetPost, closeTo(cOffsetMid, 2),
          reason:
              "With preserveSubtreeState, c should not jump. mid=$cOffsetMid post=$cOffsetPost");

      // Continue and verify smooth animation back to full.
      await tester.pumpAndSettle();
      final done = _sampleRenderState(tester);
      expect(done["b"]!.visibleExtent, 100);
      expect(done["b1"]!.visibleExtent, 100);
      expect(done["c"]!.offset, 300);
    },
  );

  testWidgets(
    "rendered extent smooth via TreeSyncController - re-insert mid-exit",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      sync.syncRoots(
        [
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
          TreeNode(key: "c", data: "C"),
        ],
        animate: false,
      );

      await tester.pumpWidget(_buildTree(controller));
      await tester.pumpAndSettle();

      // Remove b via sync.
      sync.syncRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "c", data: "C"),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final mid = _sampleRenderState(tester);
      // ignore: avoid_print
      print("Mid-exit via sync: $mid");
      final cOffsetMid = mid["c"]!.offset;
      final bExtentMid = mid["b"]?.visibleExtent ?? -1;

      // Re-add b via sync.
      sync.syncRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      await tester.pump(Duration.zero);

      final post = _sampleRenderState(tester);
      // ignore: avoid_print
      print("Post-reinsert via sync: $post");
      final cOffsetPost = post["c"]!.offset;
      final bExtentPost = post["b"]!.visibleExtent;

      expect(bExtentPost, closeTo(bExtentMid, 2),
          reason: "b extent jumped on re-sync. mid=$bExtentMid post=$bExtentPost");
      expect(cOffsetPost, closeTo(cOffsetMid, 2),
          reason: "c offset jumped on re-sync. mid=$cOffsetMid post=$cOffsetPost");
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "remove-reinsert-remove again does not corrupt descendant state",
    (tester) async {
      // After remove + default reinsert, descendants are kept mid-exit with
      // pendingDeletion cleared. A subsequent remove() should re-enter those
      // descendants into pendingDeletion cleanly and they should finalize
      // as normal.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("b", [TreeNode(key: "b1", data: "B1")]);
      controller.expand(key: "b", animate: false);

      await tester.pumpWidget(_buildTree(controller));
      await tester.pumpAndSettle();

      // Remove b (animates out).
      controller.remove(key: "b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Reinsert b (default path).
      controller.insertRoot(TreeNode(key: "b", data: "B"), index: 1);
      await tester.pump();

      // b1 should still exist structurally (mid-exit).
      expect(controller.getNodeData("b1"), isNotNull,
          reason: "b1 should not have been purged by the re-insert");
      expect(controller.getParent("b1"), "b",
          reason: "b1 should still be a child of b");

      // Remove b again. This exercises the "pending re-entry" path.
      controller.remove(key: "b");
      await tester.pumpAndSettle();

      // After full settle: b and b1 should both be fully purged.
      expect(controller.getNodeData("b"), isNull,
          reason: "b should be purged after second remove + settle");
      expect(controller.getNodeData("b1"), isNull,
          reason: "b1 should be purged after second remove + settle");
      expect(controller.rootKeys, ["a"]);
    },
  );

  testWidgets(
    "reinsert then re-expand restores descendants smoothly",
    (tester) async {
      // Remove a parent with an expanded subtree. Midway, re-insert it
      // (collapsed by default). Then re-expand it. Descendants should
      // animate back up from whatever extent their exit left them at.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      controller.setChildren("b", [TreeNode(key: "b1", data: "B1")]);
      controller.expand(key: "b", animate: false);

      await tester.pumpWidget(_buildTree(controller));
      await tester.pumpAndSettle();

      controller.remove(key: "b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Reinsert b collapsed (default).
      controller.insertRoot(TreeNode(key: "b", data: "B"), index: 1);
      await tester.pump();

      // Re-expand b — b1 should animate back to full height.
      controller.expand(key: "b");
      await tester.pumpAndSettle();

      final final_ = _sampleRenderState(tester);
      expect(final_["b"]!.visibleExtent, 100);
      expect(final_["b1"]!.visibleExtent, 100);
      expect(final_["a"]!.offset, 0);
      expect(final_["b"]!.offset, 100);
      expect(final_["b1"]!.offset, 200);
      expect(final_["c"]!.offset, 300);
    },
  );

  testWidgets(
    "insert new child mid-collapse then re-expand preserves child order",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "root", data: "root"),
      ]);
      controller.setChildren("root", [
        const TreeNode(key: "a", data: "a"),
        const TreeNode(key: "c", data: "c"),
      ]);
      controller.expand(key: "root", animate: false);

      await tester.pumpWidget(_buildTree(controller));
      await tester.pumpAndSettle();

      // Start collapse animation on root.
      controller.collapse(key: "root");
      await tester.pump(const Duration(milliseconds: 50));

      // Mid-collapse, insert "b" between a and c.
      controller.insert(
        node: const TreeNode(key: "b", data: "b"),
        parentKey: "root",
        index: 1,
      );

      // Re-expand root — reverses the collapse animation.
      controller.expand(key: "root");
      await tester.pumpAndSettle();

      // Verify visible order is [root, a, b, c] — "b" inserted at correct
      // position, not appended after c.
      final finalOrder = controller.visibleNodes.toList();
      expect(finalOrder, ["root", "a", "b", "c"]);
    },
  );

  testWidgets(
    "insert sibling during collapse animation places after collapsing subtree",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "root", data: "root")]);
      controller.setChildren("root", [
        const TreeNode(key: "a", data: "a"),
        const TreeNode(key: "c", data: "c"),
      ]);
      controller.setChildren("a", [const TreeNode(key: "a1", data: "a1")]);
      controller.expand(key: "root", animate: false);
      controller.expand(key: "a", animate: false);

      await tester.pumpWidget(_buildTree(controller));
      await tester.pumpAndSettle();

      expect(
        controller.visibleNodes.toList(),
        ["root", "a", "a1", "c"],
      );

      controller.collapse(key: "a");
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        controller.visibleNodes.toList(),
        ["root", "a", "a1", "c"],
      );

      controller.insert(
        node: const TreeNode(key: "b", data: "b"),
        parentKey: "root",
        index: 1,
      );

      expect(
        controller.visibleNodes.toList(),
        ["root", "a", "a1", "b", "c"],
      );

      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), ["root", "a", "b", "c"]);
    },
  );
}
