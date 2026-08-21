/// Regression suite: an ENTERING root that takes the sticky band over at a
/// SCROLLED offset must enter by push-down, not pop in flush at the band top.
///
/// The candidate probe selects the entering root only once its REAL animated
/// subtree bottom crosses the probe line (`findFirstVisibleIndex` walks the
/// per-frame offsets), but `pushUpY` used to be computed from the STABLE
/// subtree bottom (`_computeSubtreeBottomFallback` counted entering
/// descendants at full extent). Mid-animation the stable bottom is far past
/// the probe line, so `pinnedY = min(stackTop, pushUpY)` clamped to
/// `stackTop` on the entering root's very first pinned frame: a hard cut,
/// painted over the previous root's header, at whatever partial height the
/// row had reached. At scroll offset 0 the flip happens at near-zero extent,
/// which is why `sticky_root_diff_repro_test.dart`'s grow-in tests never saw
/// it. See `doc/plan_sticky_entering_root_handover.md`.
///
/// The expected geometry is the settled scroll-handover: the entering
/// header's band bottom (`pinnedY + extent`) equals the real subtree bottom
/// in band space, which by construction equals the natural top of the first
/// row after its subtree, so the header slides down from above the band with
/// no gap and no overlap.
///
/// Shape mirrors `sticky_root_diff_repro_test.dart`: four depth-0 section
/// roots, capped previews plus a trailing "see all" row, `SyncedSliverTree`
/// with `maxStickyDepth: 1`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/types.dart' show StickyHeaderInfo;
import 'package:widgets_extended/widgets_extended.dart';

const double kHeaderExtent = 40.0;
const double kItemExtent = 60.0;
const double kSeeAllExtent = 40.0;
const double kViewport = 400.0;

const Duration kAnim = Duration(milliseconds: 300);

/// `selected == null` is the "ALL" segment: every section, capped at 5 rows
/// with a trailing see-all. Otherwise only that section, uncapped.
List<SyncedTreeNode<String, String>> buildTree(String? selected) {
  const sections = <String>["A", "B", "C", "D"];
  return <SyncedTreeNode<String, String>>[
    for (final section in sections)
      if (selected == null || section == selected)
        SyncedTreeNode<String, String>(
          key: "section:$section",
          data: "H$section",
          children: <SyncedTreeNode<String, String>>[
            for (var i = 0; i < (selected == null ? 5 : 25); i++)
              SyncedTreeNode<String, String>(
                key: "item:$section:$i",
                data: "I$section:$i",
              ),
            if (selected == null)
              SyncedTreeNode<String, String>(
                key: "seeall:$section",
                data: "S$section",
              ),
          ],
        ),
  ];
}

class Harness extends StatefulWidget {
  const Harness({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  TreeController<String, String>? controller;
  late List<SyncedTreeNode<String, String>> tree = buildTree(null);

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
              SyncedSliverTree<String, String>(
                tree: tree,
                maxStickyDepth: 1,
                onControllerCreated: (c) {
                  controller = c;
                },
                animationStyle: TreeAnimationStyle.uniform(
                  duration: kAnim,
                  curve: Curves.linear,
                ),
                itemBuilder: (context, node) {
                  final double height = node.item.startsWith("H")
                      ? kHeaderExtent
                      : node.item.startsWith("S")
                      ? kSeeAllExtent
                      : kItemExtent;
                  return SizedBox(height: height, child: Text(node.item));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

RenderSliverTree<String, String> renderOf(WidgetTester tester) {
  return tester.renderObject(find.byType(SliverTree<String, String>))
      as RenderSliverTree<String, String>;
}

Set<String> paintedSticky(WidgetTester tester) {
  return renderOf(tester).debugLastPaintedStickyKeys;
}

List<StickyHeaderInfo<String>> computedSticky(WidgetTester tester) {
  return renderOf(tester).debugStickyHeaders;
}

void main() {
  testWidgets(
    "an entering root taking the band over at a scrolled offset enters by "
    "push-down and meets the row below with no gap",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final key = GlobalKey<HarnessState>();
      await tester.pumpWidget(Harness(key: key, scrollController: scroll));
      await tester.pumpAndSettle();

      // Single-section view, scrolled deep inside B so the incoming A
      // section (380px settled) crosses the probe line mid-animation.
      key.currentState!.select("B");
      await tester.pumpAndSettle();
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      expect(paintedSticky(tester), <String>{"section:B"});

      final c = key.currentState!.controller!;

      // Back to ALL: A, C and D are inserted, B is re-capped.
      key.currentState!.select(null);

      final aFrames = <StickyHeaderInfo<String>>[];
      var sawEnteringWhilePinned = false;
      for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
        await tester.pump(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);

        final painted = paintedSticky(tester);
        expect(
          painted,
          hasLength(1),
          reason: "the band must never be empty mid-diff; frame at $elapsed "
              "painted $painted",
        );
        if (!painted.contains("section:A")) {
          expect(
            aFrames,
            isEmpty,
            reason: "once A owns the band it must not hand it back; "
                "frame at $elapsed painted $painted",
          );
          continue;
        }

        final info = computedSticky(tester).firstWhere((h) {
          return h.nodeId == "section:A";
        });
        aFrames.add(info);

        if (c.getAnimationState("section:A")?.type == AnimationType.entering) {
          sawEnteringWhilePinned = true;
        }

        // Continuity: while A is still sliding down (pinnedY below the band
        // top), its band bottom must meet the top of the first in-flow row
        // after its subtree, which is B's header. A gap here is a bare band
        // strip; an overlap is A painting over B's rows.
        if (info.pinnedY < -0.01) {
          final hbTop = tester.getRect(find.text("HB")).top;
          expect(
            info.pinnedY + info.extent,
            closeTo(hbTop, 0.51),
            reason: "A's band bottom must meet B's in-flow top at $elapsed",
          );
        }
      }

      expect(aFrames, isNotEmpty, reason: "A must take the band over");
      expect(
        sawEnteringWhilePinned,
        isTrue,
        reason: "setup sanity: A must be pinned while genuinely entering",
      );

      // Setup sanity: the flip must land mid-animation, at substantial
      // partial height. That is the configuration that popped: at scroll
      // offset 0 the flip happens at near-zero extent and the old code was
      // already smooth there.
      expect(
        aFrames.first.extent,
        greaterThan(kHeaderExtent * 0.3),
        reason: "the handover must happen mid-animation for this repro",
      );

      // THE BUG: A's first pinned frame had pinnedY == 0.0, a flush pin at
      // the band top painted over B's header. The expected entrance is
      // push-down: the first pinned frame starts above the band.
      expect(
        aFrames.first.pinnedY,
        lessThan(-1.0),
        reason: "an entering root must slide down into the band, not pop in "
            "flush at the top",
      );

      // The slide must be monotone: pinnedY rises to 0 and never jumps back.
      for (var i = 1; i < aFrames.length; i++) {
        expect(
          aFrames[i].pinnedY,
          greaterThanOrEqualTo(aFrames[i - 1].pinnedY - 0.01),
          reason: "pinnedY must not jump back during the entrance",
        );
      }
      expect(
        aFrames.last.pinnedY,
        closeTo(0.0, 0.01),
        reason: "the entrance must complete with A pinned at the band top",
      );

      await tester.pumpAndSettle();
      expect(paintedSticky(tester), <String>{"section:A"});
    },
  );

  testWidgets(
    "the scrolled-offset removal direction stays continuous (guard for the "
    "deliberate exit asymmetry)",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final key = GlobalKey<HarnessState>();
      await tester.pumpWidget(Harness(key: key, scrollController: scroll));
      await tester.pumpAndSettle();

      // ALL view, scrolled so B's block owns the band (B starts at 380).
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      expect(paintedSticky(tester), <String>{"section:B"});

      // Drill into B: A, C and D are removed, B is uncapped. B keeps the
      // band the whole time; the exit path must not regress.
      key.currentState!.select("B");
      for (var elapsed = Duration.zero; elapsed <= kAnim + kAnim;) {
        await tester.pump(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);
        expect(
          paintedSticky(tester),
          <String>{"section:B"},
          reason: "B must stay pinned through the removal; frame at $elapsed",
        );
        final info = computedSticky(tester).single;
        expect(info.pinnedY, closeTo(0.0, 0.01));
        expect(info.extent, closeTo(kHeaderExtent, 0.01));
      }

      await tester.pumpAndSettle();
      expect(paintedSticky(tester), <String>{"section:B"});
    },
  );
}
