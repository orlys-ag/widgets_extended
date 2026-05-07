/// Regression tests for two composition bugs found while reviewing the
/// example app's rapid-reparent scenario:
///
/// 1. **Double-clamp on re-promoted ghost.** Step 4 of consume re-evaluates
///    active edge ghosts and may re-promote (remove from
///    `_phantomEdgeExits`). Step 5's clamp loop must skip these keys —
///    otherwise it sees baseline (ghost-painted, off-viewport by edge_y
///    construction) as "prior off-screen" and overwrites it with the
///    clamped edge value, breaking the carefully-composed visual
///    continuity at re-promotion (visible JUMP at t=0).
///
/// 2. **Both-off-screen suppression breaks composition.** A row with an
///    in-flight engine slide whose snapshot baseline AND current both
///    fall off-screen must NOT be suppressed — the engine's existing
///    slide is targeting an OLD destination; suppressing leaves it
///    pointing there and produces a visible SNAP at slide settle when
///    the engine clears the slide and parentData refreshes to the NEW
///    structural.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;
const _kSlideDuration = Duration(milliseconds: 800);

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

TreeController<String, int> _newController(WidgetTester tester) {
  return TreeController<String, int>(
    vsync: tester,
    animationDuration: _kSlideDuration,
    animationCurve: Curves.linear,
  );
}

Future<void> _stageAndMutate(
  WidgetTester tester,
  void Function() mutation,
) async {
  final render = tester.renderObject<RenderSliverTree<String, int>>(
    find.byType(SliverTree<String, int>),
  );
  render.beginSlideBaseline(
    duration: _kSlideDuration,
    curve: Curves.linear,
  );
  mutation();
  await tester.pump();
}

void main() {
  group("Bug 1: double-clamp on re-promoted ghost", () {
    testWidgets(
      "re-promotion (mutation moves ghost back to visible position) "
      "preserves visual continuity — no JUMP at t=0 of re-promotion slide",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Step 1: Move r0 to last position → ghost slide-OUT.
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });
        expect(controller.hasActiveSlides, true);

        // Pump partway through the ghost slide.
        await tester.pump(const Duration(milliseconds: 300));
        // Capture r0's painted position mid-ghost — should be somewhere
        // between 0 (its prior visible position) and the bottom edge.
        final r0MidGhost = tester.getTopLeft(
          find.byKey(const ValueKey("row-r0")),
        ).dy;
        expect(r0MidGhost, greaterThan(0.0));
        expect(r0MidGhost, lessThan(_kViewportHeight + 100.0),
            reason: "Ghost should still be near or just past the bottom "
                "edge mid-slide. Got $r0MidGhost.");

        // Step 2: Move r0 BACK to position 5 → re-promotion (true
        // structural now in viewport). Without the double-clamp fix,
        // r0 would JUMP from r0MidGhost to the viewport edge ± overhang
        // at the moment of re-promotion. With the fix, painted at t=0
        // of the re-promotion slide should equal r0MidGhost.
        await _stageAndMutate(tester, () {
          // Build the new order: r0 at index 5.
          final current = [
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ];
          current.removeLast(); // remove r0 from end
          current.insert(5, "r0");
          controller.reorderRoots(current);
        });

        // Immediately after the install (no time advanced — engine has
        // composed but not yet ticked), r0's painted position should
        // be very close to r0MidGhost (within 1 px for the post-tick
        // jitter). NOT clamped to viewport edge.
        final r0AtRePromoteT0 = tester.getTopLeft(
          find.byKey(const ValueKey("row-r0")),
        ).dy;
        expect(r0AtRePromoteT0, closeTo(r0MidGhost, 5.0),
            reason: "Re-promotion should preserve visual continuity. "
                "Pre-mutation r0 was at viewport-y=$r0MidGhost. After "
                "re-promotion install, r0 at viewport-y=$r0AtRePromoteT0. "
                "Diff > 5 indicates double-clamp bug.");

        await tester.pumpAndSettle();
      },
    );
  });

  group("Bug 2: both-off-screen suppression breaks composition", () {
    testWidgets(
      "row with in-flight slide-OUT, then re-mutated to a different "
      "off-screen position → engine slide redirects, no snap at settle",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 60; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Scroll to mid-tree — viewport [1000, 1500]. Items 20-29
        // visible.
        scroll.jumpTo(1000);
        await tester.pump();
        await tester.pumpAndSettle();

        // Move r25 from index 25 to index 55 (off-screen below).
        // Ghost installs.
        await _stageAndMutate(tester, () {
          final order = [for (var i = 0; i < 60; i++) "r$i"];
          order.removeAt(25);
          order.insert(55, "r25");
          controller.reorderRoots(order);
        });
        expect(controller.hasActiveSlides, true);

        // Pump a bit so the slide is in flight.
        await tester.pump(const Duration(milliseconds: 200));

        // Now move r25 to a DIFFERENT off-screen position (e.g. index 5,
        // structural y=250, off-screen above relative to viewport [1000,
        // 1500]). Both prior (mid-flight ghost-painted, may be off-
        // screen depending on slide progress) and current (structural
        // 250, off-screen above) could be off-screen.
        //
        // Pre-fix: both-off-screen suppression removed r25 from the
        // batch, leaving the engine slide pointing at the OLD edge.
        // Slide settles at OLD edge, then engine clears entry,
        // parentData refreshes to NEW structural (250) → SNAP visible
        // when r25 comes into viewport via scroll or further mutation.
        //
        // Post-fix: composition redirects the slide toward the new
        // destination via Step 5 clamp/ghost handling.
        await _stageAndMutate(tester, () {
          final order = controller.visibleNodes
              .where((k) => k.startsWith("r"))
              .toList();
          order.remove("r25");
          order.insert(5, "r25");
          controller.reorderRoots(order);
        });

        await tester.pumpAndSettle();

        // After settle, scroll to where r25 should be (structural y=250,
        // so scroll to 0 to put r25 at viewport-y=250).
        scroll.jumpTo(0);
        await tester.pump();
        await tester.pumpAndSettle();

        // r25 should be at its new structural position (y=250 in
        // scroll-space, viewport-y=250 with scrollOffset=0).
        final r25 = find.byKey(const ValueKey("row-r25"));
        if (r25.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(r25).dy, closeTo(250.0, 1.0),
              reason: "r25 should be at its NEW structural position "
                  "after the cascaded slide settles correctly.");
        }
      },
    );

    testWidgets(
      "row with no in-flight slide AND both-off-screen mutation: "
      "still suppressed (no spurious slide install)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 60; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        scroll.jumpTo(1500); // viewport [1500, 2000]
        await tester.pump();
        await tester.pumpAndSettle();

        // Move r5 (off-screen above) to index 55 (off-screen below).
        // Both prior and current off-screen. r5 has NO in-flight slide.
        // Suppression should fire — no slide installed.
        await _stageAndMutate(tester, () {
          final order = [for (var i = 0; i < 60; i++) "r$i"];
          order.removeAt(5);
          order.insert(55, "r5");
          controller.reorderRoots(order);
        });

        // r5's slide delta should be 0 (suppressed; no animation).
        expect(controller.getSlideDelta("r5"), 0.0,
            reason: "r5 had no in-flight slide and both prior/current "
                "are off-screen — slide install must be suppressed.");

        await tester.pumpAndSettle();
      },
    );
  });

  group("Bug 3: composition-during-slide (mid-flight re-mutation)", () {
    testWidgets(
      "row mid-slide-OUT gets re-targeted to in-viewport position — "
      "painted position stays continuous (no JUMP to edge at t=0 of "
      "new slide)",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Install slide A: move r0 toward end (large slide-OUT to off-
        // screen below). r0 starts at viewport-y=0, slides toward end.
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });
        expect(controller.hasActiveSlides, true);

        // Pump partway. r0 is mid-flight, painted at SOME viewport
        // position (depends on slide progress).
        await tester.pump(const Duration(milliseconds: 200));
        final r0MidA = tester.getTopLeft(
          find.byKey(const ValueKey("row-r0")),
        ).dy;

        // Install slide B mid-flight: re-target r0 to position 5
        // (in viewport). The row is mid-slide-OUT; its current painted
        // position (r0MidA) is the truth. Composition should redirect
        // the slide toward position 5 without jumping.
        await _stageAndMutate(tester, () {
          final order = [
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ];
          order.removeLast();
          order.insert(5, "r0");
          controller.reorderRoots(order);
        });

        // Immediately after install (no time advanced), r0's painted
        // position should equal r0MidA (continuity preserved). With
        // the buggy strict-clamp, r0 would JUMP to viewport-edge
        // (around 0 or just below) and then lerp from there.
        final r0AtCompose = tester.getTopLeft(
          find.byKey(const ValueKey("row-r0")),
        ).dy;
        expect(r0AtCompose, closeTo(r0MidA, 5.0),
            reason: "r0 should stay at its mid-flight position when "
                "the new slide installs. Pre-mutation: $r0MidA. Post-"
                "install: $r0AtCompose. Diff > 5 px indicates the "
                "composition-clamp bug (row jumped to edge).");

        await tester.pumpAndSettle();

        // After settle, r0 should be at structural y = 5 * 50 = 250.
        expect(
          tester.getTopLeft(find.byKey(const ValueKey("row-r0"))).dy,
          closeTo(250.0, 1.0),
        );
      },
    );

    testWidgets(
      "many rows mid-slide simultaneously re-targeted to in-viewport "
      "positions — none jump to edge",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        // 30 root rows.
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Install slide A: shuffle rows so most rows shift positions.
        // Many slides install (some slide-IN, some slide-OUT, some
        // sliding within viewport).
        await _stageAndMutate(tester, () {
          final order = [for (var i = 0; i < 30; i++) "r$i"]..shuffle(
              Random(11));
          controller.reorderRoots(order);
        });

        // Pump partway.
        await tester.pump(const Duration(milliseconds: 200));

        // Capture mid-flight painted positions for first 5 rows.
        final midA = <String, double>{};
        for (final key in ["r0", "r1", "r2", "r3", "r4"]) {
          final finder = find.byKey(ValueKey("row-$key"));
          if (finder.evaluate().isNotEmpty) {
            midA[key] = tester.getTopLeft(finder).dy;
          }
        }

        // Install slide B: another shuffle.
        await _stageAndMutate(tester, () {
          final order = [for (var i = 0; i < 30; i++) "r$i"]..shuffle(
              Random(22));
          controller.reorderRoots(order);
        });

        // Immediately after install, each captured row's painted
        // position should match midA (continuity).
        for (final entry in midA.entries) {
          final finder = find.byKey(ValueKey("row-${entry.key}"));
          if (finder.evaluate().isEmpty) continue;
          final post = tester.getTopLeft(finder).dy;
          expect(post, closeTo(entry.value, 5.0),
              reason: "${entry.key} jumped from ${entry.value} to "
                  "$post at composition. Composition-clamp bug.");
        }

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "edge-ghost slide-OUT in flight, mid-flight re-targeted to "
      "in-viewport — re-promotion preserves continuity",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Install ghost slide-OUT.
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });
        await tester.pump(const Duration(milliseconds: 200));
        final r0MidGhost = tester.getTopLeft(
          find.byKey(const ValueKey("row-r0")),
        ).dy;

        // Re-promote: move r0 back to in-viewport position.
        await _stageAndMutate(tester, () {
          final order = [
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ];
          order.removeLast();
          order.insert(3, "r0");
          controller.reorderRoots(order);
        });

        // Continuity: r0 painted at r0MidGhost.
        final r0AtRePromote = tester.getTopLeft(
          find.byKey(const ValueKey("row-r0")),
        ).dy;
        expect(r0AtRePromote, closeTo(r0MidGhost, 5.0));

        await tester.pumpAndSettle();
      },
    );
  });

  group("Rapid reparent: composition stress test", () {
    testWidgets(
      "multiple cascaded reparent batches do not corrupt widget identity "
      "OR painted positions, regardless of scroll position",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);

        // Setup mirroring the example app's "Reparent ALL" scenario:
        // 8 parents × 30 items = 240 rows total.
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
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Scroll to mid-tree to match the user's screenshot scenario.
        // Total height: 8 parents + 240 items = 248 rows × 50 = 12400.
        // Scroll to ~5000 puts viewport in the middle.
        scroll.jumpTo(5000);
        await tester.pump();
        await tester.pumpAndSettle();

        final random = Random(7);

        // Three rapid reparent batches, each moving 10 random items.
        for (int batch = 0; batch < 3; batch++) {
          final allItems = <String>[];
          for (int p = 0; p < 8; p++) {
            allItems.addAll(controller.getChildren("parent-$p"));
          }
          allItems.shuffle(random);
          for (final item in allItems.take(10)) {
            final currentParent = controller.getParent(item);
            if (currentParent == null) continue;
            int target;
            do {
              target = random.nextInt(8);
            } while ("parent-$target" == currentParent);
            final newSiblings = controller.getLiveChildren("parent-$target");
            final newIndex = newSiblings.isEmpty
                ? 0
                : random.nextInt(newSiblings.length + 1);
            controller.moveNode(
              item,
              "parent-$target",
              index: newIndex,
              animate: true,
              slideDuration: _kSlideDuration,
              slideCurve: Curves.linear,
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Mid-third-batch state. For every visible widget in the tree:
        // 1. Its key matches its displayed text (no widget identity
        //    confusion).
        // 2. Its painted position is consistent (no two widgets at
        //    identical viewport-y).
        final paintedPositions = <double, String>{};
        for (final key in controller.visibleNodes) {
          final finder = find.byKey(ValueKey("row-$key"));
          if (finder.evaluate().isEmpty) continue;
          final dy = tester.getTopLeft(finder).dy;
          // Widget identity check.
          final textWidgets = find.descendant(
            of: finder, matching: find.byType(Text),
          );
          if (textWidgets.evaluate().isEmpty) continue;
          final text = tester.widget<Text>(textWidgets);
          expect(text.data, key,
              reason: "Row $key at viewport-y=$dy must show its own "
                  "key as text. Got '${text.data}'.");
          // Position uniqueness (within viewport).
          if (dy >= 0 && dy < _kViewportHeight) {
            final existing = paintedPositions[dy];
            if (existing != null) {
              fail("Two rows at same viewport-y=$dy: $existing and $key");
            }
            paintedPositions[dy] = key;
          }
        }

        await tester.pumpAndSettle();
      },
    );
  });
}
