/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 7, the item plane. The second case's name
/// changed with the vicinity redesign: the ordinal ignores lanes, so the
/// old DERIVED name "a lane change moves an item's vicinity" described the
/// rejected lane-keyed formula and now asserts the OPPOSITE.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

/// A month-calendar-shaped board: content-sized week rows carrying a lane
/// extent, uniform day columns.
BoardController<String, _Item> _lanedController(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(6, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  double width = 280.0,
  double height = 400.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return SizedBox(
                key: _cellKey(cell.row, cell.col),
                width: 40.0,
                height: 20.0,
              );
            },
            itemBuilder: (context, item) {
              return ColoredBox(
                key: _itemKey(item.key),
                color: const Color(0xFF4CAF50),
              );
            },
          ),
        ),
      ),
    ),
  );
}

BoardSpan _chip(int row, int colStart, int colSpan) {
  return BoardSpan(rowStart: row, colStart: colStart, colSpan: colSpan);
}

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

void main() {
  // DERIVED name. No AC; item_plane_test.dart is listed under the tests not
  // tied to one criterion.
  // Asserts: item vicinities are disjoint from cell vicinities, and the
  // three collision configurations of the vicinity redesign each resolve
  // to DISTINCT vicinities: two clusters in one track, and non-laned
  // items sharing a track.
  // Falsification: the rejected lane-keyed formula gives the Mon-Tue and
  // Thu-Fri chips one vicinity (both lane 0) and one of them never
  // builds.
  testWidgets("item vicinities are disjoint from cell vicinities", (
    tester,
  ) async {
    final controller = _lanedController(tester);
    // Two NON-overlapping chips in one week row: two clusters, both lane
    // 0 in the dead design.
    controller.addItem(const _Item("mon"), _chip(1, 0, 2));
    controller.addItem(const _Item("thu"), _chip(1, 3, 2));
    await tester.pumpWidget(_board(controller));

    // Both chips exist as children: the collision would drop one.
    expect(find.byKey(_itemKey("mon")), findsOneWidget);
    expect(find.byKey(_itemKey("thu")), findsOneWidget);
    // And both share lane 0, which is what makes injectivity the
    // ordinal's job rather than the lane's.
    expect(controller.laneOf("mon"), 0);
    expect(controller.laneOf("thu"), 0);

    // Disjointness from the cell band: every item vicinity's xIndex sits
    // past every cell column.
    final viewport = _viewport(tester);
    var itemVicinities = 0;
    viewport.visitChildren((child) {
      final vicinity =
          (child.parentData! as TwoDimensionalViewportParentData).vicinity;
      if (vicinity.xIndex >= 7) {
        itemVicinities++;
      }
    });
    expect(itemVicinities, 2);
  });

  // DERIVED name, RENAMED with the vicinity redesign: the ordinal ignores
  // lanes, so a pure lane change REBUILDS IN PLACE, and what moves a
  // vicinity is an ordinal shift.
  // Asserts: adding an overlapping chip re-lanes an existing one without
  // moving its vicinity; adding a chip ordered BEFORE it shifts its
  // ordinal and does move it.
  // Falsification: a lane-keyed vicinity moves on the first add; an
  // ordinal that ignores the sort order fails the second half.
  testWidgets(
    "an ordinal shift moves an item's vicinity and a pure lane change "
    "does not",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(const _Item("a"), _chip(1, 3, 2));
      // A TALL item touching row 1's bucket while STARTING at row 0: rank
      // lists hold only the items whose primary start equals the track,
      // so this one must not occupy a row-1 ordinal slot. Without the
      // filter it would, and every row-1 ordinal below shifts by one.
      controller.addItem(
        const _Item("tall"),
        const BoardSpan(rowStart: 0, colStart: 6, rowSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      final idA = controller.idOfKey("a");
      expect(controller.vicinityOrdinalOfId(idA), 0);
      expect(controller.laneOf("a"), 0);

      // An overlapping chip sorted AFTER a (same column start, larger
      // id): a's lane stays 0 while b takes lane 1, and a's ordinal is
      // untouched.
      controller.addItem(const _Item("b"), _chip(1, 3, 2));
      await tester.pump();
      expect(controller.laneOf("b"), 1);
      expect(controller.laneOf("a"), 0);
      expect(controller.vicinityOrdinalOfId(idA), 0);

      // A chip starting EARLIER on the sweep axis sorts before a: a's
      // ordinal shifts, which IS a vicinity change.
      controller.addItem(const _Item("early"), _chip(1, 0, 1));
      await tester.pump();
      expect(controller.vicinityOrdinalOfId(idA), 1);
      // All three still build: the shift moved a's vicinity, and its
      // element with it, not dropped it.
      expect(find.byKey(_itemKey("a")), findsOneWidget);
      expect(find.byKey(_itemKey("b")), findsOneWidget);
      expect(find.byKey(_itemKey("early")), findsOneWidget);
    },
  );

  // DERIVED name. No AC.
  // Asserts: the two lane geometry modes produce the extents stated at
  // Components and State.
  // Falsification: a fixed-mode slice that ignores lanePadding, or a
  // content-mode item sized by the track instead of the laneExtent, lands
  // at the wrong rect.
  testWidgets("the two lane geometry modes produce the stated extents", (
    tester,
  ) async {
    // CONTENT-SIZED lane axis (the month shape): item height is exactly
    // laneExtent, top is track lead + padding + lane * laneExtent.
    final content = _lanedController(tester);
    content.addItem(const _Item("p"), _chip(0, 0, 2));
    content.addItem(const _Item("q"), _chip(0, 0, 2));
    await tester.pumpWidget(_board(content));
    final p = tester.getRect(find.byKey(_itemKey("p")));
    final q = tester.getRect(find.byKey(_itemKey("q")));
    expect(p.height, 18.0);
    expect(q.height, 18.0);
    // Track 0's lead is 0; padding 4; lanes 0 and 1.
    expect(p.top, 4.0);
    expect(q.top, 4.0 + 18.0);
    // The span axis takes the exact fractional endpoints: two columns of
    // 40 from column 0.
    expect(p.left, 0.0);
    expect(p.width, 80.0);

    // FIXED lane axis: the track's extent past the padding divides evenly
    // among the cluster's lanes.
    final fixed = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(
        axis: UniformAxis(6, 44.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      ),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(fixed.dispose);
    fixed.addItem(const _Item("r"), _chip(0, 0, 2));
    fixed.addItem(const _Item("s"), _chip(0, 0, 2));
    await tester.pumpWidget(_board(fixed));
    final r = tester.getRect(find.byKey(_itemKey("r")));
    final s = tester.getRect(find.byKey(_itemKey("s")));
    // (44 - 4) / 2 lanes = 20 each.
    expect(r.height, 20.0);
    expect(s.height, 20.0);
    expect(r.top, 4.0);
    expect(s.top, 24.0);
  });

  // DERIVED name. No AC; the incremental-resolve contract, which nothing
  // else pins, in BOTH arms of the flush because the counter counts either.
  // Asserts: a plain scroll frame leaves debugLaneBucketResolveCount
  // unchanged (the layout-head arm found the set empty), and a single
  // moveItem advances it by the number of LANE-AXIS buckets its old and
  // new spans occupy.
  // Falsification: a full re-resolve every layout fails the first
  // assertion.
  testWidgets(
    "a plain scroll frame resolves no lane buckets and a moveItem resolves the buckets its spans touch",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      controller.addItem(const _Item("b"), _chip(2, 0, 2));
      await tester.pumpWidget(_board(controller));
      final before = controller.debugLaneBucketResolveCount;

      // A pure paint-and-layout frame: nothing dirtied, nothing resolved.
      await tester.pump();
      expect(controller.debugLaneBucketResolveCount, before);

      // A move between lane-axis tracks dirties the OLD and NEW buckets.
      controller.moveItem("a", _chip(1, 0, 2));
      await tester.pump();
      expect(controller.debugLaneBucketResolveCount, before + 2);
    },
  );

  // DERIVED name. No AC; which arm did it, pinned separately.
  // Asserts: reading laneCountOf immediately after the moveItem, before
  // any pump, advances the counter and the following layout advances it
  // by 0, which is what shows the read-side flush exists and is not
  // double work.
  // Falsification: a layout-head-only resolve fails this case.
  testWidgets(
    "a laneCountOf read before any pump flushes the lane set and the following layout adds nothing",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));
      final before = controller.debugLaneBucketResolveCount;

      // INSIDE a batch: the structural notify is deferred, so the only
      // thing that can resolve before the read returns is the read
      // entry's own flush. Outside a batch the notify flushes first and
      // the read arm never decides, which made an earlier version of
      // this case unable to fail.
      controller.runBatch(() {
        controller.moveItem("a", _chip(1, 0, 2));
        expect(controller.laneCountOf("a"), 1);
        expect(controller.debugLaneBucketResolveCount, before + 2);
      });

      // ARM 1 at the next layout head finds the set empty.
      await tester.pump();
      expect(controller.debugLaneBucketResolveCount, before + 2);
    },
  );

  // DERIVED name. No AC; pins I7's z-order clause for the laning
  // exclusion: a non-laned item paints across its whole lane-axis extent
  // ABOVE the laned items in the same track, and hit-testing mirrors
  // paint.
  // Falsification: a plain (lane, id) order puts the non-laned item,
  // which holds lane 0, UNDER every later-id laned item, and the laned
  // chip takes the tap.
  testWidgets(
    "a non-laned item paints above the laned items in its track and "
    "takes the pointer",
    (tester) async {
      final controller = _lanedController(tester);
      final taps = <String>[];
      // The non-laned item FIRST, so its id is the lowest and a
      // (lane, id) order cannot pass by id accident.
      controller.addItem(
        const _Item("wide"),
        const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2, colSpan: 3),
      );
      controller.addItem(const _Item("a"), _chip(1, 0, 3));
      controller.addItem(const _Item("b"), _chip(1, 0, 3));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280.0,
                height: 400.0,
                child: Board<String, _Item>(
                  controller: controller,
                  cellBuilder: (context, cell) {
                    return const SizedBox(width: 40.0, height: 20.0);
                  },
                  itemBuilder: (context, item) {
                    return GestureDetector(
                      key: _itemKey(item.key),
                      onTap: () {
                        taps.add(item.key);
                      },
                      child: const ColoredBox(color: Color(0xFF4CAF50)),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Setup sanity: the rowSpan-2 item is excluded from laning and the
      // two chips cluster.
      expect(controller.isLanedId(controller.idOfKey("wide")), isFalse);
      expect(controller.isLanedId(controller.idOfKey("a")), isTrue);
      expect(controller.laneCountOf("a"), 2);

      // The chip's rect lies inside the non-laned item's rect, so the tap
      // point is covered by both.
      final chip = tester.getRect(find.byKey(_itemKey("a")));
      final wide = tester.getRect(find.byKey(_itemKey("wide")));
      expect(wide.contains(chip.center), isTrue);

      await tester.tapAt(chip.center);
      await tester.pump();
      expect(taps, <String>["wide"]);
    },
  );

  // DERIVED name. No AC; the fixed-lane-axis slice under a lanePadding
  // that exceeds the track's extent: the slice floors at zero instead of
  // going negative.
  // Falsification: the bare formula (extent - padding) / laneCount hands
  // layout a negative tight constraint, which throws in debug.
  testWidgets(
    "a lanePadding wider than a fixed track degrades to zero-extent "
    "lanes instead of throwing",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(
          axis: UniformAxis(6, 10.0),
          laneExtent: 18.0,
          lanePadding: 12.0,
        ),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(_itemKey("a"))).height, 0.0);
    },
  );

  // DERIVED name. No AC; maxLaneCountInBucket carries the same read-entry
  // flush as every other lane-value read, pinned inside a batch where the
  // deferred notify cannot mask its absence.
  // Falsification: a flushless forwarder reports the pre-move counts.
  testWidgets(
    "a maxLaneCountInBucket read inside a batch reports the moved item's "
    "buckets fresh",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      controller.addItem(const _Item("b"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));
      expect(controller.maxLaneCountInBucket(0), 2);

      controller.runBatch(() {
        controller.moveItem("b", _chip(2, 0, 2));
        expect(controller.maxLaneCountInBucket(0), 1);
        expect(controller.maxLaneCountInBucket(2), 1);
      });
    },
  );
}
