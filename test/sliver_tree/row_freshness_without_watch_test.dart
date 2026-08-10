/// Rows that read `TreeItemView` properties DIRECTLY must stay fresh.
///
/// This is the evidence that retired the old `TreeItemView.watch` wrapper
/// (plan item T7): the sliver tree's element already does dirty-key
/// targeted rebuilds on both notification channels, and every mutator
/// names the keys whose rendered inputs changed, so a row reading
/// `isExpanded` / `hasChildren` / `item` inline re-renders on its own and
/// the wrapper bought nothing. Keep these passing: they are what makes
/// inline reads the supported pattern.
///
/// Each row renders its own state as text, so the assertions are on what a
/// user would actually see, not on builder call counts.
///
/// The riskiest case has its own test: losing the LAST child through an
/// animated removal. That happens in two stages. While the child is
/// exiting, the parent's `hasChildren` stays true (the raw child list
/// still holds the departing child, which is what the painted rows show),
/// and only at purge does it flip to false. Purge-time notifications use
/// the empty affected-set convention, so the parent's rebuild at that
/// second stage is the part that could plausibly be missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'tree_input_helpers.dart';

/// Everything a row can read inline, rendered as one string.
String _describe(TreeItemView<String, String> node) {
  return "${node.key}|${node.item}|kids=${node.hasChildren}"
      "|exp=${node.isExpanded}";
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.onControllerCreated,
    this.animationStyle = TreeAnimationStyle.disabled,
  });

  final void Function(TreeController<String, String> controller)
  onControllerCreated;
  final TreeAnimationStyle animationStyle;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, String>(
              tree: _fixture,
              animationStyle: animationStyle,
              onControllerCreated: onControllerCreated,
              itemBuilder: (context, node) {
                // Deliberately NO watch(): direct property reads only.
                return SizedBox(height: 48, child: Text(_describe(node)));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tree: "a" with one child "a1", plus a childless "b". Hoisted so every
/// rebuild passes the same instance (the identity rebuild gate must hold
/// across pumps, or a re-diff would revert the controller-driven
/// mutations these tests make).
final List<SyncedTreeNode<String, String>> _fixture = treeFrom(
  roots: const ["a", "b"],
  dataByKey: const {"a": "A", "a1": "A1", "b": "B"},
  childrenByParent: const {
    "a": ["a1"],
  },
);

void main() {
  testWidgets("a row tracks its own expand and collapse without watch", (
    tester,
  ) async {
    late TreeController<String, String> controller;
    await tester.pumpWidget(
      _Harness(
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("a|A|kids=true|exp=true"), findsOneWidget);

    controller.collapse(key: "a", animate: false);
    await tester.pumpAndSettle();
    expect(find.text("a|A|kids=true|exp=false"), findsOneWidget);

    controller.expand(key: "a", animate: false);
    await tester.pumpAndSettle();
    expect(find.text("a|A|kids=true|exp=true"), findsOneWidget);
  });

  testWidgets("a row tracks its own payload update without watch", (
    tester,
  ) async {
    late TreeController<String, String> controller;
    await tester.pumpWidget(
      _Harness(
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("a|A|kids=true|exp=true"), findsOneWidget);

    controller.updateNode(const TreeNode(key: "a", data: "A-EDITED"));
    await tester.pumpAndSettle();

    expect(find.text("a|A-EDITED|kids=true|exp=true"), findsOneWidget);
  });

  testWidgets("a row tracks gaining its first child without watch", (
    tester,
  ) async {
    late TreeController<String, String> controller;
    await tester.pumpWidget(
      _Harness(
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("b|B|kids=false|exp=false"),
      findsOneWidget,
      reason: "sanity: b starts childless",
    );

    controller.setChildren("b", const [TreeNode(key: "b1", data: "B1")]);
    await tester.pumpAndSettle();

    expect(find.text("b|B|kids=true|exp=false"), findsOneWidget);
  });

  testWidgets(
    "a row tracks losing its last child across BOTH stages of an animated "
    "removal, without watch",
    (tester) async {
      late TreeController<String, String> controller;
      await tester.pumpWidget(
        _Harness(
          onControllerCreated: (c) {
            controller = c;
          },
          animationStyle: const TreeAnimationStyle(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("a|A|kids=true|exp=true"), findsOneWidget);

      controller.remove(key: "a1", animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Stage 1: still exiting. The departing row is still painted, so the
      // parent reporting kids=true is CORRECT, not stale.
      expect(
        controller.isExiting("a1"),
        isTrue,
        reason: "sanity: the removal is mid-exit at this point",
      );
      expect(find.text("a|A|kids=true|exp=true"), findsOneWidget);

      // Stage 2: purged. hasChildren flips, and the parent row must
      // re-render to match.
      await tester.pumpAndSettle();
      expect(
        controller.getNodeData("a1"),
        isNull,
        reason: "sanity: the child is fully purged",
      );
      expect(
        controller.hasChildren("a"),
        isFalse,
        reason: "sanity: the controller itself reports no children",
      );
      expect(
        find.text("a|A|kids=false|exp=true"),
        findsOneWidget,
        reason: "the parent row must re-render once the purge lands",
      );
    },
  );
}
