/// Repro for M19: every reorderable row was wrapped in `Opacity(1.0)`.
///
/// `RenderOpacity` is a compositing boundary at any alpha above zero, so
/// the wrapper made EVERY visible row a repaint boundary with its own
/// `OpacityLayer`, on top of the package's own `RepaintBoundary`, and
/// `addRepaintBoundaries: false` could not remove it. Nothing in the wrap
/// touched focus either, so a focused field in the dragged row kept
/// primary focus while invisible. The hide is now a `Visibility` whose
/// render object is a plain proxy that only skips paint, emits the
/// `IgnorePointer` the hide needs, and excludes focus while hidden. Its
/// shape is identical in both states, so row `State` survives the flip.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

class _Rig {
  _Rig({required this.tree, required this.reorder});

  final TreeController<String, String> tree;
  final TreeReorderController<String> reorder;
}

Future<_Rig> _mount(
  WidgetTester tester, {
  required Widget Function(BuildContext context, String key, int depth) content,
  bool addRepaintBoundaries = true,
  bool showDragProxy = true,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots(const [
    TreeNode(key: "a", data: "A"),
    TreeNode(key: "b", data: "B"),
    TreeNode(key: "c", data: "C"),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
    tree.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              addRepaintBoundaries: addRepaintBoundaries,
              showDragProxy: showDragProxy,
              nodeBuilder: content,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Rig(tree: tree, reorder: reorder);
}

/// Records every `initState` and publishes its `State`, so a case can
/// tell a surviving element from a re-inflated one.
class _Probe extends StatefulWidget {
  const _Probe({
    required this.label,
    required this.inits,
    required this.states,
  });

  final String label;
  final List<String> inits;
  final List<State> states;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.inits.add(widget.label);
    widget.states.add(this);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 50, child: Text(widget.label));
  }
}

void main() {
  testWidgets("with addRepaintBoundaries false no row carries an Opacity or a "
      "repaint boundary between itself and the sliver", (tester) async {
    await _mount(
      tester,
      addRepaintBoundaries: false,
      content: (context, key, depth) {
        return TreeDelayedDragHandle(
          child: SizedBox(
            key: ValueKey("row-$key"),
            height: 50,
            child: Text(key),
          ),
        );
      },
    );

    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason:
          "the hide must not be an Opacity: at alpha 1.0 its render "
          "object is a compositing boundary with its own layer on every "
          "visible row",
    );

    final sliver = tester.renderObject(find.byType(SliverTree<String, String>));
    RenderObject ro = tester.renderObject(find.byKey(const ValueKey("row-a")));
    while (!identical(ro, sliver)) {
      expect(
        ro.isRepaintBoundary,
        isFalse,
        reason:
            "no render object between a row and the sliver may be a "
            "repaint boundary once addRepaintBoundaries is false; found "
            "${ro.runtimeType}",
      );
      ro = ro.parent!;
    }
  });

  testWidgets(
    "a focused field in the dragged row loses focus while the row is hidden",
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final rig = await _mount(
        tester,
        // The in-place copy stays live (no placeholder), so what unfocuses
        // the field is the hide wrapper itself, not a re-inflation.
        showDragProxy: false,
        content: (context, key, depth) {
          return Row(
            children: [
              Expanded(
                child: key == "a"
                    ? TextField(key: const ValueKey("field-a"), focusNode: node)
                    : SizedBox(height: 50, child: Text(key)),
              ),
              TreeDragHandle(
                child: SizedBox(
                  key: ValueKey("grip-$key"),
                  width: 24,
                  height: 50,
                  child: const Icon(Icons.drag_handle),
                ),
              ),
            ],
          );
        },
      );

      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue, reason: "setup: the field is focused");

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("grip-a"))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(rig.reorder.isDragging, isTrue, reason: "setup: the drag started");

      expect(
        node.hasFocus,
        isFalse,
        reason:
            "the hidden row must exclude focus: an invisible field "
            "keeping primary focus takes keyboard input nobody can see",
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "the hide wrapper keeps its shape: row State survives lift, move and "
    "drop (showDragProxy false)",
    (tester) async {
      final inits = <String>[];
      final states = <State>[];
      final rig = await _mount(
        tester,
        showDragProxy: false,
        content: (context, key, depth) {
          return TreeDelayedDragHandle(
            child: KeyedSubtree(
              key: ValueKey("row-$key"),
              child: _Probe(label: key, inits: inits, states: states),
            ),
          );
        },
      );
      expect(inits.where((l) => l == "a").length, 1, reason: "setup");

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-a"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(rig.reorder.isDragging, isTrue, reason: "setup: the drag started");
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        inits.where((l) => l == "a").length,
        1,
        reason:
            "a conditional wrapper would re-inflate the row at the hidden "
            "flip and run initState again",
      );
      // The same State instance follows: a new State always runs initState.
    },
  );
}
