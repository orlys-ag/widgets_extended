/// Regression test for "rapid re-parenting leaves visual gaps in the
/// viewport, only resolved by a subsequent scroll/re-layout".
///
/// The test queries the live render layer after each cascaded batch:
/// for every visible-order row whose structural Y intersects the
/// viewport, we expect `RenderSliverTree.getChildForNode` to return a
/// non-null render box. A null render box means the row was either
/// never built (Pass 2 admission missed it) or evicted by the
/// post-frame stale-eviction sweep before the user could see it. Either
/// way, paint will skip the row and leave an empty slot.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;

Widget _harness(
  TreeController<String, int> controller, {
  ScrollController? scrollController,
  double height = _kViewportHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scrollController,
          slivers: <Widget>[
            SliverTree<String, int>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _kRowHeight,
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _populateTree(TreeController<String, int> controller) {
  controller.runBatch(() {
    final parents = <TreeNode<String, int>>[
      for (int i = 0; i < 8; i++)
        TreeNode<String, int>(key: "parent-$i", data: i),
    ];
    controller.setRoots(parents);
    int n = 0;
    for (int p = 0; p < 8; p++) {
      final children = <TreeNode<String, int>>[
        for (int i = 0; i < 30; i++)
          TreeNode<String, int>(key: "item-${n++}", data: n),
      ];
      controller.setChildren("parent-$p", children);
      controller.expand(key: "parent-$p", animate: false);
    }
  });
}

void _reparentBatch(
  TreeController<String, int> controller,
  Random random,
  int count,
) {
  final all = <String>[];
  for (int p = 0; p < 8; p++) {
    all.addAll(controller.getChildren("parent-$p"));
  }
  all.shuffle(random);
  for (final item in all.take(count)) {
    final currentParent = controller.getParent(item);
    if (currentParent == null) continue;
    int target;
    do {
      target = random.nextInt(8);
    } while ("parent-$target" == currentParent);
    final newSiblings = controller.getLiveChildren("parent-$target");
    final newIndex =
        newSiblings.isEmpty ? 0 : random.nextInt(newSiblings.length + 1);
    controller.moveNode(
      item,
      "parent-$target",
      index: newIndex,
      animate: true,
      slideDuration: const Duration(milliseconds: 800),
      slideCurve: Curves.linear,
    );
  }
}

/// Walks visibleNodes accumulating actual extents from the controller
/// (not assuming uniform 50px). For each row whose structural Y
/// intersects the viewport, asserts `getChildForNode` returns non-null.
void _expectNoEmptyRenderBoxesInViewport(
  WidgetTester tester,
  TreeController<String, int> controller,
  ScrollController scroll, {
  required String phase,
}) {
  final render = tester.renderObject<RenderSliverTree<String, int>>(
    find.byType(SliverTree<String, int>),
  );

  final scrollOffset = scroll.offset;
  final viewportTop = scrollOffset;
  final viewportBottom = scrollOffset + _kViewportHeight;

  final visible = controller.visibleNodes;
  double cumulativeY = 0.0;
  final missingRenderBoxes = <String>[];
  for (var i = 0; i < visible.length; i++) {
    final key = visible[i];
    final extent = controller.getCurrentExtent(key);
    final rowTop = cumulativeY;
    final rowBottom = cumulativeY + extent;
    cumulativeY += extent;
    if (rowBottom <= viewportTop) continue;
    if (rowTop >= viewportBottom) break;
    if (render.getChildForNode(key) == null) {
      missingRenderBoxes.add(
        "$key (visIdx=$i, structuralY=$rowTop, viewport-y=${rowTop - scrollOffset})",
      );
    }
  }
  expect(missingRenderBoxes, isEmpty,
      reason: "[$phase] viewport has rows with no render box (gaps): "
          "$missingRenderBoxes");
}

/// Post-settle invariant: every viewport row paints at its structural
/// Y (no residual slide delta). Differences from the structural slot
/// mean a slide didn't fully resolve.
void _expectAllRowsAtStructuralPostSettle(
  WidgetTester tester,
  TreeController<String, int> controller,
  ScrollController scroll, {
  required String phase,
}) {
  final render = tester.renderObject<RenderSliverTree<String, int>>(
    find.byType(SliverTree<String, int>),
  );
  final scrollOffset = scroll.offset;
  final viewportTop = scrollOffset;
  final viewportBottom = scrollOffset + _kViewportHeight;

  final visible = controller.visibleNodes;
  double cumulativeY = 0.0;
  final misplaced = <String>[];
  final slidesActive = <String>[];
  for (var i = 0; i < visible.length; i++) {
    final key = visible[i];
    final extent = controller.getCurrentExtent(key);
    final rowTop = cumulativeY;
    final rowBottom = cumulativeY + extent;
    cumulativeY += extent;
    if (rowBottom <= viewportTop) continue;
    if (rowTop >= viewportBottom) break;
    final box = render.getChildForNode(key);
    if (box == null) continue;
    final pd = box.parentData;
    if (pd is! SliverTreeParentData) continue;
    final actualLayoutOffset = pd.layoutOffset;
    if ((actualLayoutOffset - rowTop).abs() > 0.5) {
      misplaced.add(
        "$key visIdx=$i: parentData.layoutOffset=$actualLayoutOffset "
        "expected=$rowTop diff=${actualLayoutOffset - rowTop}",
      );
    }
    final slideDelta = controller.getSlideDelta(key);
    if (slideDelta.abs() > 0.5) {
      slidesActive.add("$key delta=$slideDelta");
    }
  }
  expect(slidesActive, isEmpty,
      reason: "[$phase] post-settle but slide deltas non-zero: "
          "$slidesActive");
  expect(misplaced, isEmpty,
      reason: "[$phase] post-settle viewport rows have stale "
          "parentData.layoutOffset: $misplaced");
}

void main() {
  group("rapid reparent: no missing render boxes in viewport", () {
    testWidgets(
      "after 3 cascaded batches with mid-flight scroll perturbations + "
      "settle, every viewport row has a render box (no gaps)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 800),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(5000);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(7);
        for (int batch = 0; batch < 3; batch++) {
          _reparentBatch(controller, random, 10);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          _expectNoEmptyRenderBoxesInViewport(
            tester, controller, scroll,
            phase: "batch $batch mid-flight",
          );
          scroll.jumpTo(5000 + 100.0 * (batch + 1));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          _expectNoEmptyRenderBoxesInViewport(
            tester, controller, scroll,
            phase: "batch $batch post-scroll",
          );
        }

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "post-settle",
        );
      },
    );

    testWidgets(
      "5 cascaded batches without scroll perturbation + settle: every "
      "viewport row has a render box",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 600),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(4000);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(99);
        for (int batch = 0; batch < 5; batch++) {
          _reparentBatch(controller, random, 12);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "post-settle",
        );
      },
    );

    testWidgets(
      "after a single 30-move reparent batch + settle: viewport fully "
      "populated",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 600),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(3500);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(33);
        _reparentBatch(controller, random, 30);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Sample mid-flight too.
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "30-move mid-flight",
        );

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "post-settle",
        );
      },
    );

    testWidgets(
      "long-duration (1500ms) heavy toggling: 8 batches at ~150ms "
      "intervals (so each batch lands well before the prior settled)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1500),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(4500);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(123);
        // 8 batches at 150ms intervals — slides from earlier batches
        // are still in flight when later ones land.
        for (int batch = 0; batch < 8; batch++) {
          _reparentBatch(controller, random, 12);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          _expectNoEmptyRenderBoxesInViewport(
            tester, controller, scroll,
            phase: "long-toggle batch $batch",
          );
        }

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "long-toggle post-settle",
        );
        _expectAllRowsAtStructuralPostSettle(
          tester, controller, scroll,
          phase: "long-toggle post-settle",
        );
      },
    );

    testWidgets(
      "long-duration toggling + concurrent scroll: 6 batches with "
      "scroll perturbations interleaved",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1500),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(4500);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(321);
        for (int batch = 0; batch < 6; batch++) {
          _reparentBatch(controller, random, 15);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          _expectNoEmptyRenderBoxesInViewport(
            tester, controller, scroll,
            phase: "scroll-toggle batch $batch mid-flight",
          );
          // Scroll perturbation.
          final delta = (batch % 2 == 0) ? 80.0 : -80.0;
          scroll.jumpTo((scroll.offset + delta).clamp(0.0, 10000.0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          _expectNoEmptyRenderBoxesInViewport(
            tester, controller, scroll,
            phase: "scroll-toggle batch $batch post-scroll",
          );
        }

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "scroll-toggle post-settle",
        );
      },
    );

    testWidgets(
      "true toggle: same items moved back-and-forth between two "
      "parents at 100ms intervals during 1500ms slides",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1500),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(2000);
        await tester.pump();
        await tester.pumpAndSettle();

        // 10 specific items toggled between parent-1 and parent-5.
        final toggleItems = ["item-30", "item-31", "item-32", "item-33",
            "item-34", "item-150", "item-151", "item-152", "item-153",
            "item-154"];
        // Confirm starting parents.
        for (final item in toggleItems) {
          final parent = controller.getParent(item);
          expect(parent, isNotNull,
              reason: "item $item must exist with a parent");
        }

        // Toggle 6 times: alternately move all 10 items to the other
        // parent.
        for (int batch = 0; batch < 6; batch++) {
          final targetParent = batch % 2 == 0 ? "parent-5" : "parent-1";
          for (final item in toggleItems) {
            final currentParent = controller.getParent(item);
            if (currentParent == targetParent) continue;
            controller.moveNode(
              item,
              targetParent,
              animate: true,
              slideDuration: const Duration(milliseconds: 1500),
              slideCurve: Curves.linear,
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          _expectNoEmptyRenderBoxesInViewport(
            tester, controller, scroll,
            phase: "true-toggle batch $batch",
          );
        }

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "true-toggle post-settle",
        );
        _expectAllRowsAtStructuralPostSettle(
          tester, controller, scroll,
          phase: "true-toggle post-settle",
        );
      },
    );

    testWidgets(
      "rapid toggle (very short interval): 10 batches at 50ms "
      "intervals during 1500ms slides — each new batch arrives while "
      "previous is barely 3% in",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1500),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(5000);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(7777);
        for (int batch = 0; batch < 10; batch++) {
          _reparentBatch(controller, random, 10);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }
        // Sample mid-flight after the cascade.
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "rapid-toggle mid-flight",
        );

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "rapid-toggle post-settle",
        );
      },
    );

    testWidgets(
      "specific same-key cascaded toggles: same item moved A→B→A→B→A "
      "across 5 rapid frames. Verifies it ends up at FINAL position "
      "post-settle (not stuck at any intermediate)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1500),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(2000);
        await tester.pump();
        await tester.pumpAndSettle();

        // item-30 starts in parent-1.
        final initialParent = controller.getParent("item-30")!;
        // Toggle item-30 between parent-1 and parent-5 five times,
        // 50ms apart (each toggle interrupts the prior slide).
        final parents = ["parent-5", "parent-1", "parent-5", "parent-1",
            "parent-5"];
        for (final target in parents) {
          controller.moveNode(
            "item-30",
            target,
            animate: true,
            slideDuration: const Duration(milliseconds: 1500),
            slideCurve: Curves.linear,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }

        await tester.pumpAndSettle();

        // After settle: item-30 should be a child of parent-5.
        expect(controller.getParent("item-30"), "parent-5",
            reason: "item-30 should be in parent-5 after toggles end at "
                "parent-5 (initial parent was $initialParent).");

        // The render box should be at the correct viewport position.
        final render = tester.renderObject<RenderSliverTree<String, int>>(
          find.byType(SliverTree<String, int>),
        );
        final box = render.getChildForNode("item-30");
        if (box != null) {
          final pd = box.parentData;
          if (pd is SliverTreeParentData) {
            // Compute expected layoutOffset from controller order.
            double expectedY = 0.0;
            for (final key in controller.visibleNodes) {
              if (key == "item-30") break;
              expectedY += controller.getCurrentExtent(key);
            }
            expect(pd.layoutOffset, closeTo(expectedY, 0.5),
                reason: "item-30's parentData.layoutOffset should match "
                    "its post-settle structural Y (got "
                    "${pd.layoutOffset}, expected $expectedY).");
          }
        }
      },
    );

    testWidgets(
      "extreme stress: 20 batches × 30 items each at 75ms intervals "
      "during 1500ms slides + concurrent scroll",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1500),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        _populateTree(controller);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(4000);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(424242);
        for (int batch = 0; batch < 20; batch++) {
          _reparentBatch(controller, random, 30);
          await tester.pump();
          // Half the time, scroll mid-flight too.
          if (batch % 2 == 1) {
            scroll.jumpTo((scroll.offset + (batch.isEven ? 50.0 : -50.0))
                .clamp(0.0, 9000.0));
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 75));
          _expectNoEmptyRenderBoxesInViewport(
            tester, controller, scroll,
            phase: "extreme-stress batch $batch",
          );
        }

        await tester.pumpAndSettle();
        _expectNoEmptyRenderBoxesInViewport(
          tester, controller, scroll,
          phase: "extreme-stress post-settle",
        );
        _expectAllRowsAtStructuralPostSettle(
          tester, controller, scroll,
          phase: "extreme-stress post-settle",
        );
      },
    );
  });
}
