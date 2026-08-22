/// Regression test for issue 3 of the 2026-08-21 review: an
/// animated-concurrent `animateScrollToKey` wrote to a disposed
/// [ScrollPosition] when the scrollable was rebuilt mid-scroll.
///
/// `_animatedConcurrentScroll` captured `scrollController.position` once
/// and its per-tick follower called `jumpTo` on that captured object. A
/// scrollable rebuilt under the SAME [ScrollController] (a new widget
/// identity, so a fresh [ScrollPosition]) leaves the captured position
/// disposed while `hasClients` stays true, so the completion loop never
/// tore the follower down and every subsequent tick asserted
/// "A ScrollPositionWithSingleContext was used after being disposed"
/// (and, in release, wrote to an object nothing renders).
///
/// The plain-unmount case is the control: it was always safe, because the
/// loop wakes at `endOfFrame`, sees `!hasClients`, and tears down before
/// the next tick.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

TreeController<String, String> _buildTree(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ),
    ),
  );
  controller.setRoots([
    for (int i = 0; i < 40; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);
  // A collapsed chain under the last root so the ANIMATED ancestor
  // expansion path (the one with the per-tick follower) is taken.
  controller.setChildren("r39", [const TreeNode(key: "mid", data: "M")]);
  controller.setChildren("mid", [const TreeNode(key: "target", data: "T")]);
  return controller;
}

Widget _host(
  TreeController<String, String> controller,
  ScrollController scrollController, {
  Key? viewKey,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        key: viewKey,
        controller: scrollController,
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (context, key, depth) {
              return SizedBox(height: 50, child: Text(key));
            },
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets("rebuilding the scrollable mid animated-concurrent scroll "
      "follows the NEW position instead of the disposed one", (tester) async {
    final controller = _buildTree(tester);
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(_host(controller, scrollController));
    await tester.pumpAndSettle();

    bool? result;
    Object? error;
    controller
        .animateScrollToKey(
          "target",
          scrollController: scrollController,
          duration: const Duration(milliseconds: 300),
          ancestorExpansion: AncestorExpansionMode.animated,
        )
        .then((value) => result = value, onError: (Object e) => error = e);

    await tester.pump(const Duration(milliseconds: 50));
    expect(result, isNull, reason: "setup: the scroll is still in flight");
    expect(scrollController.hasClients, isTrue);

    // Rebuild the scrollable with a fresh identity: the controller
    // detaches from the old position (which is then disposed) and
    // attaches to a new one, so `hasClients` never goes false.
    await tester.pumpWidget(
      _host(controller, scrollController, viewKey: UniqueKey()),
    );
    expect(
      scrollController.hasClients,
      isTrue,
      reason: "setup: the swap keeps a client attached, which is why the "
          "completion loop cannot notice it",
    );

    // Each of these ticks used to assert on the disposed position.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(error, isNull);
    expect(result, isNotNull, reason: "the scroll future must complete");
    // The assertion above only catches the DEBUG symptom. In release the
    // same defect is silent: the follower keeps driving an object nothing
    // renders while the visible scrollable never moves. Assert the
    // outcome the user would notice, which is what makes this test
    // meaningful with asserts compiled out.
    expect(
      scrollController.offset,
      greaterThan(0.0),
      reason: "the NEW position must actually have been scrolled",
    );
    expect(
      find.text("target"),
      findsOneWidget,
      reason: "and the row the scroll was asked for must be on screen",
    );
  });

  testWidgets("unmounting the scrollable mid animated-concurrent scroll "
      "still completes cleanly", (tester) async {
    final controller = _buildTree(tester);
    addTearDown(controller.dispose);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(_host(controller, scrollController));
    await tester.pumpAndSettle();

    bool? result;
    Object? error;
    controller
        .animateScrollToKey(
          "target",
          scrollController: scrollController,
          duration: const Duration(milliseconds: 300),
          ancestorExpansion: AncestorExpansionMode.animated,
        )
        .then((value) => result = value, onError: (Object e) => error = e);

    await tester.pump(const Duration(milliseconds: 50));
    expect(result, isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(scrollController.hasClients, isFalse);

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(error, isNull);
    expect(result, isNotNull);
  });
}
