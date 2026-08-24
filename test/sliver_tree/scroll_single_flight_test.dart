/// Repro for L13: every scroll the orchestrator starts is single-flight,
/// in BOTH directions.
///
/// The plain path neither cancels an in-flight animated scroll nor
/// registers itself where a later one would find it. The follower's
/// per-tick `jumpTo` disposes a plain scroll's `DrivenScrollActivity`,
/// whose completer resolves, so the plain future reports `true` for a
/// scroll the orchestrator itself overrode; and a plain scroll leaves a
/// superseded animated session untouched, so its future also resolves
/// `true` while the position lands somewhere else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Widget _harness(
  TreeController<String, String> controller,
  ScrollController scroll,
) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 50,
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

TreeController<String, String> _controller(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    ),
  );
  controller.setRoots([
    for (int i = 0; i < 40; i++) TreeNode(key: "k$i", data: "k$i"),
  ]);
  controller.setChildren("k9", [
    for (int j = 0; j < 30; j++) TreeNode(key: "k9c$j", data: "k9c$j"),
  ]);
  controller.setChildren("k12", [
    for (int j = 0; j < 10; j++) TreeNode(key: "k12c$j", data: "k12c$j"),
  ]);
  return controller;
}

Future<bool> _drain(
  WidgetTester tester,
  Future<bool> f, {
  int cap = 80,
}) async {
  bool done = false;
  late bool value;
  f.then((v) {
    done = true;
    value = v;
  });
  for (int i = 0; i < cap && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue, reason: "setup: the future must resolve");
  return value;
}

void main() {
  testWidgets(
    "a plain scroll cancels an in-flight animated scroll, whose future "
    "resolves false",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final f1 = controller.animateScrollToKey(
        "k9c29",
        scrollController: scroll,
        ancestorExpansion: AncestorExpansionMode.animated,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final f2 = controller.animateScrollToKey(
        "k1",
        scrollController: scroll,
        duration: Duration.zero,
      );
      expect(await _drain(tester, f2), isTrue);

      expect(
        await _drain(tester, f1),
        isFalse,
        reason: "the superseded animated scroll must resolve false; a "
            "plain scroll that never touches the single-flight slot "
            "leaves it running and reporting success",
      );
      await tester.pump();
      await tester.pump();
      expect(
        scroll.position.pixels,
        closeTo(50.0, 1.0),
        reason: "the newest target must win",
      );
      // The cancelled scroll's ancestor expansion keeps animating; let
      // it finish so the ticker check at test end is clean.
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "an animated scroll cancels an in-flight plain scroll, whose future "
    "resolves false",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final p = controller.animateScrollToKey(
        "k30",
        scrollController: scroll,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final a = controller.animateScrollToKey(
        "k9c29",
        scrollController: scroll,
        ancestorExpansion: AncestorExpansionMode.animated,
        duration: const Duration(milliseconds: 300),
      );

      expect(await _drain(tester, a), isTrue);
      expect(
        await _drain(tester, p),
        isFalse,
        reason: "the superseded plain scroll must resolve false; today "
            "the follower's jumpTo completes its DrivenScrollActivity "
            "and the plain path reports true for a scroll the "
            "orchestrator itself overrode",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "a zero-duration scroll superseded during its expansion wait resolves "
    "false without jumping",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      // Immediate mode expands k9 synchronously, then waits one frame
      // for the enlarged sliver; the supersede lands DURING that wait.
      final f1 = controller.animateScrollToKey(
        "k9c29",
        scrollController: scroll,
        duration: Duration.zero,
      );
      final f2 = controller.animateScrollToKey(
        "k12c0",
        scrollController: scroll,
        ancestorExpansion: AncestorExpansionMode.animated,
        duration: const Duration(milliseconds: 300),
      );

      expect(
        await _drain(tester, f1),
        isFalse,
        reason: "a scroll superseded during its one-frame wait must "
            "resolve false instead of jumping to a target the newer "
            "scroll is about to override",
      );
      expect(await _drain(tester, f2), isTrue);

      await tester.pumpAndSettle();
    },
  );
}
