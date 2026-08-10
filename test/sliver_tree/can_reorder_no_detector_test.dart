/// A row that `canReorder` refuses must leave the long-press to the app.
///
/// Consulted only at `startDrag`, the policy still let the row claim the
/// long-press and then decline it, so an app that wanted that gesture for
/// its own purposes never saw it. Deciding availability at build time
/// costs nothing extra: the semantics-action computation already calls
/// `canReorder` on every row build.
///
/// Asserted through an APP-OWNED long-press handler rather than by
/// counting `GestureDetector` widgets. The detector is deliberately still
/// installed on a refused row, with its callbacks nulled so no recognizer
/// is constructed, because omitting the widget changed the row's shape on
/// a policy flip and re-inflated the app's subtree underneath it. Widget
/// counts would pin that implementation detail; what an app can observe is
/// whether its own gesture fires.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets("a refused row leaves the long-press to the app", (tester) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(<TreeNode<String, String>>[
      const TreeNode(key: "free", data: "free"),
      const TreeNode(key: "locked", data: "locked"),
    ]);
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      canReorder: (key) {
        return key != "locked";
      },
    );
    addTearDown(() {
      reorder.dispose();
      tree.dispose();
    });

    final appLongPresses = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The app's own long-press, wrapped AROUND the tree. An inner
          // detector would be nearer the pointer and win the arena on
          // every row, refused or not, which is precisely the fixture
          // that cannot tell the two apart.
          body: GestureDetector(
            onLongPress: () {
              appLongPresses.add("app");
            },
            child: CustomScrollView(
              slivers: <Widget>[
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  showDragProxy: false,
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
      ),
    );
    await tester.pumpAndSettle();

    // The refused row's long-press belongs to the app.
    await tester.longPress(find.byKey(const ValueKey("row-locked")));
    await tester.pumpAndSettle();
    expect(
      appLongPresses,
      <String>["app"],
      reason: "a row that can never drag must not claim the gesture",
    );
    expect(
      reorder.isDragging,
      isFalse,
      reason: "and it certainly must not have started a drag",
    );

    // Setup control: on an ALLOWED row the package wins the same gesture,
    // so the result above is a refusal and not a broken fixture. Held
    // rather than tapped: `longPress` releases, which would end the
    // session before it could be observed.
    appLongPresses.clear();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-free"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(reorder.isDragging, isTrue);
    expect(
      appLongPresses,
      isEmpty,
      reason: "the package claimed it, so the app must not also fire",
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
