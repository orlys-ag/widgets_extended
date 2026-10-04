/// The controller's model hygiene: what a batch delivers for a key that
/// left the board before its notification's turn, the span components the
/// store can hold, where an item past the lattice is found, and which
/// content track the cluster check reports an item on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key, [this.label = ""]);

  final String key;
  final String label;
}

/// A controller on [rows] and [columns], by default two fixed axes, so the
/// row axis is the primary one and there is no lane axis.
BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAxisConfig? rows,
  BoardAxisConfig? columns,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows ?? BoardAxisConfig(axis: UniformAxis(6, 40.0)),
    columns: columns ?? BoardAxisConfig(axis: UniformAxis(7, 60.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Records every structural notification, copying each key set so a later
/// mutation cannot rewrite what was already delivered.
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

/// Records every item-data notification, in order.
List<String> _logItemData(BoardController<String, _Item> controller) {
  final log = <String>[];
  void listener(String key) {
    log.add(key);
  }

  controller.addItemDataListener(listener);
  addTearDown(() {
    controller.removeItemDataListener(listener);
  });
  return log;
}

void main() {
  group("a batch's notifications for a key that left the board", () {
    testWidgets("a batch does not deliver item data for a key it retired", (
      tester,
    ) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      final data = _logItemData(controller);
      controller.runBatch(() {
        controller.updateItem("a", const _Item("a", "changed"));
        controller.removeItem("a");
      });
      // Setup sanity: the zero itemEnterExit retired the key at once.
      expect(controller.contains("a"), isFalse);
      expect(controller.idOfKey("a"), -1);
      // TARGET.
      expect(data, isEmpty);
    });

    testWidgets("a batch delivers item data for a key whose exit is still "
        "running", (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      controller.animationStyle = const BoardAnimationStyle(
        itemEnterExit: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      final data = _logItemData(controller);
      controller.runBatch(() {
        controller.updateItem("a", const _Item("a", "changed"));
        controller.removeItem("a");
      });
      // Setup sanity: the key left the live set and still holds its id,
      // its exit running.
      expect(controller.contains("a"), isFalse);
      expect(controller.idOfKey("a"), greaterThanOrEqualTo(0));
      // TARGET.
      expect(data, <String>["a"]);
      // The exit's first frame starts its clock; the second runs it out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets("a batch does not deliver item data for a key a structural "
        "listener retired", (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 1, colStart: 0),
      );
      var ran = false;
      void retireA(Set<String>? affectedKeys) {
        if (!ran && affectedKeys != null && affectedKeys.contains("b")) {
          ran = true;
          controller.removeItem("a");
        }
      }

      controller.addStructuralListener(retireA);
      addTearDown(() {
        controller.removeStructuralListener(retireA);
      });
      final data = _logItemData(controller);
      controller.runBatch(() {
        controller.updateItem("a", const _Item("a", "changed"));
        controller.moveItem("b", const BoardSpan(rowStart: 2, colStart: 0));
      });
      // Setup sanity: the listener ran and retired the key.
      expect(ran, isTrue);
      expect(controller.contains("a"), isFalse);
      // TARGET.
      expect(data, isEmpty);
    });

    testWidgets("a batch's structural set drops a retired key and keeps a "
        "re-added one", (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 1, colStart: 0),
      );
      final structural = _logStructural(controller);
      controller.runBatch(() {
        controller.moveItem("a", const BoardSpan(rowStart: 2, colStart: 0));
        controller.removeItem("a");
      });
      // TARGET: a key retired in the batch is not named.
      expect(structural, <Set<String>?>[<String>{}]);
      controller.runBatch(() {
        controller.removeItem("b");
        controller.addItem(
          const _Item("b"),
          const BoardSpan(rowStart: 3, colStart: 0),
        );
      });
      // TARGET: a key retired and added back in the batch is named.
      expect(structural, <Set<String>?>[
        <String>{},
        <String>{"b"},
      ]);
    });
  });

  group("the store's span range", () {
    for (final (name, span) in <(String, BoardSpan)>[
      ("row start", const BoardSpan(rowStart: 1 << 31, colStart: 0)),
      ("column start", const BoardSpan(rowStart: 0, colStart: 1 << 31)),
      ("row span", const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 1 << 31)),
      (
        "column span",
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 1 << 31),
      ),
    ]) {
      testWidgets("a $name past the store's range is refused before it "
          "touches the board", (tester) async {
        final controller = _controller(tester);
        // TARGET: refused.
        expect(() {
          controller.addItem(const _Item("x"), span);
        }, throwsArgumentError);
        // TARGET: before anything was written.
        expect(controller.contains("x"), isFalse);
        expect(controller.itemCount, 0);
      });
    }

    testWidgets("a span component at the store's bound round-trips exactly", (
      tester,
    ) async {
      final controller = _controller(tester);
      const span = BoardSpan(
        rowStart: 0x7FFFFFFF,
        colStart: 0,
        colSpan: 0x7FFFFFFF,
      );
      controller.addItem(const _Item("x"), span);
      // TARGET.
      expect(controller.spanOf("x"), span);
    });
  });

  group("a span past the lattice", () {
    testWidgets("a span past the lattice is listed wherever it lies across "
        "axis swaps", (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(10, 40.0)),
      );
      controller.addItem(
        const _Item("long"),
        const BoardSpan(rowStart: 5, rowSpan: 1000, colStart: 0),
      );
      controller.addItem(
        const _Item("far"),
        const BoardSpan(rowStart: 50, colStart: 1),
      );
      // TARGET: found where it lies, past the lattice.
      expect(controller.itemsIn(500, 501, 0, 1), <String>["long"]);
      controller.rows = BoardAxisConfig(axis: UniformAxis(100, 40.0));
      controller.rows = BoardAxisConfig(axis: UniformAxis(20, 40.0));
      controller.removeItem("long");
      // The new key takes the removed one's id back off the free list.
      controller.addItem(
        const _Item("new"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      controller.rows = BoardAxisConfig(axis: UniformAxis(100, 40.0));
      // TARGET.
      expect(controller.itemsIn(20, 100, 0, 7), <String>["far"]);
    });
  });

  group("the content axis's cluster check", () {
    testWidgets("the cluster check reports an item a rounding error below a "
        "track on that track", (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: LazyContentAxis(6, 30.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      );
      // One rounding step below row 1, ending inside it.
      controller.addItem(
        const _Item("chip"),
        const BoardSpan(
          rowStart: 0,
          colStart: 1,
          rowFraction: 0.9999999999999999,
          rowSpan: 0,
          rowSpanFraction: 0.5,
        ),
      );
      // Setup sanity: the start rule puts it on row 1.
      final id = controller.idOfKey("chip");
      expect(controller.startIndexOfId(id, Axis.vertical), 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return const SizedBox(height: 30.0);
            },
            itemBuilder: (context, item) {
              return const ColoredBox(color: Color(0xFF4CAF50));
            },
          ),
        ),
      );
      // TARGET.
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains("intra-track item cluster"));
      expect(error.toString(), contains("track(s) 1 and"));
    });
  });
}
