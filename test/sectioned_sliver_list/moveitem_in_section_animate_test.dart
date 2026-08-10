/// Regression: an in-section [SectionedListController.moveItem] must
/// honour `animate: false`, and its documentation must describe what it
/// actually does.
///
/// The docs claimed "In-section reorders are pure repositioning ops that
/// never animate regardless of [animate]". They do animate: `moveItem`
/// forwards to `reorderItems`, which calls
/// [TreeController.reorderChildren], which stages a paint-only FLIP slide
/// whenever the parent is visible and the `reorderSlide` family is not
/// zeroed. The doc was describing per-row enter/exit animations, which
/// genuinely do not happen, and read as though nothing moved at all.
///
/// Worse than the doc: `moveItem`'s own `animate` argument was dropped on
/// the in-section path, so `animate: false` still slid.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Future<SectionedListController<String, String, String>> _pumpList(
  WidgetTester tester,
) async {
  final controller = SectionedListController<String, String, String>(
    vsync: tester,
    sectionKeyOf: (s) => s,
    itemKeyOf: (i) => i,
  );
  addTearDown(controller.dispose);

  controller.setSections(["a"], itemsOf: (_) => const [], animate: false);
  controller.addItem("a1", toSection: "a", animate: false);
  controller.addItem("a2", toSection: "a", animate: false);
  controller.addItem("a3", toSection: "a", animate: false);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(
        slivers: [
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, v) {
              return SizedBox(height: 40, child: Text(v.key));
            },
            itemBuilder: (ctx, v) {
              return SizedBox(height: 40, child: Text(v.key));
            },
          ),
        ],
      ),
    ),
  );
  controller.expandSection("a", animate: false);
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets("in-section moveItem animates by default", (tester) async {
    final controller = await _pumpList(tester);

    // Setup sanity: the section is open and its items are on screen, so
    // reorderChildren's `visible` gate is satisfied and a slide is
    // genuinely possible.
    expect(controller.isExpanded("a"), isTrue);
    expect(find.text("a2"), findsOneWidget);
    expect(controller.treeController.hasActiveSlides, isFalse);

    controller.moveItem("a1", index: 2);
    await tester.pump();

    expect(controller.itemKeysOf("a"), equals(["a2", "a3", "a1"]));
    expect(
      controller.treeController.hasActiveSlides,
      isTrue,
      reason: "an in-section reorder of visible rows stages a FLIP slide",
    );

    await tester.pumpAndSettle();
    expect(controller.treeController.hasActiveSlides, isFalse);
  });

  testWidgets("in-section moveItem honours animate: false", (tester) async {
    final controller = await _pumpList(tester);

    expect(controller.isExpanded("a"), isTrue);
    expect(find.text("a2"), findsOneWidget);

    controller.moveItem("a1", index: 2, animate: false);
    await tester.pump();

    // The reorder still applies, it just does not slide.
    expect(controller.itemKeysOf("a"), equals(["a2", "a3", "a1"]));
    expect(
      controller.treeController.hasActiveSlides,
      isFalse,
      reason: "animate: false must suppress the slide on the in-section path",
    );

    await tester.pumpAndSettle();
  });

  testWidgets("reorderItems honours animate: false", (tester) async {
    final controller = await _pumpList(tester);

    controller.reorderItems("a", ["a3", "a2", "a1"], animate: false);
    await tester.pump();

    expect(controller.itemKeysOf("a"), equals(["a3", "a2", "a1"]));
    expect(controller.treeController.hasActiveSlides, isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets("a collapsed section's reorder does not slide", (tester) async {
    final controller = await _pumpList(tester);
    controller.collapseSection("a", animate: false);
    await tester.pumpAndSettle();

    controller.moveItem("a1", index: 2);
    await tester.pump();

    expect(controller.itemKeysOf("a"), equals(["a2", "a3", "a1"]));
    expect(
      controller.treeController.hasActiveSlides,
      isFalse,
      reason: "reorderChildren gates the slide on the parent being visible",
    );

    await tester.pumpAndSettle();
  });
}
