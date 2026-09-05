/// Tests for the lane span expansion plan: a laned item occupies every
/// consecutive lane above its own that no overlapping cluster member
/// holds, both geometry rules measure that whole BAND, and the
/// content-sized cluster term holds a band an exiting member is still
/// blocking.
///
/// Source: `plans/2026-09-05-lane-span-expansion-plan.md`, the Testing
/// Plan section (anchor `testing-plan`). Case names are the plan's names
/// VERBATIM.
///
/// Every case failed at the assertion marked TARGET against Landing
/// Order step 1's tree, the pure restructuring where the store carries a
/// span array and every span in it is 1, with every setup sanity
/// assertion before it passing.
///
/// Clock cadence: a case installs, pumps once with no duration (the
/// install frame; a ticker's first tick reports elapsed zero), then pumps
/// durations, so "at 100ms" means that second pump.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// itemEnterExit alone. trackResize is ZERO on purpose: a content-sized
/// row then measures the cluster term ITSELF on every frame rather than a
/// trackResize interpolation toward it, which is what lets T13 read the
/// term's own value mid-ramp.
const BoardAnimationStyle _exitOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _zero,
  itemEnterExit: _ms200,
  makeRoom: _zero,
);

/// itemSlide alone, which is the family a re-lane and a span-only change
/// both ride. Everything else is off, so the frames T7 reads carry the
/// FLIP and nothing beside it.
const BoardAnimationStyle _slideOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms200,
  itemEnterExit: _zero,
  makeRoom: _zero,
);

/// trackResize alone. itemEnterExit is ZERO so a removal retires in the
/// frame it is made and the row's TARGET steps, leaving the frames
/// between as the trackResize interpolation toward it.
const BoardAnimationStyle _resizeOnly = BoardAnimationStyle(
  trackResize: _ms200,
  itemSlide: _zero,
  itemEnterExit: _zero,
  makeRoom: _zero,
);

/// FIXED-LANE: eight 20px rows (the SWEEP axis), seven 40px columns
/// carrying the lane extent (the LANE axis, fixed). A four-lane cluster
/// slices a column into `(40 - 4) / 4 = 9`, so one slice is 9, three are
/// 27 and lane 1's origin is `4 + 9 = 13` from the column's leading edge.
BoardController<String, _Item> _fixedLane(
  WidgetTester tester, {
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(8, 20.0)),
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 40.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// CONTENT-LANE: six content-sized rows carrying the lane extent (the
/// LANE axis), seven 40px columns (the SWEEP axis). The 80.0 is
/// `LazyContentAxis`'s ESTIMATE for an unmeasured track and not a floor,
/// so it never enters the numbers below; the cellBuilder's 20 is what a
/// row measures with no cluster in it.
BoardController<String, _Item> _contentLane(
  WidgetTester tester, {
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
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
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  void Function(BoardItemView<String, _Item> view)? onItemView,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 280.0,
          height: 300.0,
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
              onItemView?.call(item);
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

/// THE AC1 SET as ROW intervals in column 2, for the FIXED-LANE fixture:
/// A [0, 7), B [1, 4), C [2, 4), D [2, 4), E [4, 6). The resolve assigns
/// A 0, B 1, C 2, D 3, E 1 with laneCount 4 for all five; C and D share
/// an interval and are separated by the sort's id tie-break, which is why
/// they are added in that order.
void _addAc1Rows(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 7),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 2, rowSpan: 2),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 2, colStart: 2, rowSpan: 2),
  );
  controller.addItem(
    const _Item("e"),
    const BoardSpan(rowStart: 4, colStart: 2, rowSpan: 2),
  );
}

/// THE AC1 SET as COLUMN intervals in row 2, for the CONTENT-LANE
/// fixture. Same five intervals, same assignment; the sweep axis is the
/// columns there.
void _addAc1Cols(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 2, colStart: 0, colSpan: 7),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 2, colSpan: 2),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 2, colStart: 2, colSpan: 2),
  );
  controller.addItem(
    const _Item("e"),
    const BoardSpan(rowStart: 2, colStart: 4, colSpan: 2),
  );
}

double _rowExtent(WidgetTester tester, int row) {
  return tester.getRect(find.byKey(_cellKey(row, 0))).height;
}

double _width(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(_itemKey(key))).width;
}

/// Records every structural notification, copying each key set so a later
/// mutation cannot rewrite what was already delivered. The listener is
/// removed on tear-down, before the controller's own, which is what keeps
/// `dispose`'s empty-listener assert satisfied.
List<Set<String>?> _logStructural(BoardController<String, _Item> controller) {
  final log = <Set<String>?>[];
  void listener(Set<String>? affectedKeys) {
    log.add(affectedKeys == null ? null : Set<String>.of(affectedKeys));
  }

  controller.addStructuralListener(listener);
  addTearDown(() {
    controller.removeStructuralListener(listener);
  });
  return log;
}

/// F, the item that takes the lane E's band reached into: the same
/// interval as E, one lane above it. Adding it is a SPAN-ONLY change for
/// E, and that is the whole point of the interval. F at rows [3, 6)
/// instead opens a FIFTH lane, because nothing has ended at row 3, so
/// E's laneCount moves with its span and the change is no longer
/// span-only; that is the perturbation the sanity assertions below are
/// shown to fail against.
void _addF(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("f"),
    const BoardSpan(rowStart: 4, colStart: 2, rowSpan: 2),
  );
}

void main() {
  // T4 (AC2). Falsification: red against step 1's tree, where E measures
  // one slice of 9 rather than the three its band covers.
  testWidgets("a laned item paints its whole band on a fixed lane axis", (
    tester,
  ) async {
    final controller = _fixedLane(tester);
    _addAc1Rows(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    // Setup sanity, each falsifiable: the band arithmetic below is
    // written against THIS assignment. Perturbing E's interval to rows
    // [3, 6) moves it to lane 4 and takes laneCount to 5, which is the
    // perturbation that reddens these three.
    expect(controller.laneOf("a"), 0);
    expect(controller.laneOf("e"), 1);
    expect(controller.laneCountOf("e"), 4);

    // TARGET: E's band is lanes 1 to 3, three slices of 9.
    expect(controller.laneSpanOf("e"), 3);
    final e = tester.getRect(find.byKey(_itemKey("e")));
    final frame = tester.getRect(find.byKey(_frameKey));
    expect(e.width, closeTo(27.0, 0.01));
    // P4's ORIGIN half: the span enters the extent and NOT the lead, so
    // an expanded item still starts at its own lane's origin,
    // `4 + 1 * 9` past column 2's leading edge. Green before the change
    // as well as after, which is exactly what it is here to pin: a span
    // leaked into the origin would move this to 80 + 4 and leave the
    // width right.
    expect(e.left - frame.left, closeTo(93.0, 0.01));

    // A is blocked by B one lane up and keeps one slice.
    expect(controller.laneSpanOf("a"), 1);
    expect(
      tester.getSize(find.byKey(_itemKey("a"))).width,
      closeTo(9.0, 0.01),
    );
  });

  // T5 (AC3). Falsification: the first two TARGET assertions are red
  // against step 1's tree, where E measures one lane extent of 18. The
  // third is GREEN there, which is the point of asserting it: G7 says a
  // settled content-sized track measures exactly what it measured
  // before, and the C7 rewrite has to leave it alone.
  testWidgets(
    "a laned item paints its whole band on a content-sized lane axis and "
    "the track measures the same",
    (tester) async {
      final controller = _contentLane(tester);
      _addAc1Cols(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();

      // Setup sanity: the cluster is the four-lane one the 76 below is
      // an accident of otherwise.
      expect(controller.laneOf("e"), 1);
      expect(controller.laneCountOf("e"), 4);

      // TARGET: three lane extents for E, one for A.
      expect(controller.laneSpanOf("e"), 3);
      expect(
        tester.getSize(find.byKey(_itemKey("e"))).height,
        closeTo(54.0, 0.01),
      );
      expect(
        tester.getSize(find.byKey(_itemKey("a"))).height,
        closeTo(18.0, 0.01),
      );
      // G7: lanePadding + laneCount * laneExtent, unchanged.
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));
      // A row with no cluster keeps its cells-only measurement, so the
      // 76 is the term and not the frame.
      expect(_rowExtent(tester, 0), closeTo(20.0, 0.01));
    },
  );

  // T6 (AC5). C6's third term in the change accumulator is what puts E
  // in the key set: E's lane PAIR is identical before and after, so on a
  // two-term test the accumulator never hears about it. Falsification:
  // red on the baseline, where E's span never changes and E is absent
  // from both key sets.
  testWidgets("a span-only change names the item in affectedKeys", (
    tester,
  ) async {
    final controller = _fixedLane(tester);
    _addAc1Rows(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    expect(controller.laneSpanOf("e"), 3);

    final log = _logStructural(controller);
    _addF(controller);

    // Setup sanity, each falsifiable: F took lane 2, the lane E's band
    // reached into, and E's own lane pair is untouched, so the change is
    // a SPAN change and nothing else. F at rows [3, 6) reddens the lane
    // count at 5; F at rows [0, 5) reddens E's own lane at 2.
    expect(controller.laneOf("f"), 2);
    expect(controller.laneOf("e"), 1);
    expect(controller.laneCountOf("e"), 4);

    // TARGET: the band closed, and the notification names E.
    expect(controller.laneSpanOf("e"), 1);
    expect(log, hasLength(1));
    expect(log.single, contains("e"));

    log.clear();
    controller.removeItem("f");

    // TARGET: the band reopened, and that notification names E too.
    expect(controller.laneSpanOf("e"), 3);
    expect(log, hasLength(1));
    expect(log.single, contains("e"));
    await tester.pumpAndSettle();
  });

  // T7 (AC6). AC6's own wording names `relaneDeltaOf` for the second
  // assertion; that reader returns a record's LEAD, and E's lane origin
  // does not move here (lane 1 of 4 before and after), so it is
  // `Offset.zero` at every frame and cannot carry it. The plan's Open
  // Questions Q1 records the substitution, acknowledged by the
  // requirements author: `extentDeltaOf`, which observes the motion the
  // criterion is about. Falsification: red on the baseline, where E is 9
  // at every frame and no slide is installed at all, the both-zero
  // early-out returning on a lead delta and an extent delta that are
  // both zero.
  testWidgets("a span-only change animates on the itemSlide clock", (
    tester,
  ) async {
    final controller = _fixedLane(tester, style: _slideOnly);
    _addAc1Rows(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    expect(_width(tester, "e"), closeTo(27.0, 0.01));

    _addF(controller);
    await tester.pump();

    // Setup sanity: the MODEL already carries the cut, so the widths
    // below are the FLIP's and not the model's.
    expect(controller.laneSpanOf("e"), 1);

    // TARGET: 27 at the install frame, halfway at 100ms, one slice at
    // 200ms, on the itemSlide clock.
    expect(_width(tester, "e"), closeTo(27.0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "e"), closeTo(18.0, 0.5));
    expect(
      controller.anim.extentDeltaOf(controller.idOfKey("e")).dx,
      isNot(closeTo(0.0, 0.01)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "e"), closeTo(9.0, 0.01));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.extentDeltaOf(controller.idOfKey("e")), Offset.zero);
    await tester.pumpAndSettle();
  });

  // T11 (AC10). The view is where an `itemBuilder` reads the band, and
  // it is CAPTURED at construction from the controller's own reads.
  // Falsification: red before Landing Order step 1 (the field does not
  // exist) and red at step 1 and against the baseline, where both views
  // report 1.
  testWidgets("the item view carries the span", (tester) async {
    final controller = _fixedLane(tester);
    _addAc1Rows(controller);
    final views = <String, BoardItemView<String, _Item>>{};
    await tester.pumpWidget(
      _board(
        controller,
        onItemView: (view) {
          views[view.key] = view;
        },
      ),
    );
    await tester.pumpAndSettle();

    // Setup sanity, falsifiable: both views saw the SETTLED resolve, so
    // the spans below are the resolver's and not a pre-flush default.
    expect(views["e"]!.laneCount, 4);
    expect(views["a"]!.laneCount, 4);

    // TARGET: E's band is three lanes and A's is one.
    expect(views["e"]!.laneSpan, 3);
    expect(views["a"]!.laneSpan, 1);
  });

  // T10 (AC9). G5 applied to the new field: a survivor must not widen
  // into a lane a chip is still painting in, for the length of the exit
  // ramp.
  //
  // What CARRIES that is not the expansion but the registration: an
  // animated exit keeps the id registered until its settle, so no
  // survivor's rectangle changes at the removal and the bucket is never
  // re-resolved while F is exiting. Measured, not argued: a probe that
  // reports every `_expandCluster` call seeing an exiting member printed
  // nothing for this case and nothing for the whole of `test/board`.
  // The plan names a scratch variant whose `_expandCluster` drops an
  // occupant for which `_store.isExiting` is true; that variant leaves
  // this case and the whole board suite GREEN, because the expansion
  // never runs on an exiting cluster at all.
  //
  // Falsification: the first half is red against a SYNCHRONOUS retire
  // (`itemEnterExit` zero), where E reads span 3 and paints 27 at the
  // removal frame and at 100ms; the second half is red against Landing
  // Order step 1's tree, where E reads 1 and never reaches 27.
  testWidgets("an exiting item holds the lane it blocks", (tester) async {
    final controller = _fixedLane(tester, style: _exitOnly);
    _addAc1Rows(controller);
    _addF(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    // Setup sanity: F holds lane 2 and E is cut to one slice, which is
    // T6's post-add state.
    expect(controller.laneOf("f"), 2);
    expect(controller.laneSpanOf("e"), 1);
    expect(_width(tester, "e"), closeTo(9.0, 0.01));

    controller.removeItem("f");
    await tester.pump();

    // Setup sanity, falsifiable: F is EXITING rather than gone. An
    // itemEnterExit of zero retires it in this pump and reddens this.
    expect(controller.anim.isExitingItem(controller.idOfKey("f")), isTrue);

    // TARGET, first half: F holds the lane it blocks for the whole ramp,
    // so E stays at one slice.
    expect(controller.laneSpanOf("e"), 1);
    expect(_width(tester, "e"), closeTo(9.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.laneSpanOf("e"), 1);
    expect(_width(tester, "e"), closeTo(9.0, 0.01));

    // TARGET, second half: at the settle the band opens. It STEPS, which
    // is N1: the settle is not a mutation site, so nothing captures a
    // rectangle to FLIP from.
    await tester.pumpAndSettle();
    expect(controller.laneSpanOf("e"), 3);
    expect(_width(tester, "e"), closeTo(27.0, 0.01));
  });

  // T12 (G6, C7). GREEN on the baseline and green after, which is what
  // it is for: C7 rewrites the formula every one of these measurements
  // goes through, and this is the case that shows the rewrite is
  // IDENTICAL when every span is 1. It pins C7's identity half only; the
  // discriminating half is T13.
  testWidgets("a lane count change still animates a content-sized track", (
    tester,
  ) async {
    final controller = _contentLane(tester, style: _resizeOnly);
    // Three MUTUALLY overlapping column intervals in row 2, so each
    // member is blocked by the one directly above it and every span is 1.
    controller.addItem(
      const _Item("p"),
      const BoardSpan(rowStart: 2, colStart: 0, colSpan: 5),
    );
    controller.addItem(
      const _Item("q"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
    );
    controller.addItem(
      const _Item("r"),
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    // Setup sanity, each falsifiable: three lanes deep, and the two
    // members that COULD expand do not, which is what makes this the
    // identity half. R's own span is not asserted: it is the cluster's
    // deepest member, so `lane + span <= laneCount` forces 1 and the
    // assertion could not fail in the direction it would claim. T3's
    // fuzz owns that invariant.
    expect(controller.laneCountOf("q"), 3);
    expect(controller.laneSpanOf("p"), 1);
    expect(controller.laneSpanOf("q"), 1);
    expect(_rowExtent(tester, 2), closeTo(58.0, 0.01));

    // TARGET: the row decays from `4 + 3 * 18` to `4 + 2 * 18` on the
    // trackResize clock.
    controller.removeItem("r");
    await tester.pump();
    expect(controller.laneCountOf("q"), 2);
    expect(_rowExtent(tester, 2), closeTo(58.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_rowExtent(tester, 2), closeTo(49.0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_rowExtent(tester, 2), closeTo(40.0, 0.01));
    await tester.pumpAndSettle();
  });

  // T13 (C7). The DISCRIMINATING assertion is the one at 100ms: the
  // install-frame 76 and the settled 58 hold with or without C7's span
  // factor. Against a scratch variant of C7 that keeps
  // `progress * laneExtent` with no span factor, E contributes 36
  // instead of 72, the term is `54 + 18p`, and the 100ms reading is
  // `4 + 63 = 67`.
  testWidgets(
    "an exiting top-lane member does not shrink a track under an "
    "expanded band",
    (tester) async {
      final controller = _contentLane(tester, style: _exitOnly);
      _addAc1Cols(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));

      controller.removeItem("d");
      await tester.pump();

      // Setup sanity, each falsifiable: D is EXITING rather than gone
      // (an itemEnterExit of zero would retire it in this pump and
      // redden this), D's assignment is held whole so the cluster is
      // still four lanes deep, and E's band is the three lanes the term
      // has to hold.
      expect(controller.anim.isExitingItem(controller.idOfKey("d")), isTrue);
      expect(controller.laneCountOf("e"), 4);
      expect(controller.laneSpanOf("e"), 3);

      // TARGET: the row holds 76 for the whole ramp. D's ceiling decays
      // from 72 to 54 while E's stays at `1 * 18 + 3 * 18 = 72`.
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));

      // After the settle the cluster is three lanes deep, E's band is
      // two, and the deepest ceiling is `1 * 18 + 2 * 18 = 54`.
      await tester.pumpAndSettle();
      expect(controller.laneCountOf("e"), 3);
      expect(controller.laneSpanOf("e"), 2);
      expect(_rowExtent(tester, 2), closeTo(58.0, 0.01));
    },
  );

  // AUDIT A (G5, C3). T10 above never re-resolves column 2's bucket while
  // F is exiting, so an `_expandCluster` that skipped exiting members
  // would leave it green: the registration alone carries it. This case
  // dirties the bucket MID-EXIT, so the expansion runs with F in it. Red
  // at span 3 / width 27 after the addItem against a probe that drops
  // exiting occupants from the lane cursors.
  testWidgets(
    "a re-resolve during an exit still counts the exiting item as an "
    "occupant",
    (tester) async {
      final controller = _fixedLane(tester, style: _exitOnly);
      _addAc1Rows(controller);
      _addF(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      expect(controller.laneSpanOf("e"), 1);

      controller.removeItem("f");
      await tester.pump();
      final fId = controller.idOfKey("f");
      // Setup sanity, falsifiable: F is EXITING rather than gone.
      expect(controller.anim.isExitingItem(fId), isTrue);

      // The re-resolve: G joins the bucket at rows [0, 1), overlapping A
      // only. It takes lane 1 and B reuses that lane after it ends, so
      // every other assignment is unchanged and laneCount stays 4.
      controller.addItem(
        const _Item("g"),
        const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 1),
      );
      await tester.pump();
      // Setup sanity: the bucket WAS re-resolved (G is laned) and F still
      // holds lane 2 through it.
      expect(controller.laneOf("g"), 1);
      expect(controller.laneCountOf("e"), 4);
      expect(controller.laneOfId(fId), 2);

      // TARGET: the exiting F is an occupant of the lane above E, so E's
      // band is still one slice.
      expect(controller.laneSpanOf("e"), 1);
      expect(_width(tester, "e"), closeTo(9.0, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.laneSpanOf("e"), 1);
      expect(_width(tester, "e"), closeTo(9.0, 0.01));

      await tester.pumpAndSettle();
      expect(controller.laneSpanOf("e"), 3);
      expect(_width(tester, "e"), closeTo(27.0, 0.01));
    },
  );

  // AUDIT B (the reported scene). The week view example's own lattice at
  // its 30-minute increment: a 40px header row, 48 half-hour rows, a 56px
  // gutter and seven 90px days with the day axis as the lane axis and no
  // lane padding. Tuesday holds orange 09:30-13:00, teal 10:00-11:30,
  // green and yellow 10:30-11:30, pink 11:00-11:30 and purple 11:30-12:45
  // (two and a half rows, so a fractional span). The sweep lanes them
  // 0, 1, 2, 3, 4 and 1, five lanes, and purple's band runs from lane 1
  // to the column's trailing edge. Red at width 18 against a resolver
  // writing span 1 everywhere, which is what the screenshot showed.
  testWidgets("the week view example's Tuesday scene widens the purple item", (
    tester,
  ) async {
    const header = 40.0;
    const gutter = 56.0;
    const rowHeight = 16.0;
    const dayWidth = 90.0;
    const increment = 30;
    BoardSpan spanOf(int startMinute, int durationMinutes) {
      final startRows = startMinute / increment;
      final durationRows = durationMinutes / increment;
      final rowStart = startRows.floor();
      final rowSpan = durationRows.floor();
      return BoardSpan(
        rowStart: 1 + rowStart,
        colStart: 2,
        rowSpan: rowSpan,
        rowFraction: startRows - rowStart,
        rowSpanFraction: durationRows - rowSpan,
      );
    }

    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(
        axis: ExplicitAxis(<double>[
          header,
          ...List<double>.filled(48, rowHeight),
        ]),
        frozenStart: 1,
      ),
      columns: BoardAxisConfig(
        axis: ExplicitAxis(<double>[
          gutter,
          ...List<double>.filled(7, dayWidth),
        ]),
        frozenStart: 1,
        laneExtent: dayWidth,
      ),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(const _Item("orange"), spanOf(9 * 60 + 30, 210));
    controller.addItem(const _Item("teal"), spanOf(10 * 60, 90));
    controller.addItem(const _Item("green"), spanOf(10 * 60 + 30, 60));
    controller.addItem(const _Item("yellow"), spanOf(10 * 60 + 30, 60));
    controller.addItem(const _Item("pink"), spanOf(11 * 60, 30));
    controller.addItem(const _Item("purple"), spanOf(11 * 60 + 30, 75));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _frameKey,
              width: 700.0,
              height: 900.0,
              child: Board<String, _Item>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return const SizedBox.expand();
                },
                itemBuilder: (context, item) {
                  return ColoredBox(
                    key: _itemKey(item.key),
                    color: const Color(0xFF7E57C2),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Setup sanity: the assignment the screenshot shows, five lanes with
    // purple back in lane 1 under teal.
    expect(controller.laneOf("orange"), 0);
    expect(controller.laneOf("teal"), 1);
    expect(controller.laneOf("green"), 2);
    expect(controller.laneOf("yellow"), 3);
    expect(controller.laneOf("pink"), 4);
    expect(controller.laneOf("purple"), 1);
    expect(controller.laneCountOf("purple"), 5);

    // TARGET: purple spans lanes 1 to 4; the five stacked items keep one
    // slice each.
    const slice = dayWidth / 5;
    expect(controller.laneSpanOf("purple"), 4);
    expect(_width(tester, "purple"), closeTo(4 * slice, 0.01));
    for (final key in <String>["orange", "teal", "green", "yellow", "pink"]) {
      expect(controller.laneSpanOf(key), 1);
      expect(_width(tester, key), closeTo(slice, 0.01));
    }
    // Purple's lead is lane 1's origin inside Tuesday, and its trailing
    // edge is the column's.
    final frameLeft = tester.getRect(find.byKey(_frameKey)).left;
    final purple = tester.getRect(find.byKey(_itemKey("purple")));
    expect(purple.left - frameLeft, closeTo(gutter + dayWidth + slice, 0.01));
    expect(purple.right - frameLeft, closeTo(gutter + 2 * dayWidth, 0.01));
  });
}
