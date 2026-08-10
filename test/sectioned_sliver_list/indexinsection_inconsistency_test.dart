/// Verifies that `ItemView.indexInSection` is LIVE-list space: a sibling
/// that is animating out is skipped, so the items after it report their
/// settled positions immediately rather than when the exit completes.
///
/// Originally this compared the outer `itemBuilder` against the inner
/// result of `view.watch(...)`, and had to force both to re-fire with an
/// `updateItem` call. `watch` is gone, and sibling mutations now refresh
/// the rows they displace, so the assertion is the stronger one: the row
/// re-renders its new index on its own.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "indexInSection skips a pending-deletion sibling, and the displaced row "
    "refreshes without being forced",
    (tester) async {
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
                animationStyle: const TreeAnimationStyle(
                  expandCollapse: TreeAnimationSpec(
                    duration: Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                  ),
                ),
                headerBuilder: (_, view) {
                  controller = view.controller;
                  return SizedBox(height: 30, child: Text("H:${view.key}"));
                },
                itemBuilder: (_, view) {
                  return SizedBox(
                    height: 20,
                    child: Text("I:${view.key}@${view.indexInSection}"),
                  );
                },
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("I:a@0"), findsOneWidget);
      expect(find.text("I:b@1"), findsOneWidget);
      expect(find.text("I:c@2"), findsOneWidget);

      // Remove the middle item with animation: it stays painted while it
      // exits, but drops out of live-list space immediately.
      controller.removeItem("b", animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        controller.itemKeysOf("s", includeExiting: true),
        contains("b"),
        reason: "setup sanity: 'b' is still present mid-exit",
      );
      expect(
        controller.itemKeysOf("s"),
        equals(["a", "c"]),
        reason: "setup sanity: the live set already excludes 'b'",
      );

      expect(
        find.text("I:c@1"),
        findsOneWidget,
        reason:
            "'c' is at live index 1 with 'b' exiting, and its row must "
            "re-render on its own",
      );

      await tester.pumpAndSettle();
      expect(find.text("I:c@1"), findsOneWidget);
    },
  );
}
