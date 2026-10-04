/// Tests for items 7B, 7C and 7D of the board audit fixes: an item
/// entering or leaving a board with no lane axis shows it, and an item
/// leaving takes no pointer (7B); an item keeps its `State` when its
/// vicinity changes (7C); re-adding a key whose exit is running reverses
/// that exit (7D).
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, the Tests list
/// of each item. Case numbers in the comments are those lists'.
///
/// Every TARGET was red on the tree the previous item left, with every
/// setup sanity assertion before it passing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAnimationStyle style = const BoardAnimationStyle(),
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
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

Widget _host(Widget board) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(key: _frameKey, width: 280.0, height: 300.0, child: board),
      ),
    ),
  );
}

void main() {
  // Test 1 is gone with finding A5, which the plan withdrew: the board
  // reports every selection change to `onChanged` by design, and
  // board_selection_test.dart pins that.

  // Test 2 (B). No lane axis: the ramp scales the item along the primary
  // axis, the rows here, so it shrinks in height and keeps its columns.
  testWidgets("an exit on a lane-less board shrinks along the primary axis",
      (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 1, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: (context, item) {
            return ColoredBox(
              key: _itemKey(item.key),
              color: const Color(0xFF4CAF50),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final full = tester.getRect(find.byKey(_itemKey("a")));
    expect(controller.primaryAxis, Axis.vertical);
    controller.removeItem("a");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Setup sanity: mid-exit, still mounted.
    expect(controller.contains("a"), isFalse);
    expect(find.byKey(_itemKey("a")), findsOneWidget);
    final mid = tester.getRect(find.byKey(_itemKey("a")));
    // TARGET: half the height, the same width and top.
    expect(mid.height, closeTo(full.height / 2, 0.5));
    expect(mid.width, full.width);
    expect(mid.top, full.top);
    await tester.pumpAndSettle();
    expect(find.byKey(_itemKey("a")), findsNothing);

    // An enter grows the same way.
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.getRect(find.byKey(_itemKey("b"))).height,
      closeTo(full.height / 2, 0.5),
    );
    await tester.pumpAndSettle();
  });

  // Test 3 (C).
  testWidgets("a tap on an exiting item reaches what lies under it",
      (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    controller.addItem(
      const _Item("under"),
      const BoardSpan(rowStart: 1, colStart: 1, colSpan: 2),
    );
    controller.addItem(
      const _Item("over"),
      const BoardSpan(rowStart: 1, colStart: 1, colSpan: 2),
    );
    final taps = <String>[];
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: (context, item) {
            return GestureDetector(
              key: _itemKey(item.key),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                taps.add(item.key);
              },
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getRect(find.byKey(_itemKey("over"))).center;
    // Setup sanity: the two overlap, and "over" takes the tap.
    await tester.tapAt(center);
    await tester.pump();
    expect(taps, <String>["over"]);
    controller.removeItem("over");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Setup sanity: exiting and still mounted over "under".
    expect(controller.contains("over"), isFalse);
    expect(find.byKey(_itemKey("over")), findsOneWidget);
    await tester.tapAt(center);
    await tester.pump();
    // TARGET: the tap went to the item underneath.
    expect(taps, <String>["over", "under"]);
    await tester.pumpAndSettle();
  });

  // Item 7C. The item's child carries a key naming the item, so the
  // viewport element retrieves it by key wherever its vicinity moves.
  group("an item keeps its State when its vicinity changes", () {
    Widget board(BoardController<String, _Item> controller) {
      return _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: (context, item) {
            return _Counted(key: _itemKey(item.key), label: item.key);
          },
        ),
      );
    }

    // Test 7C.1. b sorts before a on a's start row, so a's rank, the
    // xIndex of its vicinity, goes from 0 to 1.
    testWidgets("a rank shift keeps an item's State", (tester) async {
      final controller = _controller(
        tester,
        style: BoardAnimationStyle.disabled,
      );
      _unmountFirst(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 3),
      );
      _Counted.inits.clear();
      await tester.pumpWidget(board(controller));
      expect(_Counted.inits, <String>["a"]);
      final aId = controller.idOfKey("a");
      expect(controller.vicinityOrdinalOfId(aId), 0);
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 1, colStart: 0),
      );
      await tester.pump();
      // Setup sanity: a was re-ranked.
      expect(controller.vicinityOrdinalOfId(aId), 1);
      // TARGET: only b was built; a kept its State.
      expect(_Counted.inits, <String>["a", "b"]);
    });

    // Test 7C.2. The vicinity's yIndex is the primary start track.
    testWidgets("a move to another row keeps an item's State",
        (tester) async {
      final controller = _controller(
        tester,
        style: BoardAnimationStyle.disabled,
      );
      _unmountFirst(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 3),
      );
      _Counted.inits.clear();
      await tester.pumpWidget(board(controller));
      controller.moveItem("a", const BoardSpan(rowStart: 4, colStart: 3));
      await tester.pump();
      // Setup sanity: a paints on row 4 now.
      expect(tester.getRect(find.byKey(_itemKey("a"))).top, 200.0);
      // TARGET: built once, ever.
      expect(_Counted.inits, <String>["a"]);
    });

    // Test 7C.3. A removal then an addition in one frame hands the new
    // item the released id; a vicinity-only lookup hands it the dead
    // item's element and, when the app's content carries no key of its
    // own, its State. The content here carries none.
    testWidgets("an id recycled under another key does not inherit the dead "
        "item's State", (tester) async {
      final controller = _controller(
        tester,
        style: BoardAnimationStyle.disabled,
      );
      _unmountFirst(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 3),
      );
      _Counted.inits.clear();
      await tester.pumpWidget(
        _host(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return null;
            },
            itemBuilder: (context, item) {
              return _Counted(label: item.key);
            },
          ),
        ),
      );
      final aId = controller.idOfKey("a");
      controller.removeItem("a");
      controller.addItem(
        const _Item("c"),
        const BoardSpan(rowStart: 1, colStart: 3),
      );
      await tester.pump();
      // Setup sanity: c took a's id, at a's vicinity.
      expect(controller.idOfKey("c"), aId);
      // TARGET: c was built fresh ...
      expect(_Counted.inits, <String>["a", "c"]);
      // ... and shows its own label, not a State made for a.
      expect(find.text("c"), findsOneWidget);
    });
  });

  // Item 7D. Re-adding a key while its exit runs brings the same item
  // back, from where its ramp stands. A board with no lane axis ramps
  // along the rows (7B), so the height is the ramp. None of these cases
  // counts `State` creations: since 7C keys each lattice child by its
  // item, a retire followed by a fresh allocation keeps the element as
  // well, so such a count cannot tell the two apart.
  group("re-adding a key whose exit is running", () {
    Widget board(BoardController<String, _Item> controller) {
      return _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: (context, item) {
            return SizedBox.expand(key: _itemKey(item.key));
          },
        ),
      );
    }

    // Test 7D.1.
    testWidgets("re-adding a key mid-exit grows it back from where it "
        "stands", (tester) async {
      final controller = _controller(tester);
      _unmountFirst(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 1, colSpan: 2),
      );
      await tester.pumpWidget(board(controller));
      await tester.pumpAndSettle();
      final full = tester.getRect(find.byKey(_itemKey("a"))).height;
      controller.removeItem("a");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final half = tester.getRect(find.byKey(_itemKey("a"))).height;
      // Setup sanity: half way out.
      expect(half, closeTo(full / 2, 0.5));

      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 1, colSpan: 2),
      );
      await tester.pump();
      // TARGET: the frame of the re-add paints where the exit stood ...
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).height,
        closeTo(half, 0.5),
      );
      // ... it grows back over the half of the duration it had left ...
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).height,
        closeTo(full * 0.75, 0.5),
      );
      // ... and is whole when that half has run.
      await tester.pump(const Duration(milliseconds: 75));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(find.byKey(_itemKey("a"))).height, full);
    });

    // Test 7D.2.
    testWidgets("re-adding a key mid-exit at another span slides it there",
        (tester) async {
      final controller = _controller(
        tester,
        style: const BoardAnimationStyle(
          trackResize: BoardAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
          itemEnterExit: BoardAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
          itemSlide: BoardAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
        ),
      );
      _unmountFirst(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      await tester.pumpWidget(board(controller));
      await tester.pumpAndSettle();
      final full = tester.getRect(find.byKey(_itemKey("a"))).height;
      controller.removeItem("a");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Setup sanity: the exit is running, a third of the way out.
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).height,
        closeTo(full * 2 / 3, 0.5),
      );
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 4),
      );
      await tester.pump();
      // TARGET: it starts from where it painted, column 1 ...
      expect(tester.getRect(find.byKey(_itemKey("a"))).left, 40.0);
      await tester.pump(const Duration(milliseconds: 100));
      // ... and slides to column 4 on the itemSlide clock.
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).left,
        closeTo(100.0, 0.5),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_itemKey("a"))).left, 160.0);
    });

    // Test 7D.3.
    testWidgets("setItems re-adding a key mid-exit reverses the exit too",
        (tester) async {
      final controller = _controller(tester);
      _unmountFirst(tester);
      const placement = BoardPlacement<_Item>(
        _Item("a"),
        BoardSpan(rowStart: 1, colStart: 1, colSpan: 2),
      );
      controller.setItems(const <BoardPlacement<_Item>>[placement]);
      await tester.pumpWidget(board(controller));
      await tester.pumpAndSettle();
      final full = tester.getRect(find.byKey(_itemKey("a"))).height;
      controller.setItems(const <BoardPlacement<_Item>>[]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final half = tester.getRect(find.byKey(_itemKey("a"))).height;
      expect(half, closeTo(full / 2, 0.5));
      controller.setItems(const <BoardPlacement<_Item>>[placement]);
      await tester.pump();
      // TARGET: no pop ...
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).height,
        closeTo(half, 0.5),
      );
      // ... and whole at the end of the reversed ramp.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(find.byKey(_itemKey("a"))).height, full);
    });

    // Test 7D.5. The setItems door re-spans a resurrected key through
    // its own capture pre-pass, not through the per-call slide.
    testWidgets("setItems re-adding a key mid-exit at another span slides "
        "it there", (tester) async {
      final controller = _controller(
        tester,
        style: const BoardAnimationStyle(
          trackResize: BoardAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
          itemEnterExit: BoardAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
          itemSlide: BoardAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
        ),
      );
      _unmountFirst(tester);
      controller.setItems(const <BoardPlacement<_Item>>[
        BoardPlacement<_Item>(_Item("a"), BoardSpan(rowStart: 1, colStart: 1)),
      ]);
      await tester.pumpWidget(board(controller));
      await tester.pumpAndSettle();
      final full = tester.getRect(find.byKey(_itemKey("a"))).height;
      controller.setItems(const <BoardPlacement<_Item>>[]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Setup sanity: the exit is running, a third of the way out.
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).height,
        closeTo(full * 2 / 3, 0.5),
      );
      controller.setItems(const <BoardPlacement<_Item>>[
        BoardPlacement<_Item>(_Item("a"), BoardSpan(rowStart: 1, colStart: 4)),
      ]);
      await tester.pump();
      // TARGET: it starts from where it painted, column 1 ...
      expect(tester.getRect(find.byKey(_itemKey("a"))).left, 40.0);
      await tester.pump(const Duration(milliseconds: 100));
      // ... and slides to column 4 on the itemSlide clock.
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).left,
        closeTo(100.0, 0.5),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_itemKey("a"))).left, 160.0);
    });

    // Test 7D.4. The reversal's bits. Under a live family exactly the
    // entering bit is left, from the ramp the exit reached. A restyle to
    // a zero itemEnterExit leaves a running exit's record for the next
    // tick to drive past 1, and a re-add in that window leaves no bit and
    // the item whole.
    testWidgets("a reversed exit leaves only the entering bit, or none "
        "under a zero family", (tester) async {
      final controller = _controller(tester);
      _unmountFirst(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 3, colStart: 1),
      );
      await tester.pumpWidget(board(controller));
      await tester.pumpAndSettle();
      final idA = controller.idOfKey("a");
      final idB = controller.idOfKey("b");
      controller.removeItem("a");
      controller.removeItem("b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final held = controller.anim.enterExitProgressOf(idA);
      // Setup sanity: a third of the way out.
      expect(held, closeTo(2 / 3, 1e-6));

      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      // TARGET: the entering bit only, from where the exit stood.
      expect(controller.anim.isExitingItem(idA), isFalse);
      expect(controller.anim.isEnteringItem(idA), isTrue);
      expect(controller.anim.enterExitProgressOf(idA), closeTo(held, 1e-9));

      controller.animationStyle = const BoardAnimationStyle(
        itemEnterExit: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );
      // Setup sanity: the restyle left b's exit for the next tick.
      expect(controller.anim.isExitingItem(idB), isTrue);
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 3, colStart: 1),
      );
      // TARGET: no bit, and the item whole.
      expect(controller.anim.isExitingItem(idB), isFalse);
      expect(controller.anim.isEnteringItem(idB), isFalse);
      expect(controller.anim.enterExitProgressOf(idB), 1.0);
      // A record left behind with no bit would settle on the next tick
      // into `finalizeEnterExit`'s exactly-one-bit assert.
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_itemKey("b"))).height, 50.0);
    });
  });
}

/// Counts its `State` creations, with the label it was built for.
class _Counted extends StatefulWidget {
  const _Counted({super.key, required this.label});

  final String label;

  static final List<String> inits = <String>[];

  @override
  State<_Counted> createState() {
    return _CountedState();
  }
}

class _CountedState extends State<_Counted> {
  late final String _builtFor;

  @override
  void initState() {
    super.initState();
    _builtFor = widget.label;
    _Counted.inits.add(widget.label);
  }

  @override
  Widget build(BuildContext context) {
    return Text(_builtFor, textDirection: TextDirection.ltr);
  }
}
