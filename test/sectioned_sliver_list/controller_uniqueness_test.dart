/// Regression tests for issue 11 of the 2026-08-21 review: the sectioned
/// controller's "item keys are globally unique" rule was enforced on one
/// input path only, and one mutator was not atomic.
///
/// `setSections` rejects duplicates through the sync layer. Every other
/// entry point delegated straight to a tree mutator with different
/// semantics: `addItem` and `setItems` reach `insert` / `syncChildren`,
/// which MOVE an existing key, so an item silently left the section that
/// owned it; `addSection(items:)` ran `insertRoot` before `setChildren`
/// inside one `runBatch`, and `setChildren`'s duplicate rejection left
/// the empty section behind (with a message naming the internal
/// `SectionKey` / `ItemKey` wrappers); and `moveItem` refused a
/// pending-deletion item on its in-section path while its cross-section
/// path resurrected one.
///
/// Validation now happens at the sectioned boundary, before any tree
/// mutation, in section/item vocabulary. Two carve-outs are deliberate
/// and are pinned below: an item that is mid-EXIT in its own section is
/// still re-addable (that is `insert`'s cancel-deletion path), and a live
/// item re-added to its own section is still an in-section upsert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

SectionedListController<String, String, String> _make(
  WidgetTester tester, {
  TreeAnimationStyle style = TreeAnimationStyle.disabled,
}) {
  final controller = SectionedListController<String, String, String>(
    vsync: tester,
    sectionKeyOf: (s) => s,
    itemKeyOf: (i) => i,
    animationStyle: style,
  );
  controller.setSections(
    ["a", "b"],
    itemsOf: (s) => s == "a" ? ["a1", "a2"] : ["b1"],
  );
  return controller;
}

void main() {
  testWidgets("addSection is atomic and speaks section/item", (tester) async {
    final controller = _make(tester);
    addTearDown(controller.dispose);

    expect(
      () => controller.addSection("c", items: ["a1"]),
      throwsArgumentError,
      reason: "a1 belongs to section a",
    );
    expect(
      controller.sectionKeys(),
      ["a", "b"],
      reason: "the rejected call must not leave an empty section behind",
    );
    expect(controller.itemKeysOf("a"), ["a1", "a2"]);

    expect(
      () => controller.addSection("a", items: ["x"]),
      throwsArgumentError,
      reason: "section a already exists; use setItems/updateSection",
    );
    expect(
      controller.itemKeysOf("a"),
      ["a1", "a2"],
      reason: "and it must not have replaced a's items on the way out",
    );
  });

  testWidgets("addItem and setItems reject a key owned by another section", (
    tester,
  ) async {
    final controller = _make(tester);
    addTearDown(controller.dispose);

    expect(
      () => controller.addItem("a1", toSection: "b"),
      throwsArgumentError,
      reason: "this used to MOVE a1 out of section a with no error",
    );
    expect(controller.itemKeysOf("a"), ["a1", "a2"]);
    expect(controller.itemKeysOf("b"), ["b1"]);

    expect(
      () => controller.setItems("b", ["b1", "a1"]),
      throwsArgumentError,
      reason: "syncChildren would have reparented a1",
    );
    expect(controller.itemKeysOf("a"), ["a1", "a2"]);
    expect(controller.itemKeysOf("b"), ["b1"]);

    // In-section re-send is untouched: same keys, new order.
    controller.setItems("a", ["a2", "a1"]);
    expect(controller.itemKeysOf("a"), ["a2", "a1"]);
  });

  testWidgets("addItem still re-adds an item that is mid-exit in its own "
      "section", (tester) async {
    // Carve-out: `insert`'s cancel-deletion path. A bare "does this key
    // exist" guard would have broken it, because an exiting item's data
    // is still present.
    final controller = _make(tester, style: const TreeAnimationStyle());
    addTearDown(controller.dispose);
    controller.expandAll(animate: false);
    await tester.pump();

    controller.removeItem("a1", animate: true);
    await tester.pump(const Duration(milliseconds: 50));

    controller.addItem("a1", toSection: "a", index: 0);
    await tester.pumpAndSettle();
    expect(controller.itemKeysOf("a"), ["a1", "a2"]);
  });

  testWidgets("moveItem refuses a removing item on BOTH paths", (
    tester,
  ) async {
    final controller = _make(tester, style: const TreeAnimationStyle());
    addTearDown(controller.dispose);
    controller.expandAll(animate: false);
    await tester.pump();

    controller.removeItem("a1", animate: true);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      () => controller.moveItem("a1", index: 1),
      throwsAssertionError,
      reason: "in-section path already refused",
    );
    expect(
      () => controller.moveItem("a1", toSection: "b"),
      throwsAssertionError,
      reason: "the cross-section path used to resurrect it instead",
    );
    await tester.pumpAndSettle();
    expect(controller.hasItem("a1"), isFalse);
  });

  testWidgets("moveItem to its own section with no index appends", (
    tester,
  ) async {
    final controller = _make(tester);
    addTearDown(controller.dispose);

    controller.moveItem("a1", toSection: "a");
    expect(
      controller.itemKeysOf("a"),
      ["a2", "a1"],
      reason: "documented as appended; it used to be a silent no-op",
    );

    // Idempotent: already last.
    controller.moveItem("a1", toSection: "a");
    expect(controller.itemKeysOf("a"), ["a2", "a1"]);
  });

  testWidgets("addSection still re-adds a section that is mid-exit", (
    tester,
  ) async {
    // Carve-out: the documented re-include path, where addSection on a
    // pending-deletion key cancels the deletion through insertRoot.
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 100),
          curve: Curves.easeInOut,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.setSections(["a", "b"], itemsOf: (_) => const []);
    controller.setSections(["a"], itemsOf: (_) => const []);
    await tester.pump(const Duration(milliseconds: 16));

    controller.addSection("b");
    await tester.pumpAndSettle();
    expect(controller.hasSection("b"), isTrue);
  });
}
