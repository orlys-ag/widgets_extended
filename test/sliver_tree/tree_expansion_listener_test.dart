/// Tests for plan item T4: `TreeController`'s expansion-listener channel.
///
/// The channel reports expansion changes made through the expansion
/// mutators, and nothing else. Two parts of the contract carry most of the
/// risk and are pinned hardest here:
///
///   - `collapseAll` must report EVERY node it flipped, not just the roots
///     it walked. It clears flags through the store's bulk registry clear,
///     which zeroes every in-depth flag including interior nodes and
///     expansion recorded under collapsed ancestors. A consumer persisting
///     expansion state would otherwise keep those nodes marked expanded.
///   - Node lifecycle (setRoots / setChildren / insert / remove) resets
///     flags SILENTLY. A persistence consumer's remembered entry for a
///     removed node has to survive the removal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

typedef _Event = (String key, bool isExpanded);

/// Builds a controller with two 3-level branches: r1 > c1 > g1 and
/// r2 > c2 > g2. Both interior nodes have children, so both can hold a
/// real expansion flag; only the leaves cannot.
TreeController<String, String> _buildController(TickerProvider vsync) {
  final controller = TreeController<String, String>(
    vsync: vsync,
    animationStyle: TreeAnimationStyle.disabled,
  );
  controller.setRoots(const [
    TreeNode(key: "r1", data: "R1"),
    TreeNode(key: "r2", data: "R2"),
  ]);
  controller.setChildren("r1", const [TreeNode(key: "c1", data: "C1")]);
  controller.setChildren("c1", const [TreeNode(key: "g1", data: "G1")]);
  controller.setChildren("r2", const [TreeNode(key: "c2", data: "C2")]);
  controller.setChildren("c2", const [TreeNode(key: "g2", data: "G2")]);
  return controller;
}

void main() {
  testWidgets("expand, collapse and toggle report the key and its new state", (
    tester,
  ) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);
    final events = <_Event>[];
    controller.addExpansionListener((key, isExpanded) {
      events.add((key, isExpanded));
    });

    controller.expand(key: "r1", animate: false);
    expect(events, [("r1", true)]);

    controller.collapse(key: "r1", animate: false);
    expect(events, [("r1", true), ("r1", false)]);

    events.clear();
    controller.toggle(key: "r1", animate: false);
    controller.toggle(key: "r1", animate: false);
    expect(events, [("r1", true), ("r1", false)]);
  });

  testWidgets("no event for a no-op expand or collapse", (tester) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);
    final events = <_Event>[];
    controller.addExpansionListener((key, isExpanded) {
      events.add((key, isExpanded));
    });

    // Already collapsed.
    controller.collapse(key: "r1", animate: false);
    expect(events, isEmpty);

    controller.expand(key: "r1", animate: false);
    events.clear();

    // Already expanded.
    controller.expand(key: "r1", animate: false);
    expect(events, isEmpty);

    // Childless: expand() cannot record a flag for it at all.
    controller.expand(key: "g1", animate: false);
    expect(events, isEmpty);
  });

  testWidgets(
    "expansion recorded while ancestors are collapsed still reports",
    (tester) async {
      final controller = _buildController(tester);
      addTearDown(controller.dispose);
      final events = <_Event>[];
      controller.addExpansionListener((key, isExpanded) {
        events.add((key, isExpanded));
      });

      // r1 stays collapsed, so c1 is not visible; its flag is still recorded
      // and the change is still a real expansion change.
      controller.expand(key: "c1", animate: false);
      expect(controller.isExpanded("c1"), isTrue);
      expect(
        controller.isVisible("c1"),
        isFalse,
        reason: "sanity: still hidden",
      );
      expect(events, [("c1", true)]);
    },
  );

  testWidgets("expandAll reports every node it flipped, and only those", (
    tester,
  ) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);
    controller.expand(key: "r1", animate: false);

    final events = <_Event>[];
    controller.addExpansionListener((key, isExpanded) {
      events.add((key, isExpanded));
    });

    controller.expandAll(animate: false);

    // r1 was already expanded, so it must NOT appear. c1, r2 and c2 have
    // children and flip; g1 and g2 are leaves and hold no expansion flag.
    expect(events.map((e) => e.$1).toSet(), <String>{"c1", "r2", "c2"});
    expect(events.every((e) => e.$2), isTrue);
  });

  testWidgets(
    "collapseAll reports interior nodes and hidden recorded expansion, not "
    "just the roots it walked",
    (tester) async {
      final controller = _buildController(tester);
      addTearDown(controller.dispose);

      // Target state: r1 expanded with c1 expanded under it (an INTERIOR
      // flag), and r2 collapsed while c2 stays expanded beneath it (a
      // HIDDEN recorded flag). Walking expanded roots sees only {r1}; the
      // true flip set is {r1, c1, c2}.
      controller.expandAll(animate: false);
      controller.collapse(key: "r2", animate: false);
      expect(controller.isExpanded("r1"), isTrue);
      expect(controller.isExpanded("c1"), isTrue, reason: "sanity: interior");
      expect(controller.isExpanded("r2"), isFalse);
      expect(
        controller.isExpanded("c2"),
        isTrue,
        reason: "sanity: c2 keeps its flag while its ancestor is collapsed",
      );
      expect(controller.isVisible("c2"), isFalse, reason: "sanity: hidden");

      final events = <_Event>[];
      controller.addExpansionListener((key, isExpanded) {
        events.add((key, isExpanded));
      });

      controller.collapseAll(animate: false);

      expect(
        events.map((e) => e.$1).toSet(),
        <String>{"r1", "c1", "c2"},
        reason:
            "every flag the bulk clear actually cleared must be reported, "
            "not just the expanded roots the mutator walked",
      );
      expect(events.every((e) => !e.$2), isTrue);
    },
  );

  testWidgets("collapseAll reports through its nothing-visible branch too", (
    tester,
  ) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);

    // An expanded root whose children were all removed afterwards: the
    // flag survives, but there is nothing visible left to hide, so
    // collapseAll takes its early branch.
    controller.expand(key: "r1", animate: false);
    controller.remove(key: "c1", animate: false);
    expect(controller.isExpanded("r1"), isTrue, reason: "sanity: flag stands");
    expect(controller.hasChildren("r1"), isFalse, reason: "sanity: emptied");

    final events = <_Event>[];
    controller.addExpansionListener((key, isExpanded) {
      events.add((key, isExpanded));
    });

    controller.collapseAll(animate: false);
    expect(events, [("r1", false)]);
  });

  testWidgets("collapseAll fires nothing when it clears nothing (documents a "
      "pre-existing early-out)", (tester) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);

    // Expansion recorded ONLY under collapsed roots.
    controller.expand(key: "c1", animate: false);
    expect(controller.isVisible("c1"), isFalse, reason: "sanity: hidden");

    final events = <_Event>[];
    controller.addExpansionListener((key, isExpanded) {
      events.add((key, isExpanded));
    });

    controller.collapseAll(animate: false);

    // Pre-existing behavior, independent of this channel: collapseAll
    // collects its work by walking expanded ROOTS, so with none expanded
    // it returns before touching the registry and c1 keeps its flag.
    // The channel's contract holds either way: it reports exactly what
    // flipped, and here nothing did. If that early-out is ever changed,
    // both expectations below move together.
    expect(controller.isExpanded("c1"), isTrue);
    expect(events, isEmpty);
  });

  testWidgets("node lifecycle changes expansion flags silently", (
    tester,
  ) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);
    controller.expand(key: "r1", animate: false);

    final events = <_Event>[];
    controller.addExpansionListener((key, isExpanded) {
      events.add((key, isExpanded));
    });

    // Removing an expanded node resets its flag: teardown, not a change.
    controller.remove(key: "r1", animate: false);
    expect(controller.getNodeData("r1"), isNull, reason: "sanity: purged");
    expect(events, isEmpty);

    // Inserting nodes initializes flags to collapsed: initialization.
    controller.insertRoot(const TreeNode(key: "r3", data: "R3"));
    controller.setChildren("r3", const [TreeNode(key: "c3", data: "C3")]);
    expect(events, isEmpty);

    // Replacing the whole tree likewise.
    controller.setRoots(const [TreeNode(key: "z", data: "Z")]);
    expect(events, isEmpty);
  });

  testWidgets("runBatch coalesces per key and drops net-unchanged sequences", (
    tester,
  ) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);
    final events = <_Event>[];
    controller.addExpansionListener((key, isExpanded) {
      events.add((key, isExpanded));
    });

    // Net-unchanged: expand then collapse the same key.
    controller.runBatch(() {
      controller.expand(key: "r1", animate: false);
      controller.collapse(key: "r1", animate: false);
      expect(events, isEmpty, reason: "sanity: nothing fires mid-batch");
    });
    expect(events, isEmpty);

    // Net change, reported once at exit with the final state.
    controller.runBatch(() {
      controller.expand(key: "r1", animate: false);
      controller.collapse(key: "r1", animate: false);
      controller.expand(key: "r1", animate: false);
    });
    expect(events, [("r1", true)]);

    // A node expanded and then removed inside one batch reports nothing.
    events.clear();
    controller.runBatch(() {
      controller.expand(key: "r2", animate: false);
      controller.remove(key: "r2", animate: false);
    });
    expect(events, isEmpty);
  });

  testWidgets("listeners see settled state and may remove themselves", (
    tester,
  ) async {
    final controller = _buildController(tester);
    addTearDown(controller.dispose);

    List<String>? visibleAtEvent;
    bool? expandedAtEvent;
    int calls = 0;
    late void Function(String, bool) listener;
    listener = (key, isExpanded) {
      calls++;
      visibleAtEvent = controller.visibleNodes;
      expandedAtEvent = controller.isExpanded(key);
      controller.removeExpansionListener(listener);
    };
    controller.addExpansionListener(listener);

    controller.expand(key: "r1", animate: false);

    expect(calls, 1);
    expect(
      expandedAtEvent,
      isTrue,
      reason: "the mutation must be complete when the callback runs",
    );
    expect(
      visibleAtEvent,
      ["r1", "c1", "r2"],
      reason: "the visible order must be rebuilt before the callback runs",
    );

    // The self-removal took effect: no further events.
    controller.collapse(key: "r1", animate: false);
    expect(calls, 1);
  });
}
