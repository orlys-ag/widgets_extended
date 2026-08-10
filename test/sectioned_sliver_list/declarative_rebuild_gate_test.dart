/// Pins the declarative [SectionedSliverList]'s rebuild identity gate.
///
/// Without it, every ancestor rebuild re-ran the full diff: `itemsOf` was
/// invoked for every section, materializing a `TreeNode` per item across
/// the whole dataset, only for the sync layer's exact-match early-out to
/// discard all of it. `SyncedSliverTree` has had this gate; this module
/// did not.
///
/// The gate keys on the `sections` instance ALONE. `itemsOf` is excluded
/// deliberately: it is near-universally an inline lambda, so including it
/// would make the gate miss on every rebuild.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("an identical sections instance skips the diff", (tester) async {
    var itemsOfCalls = 0;
    final sections = List<String>.generate(3, (i) => "s$i");
    final items = <String, List<String>>{
      for (final s in sections) s: List<String>.generate(4, (i) => "$s-i$i"),
    };

    Widget build() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: sections,
              itemsOf: (s) {
                itemsOfCalls++;
                return items[s]!;
              },
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              headerBuilder: (ctx, v) {
                return SizedBox(height: 40, child: Text(v.key));
              },
              itemBuilder: (ctx, v) {
                return SizedBox(height: 40, child: Text(v.key));
              },
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    // Setup sanity: the first sync really did run, so a zero below means
    // "skipped" rather than "never wired up".
    expect(itemsOfCalls, greaterThan(0));
    expect(find.text("s0-i0"), findsOneWidget);

    itemsOfCalls = 0;
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(
      itemsOfCalls,
      isZero,
      reason: "same `sections` instance must not re-diff",
    );
    // The list is still rendered from the controller, not torn down.
    expect(find.text("s0-i0"), findsOneWidget);
  });

  testWidgets("a new sections instance re-diffs", (tester) async {
    var itemsOfCalls = 0;
    var sections = <String>["a", "b"];
    final items = <String, List<String>>{
      "a": ["a1"],
      "b": ["b1"],
      "c": ["c1"],
    };

    Widget build() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: sections,
              itemsOf: (s) {
                itemsOfCalls++;
                return items[s]!;
              },
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              headerBuilder: (ctx, v) {
                return SizedBox(height: 40, child: Text(v.key));
              },
              itemBuilder: (ctx, v) {
                return SizedBox(height: 40, child: Text(v.key));
              },
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text("c1"), findsNothing);

    itemsOfCalls = 0;
    sections = <String>["a", "b", "c"];
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(itemsOfCalls, greaterThan(0));
    expect(find.text("c1"), findsOneWidget);
  });

  testWidgets("collapsible and hideEmptySections force a diff on their own", (
    tester,
  ) async {
    var itemsOfCalls = 0;
    // A stable instance throughout, so any re-diff is attributable to the
    // flag rather than to the collection.
    final sections = <String>["full", "empty"];
    final items = <String, List<String>>{
      "full": ["f1"],
      "empty": <String>[],
    };
    var hideEmpty = false;
    var collapsible = true;

    Widget build() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: sections,
              hideEmptySections: hideEmpty,
              collapsible: collapsible,
              initiallyExpanded: false,
              itemsOf: (s) {
                itemsOfCalls++;
                return items[s]!;
              },
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              headerBuilder: (ctx, v) {
                return SizedBox(height: 40, child: Text(v.key));
              },
              itemBuilder: (ctx, v) {
                return SizedBox(height: 40, child: Text(v.key));
              },
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text("empty"), findsOneWidget);

    // hideEmptySections must re-diff and drop the empty section.
    itemsOfCalls = 0;
    hideEmpty = true;
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(itemsOfCalls, greaterThan(0));
    expect(find.text("empty"), findsNothing);
    expect(find.text("full"), findsOneWidget);

    // collapsible: false must re-diff and force-expand, revealing the item
    // even though initiallyExpanded is false.
    expect(find.text("f1"), findsNothing);
    collapsible = false;
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text("f1"), findsOneWidget);
  });

  testWidgets("hideEmptySections evaluates itemsOf once per section", (
    tester,
  ) async {
    final calls = <String, int>{};
    final sections = List<String>.generate(3, (i) => "s$i");
    final items = <String, List<String>>{
      for (final s in sections) s: List<String>.generate(2, (i) => "$s-i$i"),
    };

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            SectionedSliverList<String, String, String>(
              sections: sections,
              hideEmptySections: true,
              itemsOf: (s) {
                calls[s] = (calls[s] ?? 0) + 1;
                return items[s]!;
              },
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
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
    await tester.pumpAndSettle();

    expect(calls.keys.toSet(), equals(sections.toSet()));
    final askedMoreThanOnce = <String, int>{
      for (final entry in calls.entries)
        if (entry.value != 1) entry.key: entry.value,
    };
    expect(
      askedMoreThanOnce,
      isEmpty,
      reason: "the emptiness filter and the diff must share one evaluation",
    );
  });
}
