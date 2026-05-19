/// Verifies that `ItemView.indexInSection` is consistent between the
/// outer itemBuilder result and the inner result of `view.watch(...)`.
///
/// Both must use LIVE-list space (skipping pending-deletion siblings).
/// The outer index comes from `treeController.getIndexInParent(key)` and
/// the inner index comes from `controller.indexOfItem(key)` — both
/// resolve to the same underlying primitive.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("indexInSection agrees between outer itemBuilder and "
      "view.watch when a pending-deletion sibling sits between live items",
      (tester) async {
    final outerIndices = <String, int>{};
    final innerIndices = <String, int>{};
    late SectionedListController<String, String, String> controller;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: const ["s"],
              itemsOf: (_) => const ["a", "b", "c"],
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              animationDuration: const Duration(milliseconds: 200),
              headerBuilder: (_, view) {
                controller = view.controller;
                return SizedBox(height: 30, child: Text("H:${view.key}"));
              },
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
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(outerIndices["a"], 0);
    expect(outerIndices["b"], 1);
    expect(outerIndices["c"], 2);

    // Remove 'b' with animation → pending-deletion.
    controller.removeItem("b", animate: true);
    await tester.pump(const Duration(milliseconds: 80));
    // Force both the outer itemBuilder AND the inner watch to re-fire
    // for 'c'. updateItem fires the typed payload listener which the
    // inner watch listens to; the outer is rebuilt because the structural
    // listener fires when 'b' enters pending-deletion.
    controller.updateItem("c", "c");
    await tester.pump();

    // 'b' is still present with includeExiting:true during exit.
    expect(
      controller.itemKeysOf("s", includeExiting: true),
      contains("b"),
    );
    // ...but live-set excludes it.
    expect(controller.itemKeysOf("s"), equals(["a", "c"]));

    expect(
      innerIndices["c"],
      outerIndices["c"],
      reason: "outer indexInSection for 'c' = ${outerIndices["c"]} "
          "(LIVE-list, skips pending-deletion 'b'). "
          "inner watch indexInSection for 'c' = ${innerIndices["c"]}. "
          "Both must agree.",
    );

    await tester.pumpAndSettle();
  });
}
