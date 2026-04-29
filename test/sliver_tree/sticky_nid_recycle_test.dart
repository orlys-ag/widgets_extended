/// Regression for nid-recycle staleness in StickyHeaderComputer.
///
/// `_stickyByNid` is indexed by the controller's internal nid. When a
/// previously-sticky node is removed and its nid is recycled to a fresh
/// key, the stale [StickyHeaderInfo] entry at that nid would otherwise
/// make the new occupant appear sticky to paint/hit-test/transform.
///
/// The clear loop inside `computeStickyHeaders` only nulls slots whose
/// `nodeId` still resolves to a live nid. After a removal that freed the
/// original key (`animate: false` immediate purge), `nidOf(staleKey)
/// == noNid`, so the slot survives until the same nid is reallocated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("nid recycled from a freed sticky header does not leak "
      "stickiness to its replacement", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Build a tree where "parent" is a sticky candidate at depth 1.
    // root
    //   parent
    //     leaf1, leaf2, …, leafN  (so parent has hasChildren=true)
    controller.setRoots([const TreeNode(key: "root", data: "root")]);
    controller.setChildren("root", [
      const TreeNode(key: "parent", data: "parent"),
      // many trailing rows so we have a long visible list and out-of-cache
      // rows to test against.
      for (var i = 0; i < 30; i++) TreeNode(key: "tail$i", data: "tail$i"),
    ]);
    controller.setChildren("parent", [
      const TreeNode(key: "leaf1", data: "leaf1"),
      const TreeNode(key: "leaf2", data: "leaf2"),
    ]);
    controller.expand(key: "root", animate: false);
    controller.expand(key: "parent", animate: false);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 200,
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                maxStickyDepth: 2,
                nodeBuilder: (_, key, _) =>
                    SizedBox(height: 40, child: Text(key)),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Scroll so "parent" becomes pinned.
    scrollController.jumpTo(60);
    await tester.pumpAndSettle();

    final renderObject =
        tester.renderObject(find.byType(SliverTree<String, String>))
            as RenderSliverTree<String, String>;

    final parentNidBefore = controller.nidOf("parent");
    expect(parentNidBefore, isNot(TreeController.noNid));

    // Sanity: parent must currently be sticky for the test to be meaningful.
    expect(renderObject.isNodeRetained("parent"), isTrue);

    // Immediate-purge removal: parent's nid is freed, but the next layout's
    // _stickyHeaders list still contains its stale StickyHeaderInfo.
    controller.remove(key: "parent", animate: false);
    await tester.pumpAndSettle();

    // Allocate enough fresh nodes that one of them recycles parent's old
    // nid. NodeIdRegistry pops from `_freeNids.removeLast()`. After
    // removing parent + 2 leaves, three slots are free. Insert four to be
    // safe.
    controller.insert(
      parentKey: "root",
      node: const TreeNode(key: "fillA", data: "fillA"),
      animate: false,
    );
    controller.insert(
      parentKey: "root",
      node: const TreeNode(key: "fillB", data: "fillB"),
      animate: false,
    );
    controller.insert(
      parentKey: "root",
      node: const TreeNode(key: "fillC", data: "fillC"),
      animate: false,
    );
    controller.insert(
      parentKey: "root",
      node: const TreeNode(key: "fillD", data: "fillD"),
      animate: false,
    );
    await tester.pumpAndSettle();

    // Identify which fresh node landed on parent's old nid.
    final occupant = controller.keyOfNid(parentNidBefore);
    expect(occupant, isNotNull,
        reason: "Expected parent's freed nid to be recycled by an insert");
    expect(
      const ["fillA", "fillB", "fillC", "fillD"].contains(occupant),
      isTrue,
      reason: "Recycled occupant must be one of the inserted fillers; got $occupant",
    );

    // Critical: the recycled occupant must NOT be reported as a sticky
    // header — it has no children, isn't at depth ≤ maxStickyDepth's
    // sticky-eligible range as an actual sticky candidate, and shouldn't
    // inherit the prior occupant's sticky status.
    //
    // Scroll the occupant well outside the cache region so the only way
    // `isNodeRetained` could return true is via a stale sticky entry.
    final occupantIndex = controller.getVisibleIndex(occupant!);
    expect(occupantIndex, greaterThanOrEqualTo(0));

    // Scroll past the occupant. With 30+ tail rows of height 40, scrolling
    // far down ensures the occupant is well beyond the cache region.
    scrollController.jumpTo(800);
    await tester.pumpAndSettle();

    expect(
      renderObject.isNodeRetained(occupant),
      isFalse,
      reason: "Recycled-nid occupant '$occupant' is incorrectly reported "
          "as retained — stale StickyHeaderInfo at nid=$parentNidBefore "
          "is leaking from the freed prior occupant.",
    );
  });
}
