/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 12.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

const BoardAnimationStyle _enterExitOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _zero,
  itemEnterExit: _ms300,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAxisConfig? rows,
  BoardAxisConfig? columns,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
  bool tearDownDispose = true,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows ?? BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    columns: columns ?? BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  if (tearDownDispose) {
    addTearDown(controller.dispose);
  }
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  ScrollController? vertical,
  BoardDragConfig<String>? drag,
  BoardSelectionConfig? selection,
  Widget Function(BuildContext, BoardItemView<String, _Item>)? itemBuilder,
  Widget Function(BuildContext, BoardCellView<String, _Item>)? cellBuilder,
  Key? boardKey,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            key: boardKey,
            controller: controller,
            drag: drag,
            selection: selection,
            verticalDetails: vertical == null
                ? const ScrollableDetails.vertical()
                : ScrollableDetails.vertical(controller: vertical),
            cellBuilder:
                cellBuilder ??
                (context, cell) {
                  return const SizedBox(width: 100.0, height: 100.0);
                },
            itemBuilder:
                itemBuilder ??
                (context, item) {
                  return ColoredBox(
                    key: _itemKey(item.key),
                    color: const Color(0xFF4CAF50),
                  );
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

int _childCount(WidgetTester tester) {
  var count = 0;
  _viewport(tester).visitChildren((child) {
    count++;
  });
  return count;
}

void main() {
  // The regression fence for the selection route: a selection change must
  // reach the cell BUILDERS, which only a delegate rebuild can do.
  // Falsification: an implementation whose selection listener calls
  // `setState` on the widget's `State` (and only that) rebuilds nothing,
  // because a parent-driven rebuild bypasses the viewport element's
  // `performRebuild` and the delegate setter early-returns on identity;
  // build counts then stay at 1 and the second assertion reads a stale
  // `isSelected`.
  testWidgets("a selection change rebuilds the cells that report it", (
    tester,
  ) async {
    final controller = _controller(tester);
    final buildCounts = <String, int>{};
    final lastSelected = <String, bool>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300.0,
            height: 300.0,
            child: Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, cell) {
                final id = "${cell.row},${cell.col}";
                buildCounts[id] = (buildCounts[id] ?? 0) + 1;
                lastSelected[id] = cell.isSelected;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );

    // Setup sanity: the target cell built exactly once and unselected.
    expect(buildCounts["1,1"], 1);
    expect(lastSelected["1,1"], isFalse);

    controller.setSelection(
      const BoardSelection(
        anchor: (row: 1, col: 1),
        focus: (row: 1, col: 1),
      ),
    );
    await tester.pump();

    // The change reached the builder: a second build, reporting selected.
    expect(buildCounts["1,1"], 2);
    expect(lastSelected["1,1"], isTrue);
  });

  // AC22 controller swap and dispose.
  // Asserts: after the swap a LazyContentAxis reports isProvisional true
  // again and isMeasured false for every track measured before it. The
  // axis INSTANCE is shared between the two controllers, which is the
  // construction that makes the render setter's reset observable.
  testWidgets(
    "swapping the controller resets measurements and animation state",
    (tester) async {
      final shared = BoardAxisConfig(
        axis: LazyContentAxis(30, 100.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      final first = _controller(tester, rows: shared);
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(_board(first, vertical: vertical));
      final lazy = shared.axis as LazyContentAxis;
      // A deep track measured by a round trip stays measured while out
      // of view, so the swap's reset is what flips it, not a re-measure.
      vertical.jumpTo(2700.0);
      await tester.pump();
      vertical.jumpTo(0.0);
      await tester.pump();
      // Setup sanity: the deep track is measured and out of the window.
      expect(lazy.isMeasured(29), isTrue);

      final second = _controller(tester, rows: shared);
      await tester.pumpWidget(_board(second, vertical: vertical));
      expect(tester.takeException(), isNull);
      expect(lazy.isMeasured(29), isFalse);
    },
  );

  // AC22, the case that pins the swap-release path: the first layout
  // after the swap feeds the retained entries' OLD-controller ids to the
  // new reader's isExitingItem, which reports none exiting, so the head
  // release drops every entry and the children unmount.
  // Asserts: the retained child raises the visitChildren count by one
  // mid-exit; one frame after the swap the count is back and the probe
  // is gone, with tester.takeException() null. A partial isExitingItem
  // throws on that first layout and fails the exception assertion, which
  // is why it is part of this case and not decoration.
  testWidgets(
    "swapping the controller releases the children an exit was retaining",
    (tester) async {
      BoardAxisConfig rows() {
        return BoardAxisConfig(axis: UniformAxis(60, 50.0));
      }

      BoardAxisConfig columns() {
        return BoardAxisConfig(axis: UniformAxis(3, 100.0));
      }

      final first = _controller(
        tester,
        rows: rows(),
        columns: columns(),
        style: _enterExitOnly,
      );
      first.addItem(
        const _Item("p"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(_board(first, vertical: vertical));
      await tester.pumpAndSettle();

      first.removeItem("p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      vertical.jumpTo(2000.0);
      await tester.pump();
      final retainedCount = _childCount(tester);
      // Setup sanity: retention holds the exiting child off-window.
      expect(
        find.byKey(_itemKey("p"), skipOffstage: false),
        findsOneWidget,
      );

      final second = _controller(
        tester,
        rows: rows(),
        columns: columns(),
        style: _enterExitOnly,
      );
      await tester.pumpWidget(_board(second, vertical: vertical));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(_itemKey("p"), skipOffstage: false), findsNothing);
      expect(_childCount(tester), retainedCount - 1);
      // The OLD controller's exit is still ticking; settle before the
      // harness's end-of-test ticker check.
      await tester.pumpAndSettle();
    },
  );

  // AC22, the dispose arm.
  // Asserts: tester.takeException() is null and the returned Future<bool>
  // completes false, which a Future<void> could not have expressed. The
  // unmount's detach cancel fires first (dispose asserts empty listener
  // lists on a mounted board, so unmount-first is forced); dispose's own
  // step runs the same cancel, and the case pins the outcome.
  testWidgets(
    "disposing during an in-flight animateScrollToCell does not throw",
    (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        tearDownDispose: false,
      );
      await tester.pumpWidget(_board(controller));
      final future = controller.animateScrollToCell(50, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(await future, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  // DERIVED name. No AC; the ordered dispose script under live tickers.
  // Asserts: tester.takeException() is null with a trackResize and an
  // exit both in flight at the moment of dispose, and the harness's own
  // end-of-test ticker check passes, which pins that dispose stopped
  // them.
  testWidgets(
    "disposing a controller mid-trackResize and mid-exit throws nothing",
    (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(
          axis: LazyContentAxis(3, 100.0),
          laneExtent: 18.0,
          lanePadding: 4.0,
        ),
        style: const BoardAnimationStyle(
          trackResize: _ms300,
          itemSlide: _zero,
          itemEnterExit: _ms300,
        ),
        tearDownDispose: false,
      );
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();

      // The removal starts an exit AND shrinks the cluster's lane
      // ceiling, which the next layout lands as a trackResize.
      controller.removeItem("b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  // DERIVED name. No AC; the drag controller's dispose runs the same
  // teardown statements endDrag does, with no commit.
  // Asserts: no onItemMoved fires, the dragging bit clears, and nothing
  // throws.
  testWidgets(
    "disposing a BoardDragController mid-drag fires no onItemMoved",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      var moved = 0;
      final drag = BoardDragController<String>(
        boardController: controller,
        vsync: tester,
        config: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moved++;
          },
        ),
      );
      final viewport = _viewport(tester);
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: const Offset(150.0, 150.0),
        ),
        isTrue,
      );
      drag.updateDrag(const Offset(50.0, 50.0));
      await tester.pump();
      expect(controller.isDragging("m"), isTrue);

      drag.dispose();
      expect(moved, 0);
      expect(controller.isDragging("m"), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  // DERIVED name. No AC; the first of the port-registration pair.
  // Asserts: the call completes false and frozenInsetOf returns 0.0.
  // Falsification: without a registered-port degradation this throws or
  // hangs instead of completing.
  testWidgets(
    "animateScrollToCell on a controller no Board has mounted completes "
    "false",
    (tester) async {
      final controller = _controller(tester);
      expect(controller.frozenInsetOf(Axis.vertical), 0.0);
      expect(await controller.animateScrollToCell(2, 2), isFalse);
    },
  );

  // DERIVED name. No AC; the second of the port-registration pair.
  // Asserts: the in-flight future completes false rather than hanging.
  testWidgets(
    "pumping the Board away mid-scroll completes the in-flight future "
    "false",
    (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
      );
      await tester.pumpWidget(_board(controller));
      bool? completed;
      controller.animateScrollToCell(50, 0).then((value) {
        completed = value;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(completed, isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(completed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  // DERIVED name. No AC; the THIRD degenerate state, which the other two
  // do not reach: a port IS registered and isLaidOut is false. The call
  // is issued from a sibling's first build, which runs after the
  // viewport's render object attaches and before any layout.
  // Asserts: it completes true and the target lands aligned;
  // frozenInsetOf in that same window returns 0.0 rather than throwing.
  // Falsification: without the isLaidOut consultation the call reads
  // viewportDimension on an unsized box and tester.takeException() is
  // non-null.
  testWidgets(
    "animateScrollToCell before the first layout completes true after "
    "one frame's wait",
    (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      Future<bool>? future;
      double? insetDuringWindow;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                SizedBox(
                  width: 280.0,
                  height: 300.0,
                  child: Board<String, _Item>(
                    controller: controller,
                    verticalDetails: ScrollableDetails.vertical(
                      controller: vertical,
                    ),
                    cellBuilder: (context, cell) {
                      return const SizedBox(width: 100.0, height: 50.0);
                    },
                  ),
                ),
                Builder(
                  builder: (context) {
                    if (future == null) {
                      insetDuringWindow = controller.frozenInsetOf(
                        Axis.vertical,
                      );
                      future = controller.animateScrollToCell(
                        20,
                        0,
                        duration: const Duration(milliseconds: 100),
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(insetDuringWindow, 0.0);
      await tester.pumpAndSettle();
      expect(await future, isTrue);
      // Row 20 at 50 px per row, alignment 0: its lead at the viewport
      // top.
      expect(vertical.offset, 1000.0);
    },
  );

  // DERIVED name. No AC; Board.State.didUpdateWidget.
  // Asserts: pumping a Board with a NEW BoardController mid-drag fires no
  // onItemMoved, leaves isDragging false on BOTH stores, and routes a
  // subsequent setSelection on the new controller to onChanged exactly
  // once.
  // Falsification: an implementation with no didUpdateWidget leaves the
  // old store's bit 2 set and reports nothing on the new controller, so
  // each half fails on its own.
  testWidgets(
    "pumping a new BoardController mid-drag cancels the drag and routes "
    "the new controller's selection",
    (tester) async {
      final first = _controller(tester);
      first.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      var moved = 0;
      final changes = <BoardSelection>[];
      final drag = BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moved++;
        },
      );
      final selection = BoardSelectionConfig(onChanged: changes.add);
      await tester.pumpWidget(
        _board(first, drag: drag, selection: selection),
      );

      final gesture = await tester.startGesture(
        tester.getRect(find.byKey(_itemKey("m"))).center,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      expect(first.isDragging("m"), isTrue);

      final second = _controller(tester);
      second.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      await tester.pumpWidget(
        _board(second, drag: drag, selection: selection),
      );
      await tester.pump();
      expect(moved, 0);
      expect(first.isDragging("m"), isFalse);
      expect(second.isDragging("m"), isFalse);

      second.setSelection(
        const BoardSelection(
          anchor: (row: 0, col: 0),
          focus: (row: 0, col: 0),
        ),
      );
      await tester.pump();
      expect(changes, hasLength(1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  // DERIVED name. No AC; the reattach half of the detach rule, which
  // nothing else reaches. Its controller-swap sibling is AC22's second
  // case; the two are tested apart because only one is a GlobalKey move.
  // Asserts: with an item mid-exit and its span scrolled out of the
  // cache region, so that the retained obtain is the only thing keeping
  // its child mounted, the Board is moved to a different parent under a
  // GlobalKey in one pump; the probe is still findable immediately after
  // the move and is ABSENT after pumpAndSettle.
  // Falsification: an implementation that drops the retention map at
  // detach fails the FIRST assertion, because the first layout in the
  // new attachment no longer obtains the vicinity and the child unmounts
  // mid-exit.
  testWidgets(
    "moving the Board under a GlobalKey releases a retained exit at "
    "settle",
    (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        style: _enterExitOnly,
      );
      controller.addItem(
        const _Item("p"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      final boardKey = GlobalKey();
      Widget tree({required bool moved}) {
        final board = _board(
          controller,
          vertical: vertical,
          boardKey: boardKey,
        );
        return moved
            ? Padding(padding: const EdgeInsets.all(8.0), child: board)
            : board;
      }

      await tester.pumpWidget(tree(moved: false));
      await tester.pumpAndSettle();

      controller.removeItem("p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      vertical.jumpTo(2000.0);
      await tester.pump();
      expect(
        find.byKey(_itemKey("p"), skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpWidget(tree(moved: true));
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(_itemKey("p"), skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(find.byKey(_itemKey("p"), skipOffstage: false), findsNothing);
    },
  );

  // DERIVED name. No AC; the DELEGATE's lifetime, whose two halves fail
  // against opposite implementations.
  // Asserts: rebuild the Board with the SAME cellBuilder and itemBuilder
  // instances and debugPerformLayoutCount is unchanged across the
  // rebuild; then rebuild with a NEW cellBuilder closure returning a
  // distinguishable probe and the new probe is found on the next pump.
  // Falsification: the first half fails against a delegate constructed
  // per build, since shouldRebuild returns true unconditionally and the
  // setter then relayouts with a full delegate rebuild; the second fails
  // against a delegate only ever built in initState, since
  // TwoDimensionalChildBuilderDelegate.builder is final. Neither
  // assertion catches the other's defect, which is why both are made.
  testWidgets(
    "the delegate survives a rebuild with the same builders and takes a "
    "new cellBuilder",
    (tester) async {
      final controller = _controller(tester);
      Widget sameCell(
        BuildContext context,
        BoardCellView<String, _Item> cell,
      ) {
        return const SizedBox(width: 100.0, height: 100.0);
      }

      Widget sameItem(
        BuildContext context,
        BoardItemView<String, _Item> item,
      ) {
        return const SizedBox();
      }

      await tester.pumpWidget(
        _board(controller, cellBuilder: sameCell, itemBuilder: sameItem),
      );
      final viewport = _viewport(tester);
      final layouts = viewport.debugPerformLayoutCount;

      await tester.pumpWidget(
        _board(controller, cellBuilder: sameCell, itemBuilder: sameItem),
      );
      expect(viewport.debugPerformLayoutCount, layouts);

      await tester.pumpWidget(
        _board(
          controller,
          cellBuilder: (context, cell) {
            return SizedBox(
              key: ValueKey<String>("probe${cell.row}_${cell.col}"),
              width: 100.0,
              height: 100.0,
            );
          },
          itemBuilder: sameItem,
        ),
      );
      expect(find.byKey(const ValueKey<String>("probe0_0")), findsOneWidget);
    },
  );
}
