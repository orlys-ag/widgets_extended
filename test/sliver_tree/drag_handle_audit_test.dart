/// Audit of the caller-placed-handle implementation.
///
/// Everything here pins a claim the design makes and nothing else
/// exercises: the recognizer's ownership and lifetime, shape stability
/// across a `canReorder` flip, a handle inside a nested scrollable, a
/// handle inside a PINNED sticky header, and the disarmed handle's
/// transparency. Each test that could pass vacuously carries a setup
/// sanity assertion proving the claimed path is genuinely reached.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// A row whose `State` records its own creation, so a re-inflation is
/// observable rather than inferred.
class _Fragile extends StatefulWidget {
  const _Fragile({required this.id, required this.built, super.key});

  final String id;
  final List<String> built;

  @override
  State<_Fragile> createState() => _FragileState();
}

class _FragileState extends State<_Fragile> {
  @override
  void initState() {
    super.initState();
    widget.built.add(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey("row-${widget.id}"),
      height: 50.0,
      width: double.infinity,
      child: const ColoredBox(color: Color(0xFF112233)),
    );
  }
}

Widget _grip(String key) {
  return TreeDragHandle(
    child: SizedBox(
      key: ValueKey("grip-$key"),
      width: 40.0,
      height: 50.0,
      child: const ColoredBox(color: Color(0xFF000000)),
    ),
  );
}

void main() {
  testWidgets("a canReorder flip does not re-inflate the row subtree", (
    tester,
  ) async {
    // The shape-stability invariant, which this change moves from the
    // package's `Visibility(maintainSize:)` apparatus onto
    // `TreeDragHandle` itself. The handle disarms by NULLING its
    // `onPointerDown`, never by omitting itself: omitting would change
    // the depth of everything beneath it, so `Widget.canUpdate` fails and
    // the framework re-inflates the row subtree, disposing the app's
    // `State` there. A half-typed text field, a nested scroll offset, a
    // running AnimationController.
    final built = <String>[];
    final locked = <String>{};
    late StateSetter setOuter;

    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
    ]);
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      canReorder: (key) {
        return !locked.contains(key);
      },
    );
    addTearDown(() {
      reorder.dispose();
      tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return CustomScrollView(
                slivers: [
                  SliverReorderableTree<String, String>(
                    controller: tree,
                    reorderController: reorder,
                    showDragProxy: false,
                    nodeBuilder: (context, key, depth) {
                      // The app's State sits INSIDE the handle, which is
                      // the arrangement the invariant is about: a caller
                      // writing `if (canDrag) TreeDragHandle(child: row)`
                      // re-inflates everything beneath it on every flip.
                      return TreeDragHandle(
                        child: _Fragile(id: key, built: built),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Setup sanity: the rows really did mount, so an unchanged list below
    // means "nothing was re-created", not "nothing was ever created".
    expect(built, ["a", "b"]);

    setOuter(() {
      locked.add("a");
    });
    await tester.pumpAndSettle();

    expect(
      built,
      ["a", "b"],
      reason:
          "refusing a row must disarm its handle, not change the row's "
          "widget shape and dispose the State beneath it",
    );

    setOuter(() {
      locked.clear();
    });
    await tester.pumpAndSettle();
    expect(built, ["a", "b"], reason: "and the same on the way back");
  });

  testWidgets("TreeDragHandle.enabled narrows but never widens", (
    tester,
  ) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      // The package's own answer is YES for every row.
      onReorder: (key, newParent, index) {
        reported.add(key);
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
                showDragProxy: false,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 50.0,
                    child: TreeDragHandle(
                      // Local narrowing on row a only.
                      enabled: key != "a",
                      child: SizedBox(
                        key: ValueKey("grip-$key"),
                        height: 50.0,
                        width: double.infinity,
                        child: const ColoredBox(color: Color(0xFF000000)),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> drag(String key, double dy) async {
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey("grip-$key"))),
      );
      await tester.pump();
      await g.moveBy(Offset(0.0, dy));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    await drag("a", 110.0);
    expect(
      reported,
      isEmpty,
      reason: "enabled: false must narrow the package's own yes",
    );

    // Setup sanity: the very same gesture on an enabled handle DOES
    // commit, so the emptiness above is the narrowing and not a broken
    // fixture.
    await drag("c", -110.0);
    expect(reported, ["c"]);
  });

  testWidgets("a handle inside a NESTED scrollable drags the tree", (
    tester,
  ) async {
    // The row resolves its own scrollable and render port from ITS
    // context, never the handle's, so a handle buried inside an inner
    // scroll view still drags the tree.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      onReorder: (key, newParent, index) {
        reported.add(key);
      },
    );
    final inner = ScrollController();
    addTearDown(() {
      inner.dispose();
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
                showDragProxy: false,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 80.0,
                    child: ListView(
                      controller: key == "a" ? inner : null,
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        SizedBox(
                          width: 900.0,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TreeDragHandle(
                              child: SizedBox(
                                key: ValueKey("grip-$key"),
                                width: 60.0,
                                height: 80.0,
                                child: const ColoredBox(
                                  color: Color(0xFF000000),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Setup sanity: the inner scrollable is real and scrollable, which is
    // what makes "the tree moved, not the inner list" a meaningful claim.
    expect(inner.position.maxScrollExtent, greaterThan(0.0));
    expect(inner.position.pixels, 0.0);

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-a"))),
    );
    await tester.pump();
    await g.moveBy(const Offset(0.0, 170.0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(reported, ["a"], reason: "the TREE reordered");
    expect(
      inner.position.pixels,
      0.0,
      reason: "the inner list must not have scrolled",
    );
  });

  testWidgets("a handle inside a PINNED sticky header drags accurately", (
    tester,
  ) async {
    // The design's headline surviving risk, retired by the
    // `paintedRowBounds` fix. A pinned header paints where its structure
    // says it is not, so grab capture must ask "where is MY row painted"
    // rather than "what row is at this y".
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "s0", data: "S0"),
      TreeNode(key: "s1", data: "S1"),
    ]);
    tree.setChildren("s0", <TreeNode<String, String>>[
      for (var i = 0; i < 12; i++) TreeNode(key: "c$i", data: "C$i"),
    ]);
    tree.expand(key: "s0", animate: false);

    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    final scroll = ScrollController();
    addTearDown(() {
      scroll.dispose();
      reorder.dispose();
      tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  maxStickyDepth: 1,
                  showDragProxy: false,
                  nodeBuilder: (context, key, depth) {
                    // Headers 40px, children 60px, so a foreign extent
                    // leaking into the grab is visible in the assertion.
                    final isHeader = key.startsWith("s");
                    return SizedBox(
                      key: ValueKey("row-$key"),
                      height: isHeader ? 40.0 : 60.0,
                      child: TreeDragHandle(
                        child: SizedBox(
                          key: ValueKey("grip-$key"),
                          height: isHeader ? 40.0 : 60.0,
                          width: double.infinity,
                          child: const ColoredBox(color: Color(0xFF000000)),
                        ),
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

    // Scroll until s0's header is genuinely PINNED: painted at the top of
    // the viewport while its structural offset has gone by.
    scroll.jumpTo(300.0);
    await tester.pumpAndSettle();

    final headerRect = tester.getRect(find.byKey(const ValueKey("row-s0")));
    // Setup sanity, and the assertion that stops this passing vacuously:
    // the header must be painted at the viewport top rather than at its
    // structural offset of 0.
    expect(
      headerRect.top,
      lessThan(1.0),
      reason: "setup: the header is pinned to the viewport top",
    );
    expect(
      scroll.position.pixels,
      greaterThan(100.0),
      reason: "setup: it is genuinely scrolled past its structural slot",
    );

    // Grab 10px below the pinned header's top edge.
    final grabAt = Offset(400.0, headerRect.top + 10.0);
    final g = await tester.startGesture(grabAt);
    await tester.pump();
    await g.moveBy(const Offset(0.0, 30.0));
    await tester.pump();

    expect(reorder.draggedKey, "s0", reason: "the pinned header lifted");
    final geometry = reorder.dragProxyGeometry;
    expect(geometry, isNotNull);
    expect(
      geometry!.grabDy,
      moreOrLessEquals(10.0, epsilon: 0.5),
      reason:
          "grabDy must be measured against the PINNED band, not the row "
          "structurally underneath it",
    );
    expect(
      geometry.rowExtent,
      40.0,
      reason: "the header's own extent, not a 60px child's",
    );

    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets("a second pointer on the dragged row does not supersede it", (
    tester,
  ) async {
    // Was: "a superseded pointer commits nothing when it is released",
    // which pinned the generation guard on `_RowDrag` by superseding a
    // live session through the DRAGGED row's other grip.
    //
    // That supersession is no longer reachable. Issue 9 of the
    // 2026-08-21 review made the hidden dragged row non-interactive
    // (`Opacity(0)` alone left it hit-testable, so a stray second finger
    // killed the drag), so the second pointer-down never reaches the
    // grip, no recognizer is replaced, and the first finger still owns
    // and commits its drag.
    //
    // The generation guard itself stays: it is what makes a released
    // pointer whose recognizer was disposed inert, and the neighbouring
    // test "a released gesture cannot end a session that REPLACED its
    // own" still exercises it.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      onReorder: (key, newParent, index) {
        reported.add(key);
      },
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
                showDragProxy: false,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 80.0,
                    child: Row(
                      children: <Widget>[
                        _grip("left-$key"),
                        const Spacer(),
                        _grip("right-$key"),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-left-a"))),
      pointer: 1,
    );
    await tester.pump();
    await first.moveBy(const Offset(0.0, 30.0));
    await tester.pump();
    expect(reorder.isDragging, isTrue, reason: "setup: a live session");

    // A second finger lands on the hidden row's other grip.
    final second = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-right-a"))),
      pointer: 2,
    );
    await tester.pump();
    expect(
      reorder.isDragging,
      isTrue,
      reason: "the hidden row ignores pointers, so nothing supersedes "
          "the live session",
    );
    expect(reorder.draggedKey, "a");

    // The first finger keeps moving and then releases: it still owns the
    // session, so its release COMMITS.
    await first.moveBy(const Offset(0.0, 200.0));
    await tester.pump();
    await first.up();
    await tester.pumpAndSettle();

    expect(
      reported.map((r) => r),
      ["a"],
      reason: "the owning finger's release commits, because nothing took "
          "the session from it",
    );
    expect(tree.rootKeys, ["b", "c", "a"]);

    await second.up();
    await tester.pumpAndSettle();
    expect(reported.length, 1, reason: "the stray finger commits nothing");
  });

  testWidgets("a released gesture cannot end a session that REPLACED its own", (
    tester,
  ) async {
    // What `dragGeneration` is for, and the only demonstrable path to it.
    // An external `cancelDrag` plus a fresh `startDrag` for the SAME key
    // leaves `isDragging` true and `draggedKey` unchanged, so those two
    // cannot tell the row that its session is gone. The original finger's
    // recognizer is still alive and still routed, so its release DOES
    // arrive; without the generation compare it would commit somebody
    // else's session.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      onReorder: (key, newParent, index) {
        reported.add(key);
      },
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
                showDragProxy: false,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 80.0,
                    child: TreeDragHandle(
                      child: SizedBox(
                        key: ValueKey("grip-$key"),
                        height: 80.0,
                        width: double.infinity,
                        child: const ColoredBox(color: Color(0xFF000000)),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-a"))),
    );
    await tester.pump();
    await g.moveBy(const Offset(0.0, 30.0));
    await tester.pump();

    // Setup sanity, and the capture the replacement needs.
    expect(reorder.isDragging, isTrue);
    final port = reorder.renderPort!;
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final firstGeneration = reorder.dragGeneration;

    reorder.cancelDrag();
    final restarted = reorder.startDrag(
      key: "a",
      renderPort: port,
      scrollable: scrollable,
      pointerGlobal: const Offset(400.0, 200.0),
    );
    await tester.pump();

    // The two observables the row would otherwise trust are BOTH
    // unchanged across the replacement. That is the whole point.
    expect(restarted, isTrue);
    expect(reorder.draggedKey, "a");
    expect(reorder.dragGeneration, isNot(firstGeneration));

    await g.up();
    await tester.pumpAndSettle();

    expect(
      reported,
      isEmpty,
      reason: "the dead gesture must not commit the replacement session",
    );
    expect(tree.rootKeys, ["a", "b", "c"]);
    expect(
      reorder.isDragging,
      isTrue,
      reason: "nor end it: the replacement is still in flight",
    );
    reorder.cancelDrag();
  });

  testWidgets("a disarmed handle does not absorb a hit meant for what is "
      "BEHIND it", (tester) async {
    // D4, stated precisely. A `Listener` never joins the gesture arena, so
    // a disarmed handle can never steal a gesture from an ANCESTOR: the
    // hit-test path contains every ancestor either way. What hit-test
    // opacity decides is whether the test continues past this widget to
    // content painted BEHIND it, which is exactly the case that matters
    // here, because `RenderSliverTree.hitTestChildren` returns on the
    // first row that reports a hit and rows overlap during a FLIP slide.
    //
    // Without the explicit `deferToChild` this would fail through the
    // package's own `MouseRegion`, whose render object defaults to
    // `HitTestBehavior.opaque`.
    var taps = 0;
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [TreeNode(key: "a", data: "A")]);
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      canReorder: (key) {
        return false;
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
                showDragProxy: false,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 80.0,
                    width: double.infinity,
                    child: Stack(
                      children: <Widget>[
                        // The app's own target, painted UNDER the handle.
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              taps++;
                            },
                          ),
                        ),
                        // A transparent grip laid over it: nothing of the
                        // caller's is opaque, so any absorption is the
                        // package's doing.
                        const Positioned.fill(
                          child: TreeDragHandle(child: SizedBox.expand()),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("row-a")));
    await tester.pumpAndSettle();

    expect(
      taps,
      1,
      reason:
          "a disarmed handle over a transparent child must let the hit "
          "reach what is painted behind it",
    );
  });

  testWidgets("an ARMED handle is hit-opaque over a transparent child", (
    tester,
  ) async {
    // The other half of the same decision, and the footgun it removes: a
    // grip built from a widget that does not hit-test itself would
    // otherwise render, show no cursor, and silently never drag.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      onReorder: (key, newParent, index) {
        reported.add(key);
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
                showDragProxy: false,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 80.0,
                    // A bare SizedBox draws nothing and hit-tests nothing.
                    child: TreeDragHandle(
                      child: SizedBox(
                        key: ValueKey("grip-$key"),
                        height: 80.0,
                        width: double.infinity,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-a"))),
    );
    await tester.pump();
    await g.moveBy(const Offset(0.0, 170.0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(reported, [
      "a",
    ], reason: "an armed handle must be grabbable even over empty space");
  });

  testWidgets("the drag proxy renders a row containing a handle, inertly", (
    tester,
  ) async {
    // The proxy clones the row's child into the root Overlay, where
    // `TreeRowDragScope.maybeOf` returns null. The handle must render its
    // child bare rather than throw, and must not arm anything.
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
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 80.0,
                    child: TreeDragHandle(
                      child: SizedBox(
                        key: ValueKey("grip-$key"),
                        height: 80.0,
                        width: double.infinity,
                        child: const ColoredBox(color: Color(0xFF000000)),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-a"))),
    );
    await tester.pump();
    await g.moveBy(const Offset(0.0, 100.0));
    await tester.pumpAndSettle();

    // Setup sanity: the proxy really is up, so the clone exists to be
    // asserted about.
    expect(reorder.isDragging, isTrue);
    expect(
      find.byKey(const ValueKey("grip-a")),
      findsOneWidget,
      reason: "cloned into the overlay; the in-place copy is a placeholder",
    );
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byKey(const ValueKey("grip-a")),
      ),
      findsNothing,
      reason: "the in-place row is a sized placeholder while the proxy is "
          "its mount (H5), so the one copy is the proxy's",
    );
    expect(tester.takeException(), isNull);

    await g.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("a handle-less row keeps its reorder semantics actions", (
    tester,
  ) async {
    // Always-wrap's other payoff: assistive technology can still reorder a
    // row no pointer can lift.
    final handle = tester.ensureSemantics();
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      onReorder: (key, newParent, index) {
        reported.add(key);
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
                showDragProxy: false,
                // No handle anywhere.
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    key: ValueKey("row-$key"),
                    height: 50.0,
                    child: Text(key),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.byKey(const ValueKey("row-a")));
    expect(
      node.getSemanticsData().customSemanticsActionIds,
      isNotEmpty,
      reason: "a row with no drag surface still advertises reorder actions",
    );

    // And they still commit.
    expect(reorder.moveDown("a"), isTrue);
    await tester.pumpAndSettle();
    expect(reported, ["a"]);

    // Disposed in the body, not a tearDown: the framework's
    // handles-were-disposed check runs before tearDowns.
    handle.dispose();
  });

  testWidgets("the default handle uses the long-press timeout", (tester) async {
    // Pins that `TreeDelayedDragHandle` inherits
    // `DelayedMultiDragGestureRecognizer`'s own default rather than
    // carrying a literal, and that the default really is press-and-hold:
    // a drag that starts BEFORE the timeout must not lift a row.
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
                showDragProxy: false,
                nodeBuilder: (context, key, depth) {
                  return TreeDelayedDragHandle(
                    child: SizedBox(
                      key: ValueKey("row-$key"),
                      height: 80.0,
                      width: double.infinity,
                      child: const ColoredBox(color: Color(0xFF000000)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final early = await tester.startGesture(const Offset(400.0, 40.0));
    await tester.pump(kLongPressTimeout - const Duration(milliseconds: 20));
    await early.moveBy(const Offset(0.0, 100.0));
    await tester.pump();
    expect(
      reorder.isDragging,
      isFalse,
      reason: "before the timeout the scrollable keeps the gesture",
    );
    await early.up();
    await tester.pumpAndSettle();

    final late = await tester.startGesture(const Offset(400.0, 40.0));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await late.moveBy(const Offset(0.0, 100.0));
    await tester.pump();
    expect(
      reorder.isDragging,
      isTrue,
      reason: "past the timeout the row lifts",
    );
    await late.up();
    await tester.pumpAndSettle();
  });

  testWidgets("a caller-placed handle works under TextDirection.rtl", (
    tester,
  ) async {
    // The package had no `Directionality` coverage at all, and a
    // caller-placed handle is the first feature where placement is the
    // caller's, so a directionality assumption in the wrapper would show
    // up here first. Scoped to the handle: the pre-existing
    // `depthForPointerX` mapping is LTR-shaped and is a separate concern.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      onReorder: (key, newParent, index) {
        reported.add(key);
      },
    );
    addTearDown(() {
      reorder.dispose();
      tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        // INSIDE the MaterialApp: it installs its own `Directionality`
        // from the resolved locale, which would shadow an outer one.
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  showDragProxy: false,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(
                      key: ValueKey("row-$key"),
                      height: 80.0,
                      child: Row(
                        children: <Widget>[
                          TreeDragHandle(
                            child: SizedBox(
                              key: ValueKey("grip-$key"),
                              width: 40.0,
                              height: 80.0,
                              child: const ColoredBox(color: Color(0xFF000000)),
                            ),
                          ),
                          Expanded(child: Text(key)),
                        ],
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

    // Setup sanity: RTL really is in force, so the leading grip sits on
    // the RIGHT. Without this the test would pass under a silently-LTR
    // tree and prove nothing.
    final gripRect = tester.getRect(find.byKey(const ValueKey("grip-a")));
    expect(
      gripRect.right,
      800.0,
      reason: "leading edge under RTL is the right edge",
    );

    final g = await tester.startGesture(gripRect.center);
    await tester.pump();
    await g.moveBy(const Offset(0.0, 170.0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(reported, ["a"]);
    expect(tree.rootKeys.first, isNot("a"));
  });

  testWidgets("flipping enabled MID-DRAG leaves the live session alone", (
    tester,
  ) async {
    // Documented rather than backstopped, and pinned in that direction so
    // a future "fix" cannot quietly add one. `enabled` is a caller's local
    // narrowing on a stateless widget that owns nothing; the recognizer
    // belongs to the row, and the `onPointerDown` being nulled has already
    // fired. `canReorder` is the refusal that DOES interrupt a live drag,
    // and `can_reorder_flip_mid_drag_test.dart` pins that.
    late StateSetter setOuter;
    var enabled = true;

    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(const [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final reported = <String>[];
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      onReorder: (key, newParent, index) {
        reported.add(key);
      },
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
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return CustomScrollView(
                slivers: [
                  SliverReorderableTree<String, String>(
                    controller: tree,
                    reorderController: reorder,
                    showDragProxy: false,
                    nodeBuilder: (context, key, depth) {
                      return SizedBox(
                        key: ValueKey("row-$key"),
                        height: 80.0,
                        child: TreeDragHandle(
                          enabled: enabled,
                          child: SizedBox(
                            key: ValueKey("grip-$key"),
                            height: 80.0,
                            width: double.infinity,
                            child: const ColoredBox(color: Color(0xFF000000)),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-a"))),
    );
    await tester.pump();
    await g.moveBy(const Offset(0.0, 30.0));
    await tester.pump();
    expect(reorder.isDragging, isTrue, reason: "setup: a live session");

    setOuter(() {
      enabled = false;
    });
    await tester.pumpAndSettle();

    expect(
      reorder.isDragging,
      isTrue,
      reason: "disarming a handle does not end the drag it already started",
    );

    await g.moveBy(const Offset(0.0, 140.0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(reported, ["a"], reason: "and the gesture still commits normally");
  });
}
