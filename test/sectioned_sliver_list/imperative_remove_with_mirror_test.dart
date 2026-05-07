/// Regression: imperative `removeItem` / `removeSection` followed by a
/// widget rebuild that mirrors the controller back into a `setSections`
/// call must not silently undo the deletion.
///
/// In v2, the canonical way to do this is `.controlled` + manual
/// `setSections` from the parent's `didUpdateWidget`. The widget itself
/// never reads from a prop; the user owns the mirror.
///
/// The bug this guards against: the sync controller's retained-branch
/// auto-cancelling pending-deletion nodes via
/// `insertRoot(preservePendingSubtreeState: true)`, which would fire on
/// every imperative remove if the mirror naturally includes the still-
/// present pending row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("imperative removeItem + manual mirror via setSections honors "
      "the deletion", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["s"],
      itemsOf: (_) => const ["a", "b", "c"],
    );
    controller.expandSection("s", animate: false);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>.controlled(
              controller: controller,
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

    expect(find.text("I:b"), findsOneWidget);

    // Imperative remove with animation. 'b' enters pending-deletion.
    controller.removeItem("b", animate: true);

    // Now the user mirrors the live state back via setSections — common
    // v2 pattern for a parent that owns its data and re-syncs in
    // didUpdateWidget. With live-by-default queries, 'b' is not in the
    // mirror.
    final liveSections = controller.sectionKeys;
    final liveItemsBySection = {
      for (final s in liveSections) s: controller.itemKeysOf(s),
    };
    controller.setSections(
      liveSections,
      itemsOf: (s) => liveItemsBySection[s] ?? const [],
    );

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasItem("b"), isFalse,
        reason: "Imperative removeItem followed by a live-mirror setSections "
            "must purge 'b'.");
    expect(controller.itemKeysOf("s"), equals(["a", "c"]));
  });

  testWidgets("imperative removeSection + manual mirror via setSections "
      "honors the deletion", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);

    controller.setSections(
      ["a", "b", "c"],
      itemsOf: (_) => const [],
    );

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

    controller.removeSection("b", animate: true);
    final liveSections = controller.sectionKeys;
    controller.setSections(
      liveSections,
      itemsOf: (_) => const [],
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.hasSection("b"), isFalse);
    expect(controller.sectionKeys, equals(["a", "c"]));
  });
}
