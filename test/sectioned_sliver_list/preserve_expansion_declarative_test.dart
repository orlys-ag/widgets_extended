/// Regression test for issue 5 of the 2026-08-21 review: the declarative
/// [SectionedSliverList] ignored `preserveExpansion` entirely.
///
/// `_runSync` snapshots the live section keys, calls `setSections` (which
/// restores remembered expansion through [TreeSyncController]), and then
/// runs `_applyInitialExpansion` over every desired section that was not
/// in that snapshot. A re-added section is never in it, so the initial
/// policy overwrote the memory restore in BOTH directions: a section the
/// user collapsed came back expanded under `initiallyExpanded: true`, and
/// one the user expanded came back collapsed under `false`.
///
/// [SyncedSliverTree] solves the same problem by snapshotting the
/// remembered key set BEFORE its sync and skipping those keys in its
/// post-sync passes; this brings the sectioned widget in line with it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  for (final initiallyExpanded in [true, false]) {
    testWidgets("a user's toggle survives a remove and re-add "
        "(initiallyExpanded: $initiallyExpanded)", (tester) async {
      var sections = <String>["a", "b"];
      final items = <String, List<String>>{
        "a": ["a1"],
        "b": ["b1"],
      };
      SectionedListController<String, String, String>? controller;

      Widget build() {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(
            slivers: [
              SectionedSliverList<String, String, String>(
                sections: sections,
                itemsOf: (s) => items[s]!,
                sectionKeyOf: (s) => s,
                itemKeyOf: (i) => i,
                initiallyExpanded: initiallyExpanded,
                preserveExpansion: true,
                animationStyle: TreeAnimationStyle.disabled,
                headerBuilder: (context, view) {
                  controller = view.controller;
                  return GestureDetector(
                    onTap: () => view.toggle(animate: false),
                    child: SizedBox(height: 40, child: Text("H-${view.key}")),
                  );
                },
                itemBuilder: (context, view) {
                  return SizedBox(height: 40, child: Text(view.key));
                },
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(
        controller!.isExpanded("a"),
        initiallyExpanded,
        reason: "setup: the initial policy applies to a brand-new section",
      );

      // The user moves "a" AWAY from the initial policy.
      await tester.tap(find.text("H-a"));
      await tester.pumpAndSettle();
      expect(controller!.isExpanded("a"), !initiallyExpanded);

      // "a" leaves the props (a filter, a search, a server update) and
      // comes back.
      sections = ["b"];
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(controller!.hasSection("a"), isFalse);
      expect(
        controller!.rememberedSectionKeys(),
        contains("a"),
        reason: "setup: the removal recorded the user's state",
      );

      sections = ["a", "b"];
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(
        controller!.isExpanded("a"),
        !initiallyExpanded,
        reason: "expansion memory must win over the initial-expansion "
            "policy for a section that is being re-added",
      );
    });
  }

  testWidgets("with preserveExpansion off, the initial policy wins on "
      "re-add", (tester) async {
    // Control: turning the memory off restores the old behavior, so the
    // fix is scoped to callers who asked for preservation.
    var sections = <String>["a", "b"];
    final items = <String, List<String>>{
      "a": ["a1"],
      "b": ["b1"],
    };
    SectionedListController<String, String, String>? controller;

    Widget build() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: sections,
              itemsOf: (s) => items[s]!,
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              initiallyExpanded: true,
              preserveExpansion: false,
              animationStyle: TreeAnimationStyle.disabled,
              headerBuilder: (context, view) {
                controller = view.controller;
                return GestureDetector(
                  onTap: () => view.toggle(animate: false),
                  child: SizedBox(height: 40, child: Text("H-${view.key}")),
                );
              },
              itemBuilder: (context, view) {
                return SizedBox(height: 40, child: Text(view.key));
              },
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text("H-a"));
    await tester.pumpAndSettle();
    expect(controller!.isExpanded("a"), isFalse);

    sections = ["b"];
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    sections = ["a", "b"];
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(
      controller!.isExpanded("a"),
      isTrue,
      reason: "no memory kept, so the initial policy applies as before",
    );
  });

  testWidgets("a section that empties while collapsed and is refilled "
      "stays collapsed", (tester) async {
    // The `hideEmptySections` route into the same defect, and a second
    // memory source: a section that empties while collapsed is recorded
    // in the sync layer's emptied-while-collapsed set rather than in the
    // expansion map, and `rememberedSectionKeys` unions both. Verified
    // while auditing this fix (2026-08-21).
    final items = <String, List<String>>{
      "a": ["a1"],
      "b": ["b1"],
    };
    var sections = <String>["a", "b"];
    SectionedListController<String, String, String>? controller;

    Widget build() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: sections,
              itemsOf: (s) => items[s]!,
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              initiallyExpanded: true,
              preserveExpansion: true,
              hideEmptySections: true,
              animationStyle: TreeAnimationStyle.disabled,
              headerBuilder: (context, view) {
                controller = view.controller;
                return SizedBox(height: 40, child: Text("H-${view.key}"));
              },
              itemBuilder: (context, view) {
                return SizedBox(height: 40, child: Text(view.key));
              },
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    controller!.collapseSection("a", animate: false);
    await tester.pumpAndSettle();

    // Empty it: `hideEmptySections` drops it from the tree. A new
    // `sections` instance is what signals an items-only change (the
    // documented identity gate).
    items["a"] = <String>[];
    sections = <String>["a", "b"];
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(controller!.hasSection("a"), isFalse);
    expect(controller!.rememberedSectionKeys(), contains("a"));

    items["a"] = <String>["a1"];
    sections = <String>["a", "b"];
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(controller!.hasSection("a"), isTrue);
    expect(
      controller!.isExpanded("a"),
      isFalse,
      reason: "refilling must not re-open a section the user collapsed",
    );
  });

  testWidgets("an existing section keeps its state across an unrelated "
      "sync", (tester) async {
    // Control: the pre-existing `knownSections` skip must still hold, so
    // a section that never left is not re-policied when its siblings
    // change.
    var sections = <String>["a", "b"];
    final items = <String, List<String>>{
      "a": ["a1"],
      "b": ["b1"],
      "c": ["c1"],
    };
    SectionedListController<String, String, String>? controller;

    Widget build() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: sections,
              itemsOf: (s) => items[s]!,
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              initiallyExpanded: true,
              preserveExpansion: true,
              animationStyle: TreeAnimationStyle.disabled,
              headerBuilder: (context, view) {
                controller = view.controller;
                return SizedBox(height: 40, child: Text("H-${view.key}"));
              },
              itemBuilder: (context, view) {
                return SizedBox(height: 40, child: Text(view.key));
              },
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    controller!.collapseSection("a", animate: false);
    await tester.pumpAndSettle();

    sections = ["a", "b", "c"];
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(controller!.isExpanded("a"), isFalse);
    expect(controller!.isExpanded("c"), isTrue);
  });
}
