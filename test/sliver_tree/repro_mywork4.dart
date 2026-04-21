import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

Map<Object, ({double offset, double visibleExtent, double measuredHeight})>
_sampleRenderState(WidgetTester tester) {
  final result =
      <
        Object,
        ({double offset, double visibleExtent, double measuredHeight})
      >{};
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
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

class _Harness extends StatefulWidget {
  const _Harness({required this.sections});
  final List<String> sections;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<String, String>? _controller;

  @override
  Widget build(BuildContext context) {
    final roots = <TreeNode<String, String>>[
      for (final s in widget.sections) TreeNode(key: s, data: s),
    ];
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, String>.nodes(
              roots: roots,
              childrenOf: (key) {
                if (key.endsWith("_1")) return const [];
                return [TreeNode(key: "${key}_1", data: "${key}_1")];
              },
              maxStickyDepth: 1,
              animationDuration: const Duration(milliseconds: 300),
              animationCurve: Curves.linear,
              itemBuilder: (context, node) {
                _controller ??= node.controller;
                return SizedBox(
                  key: ValueKey(node.key),
                  height: 48,
                  child: Text(node.key),
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
    "remove, then immediately re-add in same frame (no animation tick)",
    (tester) async {
      await tester.pumpWidget(
        const _Harness(sections: ["today", "overdue", "comingUp", "noDueDate"]),
      );
      await tester.pumpAndSettle();

      // Filter 1: today only
      await tester.pumpWidget(const _Harness(sections: ["today"]));
      // NO pump between. Go straight to the next rebuild.

      // Filter 2: overdue (removes today, re-adds overdue).
      // The first filter's sync ran but no frame was pumped, so exit animations
      // haven't ticked yet. overdue's current extent = 48 (startExtent of exit).
      await tester.pumpWidget(const _Harness(sections: ["overdue"]));
      await tester.pump();

      final post = _sampleRenderState(tester);
      // ignore: avoid_print
      print("POST (no intervening pump):");
      post.forEach((k, v) {
        print(
          "  $k  offset=${v.offset.toStringAsFixed(2)} "
          "extent=${v.visibleExtent.toStringAsFixed(2)}",
        );
      });

      // In this scenario, since no time elapsed, overdue's current extent is
      // still 48 (the initial startExtent of the exit). Reversing exit → enter
      // yields startExtent = 48, so overdue appears at full extent immediately.
      // This IS a "jump to fully expanded" from the user's perspective: they
      // click two filters rapidly and the re-added item doesn't visibly
      // animate in at all.
      final overdueExt = post["overdue"]!.visibleExtent;
      // ignore: avoid_print
      print("overdue extent after rapid filter switch = $overdueExt");

      await tester.pumpAndSettle();
    },
  );

  testWidgets("remove with one frame pumped, then re-add", (tester) async {
    // Version where a single frame pumps between the two syncs. This is the
    // closest to what actually happens in an app: the filter click causes a
    // rebuild, which triggers a frame, which starts the animation. The next
    // filter click happens a few frames later.
    await tester.pumpWidget(
      const _Harness(sections: ["today", "overdue", "comingUp", "noDueDate"]),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const _Harness(sections: ["today"]));
    await tester.pump(); // build + first layout

    final midFrame1 = _sampleRenderState(tester);
    // ignore: avoid_print
    print(
      "After pump 1 (frame 1 of exit): overdue extent=${midFrame1["overdue"]?.visibleExtent}",
    );

    await tester.pumpWidget(const _Harness(sections: ["overdue"]));
    await tester.pump();

    final post = _sampleRenderState(tester);
    // ignore: avoid_print
    print("POST: overdue extent=${post["overdue"]!.visibleExtent}");

    await tester.pumpAndSettle();
  });

  testWidgets("remove then re-add — SMALLEST mid-exit window", (tester) async {
    await tester.pumpWidget(
      const _Harness(sections: ["today", "overdue", "comingUp", "noDueDate"]),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const _Harness(sections: ["today"]));
    await tester.pump();
    // Advance just 16ms (1 frame of animation progress).
    await tester.pump(const Duration(milliseconds: 16));

    final mid = _sampleRenderState(tester);
    // ignore: avoid_print
    print("Mid after 16ms: overdue extent=${mid["overdue"]?.visibleExtent}");
    final midOverdueExt = mid["overdue"]!.visibleExtent;

    await tester.pumpWidget(const _Harness(sections: ["overdue"]));
    await tester.pump();

    final post = _sampleRenderState(tester);
    // ignore: avoid_print
    print("POST: overdue extent=${post["overdue"]!.visibleExtent}");

    expect(
      post["overdue"]!.visibleExtent,
      closeTo(midOverdueExt, 2.0),
      reason:
          "overdue should resume from mid-exit extent "
          "(mid=$midOverdueExt post=${post["overdue"]!.visibleExtent})",
    );

    await tester.pumpAndSettle();
  });
}
