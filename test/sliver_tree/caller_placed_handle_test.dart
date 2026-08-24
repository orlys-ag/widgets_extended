/// Caller-placed drag handles: the package ARMS a child, it does not
/// decide where that child sits.
///
/// Before this change the only drag surface the package offered was a
/// trailing-edge cell composed into a `Row` by `_ReorderableRowState`, so
/// a grip across the TOP of a card, at the LEADING edge, or two of them
/// in one row, were all inexpressible. Worse, the reserved gutter was a
/// layout decision imposed on every row of the tree: measured, a 24px
/// grip narrowed an 800px viewport's rows to 776px whether or not the row
/// could drag.
///
/// Each test here starts a REAL drag from a caller-placed handle and
/// asserts it commits through `onReorder`, so none of them can pass on a
/// handle that merely renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

typedef _Reported = ({String key, String? newParent, int index});

class _Harness {
  _Harness({required this.tree, required this.reorder, required this.reported});

  final TreeController<String, String> tree;
  final TreeReorderController<String> reorder;
  final List<_Reported> reported;
}

/// Mounts a three-root tree whose rows are built by [rowBuilder].
Future<_Harness> _mount(
  WidgetTester tester,
  Widget Function(String key) rowBuilder, {
  bool Function(String key)? canReorder,
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

  final reported = <_Reported>[];
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
    canReorder: canReorder,
    onReorder: (key, newParent, index) {
      reported.add((key: key, newParent: newParent, index: index));
    },
  );
  addTearDown(() {
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
              // Off so row finders stay unambiguous: the default proxy
              // clones the dragged row's child into the overlay.
              showDragProxy: false,
              nodeBuilder: (context, key, depth) {
                return rowBuilder(key);
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(tree: tree, reorder: reorder, reported: reported);
}

/// A 32px grip bar across the full width of a card, above 48px of
/// content. The originating use case for this whole change.
Widget _cardWithTopBar(String key) {
  return Column(
    key: ValueKey("row-$key"),
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      TreeDragHandle(
        child: SizedBox(
          key: ValueKey("grip-$key"),
          height: 32.0,
          width: double.infinity,
          child: const ColoredBox(color: Color(0xFF000000)),
        ),
      ),
      SizedBox(height: 48.0, child: Text(key)),
    ],
  );
}

/// A row with a grip at each end and nothing the package composed.
Widget _twoHandledRow(String key) {
  return SizedBox(
    key: ValueKey("row-$key"),
    height: 80.0,
    child: Row(
      children: <Widget>[
        TreeDragHandle(
          child: SizedBox(
            key: ValueKey("grip-left-$key"),
            width: 40.0,
            height: 80.0,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
        const Spacer(),
        TreeDragHandle(
          child: SizedBox(
            key: ValueKey("grip-right-$key"),
            width: 40.0,
            height: 80.0,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      ],
    ),
  );
}

void main() {
  group("caller-placed drag handles", () {
    testWidgets(
      "a handle across the top of a card starts a drag that commits",
      (tester) async {
        final h = await _mount(tester, _cardWithTopBar);

        // Setup sanity: the bar really is a full-width strip at the row's
        // top, not the package's trailing cell. Without this the test could
        // pass by grabbing whatever the package happened to install.
        final gripRect = tester.getRect(find.byKey(const ValueKey("grip-a")));
        expect(gripRect.width, 800.0, reason: "the bar spans the viewport");
        expect(gripRect.top, 0.0, reason: "the bar sits at the row's top");
        expect(gripRect.height, 32.0);

        final gesture = await tester.startGesture(gripRect.center);
        await tester.pump();
        // Immediate multi-drag: past the slop is enough, no press-and-hold.
        await gesture.moveBy(const Offset(0.0, 170.0));
        await tester.pump();

        expect(
          h.reorder.draggedKey,
          "a",
          reason: "the bar must have lifted its own row",
        );

        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          h.reported.map((r) => r.key),
          ["a"],
          reason: "the drag must commit exactly one reorder, for row a",
        );
        expect(h.tree.rootKeys.first, isNot("a"));
        expect(h.tree.rootKeys.toSet(), {"a", "b", "c"});
      },
    );

    testWidgets("a handle at the leading edge starts a drag that commits", (
      tester,
    ) async {
      final h = await _mount(tester, (key) {
        return SizedBox(
          key: ValueKey("row-$key"),
          height: 80.0,
          child: Row(
            children: <Widget>[
              TreeDragHandle(
                child: SizedBox(
                  key: ValueKey("grip-$key"),
                  width: 24.0,
                  height: 80.0,
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
              Expanded(child: Text(key)),
            ],
          ),
        );
      });

      final gripRect = tester.getRect(find.byKey(const ValueKey("grip-a")));
      expect(gripRect.left, 0.0, reason: "leading edge, not trailing");

      final gesture = await tester.startGesture(gripRect.center);
      await tester.pump();
      await gesture.moveBy(const Offset(0.0, 170.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(h.reported.map((r) => r.key), ["a"]);
      expect(h.tree.rootKeys.first, isNot("a"));
    });

    testWidgets("two handles in one row: either one lifts and commits", (
      tester,
    ) async {
      // Inexpressible before this change: the package offered exactly one
      // trailing cell per row.
      final h = await _mount(tester, _twoHandledRow);

      for (final grip in const ["grip-left-a", "grip-right-a"]) {
        final rect = tester.getRect(find.byKey(ValueKey(grip)));
        final gesture = await tester.startGesture(rect.center);
        await tester.pump();
        await gesture.moveBy(const Offset(0.0, 170.0));
        await tester.pump();
        expect(h.reorder.draggedKey, "a", reason: "$grip must lift row a");
        await gesture.up();
        await tester.pumpAndSettle();

        // Put it back so the second pass starts from the same place.
        h.tree.reorderRoots(const ["a", "b", "c"], animate: false);
        await tester.pumpAndSettle();
      }

      expect(h.reported.map((r) => r.key), ["a", "a"]);
    });

    testWidgets(
      "a second pointer-down on the DRAGGED row's other handle is ignored",
      (tester) async {
        // The dragged row's in-place copy is hidden AND non-interactive
        // (issue 9 of the 2026-08-21 review: hiding with `Opacity(0)` alone
        // left it hit-testable, so a second finger on its other grip ran the
        // row's re-entry guard and cancelled the live drag, which the
        // user experiences as the drag dying under a stray touch).
        // The pointer no longer reaches the hidden row at all, so the
        // session survives and the first finger still commits.
        //
        // This replaces a test that pinned the opposite outcome. That
        // guard (`_ownsSession()` then `_cancelDrag()` on pointer-down)
        // is deliberately kept: it answers a real hazard, because
        // `MultiDragGestureRecognizer.dispose` resolves its arena
        // entries without calling `cancel()` or `end()` on its client,
        // so replacing a live row's recognizer would orphan the session
        // with its pin, scroll listener and autoscroll ticker still
        // installed. It is simply no longer REACHABLE from the public
        // surface: it fires only for the row that owns the session
        // (`_ownsSession` compares `draggedKey` to this row's key), and
        // that row is hidden for the whole session, so no pointer can
        // arrive. It stays as protection for any future path that
        // un-hides a row mid-session.
        final h = await _mount(tester, _twoHandledRow);

        final left = tester.getCenter(
          find.byKey(const ValueKey("grip-left-a")),
        );
        final right = tester.getCenter(
          find.byKey(const ValueKey("grip-right-a")),
        );

        final first = await tester.startGesture(left, pointer: 1);
        await tester.pump();
        await first.moveBy(const Offset(0.0, 30.0));
        await tester.pump();

        // Setup sanity: there really is a live session.
        expect(h.reorder.isDragging, isTrue);
        expect(h.reorder.draggedKey, "a");

        final second = await tester.startGesture(right, pointer: 2);
        await tester.pump();
        expect(
          h.reorder.isDragging,
          isTrue,
          reason: "the hidden row cannot receive the pointer, so nothing "
              "supersedes the live session",
        );
        await second.up();
        await tester.pump();

        // The original finger still owns the drag and commits it.
        await first.moveBy(const Offset(0.0, 140.0));
        await tester.pump();
        await first.up();
        await tester.pumpAndSettle();

        expect(h.reorder.isDragging, isFalse);
        expect(h.reported.map((r) => r.key), ["a"]);
        expect(h.tree.rootKeys, ["b", "c", "a"]);
      },
    );

    testWidgets("the package reserves no gutter for a handle", (tester) async {
      // The layout half of the defect. Measured on the old code, a 24px
      // grip narrowed every row from 800 to 776 through the package's own
      // Row/Expanded/Visibility apparatus, including rows that could not
      // drag at all.
      final h = await _mount(
        tester,
        (key) {
          return SizedBox(
            key: ValueKey("row-$key"),
            height: 80.0,
            child: TreeDragHandle(child: Text(key)),
          );
        },
        canReorder: (key) {
          return key != "c";
        },
      );

      for (final key in const ["a", "b", "c"]) {
        expect(
          tester.getSize(find.byKey(ValueKey("row-$key"))).width,
          800.0,
          reason:
              "row $key must span the viewport: the package composes no "
              "gutter of its own, whether or not the row can drag",
        );
      }
      expect(h.tree.rootKeys, ["a", "b", "c"]);
    });

    testWidgets("a row with no handle cannot be lifted but still takes drops", (
      tester,
    ) async {
      // The first question a reader has about caller-placed handles, and
      // it was unanswered by the design. Row b has no handle at all.
      final h = await _mount(tester, (key) {
        final content = SizedBox(
          key: ValueKey("row-$key"),
          height: 80.0,
          width: double.infinity,
          child: Text(key),
        );
        if (key == "b") {
          return content;
        }
        return TreeDragHandle(child: content);
      });

      // b cannot be lifted.
      final bRect = tester.getRect(find.byKey(const ValueKey("row-b")));
      final noLift = await tester.startGesture(bRect.center);
      await tester.pump();
      await noLift.moveBy(const Offset(0.0, 100.0));
      await tester.pump();
      expect(
        h.reorder.isDragging,
        isFalse,
        reason: "a row with no handle has no drag surface",
      );
      await noLift.up();
      await tester.pumpAndSettle();
      expect(h.reported, isEmpty);

      // ...but a is still droppable past it.
      final aRect = tester.getRect(find.byKey(const ValueKey("row-a")));
      final gesture = await tester.startGesture(aRect.center);
      await tester.pump();
      await gesture.moveBy(const Offset(0.0, 170.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        h.reported.map((r) => r.key),
        ["a"],
        reason: "a handle-less row is still a drop TARGET",
      );
      expect(h.tree.rootKeys.first, isNot("a"));
    });
  });
}
