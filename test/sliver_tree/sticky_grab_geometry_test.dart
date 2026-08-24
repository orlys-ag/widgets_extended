/// Grab geometry against a REAL sticky-pinned header.
///
/// The companion unit tests in `drag_session_unit_test.dart` prove
/// `DragProbe.captureGrab`'s arithmetic against a scripted port. They
/// cannot prove the production `RenderSliverTree.paintedRowBounds`, which
/// is where the actual hazard lives: `_anchorPaintedBounds` answers in
/// sliver PAINT space (scrollOffset already subtracted) while
/// `ReorderRenderPort` speaks sliver-local scroll space. Mixing those two
/// yields an error that is invisible while scrolled to the top, which is
/// precisely the shape of the bug being fixed, so it needs a test that is
/// actually scrolled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

const double _kHeader = 40.0;
const double _kRow = 50.0;

class _Node {
  const _Node(this.id, [this.children = const <_Node>[]]);
  final String id;
  final List<_Node> children;
}

void main() {
  testWidgets("a drag started on a pinned sticky header is held where "
      "grabbed", (tester) async {
    late TreeReorderController<String> reorder;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: CustomScrollView(
              controller: scroll,
              slivers: <Widget>[
                SyncedSliverTree<String, _Node>.hierarchy(
                  roots: <_Node>[
                    _Node("s1", <_Node>[
                      for (int i = 0; i < 20; i++) _Node("i$i"),
                    ]),
                  ],
                  keyOf: (n) {
                    return n.id;
                  },
                  childrenOf: (n) {
                    return n.children;
                  },
                  maxStickyDepth: 1,
                  animationStyle: TreeAnimationStyle.disabled,
                  reorder: TreeReorderConfig<String>(
                    showDragProxy: false,
                    onReorder: (key, newParent, index) {},
                    onControllerCreated: (c) {
                      reorder = c;
                    },
                  ),
                  itemBuilder: (context, view) {
                    return SizedBox(
                      key: ValueKey("row-${view.key}"),
                      height: view.depth == 0 ? _kHeader : _kRow,
                      child: Text(view.key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll well past the header's own structural position so it is
    // genuinely pinned rather than merely at the top.
    scroll.jumpTo(300.0);
    await tester.pumpAndSettle();

    // Setup sanity, and the whole point of this test: the header is
    // PAINTED at the viewport top while its STRUCTURE says it is 300px up.
    // Without this the assertions below could pass for the trivial reason
    // that nothing was ever pinned.
    final headerRect = tester.getRect(find.byKey(const ValueKey("row-s1")));
    expect(
      headerRect.top,
      moreOrLessEquals(0.0, epsilon: 0.5),
      reason: "the header must be pinned at the viewport top",
    );
    expect(
      scroll.position.pixels,
      greaterThan(_kHeader),
      reason: "and scrolled past its own structural offset",
    );

    // Long-press the pinned header 12px down from its painted top.
    final grabPoint = Offset(headerRect.center.dx, headerRect.top + 12.0);
    final gesture = await tester.startGesture(grabPoint);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 8.0));
    await tester.pump();

    final geometry = reorder.dragProxyGeometry;
    expect(geometry, isNotNull, reason: "the drag must have started");
    expect(
      geometry!.grabDy,
      moreOrLessEquals(12.0, epsilon: 1.0),
      reason: "held where grabbed, not snapped to the header's top",
    );
    expect(
      geometry.rowExtent,
      moreOrLessEquals(_kHeader, epsilon: 0.5),
      reason: "the header's own extent, not that of a row scrolled beneath",
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("unpinned control: the same drag while scrolled to the top", (
    tester,
  ) async {
    // Pins that the fix changes nothing on the path every other drag test
    // exercises. At rest the painted and structural offsets coincide, so
    // this leg passed before the fix too and must keep passing.
    late TreeReorderController<String> reorder;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, _Node>.hierarchy(
                  roots: <_Node>[
                    _Node("s1", <_Node>[
                      for (int i = 0; i < 20; i++) _Node("i$i"),
                    ]),
                  ],
                  keyOf: (n) {
                    return n.id;
                  },
                  childrenOf: (n) {
                    return n.children;
                  },
                  maxStickyDepth: 1,
                  animationStyle: TreeAnimationStyle.disabled,
                  reorder: TreeReorderConfig<String>(
                    showDragProxy: false,
                    onReorder: (key, newParent, index) {},
                    onControllerCreated: (c) {
                      reorder = c;
                    },
                  ),
                  itemBuilder: (context, view) {
                    return SizedBox(
                      key: ValueKey("row-${view.key}"),
                      height: view.depth == 0 ? _kHeader : _kRow,
                      child: Text(view.key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Grab a plain item row 30px down from its top.
    final rect = tester.getRect(find.byKey(const ValueKey("row-i2")));
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.top + 30.0),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 8.0));
    await tester.pump();

    final geometry = reorder.dragProxyGeometry;
    expect(geometry, isNotNull);
    expect(geometry!.grabDy, moreOrLessEquals(30.0, epsilon: 1.0));
    expect(geometry.rowExtent, moreOrLessEquals(_kRow, epsilon: 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("a drag started on a pinned sticky header resolves the header, "
      "not the content scrolled beneath the strip (L21)", (tester) async {
    late TreeReorderController<String> reorder;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: CustomScrollView(
              controller: scroll,
              slivers: <Widget>[
                SyncedSliverTree<String, _Node>.hierarchy(
                  roots: <_Node>[
                    _Node("s1", <_Node>[
                      for (int i = 0; i < 20; i++) _Node("i$i"),
                    ]),
                  ],
                  keyOf: (n) {
                    return n.id;
                  },
                  childrenOf: (n) {
                    return n.children;
                  },
                  maxStickyDepth: 1,
                  animationStyle: TreeAnimationStyle.disabled,
                  reorder: TreeReorderConfig<String>(
                    showDragProxy: false,
                    onReorder: (key, newParent, index) {},
                    onControllerCreated: (c) {
                      reorder = c;
                    },
                  ),
                  itemBuilder: (context, view) {
                    return SizedBox(
                      key: ValueKey("row-${view.key}"),
                      height: view.depth == 0 ? _kHeader : _kRow,
                      child: Text(view.key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(300.0);
    await tester.pumpAndSettle();

    final headerRect = tester.getRect(find.byKey(const ValueKey("row-s1")));
    expect(
      headerRect.top,
      moreOrLessEquals(0.0, epsilon: 0.5),
      reason: "setup: the header must be pinned at the viewport top",
    );
    expect(
      scroll.position.pixels,
      greaterThan(_kHeader),
      reason: "setup: and scrolled past its own structural offset",
    );
    final render = tester.renderObject<RenderSliverTree<String, _Node>>(
      find.byType(SliverTree<String, _Node>),
    );
    expect(
      render.findRowAtPaintedY(scroll.position.pixels + 20.0)!.key,
      "i5",
      reason:
          "setup: the row structurally beneath the pinned band's "
          "midpoint is i5, which is what a positional lookup answers",
    );

    final gesture = await tester.startGesture(
      Offset(headerRect.center.dx, headerRect.top + 12.0),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 2.0));
    await tester.pump();
    expect(reorder.isDragging, isTrue, reason: "setup: the drag started");
    // The Decision's precondition: the make-room preview is installed at
    // drag start, so its lifted range already covers the very header the
    // lookup must answer with. The pinned lookup must NOT apply the
    // lifted skip, or every resolve falls through to the content beneath
    // the strip.
    final tree = reorder.treeController;
    expect(
      tree.previewLiftedStartIndex,
      tree.getVisibleIndex("s1"),
      reason:
          "setup: the held preview's lifted range must cover the "
          "header the lookup answers with",
    );
    expect(
      reorder.currentTarget?.targetKey,
      "s1",
      reason:
          "the probe sits inside the pinned band, so the header owns "
          "it; a positional lookup against structural offsets, or a pinned "
          "lookup that skips the lifted range, resolves elsewhere",
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
