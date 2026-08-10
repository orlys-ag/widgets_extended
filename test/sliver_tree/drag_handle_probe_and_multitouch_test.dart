/// Second audit pass: two behaviours that only became reachable once
/// handles were caller-placed, and that nothing else covers.
///
/// 1. A handle's grab is no longer CENTRED. The library docs claimed
///    "handle drags are unaffected, their grab is centered", which was
///    true only while the package composed a full-height trailing cell.
///    A caller can put a 32px bar at the top of an 80px card, and the
///    card-anchored probe then genuinely shifts slot selection.
/// 2. Two fingers on two DIFFERENT rows' handles. Each row owns its own
///    recognizer, so neither re-entry guard fires; the CONTROLLER is what
///    arbitrates, and the first row's release must not commit the second
///    row's session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Harness {
  _Harness({required this.tree, required this.reorder, required this.reported});

  final TreeController<String, String> tree;
  final TreeReorderController<String> reorder;
  final List<(String, int)> reported;
}

/// Rows are 80px: a 32px bar at the top or the bottom, and 48px of
/// filler. [gripAtTop] decides which, and therefore the grab offset.
Future<_Harness> _mount(
  WidgetTester tester, {
  required bool gripAtTop,
  bool showDragProxy = true,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots(const [
    TreeNode(key: "a", data: "A"),
    TreeNode(key: "b", data: "B"),
    TreeNode(key: "c", data: "C"),
    TreeNode(key: "d", data: "D"),
  ]);
  final reported = <(String, int)>[];
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
    onReorder: (key, newParent, index) {
      reported.add((key, index));
    },
  );
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
    tree.dispose();
  });

  Widget grip(String key) {
    return TreeDragHandle(
      child: SizedBox(
        key: ValueKey("grip-$key"),
        height: 32.0,
        width: double.infinity,
        child: const ColoredBox(color: Color(0xFF000000)),
      ),
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              showDragProxy: showDragProxy,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 80.0,
                  child: Column(
                    children: <Widget>[
                      if (gripAtTop) grip(key),
                      const SizedBox(height: 48.0),
                      if (!gripAtTop) grip(key),
                    ],
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
  return _Harness(tree: tree, reorder: reorder, reported: reported);
}

void main() {
  testWidgets("a caller-placed handle's grab is NOT centred", (tester) async {
    final top = await _mount(tester, gripAtTop: true);
    final topGrip = tester.getRect(find.byKey(const ValueKey("grip-a")));
    // Setup sanity: the bar really is the top 32px of an 80px row.
    expect(topGrip.top, 0.0);
    expect(topGrip.height, 32.0);

    final g = await tester.startGesture(topGrip.center);
    await tester.pump();
    await g.moveBy(const Offset(0.0, 20.0));
    await tester.pump();

    final geometry = top.reorder.dragProxyGeometry!;
    expect(geometry.rowExtent, 80.0);
    expect(
      geometry.grabDy,
      moreOrLessEquals(16.0, epsilon: 0.5),
      reason:
          "grabbed 16px into an 80px row, so the grab is 24px above the "
          "centre the old docs assumed",
    );

    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    "the card-anchored probe follows the grab point, not the pointer",
    (tester) async {
      // The consequence of the above. Same tree, same pointer position,
      // only the grab offset differs; if slot selection used the raw
      // pointer the two runs would resolve identically.
      Future<int?> runWith({required bool gripAtTop}) async {
        final h = await _mount(tester, gripAtTop: gripAtTop);
        final grip = tester.getRect(find.byKey(const ValueKey("grip-a")));
        final g = await tester.startGesture(grip.center);
        await tester.pump();
        // Land the POINTER at the same absolute y in both runs.
        await g.moveBy(Offset(0.0, 210.0 - grip.center.dy));
        await tester.pump();
        final index = h.reorder.currentTarget?.indexInFinalList;
        await g.up();
        await tester.pumpAndSettle();
        return index;
      }

      final topIndex = await runWith(gripAtTop: true);
      final bottomIndex = await runWith(gripAtTop: false);

      expect(topIndex, isNotNull, reason: "setup: both runs resolve a slot");
      expect(bottomIndex, isNotNull);
      expect(
        topIndex,
        isNot(bottomIndex),
        reason:
            "the probe is anchored to the card, so a bar grabbed at the "
            "top and one grabbed at the bottom select different slots "
            "from the same pointer position",
      );
    },
  );

  testWidgets("two fingers on two DIFFERENT rows: the second wins cleanly", (
    tester,
  ) async {
    // Neither row's re-entry guard fires here: each owns its own
    // recognizer, and `_ownsSession()` is false for the row that is not
    // dragging. The controller's own "cancel the live session first" in
    // `startDrag` is what arbitrates, and the generation compare is what
    // stops the first finger's release from committing the second row's
    // session.
    final h = await _mount(tester, gripAtTop: true, showDragProxy: false);

    final first = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-a"))),
      pointer: 1,
    );
    await tester.pump();
    await first.moveBy(const Offset(0.0, 30.0));
    await tester.pump();

    // Setup sanity: row a genuinely owns a session before row b takes it.
    expect(h.reorder.draggedKey, "a");
    final firstGeneration = h.reorder.dragGeneration;

    final second = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-b"))),
      pointer: 2,
    );
    await tester.pump();
    await second.moveBy(const Offset(0.0, 30.0));
    await tester.pump();

    expect(
      h.reorder.draggedKey,
      "b",
      reason: "the second row's startDrag replaces the first's session",
    );
    expect(h.reorder.dragGeneration, isNot(firstGeneration));

    // The first finger lifts. Its recognizer is untouched and still
    // routed, so its `Drag.end` really does arrive.
    await first.up();
    await tester.pumpAndSettle();

    expect(
      h.reported,
      isEmpty,
      reason: "the superseded row must not commit row b's session",
    );
    expect(h.reorder.draggedKey, "b", reason: "nor cancel it");

    await second.moveBy(const Offset(0.0, 140.0));
    await tester.pump();
    await second.up();
    await tester.pumpAndSettle();

    expect(
      h.reported.map((r) => r.$1),
      ["b"],
      reason: "only the finger that owns the session commits it",
    );
  });
}
