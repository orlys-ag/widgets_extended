/// The scroll range a board gives its two scroll positions: how far its
/// tracks pass its viewport on each axis, and none where they fill it but
/// for the residue a sum of doubles leaves.
library;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

/// A board of [rows] over [columns] in a frame [size] large, in a view
/// larger than it.
Future<RenderBoardViewport<String>> _pumpBoard(
  WidgetTester tester, {
  required Size size,
  required List<double> rows,
  required List<double> columns,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800.0, 2000.0);
  addTearDown(tester.view.reset);
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: ExplicitAxis(rows)),
    columns: BoardAxisConfig(axis: ExplicitAxis(columns)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  // Registered after the dispose, so it runs before it: the board
  // unsubscribes when it unmounts.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

void main() {
  testWidgets("SE1 tracks that fill the viewport but for a rounding residue "
      "give no scroll range on either axis, so the board does not scroll "
      "under a drag", (tester) async {
    // 96 rows of 1636 / 96 px sum to 1.8e-12 px past 1636 px, and 7
    // columns of 702 / 7 px to 1.1e-13 px past 702 px.
    const size = Size(702.0, 1636.0);
    final rows = List<double>.filled(96, size.height / 96);
    final columns = List<double>.filled(7, size.width / 7);
    final viewport = await _pumpBoard(
      tester,
      size: size,
      rows: rows,
      columns: columns,
    );
    // Setup sanity: each axis's total passes the viewport by a residue
    // within the tolerance.
    final rowsPast = ExplicitAxis(rows).totalExtent - size.height;
    final columnsPast = ExplicitAxis(columns).totalExtent - size.width;
    expect(rowsPast, greaterThan(0.0));
    expect(rowsPast, lessThan(precisionErrorTolerance));
    expect(columnsPast, greaterThan(0.0));
    expect(columnsPast, lessThan(precisionErrorTolerance));

    expect(viewport.verticalPosition!.maxScrollExtent, 0.0);
    expect(viewport.horizontalPosition!.maxScrollExtent, 0.0);
    await tester.dragFrom(
      const Offset(300.0, 800.0),
      const Offset(-40.0, -60.0),
    );
    await tester.pumpAndSettle();
    expect(viewport.verticalPosition!.pixels, 0.0);
    expect(viewport.horizontalPosition!.pixels, 0.0);
  });

  testWidgets("SE2 tracks passing the viewport by more than the tolerance "
      "give that much scroll range", (tester) async {
    const size = Size(702.0, 1636.0);
    const past = 1e-6;
    final viewport = await _pumpBoard(
      tester,
      size: size,
      rows: <double>[size.height / 2, size.height / 2 + past],
      columns: <double>[size.width / 2, size.width / 2 + past],
    );
    expect(
      viewport.verticalPosition!.maxScrollExtent,
      moreOrLessEquals(past, epsilon: 1e-9),
    );
    expect(
      viewport.horizontalPosition!.maxScrollExtent,
      moreOrLessEquals(past, epsilon: 1e-9),
    );
  });
}
