/// Verifies that mounting a [SectionedSliverList] against an external
/// controller that already has sections preserves the controller's
/// existing expansion state instead of forcing every section back to the
/// widget's `initiallyExpanded` default.
///
/// The bug: `_sync(isFirstSync: true)` seeds `knownSections = {}`, so the
/// initial-expansion pass treats every section as "new in this sync" and
/// applies the widget's expansion config — overriding any state the user
/// set on the controller before mounting.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("mounting with an external controller that has a "
      "user-collapsed section preserves that collapse", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Pre-populate the controller before any widget mounts. User
    // collapses 'b' to express their preference.
    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "a",
        section: "A",
        items: const [ItemInput(key: "a1", item: "A1")],
      ),
      SectionInput<String, String, String, String>(
        key: "b",
        section: "B",
        items: const [ItemInput(key: "b1", item: "B1")],
      ),
    ]);
    // Default initiallyExpanded behavior on first setSections leaves
    // sections collapsed in the controller — expand explicitly so we can
    // then collapse `b` and observe that the widget mount doesn't re-
    // expand it.
    controller.expandSection("a", animate: false);
    controller.expandSection("b", animate: false);
    controller.collapseSection("b", animate: false);

    expect(controller.isExpanded("a"), isTrue);
    expect(controller.isExpanded("b"), isFalse,
        reason: "Sanity: 'b' was just collapsed by the user");

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(slivers: [
        SectionedSliverList<String, String, String, String>(
          controller: controller,
          sections: [
            SectionInput<String, String, String, String>(
              key: "a",
              section: "A",
              items: const [ItemInput(key: "a1", item: "A1")],
            ),
            SectionInput<String, String, String, String>(
              key: "b",
              section: "B",
              items: const [ItemInput(key: "b1", item: "B1")],
            ),
          ],
          initiallyExpanded: true, // Widget default — would re-expand 'b'
          headerBuilder: (_, view) =>
              SizedBox(height: 30, child: Text(view.key)),
          itemBuilder: (_, view) =>
              SizedBox(height: 20, child: Text(view.key)),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(
      controller.isExpanded("b"),
      isFalse,
      reason: "Mounting widget against external controller with "
          "user-collapsed 'b' must preserve that state, not force "
          "initiallyExpanded=true onto it.",
    );
  });
}
