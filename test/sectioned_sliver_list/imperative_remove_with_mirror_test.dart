/// Regression for the example pattern: imperative `removeItem` /
/// `removeSection` followed by setState rebuild that mirrors the
/// controller back through the widget's `sections` prop must NOT
/// silently undo the deletion.
///
/// The bug: my prior iteration-16 fix made the sync controller's
/// retained-branch auto-cancel pending-deletion nodes via
/// `insertRoot(preservePendingSubtreeState: true)`. The example mirrors
/// the FULL controller state (including pending rows) back through
/// `sections`, which made the auto-cancel fire on every imperative
/// remove.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("imperative removeItem followed by widget rebuild that "
      "mirrors controller (full or live) honors the deletion",
      (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "s",
        section: "S",
        items: const [
          ItemInput(key: "a", item: "A"),
          ItemInput(key: "b", item: "B"),
          ItemInput(key: "c", item: "C"),
        ],
      ),
    ]);
    controller.expandSection("s", animate: false);

    // Mounting wraps everything; sections prop mirrors live state.
    Widget makeList() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(slivers: [
          SectionedSliverList<String, String, String, String>(
            controller: controller,
            sections: [
              for (final sKey in controller.liveSections)
                SectionInput<String, String, String, String>(
                  key: sKey,
                  section: controller.getSection(sKey)!,
                  items: <ItemInput<String, String>>[
                    for (final iKey in controller.liveItemsOf(sKey))
                      ItemInput<String, String>(
                        key: iKey,
                        item: controller.getItem(iKey)!,
                      ),
                  ],
                ),
            ],
            headerBuilder: (_, view) =>
                SizedBox(height: 30, child: Text("H:${view.key}")),
            itemBuilder: (_, view) =>
                SizedBox(height: 20, child: Text("I:${view.key}")),
          ),
        ]),
      );
    }

    await tester.pumpWidget(makeList());
    await tester.pumpAndSettle();

    expect(find.text("I:b"), findsOneWidget);

    // Imperative remove. setState would normally re-render — simulate
    // by re-pumping the widget (the makeList closure reads the
    // controller anew, mirroring liveItemsOf which excludes 'b' once it
    // enters pending-deletion).
    controller.removeItem("b", animate: true);
    await tester.pumpWidget(makeList());

    // Wait past the animation duration.
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.hasItem("b"), isFalse,
        reason: "Imperative removeItem followed by a rebuild that mirrors "
            "the controller through sections prop should not undo the "
            "deletion. 'b' should be purged.");
    expect(controller.itemsOf("s"), equals(["a", "c"]));
  });

  testWidgets("imperative removeSection followed by widget rebuild that "
      "mirrors controller honors the deletion", (tester) async {
    final controller =
        SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections([
      SectionInput<String, String, String, String>(
        key: "a",
        section: "A",
      ),
      SectionInput<String, String, String, String>(
        key: "b",
        section: "B",
      ),
      SectionInput<String, String, String, String>(
        key: "c",
        section: "C",
      ),
    ]);

    Widget makeList() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(slivers: [
          SectionedSliverList<String, String, String, String>(
            controller: controller,
            sections: [
              for (final sKey in controller.liveSections)
                SectionInput<String, String, String, String>(
                  key: sKey,
                  section: controller.getSection(sKey)!,
                ),
            ],
            headerBuilder: (_, view) =>
                SizedBox(height: 30, child: Text(view.key)),
            itemBuilder: (_, view) =>
                SizedBox(height: 20, child: Text(view.key)),
          ),
        ]),
      );
    }

    await tester.pumpWidget(makeList());
    await tester.pumpAndSettle();

    controller.removeSection("b", animate: true);
    await tester.pumpWidget(makeList());
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.hasSection("b"), isFalse,
        reason: "Imperative removeSection followed by a mirroring "
            "rebuild should not undo the deletion.");
    expect(controller.sections, equals(["a", "c"]));
  });
}
