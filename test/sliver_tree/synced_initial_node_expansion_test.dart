/// Tests for plan items T3 and T4 at the widget layer:
/// `SyncedSliverTree.initialNodeExpansion` (a per-node initial-expansion
/// policy, replacing the all-or-nothing `initiallyExpanded` bool) and
/// `SyncedSliverTree.onExpansionChanged` (the widget's view of the
/// controller's expansion channel).
///
/// The policy is an INITIAL policy in the strict sense: it decides a
/// node's state when the node first appears, and never overrides state the
/// node already has. Two consequences get their own tests, because they
/// are where a naive implementation goes wrong: nodes that arrive in a
/// LATER sync must still get the policy, and a node whose expansion was
/// remembered across a remove/re-add cycle must come back with the
/// remembered state even when the policy disagrees.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Node {
  const _Node(this.id, {this.children = const <_Node>[]});

  final String id;
  final List<_Node> children;
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.roots,
    this.initiallyExpanded = true,
    this.initialNodeExpansion,
    this.onControllerCreated,
    this.onExpansionChanged,
  });

  final List<_Node> roots;
  final bool initiallyExpanded;
  final bool? Function(String key, _Node item)? initialNodeExpansion;
  final void Function(TreeController<String, _Node> controller)?
  onControllerCreated;
  final void Function(String key, bool isExpanded)? onExpansionChanged;

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
              initiallyExpanded: initiallyExpanded,
              initialNodeExpansion: initialNodeExpansion,
              animationStyle: TreeAnimationStyle.disabled,
              onControllerCreated: onControllerCreated,
              onExpansionChanged: onExpansionChanged,
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

const List<_Node> _twoBranches = <_Node>[
  _Node("a", children: <_Node>[_Node("a1")]),
  _Node("b", children: <_Node>[_Node("b1")]),
];

void main() {
  testWidgets("the per-node policy decides expansion on the first sync", (
    tester,
  ) async {
    await tester.pumpWidget(
      _Harness(
        roots: _twoBranches,
        initialNodeExpansion: (key, item) {
          return key == "a";
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("a1"), findsOneWidget, reason: "policy expanded a");
    expect(find.text("b1"), findsNothing, reason: "policy left b collapsed");
  });

  testWidgets("a null policy result falls back to initiallyExpanded", (
    tester,
  ) async {
    await tester.pumpWidget(
      _Harness(
        roots: _twoBranches,
        initiallyExpanded: false,
        initialNodeExpansion: (key, item) {
          // Only "a" gets an opinion; "b" defers to initiallyExpanded.
          return key == "a" ? true : null;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("a1"), findsOneWidget);
    expect(find.text("b1"), findsNothing);
  });

  testWidgets("nodes arriving in a later sync also get the policy", (
    tester,
  ) async {
    bool? policy(String key, _Node item) {
      return key == "c";
    }

    await tester.pumpWidget(
      _Harness(
        roots: <_Node>[
          const _Node("a", children: <_Node>[_Node("a1")]),
        ],
        initialNodeExpansion: policy,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("a1"), findsNothing, reason: "sanity: policy skipped a");

    // "c" is new in this sync and its policy says expand.
    await tester.pumpWidget(
      _Harness(
        roots: <_Node>[
          const _Node("a", children: <_Node>[_Node("a1")]),
          const _Node("c", children: <_Node>[_Node("c1")]),
        ],
        initialNodeExpansion: policy,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("c1"),
      findsOneWidget,
      reason: "a node added by a later sync must receive the initial policy",
    );
    expect(find.text("a1"), findsNothing);
  });

  testWidgets("the policy never overrides a user's later toggle", (
    tester,
  ) async {
    TreeController<String, _Node>? controller;
    bool? policy(String key, _Node item) {
      return true;
    }

    await tester.pumpWidget(
      _Harness(
        roots: _twoBranches,
        initialNodeExpansion: policy,
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("a1"), findsOneWidget);

    controller!.collapse(key: "a", animate: false);
    await tester.pumpAndSettle();
    expect(find.text("a1"), findsNothing);

    // A later sync (new collection instance) must not re-apply the policy
    // to a node that already exists.
    await tester.pumpWidget(
      _Harness(
        roots: <_Node>[
          const _Node("a", children: <_Node>[_Node("a1")]),
          const _Node("b", children: <_Node>[_Node("b1")]),
        ],
        initialNodeExpansion: policy,
        onControllerCreated: (c) {
          controller = c;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("a1"),
      findsNothing,
      reason: "an existing node keeps the state the user gave it",
    );
  });

  testWidgets(
    "a remembered expansion wins over a conflicting policy on re-add",
    (tester) async {
      TreeController<String, _Node>? controller;
      // The policy says "never expand", so if the re-added node comes back
      // expanded it can only be the preserved state.
      bool? policy(String key, _Node item) {
        return false;
      }

      await tester.pumpWidget(
        _Harness(
          roots: _twoBranches,
          initialNodeExpansion: policy,
          onControllerCreated: (c) {
            controller = c;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("a1"), findsNothing, reason: "sanity: policy applied");

      controller!.expand(key: "a", animate: false);
      await tester.pumpAndSettle();
      expect(find.text("a1"), findsOneWidget, reason: "sanity: user expanded");

      // Remove "a", then bring it back.
      await tester.pumpWidget(
        _Harness(
          roots: <_Node>[
            const _Node("b", children: <_Node>[_Node("b1")]),
          ],
          initialNodeExpansion: policy,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("a"), findsNothing, reason: "sanity: removed");

      await tester.pumpWidget(
        _Harness(roots: _twoBranches, initialNodeExpansion: policy),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("a1"),
        findsOneWidget,
        reason:
            "preserveExpansion restored the node, and a restored state "
            "must win over the initial policy",
      );
    },
  );

  testWidgets("the gained-first-children heuristic respects a false policy", (
    tester,
  ) async {
    bool? policy(String key, _Node item) {
      return false;
    }

    // "a" starts childless, so nothing to expand either way.
    await tester.pumpWidget(
      _Harness(roots: <_Node>[const _Node("a")], initialNodeExpansion: policy),
    );
    await tester.pumpAndSettle();
    expect(find.text("a"), findsOneWidget);

    // Now "a" gains its first child: the auto-expand heuristic would
    // normally open it, and the policy must veto that.
    await tester.pumpWidget(
      _Harness(
        roots: <_Node>[
          const _Node("a", children: <_Node>[_Node("a1")]),
        ],
        initialNodeExpansion: policy,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("a1"),
      findsNothing,
      reason: "the heuristic must consult the per-node policy",
    );
  });

  testWidgets(
    "without a policy the heuristic still auto-expands a parent that gains "
    "its first children",
    (tester) async {
      await tester.pumpWidget(_Harness(roots: <_Node>[const _Node("a")]));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _Harness(
          roots: <_Node>[
            const _Node("a", children: <_Node>[_Node("a1")]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("a1"),
        findsOneWidget,
        reason: "the pre-existing blanket behavior must be unchanged",
      );
    },
  );

  testWidgets(
    "onExpansionChanged reports later changes but stays silent for the "
    "widget's own initial expansion",
    (tester) async {
      final events = <(String, bool)>[];
      TreeController<String, _Node>? controller;

      await tester.pumpWidget(
        _Harness(
          roots: _twoBranches,
          onControllerCreated: (c) {
            controller = c;
          },
          onExpansionChanged: (key, isExpanded) {
            events.add((key, isExpanded));
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("a1"),
        findsOneWidget,
        reason: "sanity: initiallyExpanded did expand the tree",
      );
      expect(
        events,
        isEmpty,
        reason: "the initial expansion pass is initialization, not a change",
      );

      controller!.collapse(key: "a", animate: false);
      await tester.pumpAndSettle();
      expect(events, [("a", false)]);

      controller!.expand(key: "a", animate: false);
      await tester.pumpAndSettle();
      expect(events, [("a", false), ("a", true)]);
    },
  );

  testWidgets("onExpansionChanged reports sync-driven expansion", (
    tester,
  ) async {
    final events = <(String, bool)>[];

    await tester.pumpWidget(
      _Harness(
        roots: <_Node>[const _Node("a")],
        onExpansionChanged: (key, isExpanded) {
          events.add((key, isExpanded));
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(events, isEmpty);

    // "a" gains its first child: the auto-expand heuristic opens it, and
    // that IS an expansion change a persistence consumer needs to hear.
    await tester.pumpWidget(
      _Harness(
        roots: <_Node>[
          const _Node("a", children: <_Node>[_Node("a1")]),
        ],
        onExpansionChanged: (key, isExpanded) {
          events.add((key, isExpanded));
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(events, [("a", true)]);
  });
}
