/// The board's foreground painter: where its pass falls among the paint
/// planes, that it runs on an empty board, and how a new painter reaches
/// the render object.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_background.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Color _backgroundColor = Color(0xFF0000AA);
const Color _scrolledCellColor = Color(0xFF00AA00);
const Color _bandCellColor = Color(0xFFAA00AA);
const Color _itemColor = Color(0xFFAAAA00);
const Color _foregroundColor = Color(0xFFAA0000);

/// Fills the viewport with [color].
class _FillBackground extends BoardBackgroundPainter {
  const _FillBackground();

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    canvas.drawRect(
      Offset.zero & geometry.viewportDimension,
      Paint()..color = _backgroundColor,
    );
  }

  @override
  bool shouldRepaint(_FillBackground old) {
    return false;
  }
}

/// Fills a 10 px square at the viewport's origin with [_foregroundColor],
/// and records every [paint] call in [log].
class _ProbeForeground extends BoardForegroundPainter {
  const _ProbeForeground(this.log, {this.width = 10.0});

  final List<int> log;

  /// The square's side, which [shouldRepaint] compares.
  final double width;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    log.add(geometry.lastVisibleRow);
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, width, width),
      Paint()..color = _foregroundColor,
    );
  }

  @override
  bool shouldRepaint(_ProbeForeground old) {
    return old.width != width;
  }
}

/// A different painter type, for the setter's type arm.
class _OtherForeground extends BoardForegroundPainter {
  const _OtherForeground();

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {}

  @override
  bool shouldRepaint(_OtherForeground old) {
    return false;
  }
}

/// 30 rows of 50 by 3 columns of 100, row 0 and column 0 frozen.
BoardController<String, _Item> _controller(
  WidgetTester tester, {
  int rows = 30,
  int columns = 3,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0), frozenStart: 1),
    columns: BoardAxisConfig(axis: UniformAxis(columns, 100.0), frozenStart: 1),
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
  BoardBackgroundPainter? background,
  BoardForegroundPainter? foreground,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300.0,
          height: 200.0,
          child: Board<String, _Item>(
            controller: controller,
            background: background,
            foreground: foreground,
            cellBuilder: (context, cell) {
              final band = cell.row == 0 || cell.col == 0;
              return ColoredBox(
                color: band ? _bandCellColor : _scrolledCellColor,
              );
            },
            itemBuilder: (context, item) {
              return const ColoredBox(color: _itemColor);
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

/// The colours of the rects [viewport] fills, in the order it paints them,
/// its children's included, as 32-bit ARGB: a [Paint] hands its colour
/// back from its own storage, which need not compare equal to the [Color]
/// it was given.
List<int> _paintedRectColors(RenderBoardViewport<String> viewport) {
  final canvas = TestRecordingCanvas();
  viewport.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return <int>[
    for (final call in canvas.invocations)
      if (call.invocation.memberName == #drawRect)
        (call.invocation.positionalArguments[1] as Paint).color.toARGB32(),
  ];
}

void main() {
  testWidgets("the foreground paints after the background, the scrolled "
      "cells and items and the frozen bands' cells", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 1, colStart: 1, colSpan: 2),
    );
    final log = <int>[];
    await tester.pumpWidget(
      _board(
        controller,
        background: const _FillBackground(),
        foreground: _ProbeForeground(log),
      ),
    );
    expect(log, isNotEmpty);
    final colors = _paintedRectColors(_viewport(tester));
    // Setup sanity: every plane under test painted.
    for (final color in <Color>[
      _backgroundColor,
      _scrolledCellColor,
      _itemColor,
      _bandCellColor,
      _foregroundColor,
    ]) {
      expect(colors, contains(color.toARGB32()));
    }
    expect(colors.first, _backgroundColor.toARGB32());
    expect(colors.last, _foregroundColor.toARGB32());
    expect(
      colors.where((color) => color == _foregroundColor.toARGB32()),
      hasLength(1),
    );
  });

  testWidgets("an empty board still runs the foreground painter", (
    tester,
  ) async {
    final controller = _controller(tester, rows: 0, columns: 0);
    final log = <int>[];
    await tester.pumpWidget(
      _board(controller, foreground: _ProbeForeground(log)),
    );
    expect(log, isNotEmpty);
    // The geometry reports no visible row.
    expect(log.last, -1);
  });

  testWidgets("a new foreground painter reaches the render object, which "
      "repaints only when shouldRepaint says so", (tester) async {
    final controller = _controller(tester);
    final log = <int>[];
    final first = _ProbeForeground(log);
    await tester.pumpWidget(_board(controller, foreground: first));
    final viewport = _viewport(tester);
    expect(viewport.foreground, same(first));

    final second = _ProbeForeground(log, width: 20.0);
    await tester.pumpWidget(_board(controller, foreground: second));
    expect(viewport.foreground, same(second));

    // Same config, distinct instance: no repaint.
    viewport.foreground = _ProbeForeground(log, width: 20.0);
    expect(viewport.debugNeedsPaint, isFalse);

    // A changed config repaints.
    viewport.foreground = _ProbeForeground(log, width: 30.0);
    expect(viewport.debugNeedsPaint, isTrue);
    await tester.pump();

    // Another type repaints, decided before shouldRepaint's covariant
    // parameter can mismatch.
    viewport.foreground = const _OtherForeground();
    expect(viewport.debugNeedsPaint, isTrue);
    await tester.pump();

    // Removing it repaints.
    viewport.foreground = null;
    expect(viewport.debugNeedsPaint, isTrue);
    await tester.pump();

    // Adding one repaints.
    viewport.foreground = const _OtherForeground();
    expect(viewport.debugNeedsPaint, isTrue);
  });
}
