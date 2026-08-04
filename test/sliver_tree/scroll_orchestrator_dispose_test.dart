/// Regression test for audit item 1.9: disposing the [TreeController]
/// while an animated-concurrent `animateScrollToKey` is mid-flight must
/// cancel the scroll cleanly — the completion loop used to be
/// `while (true) { ...; await endOfFrame; }` with no cancellation hook,
/// leaving the follower listener registered and the internal
/// AnimationController's Ticker active forever (tripping the framework's
/// active-Ticker check) and pumping frames indefinitely for offstage
/// trees.
///
/// Extended for review item R2 (2026-07-15): the 1.9 teardown was a
/// SINGLE slot — a second concurrent animated scroll overwrote
/// `_activeScrollProgress`/`_activeFollower`, and the first scroll's
/// `finally` nulled the slots unconditionally even when they held the
/// second scroll's resources. With two overlapping animated scrolls,
/// `dispose()` tore down only the slot's occupant; the other scroll's
/// AnimationController stayed active, re-tripping the exact active-Ticker
/// assert 1.9 fixed. The R2 fix makes animated scrolls single-flight:
/// starting a new one cancels the in-flight one (its future resolves
/// false), so the single slot is correct by construction.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// Hosts the controllers on a real [TickerProviderStateMixin] State so
/// unmounting it exercises the framework's dispose-time active-Ticker
/// assert — the R2 failure surfaces there, not in test-fixture vsyncs.
class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  late final TreeController<String, String> controller;
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    controller = TreeController<String, String>(
      vsync: this,
      animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.easeInOut)),
    );
    scrollController = ScrollController();
    controller.setRoots([
      for (int i = 0; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    // Two independent collapsed chains so BOTH scrolls take the
    // animated-concurrent path (each needs its own collapsed ancestors).
    controller.setChildren("r19", [const TreeNode(key: "a-mid", data: "M")]);
    controller.setChildren("a-mid", [
      const TreeNode(key: "a-target", data: "T"),
    ]);
    controller.setChildren("r15", [const TreeNode(key: "b-mid", data: "M")]);
    controller.setChildren("b-mid", [
      const TreeNode(key: "b-target", data: "T"),
    ]);
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    // TickerProviderStateMixin's dispose asserts that no Ticker created
    // by this State is still active — the R2 discriminator.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverTree<String, String>(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            return SizedBox(height: 50, child: Text(key));
          },
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    "disposing the controller mid animated-concurrent scroll cancels "
    "cleanly (no active ticker, future completes false)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.easeInOut)),
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      controller.setRoots([
        for (int i = 0; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      // Deep collapsed chain under the last root so the animated
      // ancestor-expansion path is exercised.
      controller.setChildren("r19", [const TreeNode(key: "mid", data: "M")]);
      controller.setChildren("mid", [
        const TreeNode(key: "target", data: "T"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
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
        ),
      );
      await tester.pumpAndSettle();

      bool completed = false;
      bool? result;
      controller
          .animateScrollToKey(
            "target",
            scrollController: scrollController,
            duration: const Duration(milliseconds: 300),
            ancestorExpansion: AncestorExpansionMode.animated,
          )
          .then((v) {
        completed = true;
        result = v;
      });

      // Let the concurrent expand+scroll get genuinely mid-flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(completed, isFalse,
          reason: "setup: the animated scroll must still be in flight");

      // Dispose the controller mid-flight — the scrollable is still
      // mounted (hasClients stays true), so only the cancellation path
      // can end the loop.
      controller.dispose();
      await tester.pump();

      expect(
        completed,
        isTrue,
        reason: "the in-flight animateScrollToKey future must complete "
            "when the controller is disposed (cancellation), not keep "
            "awaiting endOfFrame forever",
      );
      expect(result, isFalse,
          reason: "a cancelled scroll reports false (did not complete)");
      // The framework's end-of-test ticker check enforces that the
      // internal scroll-progress AnimationController was disposed.
    },
  );

  testWidgets(
    "two concurrent animated scrolls + unmount: no active-Ticker assert, "
    "both futures resolve false (R2)",
    (tester) async {
      final hostKey = GlobalKey<State<_Host>>();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _Host(key: hostKey))),
      );
      await tester.pumpAndSettle();
      final host = hostKey.currentState! as _HostState;

      bool done1 = false;
      bool? result1;
      host.controller
          .animateScrollToKey(
            "a-target",
            scrollController: host.scrollController,
            duration: const Duration(milliseconds: 400),
            ancestorExpansion: AncestorExpansionMode.animated,
          )
          .then((v) {
        done1 = true;
        result1 = v;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(done1, isFalse,
          reason: "setup: scroll #1 must still be in flight");

      // Scroll #2 starts while #1 is mid-flight. Single-flight contract:
      // #2 supersedes #1, which must be torn down synchronously here —
      // NOT left as an orphan outside the teardown slot.
      bool done2 = false;
      bool? result2;
      host.controller
          .animateScrollToKey(
            "b-target",
            scrollController: host.scrollController,
            duration: const Duration(milliseconds: 400),
            ancestorExpansion: AncestorExpansionMode.animated,
          )
          .then((v) {
        done2 = true;
        result2 = v;
      });
      await tester.pump(const Duration(milliseconds: 16));

      // Unmount the host mid-flight. Its State.dispose() runs
      // controller.dispose() then super.dispose(), where
      // TickerProviderStateMixin asserts no created Ticker is still
      // active. On the unfixed tree, scroll #1's AnimationController was
      // pushed out of the single teardown slot by #2 and is still
      // ticking here — the assert fires and fails the test.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pump();

      expect(done1, isTrue,
          reason: "superseded scroll #1's future must resolve");
      expect(result1, isFalse,
          reason: "superseded scroll #1 was cancelled, not completed");
      expect(done2, isTrue,
          reason: "scroll #2's future must resolve on dispose "
              "(cancellation), not keep awaiting endOfFrame forever");
      expect(result2, isFalse,
          reason: "a dispose-cancelled scroll reports false");
    },
  );

  testWidgets(
    "a second animated scroll supersedes the first: #1 resolves false, "
    "#2 completes true and lands on ITS target (R2)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.easeInOut)),
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      controller.setRoots([
        for (int i = 0; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      // #1 targets a chain near the bottom, #2 a chain near the top, so
      // their final snap offsets differ.
      controller.setChildren("r19", [
        const TreeNode(key: "deep-mid", data: "M"),
      ]);
      controller.setChildren("deep-mid", [
        const TreeNode(key: "deep-target", data: "T"),
      ]);
      controller.setChildren("r5", [
        const TreeNode(key: "near-mid", data: "M"),
      ]);
      controller.setChildren("near-mid", [
        const TreeNode(key: "near-target", data: "T"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
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
        ),
      );
      await tester.pumpAndSettle();

      bool done1 = false;
      bool? result1;
      controller
          .animateScrollToKey(
            "deep-target",
            scrollController: scrollController,
            duration: const Duration(milliseconds: 300),
            ancestorExpansion: AncestorExpansionMode.animated,
          )
          .then((v) {
        done1 = true;
        result1 = v;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(done1, isFalse,
          reason: "setup: scroll #1 must still be in flight");

      bool done2 = false;
      bool? result2;
      controller
          .animateScrollToKey(
            "near-target",
            scrollController: scrollController,
            duration: const Duration(milliseconds: 300),
            ancestorExpansion: AncestorExpansionMode.animated,
          )
          .then((v) {
        done2 = true;
        result2 = v;
      });
      await tester.pumpAndSettle();

      expect(done1, isTrue);
      expect(
        result1,
        isFalse,
        reason: "the superseded scroll must resolve false (cancelled) — "
            "on the unfixed tree both scrolls run concurrently, fighting "
            "over jumpTo, and #1 resolves true",
      );
      expect(done2, isTrue);
      expect(result2, isTrue,
          reason: "the newer scroll wins and completes normally");

      final position = scrollController.position;
      final expected = controller
          .scrollOffsetOf("near-target")!
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      expect(
        position.pixels,
        closeTo(expected, 0.01),
        reason: "the final offset must be scroll #2's target",
      );
    },
  );
}
