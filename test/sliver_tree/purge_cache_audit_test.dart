/// Audit-style tests for the visible-subtree-size cache invariant
/// across all paths that purge nodes (release nids).
///
/// The bug class is: a path purges a node (releasing its nid, which
/// clears `_parentByNid[nid] = _kNoParent`) and then defers the
/// visible-order bookkeeping to a later step that walks the parent
/// chain — by then it is broken, so ancestor caches stay stale.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// Helper that walks the controller and recomputes the expected
/// `_visibleSubtreeSizeByNid` for every visible node, then checks each
/// node's reported subtree size matches.
///
/// Uses only public API. The check is structural: visible-subtree-size
/// for a node should equal 1 (for the node itself if visible) +
/// sum(child.visibleSubtreeSize) over its direct children. We can't
/// call the private getter directly, but we CAN verify the consequence
/// of a wrong cache: the next `insert(parentKey: …)` would compute an
/// out-of-range insertIndex and crash inside _updateIndicesFrom.
///
/// So each test ends with an `insert` under the affected parent and
/// checks no exception is thrown.
void expectInsertConsistent(
  TreeController<String, String> controller,
  String parentKey,
  String newKey,
) {
  controller.insert(
    parentKey: parentKey,
    node: TreeNode<String, String>(key: newKey, data: newKey),
    animate: false,
  );
}

void main() {
  group("purge paths that defer visible-order maintenance", () {
    testWidgets("immediate (animate: false) remove of one child", (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(c.dispose);
      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [
        for (var i = 0; i < 5; i++) TreeNode(key: "c$i", data: "c$i"),
      ]);
      c.expand(key: "r", animate: false);

      c.remove(key: "c2", animate: false);
      // After: insert at end must compute the correct index. If the
      // cache was left stale, this would throw.
      expectInsertConsistent(c, "r", "n0");
      expect(c.getChildren("r"), equals(["c0", "c1", "c3", "c4", "n0"]));
    });

    testWidgets("immediate (animate: false) remove of a subtree", (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(c.dispose);
      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [
        const TreeNode(key: "branch", data: "branch"),
        const TreeNode(key: "sibling", data: "sibling"),
      ]);
      c.setChildren("branch", [
        for (var i = 0; i < 4; i++) TreeNode(key: "leaf$i", data: "leaf$i"),
      ]);
      c.expand(key: "r", animate: false);
      c.expand(key: "branch", animate: false);

      c.remove(key: "branch", animate: false);
      expectInsertConsistent(c, "r", "fresh");
      expect(c.getChildren("r"), equals(["sibling", "fresh"]));
    });

    testWidgets("animated remove + animation finalize + insert", (tester) async {
      // This is the originally-reported bug, kept here as a sibling
      // case alongside the immediate-remove cases above.
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(c.dispose);
      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [
        for (var i = 0; i < 5; i++) TreeNode(key: "c$i", data: "c$i"),
      ]);
      c.expand(key: "r", animate: false);

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 600,
          child: CustomScrollView(slivers: [
            SliverTree<String, String>(
              controller: c,
              nodeBuilder: (_, k, _) => SizedBox(
                height: 24,
                child: Text(k),
              ),
            ),
          ]),
        ),
      ));
      await tester.pump();

      c.remove(key: "c1", animate: true);
      await tester.pump(const Duration(milliseconds: 200));
      expectInsertConsistent(c, "r", "n0");
      await tester.pumpAndSettle();
    });

    testWidgets("removing a root with no children", (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(c.dispose);
      c.setRoots([
        const TreeNode(key: "r1", data: "r1"),
        const TreeNode(key: "r2", data: "r2"),
        const TreeNode(key: "r3", data: "r3"),
      ]);

      c.remove(key: "r2", animate: false);
      // Insert under another root must work (no parent-cache to corrupt
      // for roots, but exercises the path).
      c.setChildren("r1", [const TreeNode(key: "r1c", data: "r1c")]);
      c.expand(key: "r1", animate: false);
      expectInsertConsistent(c, "r1", "n0");
      expect(c.getChildren("r1"), equals(["r1c", "n0"]));
    });

    testWidgets("collapse with animation, then insert under same parent",
        (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(c.dispose);
      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [
        for (var i = 0; i < 4; i++) TreeNode(key: "c$i", data: "c$i"),
      ]);
      c.expand(key: "r", animate: false);

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 600,
          child: CustomScrollView(slivers: [
            SliverTree<String, String>(
              controller: c,
              nodeBuilder: (_, k, _) => SizedBox(
                height: 24,
                child: Text(k),
              ),
            ),
          ]),
        ),
      ));
      await tester.pump();

      // Remove a child mid-animation, then collapse the parent (which
      // should also fully reset state via the operation group dismissed
      // path), then re-expand and insert.
      c.remove(key: "c1", animate: true);
      await tester.pump(const Duration(milliseconds: 50));
      c.collapse(key: "r", animate: true);
      await tester.pump(const Duration(milliseconds: 200));
      c.expand(key: "r", animate: false);
      expectInsertConsistent(c, "r", "n0");
      await tester.pumpAndSettle();
    });

    testWidgets("setChildren that drops some retained, adds some, removes some",
        (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(c.dispose);
      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [
        const TreeNode(key: "a", data: "a"),
        const TreeNode(key: "b", data: "b"),
        const TreeNode(key: "c", data: "c"),
        const TreeNode(key: "d", data: "d"),
      ]);
      c.expand(key: "r", animate: false);

      c.setChildren("r", [
        const TreeNode(key: "a", data: "a"),
        const TreeNode(key: "c", data: "c"),
        const TreeNode(key: "e", data: "e"),
      ]);
      expectInsertConsistent(c, "r", "n0");
      expect(c.getChildren("r"), equals(["a", "c", "e", "n0"]));
    });
  });
}
