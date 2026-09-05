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
}
