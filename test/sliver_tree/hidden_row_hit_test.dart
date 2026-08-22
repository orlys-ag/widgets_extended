/// Regression test for issue 9 of the 2026-08-21 review: the dragged
/// row's in-place copy was hidden with `Opacity(0)` alone, which leaves
/// it hit-testable.
///
/// `RenderOpacity` does not override `hitTest`, and while the drag rests
/// in its own slot the preview holds no offsets, so the invisible row is
/// the only thing under its band. A second finger landing there hit
/// content the user cannot see: on a drag handle it ran the row's
/// re-entry guard and CANCELLED the live drag, and on ordinary row
/// content it fired that content's own gesture callbacks.
///
/// The row now wraps the hidden copy in `IgnorePointer`. The guard that
/// used to fire is kept (it still protects any path that un-hides a row
/// mid-session), but it is no longer reachable while the row is hidden,
/// which is what the two rewritten tests in `caller_placed_handle_test`
/// and `drag_handle_audit_test` now pin.
///
/// The accessibility half of the wrap, that the row's reorder actions
/// survive a drag, is covered by the last test here. Getting an
/// instrument that can actually fail took three tries during the
/// 2026-08-21 audit: `tester.getSemantics` resolves a node whose action
/// ids persist under either nesting, and a label-keyed walk of the live
/// tree misses the actions entirely because they sit on the wrapper
/// node rather than the labelled one. Counting the NODES that carry the
/// action does discriminate, because the hidden row's own node is the
/// one at stake.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

({TreeController<String, String> tree, TreeReorderController<String> reorder})
_controllers(WidgetTester tester) {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots([
    const TreeNode(key: "a", data: "A"),
    const TreeNode(key: "b", data: "B"),
    const TreeNode(key: "c", data: "C"),
    const TreeNode(key: "d", data: "D"),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  return (tree: tree, reorder: reorder);
}

const _moveDown = CustomSemanticsAction(label: "Move down");

/// Number of semantics nodes in the LIVE tree carrying [action].
///
/// Counting nodes is the instrument that discriminates here. Asking one
/// row's node for its action ids does not: `tester.getSemantics` walks
/// up to a node whose ids survive either nesting, and keying a tree walk
/// on the row's label misses the actions because they sit on the
/// wrapper node, not the labelled one. During a drag the count is 2, the
/// hidden in-place row plus the floating proxy, and it drops to 1 the
/// moment the in-place row's semantics subtree stops being emitted.
int _nodesWithAction(WidgetTester tester, CustomSemanticsAction action) {
  final id = CustomSemanticsAction.getIdentifier(action);
  // The non-deprecated routes (rootPipelineOwner / SemanticsBinding) do
  // not expose the semantics owner that holds widget-test nodes. Same
  // exemption the other semantics tests in this directory take.
  // ignore: deprecated_member_use
  final owner = tester.binding.pipelineOwner.semanticsOwner!;
  final root = owner.rootSemanticsNode!;
  var count = 0;
  void visit(SemanticsNode node) {
    final ids = node.getSemanticsData().customSemanticsActionIds;
    if (ids != null && ids.contains(id)) {
      count++;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return count;
}

void main() {
  testWidgets("a second finger on the hidden dragged row does not cancel "
      "the drag", (tester) async {
    final c = _controllers(tester);
    addTearDown(() {
      if (c.reorder.isDragging) {
        c.reorder.cancelDrag();
      }
      c.reorder.dispose();
      c.tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverReorderableTree<String, String>(
                controller: c.tree,
                reorderController: c.reorder,
                showDragProxy: true,
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = await tester.startGesture(const Offset(400, 75));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await first.moveTo(const Offset(400, 76));
    await tester.pump();
    expect(c.reorder.isDragging, isTrue);
    expect(
      c.tree.hasActiveSlides,
      isFalse,
      reason: "setup: resting in its own slot, so no preview offset moves "
          "any other row under the pointer",
    );

    // A second finger lands on the band the invisible row occupies.
    final second = await tester.startGesture(const Offset(400, 75), pointer: 7);
    await tester.pump();
    await second.up();
    await tester.pump();

    expect(
      c.reorder.isDragging,
      isTrue,
      reason: "the hidden row must not receive the pointer, so the row's "
          "re-entry guard cannot cancel the live session",
    );

    await first.up();
    await tester.pumpAndSettle();
  });

  testWidgets("the hidden dragged row does not receive taps", (tester) async {
    final c = _controllers(tester);
    var taps = 0;
    addTearDown(() {
      if (c.reorder.isDragging) {
        c.reorder.cancelDrag();
      }
      c.reorder.dispose();
      c.tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverReorderableTree<String, String>(
                controller: c.tree,
                reorderController: c.reorder,
                showDragProxy: true,
                nodeBuilder: (context, key, depth) {
                  // The realistic shape: a grip the drag starts from,
                  // beside body content with its own tap handler.
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 50,
                    child: Row(
                      children: [
                        TreeDelayedDragHandle(
                          child: SizedBox(
                            width: 60,
                            height: 50,
                            child: Text("grip-$key"),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => taps++,
                            child: SizedBox(
                              height: 50,
                              child: Text("body-$key"),
                            ),
                          ),
                        ),
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

    final first = await tester.startGesture(const Offset(30, 75));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await first.moveTo(const Offset(30, 76));
    await tester.pump();
    expect(c.reorder.isDragging, isTrue);

    // A second finger taps the invisible row's BODY, away from the grip.
    final second = await tester.startGesture(const Offset(400, 75), pointer: 7);
    await tester.pump();
    await second.up();
    await tester.pump();
    expect(taps, 0, reason: "invisible content must not be tappable");

    await first.up();
    await tester.pumpAndSettle();
  });

  testWidgets("the dragged row keeps its reorder actions while hidden", (
    tester,
  ) async {
    // The accessibility half of the wrap. Both wrappers sit INSIDE the
    // row's `Semantics`, and that ordering is load-bearing for `Opacity`
    // specifically: `RenderOpacity.visitChildrenForSemantics` stops
    // emitting its child at alpha 0 unless `alwaysIncludeSemantics` is
    // set, so a `Semantics` placed inside it would take the row's
    // reorder actions out of the tree for the length of every drag,
    // which is precisely when a screen-reader user might reach for them.
    //
    // `IgnorePointer` is not what this pins: it keeps its subtree in the
    // tree and only marks it `isBlockingUserActions`, which leaves the
    // custom action ids in place. Moving it outside changes nothing
    // here, and this test does not claim otherwise.
    final handle = tester.ensureSemantics();
    final c = _controllers(tester);
    addTearDown(() {
      if (c.reorder.isDragging) {
        c.reorder.cancelDrag();
      }
      c.reorder.dispose();
      c.tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverReorderableTree<String, String>(
                controller: c.tree,
                reorderController: c.reorder,
                showDragProxy: true,
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final idleCount = _nodesWithAction(tester, _moveDown);
    expect(
      idleCount,
      greaterThan(0),
      reason: "setup: some rows can move down while the list is idle",
    );

    final gesture = await tester.startGesture(const Offset(400, 75));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 76));
    await tester.pump();
    expect(c.reorder.isDragging, isTrue, reason: "setup: a live drag");

    expect(
      _nodesWithAction(tester, _moveDown),
      idleCount,
      reason: "hiding the dragged row must not remove its action-carrying "
          "semantics node; this reads one FEWER when the row's semantics "
          "are dropped along with its opacity",
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_nodesWithAction(tester, _moveDown), idleCount);
    // Disposed in the body, not a tearDown: the binding verifies handles
    // before tearDowns run.
    handle.dispose();
  });

  testWidgets("rows that are not being dragged stay interactive", (
    tester,
  ) async {
    // Control: `IgnorePointer` is scoped to the dragged subtree, so every
    // other row keeps its gestures during the drag.
    final c = _controllers(tester);
    final tapped = <String>[];
    addTearDown(() {
      if (c.reorder.isDragging) {
        c.reorder.cancelDrag();
      }
      c.reorder.dispose();
      c.tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverReorderableTree<String, String>(
                controller: c.tree,
                reorderController: c.reorder,
                showDragProxy: true,
                nodeBuilder: (context, key, depth) {
                  return TreeDelayedDragHandle(
                    child: GestureDetector(
                      onTap: () => tapped.add(key),
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
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

    // Before any drag, the row is tappable.
    await tester.tap(find.text("b"));
    await tester.pump();
    expect(tapped, ["b"]);

    // After a drag ends, it is tappable again.
    final gesture = await tester.startGesture(const Offset(400, 75));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 80));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    tapped.clear();
    await tester.tap(find.text("b"));
    await tester.pump();
    expect(tapped, ["b"]);
  });
}
