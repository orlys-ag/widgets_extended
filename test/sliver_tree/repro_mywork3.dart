import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Inspects actual rendered layout, not just controller state.
Map<Object, ({double offset, double visibleExtent, double measuredHeight})>
_sampleRenderState(WidgetTester tester) {
  final result =
      <
        Object,
        ({double offset, double visibleExtent, double measuredHeight})
      >{};
  final render = tester.renderObject<RenderSliverTree<Object, Object>>(
    find.byType(SliverTree<Object, Object>),
  );
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    final nodeId = pd.nodeId;
    if (nodeId != null) {
      result[nodeId] = (
        offset: pd.layoutOffset,
        visibleExtent: pd.visibleExtent,
        measuredHeight: child.size.height,
      );
    }
  });
  return result;
}

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
}

class _ItemData extends _D {
  const _ItemData(this.id, this.isLast);
  final String id;
  final bool isLast;
}

class _Harness extends StatefulWidget {
  const _Harness({required this.sectionsWithItems});
  final Map<String, List<String>> sectionsWithItems;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<Object, Object>? _controller;

  @override
  Widget build(BuildContext context) {
    final roots = <TreeNode<Object, Object>>[
      for (final s in widget.sectionsWithItems.keys)
        TreeNode<Object, Object>(key: _Section(s), data: _SectionData(s)),
    ];
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<Object, Object>.nodes(
              roots: roots,
              childrenOf: (key) {
                if (key is _Section) {
                  final items =
                      widget.sectionsWithItems[key.id] ?? const <String>[];
                  return [
                    for (int i = 0; i < items.length; i++)
                      TreeNode<Object, Object>(
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
    "render-layer: re-add mid-exit with 3 items — checks visibleExtent",
    (tester) async {
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "today": ["t1", "t2"],
            "overdue": ["o1", "o2", "o3"],
            "comingUp": ["c1"],
            "noDueDate": ["n1"],
          },
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: filter to today only.
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "today": ["t1", "t2"],
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final mid = _sampleRenderState(tester);
      // ignore: avoid_print
      print("MID (render):");
      mid.forEach((k, v) {
        print(
          "  $k  offset=${v.offset.toStringAsFixed(2)} "
          "extent=${v.visibleExtent.toStringAsFixed(2)} "
          "measured=${v.measuredHeight.toStringAsFixed(2)}",
        );
      });

      final midOverdueExt = mid[const _Section("overdue")]!.visibleExtent;
      final midO1Ext = mid[const _Item("o1")]!.visibleExtent;
      final midO2Ext = mid[const _Item("o2")]!.visibleExtent;

      // Step 2: filter to overdue only → today removed, overdue re-added.
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "overdue": ["o1", "o2", "o3"],
          },
        ),
      );
      await tester.pump();

      final post = _sampleRenderState(tester);
      // ignore: avoid_print
      print("POST (render):");
      post.forEach((k, v) {
        print(
          "  $k  offset=${v.offset.toStringAsFixed(2)} "
          "extent=${v.visibleExtent.toStringAsFixed(2)} "
          "measured=${v.measuredHeight.toStringAsFixed(2)}",
        );
      });

      final postOverdueExt = post[const _Section("overdue")]!.visibleExtent;
      final postO1Ext = post[const _Item("o1")]!.visibleExtent;
      final postO2Ext = post[const _Item("o2")]!.visibleExtent;

      expect(
        postOverdueExt,
        closeTo(midOverdueExt, 2.0),
        reason:
            "overdue should resume from mid-exit extent "
            "(mid=$midOverdueExt post=$postOverdueExt)",
      );
      expect(
        postO1Ext,
        closeTo(midO1Ext, 2.0),
        reason:
            "o1 should resume from mid-exit extent "
            "(mid=$midO1Ext post=$postO1Ext)",
      );
      expect(
        postO2Ext,
        closeTo(midO2Ext, 2.0),
        reason:
            "o2 should resume from mid-exit extent "
            "(mid=$midO2Ext post=$postO2Ext)",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "render-layer: re-add mid-exit, user-collapsed section — checks visibleExtent",
    (tester) async {
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "today": ["t1", "t2"],
            "overdue": ["o1", "o2", "o3"],
            "comingUp": ["c1"],
            "noDueDate": ["n1"],
          },
        ),
      );
      await tester.pumpAndSettle();

      final controller = tester
          .state<_HarnessState>(find.byType(_Harness))
          ._controller!;

      // Collapse overdue.
      controller.collapse(key: const _Section("overdue"), animate: false);
      await tester.pump();

      // Step 1: filter to today only. Overdue is removed while collapsed.
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "today": ["t1", "t2"],
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final mid = _sampleRenderState(tester);
      // ignore: avoid_print
      print("MID collapsed (render):");
      mid.forEach((k, v) {
        print(
          "  $k  offset=${v.offset.toStringAsFixed(2)} "
          "extent=${v.visibleExtent.toStringAsFixed(2)}",
        );
      });
      final midOverdueExt = mid[const _Section("overdue")]?.visibleExtent ?? -1;

      // Step 2: re-add overdue.
      await tester.pumpWidget(
        _Harness(
          sectionsWithItems: {
            "overdue": ["o1", "o2", "o3"],
          },
        ),
      );
      await tester.pump();

      final post = _sampleRenderState(tester);
      // ignore: avoid_print
      print("POST collapsed (render):");
      post.forEach((k, v) {
        print(
          "  $k  offset=${v.offset.toStringAsFixed(2)} "
          "extent=${v.visibleExtent.toStringAsFixed(2)}",
        );
      });
      final postOverdueExt = post[const _Section("overdue")]!.visibleExtent;

      expect(
        postOverdueExt,
        closeTo(midOverdueExt, 2.0),
        reason:
            "overdue (was collapsed) should resume from mid-exit extent "
            "(mid=$midOverdueExt post=$postOverdueExt)",
      );

      // The section is collapsed — its children should not be in the render.
      expect(
        post[const _Item("o1")],
        isNull,
        reason: "o1 should not be rendered when overdue is still collapsed",
      );

      await tester.pumpAndSettle();

      // After settle + expansion restoration, o1 should be visible at full extent.
      final done = _sampleRenderState(tester);
      // ignore: avoid_print
      print("DONE collapsed (render):");
      done.forEach((k, v) {
        print(
          "  $k  offset=${v.offset.toStringAsFixed(2)} "
          "extent=${v.visibleExtent.toStringAsFixed(2)}",
        );
      });
    },
  );
}
