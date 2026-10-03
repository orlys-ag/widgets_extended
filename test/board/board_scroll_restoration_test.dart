/// Tests for item 7R of the board audit fixes: `Board.restorationId`
/// restores the two scroll offsets, and the scroll view's own build,
/// which forwards it, keeps the base's primary-controller handling.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7R", the
/// Tests list. Case numbers in the comments are that list's.
///
/// The parameter is new, so no case compiled on the tree item 7Q left.
/// Case 1 is red at its TARGET with the id not handed to the scrollable,
/// which is that tree's behaviour; cases 2 to 4 pin what the scroll
/// view's own build must keep of the base's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

BoardController<String, _Item> _controller(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(24, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(20, 40.0)),
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

Widget _app(Widget board) {
  return MaterialApp(
    restorationScopeId: "app",
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 280.0, height: 300.0, child: board),
      ),
    ),
  );
}

Widget _restorable(
  BoardController<String, _Item> controller,
  ScrollController vertical,
  ScrollController horizontal, {
  String? restorationId,
}) {
  return _app(
    Board<String, _Item>(
      controller: controller,
      restorationId: restorationId,
      verticalDetails: ScrollableDetails.vertical(controller: vertical),
      horizontalDetails: ScrollableDetails.horizontal(controller: horizontal),
      cellBuilder: (context, cell) {
        return const SizedBox.expand();
      },
    ),
  );
}

void main() {
  late ScrollController vertical;
  late ScrollController horizontal;

  setUp(() {
    vertical = ScrollController();
    horizontal = ScrollController();
  });

  tearDown(() {
    vertical.dispose();
    horizontal.dispose();
  });

  // Test 1.
  testWidgets("a board with a restorationId restores both offsets after "
      "a restart", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    await tester.pumpWidget(
      _restorable(controller, vertical, horizontal, restorationId: "board"),
    );
    vertical.jumpTo(200.0);
    horizontal.jumpTo(120.0);
    await tester.pump();

    await tester.restartAndRestore();
    // TARGET.
    expect(vertical.offset, 200.0);
    expect(horizontal.offset, 120.0);
  });

  // Test 2.
  testWidgets("without a restorationId the offsets start over",
      (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    await tester.pumpWidget(_restorable(controller, vertical, horizontal));
    vertical.jumpTo(200.0);
    horizontal.jumpTo(120.0);
    await tester.pump();
    // Setup sanity: scrolled before the restart.
    expect(vertical.offset, 200.0);
    expect(horizontal.offset, 120.0);

    await tester.restartAndRestore();
    // TARGET.
    expect(vertical.offset, 0.0);
    expect(horizontal.offset, 0.0);
  });

  // Test 3.
  testWidgets("primary: true attaches the main axis to the primary "
      "controller", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    late ScrollController primary;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            primary = PrimaryScrollController.of(context);
            return Board<String, _Item>(
              controller: controller,
              primary: true,
              cellBuilder: (context, cell) {
                return const SizedBox.expand();
              },
            );
          },
        ),
      ),
    );
    // TARGET.
    expect(primary.hasClients, isTrue);
  });

  // Test 4. A vertical list in a cell would inherit the primary
  // controller too, which the base's `PrimaryScrollController.none`
  // prevents.
  testWidgets("scroll views inside a primary board do not inherit its "
      "controller", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    late ScrollController primary;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            primary = PrimaryScrollController.of(context);
            return Board<String, _Item>(
              controller: controller,
              primary: true,
              cellBuilder: (context, cell) {
                if (cell.row != 0 || cell.col != 0) {
                  return const SizedBox.expand();
                }
                return ListView(
                  children: const <Widget>[SizedBox(height: 200.0)],
                );
              },
            );
          },
        ),
      ),
    );
    // Setup sanity: the list is built.
    expect(find.byType(ListView), findsOneWidget);
    // TARGET: the board's position alone.
    expect(primary.positions, hasLength(1));
  });
}
