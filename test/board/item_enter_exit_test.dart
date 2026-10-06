/// The board's item enter and exit animations: an exiting item's place in
/// the index, hit-testing, retention and lanes, an entering item's ramp,
/// re-adding a key mid-exit, removing one mid-enter under a live or an off
/// itemEnterExit, and the settle's re-entrancy and layout.
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

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms240 = BoardAnimationSpec(
  duration: Duration(milliseconds: 240),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Enter/exit animate; everything else is off.
const BoardAnimationStyle _enterExitOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _zero,
  itemEnterExit: _ms300,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _lanedController(
  WidgetTester tester, {
  BoardAnimationStyle style = _enterExitOnly,
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
  ScrollController? vertical,
  double height = 400.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: height,
          child: Board<String, _Item>(
            controller: controller,
            verticalDetails: vertical == null
                ? const ScrollableDetails.vertical()
                : ScrollableDetails.vertical(controller: vertical),
            cellBuilder: (context, cell) {
              return const SizedBox(width: 40.0, height: 20.0);
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

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

BoardSpan _chip(int row, int colStart, int colSpan) {
  return BoardSpan(rowStart: row, colStart: colStart, colSpan: colSpan);
}

/// A laned controller with no board, holding `b` mid-enter on [_ms240]
/// and then restyled to [BoardAnimationStyle.disabled], which leaves the
/// enter's record to its next tick.
Future<BoardController<String, _Item>> _midEnterUnderOffFamily(
  WidgetTester tester,
) async {
  final controller = _lanedController(
    tester,
    style: const BoardAnimationStyle(
      trackResize: _zero,
      itemSlide: _zero,
      itemEnterExit: _ms240,
    ),
  );
  controller.addItem(const _Item("b"), _chip(0, 0, 2));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  final idB = controller.idOfKey("b");
  final anim = controller.anim;
  // Setup sanity 1: mid-enter, so a removal cannot take the retire of an
  // enter that never ticked.
  expect(anim.isEnteringItem(idB), isTrue);
  expect(anim.enterExitProgressOf(idB), greaterThan(0.0));
  expect(anim.enterExitProgressOf(idB), lessThan(1.0));
  controller.animationStyle = BoardAnimationStyle.disabled;
  // Setup sanity 2: the restyle left the enter in flight.
  expect(anim.isEnteringItem(idB), isTrue);
  return controller;
}

void main() {
  // AC8 exiting item, four consumers, plus a fifth assertion.
  // Asserts: absent from itemsAt; itemAt at its rect returns null; a live
  // neighbour's laneOf and laneCountOf are unchanged, because a LANE is
  // held whole until settle; and the track's rectOfCell extent, measured
  // one frame after the removeItem, is strictly GREATER than the extent
  // it settles to, which is the KEPT and SCALED form of the contribution
  // rule. The FIFTH assertion pins the other end of every KEPT rule:
  // after pumpAndSettle the neighbour's laneCountOf has DROPPED and
  // itemsIn over the retired span omits the key.
  // Falsification: dropping the contribution on the mutation frame snaps
  // straight to the settled extent; a settle that clears the bit and
  // releases the id without touching SpanIndex leaves the lane count at
  // its held value forever and fails only the fifth.
  testWidgets(
    "an exiting item leaves the index and hit-testing but keeps its lane "
    "and its contribution",
    (tester) async {
      final controller = _lanedController(tester);
      RenderBoardViewport<String> viewport() {
        return _viewport(tester);
      }

      controller.animationStyle = BoardAnimationStyle.disabled;
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      controller.addItem(const _Item("b"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));
      // Setup sanity: two lanes, and the track holds them: 2*18+4.
      expect(controller.laneCountOf("a"), 2);
      expect(viewport().rectOfCell(0, 0)!.height, 40.0);
      final bTop = tester.getRect(find.byKey(_itemKey("b"))).top;
      controller.animationStyle = _enterExitOnly;

      controller.removeItem("b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.itemsAt(0, 0), isNot(contains("b")));
      // Just inside the lane-1 slice, where b still paints.
      expect(viewport().itemAt(Offset(10.0, bTop + 1.0)), isNull);
      expect(controller.laneOf("a"), 0);
      expect(controller.laneCountOf("a"), 2);
      // KEPT and SCALED: greater than the settled 22, less than the held
      // 40.
      final midExtent = viewport().rectOfCell(0, 0)!.height;
      expect(midExtent, greaterThan(22.0));
      expect(midExtent, lessThan(40.0));

      await tester.pumpAndSettle();
      expect(controller.laneCountOf("a"), 1);
      expect(controller.itemsIn(0, 1, 0, 2), isNot(contains("b")));
    },
  );

  // AC16 exiting item off-window.
  // Asserts: the probe widget is findable mid-exit after its span is
  // scrolled past the cache region, and absent after pumpAndSettle. The
  // release is the sweep's no-obtain case, reached by the layout the
  // settle tick schedules through the prior-tick latch, which is why
  // pumpAndSettle and not a bare pump is what makes it true.
  // Falsification: an implementation that only clears keepAlive in a
  // layout that also obtains the vicinity leaves the probe findable
  // forever.
  testWidgets(
    "an exiting item stays mounted after its span scrolls out and is "
    "released at settle",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: _enterExitOnly,
      );
      addTearDown(controller.dispose);
      controller.addItem(const _Item("p"), _chip(0, 0, 2));
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(controller, vertical: vertical, height: 200.0),
      );
      // Let p's own ENTER settle first: removing a never-ticked enter is
      // the synchronous mid-enter retire, not an exit.
      await tester.pumpAndSettle();
      expect(find.byKey(_itemKey("p")), findsOneWidget);

      controller.removeItem("p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      vertical.jumpTo(2000.0);
      await tester.pump();
      // Mid-exit and far outside the window: still MOUNTED, not painted.
      expect(
        find.byKey(_itemKey("p"), skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(find.byKey(_itemKey("p"), skipOffstage: false), findsNothing);
    },
  );

  // DERIVED name. The retention map is keyed by vicinity, and an exiting
  // item's ordinal can shift mid-exit.
  // Asserts: after a rank insert on the exiting item's start track (a new
  // item whose span-axis start sorts earlier), the off-window exiting
  // item is STILL mounted, and still released at settle.
  // Falsification: retention that keeps obtaining the vicinity recorded
  // at exit time rebuilds it as the item that holds that ordinal NOW, so
  // the exiting child's widget is gone mid-exit.
  testWidgets(
    "an exiting item's retention follows its ordinal when a rank insert "
    "shifts it",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: _enterExitOnly,
      );
      addTearDown(controller.dispose);
      controller.addItem(const _Item("p"), _chip(0, 1, 1));
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(controller, vertical: vertical, height: 200.0),
      );
      await tester.pumpAndSettle();

      controller.removeItem("p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      vertical.jumpTo(2000.0);
      await tester.pump();
      // Setup sanity: retention holds the exiting item before the shift.
      expect(
        find.byKey(_itemKey("p"), skipOffstage: false),
        findsOneWidget,
      );

      // Sorts BEFORE p in row 0's rank bucket (span-axis start 0 is less
      // than 1), shifting p's ordinal from 0 to 1 mid-exit.
      controller.addItem(const _Item("q"), _chip(0, 0, 1));
      await tester.pump();
      expect(
        find.byKey(_itemKey("p"), skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(find.byKey(_itemKey("p"), skipOffstage: false), findsNothing);
    },
  );

  // DERIVED name. The same shift with the exiting item IN the window:
  // the retained entry must not overwrite the live occupant's id mapping.
  // Asserts: after the rank insert, itemAt at the NEW item's painted
  // center resolves the new item.
  // Falsification: an obtain that re-records the stale vicinity maps the
  // new item's child to the exiting id, which lays it out at the exiting
  // item's rect and makes itemAt skip it as exiting.
  testWidgets(
    "a rank insert mid-exit does not misattribute the live occupant of "
    "the old vicinity",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 90.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: _enterExitOnly,
      );
      addTearDown(controller.dispose);
      controller.addItem(const _Item("p"), _chip(0, 1, 1));
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();

      controller.removeItem("p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      controller.addItem(const _Item("q"), _chip(0, 0, 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final probe = tester.getRect(find.byKey(_itemKey("q"))).center;
      expect(_viewport(tester).itemAt(probe), "q");
      await tester.pumpAndSettle();
    },
  );

  // DERIVED name. No AC; the only assertion for what enterExitProgressOf
  // scales.
  // Asserts: mid-enter, the item's painted lane-axis extent is strictly
  // between 0 and laneExtent and its track's extent is strictly between
  // the no-item value and the settled one; on the SPAN axis its painted
  // width matches its span exactly at the same frame.
  // Falsification: laying an entering item out at full extent and merely
  // fading it fails the first pair; scaling both axes fails the span
  // half.
  testWidgets("an entering item's lane-axis extent ramps with its progress", (
    tester,
  ) async {
    final controller = _lanedController(tester);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    controller.addItem(const _Item("n"), _chip(0, 0, 2));
    await tester.pump();
    // 285 of 300ms: progress 0.95, where the ramping cluster term
    // (18p + 4) also exceeds the cells' 20.
    await tester.pump(const Duration(milliseconds: 285));
    final rect = tester.getRect(find.byKey(_itemKey("n")));
    expect(rect.height, greaterThan(0.0));
    expect(rect.height, lessThan(18.0));
    final trackExtent = _viewport(tester).rectOfCell(0, 0)!.height;
    expect(trackExtent, greaterThan(20.0));
    expect(trackExtent, lessThan(22.0));
    // The span axis is never scaled: two columns of 40 at every frame.
    expect(rect.width, 80.0);

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_itemKey("n"))).height, 18.0);
  });

  // DERIVED name. No AC; one of the two id-lifecycle cases.
  // Asserts: remove a key, pump to mid-exit, addItem the same key;
  // contains is true immediately, spanOf reports the NEW span,
  // laneCountOf on a neighbour is the live value, and after pumpAndSettle
  // exactly one child for that key remains.
  // Falsification: an implementation that allocates a second id without
  // retiring the first passes the first two assertions and fails the
  // last, because the old id's settle deletes the live key's mapping.
  // Since item 7D of the 2026-09-23 audit fixes the re-add brings the
  // exiting item back on its own id rather than retiring it
  // (board_lifecycle_fixes_test.dart pins the reversal); this case keeps
  // the one-incarnation contract.
  testWidgets("re-adding a key mid-exit leaves one incarnation of it", (
    tester,
  ) async {
    final controller = _lanedController(tester);
    controller.animationStyle = BoardAnimationStyle.disabled;
    controller.addItem(const _Item("a"), _chip(0, 0, 2));
    controller.addItem(const _Item("b"), _chip(0, 0, 2));
    await tester.pumpWidget(_board(controller));
    expect(controller.laneCountOf("a"), 2);
    controller.animationStyle = _enterExitOnly;

    controller.removeItem("b");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    controller.addItem(const _Item("b"), _chip(2, 0, 2));
    expect(controller.contains("b"), isTrue);
    expect(controller.spanOf("b"), _chip(2, 0, 2));
    expect(controller.laneCountOf("a"), 1);

    await tester.pumpAndSettle();
    expect(find.byKey(_itemKey("b"), skipOffstage: false), findsOneWidget);
  });

  // DERIVED name. No AC; the clearForId case.
  // Asserts: moveItem a key to install a slide, removeItem it inside the
  // same itemSlide duration with itemEnterExit zero so the id is released
  // at once, addItem a DIFFERENT key which under LIFO takes that id back,
  // and assert the new item's painted rect equals its structural rect on
  // the very next frame and that anim.hasActiveOffsets is false.
  // Falsification: without clearForId the new item paints at the dead
  // one's residual delta and hasActiveOffsets is true, so both halves
  // fail in the direction they claim.
  testWidgets("a recycled id carries no animation record", (tester) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms300,
        itemEnterExit: _zero,
      ),
    );
    addTearDown(controller.dispose);
    controller.addItem(const _Item("m"), _chip(0, 0, 2));
    await tester.pumpWidget(_board(controller));

    controller.moveItem("m", _chip(3, 0, 2));
    final recycledId = controller.idOfKey("m");
    expect(controller.anim.hasActiveOffsets, isTrue);
    controller.removeItem("m");
    controller.addItem(const _Item("n"), _chip(1, 2, 2));
    // Setup sanity: LIFO handed the new key the released id.
    expect(controller.idOfKey("n"), recycledId);

    await tester.pump();
    // Structural: row 1 of 50s, column 2 of 40s, two columns wide.
    expect(
      tester.getRect(find.byKey(_itemKey("n"))),
      const Rect.fromLTWH(80.0, 50.0, 80.0, 50.0),
    );
    expect(controller.anim.hasActiveOffsets, isFalse);
  });

  // DERIVED name. No AC; the first of the two mid-enter removal cases.
  // Asserts: the SETUP first, isEnteringItem true with
  // enterExitProgressOf strictly between 0 and 1; then on the frame of
  // the removeItem with no pump, isEnteringItem false, isExitingItem true
  // and enterExitProgressOf still reading the value it held before the
  // call. After pumpAndSettle the neighbour's laneCountOf has DROPPED and
  // itemsIn over the retired span omits the key.
  // Falsification: an exit installed from 1 fails only the third
  // assertion; a retire without an install reports 0 and fails it the
  // other way; a bit-0 set over the live bit 1 dies on the handler's
  // exactly-one-bit assert.
  testWidgets(
    "removing a key mid-enter exits from where it is and never sets both "
    "bits",
    (tester) async {
      final controller = _lanedController(tester);
      controller.animationStyle = BoardAnimationStyle.disabled;
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));
      controller.animationStyle = _enterExitOnly;

      controller.addItem(const _Item("b"), _chip(0, 0, 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final idB = controller.idOfKey("b");
      // Setup sanity: mid-enter.
      expect(controller.anim.isEnteringItem(idB), isTrue);
      final held = controller.anim.enterExitProgressOf(idB);
      expect(held, greaterThan(0.0));
      expect(held, lessThan(1.0));

      controller.removeItem("b");
      expect(controller.anim.isEnteringItem(idB), isFalse);
      expect(controller.anim.isExitingItem(idB), isTrue);
      expect(controller.anim.enterExitProgressOf(idB), closeTo(held, 1e-9));

      await tester.pumpAndSettle();
      expect(controller.laneCountOf("a"), 1);
      expect(controller.itemsIn(0, 1, 0, 2), isNot(contains("b")));
    },
  );

  // DERIVED name. No AC; the second of the two mid-enter removal cases.
  // Asserts: addItem and removeItem one key inside a single runBatch
  // under a non-zero family; hasLayoutDrivingAnimations is false on exit
  // from the batch and a following addItem of a DIFFERENT key takes the
  // same id, which is the synchronous retire of an enter that never
  // ticked.
  // Falsification: an implementation that installs a zero-length record
  // instead leaves the flag true for a frame.
  testWidgets("an add and a remove in one batch retire with no install", (
    tester,
  ) async {
    final controller = _lanedController(tester);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    late int xId;
    controller.runBatch(() {
      controller.addItem(const _Item("x"), _chip(0, 0, 2));
      xId = controller.idOfKey("x");
      controller.removeItem("x");
    });
    expect(controller.anim.hasLayoutDrivingAnimations, isFalse);
    controller.addItem(const _Item("y"), _chip(2, 0, 2));
    expect(controller.idOfKey("y"), xId);
    await tester.pumpAndSettle();
  });

  testWidgets("removing a key mid-enter under an off itemEnterExit retires "
      "it at once", (tester) async {
    final controller = await _midEnterUnderOffFamily(tester);

    controller.removeItem("b");
    // TARGET a: the id is released within the call.
    expect(controller.idOfKey("b"), -1);
    // TARGET b: no exit record stands, the one record that could drive
    // layout under a disabled style.
    expect(controller.anim.hasLayoutDrivingAnimations, isFalse);
  });

  testWidgets("setItems dropping a key mid-enter under an off itemEnterExit "
      "retires it at once", (tester) async {
    final controller = await _midEnterUnderOffFamily(tester);

    controller.setItems(const <BoardPlacement<_Item>>[]);
    // TARGET a: the id is released within the call.
    expect(controller.idOfKey("b"), -1);
    // TARGET b: no exit record stands.
    expect(controller.anim.hasLayoutDrivingAnimations, isFalse);
  });

  // DERIVED name. No AC; settle-tick re-entrancy: the first settle's
  // delivered notification reaches an app listener that re-adds the
  // OTHER key settling on the same tick. The re-add reverses that key's
  // exit on the SAME id, replacing its record with an enter's, so the
  // animator's loop still holds that id in its collected settle list.
  // Falsification: a settle loop that does not re-check the record
  // reaches the handler against the reversed id and finalizes its ENTER
  // on the spot, so isEnteringItem reads false on the very tick the
  // enter was installed.
  testWidgets(
    "a structural listener re-adding a key during a double settle does "
    "not reach the handler twice",
    (tester) async {
      final controller = _lanedController(tester);
      controller.animationStyle = BoardAnimationStyle.disabled;
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      controller.addItem(const _Item("b"), _chip(2, 0, 2));
      await tester.pumpWidget(_board(controller));
      controller.animationStyle = _enterExitOnly;

      var reAdded = false;
      void listener(Set<String>? affected) {
        if (reAdded) {
          return;
        }
        final idB = controller.idOfKey("b");
        // Only on the SETTLE tick's delivered notification: at the
        // install-time notification the exit still reads its full ramp,
        // and re-adding there would let the fresh enter settle before
        // the assertion looks at it.
        if (idB >= 0 &&
            controller.anim.isExitingItem(idB) &&
            controller.anim.enterExitProgressOf(idB) < 0.5) {
          reAdded = true;
          controller.addItem(const _Item("b"), _chip(4, 0, 2));
        }
      }

      controller.addStructuralListener(listener);
      addTearDown(() {
        controller.removeStructuralListener(listener);
      });

      // Both exits install on one frame and settle on one tick.
      controller.removeItem("a");
      controller.removeItem("b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      // Setup sanity: the listener really ran.
      expect(reAdded, isTrue);
      // The reversed item's enter survives the tick that collected its
      // id to settle.
      expect(
        controller.anim.isEnteringItem(controller.idOfKey("b")),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(controller.contains("a"), isFalse);
      expect(controller.contains("b"), isTrue);
      expect(controller.spanOf("b"), _chip(4, 0, 2));
    },
  );

  // DERIVED name. No AC; the falsifiable case for the prior-tick latch,
  // and the only one.
  // Asserts: addItem under a non-zero itemEnterExit with no other
  // mutation in flight; pump to just before the settle and assert the
  // SETUP, that the item's painted lane-axis extent is strictly less
  // than laneExtent; record debugPerformLayoutCount; pump past the
  // settle and assert BOTH that the count increased and that the extent
  // now equals laneExtent.
  // Falsification: against a routing with no prior-tick mirror both
  // halves fail. Asserting the extent alone would NOT discriminate,
  // since any later pump of an unrelated mutation supplies the missing
  // dirtying.
  testWidgets(
    "an enter that settles with nothing else dirtying the frame still "
    "lays out",
    (tester) async {
      final controller = _lanedController(tester);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();

      controller.addItem(const _Item("n"), _chip(0, 0, 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 290));
      // Setup sanity: not yet settled.
      expect(
        tester.getRect(find.byKey(_itemKey("n"))).height,
        lessThan(18.0),
      );
      final layoutsBefore = _viewport(tester).debugPerformLayoutCount;

      await tester.pump(const Duration(milliseconds: 20));
      expect(
        _viewport(tester).debugPerformLayoutCount,
        greaterThan(layoutsBefore),
      );
      expect(tester.getRect(find.byKey(_itemKey("n"))).height, 18.0);
    },
  );
}
