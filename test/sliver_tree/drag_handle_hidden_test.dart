/// Repro: the drag handle stays fully opaque while the row it belongs to
/// is hidden for the drag.
///
/// Make-room hides the in-place dragged row so its slot can close under it
/// and neighbouring rows can slide over that space. If the hide were
/// applied to anything narrower than the whole row the caller built, a
/// caller-placed grip would keep painting at full opacity in a slot the
/// neighbours are sliding across, which is precisely the "residual paint"
/// the hide exists to prevent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const Key _handleKey = ValueKey("handle-a");

Future<TreeReorderController<String>> _mount(WidgetTester tester) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots(<TreeNode<String, String>>[
    const TreeNode(key: "a", data: "A"),
    const TreeNode(key: "b", data: "B"),
    const TreeNode(key: "c", data: "C"),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  addTearDown(() {
    reorder.dispose();
    tree.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              // Off: the default proxy clones the row into an overlay and
              // would make the handle finder ambiguous mid-drag.
              showDragProxy: false,
              nodeBuilder: (context, key, depth) {
                return Row(
                  children: <Widget>[
                    Expanded(
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
                    ),
                    TreeDragHandle(
                      child: SizedBox(
                        key: key == "a" ? _handleKey : null,
                        width: 24.0,
                        height: 50.0,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reorder;
}

/// The smallest `Opacity.opacity` on the path from [finder] up to the
/// root, or 1.0 when nothing on that path fades it. This is what actually
/// decides whether the widget puts ink on the screen.
double _effectiveOpacity(WidgetTester tester, Finder finder) {
  double result = 1.0;
  for (final Widget w in tester.widgetList<Opacity>(
    find.ancestor(of: finder, matching: find.byType(Opacity)),
  )) {
    result = result < (w as Opacity).opacity ? result : w.opacity;
  }
  return result;
}

void main() {
  testWidgets("a dragged row's handle is hidden with the rest of the row", (
    tester,
  ) async {
    final reorder = await _mount(tester);

    final handle = find.byKey(_handleKey);
    expect(handle, findsOneWidget);
    expect(
      _effectiveOpacity(tester, handle),
      1.0,
      reason: "setup: the handle is visible before any drag",
    );

    // Grab the handle itself, which is the gesture this mode exists for.
    final gesture = await tester.startGesture(tester.getCenter(handle));
    // Handle mode uses a vertical-drag recognizer, so exceeding the touch
    // slop is what starts the session; there is no long-press delay.
    await gesture.moveBy(const Offset(0.0, 30.0));
    await tester.pump();

    expect(
      reorder.isDragging,
      isTrue,
      reason: "setup: the handle drag must actually have started",
    );
    expect(reorder.draggedKey, "a");

    // The row's own content is hidden already; that part works today.
    expect(
      _effectiveOpacity(tester, find.byKey(const ValueKey("row-a"))),
      0.0,
      reason: "setup: the in-place row content is hidden for the drag",
    );

    // The handle must go with it. Neighbouring rows slide across this
    // slot, so anything left painting here overlaps them.
    expect(
      _effectiveOpacity(tester, handle),
      0.0,
      reason: "the handle is residual paint in a slot that is closing",
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      _effectiveOpacity(tester, handle),
      1.0,
      reason: "and it comes back once the drag ends",
    );
  });

  testWidgets("hiding the row does not break the in-flight drag gesture", (
    tester,
  ) async {
    // The fix moves the gesture detector INSIDE the Opacity. RenderOpacity
    // does not override hitTest, and an in-flight drag routes to its
    // recognizer regardless, but that is worth pinning rather than
    // assuming: a zero-opacity subtree must still drive the session.
    final reorder = await _mount(tester);
    final handle = find.byKey(_handleKey);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    // Handle mode uses a vertical-drag recognizer, so exceeding the touch
    // slop is what starts the session; there is no long-press delay.
    await gesture.moveBy(const Offset(0.0, 30.0));
    await tester.pump();
    expect(reorder.isDragging, isTrue);

    // Keep moving after the row went transparent, then commit.
    await gesture.moveBy(const Offset(0.0, 80.0));
    await tester.pump();
    expect(reorder.isDragging, isTrue, reason: "updates still land");
    expect(reorder.currentTarget, isNotNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(reorder.isDragging, isFalse);
  });
}
