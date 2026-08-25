import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Repro for M25: the drag session subscribed to the `ScrollPosition`
/// captured at `startDrag`. `ScrollableState` replaces its position when
/// the physics runtimeType changes, which the
/// `physics: isDragging ? const NeverScrollableScrollPhysics() : ...`
/// pattern does on the first drag notification, so after the swap the
/// listener sat on the dead position and no scroll re-resolved the drop
/// target.
///
/// The fix has two halves and the cases pin them separately:
/// - every `PointerSpace.sample` re-validates the position identity, so
///   any pointer event or autoscroll tick after a swap re-binds (case 1,
///   the textbook pattern, where the move that follows the drag start is
///   such an event; the headless half is in `drag_session_unit_test.dart`);
/// - the dragged row's `didChangeDependencies` re-binds in the swap's own
///   frame, which is the only cover when the swap lands AFTER the last
///   pointer event and an external scroll follows with the finger at rest
///   (case 3).
/// Case 2 is the no-swap control on the same harness.
void main() {
  testWidgets("case 1: physics following isDragging swaps the position at drag "
      "start; external scrolls still re-resolve", (tester) async {
    final h = await _mount(tester);
    // The textbook wiring: block user scrolling while a drag is live.
    h.reorder.addListener(() {
      h.blocked.value = h.reorder.isDragging;
    });
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final before = scrollable.position;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-r0"))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 275));
    await tester.pump();

    expect(
      h.reorder.isDragging,
      isTrue,
      reason: "setup sanity: the long press must start a drag",
    );
    expect(
      identical(before, scrollable.position),
      isFalse,
      reason:
          "setup sanity: the physics flip must have swapped the "
          "ScrollPosition",
    );
    expect(
      h.reorder.currentTarget?.targetKey,
      "r5",
      reason: "setup sanity: the pointer at y=275 resolves r5",
    );

    // Content moves under the stationary pointer, no pointer event.
    scrollable.position.jumpTo(500.0);
    await tester.pump();
    expect(
      h.reorder.currentTarget?.targetKey,
      "r15",
      reason:
          "after a 500 px external scroll the stationary pointer hovers "
          "r15; a stale r5 means the subscription died with the swapped "
          "position",
    );

    scrollable.position.jumpTo(1000.0);
    await tester.pump();
    expect(
      h.reorder.currentTarget?.targetKey,
      "r25",
      reason: "a second external scroll must re-resolve as well",
    );

    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle();
  });

  testWidgets(
    "case 2: control, stable physics keeps following external scrolls",
    (tester) async {
      final h = await _mount(tester);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final before = scrollable.position;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-r0"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 275));
      await tester.pump();

      expect(
        identical(before, scrollable.position),
        isTrue,
        reason: "setup sanity: stable physics must keep the ScrollPosition",
      );
      expect(
        h.reorder.currentTarget?.targetKey,
        "r5",
        reason: "setup sanity: the pointer at y=275 resolves r5",
      );

      scrollable.position.jumpTo(500.0);
      await tester.pump();
      expect(
        h.reorder.currentTarget?.targetKey,
        "r15",
        reason: "control: the unswapped position keeps re-resolving",
      );

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "case 3: a swap after the last pointer event is re-bound in its own "
    "frame, so a following external scroll re-resolves",
    (tester) async {
      final h = await _mount(tester);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-r0"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 275));
      await tester.pump();
      expect(
        h.reorder.currentTarget?.targetKey,
        "r5",
        reason: "setup sanity: the pointer at y=275 resolves r5",
      );

      // The finger rests; the app flips the physics now. No pointer
      // event or autoscroll tick follows, so nothing samples.
      final before = scrollable.position;
      h.blocked.value = true;
      await tester.pump();
      expect(
        identical(before, scrollable.position),
        isFalse,
        reason:
            "setup sanity: the physics flip must have swapped the "
            "ScrollPosition",
      );

      scrollable.position.jumpTo(500.0);
      await tester.pump();
      expect(
        h.reorder.currentTarget?.targetKey,
        "r15",
        reason:
            "the swap frame must re-bind the subscription itself: with the "
            "finger at rest nothing else samples before the scroll",
      );

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );
}

Future<
  ({
    TreeController<String, String> tree,
    TreeReorderController<String> reorder,
    ValueNotifier<bool> blocked,
  })
>
_mount(WidgetTester tester) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots([
    for (var i = 0; i < 40; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  final blocked = ValueNotifier<bool>(false);
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
    tree.dispose();
    blocked.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: blocked,
          builder: (context, isBlocked, child) {
            // A physics runtimeType change is what makes ScrollableState
            // replace its ScrollPosition.
            return CustomScrollView(
              physics: isBlocked
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  nodeBuilder: (context, key, depth) {
                    return TreeDelayedDragHandle(
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (tree: tree, reorder: reorder, blocked: blocked);
}
