/// Regression suite: the sticky band must not go blank while a depth-0 root
/// is entering or exiting.
///
/// `_forEachStickyCandidate` used to disqualify any candidate in the animating
/// set (`_sticky_header_computer.dart`, the `isAnimating(candidateId) break`),
/// and because that `break` aborts the whole depth loop, a break at depth 0
/// produced ZERO sticky headers. A sectioned tree whose roots are added and
/// removed by a sync diff therefore lost its pinned header for the entire diff
/// animation, in both directions.
///
/// Shape below mirrors the My Work screen: four depth-0 section roots, each a
/// capped preview (5 items) plus a trailing "see all" row, through
/// `SyncedSliverTree` with `maxStickyDepth: 1`.
///
/// PAINT TRUTH. These tests assert against
/// [RenderSliverTree.debugLastPaintedStickyKeys], never `tester.getRect`, for
/// the pinned row. `applyPaintTransform` and `childMainAxisPosition` return
/// the pinned band for ANY member of the sticky set regardless of whether
/// Pass B painted it, so a `getRect`-based assertion passes on a header that
/// is computed-but-invisible, which is exactly the bug. `getRect` is still
/// used for NON-sticky rows, where it resolves through
/// `parentData.layoutOffset` and is honest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/types.dart' show StickyHeaderInfo;
import 'package:widgets_extended/widgets_extended.dart';

const double kHeaderExtent = 40.0;
const double kItemExtent = 60.0;
const double kSeeAllExtent = 40.0;
const double kViewport = 400.0;

/// One capped section block is header + 5 items + see-all = 380.
const double kSectionExtent = kHeaderExtent + 5 * kItemExtent + kSeeAllExtent;

const Duration kAnim = Duration(milliseconds: 300);

sealed class Row {
  const Row();
}

class SectionRow extends Row {
  const SectionRow(this.id);
  final String id;
  @override
  bool operator ==(Object other) {
    return other is SectionRow && other.id == id;
  }

  @override
  int get hashCode => Object.hash(SectionRow, id);
}

class ItemRow extends Row {
  const ItemRow(this.id);
  final String id;
  @override
  bool operator ==(Object other) {
    return other is ItemRow && other.id == id;
  }

  @override
  int get hashCode => Object.hash(ItemRow, id);
}

class SeeAllRow extends Row {
  const SeeAllRow(this.id);
  final String id;
  @override
  bool operator ==(Object other) {
    return other is SeeAllRow && other.id == id;
  }

  @override
  int get hashCode => Object.hash(SeeAllRow, id);
}

/// `selected == null` is the "ALL" segment: every section, capped at 5 rows
/// with a trailing see-all. Otherwise only that section, uncapped.
List<SyncedTreeNode<String, Row>> buildTree(String? selected) {
  const sections = <String>["A", "B", "C", "D"];
  return <SyncedTreeNode<String, Row>>[
    for (final section in sections)
      if (selected == null || section == selected)
        SyncedTreeNode<String, Row>(
          key: "section:$section",
          data: SectionRow(section),
          children: <SyncedTreeNode<String, Row>>[
            for (var i = 0; i < (selected == null ? 5 : 25); i++)
              SyncedTreeNode<String, Row>(
                key: "item:$section:$i",
                data: ItemRow("$section:$i"),
              ),
            if (selected == null)
              SyncedTreeNode<String, Row>(
                key: "seeall:$section",
                data: SeeAllRow(section),
              ),
          ],
        ),
  ];
}

class Harness extends StatefulWidget {
  const Harness({
    super.key,
    required this.scrollController,
    this.maxStickyDepth = 1,
  });

  final ScrollController scrollController;
  final int maxStickyDepth;

  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  TreeController<String, Row>? controller;
  late List<SyncedTreeNode<String, Row>> tree = buildTree(null);

  void select(String? next) {
    setState(() {
      tree = buildTree(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: kViewport,
          child: CustomScrollView(
            controller: widget.scrollController,
            slivers: <Widget>[
              SyncedSliverTree<String, Row>(
                tree: tree,
                maxStickyDepth: widget.maxStickyDepth,
                onControllerCreated: (c) {
                  controller = c;
                },
                animationStyle: TreeAnimationStyle.uniform(
                  duration: kAnim,
                  curve: Curves.linear,
                ),
                itemBuilder: (context, node) {
                  return switch (node.item) {
                    SectionRow(:final id) => SizedBox(
                      height: kHeaderExtent,
                      child: ColoredBox(
                        color: const Color(0xFFFFDDDD),
                        child: Text("H$id"),
                      ),
                    ),
                    ItemRow(:final id) => SizedBox(
                      height: kItemExtent,
                      child: Text("I$id"),
                    ),
                    SeeAllRow(:final id) => SizedBox(
                      height: kSeeAllExtent,
                      child: Text("S$id"),
                    ),
                  };
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

RenderSliverTree<String, Row> renderOf(WidgetTester tester) {
  return tester.renderObject(find.byType(SliverTree<String, Row>))
      as RenderSliverTree<String, Row>;
}

/// Keys Pass B actually painted on the last frame.
Set<String> paintedSticky(WidgetTester tester) {
  return renderOf(tester).debugLastPaintedStickyKeys;
}

/// The computed sticky set, root to leaf.
List<StickyHeaderInfo<String>> computedSticky(WidgetTester tester) {
  return renderOf(tester).debugStickyHeaders;
}


/// Replicates the private candidate probe from public state: the depth-0
/// ancestor of the first visible row whose bottom edge is past [scrollOffset].
///
/// Offsets are accumulated from `getCurrentExtent` rather than read off
/// `parentData`, so a row that has not been built yet still participates. That
/// is required here: the row that owns the band during an insertion is often
/// one the layout has not force-created.
String? bandOwnerAt(TreeController<String, Row> c, double scrollOffset) {
  var cumulative = 0.0;
  for (final key in c.visibleNodes) {
    cumulative += c.getCurrentExtent(key);
    if (cumulative > scrollOffset) {
      var owner = key;
      for (var parent = c.getParent(owner); parent != null;) {
        owner = parent;
        parent = c.getParent(owner);
      }
      return owner;
    }
  }
  return null;
}

void main() {
  // ------------------------------------------------------------------
  // Test 0: the paint-truth hook itself.
  // ------------------------------------------------------------------

  testWidgets("debugLastPaintedStickyKeys reports a normally-pinned header", (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(Harness(scrollController: scroll));
    await tester.pumpAndSettle();

    // At the top, A's header is pinned at y=0, coincident with its in-flow
    // slot. Pass B owns it either way, so the hook reports it.
    expect(paintedSticky(tester), <String>{"section:A"});

    scroll.jumpTo(220);
    await tester.pumpAndSettle();
    expect(
      paintedSticky(tester),
      <String>{"section:A"},
      reason: "A stays pinned while the viewport is inside its subtree",
    );

    // Scrolling into B's block hands the band over.
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    expect(paintedSticky(tester), <String>{"section:B"});

    // The hook tracks PAINT, so it never reports a header Pass B skipped.
    // At rest the two agree, which is the invariant the diff tests lean on.
    expect(
      paintedSticky(tester),
      computedSticky(tester).map((h) => h.nodeId).toSet(),
    );
  });

  // ------------------------------------------------------------------
  // Test 1 + 2: removal.
  // ------------------------------------------------------------------

  testWidgets("a root removed while pinned stays painted until push-up "
      "retires it, and hands over without a blank frame", (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(Harness(key: key, scrollController: scroll));
    await tester.pumpAndSettle();

    // A pinned, B's block visible below it.
    scroll.jumpTo(220);
    await tester.pumpAndSettle();
    expect(paintedSticky(tester), <String>{"section:A"});
    expect(find.text("HB"), findsOneWidget);

    // Drill into B: A, C and D are removed, B is uncapped.
    key.currentState!.select("B");

    final pinnedPerFrame = <String>[];
    var sawA = false;
    var sawB = false;
    for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);

      final painted = paintedSticky(tester);
      expect(
        painted,
        hasLength(1),
        reason:
            "the sticky band must never be empty mid-diff; frame at $elapsed "
            "painted $painted (computed: "
            "${computedSticky(tester).map((h) => h.nodeId).toList()})",
      );
      final pinned = painted.single;
      if (pinnedPerFrame.isEmpty || pinnedPerFrame.last != pinned) {
        pinnedPerFrame.add(pinned);
      }
      sawA = sawA || pinned == "section:A";
      sawB = sawB || pinned == "section:B";

      // Setup sanity: while A is still pinned it must genuinely be exiting,
      // so the test is exercising the removed guard and not a settled tree.
      if (pinned == "section:A") {
        expect(
          key.currentState!.controller!.isExiting("section:A"),
          isTrue,
          reason: "A must be mid-exit while it is still the pinned header",
        );
      }
    }

    expect(sawA, isTrue, reason: "the outgoing root must stay pinned");
    expect(sawB, isTrue, reason: "the incoming root must take over");
    expect(
      pinnedPerFrame,
      <String>["section:A", "section:B"],
      reason: "handover must happen exactly once and never go back",
    );

    await tester.pumpAndSettle();
    expect(paintedSticky(tester), <String>{"section:B"});
  });

  testWidgets("the painted header always covers the top of the band", (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(Harness(key: key, scrollController: scroll));
    await tester.pumpAndSettle();
    scroll.jumpTo(220);
    await tester.pumpAndSettle();

    key.currentState!.select("B");
    for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);
      // The whole point of the band is that the top of the viewport is
      // never bare. Whatever is pinned must straddle y == 0: its top at or
      // above the band top, its bottom below it.
      final painted = paintedSticky(tester);
      expect(painted, hasLength(1), reason: "bare band at frame $elapsed");
      final info = computedSticky(tester).firstWhere((h) {
        return painted.contains(h.nodeId);
      });
      expect(
        info.pinnedY,
        lessThanOrEqualTo(0.01),
        reason: "${info.nodeId} starts below the band top at frame $elapsed",
      );
      expect(
        info.pinnedY + info.extent,
        greaterThan(0.0),
        reason: "${info.nodeId} ends above the band top at frame $elapsed",
      );
    }
  });

  // ------------------------------------------------------------------
  // Test 3: insertion.
  // ------------------------------------------------------------------

  testWidgets("an inserted root is pinned as soon as its subtree owns the "
      "band, and not before", (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(Harness(key: key, scrollController: scroll));
    await tester.pumpAndSettle();

    // Single-section view, scrolled deep inside B.
    key.currentState!.select("B");
    await tester.pumpAndSettle();
    scroll.jumpTo(300);
    await tester.pumpAndSettle();
    expect(paintedSticky(tester), <String>{"section:B"});

    // Back to ALL: A, C and D are inserted, B is re-capped.
    key.currentState!.select(null);

    var sawA = false;
    for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);

      final painted = paintedSticky(tester);
      expect(
        painted,
        hasLength(1),
        reason: "the sticky band must never be empty mid-diff; frame at "
            "$elapsed painted $painted",
      );
      sawA = sawA || painted.single == "section:A";
    }

    expect(sawA, isTrue, reason: "A must take the band over as it grows in");
    await tester.pumpAndSettle();
    expect(paintedSticky(tester), <String>{"section:A"});
  });

  // ------------------------------------------------------------------
  // Test 6: the path the fix must NOT change.
  // ------------------------------------------------------------------

  testWidgets("expanding and collapsing a pinned header is unchanged", (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(Harness(key: key, scrollController: scroll));
    await tester.pumpAndSettle();
    scroll.jumpTo(220);
    await tester.pumpAndSettle();
    expect(paintedSticky(tester), <String>{"section:A"});

    final controller = key.currentState!.controller!;

    // Collapsing A retires the pin by push-up: A's subtree shrinks to
    // nothing, so it can no longer support a pinned header at this scroll
    // offset. The toggled node is never its own op-group member, so this
    // path never went through the removed guard.
    controller.collapse(key: "section:A");
    for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);
      expect(
        paintedSticky(tester).length,
        lessThanOrEqualTo(1),
        reason: "at most one depth-0 header can be pinned",
      );
    }
    await tester.pumpAndSettle();

    controller.expand(key: "section:A");
    await tester.pumpAndSettle();
    expect(
      paintedSticky(tester).length,
      lessThanOrEqualTo(1),
      reason: "re-expanding must not leave two headers pinned",
    );
  });

  // ------------------------------------------------------------------
  // Tests 7 + 8: maxStickyDepth 2, the reach the fix widens.
  // ------------------------------------------------------------------

  testWidgets("maxStickyDepth 2: revealing a depth-1 header by expanding its "
      "parent keeps the band coherent", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.uniform(
        duration: kAnim,
        curve: Curves.linear,
      ),
    );
    addTearDown(controller.dispose);

    controller.setRoots(<TreeNode<String, String>>[
      const TreeNode<String, String>(key: "root", data: "root"),
    ]);
    controller.setChildren("root", <TreeNode<String, String>>[
      for (var g = 0; g < 3; g++)
        TreeNode<String, String>(key: "group$g", data: "group$g"),
    ]);
    for (var g = 0; g < 3; g++) {
      controller.setChildren("group$g", <TreeNode<String, String>>[
        for (var i = 0; i < 6; i++)
          TreeNode<String, String>(key: "leaf$g-$i", data: "leaf$g-$i"),
      ]);
    }
    controller.expand(key: "root", animate: false);
    await tester.pump();

    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: kViewport,
            child: CustomScrollView(
              controller: scroll,
              slivers: <Widget>[
                SliverTree<String, String>(
                  controller: controller,
                  maxStickyDepth: 2,
                  nodeBuilder: (_, key, _) {
                    return SizedBox(height: kHeaderExtent, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Expanding group0 reveals its leaves. group0 is NOT its own op-group
    // member, but the revealed leaves are, and at depth 2 the depth-1 header
    // itself can be an op-group member when a grandparent expands.
    controller.expand(key: "group0");
    for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);
      final render =
          tester.renderObject(find.byType(SliverTree<String, String>))
              as RenderSliverTree<String, String>;
      final pinned = render.debugStickyHeaders;
      // Depth ordering must hold on every frame: root before group.
      for (var i = 1; i < pinned.length; i++) {
        expect(
          controller.getDepth(pinned[i].nodeId),
          greaterThan(controller.getDepth(pinned[i - 1].nodeId)),
          reason: "sticky stack must stay ordered root to leaf",
        );
        expect(
          pinned[i].pinnedY,
          greaterThanOrEqualTo(pinned[i - 1].pinnedY - 0.01),
          reason: "a deeper header must never float above its parent",
        );
      }
    }
    await tester.pumpAndSettle();
  });

  // ------------------------------------------------------------------
  // Entering headers must grow into the band, not snap to full height.
  // ------------------------------------------------------------------

  testWidgets("an entering root's band grows in step with its own row", (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(Harness(key: key, scrollController: scroll));
    await tester.pumpAndSettle();
    key.currentState!.select("B");
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    final c = key.currentState!.controller!;

    key.currentState!.select(null);
    final widths = <double>[];
    for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += const Duration(milliseconds: 16);
      // Deliberately NOT asserting that something is pinned every frame: the
      // incoming header is legitimately zero-height for one frame. That case
      // is pinned by the qualified-invariant test below.
      for (final info in computedSticky(tester)) {
        expect(
          info.extent,
          closeTo(c.getCurrentExtent(info.nodeId), 0.01),
          reason:
              "the band must be as tall as the row it heads; "
              "${info.nodeId} at $elapsed",
        );
        if (info.nodeId == "section:A") {
          widths.add(info.extent);
        }
      }
    }
    await tester.pumpAndSettle();

    expect(widths, isNotEmpty, reason: "A must be pinned at some point");
    for (var i = 1; i < widths.length; i++) {
      expect(
        widths[i],
        greaterThanOrEqualTo(widths[i - 1] - 0.01),
        reason: "the band must never shrink while the header grows in",
      );
    }
    expect(
      widths.first,
      lessThan(kHeaderExtent),
      reason: "it must start partway, not at full height",
    );
    expect(computedSticky(tester).single.extent, closeTo(kHeaderExtent, 0.01));
  });

  testWidgets(
    "an exiting root's band holds full height and retires by push-up",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final key = GlobalKey<HarnessState>();
      await tester.pumpWidget(Harness(key: key, scrollController: scroll));
      await tester.pumpAndSettle();
      scroll.jumpTo(220);
      await tester.pumpAndSettle();
      final c = key.currentState!.controller!;
      expect(paintedSticky(tester), <String>{"section:A"});

      key.currentState!.select("B");
      var sawNegativePinnedY = false;
      var stillPinned = true;
      for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
        await tester.pump(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);
        final a = computedSticky(
          tester,
        ).where((h) => h.nodeId == "section:A").toList();
        if (a.isEmpty) {
          stillPinned = false;
          continue;
        }
        expect(stillPinned, isTrue, reason: "A must not re-enter the band");
        expect(
          c.isExiting("section:A"),
          isTrue,
          reason: "setup sanity: A must be mid-exit while pinned",
        );
        expect(
          a.single.extent,
          closeTo(kHeaderExtent, 0.01),
          reason:
              "an exiting header keeps full height; shrinking it makes it "
              "vanish mid-height instead of sliding off",
        );
        if (a.single.pinnedY < -0.01) {
          sawNegativePinnedY = true;
        }
      }
      expect(
        sawNegativePinnedY,
        isTrue,
        reason:
            "A must leave by push-up (pinnedY going negative), not by "
            "being dropped at pinnedY == 0",
      );
    },
  );

  testWidgets("no pinned header is ever computed at zero height", (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(Harness(key: key, scrollController: scroll));
    await tester.pumpAndSettle();

    Future<void> sweep() async {
      for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
        await tester.pump(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);
        for (final info in computedSticky(tester)) {
          expect(
            info.extent,
            greaterThan(0.0),
            reason: "${info.nodeId} pinned at zero height",
          );
        }
      }
      await tester.pumpAndSettle();
    }

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    key.currentState!.select("B");
    await sweep();
    key.currentState!.select(null);
    await sweep();
  });

  testWidgets(
    "the band is never empty unless the header that owns it has zero height",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final key = GlobalKey<HarnessState>();
      await tester.pumpWidget(Harness(key: key, scrollController: scroll));
      await tester.pumpAndSettle();
      key.currentState!.select("B");
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final c = key.currentState!.controller!;

      key.currentState!.select(null);
      for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
        await tester.pump(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);
        if (paintedSticky(tester).isNotEmpty) {
          continue;
        }
        final owner = bandOwnerAt(c, scroll.offset);
        expect(
          owner,
          isNotNull,
          reason: "an empty band with no row owning it at $elapsed",
        );
        expect(
          c.getCurrentExtent(owner!),
          closeTo(0.0, 0.01),
          reason:
              "the band may only be empty while the header that owns it is "
              "still at zero height; $owner at $elapsed",
        );
      }
    },
  );

  testWidgets(
    "maxStickyDepth 2: a depth-1 header revealed by an ancestor expand grows "
    "into the band under a full-height parent",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.uniform(
          duration: kAnim,
          curve: Curves.linear,
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots(<TreeNode<String, String>>[
        const TreeNode<String, String>(key: "root", data: "root"),
      ]);
      controller.setChildren("root", <TreeNode<String, String>>[
        for (var g = 0; g < 3; g++)
          TreeNode<String, String>(key: "group$g", data: "group$g"),
      ]);
      for (var g = 0; g < 3; g++) {
        controller.setChildren("group$g", <TreeNode<String, String>>[
          for (var i = 0; i < 6; i++)
            TreeNode<String, String>(key: "leaf$g-$i", data: "leaf$g-$i"),
        ]);
        controller.expand(key: "group$g", animate: false);
      }
      controller.expand(key: "root", animate: false);

      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: kViewport,
              child: CustomScrollView(
                controller: scroll,
                slivers: <Widget>[
                  SliverTree<String, String>(
                    controller: controller,
                    maxStickyDepth: 2,
                    nodeBuilder: (_, key, _) {
                      return SizedBox(height: kHeaderExtent, child: Text(key));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final render =
          tester.renderObject(find.byType(SliverTree<String, String>))
              as RenderSliverTree<String, String>;

      // Measure everything, then hide it, then reveal it WITH animation so
      // the depth-1 header is itself an op-group member while entering.
      controller.collapse(key: "root", animate: false);
      await tester.pumpAndSettle();

      controller.expand(key: "root");
      var sawGrowingChild = false;
      for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
        await tester.pump(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);
        final pinned = render.debugStickyHeaders;
        for (final info in pinned) {
          expect(
            info.extent,
            closeTo(controller.getCurrentExtent(info.nodeId), 0.01),
            reason: "${info.nodeId}'s band must match its row at $elapsed",
          );
        }
        final child = pinned.where((h) => h.nodeId == "group0").toList();
        if (child.isNotEmpty && child.single.extent < kHeaderExtent - 0.01) {
          sawGrowingChild = true;
        }
        // The stack stays ordered even while the child's height moves, which
        // is what a per-frame `stackTop = pinnedY + extent` puts at risk.
        for (var i = 1; i < pinned.length; i++) {
          expect(
            controller.getDepth(pinned[i].nodeId),
            greaterThan(controller.getDepth(pinned[i - 1].nodeId)),
            reason: "sticky stack must stay ordered root to leaf",
          );
          expect(
            pinned[i].pinnedY,
            greaterThanOrEqualTo(pinned[i - 1].pinnedY - 0.01),
            reason: "a deeper header must never float above its parent",
          );
        }
      }
      await tester.pumpAndSettle();

      expect(
        sawGrowingChild,
        isTrue,
        reason: "group0 must be pinned at a partial height while it enters",
      );
    },
  );
}
