import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// Section-header item-count invalidation regression test
/// (plans/2026-08-04-child-count-invalidation-plan.md).
///
/// `SectionView.itemCount` renders the raw child count of the section node
/// (`sectioned_sliver_list_widget.dart` header build site). After an
/// animated item removal the count is purged from the child list only when
/// the exit animations complete, and under the old "hasChildren flipped"
/// invalidation rule the header row was never refreshed unless the section
/// emptied entirely, so it kept showing the pre-removal count forever.
void main() {
  testWidgets(
    "section header itemCount refreshes after animated item removal",
    (tester) async {
      final controller = SectionedListController<String, String, String>(
        vsync: tester,
        sectionKeyOf: (s) => s,
        itemKeyOf: (i) => i,
        animationStyle: const TreeAnimationStyle(
          enterExit: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setSections(
        ["s1"],
        itemsOf: (_) => [for (int i = 0; i < 12; i++) "i$i"],
      );
      controller.expandSection("s1", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SectionedSliverList<String, String, String>.controlled(
                  controller: controller,
                  headerBuilder: (context, view) {
                    return SizedBox(
                      height: 48,
                      child: Text("items:${view.itemCount}"),
                    );
                  },
                  itemBuilder: (context, view) {
                    return SizedBox(height: 48, child: Text(view.item));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      // One tick past the first frame: the section root was inserted with
      // an enter animation BEFORE the tree first mounted, so on frame 1 it
      // sits at zero extent with an unmeasured target and is not admitted
      // by layout yet. One pump later it renders. (Pre-existing behavior,
      // unrelated to the invalidation under test.)
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text("items:12"), findsOneWidget);

      controller.setItems(
        "s1",
        [for (int i = 0; i < 3; i++) "i$i"],
        animate: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Setup sanity: the animated path is genuinely exercised (a removed
      // item row is still painted mid-exit) and the header's raw count
      // matches the rows still on screen.
      expect(
        find.text("i5"),
        findsOneWidget,
        reason: "setup sanity: removed item must still be painted mid-exit, "
            "proving the animated path is exercised",
      );
      expect(
        find.text("items:12"),
        findsOneWidget,
        reason: "itemCount includes items animating out; the header must "
            "match the rows still visible",
      );

      await tester.pumpAndSettle();

      expect(
        find.text("items:3"),
        findsOneWidget,
        reason: "after the exit animations purge the removed items, the "
            "header must refresh to the new count, not keep showing the "
            "pre-removal number forever",
      );
    },
  );
}
