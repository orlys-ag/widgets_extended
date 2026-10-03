/// Tests for item 6A of the board audit fixes: the semantics tree the
/// board produces. Its children are in PAINT order, so the node drawn on
/// top is the node explore-by-touch finds; a node the board does not show,
/// outside the viewport or under a frozen band, is kept and flagged
/// hidden; and the built-in move actions carry the framework's localized
/// labels.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 6A", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 5 left, or is a DESIGN PIN whose
/// red was shown by the mutation its comment names.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  required BoardAxisConfig columns,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns,
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Unmounts the board before the controller's own tear-down disposes it.
void _unmountFirst(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _frame(
  Widget board, {
  double width = 300.0,
  double height = 200.0,
  Iterable<LocalizationsDelegate<dynamic>>? delegates,
}) {
  return MaterialApp(
    localizationsDelegates: delegates,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: width,
          height: height,
          child: board,
        ),
      ),
    ),
  );
}

/// A cell that is its own semantics node, labelled with its position.
Widget _semanticCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return Semantics(
    key: _cellKey(cell.row, cell.col),
    container: true,
    label: "cell ${cell.row},${cell.col}",
    child: const SizedBox.expand(),
  );
}

bool _hidden(WidgetTester tester, Key key) {
  return tester
      .getSemantics(find.byKey(key))
      .getSemanticsData()
      .flagsCollection
      .isHidden;
}

/// German move labels, so a label read from the localizations is told
/// from the English literal it replaces.
class _GermanWidgets extends DefaultWidgetsLocalizations {
  const _GermanWidgets();

  @override
  String get reorderItemUp => "Nach oben";

  @override
  String get reorderItemDown => "Nach unten";

  @override
  String get reorderItemLeft => "Nach links";

  @override
  String get reorderItemRight => "Nach rechts";
}

class _GermanWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _GermanWidgetsDelegate();

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    return SynchronousFuture<WidgetsLocalizations>(const _GermanWidgets());
  }

  @override
  bool shouldReload(_GermanWidgetsDelegate old) {
    return false;
  }
}

void main() {
  // Test 1 (F3). The semantics child list is the paint order, and its
  // reverse is the hit-test order (semantics/semantics.dart:4064-4071):
  // the frozen header paints over the content cell scrolled under it, so
  // it must come after it.
  testWidgets("a frozen header cell is above the content cell under it in "
      "semantics hit-test order", (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    _unmountFirst(tester);
    final vertical = ScrollController(initialScrollOffset: 500.0);
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
          cellBuilder: _semanticCell,
        ),
      ),
    );
    final header = tester.getSemantics(find.byKey(_cellKey(0, 1)));
    final covered = tester.getSemantics(find.byKey(_cellKey(10, 1)));
    // Setup sanity: siblings, painted at the same place.
    expect(identical(header.parent, covered.parent), isTrue);
    expect(
      tester.getRect(find.byKey(_cellKey(10, 1))).top,
      tester.getRect(find.byKey(_cellKey(0, 1))).top,
    );
    final siblings = header.parent!.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.inverseHitTest,
    );
    // TARGET: the header is later in paint order, so it is hit first.
    expect(siblings.indexOf(header), greaterThan(siblings.indexOf(covered)));
    handle.dispose();
  });

  // Test 2 (F3b). An item paints over the cells it covers, but its
  // vicinity row is its START row, so the vicinity-sorted walk put a cell
  // of a later row after it.
  testWidgets("an item is above the cells it covers in semantics hit-test "
      "order", (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    _unmountFirst(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, rowSpan: 3, colStart: 1),
    );
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: _semanticCell,
          itemBuilder: (context, item) {
            return Semantics(
              key: _itemKey(item.key),
              container: true,
              label: "item ${item.key}",
              child: const SizedBox.expand(),
            );
          },
        ),
        height: 300.0,
      ),
    );
    final item = tester.getSemantics(find.byKey(_itemKey("m")));
    final covered = tester.getSemantics(find.byKey(_cellKey(3, 1)));
    // Setup sanity: siblings, and the item's rect covers the cell's.
    expect(identical(item.parent, covered.parent), isTrue);
    final itemRect = tester.getRect(find.byKey(_itemKey("m")));
    final cellRect = tester.getRect(find.byKey(_cellKey(3, 1)));
    expect(itemRect.intersect(cellRect), cellRect);
    final siblings = item.parent!.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.inverseHitTest,
    );
    // TARGET.
    expect(siblings.indexOf(item), greaterThan(siblings.indexOf(covered)));
    handle.dispose();
  });

  // Test 3 (F4). A cell built in the cache region, wholly below the
  // viewport, is not shown; it stays in the tree, for a screen reader's
  // implicit scrolling, and is flagged hidden.
  testWidgets("a cache-region cell outside the viewport is kept in "
      "semantics and flagged hidden", (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    _unmountFirst(tester);
    await tester.pumpWidget(
      _frame(Board<String, _Item>(controller: controller, cellBuilder: _semanticCell)),
    );
    final frame = tester.getRect(find.byKey(_frameKey));
    // Setup sanity: row 5 is built and lies wholly below the viewport;
    // row 1 is on screen and is not hidden.
    expect(
      tester.getRect(find.byKey(_cellKey(5, 0))).top,
      greaterThanOrEqualTo(frame.bottom),
    );
    expect(_hidden(tester, _cellKey(1, 0)), isFalse);
    // TARGET: kept IN THE TREE (a node whose rect the clip empties is
    // dropped from its parent's children, rendering/object.dart:6246,
    // while `getSemantics` still returns it), and hidden.
    final node = tester.getSemantics(find.byKey(_cellKey(5, 0)));
    expect(node.parent, isNotNull);
    expect(node.getSemanticsData().flagsCollection.isHidden, isTrue);
    handle.dispose();
  });

  // Test 4 (B). A content cell scrolled under a frozen header band
  // paints, and the band paints over it: it is not shown.
  testWidgets("a scrolled cell under a frozen band is flagged hidden",
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    _unmountFirst(tester);
    final vertical = ScrollController(initialScrollOffset: 500.0);
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
          cellBuilder: _semanticCell,
        ),
      ),
    );
    // Setup sanity: row 10 is wholly under the 50-tall header band, and
    // row 11, just below the band, is not hidden.
    expect(
      tester.getRect(find.byKey(_cellKey(10, 1))),
      tester.getRect(find.byKey(_cellKey(0, 1))),
    );
    expect(_hidden(tester, _cellKey(11, 1)), isFalse);
    // TARGET.
    expect(_hidden(tester, _cellKey(10, 1)), isTrue);
    // The header itself is shown.
    expect(_hidden(tester, _cellKey(0, 1)), isFalse);
    handle.dispose();
  });

  // Test 5 (B). A header-row cell is pinned vertically and scrolls
  // horizontally, so the frozen corner covers it once it slides under
  // the frozen column: on its scrolling axis its region is the scrolled
  // one, not the viewport.
  testWidgets("a header cell slid under the frozen corner is flagged "
      "hidden, and the corner cell is not", (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(10, 100.0), frozenStart: 1),
    );
    _unmountFirst(tester);
    final horizontal = ScrollController(initialScrollOffset: 250.0);
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          horizontalDetails: ScrollableDetails.horizontal(
            controller: horizontal,
          ),
          cellBuilder: _semanticCell,
        ),
      ),
    );
    final frame = tester.getRect(find.byKey(_frameKey));
    // Setup sanity: header cell (0, 2) paints at -50 to 50, under the
    // 100-wide frozen column; (0, 3) reaches out past it.
    final slid = tester.getRect(find.byKey(_cellKey(0, 2)));
    expect(slid.left - frame.left, closeTo(-50.0, 0.01));
    expect(_hidden(tester, _cellKey(0, 3)), isFalse);
    // TARGET: covered, so hidden ...
    expect(_hidden(tester, _cellKey(0, 2)), isTrue);
    // ... while the corner is shown.
    expect(_hidden(tester, _cellKey(0, 0)), isFalse);
    handle.dispose();
  });

  // Test 6 (B's rule). A render object that clips with a `Clip` must
  // describe no paint clip under `Clip.none`
  // (rendering/object.dart:3747-3750). DESIGN PIN: red under a mutation
  // that describes the clip whatever `clipBehavior` says.
  testWidgets("under Clip.none no cell is hidden by the board",
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    _unmountFirst(tester);
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          clipBehavior: Clip.none,
          cellBuilder: _semanticCell,
        ),
      ),
    );
    final frame = tester.getRect(find.byKey(_frameKey));
    expect(
      tester.getRect(find.byKey(_cellKey(5, 0))).top,
      greaterThanOrEqualTo(frame.bottom),
    );
    expect(_hidden(tester, _cellKey(5, 0)), isFalse);
    handle.dispose();
  });

  // Test 7 (D). The move labels are the framework's localized strings.
  testWidgets("the move actions read their labels from "
      "WidgetsLocalizations", (tester) async {
    final handle = tester.ensureSemantics();
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    _unmountFirst(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          drag: BoardDragConfig<String>(onItemMoved: (key, span) {}),
          cellBuilder: (context, cell) {
            return const SizedBox.expand();
          },
          itemBuilder: (context, item) {
            return ColoredBox(
              key: _itemKey(item.key),
              color: const Color(0xFF4CAF50),
            );
          },
        ),
        height: 300.0,
        delegates: const <LocalizationsDelegate<dynamic>>[
          _GermanWidgetsDelegate(),
        ],
      ),
    );
    final ids = tester
        .getSemantics(find.byKey(_itemKey("m")))
        .getSemanticsData()
        .customSemanticsActionIds;
    int id(String label) {
      return CustomSemanticsAction.getIdentifier(
        CustomSemanticsAction(label: label),
      );
    }

    // TARGET: all four, in German, and no English literal.
    expect(
      ids,
      containsAll(<int>[
        id("Nach oben"),
        id("Nach unten"),
        id("Nach links"),
        id("Nach rechts"),
      ]),
    );
    expect(ids, isNot(contains(id("Move up"))));
    handle.dispose();
  });
}
