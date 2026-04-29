/// Verifies that `ItemView.indexInSection` is consistent between the
/// outer itemBuilder result and the inner result of `view.watch(...)`.
///
/// The outer builder gets `indexInSection` from
/// `treeController.getIndexInParent(key)` which returns the LIVE-list
/// index (skipping pending-deletion siblings). The inner watch builder
/// computes `widget.controller.itemsOf(sectionKey).indexOf(itemKey)`
/// which returns the FULL-list index (including pending-deletion). With
/// a pending-deletion sibling between, the two values diverge.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("indexInSection is consistent between outer itemBuilder "
      "and view.watch inner builder when a pending-deletion sibling sits "
      "between live items", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    final outerIndices = <String, int>{};
    final innerIndices = <String, int>{};

    final sections = [
      SectionInput<String, String, String, String>(
        key: "s",
        section: "S",
        items: const [
          ItemInput(key: "a", item: "A"),
          ItemInput(key: "b", item: "B"),
          ItemInput(key: "c", item: "C"),
        ],
      ),
    ];

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(slivers: [
        SectionedSliverList<String, String, String, String>(
          controller: controller,
          sections: sections,
          headerBuilder: (_, view) =>
              SizedBox(height: 30, child: Text("H:${view.key}")),
          itemBuilder: (_, view) {
            outerIndices[view.key] = view.indexInSection;
            return view.watch(
              builder: (_, watchedView) {
                innerIndices[watchedView.key] = watchedView.indexInSection;
                return SizedBox(
                  height: 20,
                  child: Text("I:${watchedView.key}"),
                );
              },
            );
          },
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(outerIndices["a"], 0,
        reason: "Sanity: 'a' at index 0 initially");
    expect(outerIndices["b"], 1);
    expect(outerIndices["c"], 2);

    // Remove 'b' with animation → pending-deletion.
    controller.removeItem("b", animate: true);
    await tester.pump(const Duration(milliseconds: 80));
    // Force BOTH outer itemBuilder AND inner watch to re-fire for 'c'
    // by calling updateItem on 'c' — the outer is rebuilt because
    // _onNodeDataChanged queues 'c' into _dirtyKeys; the inner is
    // rebuilt because _ItemViewListener's _onPayload fires on any
    // nodeData notification.
    controller.updateItem("c", "C");
    await tester.pump();

    expect(controller.itemsOf("s"), contains("b"),
        reason: "'b' should still be in itemsOf during exit animation");

    expect(
      innerIndices["c"],
      outerIndices["c"],
      reason:
          "outer indexInSection for 'c' = ${outerIndices["c"]} "
          "(LIVE-list, skips pending-deletion 'b'). "
          "inner watch indexInSection for 'c' = ${innerIndices["c"]} "
          "(FULL-list, includes pending-deletion 'b'). The two paths "
          "should agree on whether to include pending-deletion siblings.",
    );

    // Drain to clean up.
    await tester.pumpAndSettle();
  });
}
