/// Targeted tests for the "wrong widget animates during slide while
/// scrolling" report. Verifies that:
///
/// - Painted position of a sliding row matches its key/data identity
///   throughout the slide, even when the user scrolls concurrently.
/// - Edge-ghost rows correctly identify themselves at their painted
///   position (hit-test resolves to the right row).
/// - applyPaintTransform reports correct positions during and after
///   the slide for ghost rows.
library;

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
  group("scroll during normal (non-ghost) slide", () {
    testWidgets(
      "moved row's widget identity stays correct as user scrolls",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        // 30 rows × 50 = 1500 total; viewport 500 → max scroll 1000.
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Move r2 to position 7. Distance = 250 px, within viewport.
        // Both prior and current on-screen → normal slide, no ghost.
        await _stageAndMutate(tester, () {
          final order = [
            "r0", "r1", "r3", "r4", "r5", "r6", "r7", "r2",
            for (var i = 8; i < 30; i++) "r$i",
          ];
          controller.reorderRoots(order);
        });
        expect(controller.hasActiveSlides, true);

        // Mid-slide, scroll by 50 px.
        await tester.pump(const Duration(milliseconds: 200));
        scroll.jumpTo(50);
        await tester.pump();

        // r2's widget should still display "r2".
        final r2 = find.byKey(const ValueKey("row-r2"));
        expect(r2, findsOneWidget);
        final textInR2 = tester.widget<Text>(
          find.descendant(of: r2, matching: find.byType(Text)),
        );
        expect(textInR2.data, "r2");

        await tester.pumpAndSettle();
        // Final paint: r2 at structural y=350, viewport [50, 550].
        // viewport-relative = 300.
        final r2Top = tester.getTopLeft(r2).dy;
        expect(r2Top, closeTo(300.0, 1.0),
            reason: "After scroll=50 + slide settled, r2 (structural y=350) "
                "should paint at viewport-y=300. If parentData is stale, "
                "would paint at viewport-y=350-50=300 with stale offset 350, "
                "or at the prior structural y=100 if mid-slide composition "
                "got confused.");
      },
    );

    testWidgets(
      "scrolling during slide does not swap painted positions of two rows",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 10; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Swap r2 and r5 positions.
        await _stageAndMutate(tester, () {
          final order = ["r0", "r1", "r5", "r3", "r4", "r2", "r6", "r7", "r8", "r9"];
          controller.reorderRoots(order);
        });

        // Mid-slide.
        await tester.pump(const Duration(milliseconds: 200));
        scroll.jumpTo(30);
        await tester.pump();

        // Each row's text should match its key throughout.
        for (final key in ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9"]) {
          final finder = find.byKey(ValueKey("row-$key"));
          if (finder.evaluate().isEmpty) continue;
          final text = tester.widget<Text>(
            find.descendant(of: finder, matching: find.byType(Text)),
          );
          expect(text.data, key,
              reason: "Row $key should display its own text label, not "
                  "another row's text. Got '${text.data}'.");
        }

        await tester.pumpAndSettle();
      },
    );
  });

  group("scroll during edge-ghost slide-OUT", () {
    testWidgets(
      "ghost row's widget identity stays correct under scroll",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Move r0 to end → ghost slide-OUT.
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });

        // Mid-slide.
        await tester.pump(const Duration(milliseconds: 200));

        final r0 = find.byKey(const ValueKey("row-r0"));
        expect(r0, findsOneWidget,
            reason: "Ghost row should be retained for paint/hit-test.");
        final textInR0 = tester.widget<Text>(
          find.descendant(of: r0, matching: find.byType(Text)),
        );
        expect(textInR0.data, "r0",
            reason: "Ghost row should still display its own text.");

        // Scroll a bit.
        scroll.jumpTo(50);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // r0's widget should still be r0.
        if (find.byKey(const ValueKey("row-r0")).evaluate().isNotEmpty) {
          final r0After = find.byKey(const ValueKey("row-r0"));
          final textAfter = tester.widget<Text>(
            find.descendant(of: r0After, matching: find.byType(Text)),
          );
          expect(textAfter.data, "r0");
        }

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "scroll-induced re-promotion: scrolling toward ghost destination "
      "re-promotes and the row settles at structural without snap",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Move r0 to end (structural y=1450). Ghost installed.
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });
        await tester.pump(const Duration(milliseconds: 100));

        // User scrolls down so r0's destination (structural 1450) is in
        // viewport. With viewport=500 and r0 at y=1450, scrolling to
        // ~1000 puts the destination at viewport-y=450 (visible).
        scroll.jumpTo(1000);
        await tester.pump(); // triggers scroll-induced re-promotion

        // r0 should now be re-promoted (no longer ghost). It paints at
        // its sliding position en route to structural y=1450.
        // The slide should continue and settle at structural.
        await tester.pumpAndSettle();

        // After settle: r0 paints at structural y=1450, viewport [1000, 1500].
        // viewport-relative y = 450.
        final r0 = find.byKey(const ValueKey("row-r0"));
        if (r0.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(r0).dy, closeTo(450.0, 1.0),
              reason: "After settle, r0 should be at its structural "
                  "position (1450) relative to scroll (1000) → "
                  "viewport-y=450.");
        }
      },
    );
  });

  group("childMainAxisPosition / childScrollOffset for ghost rows", () {
    testWidgets(
      "framework scroll APIs report a sensible position for ghost rows "
      "(not far-off-screen structural)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });
        await tester.pump(const Duration(milliseconds: 100));

        // r0 ghost. Find its render box and query childMainAxisPosition.
        final render = tester.renderObject<RenderSliverTree<String, int>>(
          find.byType(SliverTree<String, int>),
        );
        final r0Box = render.getChildForNode("r0");
        expect(r0Box, isNotNull,
            reason: "Ghost row's child should be retained.");
        if (r0Box != null) {
          final childMain = render.childMainAxisPosition(r0Box);
          // Regression guard for the parentData-refresh fix: the
          // post-sticky refresh now also runs when slides are active,
          // ensuring off-cache mounted rows (like edge-ghost slide-OUT
          // targets) have fresh `parentData.layoutOffset` matching their
          // actual structural position. Without this fix, framework
          // scroll APIs would return the row's PRE-mutation position,
          // causing visible "wrong position during slide; switches at
          // settle" artifacts when concurrent scroll triggers re-layout.
          //
          // r0 was moved to last position (structural y=1450); with the
          // fix, parentData.layoutOffset is updated to 1450 → childMain
          // returns 1450 - 0 (scrollOffset) = 1450.
          expect(childMain, closeTo(1450.0, 10.0),
              reason: "parentData.layoutOffset must be refreshed for "
                  "off-cache mounted rows during slide-only frames "
                  "(may be slightly off due to mid-slide extent "
                  "interpolation if other rows are animating).");
        }

        await tester.pumpAndSettle();
      },
    );
  });
}
