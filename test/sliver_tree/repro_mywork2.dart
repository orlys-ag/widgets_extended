import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Mimics MyWork: section nodes keyed by section id, each with a list of
/// item children keyed by item id. Payload is a non-== class (identity
/// equality), so every rebuild marks retained nodes as data-changed.
sealed class _K {
  const _K();
}

class _Section extends _K {
  const _Section(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is _Section && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => "Section($id)";
}

class _Item extends _K {
  const _Item(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is _Item && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => "Item($id)";
}

sealed class _D {
  const _D();
}

class _SectionData extends _D {
  const _SectionData(this.id);
  final String id;
  // Deliberately NO operator==, mirroring MyWorkSectionNode.
}

class _ItemData extends _D {
  const _ItemData(this.id, this.isLast);
  final String id;
  final bool isLast;
  // Deliberately NO operator==.
}

class _Harness extends StatefulWidget {
  const _Harness({required this.sectionsWithItems});

  /// Map of section id -> list of item ids.
  final Map<String, List<String>> sectionsWithItems;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<_K, _D>? _controller;

  @override
  Widget build(BuildContext context) {
    final roots = <TreeNode<_K, _D>>[
      for (final s in widget.sectionsWithItems.keys)
        TreeNode(key: _Section(s), data: _SectionData(s)),
    ];
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<_K, _D>.nodes(
              roots: roots,
              childrenOf: (key) {
                if (key is _Section) {
                  final items =
                      widget.sectionsWithItems[key.id] ?? const <String>[];
                  return [
                    for (int i = 0; i < items.length; i++)
                      TreeNode(
                        key: _Item(items[i]),
                        data: _ItemData(items[i], i == items.length - 1),
                      ),
                  ];
                }
                return const [];
              },
              maxStickyDepth: 1,
              animationDuration: const Duration(milliseconds: 300),
              animationCurve: Curves.linear,
              itemBuilder: (context, node) {
                _controller ??= node.controller;
                return SizedBox(
                  key: ValueKey(node.key),
                  height: 48,
                  child: Text(node.key.toString()),
                );
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
    "mywork2: re-add mid-exit section with 3 items while another removes",
    (tester) async {
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "today": ["t1", "t2"],
            "overdue": ["o1", "o2", "o3"],
            "comingUp": ["c1"],
            "noDueDate": ["n1", "n2"],
          },
        ),
      );
      await tester.pumpAndSettle();

      final controller = tester
          .state<_HarnessState>(find.byType(_Harness))
          ._controller!;

      // Step 1: filter to only today → exits overdue + its 3 items, etc.
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "today": ["t1", "t2"],
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final midOverdue = controller.getCurrentExtent(const _Section("overdue"));
      final midO1 = controller.getCurrentExtent(const _Item("o1"));
      final midO2 = controller.getCurrentExtent(const _Item("o2"));
      final midO3 = controller.getCurrentExtent(const _Item("o3"));
      // ignore: avoid_print
      print("Mid-exit: overdue=$midOverdue o1=$midO1 o2=$midO2 o3=$midO3");
      expect(midOverdue, greaterThan(0));
      expect(midOverdue, lessThan(48));

      // Step 2: filter to only overdue → removes today, re-adds overdue.
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "overdue": ["o1", "o2", "o3"],
          },
        ),
      );
      await tester.pump();

      final afterOverdue = controller.getCurrentExtent(
        const _Section("overdue"),
      );
      final afterO1 = controller.getCurrentExtent(const _Item("o1"));
      final afterO2 = controller.getCurrentExtent(const _Item("o2"));
      final afterO3 = controller.getCurrentExtent(const _Item("o3"));
      // ignore: avoid_print
      print(
        "After re-add: overdue=$afterOverdue o1=$afterO1 o2=$afterO2 o3=$afterO3",
      );

      expect(
        afterOverdue,
        closeTo(midOverdue, 2.0),
        reason: "overdue section must resume from mid-exit, not jump to full",
      );
      expect(
        afterO1,
        closeTo(midO1, 2.0),
        reason: "o1 must resume from mid-exit, not jump to full",
      );
      expect(
        afterO2,
        closeTo(midO2, 2.0),
        reason: "o2 must resume from mid-exit, not jump to full",
      );
      expect(
        afterO3,
        closeTo(midO3, 2.0),
        reason: "o3 must resume from mid-exit, not jump to full",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets("mywork2: different item set on re-add (some new, some same)", (
    tester,
  ) async {
    // Simulates a scenario where the item list changes between the remove
    // and the re-add — e.g., an item was completed while the section was
    // being removed, so when it comes back there are fewer items.
    await tester.pumpWidget(
      _Harness(
        sectionsWithItems: {
          "today": ["t1", "t2"],
          "overdue": ["o1", "o2", "o3"],
        },
      ),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .state<_HarnessState>(find.byType(_Harness))
        ._controller!;

    // Step 1: filter to only today.
    await tester.pumpWidget(
      _Harness(
        sectionsWithItems: {
          "today": ["t1", "t2"],
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final midOverdue = controller.getCurrentExtent(const _Section("overdue"));
    final midO2 = controller.getCurrentExtent(const _Item("o2"));
    // ignore: avoid_print
    print("Mid-exit: overdue=$midOverdue o2=$midO2");

    // Step 2: re-add overdue but with a different item set (o2 gone, o4 new).
    await tester.pumpWidget(
      _Harness(
        sectionsWithItems: {
          "overdue": ["o1", "o4", "o3"],
        },
      ),
    );
    await tester.pump();

    final afterOverdue = controller.getCurrentExtent(const _Section("overdue"));
    // ignore: avoid_print
    print("After re-add: overdue=$afterOverdue");

    expect(
      afterOverdue,
      closeTo(midOverdue, 2.0),
      reason: "overdue section must resume from mid-exit, not jump to full",
    );

    await tester.pumpAndSettle();
  });

  testWidgets("mywork2: rapid filter toggles (3x in 3 frames)", (tester) async {
    await tester.pumpWidget(
      _Harness(
        sectionsWithItems: {
          "today": ["t1"],
          "overdue": ["o1", "o2"],
          "comingUp": ["c1"],
          "noDueDate": ["n1"],
        },
      ),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .state<_HarnessState>(find.byType(_Harness))
        ._controller!;

    // Filter 1: today only (removes overdue, comingUp, noDueDate).
    await tester.pumpWidget(
      _Harness(
        sectionsWithItems: {
          "today": ["t1"],
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // Filter 2: all (re-adds overdue, comingUp, noDueDate mid-exit).
    await tester.pumpWidget(
      _Harness(
        sectionsWithItems: {
          "today": ["t1"],
          "overdue": ["o1", "o2"],
          "comingUp": ["c1"],
          "noDueDate": ["n1"],
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // Mid-enter: overdue should be partially entered.
    final midOverdue = controller.getCurrentExtent(const _Section("overdue"));
    final midO1 = controller.getCurrentExtent(const _Item("o1"));
    // ignore: avoid_print
    print("Mid-enter: overdue=$midOverdue o1=$midO1");

    // Filter 3: overdue only (removes today, comingUp, noDueDate mid-*).
    // Overdue is mid-enter at this point. The sync diff will keep overdue
    // as retained — so nothing triggers _cancelDeletion for it. This is
    // a different path than the repro above.
    await tester.pumpWidget(
      _Harness(
        sectionsWithItems: {
          "overdue": ["o1", "o2"],
        },
      ),
    );
    await tester.pump();

    final afterOverdue = controller.getCurrentExtent(const _Section("overdue"));
    final afterO1 = controller.getCurrentExtent(const _Item("o1"));
    // ignore: avoid_print
    print("After filter 3: overdue=$afterOverdue o1=$afterO1");

    // Overdue's enter animation should continue uninterrupted.
    expect(
      afterOverdue,
      greaterThanOrEqualTo(midOverdue - 2.0),
      reason: "overdue should continue entering, not jump to full or reset",
    );
    expect(afterOverdue, lessThanOrEqualTo(48.0));

    await tester.pumpAndSettle();
  });
}
