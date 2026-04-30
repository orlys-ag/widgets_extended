/// Regression tests for capture / collapse / re-expand visual behavior:
///
///   1. A descendant captured into a parent's collapse op-group shrinks
///      visually together with the parent (subtree-subordinate visual).
///   2. After re-expand, the row reaches full extent without a replay
///      (no second growth animation after the parent finishes).
///   3. `setFullExtent` resize updates do NOT override a captured-source
///      member's `targetExtent` — required so freshly-inserted rows
///      caught at progress=0 don't suddenly read at full natural size
///      during the parent's collapse.
///   4. Standalone captures with `_unknownExtent` target compute the
///      visible extent from the proportional formula, not the stale
///      `currentExtent` cache.
///   5. `hasActiveAnimations` correctly tracks animation state so the
///      render layer keeps relayouting until extents settle.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  group("capture / collapse / re-expand visual regressions", () {
    testWidgets(
        "descendant mid-collapse follows parent's collapse visually, "
        "resumes its own collapse on parent re-expand", (tester) async {
      // Setup: P → C → c1, all expanded, c1 visible at full extent.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren("c", [const TreeNode(key: "c1", data: "c1")]);
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);
      controller.setFullExtent("c1", 48.0);
      expect(controller.getCurrentExtent("c1"), 48);

      // t=0: collapse C. c1 begins exiting via Gc.
      controller.collapse(key: "c", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      // t=50ms: 25% in, c1 ≈ 36.
      expect(controller.getCurrentExtent("c1"), closeTo(36, 4));

      // t=50ms: collapse P. c1 is captured into Gp; its visual
      // extent now follows Gp's collapse rather than its own
      // independent clock. c1's preserved clock is stashed as a
      // private record (paused).
      controller.collapse(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 49));

      // t=100ms: 50ms into Gp's 200ms collapse → Gp.value=0.75. c1's
      // visual extent = lerp(0, capturedExtent≈36, 0.75) ≈ 27 — NOT
      // c1's own-clock value of 24. The visible motion is the
      // parent-driven shrink, the same as today's behavior before the
      // per-node-record refactor.
      expect(
        controller.getCurrentExtent("c1"),
        closeTo(27, 4),
        reason: "While captured in Gp, c1's visual must follow Gp's "
            "collapse — NOT advance on its own preserved clock.",
      );

      // t=100ms: re-expand P. Path-1 reversal of Gp. c1 was in
      // pendingRemoval; that clears, and reads now resolve via the
      // group's rebased member envelope (and once the group disposes,
      // via c1's preserved private record).
      controller.expand(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));

      // First frame after re-expand: c1's extent must be effectively
      // unchanged (visual continuity at the boundary).
      final c1AfterReversal = controller.getCurrentExtent("c1");
      expect(
        c1AfterReversal,
        closeTo(27, 4),
        reason: "Re-expand must preserve visual position; got "
            "c1AfterReversal=$c1AfterReversal",
      );

      // Settle. After the parent's group completes, c1's private
      // record (which carried its own preserved exit clock) takes
      // over reads. The record's progress was rebased at re-expand
      // so its currentExtent matched the visual boundary, and it
      // continues toward 0 on its own remaining duration. After
      // pumpAndSettle c1 has finished its exit and was removed.
      await tester.pumpAndSettle();
      expect(
        controller.visibleNodes.toList(),
        equals(["p", "c"]),
        reason: "C is re-expanded (visible) but c1 finished its exit "
            "on its own preserved clock and was removed from order.",
      );
    });

    testWidgets(
        "descendant mid-expand follows parent's collapse visually, "
        "resumes its own enter on parent re-expand", (tester) async {
      // Setup: P → C → c1. P expanded, C collapsed, c1 not yet visible.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren("c", [const TreeNode(key: "c1", data: "c1")]);
      controller.expand(key: "p", animate: false);
      controller.setFullExtent("c1", 48.0);

      // t=0: expand C. c1 begins entering, 0 → 48 over 200ms linear.
      controller.expand(key: "c", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      // t=50ms: 25% in, c1 ≈ 12.
      expect(controller.getCurrentExtent("c1"), closeTo(12, 4));

      // t=50ms: collapse P. c1 captured into Gp's collapse. Its
      // visual now follows Gp's collapse, NOT its own enter clock.
      controller.collapse(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 49));

      // t=100ms: 50ms into Gp's 200ms collapse → Gp.value=0.75. c1's
      // captured extent at the moment of capture was ≈12, so c1 in
      // Gp has envelope (0, 12). lerp(0, 12, 0.75) = 9.
      expect(
        controller.getCurrentExtent("c1"),
        closeTo(9, 4),
        reason: "While captured in Gp, c1 visually shrinks together "
            "with the parent's collapse — not still entering.",
      );

      // t=100ms: re-expand P. Path-1 reversal. c1's preserved enter
      // record will take over once the group disposes.
      controller.expand(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      final c1AfterReversal = controller.getCurrentExtent("c1");
      expect(
        c1AfterReversal,
        closeTo(9, 4),
        reason: "Re-expand must preserve visual position.",
      );

      // Settle. The group's re-expand rebases c1's member envelope
      // toward full and runs over the configured duration. Once the
      // group completes and disposes, c1's preserved private record
      // takes over and continues toward full on its own clock.
      // Either path lands c1 at full extent eventually.
      await tester.pumpAndSettle();
      expect(controller.getCurrentExtent("c1"), 48);
      expect(controller.visibleNodes.toList(), equals(["p", "c", "c1"]));
    });

    testWidgets(
        "child entering while parent collapses: descendants reach 0 "
        "in lockstep with parent — no leftover rows visible after the "
        "parent's collapse finishes", (tester) async {
      // Regression for the visual bug reported as "child's nodes keep
      // showing even when the parent is fully collapsed, then get
      // removed in one frame." Under the new captured-clock semantic
      // a captured node's visual follows the parent's collapse, so by
      // the time the parent's controller dismisses, the descendant's
      // extent is already 0 — its removal from `_order` produces no
      // visible jump.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren("c", [
        const TreeNode(key: "c1", data: "c1"),
        const TreeNode(key: "c2", data: "c2"),
      ]);
      controller.expand(key: "p", animate: false);
      controller.setFullExtent("c1", 48.0);
      controller.setFullExtent("c2", 48.0);

      // Expand C — c1, c2 begin entering.
      controller.expand(key: "c", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 80));
      // Mid-flight: c1, c2 are partway through their enter.
      expect(controller.getCurrentExtent("c1"), greaterThan(0.0));
      expect(controller.getCurrentExtent("c1"), lessThan(48.0));

      // Collapse P. c1, c2 (and C) are captured into Gp; their visual
      // now follows Gp's collapse uniformly with the parent.
      controller.collapse(key: "p", animate: true);

      // Sample multiple frames during the collapse and assert the
      // descendants are NEVER above their captured-extent envelope —
      // they shrink monotonically toward 0 alongside the parent.
      double prevExtent = double.infinity;
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final c1Extent = controller.getCurrentExtent("c1");
        expect(
          c1Extent,
          lessThanOrEqualTo(prevExtent + 0.01),
          reason: "c1 must shrink monotonically while Gp collapses; "
              "frame $i: $c1Extent (was $prevExtent)",
        );
        prevExtent = c1Extent;
      }

      // After the parent's collapse fully completes, only P remains.
      // The descendants exit the visible order with extent already
      // at 0 — no one-frame snap.
      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p"]));
    });

    testWidgets(
        "inserted children + parent collapse: children shrink with "
        "parent, no jump to full extent", (tester) async {
      // Regression: user reported that inserting children, then
      // collapsing the parent above, made the inserted children
      // "skip their animation and show fully expanded." Children
      // mid-enter (standalone state) must follow the captured-clock
      // semantic — capture into the parent's collapse op-group with
      // the correct visual extent, then shrink to 0 with the parent.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      // Seed c with one existing child so expand(c) takes effect
      // (expand returns early when the node has no children).
      controller.setChildren(
        "c",
        [const TreeNode(key: "seed", data: "seed")],
      );
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);
      controller.setFullExtent("c", 48.0);
      controller.setFullExtent("seed", 48.0);

      // Now insert two new children of c. Because c is expanded these
      // go through the standalone enter animation path.
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c1", data: "c1"),
      );
      controller.setFullExtent("c1", 48.0);
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c2", data: "c2"),
      );
      controller.setFullExtent("c2", 48.0);

      // Pump partway; children mid-enter via standalone.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      final c1Before = controller.getCurrentExtent("c1");
      expect(c1Before, greaterThan(0.0));
      expect(c1Before, lessThan(48.0));

      // Collapse P. c1 must NOT jump to full — it must follow P's
      // collapse from its current visual extent down to 0.
      controller.collapse(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      final c1AfterStart = controller.getCurrentExtent("c1");
      expect(
        c1AfterStart,
        lessThanOrEqualTo(c1Before + 0.5),
        reason: "c1 must not jump up to full when P collapses; "
            "got $c1AfterStart, was $c1Before",
      );

      // Sweep the collapse animation; c1 must shrink monotonically
      // while it's still in the visible order. Once c1 leaves the
      // visible order (animation completed structurally), stop
      // sampling — `getCurrentExtent` falls through to fullExtent
      // for un-animated keys, which is correct for that off-order
      // state but not what we want to assert visually here.
      double prev = c1AfterStart;
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!controller.visibleNodes.contains("c1")) break;
        final extent = controller.getCurrentExtent("c1");
        expect(
          extent,
          lessThanOrEqualTo(prev + 0.01),
          reason: "c1 must shrink monotonically while P collapses; "
              "frame $i: $extent (prev $prev)",
        );
        prev = extent;
      }

      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p"]));
    });

    testWidgets(
        "example-app insertChildren flow: insert N + expand parent "
        "+ collapse grandparent mid-flight: children shrink with "
        "grandparent, never jump to full",
        (tester) async {
      // Mirrors examples/lib/concurrent_ops_example.dart's
      // _executeInsertChildren: insert several children under a
      // parent, then expand the parent if it isn't already. This
      // takes the Path-2-expand path (children animate via Gc).
      // Then collapse the grandparent mid-flight — the user's
      // reported scenario.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.expand(key: "p", animate: false);
      controller.setFullExtent("p", 48.0);
      controller.setFullExtent("c", 48.0);
      // c is NOT expanded yet (matches example: parent may be
      // collapsed when insertChildren runs).

      // Insert children. Parent c isn't expanded, so these are
      // structural-only; no animation yet.
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c1", data: "c1"),
      );
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c2", data: "c2"),
      );
      controller.setFullExtent("c1", 48.0);
      controller.setFullExtent("c2", 48.0);

      // Expand parent c. Children c1, c2 now enter via Gc.
      controller.expand(key: "c");
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      // Children mid-enter.
      final c1Mid = controller.getCurrentExtent("c1");
      expect(c1Mid, greaterThan(0.0));
      expect(c1Mid, lessThan(48.0));

      // Collapse grandparent p — captures c, c1, c2 from Gc into Gp.
      controller.collapse(key: "p", animate: true);

      // Sweep collapse frames; while c1 is in visible order, its
      // extent must shrink monotonically and never jump to full.
      await tester.pump(const Duration(milliseconds: 1));
      double prev = controller.getCurrentExtent("c1");
      expect(
        prev,
        lessThanOrEqualTo(c1Mid + 0.5),
        reason: "c1 must not jump up when grandparent collapses; "
            "got $prev, was $c1Mid",
      );
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!controller.visibleNodes.contains("c1")) break;
        final extent = controller.getCurrentExtent("c1");
        expect(
          extent,
          lessThanOrEqualTo(prev + 0.01),
          reason: "c1 must shrink monotonically while grandparent "
              "collapses; frame $i: $extent (prev $prev)",
        );
        // Also assert it never reaches the full extent (would
        // indicate the read fell through to no-animation full).
        expect(
          extent,
          lessThan(48.0),
          reason: "c1 must never read as full extent during the "
              "grandparent collapse; frame $i: $extent",
        );
        prev = extent;
      }

      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p"]));
    });

    testWidgets(
        "insert + immediate collapse (no pump): freshly-inserted "
        "children must still animate out with the parent's collapse",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren(
        "c",
        [const TreeNode(key: "seed", data: "seed")],
      );
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);
      controller.setFullExtent("c", 48.0);
      controller.setFullExtent("seed", 48.0);
      controller.setFullExtent("c1", 48.0);
      controller.setFullExtent("c2", 48.0);

      // Insert + immediately collapse with no pump in between.
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c1", data: "c1"),
      );
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c2", data: "c2"),
      );
      // Synchronous collapse — same call frame, no ticker has fired.
      controller.collapse(key: "p", animate: true);

      // Sweep frames. c1 was just inserted (standalone enter at
      // progress=0, currentExtent=0). After capture into Gp, its
      // member envelope should NOT make it visible at full extent.
      await tester.pump(const Duration(milliseconds: 1));
      double prev = double.infinity;
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!controller.visibleNodes.contains("c1")) break;
        final extent = controller.getCurrentExtent("c1");
        expect(
          extent,
          lessThan(48.0),
          reason: "c1 must never read as full extent during the "
              "grandparent collapse; frame $i: $extent",
        );
        expect(
          extent,
          lessThanOrEqualTo(prev + 0.01),
          reason: "c1 must shrink monotonically; frame $i: $extent "
              "(prev $prev)",
        );
        prev = extent;
      }

      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p"]));
    });

    testWidgets(
        "insert without pre-set full extent + collapse parent: "
        "freshly inserted children with unknown extent still follow "
        "the parent's collapse (no jump to default extent)",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren(
        "c",
        [const TreeNode(key: "seed", data: "seed")],
      );
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);
      controller.setFullExtent("c", 48.0);
      controller.setFullExtent("seed", 48.0);

      // Insert WITHOUT calling setFullExtent for the new children —
      // matches the example-app/renderer flow where the renderer
      // measures rows lazily via setFullExtent.
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c1", data: "c1"),
      );
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c2", data: "c2"),
      );

      // Pump partway.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      final c1Mid = controller.getCurrentExtent("c1");

      // Now collapse p.
      controller.collapse(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));

      final c1AfterStart = controller.getCurrentExtent("c1");
      expect(
        c1AfterStart,
        lessThanOrEqualTo(c1Mid + 0.5),
        reason: "c1 must not jump up when grandparent collapses; "
            "got $c1AfterStart, was $c1Mid",
      );

      // Sweep — c1 should not jump to default-extent during collapse.
      double prev = c1AfterStart;
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!controller.visibleNodes.contains("c1")) break;
        final extent = controller.getCurrentExtent("c1");
        expect(
          extent,
          lessThanOrEqualTo(prev + 0.01),
          reason: "frame $i: $extent (prev $prev)",
        );
        prev = extent;
      }

      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p"]));
    });

    testWidgets(
        "regression: insert + immediate parent collapse — "
        "freshly-inserted row must NOT jump to full extent during "
        "the parent's collapse",
        (tester) async {
      // Bug: when a child was inserted at progress=0 (entering
      // animation just started, target=_unknownExtent — renderer
      // hadn't measured yet), then the parent was collapsed in the
      // same frame, the captured visual extent was 0. The op-group
      // member.targetExtent got set to 0. Then setFullExtent — fired
      // by the renderer's measure pass — saw target=0 vs. measured
      // natural=48 and updated target to 48. The row read as 48
      // throughout the parent's collapse, manifesting as "children
      // appear all at once at full extent and then collapse smoothly."
      //
      // Fix: NodeGroupExtent.targetIsCaptured marks captured-source
      // members so setFullExtent leaves their target alone.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren(
        "c",
        [const TreeNode(key: "seed", data: "seed")],
      );
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (ctx, key, depth) {
                    return SizedBox(
                      key: ValueKey(key),
                      height: 48,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Insert + collapse synchronously (the rapid-click case).
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c1", data: "c1"),
      );
      controller.collapse(key: "p", animate: true);
      await tester.pump();

      // c1 must not be visible at full extent; the captured value
      // (~0) must survive setFullExtent's resize update.
      final c1Element = find.byKey(const ValueKey("c1"));
      if (c1Element.evaluate().isNotEmpty) {
        final renderBox =
            c1Element.evaluate().single.renderObject as RenderBox;
        final pd = renderBox.parentData! as SliverTreeParentData;
        expect(
          pd.visibleExtent,
          lessThan(2.0),
          reason: "c1's visibleExtent must stay near the captured "
              "value (~0) during the parent's collapse; got "
              "${pd.visibleExtent}",
        );
      }

      // Settle — only p remains.
      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p"]));
    });

    testWidgets(
        "rendered insert animation: row's painted height grows from "
        "0 to full over the configured duration",
        (tester) async {
      // Mounts a real SliverTree, inserts a child under a visible
      // expanded parent, and inspects the row's painted height
      // across frames. The painted height comes from the render
      // sliver's animated extent — exactly what the user sees.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren(
        "c",
        [const TreeNode(key: "seed", data: "seed")],
      );
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (ctx, key, depth) {
                    return SizedBox(
                      key: ValueKey(key),
                      height: 48,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      // Initial rows visible: p, c, seed.
      expect(find.byKey(const ValueKey("p")), findsOneWidget);
      expect(find.byKey(const ValueKey("seed")), findsOneWidget);

      // Insert c1.
      controller.insert(
        parentKey: "c",
        node: const TreeNode(key: "c1", data: "c1"),
      );
      // First frame after insert.
      await tester.pump();
      expect(find.byKey(const ValueKey("c1")), findsOneWidget);
      final initialExtent = controller.getCurrentExtent("c1");
      expect(
        initialExtent,
        lessThan(2.0),
        reason: "c1 must enter at ≈0 animated extent; got $initialExtent",
      );

      // Pump through the animation.
      await tester.pump(const Duration(milliseconds: 100));
      final midExtent = controller.getCurrentExtent("c1");
      expect(midExtent, greaterThan(initialExtent));
      expect(midExtent, lessThan(48.0));

      await tester.pumpAndSettle();
      expect(controller.getCurrentExtent("c1"), 48.0);
    });

    testWidgets(
        "insert N children at once + collapse parent: all children "
        "register their enter and follow the parent's collapse",
        (tester) async {
      // Mirrors the example app's _executeInsertChildren flow:
      // insert N at once into a parent (which may or may not be
      // expanded), expand parent if needed, then collapse the
      // grandparent.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.expand(key: "p", animate: false);
      // c starts as a leaf — matches the example app's "select node
      // with no children, click insertChildren" scenario.

      // Insert N children. `c` is a leaf (not expanded) so these are
      // structural-only.
      const childCount = 5;
      for (var i = 0; i < childCount; i++) {
        controller.insert(
          parentKey: "c",
          node: TreeNode(key: "c$i", data: "c$i"),
        );
      }
      // Now expand c. Path-2 expand kicks in.
      controller.expand(key: "c");

      // First post-expand frame, then pump 50ms — children should be
      // partway entering.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < childCount; i++) {
        final extent = controller.getCurrentExtent("c$i");
        expect(
          extent,
          lessThan(48.0),
          reason: "c$i must be mid-enter at t=51ms; got $extent",
        );
      }

      // Now collapse grandparent p mid-flight.
      controller.collapse(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));

      // Sweep collapse frames — children must shrink monotonically.
      double prev = 0.0;
      for (var i = 0; i < childCount; i++) {
        final v = controller.getCurrentExtent("c$i");
        if (v > prev) prev = v;
      }
      for (var f = 0; f < 20; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < childCount; i++) {
          final key = "c$i";
          if (!controller.visibleNodes.contains(key)) continue;
          final extent = controller.getCurrentExtent(key);
          expect(
            extent,
            lessThan(48.0),
            reason: "$key must not jump to full during the parent's "
                "collapse; frame $f: $extent",
          );
        }
      }

      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p"]));
    });

    testWidgets(
        "regression: insert children + collapse parent + re-expand "
        "parent — children must grow back to full extent, not stay "
        "stacked at 0",
        (tester) async {
      // Bug: after inserts + parent-collapse + re-expand, the
      // freshly-inserted children appear stacked at the same y
      // because their `targetExtent` stayed at the captured value 0
      // through the re-expand and Path-1's target=full update is
      // somehow being defeated.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren(
        "c",
        [const TreeNode(key: "seed", data: "seed")],
      );
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (ctx, key, depth) {
                    return SizedBox(
                      key: ValueKey(key),
                      height: 48,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Insert children of c.
      for (final id in ["c1", "c2", "c3"]) {
        controller.insert(
          parentKey: "c",
          node: TreeNode(key: id, data: id),
        );
      }
      // Collapse p (captures c, c1, c2, c3, seed).
      controller.collapse(key: "p", animate: true);
      // Pump partway through the collapse.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      // Re-expand p.
      controller.expand(key: "p", animate: true);
      // Pump partway through the re-expand.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      // Children must have non-trivial extent at this point and
      // distinct y positions (not all stacked at the same offset).
      for (final id in ["c1", "c2", "c3"]) {
        final element = find.byKey(ValueKey(id));
        if (element.evaluate().isEmpty) {
          fail("Row $id is missing from the rendered output");
        }
        final renderBox =
            element.evaluate().single.renderObject as RenderBox;
        final pd = renderBox.parentData! as SliverTreeParentData;
        expect(
          pd.visibleExtent,
          greaterThan(0.0),
          reason: "Row $id must have non-zero visibleExtent during "
              "re-expand; got ${pd.visibleExtent}",
        );
      }

      // Pump to completion — all children at full, distinct offsets.
      await tester.pumpAndSettle();
      double prevOffset = -1;
      for (final id in ["c", "seed", "c1", "c2", "c3"]) {
        final element = find.byKey(ValueKey(id));
        if (element.evaluate().isEmpty) continue;
        final renderBox =
            element.evaluate().single.renderObject as RenderBox;
        final pd = renderBox.parentData! as SliverTreeParentData;
        expect(
          pd.layoutOffset,
          greaterThan(prevOffset),
          reason: "Row $id must have a layoutOffset greater than the "
              "previous row; got ${pd.layoutOffset} (prev $prevOffset)",
        );
        prevOffset = pd.layoutOffset;
      }
    });

    testWidgets(
        "regression: c is a leaf, insert + expand(c) + collapse(p) "
        "+ expand(p) — c's children must lay out in distinct y "
        "positions, not stacked",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // c starts as a leaf (no children, not expanded).
      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.expand(key: "p", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (ctx, key, depth) {
                    return SizedBox(
                      key: ValueKey(key),
                      height: 48,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      // Initial: p, c visible.
      await tester.pump();

      // Insert children of c (parent is a leaf; structural only).
      for (final id in ["c1", "c2", "c3"]) {
        controller.insert(
          parentKey: "c",
          node: TreeNode(key: id, data: id),
        );
      }
      // Now expand c — Path-2 expand kicks in for c1, c2, c3.
      controller.expand(key: "c");
      await tester.pump(const Duration(milliseconds: 1));
      // Pump partway through c's expand.
      await tester.pump(const Duration(milliseconds: 80));

      // Collapse p mid-flight.
      controller.collapse(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 80));

      // Re-expand p. Track c1's painted extent across the whole
      // animation: after the re-expand completes, the row must NOT
      // visibly drop or replay (the record-resume bug).
      controller.expand(key: "p", animate: true);

      // Sample c1's visibleExtent until the re-expand reaches its
      // peak (close to full). Then settle and assert the post-settle
      // value never dips below the peak (no replay).
      double peakExtent = 0.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final element = find.byKey(const ValueKey("c1"));
        if (element.evaluate().isEmpty) continue;
        final renderBox =
            element.evaluate().single.renderObject as RenderBox;
        final pd = renderBox.parentData! as SliverTreeParentData;
        if (pd.visibleExtent > peakExtent) peakExtent = pd.visibleExtent;
        // Once we've climbed past 80% of full, we're past the
        // re-expand's peak; further frames must not drop below the
        // running peak (modulo a tiny tolerance for floating point).
        if (peakExtent > 38.0) {
          expect(
            pd.visibleExtent,
            greaterThanOrEqualTo(peakExtent - 0.5),
            reason: "Frame $i: c1.visibleExtent=${pd.visibleExtent} "
                "dropped below peak=$peakExtent — the captured-record "
                "replay regression returned.",
          );
        }
      }
      await tester.pumpAndSettle();

      // Probe: every visible row must have a strictly increasing
      // layoutOffset.
      double prevOffset = -1;
      double prevExtent = 0.0;
      for (final id in ["p", "c", "c1", "c2", "c3"]) {
        final element = find.byKey(ValueKey(id));
        if (element.evaluate().isEmpty) continue;
        final renderBox =
            element.evaluate().single.renderObject as RenderBox;
        final pd = renderBox.parentData! as SliverTreeParentData;
        expect(
          pd.layoutOffset,
          greaterThanOrEqualTo(prevOffset + prevExtent - 0.01),
          reason: "Row $id must lay out below prev row "
              "(prevOffset=$prevOffset, prevExtent=$prevExtent), "
              "got ${pd.layoutOffset}",
        );
        prevOffset = pd.layoutOffset;
        prevExtent = pd.visibleExtent;
      }

      // All children should be at full extent after settle.
      for (final id in ["c1", "c2", "c3"]) {
        final element = find.byKey(ValueKey(id));
        if (element.evaluate().isEmpty) continue;
        final renderBox =
            element.evaluate().single.renderObject as RenderBox;
        final pd = renderBox.parentData! as SliverTreeParentData;
        expect(
          pd.visibleExtent,
          48.0,
          reason: "Row $id must be at full extent after settle; "
              "got ${pd.visibleExtent}",
        );
      }
    });

    testWidgets(
        "synchronous parent collapse → expand round-trip preserves "
        "the captured descendant's visual continuity", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setChildren("c", [const TreeNode(key: "c1", data: "c1")]);
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c", animate: false);
      controller.setFullExtent("c1", 48.0);

      // t=0: collapse C. c1 starts exiting at 48 → 0 over 400ms.
      controller.collapse(key: "c", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      // t=100ms: 25% in, c1 ≈ 36.
      expect(controller.getCurrentExtent("c1"), closeTo(36, 4));

      // Round-trip: collapse P, then re-expand P, both with no
      // intervening pump — a fast user toggle.
      controller.collapse(key: "p", animate: true);
      controller.expand(key: "p", animate: true);
      await tester.pump(const Duration(milliseconds: 1));
      // c1's visual should stay near 36 across the round-trip — no
      // jump up or down.
      expect(controller.getCurrentExtent("c1"), closeTo(36, 4),
          reason: "Round-trip must not jolt visual position.");

      // Settle. C is still in collapsed state (collapse(C) at t=0
      // is still in effect; the P round-trip didn't change C's
      // expansion). c1 finishes its exit and disappears.
      await tester.pumpAndSettle();
      expect(controller.visibleNodes.toList(), equals(["p", "c"]));
    });
  });
}
