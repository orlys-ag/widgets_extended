/// Regression for `initiallyExpanded: true` failing to apply when an
/// external controller is pre-populated with sections in `initState`
/// before the widget mounts.
///
/// The first-sync heuristic must distinguish "user has explicit
/// expansion state on the controller" (preserve) from "controller is in
/// default-collapsed state" (apply widget config). The fix uses
/// `any(isExpanded)` as the discriminator: zero expanded sections means
/// "default state" and `initiallyExpanded` applies; one or more
/// expanded sections means "user-managed" and the existing state is
/// preserved.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("initiallyExpanded:true expands sections of an external "
      "controller pre-populated with all-collapsed sections",
      (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Mirrors the SectionedSliverListExample pattern: populate the
    // controller before mounting the widget. Sections are added in
    // their default-collapsed state.
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

    expect(controller.isExpanded("a"), isFalse,
        reason: "Sanity: 'a' default-collapsed before mount");
    expect(controller.isExpanded("b"), isFalse);

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
          initiallyExpanded: true,
          headerBuilder: (_, view) =>
              SizedBox(height: 30, child: Text(view.key)),
          itemBuilder: (_, view) =>
              SizedBox(height: 20, child: Text(view.key)),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(controller.isExpanded("a"), isTrue,
        reason: "initiallyExpanded:true should expand 'a' on first mount "
            "even when the controller was pre-populated default-collapsed.");
    expect(controller.isExpanded("b"), isTrue,
        reason: "initiallyExpanded:true should expand 'b' on first mount "
            "even when the controller was pre-populated default-collapsed.");
  });

  testWidgets("initiallyExpanded:true does NOT override user's explicit "
      "expansion state on a pre-populated external controller "
      "(iteration 14 regression check)", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

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
    // Explicit user state: 'a' expanded, 'b' collapsed. The presence of
    // an expanded section signals "user-managed" — heuristic should
    // preserve.
    controller.expandSection("a", animate: false);

    expect(controller.isExpanded("a"), isTrue);
    expect(controller.isExpanded("b"), isFalse);

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
          initiallyExpanded: true,
          headerBuilder: (_, view) =>
              SizedBox(height: 30, child: Text(view.key)),
          itemBuilder: (_, view) =>
              SizedBox(height: 20, child: Text(view.key)),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(controller.isExpanded("a"), isTrue,
        reason: "User's explicit expansion on 'a' must be preserved.");
    expect(controller.isExpanded("b"), isFalse,
        reason: "User's explicit collapse on 'b' must be preserved — "
            "'a' being expanded signals 'user-managed' state.");
  });

  testWidgets("internal controller (no pre-population) applies "
      "initiallyExpanded as before", (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(slivers: [
        SectionedSliverList<String, String, String, String>(
          sections: [
            SectionInput<String, String, String, String>(
              key: "a",
              section: "A",
              items: const [ItemInput(key: "a1", item: "A1")],
            ),
          ],
          animationDuration: Duration.zero,
          initiallyExpanded: true,
          headerBuilder: (_, view) =>
              SizedBox(height: 30, child: Text("H:${view.key}")),
          itemBuilder: (_, view) =>
              SizedBox(height: 20, child: Text("I:${view.key}")),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    // Item should be visible (section expanded).
    expect(find.text("I:a1"), findsOneWidget,
        reason: "Internal controller with initiallyExpanded:true should "
            "render the section's items.");
  });
}
