/// Tests for plan item T5: `SyncedSliverTree` forwards
/// `maxExpansionMemorySize` to its internal [TreeSyncController], so
/// callers can bound (or disable) the expansion memory that survives
/// remove/re-add cycles.
///
/// Every test here runs with `initiallyExpanded: false`, deliberately.
/// With the default `true`, the gained-first-children auto-expand
/// heuristic re-expands a re-added parent on its own (an empty
/// remembered-key set cannot suppress it), so a "not restored" assertion
/// would be observing the heuristic instead of expansion memory, and would
/// pass for the wrong reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Node {
  const _Node(this.id, {this.children = const <_Node>[]});

  final String id;
  final List<_Node> children;
}

const List<_Node> _withA = <_Node>[
  _Node("a", children: <_Node>[_Node("a1")]),
  _Node("b"),
];

const List<_Node> _withoutA = <_Node>[_Node("b")];

class _Harness extends StatelessWidget {
  const _Harness({
    required this.roots,
    required this.maxExpansionMemorySize,
    this.onControllerCreated,
  });

  final List<_Node> roots;
  final int maxExpansionMemorySize;
  final void Function(TreeController<String, _Node> controller)?
  onControllerCreated;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, _Node>.hierarchy(
              roots: roots,
              keyOf: (item) {
                return item.id;
              },
              childrenOf: (item) {
                return item.children;
              },
              initiallyExpanded: false,
              maxExpansionMemorySize: maxExpansionMemorySize,
              animationStyle: TreeAnimationStyle.disabled,
              onControllerCreated: onControllerCreated,
              itemBuilder: (context, node) {
                return SizedBox(height: 48, child: Text(node.key));
              },
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets("maxExpansionMemorySize: 0 disables expansion memory across a "
      "remove/re-add cycle", (tester) async {
    TreeController<String, _Node>? controller;

    await tester.pumpWidget(
      _Harness(
        roots: _withA,
        maxExpansionMemorySize: 0,
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller!.isExpanded("a"),
      isFalse,
      reason: "sanity: initiallyExpanded is false, so nothing starts open",
    );

    controller!.expand(key: "a", animate: false);
    await tester.pumpAndSettle();
    expect(
      find.text("a1"),
      findsOneWidget,
      reason: "sanity: the deliberate expansion took effect",
    );

    // Remove the expanded subtree, then bring it back.
    await tester.pumpWidget(
      const _Harness(roots: _withoutA, maxExpansionMemorySize: 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("a"),
      findsNothing,
      reason: "sanity: the sync removed the subtree",
    );

    await tester.pumpWidget(
      const _Harness(roots: _withA, maxExpansionMemorySize: 0),
    );
    await tester.pumpAndSettle();

    expect(
      controller!.isExpanded("a"),
      isFalse,
      reason: "with memory disabled the re-added node comes back collapsed",
    );
    expect(find.text("a1"), findsNothing);
  });

  testWidgets(
    "a nonzero maxExpansionMemorySize restores expansion across the same "
    "cycle",
    (tester) async {
      TreeController<String, _Node>? controller;

      // 1024 is the default; passed explicitly so this positive control
      // differs from the test above in exactly one value.
      await tester.pumpWidget(
        _Harness(
          roots: _withA,
          maxExpansionMemorySize: 1024,
          onControllerCreated: (c) {
            controller = c;
          },
        ),
      );
      await tester.pumpAndSettle();

      controller!.expand(key: "a", animate: false);
      await tester.pumpAndSettle();
      expect(find.text("a1"), findsOneWidget);

      await tester.pumpWidget(
        const _Harness(roots: _withoutA, maxExpansionMemorySize: 1024),
      );
      await tester.pumpAndSettle();
      expect(find.text("a"), findsNothing);

      await tester.pumpWidget(
        const _Harness(roots: _withA, maxExpansionMemorySize: 1024),
      );
      await tester.pumpAndSettle();

      expect(
        controller!.isExpanded("a"),
        isTrue,
        reason: "expansion memory must restore the user's expansion",
      );
      expect(find.text("a1"), findsOneWidget);
    },
  );

  testWidgets("changing maxExpansionMemorySize at runtime rebuilds the sync "
      "controller and drops what it had remembered", (tester) async {
    TreeController<String, _Node>? controller;

    await tester.pumpWidget(
      _Harness(
        roots: _withA,
        maxExpansionMemorySize: 1024,
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();

    controller!.expand(key: "a", animate: false);
    await tester.pumpAndSettle();
    expect(find.text("a1"), findsOneWidget);

    // Flip the bound to 0 on a later build: the sync controller is
    // recreated, so nothing is remembered from here on.
    await tester.pumpWidget(
      const _Harness(roots: _withA, maxExpansionMemorySize: 0),
    );
    await tester.pumpAndSettle();
    expect(
      controller!.isExpanded("a"),
      isTrue,
      reason:
          "sanity: recreating the sync controller must not disturb "
          "expansion that is currently live",
    );

    await tester.pumpWidget(
      const _Harness(roots: _withoutA, maxExpansionMemorySize: 0),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      const _Harness(roots: _withA, maxExpansionMemorySize: 0),
    );
    await tester.pumpAndSettle();

    expect(
      controller!.isExpanded("a"),
      isFalse,
      reason: "the new bound must govern the remove/re-add cycle",
    );
  });
}
