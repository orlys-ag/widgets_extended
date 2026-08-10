/// Tests for plan item T2: `SyncedSliverTree` hands its internal
/// [TreeController] to the caller through `onControllerCreated`.
///
/// This is the supported way to reach controller capabilities that no row
/// builder can offer: `animateScrollToKey`, toolbar expand/collapse-all,
/// reading expansion state to persist it. Before this hook the only way in
/// was to smuggle the reference out of `itemBuilder` on the first build.
///
/// The contract has three parts, one test each: the callback observes the
/// SETTLED initial state (after the first sync and the initial expansion
/// pass), the reference actually drives the live tree, and the hook is a
/// one-shot handover rather than a per-sync notification.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Node {
  const _Node(this.id, {this.children = const <_Node>[]});

  final String id;
  final List<_Node> children;
}

class _Harness extends StatefulWidget {
  const _Harness({required this.roots, this.onControllerCreated});

  final List<_Node> roots;
  final void Function(TreeController<String, _Node> controller)?
  onControllerCreated;

  @override
  State<_Harness> createState() {
    return _HarnessState();
  }
}

class _HarnessState extends State<_Harness> {
  void rebuild() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, _Node>.hierarchy(
              roots: widget.roots,
              keyOf: (item) {
                return item.id;
              },
              childrenOf: (item) {
                return item.children;
              },
              animationStyle: TreeAnimationStyle.disabled,
              onControllerCreated: widget.onControllerCreated,
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
  testWidgets(
    "onControllerCreated fires once with the controller already in its "
    "settled initial state",
    (tester) async {
      int calls = 0;
      bool? expandedAtCallbackTime;
      List<String>? visibleAtCallbackTime;

      await tester.pumpWidget(
        _Harness(
          roots: <_Node>[
            const _Node("a", children: <_Node>[_Node("a1")]),
          ],
          onControllerCreated: (controller) {
            calls++;
            // Read INSIDE the callback: the contract is that the tree is
            // already synced and the initial expansion pass has run by the
            // time the caller gets the reference.
            expandedAtCallbackTime = controller.isExpanded("a");
            visibleAtCallbackTime = controller.visibleNodes;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        expandedAtCallbackTime,
        isTrue,
        reason:
            "initiallyExpanded defaults to true, so the callback must "
            "observe the node already expanded",
      );
      expect(
        visibleAtCallbackTime,
        <String>["a", "a1"],
        reason: "the first sync must be complete before the handover",
      );
    },
  );

  testWidgets(
    "the captured controller drives the live tree from outside the builders",
    (tester) async {
      TreeController<String, _Node>? captured;

      await tester.pumpWidget(
        _Harness(
          roots: <_Node>[
            const _Node("a", children: <_Node>[_Node("a1")]),
          ],
          onControllerCreated: (controller) {
            captured = controller;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("a1"),
        findsOneWidget,
        reason: "sanity: the child row starts visible",
      );

      captured!.collapseAll(animate: false);
      await tester.pumpAndSettle();

      expect(find.text("a1"), findsNothing);
      expect(find.text("a"), findsOneWidget);

      captured!.expandAll(animate: false);
      await tester.pumpAndSettle();
      expect(find.text("a1"), findsOneWidget);
    },
  );

  testWidgets(
    "the hook is a one-shot handover: no refire on rebuild or on a fresh "
    "sync, and unmounting stays clean",
    (tester) async {
      int calls = 0;
      void capture(TreeController<String, _Node> controller) {
        calls++;
      }

      await tester.pumpWidget(
        _Harness(
          roots: <_Node>[const _Node("a")],
          onControllerCreated: capture,
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);

      // Identity-skipped rebuild.
      tester.state<_HarnessState>(find.byType(_Harness)).rebuild();
      await tester.pump();
      expect(calls, 1);

      // A genuinely new collection instance: a real sync runs, but the
      // controller is the same object and must not be handed over again.
      await tester.pumpWidget(
        _Harness(
          roots: <_Node>[const _Node("a"), const _Node("b")],
          onControllerCreated: capture,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("b"),
        findsOneWidget,
        reason: "sanity: the new instance did sync",
      );
      expect(
        calls,
        1,
        reason: "onControllerCreated is a handover, not a per-sync callback",
      );

      // The widget owns the controller: unmounting disposes it cleanly.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
