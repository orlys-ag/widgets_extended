/// Repro for H5: a `GlobalKey` inside a row breaks dragging.
///
/// The drag proxy mounts the exact widget instance the `nodeBuilder`
/// returned in the root overlay while the in-place copy stays mounted, so
/// one subtree has two live inflations; the lift frame's layout-phase
/// rebuild of the row then retakes an app-owned STABLE `GlobalKey` out of
/// the overlay, a render-tree mutation outside the sliver's layout root.
/// The fix replaces the dragged subtree's in-place rows with sized
/// placeholders while the proxy is their mount, so content is inflated
/// exactly once; `State` is recreated at lift and drop unless the caller
/// supplies a `GlobalKey`, which then migrates intact.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Records its lifecycle so a test can tell a migrated State from a
/// re-created one.
class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.log, required this.label});

  final List<String> log;
  final String label;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add("init:${widget.label}");
  }

  @override
  void dispose() {
    widget.log.add("dispose:${widget.label}");
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 50, child: Text(widget.label));
  }
}

class _Rig {
  _Rig({required this.tree, required this.reorder});

  final TreeController<String, String> tree;
  final TreeReorderController<String> reorder;
}

Future<_Rig> _mount(
  WidgetTester tester, {
  required Widget Function(BuildContext context, String key, int depth) content,
  bool showDragProxy = true,
  bool expandA = false,
  ScrollController? scroll,
  double? viewportHeight,
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
  tree.setChildren("a", const [
    TreeNode(key: "a0", data: "A0"),
    TreeNode(key: "a1", data: "A1"),
  ]);
  if (expandA) {
    tree.expand(key: "a", animate: false);
  }
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

  Widget body = CustomScrollView(
    controller: scroll,
    slivers: [
      SliverReorderableTree<String, String>(
        controller: tree,
        reorderController: reorder,
        showDragProxy: showDragProxy,
        nodeBuilder: (context, key, depth) {
          return TreeDelayedDragHandle(
            child: KeyedSubtree(
              key: ValueKey("row-$key"),
              child: content(context, key, depth),
            ),
          );
        },
      ),
    ],
  );
  if (viewportHeight != null) {
    body = SizedBox(height: viewportHeight, child: body);
  }
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
  await tester.pumpAndSettle();
  return _Rig(tree: tree, reorder: reorder);
}

/// Long-presses the IN-PLACE copy of [key] (scoped under the scroll view:
/// the proxy duplicates row keys mid-drag).
Future<TestGesture> _lift(WidgetTester tester, String key) async {
  final center = tester.getCenter(
    find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byKey(ValueKey("row-$key")),
    ),
  );
  final gesture = await tester.startGesture(center);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return gesture;
}

Finder _inPlace(Key key) {
  return find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byKey(key),
  );
}

/// The in-place [_Probe] labelled [label], found by label rather than by
/// key so a case can vary the key without changing how it looks the
/// probe up.
Finder _probeIn(String label) {
  return find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byWidgetPredicate((w) => w is _Probe && w.label == label),
  );
}

void main() {
  testWidgets(
    "a stable GlobalKey nested in row content survives lift, move and "
    "release without an exception",
    (tester) async {
      // One instance per node id, held OUTSIDE the builder, so the row's
      // layout-phase rebuild and the overlay's captured copy name the
      // SAME key. An inline GlobalKey() would not reproduce anything: a
      // fresh instance per build never has a current element to retake.
      final keys = <String, GlobalKey>{};
      GlobalKey keyFor(String k) => keys.putIfAbsent(k, GlobalKey.new);
      final rig = await _mount(
        tester,
        content: (context, key, depth) {
          return SizedBox(
            height: 50,
            child: SizedBox(key: keyFor(key), child: Text(key)),
          );
        },
      );

      final gesture = await _lift(tester, "a");
      expect(rig.reorder.isDragging, isTrue, reason: "setup");
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            "no frame of the drag may throw: the LIFT frame's "
            "layout-phase rebuild used to retake the key out of the overlay",
      );
      expect(rig.reorder.isDragging, isFalse, reason: "the drop ended it");
    },
  );

  testWidgets(
    "with a stable GlobalKey the row's State migrates to the proxy and "
    "back intact, descendant clones included",
    (tester) async {
      final keys = <String, GlobalKey>{};
      GlobalKey keyFor(String k) => keys.putIfAbsent(k, GlobalKey.new);
      final log = <String>[];
      await _mount(
        tester,
        expandA: true,
        content: (context, key, depth) {
          return _Probe(key: keyFor(key), log: log, label: key);
        },
      );
      final before = tester.state<_ProbeState>(_probeIn("a"));
      final beforeChild = tester.state<_ProbeState>(_probeIn("a0"));
      expect(log.where((e) => e == "init:a").length, 1, reason: "setup");

      // An EXPANDED parent: the proxy stacks one fresh clone per visible
      // descendant, each re-invoking nodeBuilder with the same stable key.
      final gesture = await _lift(tester, "a");
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            "no frame of the drag may throw, the descendant clones "
            "included",
      );

      expect(
        identical(tester.state<_ProbeState>(_probeIn("a")), before),
        isTrue,
        reason:
            "the same element must migrate in place, to the proxy and "
            "back, so the State instance is preserved end to end",
      );
      expect(
        identical(tester.state<_ProbeState>(_probeIn("a0")), beforeChild),
        isTrue,
        reason: "and so must a descendant's, through the clone path",
      );
    },
  );

  testWidgets(
    "without a GlobalKey the in-place State is disposed at lift (so a new "
    "instance is created at drop)",
    (tester) async {
      final log = <String>[];
      await _mount(
        tester,
        content: (context, key, depth) {
          return _Probe(log: log, label: key);
        },
      );

      final gesture = await _lift(tester, "a");
      expect(
        log.where((e) => e == "dispose:a").length,
        1,
        reason:
            "the in-place copy is replaced by a placeholder at lift, "
            "so its State is disposed exactly once (the proxy's copy is a "
            "separate, new inflation)",
      );

      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      // The documented default, a NEW State in place at the drop, follows
      // from the dispose above: a disposed State cannot be remounted.
    },
  );

  testWidgets(
    "sanity control: showDragProxy false keeps the live in-place mount",
    (tester) async {
      await _mount(
        tester,
        showDragProxy: false,
        content: (context, key, depth) {
          return SizedBox(
            height: 50,
            child: SizedBox(key: ValueKey("content-$key"), child: Text(key)),
          );
        },
      );
      final gesture = await _lift(tester, "a");
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(
        _inPlace(const ValueKey("content-a")),
        findsOneWidget,
        reason:
            "nothing else inflates the row, so the live copy stays "
            "(the dragProxyEnabled gate)",
      );
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "a never-measured descendant keeps its lift-time extent for the drag "
    "and heals at the drop",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      tree.setRoots(const [TreeNode(key: "p", data: "P")]);
      tree.setChildren("p", [
        for (int i = 0; i < 40; i++) TreeNode(key: "p$i", data: "P$i"),
      ]);
      tree.expand(key: "p", animate: false);
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
            body: SizedBox(
              height: 600,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverReorderableTree<String, String>(
                    controller: tree,
                    reorderController: reorder,
                    nodeBuilder: (context, key, depth) {
                      return TreeDelayedDragHandle(
                        child: SizedBox(
                          key: ValueKey("row-$key"),
                          // Deliberately above defaultExtent (48).
                          height: 100,
                          child: Text(key),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tree.getMeasuredExtent("p0"), 100.0, reason: "setup: measured");
      expect(
        tree.getMeasuredExtent("p30"),
        isNull,
        reason: "setup: p30 has never been laid out",
      );
      final gesture = await _lift(tester, "p");
      expect(
        tester.takeException(),
        isNull,
        reason:
            "the lift rebuilds every MOUNTED row of the subtree, the "
            "stale ones (mounted, not admitted this frame) included; their "
            "new placeholder render objects must be laid out before the "
            "frame's semantics flush, not left for post-frame eviction",
      );
      expect(reorder.isDragging, isTrue, reason: "setup");
      // Bring p30 into the viewport mid-drag. Rows past the cache region
      // sit at ESTIMATED offsets (48 px each), so the jump is taken from
      // the controller's own prefix sum rather than from 100 px rows.
      final p30Offset = tree.scrollOffsetOf("p30");
      expect(p30Offset, isNotNull, reason: "setup");
      scroll.jumpTo(p30Offset! - 100.0);
      await tester.pump();
      await tester.pump();
      expect(
        reorder.isDragging,
        isTrue,
        reason: "setup: the programmatic scroll must not end the drag",
      );

      expect(
        tree.getMeasuredExtent("p30"),
        TreeController.defaultExtent,
        reason:
            "the placeholder measures at the estimate, so the stored "
            "extent is defaultExtent, not the row's true 100",
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tree.getMeasuredExtent("p30"),
        100.0,
        reason:
            "real content replaces the placeholder at the drop and "
            "re-measures",
      );
    },
  );
}
