library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Event {
  const _Event(this.key);

  final String key;
}

const double _hour = 60.0;
const double _day = 170.0;

/// THE REPORTED SCENE, promoted from the repro that diagnosed it.
///
/// Hours down, days across, a Standup bar across four days at 09:00, and
/// a Design review block on Tuesday from 09:30 to 11:00 dragged up so it
/// sits around 07:45 to 09:15, clipping Standup. The app refuses any
/// overlap.
///
/// Without a `dropFit` policy the drop is refused and the block returns
/// to 09:30, which is what was reported as the feature not working. With
/// one it lands in the free slot the block mostly covers, 07:30 to 09:00
/// under a fifteen minute snap.
void main() {
  Future<List<BoardSpan>> run(
    WidgetTester tester, {
    required BoardSnap snap,
    required BoardDropFit? dropFit,
    required double dropTopHour,
  }) async {
    final controller = BoardController<String, _Event>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, _hour)),
      columns: BoardAxisConfig(axis: UniformAxis(7, _day), laneExtent: _day),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Event("gym"),
      const BoardSpan(rowStart: 7, colStart: 0),
    );
    // Standup: 09:00 to 09:15 across Mon..Thu.
    controller.addItem(
      const _Event("standup"),
      const BoardSpan(
        rowStart: 9,
        colStart: 0,
        colSpan: 4,
        rowSpan: 0,
        rowSpanFraction: 0.25,
      ),
    );
    // Design review: Tuesday 09:30 to 11:00.
    controller.addItem(
      const _Event("design"),
      const BoardSpan(
        rowStart: 9,
        rowFraction: 0.5,
        rowSpan: 1,
        rowSpanFraction: 0.5,
        colStart: 1,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 700.0,
              height: 700.0,
              child: Board<String, _Event>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return const SizedBox(width: _day, height: _hour);
                },
                itemBuilder: (context, item) {
                  return const ColoredBox(color: Color(0xFF7E57C2));
                },
              ),
            ),
          ),
        ),
      ),
    );
    final moves = <BoardSpan>[];
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        snap: snap,
        dropFit: dropFit,
        onItemMoved: (key, span) {
          moves.add(span);
        },
        canDropAt: (key, span) {
          for (final other in controller.itemsIn(
            span.rowStart,
            span.endTrackOn(Axis.vertical).ceil(),
            span.colStart,
            span.endTrackOn(Axis.horizontal).ceil(),
          )) {
            if (other == key) {
              continue;
            }
            final o = controller.spanOf(other)!;
            final rowsMeet =
                span.startTrackOn(Axis.vertical) <
                    o.endTrackOn(Axis.vertical) &&
                o.startTrackOn(Axis.vertical) < span.endTrackOn(Axis.vertical);
            final colsMeet =
                span.startTrackOn(Axis.horizontal) <
                    o.endTrackOn(Axis.horizontal) &&
                o.startTrackOn(Axis.horizontal) <
                    span.endTrackOn(Axis.horizontal);
            if (rowsMeet && colsMeet) {
              return false;
            }
          }
          return true;
        },
      ),
    );
    addTearDown(drag.dispose);
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    final origin = tester.getRect(find.byType(Board<String, _Event>)).topLeft;
    final rect = viewport.rectOfItem("design")!;
    // Grab the block's own top-left corner, then move so the corner
    // lands on dropTopHour in the same day column.
    final grab = rect.topLeft + const Offset(20.0, 6.0);
    drag.startDrag(
      key: "design",
      renderPort: viewport,
      pointerGlobal: origin + grab,
    );
    final targetTop = dropTopHour * _hour;
    drag.updateDrag(
      origin + Offset(grab.dx, targetTop + (grab.dy - rect.top)),
    );
    await tester.pump();
    drag.endDrag(cancel: false);
    await tester.pump();
    return moves;
  }

  // The reported symptom: with no policy the block returns to where it
  // started, because the app refuses the overlap and the board has
  // nowhere to go.
  testWidgets("a calendar block clipping a short event is refused with no "
      "policy", (tester) async {
    final moves = await run(
      tester,
      snap: const BoardSnap.fraction(0.25),
      dropFit: null,
      dropTopHour: 7.75,
    );
    expect(moves, isEmpty);
  });

  // TARGET: the free slot the block mostly covers, ending exactly where
  // Standup begins. Half-open spans are what let 09:00 be free.
  testWidgets("a calendar block clipping a short event lands in the free "
      "slot above it", (tester) async {
    final moves = await run(
      tester,
      snap: const BoardSnap.fraction(0.25),
      dropFit: const BoardDropFit(),
      dropTopHour: 7.75,
    );
    expect(moves, hasLength(1));
    expect(moves.single.startTrackOn(Axis.vertical), 7.5);
    expect(moves.single.endTrackOn(Axis.vertical), 9.0);
    expect(moves.single.colStart, 1);
  });

  // The same drag under a whole-hour snap, where the scan can only step
  // in hours, so it lands an hour earlier rather than at the half hour.
  testWidgets("a whole-hour snap steps the calendar block by an hour", (
    tester,
  ) async {
    final moves = await run(
      tester,
      snap: const BoardSnap.track(),
      dropFit: const BoardDropFit(),
      dropTopHour: 7.75,
    );
    expect(moves, hasLength(1));
    expect(moves.single.startTrackOn(Axis.vertical), 7.0);
    expect(moves.single.endTrackOn(Axis.vertical), 8.5);
  });

  // THE EXAMPLE'S OWN LATTICE, not a simplification of it: a frozen
  // header row and a frozen hour gutter, explicit per-track extents, the
  // day axis carrying the lane extent, and fifteen minute increments, so
  // row `1 + minutes / 15` is a time and column `1 + weekday` is a day.
  //
  // The scene is the screenshot's. Standup is a MULTI-DAY block across
  // Monday to Thursday at 09:00, which the example's predicate refuses
  // to share a slot with, and Design review is a single-day event
  // dragged up from 09:30 so its block covers 07:45 to 09:15 and clips
  // Standup by one increment.
  //
  // Asserts: the commit is 07:30 to 09:00, ending exactly where Standup
  // begins. The policy is the asymmetric one a calendar wants, an hour
  // of slack in time and none across days.
  testWidgets("the week view example's lattice slides the block to 07:30", (
    tester,
  ) async {
    const header = 28.0;
    const gutter = 56.0;
    const rowHeight = 16.0;
    const dayWidth = 90.0;
    int rowOf(int minutes) {
      return 1 + minutes ~/ 15;
    }

    final controller = BoardController<String, _Event>(
      vsync: tester,
      rows: BoardAxisConfig(
        axis: ExplicitAxis(<double>[
          header,
          ...List<double>.filled(96, rowHeight),
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
    controller.addItem(
      const _Event("gym"),
      BoardSpan(rowStart: rowOf(7 * 60), colStart: 1, rowSpan: 4),
    );
    controller.addItem(
      const _Event("standup"),
      BoardSpan(rowStart: rowOf(9 * 60), colStart: 1, colSpan: 4),
    );
    controller.addItem(
      const _Event("design"),
      BoardSpan(rowStart: rowOf(9 * 60 + 30), colStart: 2, rowSpan: 6),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 700.0,
              height: 700.0,
              child: Board<String, _Event>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return const SizedBox.expand();
                },
                itemBuilder: (context, item) {
                  return const ColoredBox(color: Color(0xFF7E57C2));
                },
              ),
            ),
          ),
        ),
      ),
    );
    final moves = <BoardSpan>[];
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moves.add(span);
        },
        // The example's own rule: never the header or the gutter, and a
        // single-day event may not share a slot with a multi-day block.
        canDropAt: (key, span) {
          if (span.rowStart < 1 || span.colStart < 1) {
            return false;
          }
          final rowEnd =
              span.rowStart +
              span.rowSpan +
              (span.rowSpanFraction > 0.0 ? 1 : 0);
          final others = controller.itemsIn(
            span.rowStart,
            rowEnd,
            span.colStart,
            span.colStart + span.colSpan,
          )..remove(key);
          if (span.colSpan > 1) {
            return others.isEmpty;
          }
          for (final other in others) {
            if (controller.spanOf(other)!.colSpan > 1) {
              return false;
            }
          }
          return true;
        },
        // One hour of slack in time, none across days.
        dropFit: const BoardDropFit(rowRadius: 4.0, colRadius: 0.0),
      ),
    );
    addTearDown(drag.dispose);
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    final origin = tester.getRect(find.byType(Board<String, _Event>)).topLeft;
    final rect = viewport.rectOfItem("design")!;
    final grab = rect.topLeft + const Offset(20.0, 6.0);
    drag.startDrag(
      key: "design",
      renderPort: viewport,
      pointerGlobal: origin + grab,
    );
    // Move the block's corner to 07:45, which clips Standup at 09:00.
    final topOf0745 = header + (rowOf(7 * 60 + 45) - 1) * rowHeight;
    drag.updateDrag(
      origin + Offset(grab.dx, topOf0745 + (grab.dy - rect.top)),
    );
    await tester.pump();
    // Setup sanity: the nudge is what answers, not the raw resolve.
    expect(drag.currentTarget!.span.rowStart, rowOf(7 * 60 + 30));
    drag.endDrag(cancel: false);
    await tester.pump();

    expect(moves, hasLength(1));
    // 07:30 to 09:00, ending exactly where Standup begins.
    expect(moves.single.rowStart, rowOf(7 * 60 + 30));
    expect(moves.single.rowStart + moves.single.rowSpan, rowOf(9 * 60));
    expect(moves.single.colStart, 2);
  });
}
