/// Promoted repros for the controller-layer sections of
/// `plans/2026-09-06-board-review-fixes-plan.md`: F5 (the settle snap of
/// a second landing in one frame), F6 (a phantom occupant one track past a
/// fractional end) and F7 (a non-positive snap fraction).
///
/// Each case carries setup sanity assertions that can fail, then the
/// target assertion shown red on the unfixed tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

/// A board whose rows are a content-sized axis ESTIMATED at 100 per track
/// while every cell measures 20 tall, so a landing computed against the
/// estimate is wrong by construction and only the settle snap corrects it.
///
/// 80 rows and not 60: with 60, row 50 is the last row that fits the
/// 200-tall viewport (rows 50 through 59 measure 200 together), so a
/// stale landing there sits past `maxScrollExtent` once the rows around
/// it measure, and the scroll position's own out-of-range ballistic
/// carries it to row 50's offset without any snap. With 80 rows neither
/// landing is at the extent and the snap is the only correction.
BoardController<String, _Item> _lazyRowsController(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: LazyContentAxis(80, 100.0)),
    columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(BoardController<String, _Item> controller) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 300.0,
          height: 200.0,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return SizedBox(
                key: _cellKey(cell.row, cell.col),
                width: 100.0,
                height: 20.0,
              );
            },
          ),
        ),
      ),
    ),
  );
}

BoardController<String, _Item> _uniformController(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(10, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(10, 50.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group("F5", () {
    // The control: a single zero-duration scroll to row 50 lands its cell
    // at the frame's top once the settle snap has run. This is what the
    // target case's second call must reproduce.
    testWidgets("one landing snaps row 50 to the top", (tester) async {
      final controller = _lazyRowsController(tester);
      await tester.pumpWidget(_board(controller));
      final frame = tester.getRect(find.byKey(_frameKey));
      // Setup sanity: settled at the origin, and the cells really measure
      // 20 tall against a 100 estimate, so a landing needs the snap.
      expect(tester.getRect(find.byKey(_cellKey(0, 0))).top - frame.top, 0.0);
      expect(tester.getSize(find.byKey(_cellKey(0, 0))).height, 20.0);

      final landed = controller.animateScrollToCell(
        50,
        0,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();
      expect(await landed, isTrue);
      expect(tester.getRect(find.byKey(_cellKey(50, 0))).top - frame.top, 0.0);
    });

    // The target: two zero-duration landings in ONE frame. The first has
    // LANDED (its future completes in a microtask, no frame in between)
    // and scheduled the post-frame snap under its generation before the
    // second is issued; the second overwrites the snap slot, but its
    // `_scheduleSnap` call returns early on the already-scheduled flag,
    // so the callback compares the FIRST landing's generation against the
    // intent generation and discards the newer snap.
    testWidgets("two landings in one frame snap to the later one", (
      tester,
    ) async {
      final controller = _lazyRowsController(tester);
      await tester.pumpWidget(_board(controller));
      final frame = tester.getRect(find.byKey(_frameKey));
      // Setup sanity: settled at the origin before either call.
      expect(tester.getRect(find.byKey(_cellKey(0, 0))).top - frame.top, 0.0);

      final first = controller.animateScrollToCell(
        40,
        0,
        duration: Duration.zero,
      );
      // Setup sanity: the first call landed and was not superseded, so it
      // is the one holding the scheduled snap when the second lands. No
      // frame is pumped here; the await yields to the microtask queue.
      expect(await first, isTrue);
      final second = controller.animateScrollToCell(
        50,
        0,
        duration: Duration.zero,
      );
      await tester.pump();
      // Setup sanity: the frame that laid out the second landing measured
      // rows ahead of row 50 and moved it, so this landing NEEDS its snap;
      // a fixture whose jump was already right would pass the target
      // below with no snap at all.
      expect(
        tester.getRect(find.byKey(_cellKey(50, 0))).top - frame.top,
        isNot(0.0),
      );
      await tester.pumpAndSettle();
      // Setup sanity: the second leg reports landed too, so a lost snap
      // below is the snap's and not a cancelled flight's.
      expect(await second, isTrue);
      // TARGET.
      expect(tester.getRect(find.byKey(_cellKey(50, 0))).top - frame.top, 0.0);
    });
  });
}
