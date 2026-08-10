/// Covers the single commit path shared by pointer drops and programmatic
/// / assistive-technology moves.
///
/// Two things are being established:
///
/// 1. A structural mutation issued WHILE a drag session is live corrupts
///    that session. The semantic reorder actions can do exactly this today
///    (they call `reorderRoots` / `reorderChildren` / `moveNode` with no
///    `isDragging` guard) and are reachable from assistive technology at
///    any moment, including mid-drag. Refusing is the fix.
/// 2. Every committed reorder, however it was initiated, reports itself
///    through one `onReorder` channel. Without that, a consumer holding
///    authoritative data cannot observe an AT-driven move at all.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:widgets_extended/sliver_tree/reorder_render_port.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/tree_reorder_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Minimal render port: four 50px rows, laid out, driven by [controller].
class _FakePort implements ReorderRenderPort<String> {
  _FakePort(this.controller, this.rows);

  final TreeController<String, Object?> controller;
  final List<String> rows;
  final Set<String> pinned = <String>{};
  int baselineCalls = 0;

  @override
  bool get isLaidOut => true;

  @override
  double get precedingScrollExtent => 0.0;

  @override
  bool drivesController(Object c) {
    return identical(c, controller);
  }

  @override
  ({double paintedOffset, double extent})? paintedRowBounds(String key) {
    final index = rows.indexOf(key);
    if (index < 0) {
      return null;
    }
    return (paintedOffset: index * 50.0, extent: 50.0);
  }

  @override
  ({String key, double paintedOffset, double extent})? findRowAtPaintedY(
    double y,
  ) {
    final index = (y ~/ 50).clamp(0, rows.length - 1);
    return (key: rows[index], paintedOffset: index * 50.0, extent: 50.0);
  }

  @override
  void pinNode(String key) {
    pinned.add(key);
  }

  @override
  void unpinNode(String key) {
    pinned.remove(key);
  }

  @override
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
    Map<String, ({double y, double? x})>? baselineOverrides,
  }) {
    baselineCalls++;
  }
}

void main() {
  late TreeController<String, String> tree;

  Future<TreeController<String, String>> build(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(<TreeNode<String, String>>[
      const TreeNode(key: "a", data: "a"),
      const TreeNode(key: "b", data: "b"),
      const TreeNode(key: "c", data: "c"),
      const TreeNode(key: "d", data: "d"),
    ]);
    return tree;
  }

  tearDown(() {
    tree.dispose();
  });

  group("onReorder reports every committed move", () {
    testWidgets("a programmatic moveTo fires it once with the final slot", (
      tester,
    ) async {
      await build(tester);
      final events = <(String, String?, int)>[];
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        onReorder: (key, newParent, index) {
          events.add((key, newParent, index));
        },
      );
      addTearDown(reorder.dispose);

      // Same-parent reorder: "a" moves to sit after "c".
      final ok = reorder.moveTo("a", null, index: 2);
      expect(ok, isTrue);
      expect(tree.liveRootKeys, <String>["b", "c", "a", "d"]);
      expect(events, <(String, String?, int)>[("a", null, 2)]);
    });

    testWidgets("a cross-parent moveTo reports the destination parent", (
      tester,
    ) async {
      await build(tester);
      final events = <(String, String?, int)>[];
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        onReorder: (key, newParent, index) {
          events.add((key, newParent, index));
        },
      );
      addTearDown(reorder.dispose);

      expect(reorder.moveTo("a", "c", index: 0), isTrue);
      expect(tree.getParent("a"), "c");
      expect(events, <(String, String?, int)>[("a", "c", 0)]);
    });

    testWidgets("each semantic move fires it exactly once", (tester) async {
      await build(tester);
      final events = <(String, String?, int)>[];
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        onReorder: (key, newParent, index) {
          events.add((key, newParent, index));
        },
      );
      addTearDown(reorder.dispose);

      expect(reorder.moveDown("a"), isTrue);
      expect(tree.liveRootKeys, <String>["b", "a", "c", "d"]);
      expect(events.length, 1);
      expect(events.single, ("a", null, 1));

      expect(reorder.moveUp("a"), isTrue);
      expect(tree.liveRootKeys, <String>["a", "b", "c", "d"]);
      expect(events.length, 2);

      expect(reorder.moveIntoPrevious("c"), isTrue);
      expect(tree.getParent("c"), "b");
      expect(events.length, 3);
      expect(events.last, ("c", "b", 0));

      expect(reorder.moveOut("c"), isTrue);
      expect(tree.getParent("c"), isNull);
      expect(events.length, 4);
    });

    testWidgets("a refused move fires nothing and mutates nothing", (
      tester,
    ) async {
      await build(tester);
      var fired = 0;
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        canAcceptDrop: ({required movingKey, newParent, index}) {
          return newParent != "c";
        },
        onReorder: (key, newParent, index) {
          fired++;
        },
      );
      addTearDown(reorder.dispose);
      final before = tree.structureGeneration;

      expect(
        reorder.moveTo("a", "c", index: 0),
        isFalse,
        reason: "policy refuses c as a parent",
      );
      expect(
        reorder.moveTo("zzz", null, index: 0),
        isFalse,
        reason: "unknown key",
      );
      expect(reorder.moveTo("a", "a", index: 0), isFalse, reason: "self");
      expect(
        reorder.moveTo("a", null, index: 0),
        isFalse,
        reason: "already at that position",
      );
      // moveUp on the first row has nowhere to go.
      expect(reorder.moveUp("a"), isFalse);

      expect(fired, 0);
      expect(tree.structureGeneration, before);
      expect(tree.liveRootKeys, <String>["a", "b", "c", "d"]);
    });

    testWidgets("reports the RESOLVED index, never the raw argument", (
      tester,
    ) async {
      await build(tester);
      final events = <(String, String?, int)>[];
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        onReorder: (key, newParent, index) {
          events.add((key, newParent, index));
        },
      );
      addTearDown(reorder.dispose);

      // Cross-parent, wildly out of range. `moveNode` clamps internally,
      // so the tree lands correctly; reporting the argument would publish
      // a position that never existed to a consumer told to treat it as a
      // live-space list index.
      expect(reorder.moveTo("a", "c", index: 7), isTrue);
      expect(tree.getLiveChildren("c"), <String>["a"]);
      expect(events.single, ("a", "c", 0));

      events.clear();
      expect(reorder.moveTo("b", "c", index: -4), isTrue);
      expect(tree.getLiveChildren("c"), <String>["b", "a"]);
      expect(events.single, ("b", "c", 0));
    });

    testWidgets("canReorder is enforced by the programmatic API too", (
      tester,
    ) async {
      await build(tester);
      var fired = 0;
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        canReorder: (key) {
          return key != "a";
        },
        onReorder: (key, newParent, index) {
          fired++;
        },
      );
      addTearDown(reorder.dispose);

      // Enforced only in the presentation layer, an immovable row could
      // still be repositioned by anything calling the controller.
      expect(reorder.moveTo("a", null, index: 2), isFalse);
      expect(reorder.moveDown("a"), isFalse);
      expect(tree.liveRootKeys, <String>["a", "b", "c", "d"]);
      expect(fired, 0);

      expect(reorder.moveDown("b"), isTrue, reason: "others still move");
    });

    testWidgets("a cycle attempt is refused", (tester) async {
      await build(tester);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      expect(reorder.moveTo("b", "a", index: 0), isTrue);
      expect(tree.getParent("b"), "a");
      // "a" may not become a child of its own descendant.
      expect(reorder.moveTo("a", "b", index: 0), isFalse);
      expect(tree.getParent("a"), isNull);
    });
  });

  group("a live drag session refuses programmatic moves", () {
    testWidgets("moveTo and the semantic moves are refused while dragging", (
      tester,
    ) async {
      await build(tester);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
      );
      addTearDown(reorder.dispose);
      final port = _FakePort(tree, <String>["a", "b", "c", "d"]);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(children: const <Widget>[SizedBox(height: 1000)]),
        ),
      );
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

      final started = reorder.startDrag(
        key: "a",
        renderPort: port,
        scrollable: scrollable,
        pointerGlobal: const Offset(10.0, 20.0),
      );
      expect(started, isTrue, reason: "setup: the session must be live");

      final before = tree.structureGeneration;
      final order = tree.liveRootKeys;

      // Mutating structure underneath a live session leaves it resolving
      // against painted offsets that predate the change, collides with the
      // commit script's first-wins FLIP baseline, and can strand the
      // make-room gap on a slot that no longer exists. Refusing is the
      // only safe answer, and it is what the row-level actions never did.
      expect(reorder.moveDown("c"), isFalse);
      expect(reorder.moveUp("d"), isFalse);
      expect(reorder.moveOut("b"), isFalse);
      expect(reorder.moveIntoPrevious("c"), isFalse);
      expect(reorder.moveTo("c", null, index: 0), isFalse);

      expect(
        tree.structureGeneration,
        before,
        reason: "no mutation may reach the tree mid-session",
      );
      expect(tree.liveRootKeys, order);
      expect(reorder.isDragging, isTrue, reason: "and the drag survives");

      reorder.cancelDrag();

      // Once the session is over the same call succeeds.
      expect(reorder.moveDown("c"), isTrue);
      expect(tree.liveRootKeys, <String>["a", "b", "d", "c"]);
    });
  });
}
