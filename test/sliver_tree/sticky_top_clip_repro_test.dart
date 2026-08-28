/// Regression suite: a sticky header must never paint above the tree
/// sliver's own paint origin.
///
/// `_sticky_header_computer.dart`'s push-up drives a retiring header's
/// `pinnedY` through the whole range `(-extent, 0)` before the retirement
/// gate drops it. Pass B used to clip only the BOTTOM edge, so for those
/// frames the header was drawn above the sliver's region with no clip at
/// all. Two ways that becomes visible:
///
///   * The tree fits its viewport, so the sliver declares no visual
///     overflow, the viewport pushes no clip layer, and the header escapes
///     the scroll view entirely onto whatever sits above it. This is the
///     reported My Work artifact (the "Today" header covering
///     `MyWorkTypeFilter`), and [stickyHeaderDoesNotEscapeTheViewport]
///     reproduces it in pixels.
///   * A sliver sits ABOVE the tree, and the header is drawn over it even
///     when the viewport DOES clip, because the viewport's clip is to its
///     own rect and both bands are inside it. No geometry flag can fix
///     that one; only the sliver clipping itself can.
///
/// PAINT TRUTH. These tests assert against
/// [RenderSliverTree.debugLastPaintedStickyBands] and against captured
/// pixels, never `tester.getRect`. `applyPaintTransform` returns the
/// pinned band for ANY member of the sticky set and is identical before
/// and after the fix, so a `getRect` assertion cannot discriminate.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

const double kHeaderExtent = 40.0;
const double kItemExtent = 60.0;
const double kViewport = 400.0;

/// Height of the widget sitting ABOVE the `CustomScrollView`, standing in
/// for `MyWorkTypeFilter`.
const double kBar = 50.0;

/// Height of the sliver sitting above the tree INSIDE the scroll view.
const double kBanner = 60.0;

const int kBarColor = 0xff00ff00;
const int kHeaderColor = 0xffff0000;
const int kItemColor = 0xff0000ff;

const Duration kAnim = Duration(milliseconds: 300);

sealed class Row {
  const Row();
}

class SectionRow extends Row {
  const SectionRow();
}

class ItemRow extends Row {
  const ItemRow();
}

List<SyncedTreeNode<String, Row>> buildTree(
  List<String> sections,
  int perSection,
) {
  return <SyncedTreeNode<String, Row>>[
    for (final section in sections)
      SyncedTreeNode<String, Row>(
        key: "section:$section",
        data: const SectionRow(),
        children: <SyncedTreeNode<String, Row>>[
          for (var i = 0; i < perSection; i++)
            SyncedTreeNode<String, Row>(
              key: "item:$section:$i",
              data: const ItemRow(),
            ),
        ],
      ),
  ];
}

final GlobalKey kCaptureKey = GlobalKey();

class Harness extends StatefulWidget {
  const Harness({
    super.key,
    required this.initialSections,
    this.perSection = 1,
    this.precedingSliver = false,
    this.scrollController,
  });

  final List<String> initialSections;
  final int perSection;

  /// Puts a `SliverToBoxAdapter` INSIDE the scroll view, above the tree.
  /// That band is unreachable by the viewport's clip, so it isolates the
  /// half of the defect a `hasVisualOverflow` term could never fix.
  final bool precedingSliver;

  final ScrollController? scrollController;

  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late List<SyncedTreeNode<String, Row>> tree = buildTree(
    widget.initialSections,
    widget.perSection,
  );

  TreeController<String, Row>? controller;

  void select(List<String> next) {
    setState(() {
      tree = buildTree(next, widget.perSection);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: kCaptureKey,
          child: Column(
            children: <Widget>[
              const SizedBox(
                height: kBar,
                width: double.infinity,
                child: ColoredBox(color: Color(kBarColor)),
              ),
              Expanded(
                child: CustomScrollView(
                  controller: widget.scrollController,
                  slivers: <Widget>[
                    if (widget.precedingSliver)
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: kBanner,
                          width: double.infinity,
                          child: ColoredBox(color: Color(kBarColor)),
                        ),
                      ),
                    SyncedSliverTree<String, Row>(
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
                        return switch (node.item) {
                          SectionRow() => const SizedBox(
                            height: kHeaderExtent,
                            width: double.infinity,
                            child: ColoredBox(color: Color(kHeaderColor)),
                          ),
                          ItemRow() => const SizedBox(
                            height: kItemExtent,
                            width: double.infinity,
                            child: ColoredBox(color: Color(kItemColor)),
                          ),
                        };
                      },
                    ),
                  ],
                ),
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

/// The ARGB value of one captured pixel of the real rendered frame. The
/// only oracle in this file that trusts nothing but the raster.
Future<int> pixelAt(WidgetTester tester, int x, int y) async {
  final boundary =
      kCaptureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late int result;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final int offset = (y * image.width + x) * 4;
    result =
        (data.getUint8(offset + 3) << 24) |
        (data.getUint8(offset) << 16) |
        (data.getUint8(offset + 1) << 8) |
        data.getUint8(offset + 2);
    image.dispose();
  });
  return result;
}

Future<void> pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  // ------------------------------------------------------------------
  // T1: the reported artifact, in pixels.
  // ------------------------------------------------------------------

  testWidgets("a retiring header does not paint outside the scroll view", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, kViewport + kBar));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(
      Harness(key: key, initialSections: const <String>["A", "B"]),
    );
    await tester.pumpAndSettle();

    key.currentState!.select(const <String>["B"]);
    await tester.pump();

    var pushUpFrames = 0;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      final render = renderOf(tester);
      final headers = render.debugStickyHeaders;
      if (headers.isEmpty || headers.first.pinnedY >= 0) {
        continue;
      }
      pushUpFrames++;

      // Setup sanity. Without this the test could pass because the
      // viewport happened to clip, which is a different code path from
      // the one under test.
      expect(
        render.geometry!.hasVisualOverflow,
        isFalse,
        reason:
            "the escape only happens when no sliver declares overflow, so "
            "the viewport pushes no clip; frame $i",
      );

      // Sample one pixel ABOVE the bottom edge of the bar, not at its
      // midpoint. The header intrudes by `-pinnedY`, growing from zero,
      // so a midpoint sample is blind for most of the push-up: measured
      // on unfixed code it stayed the bar's colour at pinnedY -10 and
      // -20 and only went red at -30.
      expect(
        await pixelAt(tester, 200, (kBar - 1).toInt()),
        kBarColor,
        reason:
            "the header painted over the bar at pinnedY "
            "${headers.first.pinnedY}",
      );
    }

    expect(
      pushUpFrames,
      greaterThan(0),
      reason:
          "no frame had a negative pinnedY, so this test asserted nothing; "
          "the harness has stopped exercising the push-up",
    );
  });

  // ------------------------------------------------------------------
  // T2: the painted band, every frame.
  // ------------------------------------------------------------------

  testWidgets("the painted band never starts above the sliver's origin", (
    tester,
  ) async {
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(
      Harness(key: key, initialSections: const <String>["A", "B"]),
    );
    await tester.pumpAndSettle();

    key.currentState!.select(const <String>["B"]);
    await tester.pump();

    var pushUpFrames = 0;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      final render = renderOf(tester);
      final headers = render.debugStickyHeaders;
      if (headers.isNotEmpty && headers.first.pinnedY < 0) {
        pushUpFrames++;
      }
      // Iterate the PAINTED set, never `debugStickyHeaders`: Pass B also
      // skips an unmounted header and one pushed past `paintExtent`, so a
      // key from the computed set can be absent from the band map.
      for (final paintedKey in render.debugLastPaintedStickyKeys) {
        expect(
          render.debugLastPaintedStickyBands[paintedKey]!.top,
          greaterThanOrEqualTo(-0.01),
          reason: "$paintedKey painted above the origin at frame $i",
        );
      }
    }

    expect(
      pushUpFrames,
      greaterThan(0),
      reason: "the loop never saw a negative pinnedY, so it asserted nothing",
    );
  });

  // ------------------------------------------------------------------
  // T3: the half a viewport clip cannot reach.
  // ------------------------------------------------------------------

  testWidgets("a retiring header does not bleed onto a PRECEDING sliver", (
    tester,
  ) async {
    // The surface is pinned so the geometry is load-bearing rather than
    // incidental: the viewport is kViewport tall, and what REMAINS after
    // A leaves (the banner plus B's block) still overflows it. On the
    // default 800x600 surface it does not, the viewport stops clipping
    // before the push-up begins, and the test silently degrades into T2.
    await tester.binding.setSurfaceSize(const Size(400, kViewport + kBar));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(
      Harness(
        key: key,
        initialSections: const <String>["A", "B"],
        // Tall enough to scroll, so the viewport's own clip IS active and
        // this test is not a duplicate of T2.
        perSection: 6,
        precedingSliver: true,
      ),
    );
    await tester.pumpAndSettle();

    key.currentState!.select(const <String>["B"]);
    await tester.pump();

    // Counted separately from plain push-up frames: the tree shrinks as A
    // leaves, and once it fits the viewport again `hasVisualOverflow` goes
    // false. What makes this test distinct from T2 is that at least one
    // push-up frame happens while the viewport IS clipping and the header
    // is still drawn over the preceding sliver's band, which no geometry
    // flag can prevent.
    var clippedPushUpFrames = 0;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      final render = renderOf(tester);
      final headers = render.debugStickyHeaders;
      if (headers.isNotEmpty &&
          headers.first.pinnedY < 0 &&
          render.geometry!.hasVisualOverflow) {
        clippedPushUpFrames++;
      }
      for (final paintedKey in render.debugLastPaintedStickyKeys) {
        expect(
          render.debugLastPaintedStickyBands[paintedKey]!.top,
          greaterThanOrEqualTo(-0.01),
          reason: "$paintedKey bled onto the preceding sliver at frame $i",
        );
      }
    }

    expect(
      clippedPushUpFrames,
      greaterThan(0),
      reason:
          "setup: no frame combined a negative pinnedY with an ACTIVE "
          "viewport clip, so this test collapsed into T2",
    );
  });

  // ------------------------------------------------------------------
  // T4: L25.1's no-clip fast path must survive.
  // ------------------------------------------------------------------

  testWidgets("a settled header paints its whole box and pushes no clip", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, kViewport + kBar));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(
      Harness(key: key, initialSections: const <String>["A", "B"]),
    );
    await tester.pumpAndSettle();

    final render = renderOf(tester);
    expect(
      render.debugStickyHeaders.single.pinnedY,
      0.0,
      reason: "setup: at rest the first root pins flush at the band top",
    );

    // (a) The band is the child's whole box: no top cut, and a bottom at
    // the child's own height rather than at the paint region's edge.
    expect(render.debugLastPaintedStickyKeys, contains("section:A"));
    expect(
      render.debugLastPaintedStickyBands["section:A"],
      const Rect.fromLTRB(0, 0, 400, kHeaderExtent),
    );

    // (b) The assertion that actually guards L25.1. The band alone cannot:
    // at rest `bottomCut` and `child.size.height` coincide, so the clipped
    // and unclipped arms would record the same rect.
    expect(
      tester.layers.whereType<ClipRectLayer>(),
      isEmpty,
      reason:
          "a settled header must take the no-clip arm; with RepaintBoundary "
          "rows a clip costs a ClipRectLayer per header per paint",
    );
  });

  // ------------------------------------------------------------------
  // T5: the bottom cut is unchanged.
  // ------------------------------------------------------------------

  testWidgets("an entering header is painted only as tall as it currently is", (
    tester,
  ) async {
    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(
      Harness(key: key, initialSections: const <String>["B"]),
    );
    await tester.pumpAndSettle();

    // A enters ABOVE B, so it owns the band from its first frame.
    key.currentState!.select(const <String>["A", "B"]);
    await tester.pump();

    var enteringFrames = 0;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      final render = renderOf(tester);
      final controller = key.currentState!.controller!;
      if (!render.debugLastPaintedStickyKeys.contains("section:A")) {
        continue;
      }
      final current = controller.getCurrentExtent("section:A");
      if (current >= kHeaderExtent) {
        continue;
      }
      enteringFrames++;

      // Stated against the controller's animated extent, not against
      // `min(sticky.extent, paintExtent - pinnedY)`: restating the
      // implementation's own expression would make this true by
      // construction and blind to the `sticky.extent` term being dropped.
      expect(
        render.debugLastPaintedStickyBands["section:A"]!.height,
        moreOrLessEquals(current, epsilon: 0.01),
        reason: "an entering header must not paint at its settled height",
      );
    }

    expect(
      enteringFrames,
      greaterThan(0),
      reason:
          "setup: no frame caught A mid-enter (current extent below its "
          "settled height), so this test asserted nothing",
    );
  });
}
