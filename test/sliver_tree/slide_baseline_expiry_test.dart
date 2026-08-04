/// D12 repro tests: `beginSlideBaseline`'s caller contract ("every
/// successful stage MUST be followed by a same-frame structural mutation")
/// was comment-enforced only. A violating caller left the baseline staged
/// forever — silently blocking every subsequent slide stage (first-wins
/// slot) until an unrelated layout flushed it.
///
/// Expected post-D12 behavior: a staged-but-unconsumed baseline is
/// discarded at the end of the next frame, a debug FlutterError names the
/// protocol violation, and later slides work normally.
///
/// Repro-test methodology: the first test fails on pre-D12 code (the slot
/// stays staged, no error is reported). The second is the false-positive
/// guard: the legitimate stage→mutate→consume flow must NOT trip the
/// backstop.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Future<TreeController<String, String>> _mount(WidgetTester tester) async {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 200), curve: Curves.linear)),
  );
  addTearDown(controller.dispose);
  controller.setRoots([
    const TreeNode(key: "a", data: "A"),
    const TreeNode(key: "b", data: "B"),
    const TreeNode(key: "c", data: "C"),
  ]);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
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
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

RenderSliverTree<String, String> _render(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

void main() {
  testWidgets(
    "a staged baseline with no following mutation is discarded next frame "
    "with a debug error, and later slides still work",
    (tester) async {
      final controller = await _mount(tester);
      final render = _render(tester);

      // Violate the protocol: stage and mutate nothing.
      render.beginSlideBaseline(
        duration: const Duration(milliseconds: 120),
        curve: Curves.linear,
      );
      expect(render.debugSlideBaselineStaged, isTrue,
          reason: "setup: the stage must have been accepted");

      // Next frame: no layout consumed it → the backstop must discard it
      // and report the violation in debug builds.
      await tester.pump();
      expect(
        render.debugSlideBaselineStaged,
        isFalse,
        reason: "an unconsumed baseline must not outlive the next frame — "
            "first-wins staging would otherwise block every later slide",
      );
      final reported = tester.takeException();
      expect(reported, isA<FlutterError>(),
          reason: "the protocol violation must be loud in debug builds");

      // A subsequent REAL reorder must still slide: the discarded
      // baseline must not have poisoned the pipeline.
      controller.reorderRoots(["c", "a", "b"]);
      await tester.pump();
      var sawActiveSlide = false;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        if (controller.hasActiveSlides) {
          sawActiveSlide = true;
        }
      }
      expect(sawActiveSlide, isTrue,
          reason: "the animated reorder after the discard must still "
              "install its FLIP slide");
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "the legitimate stage → mutate → consume flow does not trip the "
    "backstop",
    (tester) async {
      final controller = await _mount(tester);
      final render = _render(tester);

      // reorderRoots(animate: true) stages via the render-host fan-out and
      // mutates in the same call; the next frame's layout consumes the
      // baseline before the post-frame check runs.
      controller.reorderRoots(["b", "c", "a"]);
      await tester.pump();

      expect(render.debugSlideBaselineStaged, isFalse,
          reason: "the layout pass consumed the baseline");
      expect(tester.takeException(), isNull,
          reason: "a consumed baseline is not a violation — the backstop "
              "must not false-positive on the normal flow");
      await tester.pumpAndSettle();
    },
  );
}
