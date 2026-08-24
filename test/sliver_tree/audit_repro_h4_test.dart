import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Repro tests for H4: depth-limited `expandAll` / `collapseAll` must act
/// on POST-FLIP visibility, not on "is this group collapsing/expanding".
/// Pre-fix, `expandAll(maxDepth:)` harvested exiting children depth-blind
/// and un-pended every reversing group wholesale, growing rows back to
/// full extent under parents that stayed collapsed (zombie rows the
/// terminal handlers never remove); `collapseAll(maxDepth:)` dragged rows
/// to zero, or removed them outright on the non-animated path, even when
/// the depth limit flipped nothing.
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

  testWidgets("case 1: depth-gated harvest leaves a deeper group pended", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([const TreeNode(key: "a", data: "A")]);
    controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
    controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
    controller.expand(key: "a", animate: false);
    controller.expand(key: "b", animate: false);

    controller.collapse(key: "b");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.isExiting("c"),
      isTrue,
      reason: "setup sanity: c must be mid-collapse in b's op group",
    );
    expect(
      controller.isExpanded("b"),
      isFalse,
      reason: "setup sanity: the collapse flipped b",
    );

    controller.expandAll(maxDepth: 1);
    await tester.pumpAndSettle();

    expect(
      controller.visibleNodes,
      ["a", "b"],
      reason:
          "b sits at the depth limit and stayed collapsed, so c must "
          "finish collapsing and leave the order instead of growing back "
          "as a permanent hidden-parent row",
    );
    expect(controller.isExpanded("b"), isFalse);
  });

  testWidgets("case 2: bulk pending partitions by post-flip visibility", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([const TreeNode(key: "a", data: "A")]);
    controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
    controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
    controller.expand(key: "a", animate: false);
    controller.expand(key: "b", animate: false);

    controller.collapseAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.isBulkMember("b"),
      isTrue,
      reason: "setup sanity: b must be collapsing in the bulk group",
    );
    expect(
      controller.isBulkMember("c"),
      isTrue,
      reason: "setup sanity: c must be collapsing in the bulk group",
    );

    controller.expandAll(maxDepth: 1);
    await tester.pumpAndSettle();

    expect(
      controller.visibleNodes,
      ["a", "b"],
      reason:
          "only b is post-flip visible; c's chain stays collapsed, so c "
          "must finish exiting instead of being un-pended wholesale",
    );
    expect(controller.isExpanded("a"), isTrue);
    expect(controller.isExpanded("b"), isFalse);
  });

  testWidgets("case 3: one call, one group un-pends and one group skips", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([const TreeNode(key: "r", data: "R")]);
    controller.setChildren("r", [const TreeNode(key: "a", data: "A")]);
    controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
    controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
    controller.expand(key: "r", animate: false);
    controller.expand(key: "a", animate: false);
    controller.expand(key: "b", animate: false);

    controller.collapse(key: "a");
    controller.collapse(key: "r");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.isExiting("a"),
      isTrue,
      reason: "setup sanity: a must be mid-collapse in r's op group",
    );
    expect(
      controller.isExiting("b"),
      isTrue,
      reason: "setup sanity: b must be mid-collapse in a's op group",
    );
    expect(
      controller.isExiting("c"),
      isTrue,
      reason: "setup sanity: c must be mid-collapse in a's op group",
    );
    expect(
      controller.isExpanded("b"),
      isTrue,
      reason:
          "setup sanity: collapse(a) must not clear b's own expansion "
          "flag; b and c are hidden by a's collapse alone",
    );

    controller.expandAll(maxDepth: 1);
    await tester.pumpAndSettle();

    expect(
      controller.visibleNodes,
      ["r", "a"],
      reason:
          "group r's member a is post-flip visible and grows back; group "
          "a's members b and c are post-flip hidden and must finish "
          "collapsing away instead of growing under collapsed a",
    );
    expect(controller.isExpanded("r"), isTrue);
    expect(controller.isExpanded("a"), isFalse);
  });

  testWidgets(
    "case 4: collapseAll(maxDepth: 0) leaves a mid-expand bulk group alone",
    (tester) async {
      final controller = makeController(tester);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);

      controller.expandAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        controller.isBulkMember("b"),
        isTrue,
        reason: "setup sanity: b must be mid-expand in the bulk group",
      );
      final base = controller.getCurrentExtent("b");
      expect(
        base,
        greaterThan(0.0),
        reason: "setup sanity: b must be mid-flight, not at zero",
      );
      expect(
        base,
        lessThan(controller.getEstimatedExtent("b")),
        reason: "setup sanity: b must be mid-flight, not settled",
      );

      controller.collapseAll(maxDepth: 0);

      double prev = controller.getCurrentExtent("b");
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = controller.getCurrentExtent("b");
        expect(
          now,
          greaterThanOrEqualTo(prev - 0.001),
          reason:
              "maxDepth: 0 flipped nothing, so the expanding bulk group "
              "must be left untouched; the extent must never decrease "
              "(frame $i: $prev -> $now)",
        );
        prev = now;
        if (!controller.hasActiveAnimations) {
          break;
        }
      }

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, ["a", "b", "c"]);
    },
  );

  testWidgets(
    "case 5: collapseAll(maxDepth: 0, animate: false) removes nothing",
    (tester) async {
      final controller = makeController(tester);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [const TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [const TreeNode(key: "c", data: "C")]);
      controller.expand(key: "a", animate: false);
      controller.expand(key: "b", animate: false);

      controller.collapseAll(maxDepth: 0, animate: false);

      expect(
        controller.visibleNodes,
        ["a", "b", "c"],
        reason:
            "maxDepth: 0 collapses nothing, so the non-animated branch "
            "must not remove still-visible rows from the order",
      );
      expect(controller.isExpanded("a"), isTrue);
    },
  );
}
