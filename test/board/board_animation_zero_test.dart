/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 9 with the animation sources.
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

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _contentRows(
  WidgetTester tester, {
  required BoardAnimationStyle style,
  double laneExtent = 18.0,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(6, 80.0),
      laneExtent: laneExtent,
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
  double cellHeight = 20.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: 400.0,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return SizedBox(width: 40.0, height: cellHeight);
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

void main() {
  // AC11 the zero rule, part (1).
  // Asserts: a zero family CREATES no motion while other families'
  // in-flight animations survive.
  // Falsification: a master switch fails this case.
  testWidgets(
    "a zero itemSlide refuses the install and leaves an in-flight "
    "trackResize running",
    (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _zero,
        itemEnterExit: _zero,
      );
      final controller = _contentRows(tester, style: style);
      controller.addItem(const _Item("m"), _chip(2, 0, 2));
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();

      // A re-measurement of already-measured tracks installs a resize.
      await tester.pumpWidget(_board(controller, cellHeight: 40.0));
      expect(controller.anim.hasActiveTrackResize, isTrue);

      // The zero itemSlide REFUSES; the resize keeps running.
      controller.moveItem("m", _chip(4, 0, 2));
      final id = controller.idOfKey("m");
      expect(controller.anim.offsetOfItem(id), Offset.zero);
      expect(controller.anim.hasActiveTrackResize, isTrue);
      // Let the surviving resize run out; a live ticker fails the test
      // harness at the end of the body.
      await tester.pumpAndSettle();
    },
  );

  // AC11 the zero rule, part (2).
  // Asserts: DISABLING stops in-flight slide motion at the transition.
  // Falsification: a style setter without purgeActive fails this case.
  testWidgets(
    "restyling itemSlide to zero stops an in-flight slide at the "
    "transition",
    (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms300,
      );
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: style,
      );
      addTearDown(controller.dispose);
      controller.addItem(const _Item("m"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));

      controller.moveItem("m", _chip(0, 4, 2));
      final id = controller.idOfKey("m");
      // Setup sanity: the slide is in flight and displacing.
      expect(controller.anim.offsetOfItem(id), isNot(Offset.zero));
      expect(controller.anim.hasActiveOffsets, isTrue);

      controller.animationStyle = const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _zero,
      );
      expect(controller.anim.offsetOfItem(id), Offset.zero);
      expect(controller.anim.hasActiveOffsets, isFalse);
      await tester.pump();
      // The item paints at its structural position: column 4 of 40s.
      expect(tester.getRect(find.byKey(_itemKey("m"))).left, 160.0);
    },
  );

  // AC11 the zero rule, part (3), the layout-driving arm.
  // Asserts: the in-flight resize is finalized at its target extent
  // rather than purged.
  // Falsification: a style setter that PURGES trackResize instead of
  // finalizing it fails this case, leaving the track at its partial
  // extent forever, which is the layout-driving asymmetry I16 states.
  testWidgets(
    "restyling trackResize to zero finalizes an in-flight resize at its "
    "target extent",
    (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _zero,
        itemEnterExit: _zero,
      );
      final controller = _contentRows(tester, style: style);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_board(controller, cellHeight: 40.0));
      expect(controller.anim.hasActiveTrackResize, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      // Setup sanity: mid-flight, the painted extent is strictly between.
      final viewport = _viewport(tester);
      final midHeight = viewport.rectOfCell(0, 0)!.height;
      expect(midHeight, greaterThan(20.0));
      expect(midHeight, lessThan(40.0));

      controller.animationStyle = const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _zero,
        itemEnterExit: _zero,
      );
      expect(controller.anim.hasActiveTrackResize, isFalse);
      await tester.pump();
      expect(viewport.rectOfCell(0, 0)!.height, 40.0);
    },
  );

  // DERIVED name. No AC; the pre-first-tick window of the trackResize
  // transition: before any tick has latched the prior-tick mirror, the
  // animation channel alone cannot route a relayout, so the setter's arm
  // must dirty layout itself.
  // Falsification: a setter that only finalizes and notifies leaves the
  // cells painted at the captured `from` extents until an unrelated
  // relayout.
  testWidgets(
    "restyling trackResize to zero before its first tick still lands "
    "the target extent",
    (tester) async {
      const style = BoardAnimationStyle(
        trackResize: _ms300,
        itemSlide: _zero,
        itemEnterExit: _zero,
      );
      final controller = _contentRows(tester, style: style);
      Widget keyedBoard(double cellHeight) {
        return MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280.0,
                height: 400.0,
                child: Board<String, _Item>(
                  controller: controller,
                  cellBuilder: (context, cell) {
                    return SizedBox(
                      key: ValueKey<String>("c${cell.row}_${cell.col}"),
                      width: 40.0,
                      height: cellHeight,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(keyedBoard(20.0));
      await tester.pumpAndSettle();

      // The install frame lays the cells out at the captured `from`; no
      // tick has run yet.
      await tester.pumpWidget(keyedBoard(40.0));
      expect(controller.anim.hasActiveTrackResize, isTrue);
      controller.animationStyle = BoardAnimationStyle.disabled;
      expect(controller.anim.hasActiveTrackResize, isFalse);

      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey<String>("c0_0"))).height,
        40.0,
      );
    },
  );

  // AC11 the zero rule, both entries.
  // Asserts: after the mutator returns, contains(key) is false, itemsAt
  // omits it, and a live neighbour's laneCountOf has already dropped, all
  // on the frame of the call with no pump, which is what the read-side
  // lane flush buys. Asserted once per entry, removeItem and setItems.
  // Falsification: an implementation that REFUSES the enter/exit install
  // fails it twice; the setItems arm is the one an earlier caller list
  // would have passed while leaking. The same three assertions catch a
  // synchronous retire that reaches the handler with both bits clear and
  // falls into the ENTER branch, which is why the case asserts model
  // state rather than only that no animation is running.
  testWidgets(
    "a zero itemEnterExit retires an item synchronously through "
    "removeItem AND through setItems",
    (tester) async {
      final controller = _contentRows(
        tester,
        style: BoardAnimationStyle.disabled,
      );
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      controller.addItem(const _Item("b"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(controller));
      expect(controller.laneCountOf("a"), 2);

      controller.removeItem("b");
      expect(controller.contains("b"), isFalse);
      expect(controller.itemsAt(0, 0), isNot(contains("b")));
      expect(controller.laneCountOf("a"), 1);

      // The setItems entry, on a fresh overlap.
      controller.addItem(const _Item("d"), _chip(2, 0, 2));
      controller.addItem(const _Item("e"), _chip(2, 0, 2));
      expect(controller.laneCountOf("d"), 2);
      controller.setItems(<BoardPlacement<_Item>>[
        BoardPlacement<_Item>(const _Item("a"), _chip(0, 0, 2)),
        BoardPlacement<_Item>(const _Item("d"), _chip(2, 0, 2)),
      ]);
      expect(controller.contains("e"), isFalse);
      expect(controller.itemsAt(2, 0), isNot(contains("e")));
      expect(controller.laneCountOf("d"), 1);
    },
  );

  // AC12 a zero makeRoom INSTALLS the gap, driven through
  // previewMakeRoomGap and releaseMakeRoomPreview, the declared route.
  // Asserts: under BoardAnimationStyle.disabled, (i) a displaced item's
  // offsetOfItem already equals the full target on the next pump and its
  // probe rect is displaced by the same amount; (ii) after
  // releaseMakeRoomPreview and one more pump both are back at zero;
  // (iii) debugPerformLayoutCount increases across the install frame AND
  // across the release frame, which is the only assertion that reaches
  // the two uncoalesced notifies. A NON-zero rerun pins that (i) cannot
  // pass by accident: its first-frame value is strictly between.
  testWidgets(
    "a zero makeRoom snaps the gap open rather than refusing it",
    (tester) async {
      final controller = _contentRows(
        tester,
        style: BoardAnimationStyle.disabled,
      );
      // A two-lane cluster; the prospective span starts EARLIER on the
      // sweep axis, so the dry run hands it lane 0 and displaces both.
      controller.addItem(const _Item("a"), _chip(0, 2, 2));
      controller.addItem(const _Item("b"), _chip(0, 2, 2));
      controller.addItem(const _Item("d"), _chip(2, 0, 2));
      await tester.pumpWidget(_board(controller));
      final viewport = _viewport(tester);
      final idA = controller.idOfKey("a");
      final restingTop = tester.getRect(find.byKey(_itemKey("a"))).top;

      final layoutsBefore = viewport.debugPerformLayoutCount;
      controller.previewMakeRoomGap(
        draggedKey: "d",
        prospective: _chip(0, 0, 3),
      );
      await tester.pump();
      // (i) The full target, on the first frame: one lane extent down.
      expect(controller.anim.offsetOfItem(idA), const Offset(0.0, 18.0));
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).top,
        restingTop + 18.0,
      );
      // (iii) The install frame laid out: the offset exceeded the
      // admitted bound and the uncoalesced notify routed it.
      expect(viewport.debugPerformLayoutCount, greaterThan(layoutsBefore));

      final layoutsMid = viewport.debugPerformLayoutCount;
      controller.releaseMakeRoomPreview();
      await tester.pump();
      // (ii) Both back at zero.
      expect(controller.anim.offsetOfItem(idA), Offset.zero);
      expect(tester.getRect(find.byKey(_itemKey("a"))).top, restingTop);
      expect(viewport.debugPerformLayoutCount, greaterThan(layoutsMid));

      // The non-zero rerun: the first frame sits strictly between.
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _zero,
        itemEnterExit: _zero,
        makeRoom: _ms300,
      );
      controller.previewMakeRoomGap(
        draggedKey: "d",
        prospective: _chip(0, 0, 3),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final midOffset = controller.anim.offsetOfItem(idA).dy;
      expect(midOffset, greaterThan(0.0));
      expect(midOffset, lessThan(18.0));
      controller.releaseMakeRoomPreview();
      await tester.pumpAndSettle();
    },
  );
}
