/// D8 repro tests: assistive-technology users must be able to reorder —
/// wrapped rows expose custom semantics actions (move up / move down /
/// move out / move into previous sibling) that commit the same mutations
/// as the equivalent pointer drops.
///
/// Repro-test methodology: on pre-D8 code no custom actions exist on any
/// row, so every expectation here fails.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _moveUp = CustomSemanticsAction(label: "Move up");
const _moveDown = CustomSemanticsAction(label: "Move down");
const _moveOut = CustomSemanticsAction(label: "Move out");
const _moveInto = CustomSemanticsAction(label: "Move into previous sibling");

Future<({TreeController<String, String> tree, TreeReorderController<String> reorder})>
    _mount(
  WidgetTester tester, {
  bool Function(String key)? canReorder,
  bool Function({required String movingKey, String? newParent, int? index})?
      canAcceptDrop,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots([
    const TreeNode(key: "a", data: "A"),
    const TreeNode(key: "b", data: "B"),
    const TreeNode(key: "c", data: "C"),
  ]);
  tree.setChildren("a", [const TreeNode(key: "a1", data: "A1")]);
  tree.expand(key: "a", animate: false);

  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
    canReorder: canReorder,
    canAcceptDrop: canAcceptDrop,
  );
  addTearDown(() {
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
  return (tree: tree, reorder: reorder);
}

/// Finds the semantics node above the row and performs [action], failing
/// with a clear message if the node does not carry it.
void _perform(WidgetTester tester, String rowKey, CustomSemanticsAction action) {
  final node = tester.getSemantics(find.byKey(ValueKey("row-$rowKey")));
  final actions = node.getSemanticsData().customSemanticsActionIds;
  final id = CustomSemanticsAction.getIdentifier(action);
  expect(actions, contains(id),
      reason: "row $rowKey must expose '${action.label}'");
  // The non-deprecated routes (rootPipelineOwner / SemanticsBinding) do
  // not expose the semantics owner that holds widget-test nodes.
  // ignore: deprecated_member_use
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.customAction,
    id,
  );
}

bool _hasAction(WidgetTester tester, String rowKey, CustomSemanticsAction action) {
  final node = tester.getSemantics(find.byKey(ValueKey("row-$rowKey")));
  final ids = node.getSemanticsData().customSemanticsActionIds;
  if (ids == null) {
    return false;
  }
  return ids.contains(CustomSemanticsAction.getIdentifier(action));
}

void main() {
  testWidgets("move up / move down commit the same-parent reorder",
      (tester) async {
    final handle = tester.ensureSemantics();
    final h = await _mount(tester);

    expect(h.tree.liveRootKeys, ["a", "b", "c"]);

    _perform(tester, "b", _moveDown);
    await tester.pumpAndSettle();
    expect(h.tree.liveRootKeys, ["a", "c", "b"],
        reason: "'Move down' on b must swap it with the next root");

    _perform(tester, "b", _moveUp);
    await tester.pumpAndSettle();
    expect(h.tree.liveRootKeys, ["a", "b", "c"],
        reason: "'Move up' on b must swap it back");
    handle.dispose();
  });

  testWidgets("boundary rows omit the impossible directions",
      (tester) async {
    final handle = tester.ensureSemantics();
    await _mount(tester);

    expect(_hasAction(tester, "a", _moveUp), isFalse,
        reason: "the first root cannot move up");
    expect(_hasAction(tester, "a", _moveDown), isTrue);
    expect(_hasAction(tester, "c", _moveDown), isFalse,
        reason: "the last root cannot move down");
    expect(_hasAction(tester, "c", _moveUp), isTrue);
    expect(_hasAction(tester, "a", _moveOut), isFalse,
        reason: "a root has no parent to move out of");
    handle.dispose();
  });

  testWidgets("move out reparents to the grandparent level",
      (tester) async {
    final handle = tester.ensureSemantics();
    final h = await _mount(tester);

    expect(h.tree.getParent("a1"), "a", reason: "setup: a1 under a");

    _perform(tester, "a1", _moveOut);
    await tester.pumpAndSettle();

    expect(h.tree.getParent("a1"), isNull,
        reason: "'Move out' must make a1 the next sibling of its parent");
    expect(h.tree.liveRootKeys, ["a", "a1", "b", "c"]);
    handle.dispose();
  });

  testWidgets("move into previous sibling appends as its last child",
      (tester) async {
    final handle = tester.ensureSemantics();
    final h = await _mount(tester);

    _perform(tester, "b", _moveInto);
    await tester.pumpAndSettle();

    expect(h.tree.getParent("b"), "a",
        reason: "'Move into previous sibling' must reparent b under a");
    expect(h.tree.getLiveChildren("a"), ["a1", "b"],
        reason: "b lands as a's LAST child");
    handle.dispose();
  });

  testWidgets("canAcceptDrop vetoes gate individual actions",
      (tester) async {
    final handle = tester.ensureSemantics();
    // Policy: nothing may become a child of "a" — kills b's
    // move-into-previous (a is b's previous sibling) while leaving b's
    // same-parent moves intact.
    await _mount(
      tester,
      canAcceptDrop: ({required movingKey, newParent, index}) {
        return newParent != "a";
      },
    );

    expect(_hasAction(tester, "b", _moveInto), isFalse,
        reason: "moving b into a is vetoed by policy");
    expect(_hasAction(tester, "b", _moveUp), isTrue,
        reason: "same-parent moves target the root level, not a");
    expect(_hasAction(tester, "b", _moveDown), isTrue);
    handle.dispose();
  });

  testWidgets("canReorder=false rows expose no reorder actions",
      (tester) async {
    final handle = tester.ensureSemantics();
    await _mount(tester, canReorder: (key) => key != "b");

    expect(_hasAction(tester, "b", _moveUp), isFalse);
    expect(_hasAction(tester, "b", _moveDown), isFalse);
    expect(_hasAction(tester, "b", _moveInto), isFalse);
    expect(_hasAction(tester, "a", _moveDown), isTrue,
        reason: "other rows keep their actions");
    handle.dispose();
  });
}
