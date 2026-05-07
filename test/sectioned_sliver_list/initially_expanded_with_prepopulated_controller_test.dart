/// Verifies the v2 expansion contract:
///
///  • `.controlled` mode never applies `initiallyExpanded` /
///    `initialSectionExpansion` — controller state is the truth, full
///    stop. There are no widget knobs for those in this mode.
///
///  • default/`.fromMap` mode applies the widget's initial-expansion
///    config to all sections on first sync (the internal controller is
///    always fresh).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(".controlled mounted against pre-populated controller does NOT "
      "force-expand collapsed sections", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.setSections(["a", "b"], itemsOf: (s) => ["${s}1"]);
    // Both sections start collapsed. v2 .controlled must not change this.
    expect(controller.isExpanded("a"), isFalse);
    expect(controller.isExpanded("b"), isFalse);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>.controlled(
              controller: controller,
              headerBuilder: (_, view) =>
                  SizedBox(height: 30, child: Text(view.key)),
              itemBuilder: (_, view) =>
                  SizedBox(height: 20, child: Text(view.key)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.isExpanded("a"), isFalse,
        reason: ".controlled must not auto-expand pre-collapsed sections.");
    expect(controller.isExpanded("b"), isFalse);
  });

  testWidgets(".controlled preserves user's explicit expansion state when "
      "pre-populated controller has a mix", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    controller.setSections(["a", "b"], itemsOf: (s) => ["${s}1"]);
    controller.expandSection("a", animate: false);
    // 'a' expanded, 'b' collapsed.

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>.controlled(
              controller: controller,
              headerBuilder: (_, view) =>
                  SizedBox(height: 30, child: Text(view.key)),
              itemBuilder: (_, view) =>
                  SizedBox(height: 20, child: Text(view.key)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.isExpanded("a"), isTrue,
        reason: "User's explicit expansion on 'a' must be preserved.");
    expect(controller.isExpanded("b"), isFalse,
        reason: "User's explicit collapse on 'b' must be preserved.");
  });

  testWidgets("default mode (internal controller) applies initiallyExpanded:"
      "true on first sync", (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: const ["a"],
              itemsOf: (_) => const ["a1"],
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              animationDuration: Duration.zero,
              initiallyExpanded: true,
              headerBuilder: (_, view) =>
                  SizedBox(height: 30, child: Text("H:${view.key}")),
              itemBuilder: (_, view) =>
                  SizedBox(height: 20, child: Text("I:${view.key}")),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("I:a1"), findsOneWidget,
        reason: "default-mode internal controller with initiallyExpanded:"
            "true should render the section's items.");
  });
}
