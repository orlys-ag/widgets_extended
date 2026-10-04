/// Promoted repros for `plans/2026-09-06-board-review-fixes-plan.md`,
/// section F12: frozen tracks in the background geometry.
///
/// Every case observes through a recording [BoardBackgroundPainter] that
/// captures what the geometry view reports during the board's own paint
/// pass, and through the stock [BoardGridPainter] run against a recording
/// canvas on that same geometry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_background.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

/// Records every `drawLine` and `drawRect` argument; everything else is a
/// no-op.
class _RecordingCanvas implements Canvas {
  final List<(Offset, Offset)> lines = <(Offset, Offset)>[];
  final List<Rect> rects = <Rect>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.positionalArguments;
    if (invocation.memberName == #drawLine) {
      lines.add((args[0] as Offset, args[1] as Offset));
    } else if (invocation.memberName == #drawRect) {
      rects.add(args[0] as Rect);
    }
    return null;
  }
}

/// What one paint pass reported.
class _Capture {
  _Capture({
    required this.firstRow,
    required this.lastRow,
    required this.firstCol,
    required this.lastCol,
    required this.frozenRows,
    required this.frozenCols,
    required this.row0Tops,
    required this.lines,
    required this.rects,
  });

  final int firstRow;
  final int lastRow;
  final int firstCol;
  final int lastCol;
  final List<int> frozenRows;
  final List<int> frozenCols;

  /// `visibleCellRect(0, c).top` for every visible column `c`.
  final List<double> row0Tops;

  /// What [BoardGridPainter] drew on this geometry.
  final List<(Offset, Offset)> lines;
  final List<Rect> rects;
}

/// Captures the geometry it is handed and runs the stock grid painter on
/// it against a recording canvas.
class _RecordingPainter extends BoardBackgroundPainter {
  const _RecordingPainter(this.log, {this.grid = const BoardGridPainter()});

  final List<_Capture> log;
  final BoardGridPainter grid;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    final recording = _RecordingCanvas();
    grid.paint(recording, geometry);
    final tops = <double>[];
    for (var c = geometry.firstVisibleCol; c <= geometry.lastVisibleCol; c++) {
      tops.add(geometry.visibleCellRect(0, c).top);
    }
    log.add(_Capture(
      firstRow: geometry.firstVisibleRow,
      lastRow: geometry.lastVisibleRow,
      firstCol: geometry.firstVisibleCol,
      lastCol: geometry.lastVisibleCol,
      frozenRows: geometry.frozenTracksOf(Axis.vertical).toList(),
      frozenCols: geometry.frozenTracksOf(Axis.horizontal).toList(),
      row0Tops: tops,
      lines: recording.lines,
      rects: recording.rects,
    ));
  }

  @override
  bool shouldRepaint(_RecordingPainter old) {
    return !identical(old.log, log);
  }
}

Color? _tintRow0(Axis axis, int track) {
  if (axis == Axis.vertical && track == 0) {
    return const Color(0xFF2196F3);
  }
  return null;
}

Future<List<_Capture>> _pumpFrozenBoard(
  WidgetTester tester, {
  required double initialScrollOffset,
  BoardGridPainter grid = const BoardGridPainter(),
}) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    // Row 0 is a frozen header 50 tall over 30 rows of 50; three columns
    // of 100 fill the 300 wide frame exactly.
    rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
    columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  final vertical = ScrollController(initialScrollOffset: initialScrollOffset);
  addTearDown(vertical.dispose);
  final log = <_Capture>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300.0,
            height: 200.0,
            child: Board<String, _Item>(
              controller: controller,
              background: _RecordingPainter(log, grid: grid),
              verticalDetails: ScrollableDetails.vertical(controller: vertical),
              cellBuilder: (context, cell) {
                return SizedBox(
                  key: ValueKey<String>("c${cell.row}_${cell.col}"),
                  width: 100.0,
                  height: 50.0,
                );
              },
              itemBuilder: (context, item) {
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    ),
  );
  // Setup sanity: the frozen header's child paints in the band at the
  // top of the frame whatever the scroll offset.
  expect(
    tester.getTopLeft(find.byKey(const ValueKey<String>("c0_0"))),
    Offset.zero,
  );
  expect(log, isNotEmpty);
  return log;
}

/// The y of every horizontal line in [lines].
Iterable<double> _horizontalLineYs(List<(Offset, Offset)> lines) {
  return lines.where((line) {
    return line.$1.dy == line.$2.dy;
  }).map((line) {
    return line.$1.dy;
  });
}

void main() {
  // F12, the scrolled-out half: at offset 520 the visible window is rows
  // 10..14 (tops -20, 30, 80, 130, 180), so row 0 lies outside it and no
  // scrolled row's top coincides with the band's top at 0. Unfixed:
  // frozenTracksOf does not exist, visibleCellRect(0, c) asserts out of
  // range, and the grid painter never iterates row 0, so no line is drawn
  // at y 0 and no tint covers 0..50.
  testWidgets("F12 a frozen row keeps its grid line while scrolled", (
    tester,
  ) async {
    final log = await _pumpFrozenBoard(
      tester,
      initialScrollOffset: 520.0,
      grid: const BoardGridPainter(trackTint: _tintRow0),
    );
    final capture = log.last;
    // Setup sanity: row 0 is outside the scrolled window.
    expect(capture.firstRow, greaterThan(0));
    expect(capture.firstCol, 0);
    expect(capture.lastCol, 2);

    expect(capture.frozenRows, <int>[0]);
    expect(capture.frozenCols, isEmpty);
    expect(capture.row0Tops, <double>[0.0, 0.0, 0.0]);

    expect(_horizontalLineYs(capture.lines), contains(0.0));
    expect(
      capture.rects,
      contains(const Rect.fromLTRB(0.0, 0.0, 300.0, 50.0)),
    );
  });

  // F12, the in-range half: at offset 20 row 0's SCROLLED position (top
  // -20) would still be on screen, but its rect must sit where its frozen
  // child paints (top 0). Unfixed: the top is -20.0 and the grid line for
  // row 0 is drawn there. Since the audit fixes' item 3 the visible range
  // leaves a frozen row out altogether, reporting it through
  // frozenTracksOf alone, which is what makes it drawn once.
  testWidgets(
    "F12 a frozen row inside the visible window is positioned in the band",
    (tester) async {
      final log = await _pumpFrozenBoard(tester, initialScrollOffset: 20.0);
      final capture = log.last;
      // Setup sanity: the frozen row comes from frozenTracksOf, and the
      // scrolled range starts below the band.
      expect(capture.firstRow, 1);
      expect(capture.frozenRows, <int>[0]);

      expect(capture.row0Tops, <double>[0.0, 0.0, 0.0]);
      final ys = _horizontalLineYs(capture.lines).toList();
      expect(ys, contains(0.0));
      expect(ys, isNot(contains(-20.0)));
      // Row 0 is drawn once, not once per source (visible range and
      // frozen list).
      expect(ys.where((y) => y == 0.0).length, 1);
    },
  );
}
