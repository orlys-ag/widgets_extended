/// Gate test for plan item T6 (and its twin, the sectioned plan's S9):
/// when a sibling is inserted or removed, do the DISPLACED siblings'
/// rows re-render?
///
/// Sibling position is a rendered input for connector lines, dividers and
/// rounded-group styling, but it is an input no mutator names directly:
/// inserting a child dirties the parent (its child-list length changed),
/// not the siblings whose index shifted underneath it. If those rows are
/// not rebuilt, any position-derived UI silently goes stale, and shipping
/// `indexInParent` / `isFirst` / `isLast` on `TreeItemView` would be
/// shipping a trap.
///
/// The rows here read position through the controller primitives those
/// getters would wrap, so this tests the DIRTYING, not the getters.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'tree_input_helpers.dart';

/// Static fixture: p > [x, y, z]. Hoisted so every rebuild passes the
/// same instance, which is the convention the identity fast path expects.
final List<SyncedTreeNode<String, String>> _fixture = treeFrom(
  roots: const ["p"],
  dataByKey: const {"p": "P", "x": "X", "y": "Y", "z": "Z"},
  childrenByParent: const {
    "p": ["x", "y", "z"],
  },
);

/// Renders each row's own sibling position, the way a divider- or
/// connector-drawing row would.
///
/// Reads the controller primitives rather than the `TreeItemView` getters
/// so this file keeps testing the DIRTYING even if the getters change;
/// the getters get their own test at the bottom.
String _describe(TreeItemView<String, String> node) {
  final controller = node.controller;
  final index = controller.getIndexInParent(node.key);
  final parent = node.parentKey;
  final siblingCount = parent == null
      ? controller.liveRootCount
      : controller.liveChildCount(parent);
  final isLast = index == siblingCount - 1;
  return "${node.key}@$index|last=$isLast";
}

/// Same information, via the public getters.
String _describeViaGetters(TreeItemView<String, String> node) {
  return "${node.key}@${node.indexInParent}"
      "|first=${node.isFirst}|last=${node.isLast}|n=${node.siblingCount}";
}

class _Harness extends StatelessWidget {
  const _Harness({required this.onControllerCreated});

  final void Function(TreeController<String, String> controller)
  onControllerCreated;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, String>(
              tree: _fixture,
              animationStyle: TreeAnimationStyle.disabled,
              onControllerCreated: onControllerCreated,
              itemBuilder: (context, node) {
                return SizedBox(height: 48, child: Text(_describe(node)));
              },
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets("inserting a sibling refreshes the rows it displaced", (
    tester,
  ) async {
    late TreeController<String, String> controller;
    await tester.pumpWidget(
      _Harness(
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("x@0|last=false"), findsOneWidget);
    expect(find.text("y@1|last=false"), findsOneWidget);
    expect(find.text("z@2|last=true"), findsOneWidget);

    // Head insert: every existing sibling shifts down one slot.
    controller.insert(
      parentKey: "p",
      node: const TreeNode(key: "w", data: "W"),
      index: 0,
      animate: false,
    );
    await tester.pumpAndSettle();

    expect(
      controller.getIndexInParent("x"),
      1,
      reason: "sanity: the controller itself sees the shift",
    );
    expect(find.text("w@0|last=false"), findsOneWidget);
    expect(
      find.text("x@1|last=false"),
      findsOneWidget,
      reason: "a displaced sibling must re-render its new position",
    );
    expect(find.text("y@2|last=false"), findsOneWidget);
    expect(find.text("z@3|last=true"), findsOneWidget);
  });

  testWidgets("removing the last sibling refreshes the new last sibling", (
    tester,
  ) async {
    late TreeController<String, String> controller;
    await tester.pumpWidget(
      _Harness(
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("y@1|last=false"), findsOneWidget);

    controller.remove(key: "z", animate: false);
    await tester.pumpAndSettle();

    expect(
      controller.liveChildCount("p"),
      2,
      reason: "sanity: the controller itself sees the removal",
    );
    expect(
      find.text("y@1|last=true"),
      findsOneWidget,
      reason: "the sibling that became last must re-render",
    );
  });

  testWidgets("reordering siblings refreshes every row whose index moved", (
    tester,
  ) async {
    late TreeController<String, String> controller;
    await tester.pumpWidget(
      _Harness(
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();

    controller.reorderChildren("p", <String>["z", "x", "y"]);
    await tester.pumpAndSettle();

    expect(find.text("z@0|last=false"), findsOneWidget);
    expect(find.text("x@1|last=false"), findsOneWidget);
    expect(find.text("y@2|last=true"), findsOneWidget);
  });

  testWidgets(
    "TreeItemView position getters report live space and stay fresh",
    (tester) async {
      late TreeController<String, String> controller;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SyncedSliverTree<String, String>(
                  tree: _fixture,
                  animationStyle: const TreeAnimationStyle(),
                  onControllerCreated: (c) {
                    controller = c;
                  },
                  itemBuilder: (context, node) {
                    return SizedBox(
                      height: 48,
                      child: Text(_describeViaGetters(node)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("p@0|first=true|last=true|n=1"), findsOneWidget);
      expect(find.text("x@0|first=true|last=false|n=3"), findsOneWidget);
      expect(find.text("y@1|first=false|last=false|n=3"), findsOneWidget);
      expect(find.text("z@2|first=false|last=true|n=3"), findsOneWidget);

      // Live space: while "z" animates out it is excluded from both the
      // index space and the count, so "y" becomes last immediately rather
      // than when the exit finishes.
      controller.remove(key: "z", animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        controller.isExiting("z"),
        isTrue,
        reason: "sanity: the removal is still animating",
      );
      expect(
        find.text("y@1|first=false|last=true|n=2"),
        findsOneWidget,
        reason: "an exiting sibling must not count toward live position",
      );

      await tester.pumpAndSettle();
      expect(find.text("y@1|first=false|last=true|n=2"), findsOneWidget);
    },
  );
}
