/// Item 1 of `plans/2026-09-23-board-audit-fixes-plan.md`: a new config
/// instance is applied in place, and no runtime toggle re-creates the
/// widgets under the board.
///
/// Builders are TOP-LEVEL functions wherever a case counts builder calls
/// or `State` inits: an inline closure is a new object per pump, and a new
/// builder rebuilds the delegate by design, which would mask the defect.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key, [this.label = ""]);

  final String key;
  final String label;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

/// Counts builder calls and `State` inits across one case.
abstract final class _Counts {
  static int cellBuilds = 0;
  static int itemBuilds = 0;
  static int inits = 0;

  static void reset() {
    cellBuilds = 0;
    itemBuilds = 0;
    inits = 0;
  }
}

/// A stateful leaf whose `initState` count is what re-inflation shows.
class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() {
    return _ProbeState();
  }
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Counts.inits += 1;
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF4CAF50));
  }
}

Widget? _countingCell(
  BuildContext context,
  BoardCellView<String, _Item> cell,
) {
  _Counts.cellBuilds += 1;
  return const SizedBox.expand();
}

Widget? _probeCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return const _Probe();
}

Widget? _nullCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return null;
}

void _ignoreSelection(BoardSelection selection) {}

Widget _countingItem(BuildContext context, BoardItemView<String, _Item> item) {
  _Counts.itemBuilds += 1;
  return ColoredBox(
    key: _itemKey(item.key),
    color: const Color(0xFF4CAF50),
  );
}

Widget _probeItem(BuildContext context, BoardItemView<String, _Item> item) {
  return _Probe(key: _itemKey(item.key));
}

Widget _labelItem(BuildContext context, BoardItemView<String, _Item> item) {
  return ColoredBox(
    key: _itemKey(item.key),
    color: const Color(0xFF4CAF50),
    child: Text(item.item.label, textDirection: TextDirection.ltr),
  );
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  int rows = 6,
  double rowExtent = 50.0,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, rowExtent)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _frame(Widget board) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 280.0,
          height: 300.0,
          child: board,
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

/// Presses the item's centre, waits out the move handle's delay and moves
/// once, which starts a move session when the handles are live.
Future<TestGesture> _lift(WidgetTester tester, String key) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_itemKey(key)).first),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
  await gesture.moveBy(const Offset(0.0, 20.0));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets(
    "a parent rebuild with an equivalent inline config keeps a live drag, "
    "and the latest config gets the report",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      final reports = <int>[];
      var generation = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _frame(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              final mine = generation;
              return Board<String, _Item>(
                controller: controller,
                cellBuilder: _nullCell,
                itemBuilder: _countingItem,
                drag: BoardDragConfig<String>(
                  onItemMoved: (key, span) {
                    reports.add(mine);
                    controller.moveItem(key, span);
                  },
                ),
              );
            },
          ),
        ),
      );
      final gesture = await _lift(tester, "m");
      // Setup sanity: the session is live before the rebuild.
      expect(controller.isDragging("m"), isTrue);

      rebuild(() {
        generation = 1;
      });
      await tester.pump();
      // TARGET: the rebuild did not end the session.
      expect(controller.isDragging("m"), isTrue);

      await gesture.moveBy(const Offset(0.0, 80.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      // TARGET: one commit, reported to the config that is current now.
      expect(reports, <int>[1]);
      expect(controller.spanOf("m")!.rowStart, 4);
    },
  );

  testWidgets(
    "a parent rebuild with a new drag config instance runs no cell or item "
    "builder",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      Widget board() {
        return _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _countingCell,
            itemBuilder: _countingItem,
            drag: BoardDragConfig<String>(onItemMoved: (key, span) {}),
          ),
        );
      }

      await tester.pumpWidget(board());
      await tester.pumpAndSettle();
      // Setup sanity: the first build ran both builders.
      expect(_Counts.cellBuilds, greaterThan(0));
      expect(_Counts.itemBuilds, greaterThan(0));
      _Counts.reset();

      await tester.pumpWidget(board());
      await tester.pumpAndSettle();
      // TARGET: a new config instance is not a new lattice.
      expect(_Counts.cellBuilds, 0);
      expect(_Counts.itemBuilds, 0);
    },
  );

  testWidgets(
    "toggling drag enabled keeps every item's State, and the handles follow "
    "the switch",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      Widget board(bool enabled) {
        return _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _probeItem,
            drag: BoardDragConfig<String>(
              enabled: enabled,
              onItemMoved: (key, span) {},
            ),
          ),
        );
      }

      _Counts.reset();
      await tester.pumpWidget(board(true));
      // Setup sanity: one item, built once.
      expect(_Counts.inits, 1);

      await tester.pumpWidget(board(false));
      // TARGET: disabling kept the item's State.
      expect(_Counts.inits, 1);
      var gesture = await _lift(tester, "m");
      // TARGET: a disabled board lifts nothing.
      expect(controller.isDragging("m"), isFalse);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.pumpWidget(board(true));
      // TARGET: re-enabling kept it too.
      expect(_Counts.inits, 1);
      gesture = await _lift(tester, "m");
      // TARGET: and the handles are live again.
      expect(controller.isDragging("m"), isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets("toggling the resize policy keeps every item's State", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    Widget board(BoardResizeEdges edges) {
      return _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: _nullCell,
          itemBuilder: _probeItem,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {},
            onItemResized: (key, span) {},
            resizeEdges: edges,
            primaryResizeEdges: edges,
          ),
        ),
      );
    }

    _Counts.reset();
    await tester.pumpWidget(board(BoardResizeEdges.none));
    expect(_Counts.inits, 1);
    await tester.pumpWidget(board(BoardResizeEdges.both));
    // TARGET.
    expect(_Counts.inits, 1);
    await tester.pumpWidget(board(BoardResizeEdges.none));
    // TARGET.
    expect(_Counts.inits, 1);
  });

  testWidgets("toggling buildDefaultDragHandles keeps every item's State", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    Widget board(bool defaults) {
      return _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: _nullCell,
          itemBuilder: _probeItem,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {},
            buildDefaultDragHandles: defaults,
          ),
        ),
      );
    }

    _Counts.reset();
    await tester.pumpWidget(board(true));
    expect(_Counts.inits, 1);
    await tester.pumpWidget(board(false));
    // TARGET.
    expect(_Counts.inits, 1);
    await tester.pumpWidget(board(true));
    // TARGET.
    expect(_Counts.inits, 1);
  });

  testWidgets(
    "toggling selection enabled, mode and presence keeps the viewport and "
    "every cell's State",
    (tester) async {
      final controller = _controller(tester);
      Widget board(BoardSelectionConfig? selection) {
        return _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _probeCell,
            selection: selection,
          ),
        );
      }

      _Counts.reset();
      await tester.pumpWidget(
        board(const BoardSelectionConfig(onChanged: _ignoreSelection)),
      );
      final built = _Counts.inits;
      final viewport = _viewport(tester);
      // Setup sanity: all 42 cells of the 6 by 7 lattice mounted once.
      expect(built, 42);

      for (final selection in <BoardSelectionConfig?>[
        const BoardSelectionConfig(onChanged: _ignoreSelection, enabled: false),
        const BoardSelectionConfig(onChanged: _ignoreSelection),
        const BoardSelectionConfig(
          onChanged: _ignoreSelection,
          mode: BoardSelectionMode.none,
        ),
        const BoardSelectionConfig(
          onChanged: _ignoreSelection,
          mode: BoardSelectionMode.cell,
        ),
        null,
        const BoardSelectionConfig(onChanged: _ignoreSelection),
      ]) {
        await tester.pumpWidget(board(selection));
        // TARGET: the same render object and no cell re-initialized.
        expect(identical(_viewport(tester), viewport), isTrue);
        expect(_Counts.inits, built);
      }
    },
  );

  testWidgets(
    "toggling drag presence keeps the viewport and the scroll offset",
    (tester) async {
      final controller = _controller(tester, rows: 30);
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      Widget board(bool drag) {
        return _frame(
          Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            cellBuilder: _nullCell,
            itemBuilder: _countingItem,
            drag: drag
                ? BoardDragConfig<String>(onItemMoved: (key, span) {})
                : null,
          ),
        );
      }

      await tester.pumpWidget(board(false));
      vertical.jumpTo(200.0);
      await tester.pump();
      final viewport = _viewport(tester);
      await tester.pumpWidget(board(true));
      // TARGET.
      expect(identical(_viewport(tester), viewport), isTrue);
      expect(vertical.offset, 200.0);
      await tester.pumpWidget(board(false));
      // TARGET.
      expect(identical(_viewport(tester), viewport), isTrue);
      expect(vertical.offset, 200.0);
    },
  );

  testWidgets("a config that disables drag cancels a live session", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final reports = <BoardSpan>[];
    Widget board(bool enabled) {
      return _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: _nullCell,
          itemBuilder: _countingItem,
          drag: BoardDragConfig<String>(
            enabled: enabled,
            onItemMoved: (key, span) {
              reports.add(span);
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(board(true));
    final gesture = await _lift(tester, "m");
    // Setup sanity: live, with the proxy showing a second copy.
    expect(controller.isDragging("m"), isTrue);
    expect(find.byKey(_itemKey("m")), findsNWidgets(2));

    await tester.pumpWidget(board(false));
    // TARGET: the session ended with the switch.
    expect(controller.isDragging("m"), isFalse);
    await gesture.moveBy(const Offset(0.0, 80.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET: nothing was reported and the proxy is gone.
    expect(reports, isEmpty);
    expect(find.byKey(_itemKey("m")), findsOneWidget);
  });

  testWidgets(
    "a config that can no longer report a resize cancels a live resize",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
      );
      final resizes = <BoardSpan>[];
      Widget board(bool reports) {
        return _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _countingItem,
            drag: BoardDragConfig<String>(
              onItemMoved: (key, span) {},
              onItemResized: reports
                  ? (key, span) {
                      resizes.add(span);
                    }
                  : null,
              primaryResizeEdges: BoardResizeEdges.trailing,
            ),
          ),
        );
      }

      await tester.pumpWidget(board(true));
      final rect = tester.getRect(find.byKey(_itemKey("m")));
      final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.bottom - 4.0),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0.0, 30.0));
      await tester.pump();
      // Setup sanity: the trailing band started a resize.
      expect(controller.isDragging("m"), isTrue);

      await tester.pumpWidget(board(false));
      // TARGET.
      expect(controller.isDragging("m"), isFalse);
      await gesture.moveBy(const Offset(0.0, 30.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(resizes, isEmpty);
    },
  );

  testWidgets(
    "after a torn-down session the next session's proxy shows the current "
    "payload",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m", "v1"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      Widget board(bool drag) {
        return _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _labelItem,
            drag: drag
                ? BoardDragConfig<String>(onItemMoved: (key, span) {})
                : null,
          ),
        );
      }

      await tester.pumpWidget(board(true));
      var gesture = await _lift(tester, "m");
      // Setup sanity: the first session's proxy shows v1.
      expect(controller.isDragging("m"), isTrue);
      expect(find.text("v1"), findsNWidgets(2));
      // Dropping the drag config tears the drag controller down, and its
      // session with it.
      await tester.pumpWidget(board(false));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.isDragging("m"), isFalse);

      controller.updateItem("m", const _Item("m", "v2"));
      await tester.pumpWidget(board(true));
      await tester.pumpAndSettle();
      // Setup sanity: the lattice shows the new payload.
      expect(find.text("v2"), findsOneWidget);

      gesture = await _lift(tester, "m");
      expect(controller.isDragging("m"), isTrue);
      // TARGET: the proxy is built from the current payload.
      expect(find.text("v1"), findsNothing);
      expect(find.text("v2"), findsNWidgets(2));
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "an item 20 px tall with both primary edges admitted moves from its "
    "centre",
    (tester) async {
      final controller = _controller(tester, rows: 10, rowExtent: 20.0);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      final moves = <BoardSpan>[];
      final resizes = <BoardSpan>[];
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _countingItem,
            drag: BoardDragConfig<String>(
              onItemMoved: (key, span) {
                moves.add(span);
              },
              onItemResized: (key, span) {
                resizes.add(span);
              },
              primaryResizeEdges: BoardResizeEdges.both,
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(_itemKey("m")));
      // Setup sanity: a 20 px tall item.
      expect(rect.height, 20.0);
      final gesture = await tester.startGesture(
        rect.center,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0.0, 10.0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      // TARGET: a move, not a resize.
      expect(resizes, isEmpty);
      expect(moves, hasLength(1));
    },
  );

  testWidgets(
    "a disabled board's edge band leaves a tap to the item's content",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
      );
      var taps = 0;
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: (context, item) {
              return GestureDetector(
                key: _itemKey(item.key),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  taps += 1;
                },
              );
            },
            drag: BoardDragConfig<String>(
              enabled: false,
              onItemMoved: (key, span) {},
              onItemResized: (key, span) {},
              primaryResizeEdges: BoardResizeEdges.both,
              resizeEdges: BoardResizeEdges.both,
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(_itemKey("m")));
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 4.0));
      await tester.tapAt(Offset(rect.right - 4.0, rect.center.dy));
      // TARGET: both taps inside an edge band reached the content.
      expect(taps, 2);
    },
  );
}
