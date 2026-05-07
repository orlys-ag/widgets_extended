/// Verifies that mounting a [SectionedSliverList.controlled] against a
/// pre-populated controller does NOT touch the controller's expansion
/// state. In v2, `.controlled` mode treats the controller as the source
/// of truth and never applies `initiallyExpanded` / `initialSectionExpansion`
/// — those config knobs aren't even on `.controlled`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("mounting .controlled against an external controller with a "
      "user-collapsed section preserves that collapse", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Pre-populate before mount. User explicitly: 'a' expanded, 'b'
    // collapsed.
    controller.setSections(["a", "b"], itemsOf: (s) => ["${s}1"]);
    controller.expandSection("a", animate: false);
    // 'b' stays collapsed.

    expect(controller.isExpanded("a"), isTrue);
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

    expect(
      controller.isExpanded("a"),
      isTrue,
      reason: "Pre-mount expanded state must survive mount in .controlled.",
    );
    expect(
      controller.isExpanded("b"),
      isFalse,
      reason: ".controlled mode is the source of truth — must NOT apply "
          "any initial-expansion config.",
    );
  });
}
