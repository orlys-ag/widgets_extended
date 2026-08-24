/// Repro suite for M10: EXIT ghosts must retire when their FLIP slide
/// settles, even while a make-room preview is held, and their painted
/// base must follow the anchor's HELD preview displacement.
///
/// Modelled on `ghost_prune_flip_only_test.dart`, the edge-ghost twin.
/// Three exit-ghost sites read the COMPOSED slide + preview delta where
/// they must ask a FLIP-only or a split question:
///
/// - the Step 0a prune criterion and the Pass A.5 paint gate (a PAIR)
///   read the ghost's and the anchor's composed deltas, so a held
///   preview on the ANCHOR keeps a settled ghost alive, painted, and
///   pinned through `isNodeRetained` for the whole drag;
/// - the ghost's painted base uses the anchor's raw `layoutOffset`,
///   which under a held preview under-shoots the anchor's settled
///   painted band by exactly the preview offset.
///
/// The last test is a GUARD, not a repro: it pins the sum identity
/// `getSlideDeltaNid == getFlipSlideDeltaNid + getHeldPreviewDeltaNid`
/// for every visible row while both engines are active.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const double _viewportHeight = 550.0;
const double _rowHeight = 40.0;
const int _rowCount = 20;
const Duration _slide = Duration(milliseconds: 300);
const Duration _makeRoom = Duration(milliseconds: 200);

Widget _harness(
  TreeController<String, String> controller, {
  ScrollController? scrollController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _viewportHeight,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _rowHeight,
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

RenderSliverTree<String, String> _sliver(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

TreeController<String, String> _controller(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(duration: _slide, curve: Curves.linear),
      enterExit: TreeAnimationSpec(duration: _slide, curve: Curves.linear),
      reorderSlide: TreeAnimationSpec(duration: _slide, curve: Curves.linear),
      makeRoom: TreeAnimationSpec(duration: _makeRoom, curve: Curves.linear),
    ),
  );
  // n5 ("Q") stays COLLAPSED: moving a visible row under it makes that
  // row an EXIT ghost anchored on Q. Q needs a child so it is a real
  // parent either way; the child stays hidden throughout.
  controller.setRoots([
    for (int i = 0; i < _rowCount; i++) TreeNode(key: "n$i", data: "N$i"),
  ]);
  controller.setChildren("n5", [const TreeNode(key: "q0", data: "Q0")]);
  return controller;
}

/// Moves visible root `n10` under the collapsed `n5`, creating one exit
/// ghost anchored on `n5`, and returns after the install frame with the
/// ghost's FLIP slide still in flight.
Future<RenderSliverTree<String, String>> _installExitGhost(
  WidgetTester tester,
  TreeController<String, String> controller, {
  ScrollController? scrollController,
}) async {
  await tester.pumpWidget(
    _harness(controller, scrollController: scrollController),
  );
  await tester.pumpAndSettle();
  final sliver = _sliver(tester);

  expect(
    sliver.debugPhantomExitGhostCount,
    0,
    reason: "setup: idle, no exit ghosts",
  );

  controller.moveNode(
    "n10",
    "n5",
    animate: true,
    slideDuration: _slide,
    slideCurve: Curves.linear,
  );
  await tester.pump(); // install frame: consumes the baseline

  expect(
    sliver.debugPhantomExitGhostCount,
    1,
    reason: "setup: the move must install exactly one exit ghost, "
        "otherwise this test exercises nothing",
  );
  expect(
    sliver.isNodeRetained("n10"),
    isTrue,
    reason: "setup: the ghost's render box must be retained mid-slide",
  );
  return sliver;
}

/// Holds a make-room preview whose span covers the anchor `n5` (drag
/// `n0`, gap below `n7`: rows n1..n7 shift up by one row height), so the
/// anchor carries a HELD preview offset while the ghost carries none.
Future<void> _holdPreviewOverAnchor(
  WidgetTester tester,
  TreeController<String, String> controller,
) async {
  controller.setReorderPreview(
    draggedKey: "n0",
    targetKey: "n7",
    gapBelowTarget: true,
  );
  await tester.pump(); // arm the preview ticker
  await tester.pump(_makeRoom); // preview reaches its held target
}

void main() {
  group("exit ghosts retire on FLIP state, not composed state", () {
    testWidgets(
      "a settled exit ghost retires and releases its retention pin while "
      "a preview is held on its anchor",
      (tester) async {
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final sliver = await _installExitGhost(
          tester,
          controller,
          scrollController: scroll,
        );

        await _holdPreviewOverAnchor(tester, controller);

        // Setup sanity: the anchor really carries a held preview offset,
        // the ghost does not (it is hidden, previews target visible
        // rows only).
        expect(
          controller.getSlideDelta("n5"),
          isNot(0.0),
          reason: "setup: the anchor must be preview-shifted",
        );

        // Let the ghost's FLIP finish while the preview stays held, then
        // force one layout so Step 0a runs.
        await tester.pump(_slide);
        scroll.jumpTo(1.0);
        await tester.pump();

        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "setup: the held preview must keep hasActiveSlides true",
        );
        expect(
          controller.hasActiveFlipSlides,
          isFalse,
          reason: "setup: every FLIP slide must have settled by now",
        );

        expect(
          sliver.debugPhantomExitGhostCount,
          0,
          reason: "a settled exit ghost must retire during a held "
              "preview; the prune criterion is FLIP-only",
        );
        expect(
          sliver.isNodeRetained("n10"),
          isFalse,
          reason: "retiring the ghost must release its unconditional "
              "retention pin",
        );

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "a mid-FLIP exit ghost's painted base follows its anchor's held "
      "preview displacement",
      (tester) async {
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        final sliver = await _installExitGhost(tester, controller);

        await _holdPreviewOverAnchor(tester, controller);

        // Sample while the ghost's FLIP is still in flight (the move ran
        // 200 ms ago against a 300 ms slide) and the preview is held.
        final ghostDelta = controller.getSlideDelta("n10");
        expect(
          ghostDelta,
          isNot(0.0),
          reason: "setup: the ghost's own FLIP must still be in flight",
        );

        final paint = sliver.debugLastPhantomGhostPaint;
        expect(
          paint.containsKey("n10"),
          isTrue,
          reason: "setup: a sliding ghost must have been painted and "
              "captured by the oracle",
        );

        // All rows are the same height, so the direction-aware tuck is 0
        // and the expected painted top is the anchor's painted top plus
        // the ghost's own delta. Read the anchor's painted top from its
        // own render box so the assertion is on agreement between the
        // two paints, not on a literal.
        final sliverTop = tester
            .getTopLeft(find.byType(CustomScrollView))
            .dy;
        final anchorTop =
            tester.getTopLeft(find.byKey(const ValueKey("row-n5"))).dy -
            sliverTop;
        final ghostTop = paint["n10"]!.ghostRect.top;
        expect(
          (ghostTop - (anchorTop + ghostDelta)).abs(),
          lessThan(0.01),
          reason: "the ghost must converge on the anchor's SETTLED "
              "position, which under a held preview is structural plus "
              "the preview offset; a base missing the held term paints "
              "the ghost one preview-lift above the anchor's band",
        );

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "identity guard: composed delta is FLIP plus held preview for "
      "every visible row",
      (tester) async {
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        await _installExitGhost(tester, controller);
        await _holdPreviewOverAnchor(tester, controller);

        // Both engines active: the ghost's FLIP is in flight and the
        // anchor really carries a held preview offset (a trivially idle
        // preview would make the identity hold as 0 == 0 + 0 and the
        // guard would have no teeth).
        expect(controller.hasActiveFlipSlides, isTrue);
        expect(controller.getSlideDelta("n5"), isNot(0.0));

        for (final key in controller.visibleNodes) {
          final nid = controller.nidOf(key);
          expect(
            controller.getSlideDeltaNid(nid),
            controller.getFlipSlideDeltaNid(nid) +
                controller.getHeldPreviewDeltaNid(nid),
            reason: "the sum identity must hold for $key",
          );
        }

        await tester.pumpAndSettle();
      },
    );
  });
}
