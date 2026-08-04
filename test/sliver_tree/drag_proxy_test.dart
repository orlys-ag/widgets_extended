/// D13 repro tests: a floating drag preview that follows the pointer.
///
/// Two layers:
/// 1. Controller: a per-pointer-move channel (`pointerPosition`) and the
///    grab geometry (`dragProxyGeometry`) — the coalesced ChangeNotifier
///    channel stays coalesced (semantic targets only).
/// 2. Widget: an overlay proxy positioned at pointer − grab offset,
///    following every move, torn down with the session.
///
/// Repro-test methodology: every expectation fails on pre-D13 code (the
/// APIs and the proxy overlay do not exist).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const Color _kProxyColor = Color(0xFFFEDCBA);

Finder _proxyFinder() {
  return find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == _kProxyColor,
  );
}

class _FakePort implements ReorderRenderPort<String> {
  _FakePort({required this.controller});

  final TreeController<String, String> controller;

  @override
  bool get isLaidOut {
    return true;
  }

  @override
  double get precedingScrollExtent {
    return 0.0;
  }

  @override
  bool drivesController(Object treeController) {
    return identical(controller, treeController);
  }

  // Rows a/b/c at 50px each.
  @override
  ({String key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  ) {
    if (scrollY < 50) {
      return (key: "a", paintedOffset: 0.0, extent: 50.0);
    }
    if (scrollY < 100) {
      return (key: "b", paintedOffset: 50.0, extent: 50.0);
    }
    return (key: "c", paintedOffset: 100.0, extent: 50.0);
  }

  @override
  void pinNode(String key) {}

  @override
  void unpinNode(String key) {}

  @override
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
    Map<String, double>? baselineYOverrides,
  }) {}
}

void main() {
  testWidgets(
    "pointerPosition fires per move (uncoalesced) while the semantic "
    "channel stays coalesced; grab geometry captured at start",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final port = _FakePort(controller: controller);
      final reorder = TreeReorderController<String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );

      var pointerEvents = 0;
      reorder.pointerPosition.addListener(() {
        pointerEvents++;
      });
      var semanticEvents = 0;
      reorder.addListener(() {
        semanticEvents++;
      });

      expect(reorder.pointerPosition.value, isNull,
          reason: "no session, no pointer");

      // Grab row "a" at y=30 → grab offset 30 within the 50px row.
      reorder.startDrag(
        key: "a",
        renderPort: port,
        scrollable: scrollable,
        pointerGlobal: const Offset(200, 30),
      );
      expect(reorder.pointerPosition.value, const Offset(200, 30));
      expect(reorder.dragProxyGeometry?.grabDy, 30.0,
          reason: "the proxy must not jump: the grab point within the "
              "dragged row is captured at start");
      expect(reorder.dragProxyGeometry?.rowExtent, 50.0);

      // Micro-moves within the same zone: the SEMANTIC channel must stay
      // quiet (coalesced), the POINTER channel must fire every time.
      reorder.updateDrag(const Offset(200, 145));
      final semanticAfterFirstMove = semanticEvents;
      final pointerAfterFirstMove = pointerEvents;
      reorder.updateDrag(const Offset(200, 146));
      reorder.updateDrag(const Offset(200, 147));
      expect(semanticEvents, semanticAfterFirstMove,
          reason: "micro-moves within the same zone must not re-notify "
              "the semantic channel");
      expect(pointerEvents, pointerAfterFirstMove + 2,
          reason: "the pointer channel fires on EVERY move — that is its "
              "reason to exist");

      reorder.cancelDrag();
      expect(reorder.pointerPosition.value, isNull,
          reason: "session teardown clears the pointer channel");
      expect(reorder.dragProxyGeometry, isNull);
    },
  );

  testWidgets(
    "a custom drag proxy follows the pointer at pointer − grab offset and "
    "tears down with the session",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      tree.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
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
                  dragProxyBuilder: (context, key, child) {
                    return const ColoredBox(color: _kProxyColor);
                  },
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

      expect(_proxyFinder(), findsNothing,
          reason: "no proxy before any drag");

      // Long-press the center of row a: grab point y=25 within the row.
      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(reorder.isDragging, isTrue, reason: "setup: session started");
      expect(_proxyFinder(), findsOneWidget,
          reason: "the proxy appears as soon as the drag starts");

      // Move to y=300: proxy top must sit at 300 − 25 = 275 (pointer
      // minus grab offset), i.e. the row appears held where it was
      // grabbed.
      await gesture.moveTo(const Offset(400, 300));
      await tester.pump();
      expect(tester.getTopLeft(_proxyFinder()).dy, 275.0,
          reason: "the proxy follows the pointer, anchored at the grab "
              "point");

      // And keeps following.
      await gesture.moveTo(const Offset(400, 320));
      await tester.pump();
      expect(tester.getTopLeft(_proxyFinder()).dy, 295.0);

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_proxyFinder(), findsNothing,
          reason: "the proxy is torn down with the session");
    },
  );

  testWidgets(
    "showDragProxy renders the row's own child as the default proxy",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      tree.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
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

      expect(find.text("a"), findsOneWidget);

      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      expect(find.text("a"), findsNWidgets(2),
          reason: "the default proxy clones the dragged row's child into "
              "the overlay (in-tree dimmed copy + floating copy)");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text("a"), findsOneWidget,
          reason: "the clone disappears with the session");
    },
  );
}
