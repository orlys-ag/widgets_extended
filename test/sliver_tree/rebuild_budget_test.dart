import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Rebuild-budget regression tests.
///
/// The delta-refresh channel (addStructuralListener + affectedKeys) is the
/// main defense against the O(mountedRows) rebuild spike that used to fire
/// at the end of every structural mutation — most visibly, the ~1150
/// _TreeTile rebuilds seen when a 1150-child node finished expanding.
///
/// These tests pin the contract so it can't silently regress: each
/// mutation must only rebuild the keys it declares affected, not every
/// mounted row.

Widget _harness({
  required TreeController<String, String> controller,
  required Widget Function(BuildContext, String, int) nodeBuilder,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: nodeBuilder,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets("expand rebuilds only the toggled node, not siblings", (
    tester,
  ) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);

    final counts = <String, int>{};
    await tester.pumpWidget(
      _harness(
        controller: controller,
        nodeBuilder: (context, key, depth) {
          counts[key] = (counts[key] ?? 0) + 1;
          return SizedBox(height: 48, child: Text(key));
        },
      ),
    );
    final before = Map<String, int>.from(counts);

    controller.expand(key: "a");
    await tester.pump();

    expect(
      counts["a"]!,
      greaterThan(before["a"]!),
      reason: "the toggled node rebuilds so its chevron state updates",
    );
    expect(counts["b"], before["b"], reason: "sibling b must not rebuild");
    expect(counts["c"], before["c"], reason: "sibling c must not rebuild");
  });

  testWidgets("collapse rebuilds only the toggled node, not siblings", (
    tester,
  ) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
    controller.expand(key: "a");

    final counts = <String, int>{};
    await tester.pumpWidget(
      _harness(
        controller: controller,
        nodeBuilder: (context, key, depth) {
          counts[key] = (counts[key] ?? 0) + 1;
          return SizedBox(height: 48, child: Text(key));
        },
      ),
    );
    final before = Map<String, int>.from(counts);

    controller.collapse(key: "a");
    await tester.pump();

    expect(counts["a"]!, greaterThan(before["a"]!));
    expect(counts["b"], before["b"]);
    expect(counts["c"], before["c"]);
  });

  testWidgets(
    "animated expand of a large subtree does not spike siblings on completion",
    (tester) async {
      // Reproduces the original 1150-child scenario in miniature. The exact
      // count doesn't matter for the assertion — we only care that sibling
      // rebuilds stay at their pre-expand counts throughout the animation,
      // including when the animation completes (the site that used to
      // fire _notifyStructural unconditionally at .completed, causing the
      // O(mountedRows) rebuild spike).
      //
      // Only a top sibling is used; a bottom sibling would get pushed off
      // the viewport by the expanded children and never mount, which
      // defeats the test (an unmounted row obviously can't rebuild).
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "siblingTop", data: "ST"),
        TreeNode(key: "parent", data: "P"),
      ]);
      controller.setChildren("parent", [
        for (int i = 0; i < 40; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);

      final counts = <String, int>{};
      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            counts[key] = (counts[key] ?? 0) + 1;
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      final siblingTopBefore = counts["siblingTop"]!;

      controller.expand(key: "parent");
      await tester.pumpAndSettle();

      expect(
        counts["siblingTop"],
        siblingTopBefore,
        reason:
            "siblingTop must not rebuild during or after the expand animation",
      );
    },
  );

  testWidgets(
    "animated collapse of a large subtree does not spike siblings on "
    "completion",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "siblingTop", data: "ST"),
        TreeNode(key: "parent", data: "P"),
      ]);
      controller.setChildren("parent", [
        for (int i = 0; i < 40; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);
      controller.expand(key: "parent", animate: false);

      final counts = <String, int>{};
      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            counts[key] = (counts[key] ?? 0) + 1;
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      final siblingTopBefore = counts["siblingTop"]!;

      controller.collapse(key: "parent");
      await tester.pumpAndSettle();

      expect(counts["siblingTop"], siblingTopBefore);
    },
  );

  testWidgets(
    "insert to an already-populated parent does not rebuild siblings",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "p", data: "P"),
        TreeNode(key: "other", data: "O"),
      ]);
      controller.setChildren("p", [TreeNode(key: "existing", data: "E")]);
      controller.expand(key: "p");

      final counts = <String, int>{};
      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            counts[key] = (counts[key] ?? 0) + 1;
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      final before = Map<String, int>.from(counts);

      controller.insert(
        parentKey: "p",
        node: TreeNode(key: "fresh", data: "F"),
        animate: false,
      );
      await tester.pump();

      expect(
        counts["p"],
        before["p"],
        reason: "parent already had children — hasChildren did not flip",
      );
      expect(counts["existing"], before["existing"]);
      expect(counts["other"], before["other"]);
    },
  );

  testWidgets(
    "insert into an empty parent rebuilds the parent (hasChildren flip) "
    "but no siblings",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "p", data: "P"),
        TreeNode(key: "other", data: "O"),
      ]);
      // "p" has no children yet.

      final counts = <String, int>{};
      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            counts[key] = (counts[key] ?? 0) + 1;
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      final before = Map<String, int>.from(counts);

      controller.insert(
        parentKey: "p",
        node: TreeNode(key: "first", data: "F"),
        animate: false,
      );
      await tester.pump();

      expect(
        counts["p"]!,
        greaterThan(before["p"]!),
        reason: "parent's hasChildren flipped false → true; its chevron row "
            "needs to rebuild",
      );
      expect(
        counts["other"],
        before["other"],
        reason: "unrelated root sibling must not rebuild",
      );
    },
  );

  testWidgets(
    "removing the last child rebuilds the parent but no siblings",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "p", data: "P"),
        TreeNode(key: "other", data: "O"),
      ]);
      controller.setChildren("p", [TreeNode(key: "only", data: "ONLY")]);
      controller.expand(key: "p");

      final counts = <String, int>{};
      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            counts[key] = (counts[key] ?? 0) + 1;
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      final before = Map<String, int>.from(counts);

      controller.remove(key: "only", animate: false);
      await tester.pump();

      expect(
        counts["p"]!,
        greaterThan(before["p"]!),
        reason:
            "parent lost its last child — hasChildren flipped true → false",
      );
      expect(counts["other"], before["other"]);
    },
  );

  testWidgets("reorderRoots does not rebuild any row", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);

    final counts = <String, int>{};
    await tester.pumpWidget(
      _harness(
        controller: controller,
        nodeBuilder: (context, key, depth) {
          counts[key] = (counts[key] ?? 0) + 1;
          return SizedBox(height: 48, child: Text(key));
        },
      ),
    );
    final before = Map<String, int>.from(counts);

    controller.reorderRoots(["c", "a", "b"]);
    await tester.pump();

    expect(counts["a"], before["a"]);
    expect(counts["b"], before["b"]);
    expect(counts["c"], before["c"]);
  });

  testWidgets(
    "single-node expand does not build every entering child on frame 1",
    (tester) async {
      // Reproduces the original DevTools observation: expanding a node with
      // 1150 children caused 1151 _TreeTile rebuilds (parent + every child)
      // on the very first frame of the animation. Root cause was Pass 2's
      // cache-region admission reading live animated offsets — at animation
      // value ≈ 0 every entering child sat at ~parent.offset with ~0 extent,
      // so the `offset >= cacheEnd` break never fired and createChild ran
      // for all 1150. After the fix, admission is capped at what fits the
      // cache region at *steady-state* extents, mirroring the bulk-only
      // fast path's rationale.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "parent", data: "P")]);
      controller.setChildren("parent", [
        for (int i = 0; i < 1150; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);

      final builds = <String, int>{};
      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            builds[key] = (builds[key] ?? 0) + 1;
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );

      controller.expand(key: "parent");
      await tester.pump();

      final childBuildCount = builds.keys
          .where((k) => k.startsWith("c"))
          .length;
      // Default test surface is 800x600. At 48px/row + default cache band,
      // a steady-state-anchored cache region holds on the order of ~30 rows,
      // nowhere near 1150. Guard with a generous 100-row ceiling so the
      // assertion stays stable across Flutter's cache-extent tweaks but
      // still fails hard if the mass-admission regression returns.
      expect(
        childBuildCount,
        lessThan(100),
        reason:
            "only the cache-region slice of entering children should build "
            "on frame 1, not all 1150",
      );

      // Settle the op-group animation so its ticker disposes cleanly.
      await tester.pumpAndSettle();
    },
  );

  testWidgets("updateNode rebuilds only the updated node", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
    ]);

    final counts = <String, int>{};
    await tester.pumpWidget(
      _harness(
        controller: controller,
        nodeBuilder: (context, key, depth) {
          counts[key] = (counts[key] ?? 0) + 1;
          final data = controller.getNodeData(key)?.data ?? "";
          return SizedBox(height: 48, child: Text(data));
        },
      ),
    );
    final before = Map<String, int>.from(counts);

    controller.updateNode(TreeNode(key: "b", data: "B-updated"));
    await tester.pump();

    expect(counts["a"], before["a"]);
    expect(counts["b"]!, greaterThan(before["b"]!));
    expect(find.text("B-updated"), findsOneWidget);
  });
}
