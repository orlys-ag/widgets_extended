/// The consumer seam for reorder semantics actions.
///
/// A restrictive `canAcceptDrop` disconnects the built-in four: they only
/// form a connected action set when the illegal intermediate states are
/// traversable, so a policy forbidding one of them can leave a row
/// unreachable by keyboard or screen reader while a pointer drag still
/// gets there. The seam lets a consumer contribute the missing moves
/// without teaching the tree layer about their model.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const CustomSemanticsAction _moveUp = CustomSemanticsAction(label: "Move up");
const CustomSemanticsAction _extra = CustomSemanticsAction(label: "Teleport");

class _Mounted {
  _Mounted(this.tree, this.reorder);
  final TreeController<String, String> tree;
  final TreeReorderController<String> reorder;
}

Future<_Mounted> _mount(
  WidgetTester tester, {
  ReorderSemanticsActionsBuilder<String>? builder,
  bool Function(String key)? canReorder,
  List<String> roots = const <String>["a", "b", "c"],
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots(<TreeNode<String, String>>[
    for (final k in roots) TreeNode<String, String>(key: k, data: k),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
    canReorder: canReorder,
  );
  addTearDown(() {
    reorder.dispose();
    tree.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              showDragProxy: false,
              semanticsActionsBuilder: builder,
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
  return _Mounted(tree, reorder);
}

List<int> _actionIds(WidgetTester tester, String key) {
  final node = tester.getSemantics(find.byKey(ValueKey("row-$key")));
  return node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
}

bool _has(WidgetTester tester, String key, CustomSemanticsAction action) {
  return _actionIds(
    tester,
    key,
  ).contains(CustomSemanticsAction.getIdentifier(action));
}

void main() {
  testWidgets("no builder leaves the built-in set exactly as it was", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _mount(tester);
    expect(_has(tester, "b", _moveUp), isTrue);
    expect(_has(tester, "b", _extra), isFalse);
    handle.dispose();
  });

  testWidgets("a builder can add an action", (tester) async {
    final handle = tester.ensureSemantics();
    var invokedFor = <String>[];
    await _mount(
      tester,
      builder: (nodeKey, builtIn) {
        invokedFor.add(nodeKey);
        return <CustomSemanticsAction, VoidCallback>{...builtIn, _extra: () {}};
      },
    );

    expect(_has(tester, "b", _extra), isTrue);
    expect(_has(tester, "b", _moveUp), isTrue, reason: "built-ins survive");
    expect(invokedFor, contains("a"));
    handle.dispose();
  });

  testWidgets("a builder can remove an action", (tester) async {
    final handle = tester.ensureSemantics();
    await _mount(
      tester,
      builder: (nodeKey, builtIn) {
        return <CustomSemanticsAction, VoidCallback>{...builtIn}
          ..remove(_moveUp);
      },
    );
    expect(_has(tester, "b", _moveUp), isFalse);
    handle.dispose();
  });

  testWidgets("a builder contributing to an EMPTY built-in set is honored", (
    tester,
  ) async {
    // A lone root has no legal built-in move, so its built-in set is
    // empty but the row IS reorderable. Testing `isNotEmpty` before the
    // builder instead of after would silently drop this contribution.
    final handle = tester.ensureSemantics();
    await _mount(
      tester,
      roots: const <String>["only"],
      builder: (nodeKey, builtIn) {
        expect(builtIn, isEmpty, reason: "setup: nothing built-in applies");
        return <CustomSemanticsAction, VoidCallback>{_extra: () {}};
      },
    );
    expect(_has(tester, "only", _extra), isTrue);
    handle.dispose();
  });

  testWidgets("a builder is NOT consulted for a canReorder-refused row", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final seen = <String>[];
    await _mount(
      tester,
      canReorder: (key) {
        return key != "b";
      },
      builder: (nodeKey, builtIn) {
        seen.add(nodeKey);
        return <CustomSemanticsAction, VoidCallback>{...builtIn, _extra: () {}};
      },
    );

    expect(
      seen,
      isNot(contains("b")),
      reason: "a refusal is a hard no, not a vocabulary to refine",
    );
    expect(_has(tester, "b", _extra), isFalse);
    expect(_has(tester, "a", _extra), isTrue, reason: "other rows unaffected");
    handle.dispose();
  });

  testWidgets("a builder returning an empty map emits no custom actions", (
    tester,
  ) async {
    // An empty NON-NULL map would still raise the customAction bit on the
    // node, advertising actions that do not exist.
    final handle = tester.ensureSemantics();
    await _mount(
      tester,
      builder: (nodeKey, builtIn) {
        return const <CustomSemanticsAction, VoidCallback>{};
      },
    );
    expect(_actionIds(tester, "b"), isEmpty);
    handle.dispose();
  });

  testWidgets("a builder swapped at runtime reaches already-mounted rows", (
    tester,
  ) async {
    // Rows cache the builder from an inherited scope. If the scope does
    // not notify on a change, turning the seam on later does nothing at
    // all and turning it off leaves stale actions live.
    final handle = tester.ensureSemantics();
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(<TreeNode<String, String>>[
      const TreeNode(key: "a", data: "a"),
      const TreeNode(key: "b", data: "b"),
    ]);
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    addTearDown(() {
      reorder.dispose();
      tree.dispose();
    });

    Map<CustomSemanticsAction, VoidCallback> add(
      String key,
      Map<CustomSemanticsAction, VoidCallback> builtIn,
    ) {
      return <CustomSemanticsAction, VoidCallback>{...builtIn, _extra: () {}};
    }

    Future<void> pumpWith(ReorderSemanticsActionsBuilder<String>? b) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  showDragProxy: false,
                  semanticsActionsBuilder: b,
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
    }

    await pumpWith(null);
    expect(_has(tester, "b", _extra), isFalse);

    await pumpWith(add);
    expect(_has(tester, "b", _extra), isTrue, reason: "turning it ON works");

    await pumpWith(null);
    expect(_has(tester, "b", _extra), isFalse, reason: "and OFF again");
    handle.dispose();
  });

  testWidgets("a contributed action commits through the controller", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    late TreeReorderController<String> reorder;
    final events = <String>[];
    final mounted = await _mount(
      tester,
      builder: (nodeKey, builtIn) {
        return <CustomSemanticsAction, VoidCallback>{
          ...builtIn,
          _extra: () {
            reorder.moveTo(nodeKey, null, index: 2);
          },
        };
      },
    );
    reorder = mounted.reorder;
    mounted.tree.addStructuralListener((_) {
      events.add("structural");
    });

    final node = tester.getSemantics(find.byKey(const ValueKey("row-a")));
    // The non-deprecated routes (rootPipelineOwner / SemanticsBinding) do
    // not expose the semantics owner that holds widget-test nodes.
    // ignore: deprecated_member_use
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(_extra),
    );
    await tester.pumpAndSettle();

    expect(mounted.tree.liveRootKeys, <String>["b", "c", "a"]);
    expect(events, isNotEmpty);
    handle.dispose();
  });
}
