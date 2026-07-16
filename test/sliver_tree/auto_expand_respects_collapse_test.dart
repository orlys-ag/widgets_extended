/// Regression test for audit item 2.4: the "gained first children"
/// auto-expand heuristic must not override a user's deliberate collapse
/// of a RETAINED parent.
///
/// Sequence: user collapses P -> a filter-sync empties P's children ->
/// filter cleared, children return. The heuristic used to see "gained
/// first children" + not remembered + not expanded and call expand(P),
/// silently undoing the user's collapse. (Parents that are removed and
/// re-added were already covered by expansion memory; a parent that stays
/// in the tree the whole time was not.)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Item {
  const _Item({required this.id, this.parentId});

  final String id;
  final String? parentId;
}

class _Harness extends StatefulWidget {
  const _Harness({required this.items});

  final List<_Item> items;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<String, _Item>? _capturedController;

  TreeController<String, _Item> get treeController {
    return _capturedController!;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SyncedSliverTree<String, _Item>.flat(
              items: widget.items,
              keyOf: (item) {
                return item.id;
              },
              parentOf: (item) {
                return item.parentId;
              },
              initiallyExpanded: true,
              animationDuration: Duration.zero,
              itemBuilder: (context, node) {
                _capturedController = node.controller;
                return SizedBox(height: 48, child: Text(node.item.id));
              },
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  const fullTree = <_Item>[
    _Item(id: "p"),
    _Item(id: "c1", parentId: "p"),
    _Item(id: "q"),
  ];
  const filteredTree = <_Item>[
    _Item(id: "p"),
    _Item(id: "q"),
  ];

  testWidgets(
    "collapse -> filter empties children -> unfilter: the parent stays "
    "collapsed",
    (tester) async {
      await tester.pumpWidget(const _Harness(items: fullTree));
      await tester.pumpAndSettle();

      final harness = tester.state<_HarnessState>(find.byType(_Harness));
      final controller = harness.treeController;
      expect(controller.isExpanded("p"), isTrue,
          reason: "setup: initiallyExpanded opens p");
      expect(find.text("c1"), findsOneWidget);

      // The user deliberately collapses p.
      controller.collapse(key: "p", animate: false);
      await tester.pumpAndSettle();
      expect(find.text("c1"), findsNothing);

      // A filter-sync empties p's children (p itself survives).
      await tester.pumpWidget(const _Harness(items: filteredTree));
      await tester.pumpAndSettle();
      expect(controller.getNodeData("p"), isNotNull,
          reason: "setup: p must survive the filter");
      expect(controller.isExpanded("p"), isFalse);

      // Filter cleared — children return.
      await tester.pumpWidget(const _Harness(items: fullTree));
      await tester.pumpAndSettle();

      expect(
        controller.isExpanded("p"),
        isFalse,
        reason: "the auto-expand heuristic must not override the user's "
            "deliberate collapse of a parent that stayed in the tree "
            "through the filter cycle",
      );
      expect(find.text("c1"), findsNothing);
    },
  );

  testWidgets(
    "an expanded parent emptied by a filter shows its returning children "
    "(no false suppression)",
    (tester) async {
      await tester.pumpWidget(const _Harness(items: fullTree));
      await tester.pumpAndSettle();

      final harness = tester.state<_HarnessState>(find.byType(_Harness));
      final controller = harness.treeController;
      expect(controller.isExpanded("p"), isTrue);

      // Filter cycle WITHOUT a user collapse.
      await tester.pumpWidget(const _Harness(items: filteredTree));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const _Harness(items: fullTree));
      await tester.pumpAndSettle();

      expect(controller.isExpanded("p"), isTrue,
          reason: "p was expanded the whole time — children must be "
              "visible again after the filter cycle");
      expect(find.text("c1"), findsOneWidget);
    },
  );
}
