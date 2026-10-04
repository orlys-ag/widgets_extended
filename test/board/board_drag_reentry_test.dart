/// Tests for app code the drag layer calls re-entering the board: the
/// three lifecycle callbacks run after the board call that caused them,
/// never inside a mutation, a build or the frame's finalize; a session
/// ended by app code inside a drag call is not touched again by it; and a
/// throwing callback, predicate or animation listener is reported and
/// never strands a session.
///
/// Scripted cases drive a standalone [BoardDragController] against the
/// pumped board's render port; widget cases drive the Board's own drag
/// controller through gestures and rebuilds.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
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

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

/// What `onDragEnd` saw: its arguments and the board's answer for the key
/// at the moment it ran.
typedef _End = ({String key, bool committed, bool contains, BoardSpan? span});

BoardController<String, _Item> _newController(
  WidgetTester tester, {
  int rows = 6,
}) {
  return BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
}

/// A controller the test's teardown disposes, after unmounting whatever
/// board still listens to it.
BoardController<String, _Item> _plainController(
  WidgetTester tester, {
  int rows = 6,
}) {
  final controller = _newController(tester, rows: rows);
  addTearDown(controller.dispose);
  // Registered after the dispose, so it runs before it: the board
  // unsubscribes when it unmounts.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return controller;
}

/// Rows content-sized with lanes, so a make-room preview holds offsets.
BoardController<String, _Item> _lanedController(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(6, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return controller;
}

Widget? _noCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return null;
}

Widget _sizedCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return const SizedBox(width: 40.0, height: 50.0);
}

Widget _itemBox(BuildContext context, BoardItemView<String, _Item> item) {
  return ColoredBox(key: _itemKey(item.key), color: const Color(0xFF4CAF50));
}

void _ignoreMove(String key, BoardSpan span) {}

/// The board the scripted cases drive; it has no drag config of its own.
Widget _board(BoardController<String, _Item> controller) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: _sizedCell,
            itemBuilder: _itemBox,
          ),
        ),
      ),
    ),
  );
}

/// A board with its own drag controller, for the gesture cases.
Widget _host(
  BoardController<String, _Item> controller,
  BoardDragConfig<String> drag,
) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: _noCell,
            itemBuilder: _itemBox,
            drag: drag,
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

/// A standalone drag controller for the scripted cases, ticking through
/// [vsync] when given and the tester otherwise.
BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  BoardDragConfig<String> config, {
  TickerProvider? vsync,
}) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: vsync ?? tester,
    config: config,
  );
  addTearDown(drag.dispose);
  return drag;
}

/// Hands out plain [Ticker]s. The tester's own tickers assert when one is
/// disposed twice, which a plain ticker does not, so only a session built
/// on these runs on past a second teardown of its autoscroller.
class _PlainTickerProvider implements TickerProvider {
  const _PlainTickerProvider();

  @override
  Ticker createTicker(TickerCallback onTick) {
    return Ticker(onTick);
  }
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

/// The semantics id of the custom action labelled [label].
int _actionId(String label) {
  return CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
}

/// Whether [span] meets no item but [key].
bool _free(
  BoardController<String, _Item> controller,
  String key,
  BoardSpan span,
) {
  for (final other in controller.itemsIn(
    span.rowStart,
    span.rowStart + span.rowSpan,
    span.colStart,
    span.colStart + span.colSpan,
  )) {
    if (other != key) {
      return false;
    }
  }
  return true;
}

/// Lifts "m" at (2, 1), runs [mutate] on the dragged key, and checks that
/// `onDragEnd` ran after it, once, seeing [contains] and [span].
Future<void> _expectEndAfterMutation(
  WidgetTester tester, {
  required void Function(BoardController<String, _Item> controller) mutate,
  required bool contains,
  required BoardSpan? span,
}) async {
  final controller = _plainController(tester);
  controller.addItem(
    const _Item("m"),
    const BoardSpan(rowStart: 2, colStart: 1),
  );
  await tester.pumpWidget(_board(controller));
  final ends = <_End>[];
  final drag = _drag(
    tester,
    controller,
    BoardDragConfig<String>(
      onItemMoved: _ignoreMove,
      onDragEnd: (key, committed) {
        ends.add((
          key: key,
          committed: committed,
          contains: controller.contains(key),
          span: controller.spanOf(key),
        ));
      },
    ),
  );
  final viewport = _viewport(tester);
  // Setup sanity: a live session on the key.
  expect(
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
    ),
    isTrue,
  );
  expect(controller.isDragging("m"), isTrue);
  await tester.pump();

  mutate(controller);
  // TARGET: nothing has run inside the mutation.
  expect(ends, isEmpty);
  await tester.pump();
  // TARGET: one uncommitted end, which saw the mutation's result.
  expect(ends, <_End>[
    (key: "m", committed: false, contains: contains, span: span),
  ]);
}

enum _Rebuild { disable, dropConfig, swapController }

/// Lifts "m" through the Board's own gesture, then has the parent rebuild
/// the Board with [change]; `onDragEnd` records the scheduler phase and
/// calls the parent's `setState`.
Future<void> _expectRebuildEndsAfterFrame(
  WidgetTester tester,
  _Rebuild change,
) async {
  final first = _plainController(tester);
  final second = _plainController(tester);
  first.addItem(const _Item("m"), const BoardSpan(rowStart: 2, colStart: 1));
  var enabled = true;
  var hasDrag = true;
  var swapped = false;
  var ends = 0;
  final phases = <SchedulerPhase>[];
  late StateSetter setParent;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            setParent = setState;
            // No component element between this builder and the Board, so
            // this builder is the element being built when the Board's
            // `didUpdateWidget` runs.
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280.0,
                height: 300.0,
                child: Board<String, _Item>(
                  controller: swapped ? second : first,
                  cellBuilder: _noCell,
                  itemBuilder: _itemBox,
                  drag: hasDrag
                      ? BoardDragConfig<String>(
                          enabled: enabled,
                          onItemMoved: _ignoreMove,
                          onDragEnd: (key, committed) {
                            phases.add(SchedulerBinding.instance.schedulerPhase);
                            setParent(() {
                              ends += 1;
                            });
                          },
                        )
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_itemKey("m"))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
  // Setup sanity: lifted.
  expect(first.isDragging("m"), isTrue);

  setParent(() {
    switch (change) {
      case _Rebuild.disable:
        enabled = false;
      case _Rebuild.dropConfig:
        hasDrag = false;
      case _Rebuild.swapController:
        swapped = true;
    }
  });
  await tester.pump();
  // TARGET: the end ran after the frame, not inside its build ...
  expect(phases, <Object>[isNot(SchedulerPhase.persistentCallbacks)]);
  // ... so its setState threw nothing.
  expect(tester.takeException(), isNull);
  await tester.pump();
  // GUARD: delivered once.
  expect(ends, 1);
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The laned board of the animation-listener cases: "a" on row 0 and "d",
/// three columns wide, on row 2, dragged by [drag], with an animation
/// listener that throws [error] once, the first time it is called after
/// [armed] is set.
class _LanedSession {
  late final BoardController<String, _Item> controller;
  late final BoardDragController<String> drag;
  final List<String> ends = <String>[];
  int moved = 0;
  final StateError error = StateError("animation listener");
  bool armed = false;

  void listener() {
    if (armed) {
      armed = false;
      throw error;
    }
  }
}

/// Builds a [_LanedSession] and, when [lift] is true, lifts "d" and moves
/// it onto row 0, which opens a make-room gap.
Future<_LanedSession> _lanedSession(
  WidgetTester tester, {
  bool lift = true,
}) async {
  final s = _LanedSession();
  final controller = s.controller = _lanedController(tester);
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
  );
  await tester.pumpWidget(_board(controller));
  s.drag = _drag(
    tester,
    controller,
    BoardDragConfig<String>(
      onItemMoved: (key, span) {
        s.moved += 1;
      },
      onDragEnd: (key, committed) {
        s.ends.add("$key $committed");
      },
    ),
  );
  controller.addAnimationListener(s.listener);
  addTearDown(() {
    controller.removeAnimationListener(s.listener);
  });
  if (lift) {
    final viewport = _viewport(tester);
    final center = viewport.rectOfItem("d")!.center;
    s.drag.startDrag(
      key: "d",
      renderPort: viewport,
      pointerGlobal: _global(tester, center),
    );
    final target = viewport.rectOfCell(0, 0)!;
    s.drag.updateDrag(_global(tester, Offset(center.dx, target.top + 10.0)));
    await tester.pump();
  }
  return s;
}

void main() {
  group("onDragEnd sees the board after the mutation that cancelled the "
      "drag", () {
    testWidgets("setItems omitting the dragged key", (tester) async {
      await _expectEndAfterMutation(
        tester,
        mutate: (controller) {
          controller.setItems(const <BoardPlacement<_Item>>[]);
        },
        contains: false,
        span: null,
      );
    });

    testWidgets("setItems giving the dragged key a new span", (tester) async {
      await _expectEndAfterMutation(
        tester,
        mutate: (controller) {
          controller.setItems(const <BoardPlacement<_Item>>[
            BoardPlacement<_Item>(
              _Item("m"),
              BoardSpan(rowStart: 4, colStart: 3),
            ),
          ]);
        },
        contains: true,
        span: const BoardSpan(rowStart: 4, colStart: 3),
      );
    });

    testWidgets("removeItem", (tester) async {
      await _expectEndAfterMutation(
        tester,
        mutate: (controller) {
          controller.removeItem("m");
        },
        contains: false,
        span: null,
      );
    });

    testWidgets("moveItem", (tester) async {
      await _expectEndAfterMutation(
        tester,
        mutate: (controller) {
          controller.moveItem("m", const BoardSpan(rowStart: 4, colStart: 3));
        },
        contains: true,
        span: const BoardSpan(rowStart: 4, colStart: 3),
      );
    });

    testWidgets("resizeItem", (tester) async {
      await _expectEndAfterMutation(
        tester,
        mutate: (controller) {
          controller.resizeItem(
            "m",
            const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
          );
        },
        contains: true,
        span: const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
    });
  });

  // The outer call's exit loop reads each key's id after the hook ran for
  // the first; a handler that retires the keys under it leaves the loop
  // an id of -1 to read flags through.
  testWidgets("an onDragEnd that re-syncs with setItems inside setItems", (
    tester,
  ) async {
    final controller = _plainController(tester);
    var model = <BoardPlacement<_Item>>[
      const BoardPlacement<_Item>(
        _Item("d"),
        BoardSpan(rowStart: 2, colStart: 1),
      ),
      const BoardPlacement<_Item>(
        _Item("x"),
        BoardSpan(rowStart: 4, colStart: 3),
      ),
    ];
    controller.setItems(model);
    await tester.pumpWidget(_board(controller));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: _ignoreMove,
        onDragEnd: (key, committed) {
          controller.setItems(model);
        },
      ),
    );
    final viewport = _viewport(tester);
    drag.startDrag(
      key: "d",
      renderPort: viewport,
      pointerGlobal: _global(tester, viewport.rectOfItem("d")!.center),
    );
    await tester.pump();

    model = <BoardPlacement<_Item>>[];
    // TARGET.
    expect(() {
      controller.setItems(model);
    }, returnsNormally);
    await tester.pump();
  });

  // The handler frees the dragged key's id and the add takes it back off
  // the free list; the outer removal must not then retire the new key.
  testWidgets("an onDragEnd that removes the dragged key and adds another "
      "inside removeItem keeps the new key", (tester) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: _ignoreMove,
        onDragEnd: (key, committed) {
          if (controller.contains(key)) {
            controller.removeItem(key);
          }
          controller.addItem(
            const _Item("n"),
            const BoardSpan(rowStart: 0, colStart: 0),
          );
        },
      ),
    );
    final viewport = _viewport(tester);
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
    );
    await tester.pump();

    controller.removeItem("m");
    await tester.pump();
    // TARGET.
    expect(controller.contains("n"), isTrue);
  });

  // The Board ends the drag from its own `dispose`, inside the frame's
  // finalize, where a `setState` throws.
  testWidgets("removing the board mid-drag reports the end after the frame", (
    tester,
  ) async {
    // Owned here and disposed below, as the last TARGET.
    final controller = _newController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    var showBoard = true;
    var ends = 0;
    final phases = <SchedulerPhase>[];
    late StateSetter setParent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setParent = setState;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text("ends $ends"),
                  if (showBoard)
                    SizedBox(
                      width: 280.0,
                      height: 300.0,
                      child: Board<String, _Item>(
                        controller: controller,
                        cellBuilder: _noCell,
                        itemBuilder: _itemBox,
                        drag: BoardDragConfig<String>(
                          onItemMoved: _ignoreMove,
                          onDragEnd: (key, committed) {
                            phases.add(
                              SchedulerBinding.instance.schedulerPhase,
                            );
                            setParent(() {
                              ends += 1;
                            });
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    // Setup sanity: lifted.
    expect(controller.isDragging("m"), isTrue);

    setParent(() {
      showBoard = false;
    });
    await tester.pump();
    // TARGET: the end's setState threw nothing ...
    expect(tester.takeException(), isNull);
    // ... because it ran after the frame, not in its finalize.
    expect(phases, <Object>[isNot(SchedulerPhase.persistentCallbacks)]);
    await tester.pump();
    // TARGET: the parent rebuilt with the count.
    expect(find.text("ends 1"), findsOneWidget);
    await gesture.up();
    // TARGET: the Board left nothing subscribed.
    expect(controller.dispose, returnsNormally);
  });

  group("a drag ended by a rebuild reports the end after the frame", () {
    testWidgets("a config with enabled false", (tester) async {
      await _expectRebuildEndsAfterFrame(tester, _Rebuild.disable);
    });

    testWidgets("a null drag config", (tester) async {
      await _expectRebuildEndsAfterFrame(tester, _Rebuild.dropConfig);
    });

    testWidgets("a new BoardController", (tester) async {
      await _expectRebuildEndsAfterFrame(tester, _Rebuild.swapController);
    });
  });

  // A target report whose mutation tears the session down must not leave
  // `updateDrag` evaluating the disposed autoscroller: ten 50 px rows in a
  // 300 px frame, and the pointer inside the bottom autoscroll zone.
  testWidgets("updateDrag survives an onDragTargetChanged that moves the "
      "dragged item", (tester) async {
    final controller = _plainController(tester, rows: 10);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: _ignoreMove,
        onDragTargetChanged: (key, target) {
          if (target != null && target.span.rowStart >= 4) {
            controller.moveItem(key, target.span);
          }
        },
      ),
    );
    final viewport = _viewport(tester);
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
    );
    await tester.pump();

    // TARGET.
    expect(() {
      drag.updateDrag(_global(tester, const Offset(60.0, 298.0)));
    }, returnsNormally);
    await tester.pump();
    // GUARD: the reported target was delivered, and its move ended the
    // drag. Row 5 is where the pointer puts the item's top edge.
    expect(drag.draggedKey, isNull);
    expect(controller.spanOf("m"), const BoardSpan(rowStart: 5, colStart: 1));
  });

  // Control: every call below is synchronous, so the order is the order
  // the calls were made in.
  testWidgets("a session's end precedes the next session's start", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 3, colStart: 4),
    );
    await tester.pumpWidget(_board(controller));
    final events = <String>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: _ignoreMove,
        onDragStart: (key, kind) {
          events.add("start $key");
        },
        onDragEnd: (key, committed) {
          events.add("end $key $committed");
        },
      ),
    );
    final viewport = _viewport(tester);
    final a = viewport.rectOfItem("a")!.center;
    final b = viewport.rectOfItem("b")!.center;
    drag.startDrag(
      key: "a",
      renderPort: viewport,
      pointerGlobal: _global(tester, a),
    );
    controller.moveItem("a", const BoardSpan(rowStart: 1, colStart: 2));
    drag.startDrag(
      key: "b",
      renderPort: viewport,
      pointerGlobal: _global(tester, b),
    );
    await tester.pump();
    // TARGET.
    expect(events, <String>["start a", "end a false", "start b"]);
    drag.endDrag(cancel: true);
    await tester.pump();
  });

  // Control: a move and a release can share one task.
  testWidgets("a target change is reported before the drop it precedes", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final events = <String>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          events.add("moved $key ${span.rowStart},${span.colStart}");
        },
        onDragTargetChanged: (key, target) {
          final span = target?.span;
          events.add("target $key ${span?.rowStart},${span?.colStart}");
        },
        onDragEnd: (key, committed) {
          events.add("end $key $committed");
        },
      ),
    );
    final viewport = _viewport(tester);
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
    );
    await tester.pump();

    drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
    drag.endDrag(cancel: false);
    await tester.pump();
    // TARGET.
    expect(events.sublist(events.length - 3), <String>[
      "target m 2,2",
      "moved m 2,2",
      "end m true",
    ]);
  });

  // The end is queued behind the throwing start, in the same drain, so a
  // drain that stopped at the throw would strand it.
  testWidgets("a throwing lifecycle callback is reported and later ones "
      "still arrive", (tester) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final error = StateError("onDragStart");
    final ends = <String>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: _ignoreMove,
        onDragStart: (key, kind) {
          throw error;
        },
        onDragEnd: (key, committed) {
          ends.add("$key $committed");
        },
      ),
    );
    final viewport = _viewport(tester);
    var started = false;
    // TARGET.
    expect(() {
      started = drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
      );
    }, returnsNormally);
    expect(started, isTrue);
    drag.endDrag(cancel: true);
    await tester.pump();
    // TARGET: reported, not thrown at the caller.
    expect(tester.takeException(), same(error));
    // GUARD: the end queued behind it still arrived.
    expect(ends, <String>["m false"]);
  });

  group("an animation listener that removes the dragged item ends the drag "
      "once, after its start", () {
    // Every make-room preview and release snaps under the disabled style
    // and dispatches the animation channel synchronously.
    // The lift lands inside the bottom autoscroll zone, so an evaluate on
    // the session the listener ended would start its disposed ticker.
    testWidgets("startDrag", (tester) async {
      final controller = _plainController(tester, rows: 10);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 5, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final events = <String>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: _ignoreMove,
          onDragStart: (key, kind) {
            events.add("start $key ${kind.name}");
          },
          onDragEnd: (key, committed) {
            events.add("end $key $committed");
          },
        ),
      );
      var armed = true;
      void listener() {
        if (armed && controller.contains("m")) {
          armed = false;
          controller.removeItem("m");
        }
      }

      controller.addAnimationListener(listener);
      addTearDown(() {
        controller.removeAnimationListener(listener);
      });
      final viewport = _viewport(tester);
      // TARGET: a session ended inside the call still started.
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
        ),
        isTrue,
      );
      await tester.pump();
      // TARGET.
      expect(events, <String>["start m move", "end m false"]);
    });

    testWidgets("updateDrag", (tester) async {
      final controller = _plainController(tester, rows: 10);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(onItemMoved: _ignoreMove),
      );
      var armed = false;
      void listener() {
        if (armed && controller.contains("m")) {
          armed = false;
          controller.removeItem("m");
        }
      }

      controller.addAnimationListener(listener);
      addTearDown(() {
        controller.removeAnimationListener(listener);
      });
      final viewport = _viewport(tester);
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
      );
      await tester.pump();

      armed = true;
      // TARGET.
      expect(() {
        drag.updateDrag(_global(tester, const Offset(60.0, 298.0)));
      }, returnsNormally);
      await tester.pump();
    });

    testWidgets("endDrag", (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      final ends = <String>[];
      var moved = 0;
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moved += 1;
          },
          onDragEnd: (key, committed) {
            ends.add("$key $committed");
          },
        ),
        vsync: const _PlainTickerProvider(),
      );
      var armed = false;
      void listener() {
        if (armed && controller.contains("d")) {
          armed = false;
          controller.removeItem("d");
        }
      }

      controller.addAnimationListener(listener);
      addTearDown(() {
        controller.removeAnimationListener(listener);
      });
      final viewport = _viewport(tester);
      final lift = viewport.rectOfItem("d")!.center;
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      );
      final target = viewport.rectOfCell(0, 0)!;
      drag.updateDrag(_global(tester, Offset(lift.dx, target.top + 10.0)));
      await tester.pump();
      // Setup sanity: the commit snap has a gap to release, so it
      // dispatches.
      expect(controller.anim.hasActiveOffsets, isTrue);

      armed = true;
      drag.endDrag(cancel: false);
      await tester.pump();
      // TARGET: one uncommitted end, and no report for the removed key.
      expect(ends, <String>["d false"]);
      expect(moved, 0);
    });
  });

  testWidgets("a throwing onItemMoved still ends the drag", (tester) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final error = StateError("onItemMoved");
    final ends = <String>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          throw error;
        },
        onDragEnd: (key, committed) {
          ends.add("$key $committed");
        },
      ),
    );
    final viewport = _viewport(tester);
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
    );
    drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
    await tester.pump();

    expect(() {
      drag.endDrag(cancel: false);
    }, throwsA(same(error)));
    await tester.pump();
    // TARGET: the drop was reported, and the drag still ended.
    expect(ends, <String>["m true"]);
  });

  group("a throwing predicate is a refusal and never strands the drag", () {
    testWidgets("release, scripted", (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final error = StateError("canDropAt");
      var armed = false;
      final ends = <String>[];
      var moved = 0;
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moved += 1;
          },
          canDropAt: (key, span) {
            if (armed) {
              armed = false;
              throw error;
            }
            return true;
          },
          onDragEnd: (key, committed) {
            ends.add("$key $committed");
          },
        ),
      );
      final viewport = _viewport(tester);
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
      );
      drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
      await tester.pump();

      armed = true;
      // TARGET.
      expect(() {
        drag.endDrag(cancel: false);
      }, returnsNormally);
      expect(drag.draggedKey, isNull);
      expect(controller.isDragging("m"), isFalse);
      expect(tester.takeException(), same(error));
      await tester.pump();
      expect(ends, <String>["m false"]);
      expect(moved, 0);
    });

    testWidgets("release, through the Board's own gesture", (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      final error = StateError("canDropAt");
      var armed = false;
      var starts = 0;
      await tester.pumpWidget(
        _host(
          controller,
          BoardDragConfig<String>(
            onItemMoved: _ignoreMove,
            canDropAt: (key, span) {
              if (armed) {
                armed = false;
                throw error;
              }
              return true;
            },
            onDragStart: (key, kind) {
              starts += 1;
            },
          ),
        ),
      );
      // Read once: a stranded session would still show the proxy, a second
      // widget with the item's key.
      final center = tester.getCenter(find.byKey(_itemKey("m")));
      var gesture = await tester.startGesture(center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(40.0, 0.0));
      await tester.pump();

      armed = true;
      await gesture.up();
      await tester.pump();
      // TARGET: the release ended the session.
      expect(controller.isDragging("m"), isFalse);
      expect(tester.takeException(), same(error));
      gesture = await tester.startGesture(center);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      // TARGET: nothing stranded refuses the next lift.
      expect(starts, 2);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets("lift, scripted", (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final error = StateError("canDropAt");
      var armed = true;
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: _ignoreMove,
          canDropAt: (key, span) {
            if (armed) {
              armed = false;
              throw error;
            }
            return true;
          },
        ),
      );
      final viewport = _viewport(tester);
      var started = false;
      // TARGET.
      expect(() {
        started = drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
        );
      }, returnsNormally);
      expect(started, isTrue);
      expect(drag.currentTarget, isNull);
      expect(tester.takeException(), isA<StateError>());
      drag.endDrag(cancel: true);
      await tester.pump();
    });

    testWidgets("canDrag at the lift, scripted", (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final error = StateError("canDrag");
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: _ignoreMove,
          canDrag: (key) {
            throw error;
          },
        ),
      );
      final viewport = _viewport(tester);
      bool? started;
      // TARGET: a refused lift, with no session, and the throw reported.
      expect(() {
        started = drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, viewport.rectOfItem("m")!.center),
        );
      }, returnsNormally);
      expect(started, isFalse);
      expect(controller.isDragging("m"), isFalse);
      expect(tester.takeException(), same(error));
    });

    // "m" at column 0 and "o" at column 2: a move onto "o" is refused and
    // the scan's nearest free candidate is column 1, then column 3.
    testWidgets("scan, scripted", (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 0),
      );
      controller.addItem(
        const _Item("o"),
        const BoardSpan(rowStart: 2, colStart: 2),
      );
      await tester.pumpWidget(_board(controller));
      final error = StateError("canDropAt");
      var armed = false;
      final asked = <BoardSpan>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: _ignoreMove,
          dropFit: const BoardDropFit(),
          canDropAt: (key, span) {
            asked.add(span);
            if (armed && span == const BoardSpan(rowStart: 2, colStart: 1)) {
              armed = false;
              throw error;
            }
            return _free(controller, key, span);
          },
        ),
      );
      final viewport = _viewport(tester);
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(20.0, 125.0)),
      );
      await tester.pump();

      armed = true;
      asked.clear();
      // TARGET.
      expect(() {
        drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
      }, returnsNormally);
      // Setup sanity: the direct target was the occupied cell, so the
      // nudge ran.
      expect(asked.first, const BoardSpan(rowStart: 2, colStart: 2));
      expect(drag.currentTarget?.span, const BoardSpan(rowStart: 2, colStart: 3));
      expect(tester.takeException(), same(error));
      drag.endDrag(cancel: true);
      await tester.pump();
    });

    testWidgets("direct gate, scripted", (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 0),
      );
      controller.addItem(
        const _Item("o"),
        const BoardSpan(rowStart: 2, colStart: 2),
      );
      await tester.pumpWidget(_board(controller));
      final error = StateError("canDropAt");
      var armed = false;
      var asked = 0;
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: _ignoreMove,
          dropFit: const BoardDropFit(),
          canDropAt: (key, span) {
            asked += 1;
            if (armed) {
              armed = false;
              throw error;
            }
            return _free(controller, key, span);
          },
        ),
      );
      final viewport = _viewport(tester);
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(20.0, 125.0)),
      );
      await tester.pump();

      armed = true;
      asked = 0;
      // TARGET.
      expect(() {
        drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
      }, returnsNormally);
      expect(drag.currentTarget, isNull);
      expect(tester.takeException(), isA<StateError>());
      // GUARD: a throw is not an overlap, so no scan follows it.
      expect(asked, 1);
      drag.endDrag(cancel: true);
      await tester.pump();
    });

    // A new config instance makes exactly the one host rebuild; the
    // builders are the same functions, so the lattice is not rebuilt.
    testWidgets("build", (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      final error = StateError("canDrag");
      var armed = false;
      bool canDrag(String key) {
        if (armed) {
          armed = false;
          throw error;
        }
        return true;
      }

      BoardDragConfig<String> config() {
        return BoardDragConfig<String>(
          onItemMoved: _ignoreMove,
          canDrag: canDrag,
        );
      }

      await tester.pumpWidget(_host(controller, config()));
      armed = true;
      await tester.pumpWidget(_host(controller, config()));
      // TARGET: the item keeps its content.
      expect(find.byKey(_itemKey("m")), findsOneWidget);
      // GUARD: the throw is reported.
      expect(tester.takeException(), same(error));
    });

    // The item host asks `canDropAt` for each one-track move as it builds;
    // the question for "Move up" throws, once.
    testWidgets("canDropAt while the semantics actions build", (tester) async {
      final handle = tester.ensureSemantics();
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      final error = StateError("canDropAt");
      // Throws once: a predicate that kept throwing would report on every
      // host build. So the refusal below holds for the one build the
      // first pump makes; a later build asks again and is answered.
      var armed = true;
      await tester.pumpWidget(
        _host(
          controller,
          BoardDragConfig<String>(
            onItemMoved: _ignoreMove,
            canDropAt: (key, span) {
              if (armed && span == const BoardSpan(rowStart: 1, colStart: 1)) {
                armed = false;
                throw error;
              }
              return true;
            },
          ),
        ),
      );
      // TARGET: the item keeps its content, and the throw is reported.
      expect(find.byKey(_itemKey("m")), findsOneWidget);
      expect(tester.takeException(), same(error));
      final ids =
          tester
              .getSemantics(find.byKey(_itemKey("m")))
              .getSemanticsData()
              .customSemanticsActionIds ??
          const <int>[];
      // TARGET: the move the throw refused is not advertised ...
      expect(ids, isNot(contains(_actionId("Move up"))));
      // ... and the item keeps its drag affordances: the others are.
      expect(ids, contains(_actionId("Move down")));
      handle.dispose();
    });
  });

  group("a throwing animation listener never strands the drag", () {
    testWidgets("commit", (tester) async {
      final s = await _lanedSession(tester);
      // Setup sanity: the commit snap has a gap to release.
      expect(s.controller.anim.hasActiveOffsets, isTrue);

      s.armed = true;
      // TARGET.
      expect(() {
        s.drag.endDrag(cancel: false);
      }, returnsNormally);
      expect(s.controller.isDragging("d"), isFalse);
      expect(tester.takeException(), same(s.error));
      await tester.pump();
      expect(s.moved, 1);
      expect(s.ends, <String>["d true"]);
    });

    testWidgets("cancel", (tester) async {
      final s = await _lanedSession(tester);
      // Setup sanity: a release with nothing held returns before it
      // dispatches.
      expect(s.controller.anim.hasActiveOffsets, isTrue);

      s.armed = true;
      // TARGET.
      expect(() {
        s.drag.endDrag(cancel: true);
      }, returnsNormally);
      expect(s.controller.isDragging("d"), isFalse);
      await tester.pump();
      expect(s.ends, <String>["d false"]);
      expect(tester.takeException(), isA<StateError>());
    });

    testWidgets("lift", (tester) async {
      final s = await _lanedSession(tester, lift: false);
      final viewport = _viewport(tester);
      s.armed = true;
      var started = false;
      // TARGET.
      expect(() {
        started = s.drag.startDrag(
          key: "d",
          renderPort: viewport,
          pointerGlobal: _global(tester, viewport.rectOfItem("d")!.center),
        );
      }, returnsNormally);
      expect(started, isTrue);
      expect(tester.takeException(), same(s.error));
      s.drag.endDrag(cancel: true);
      await tester.pump();
    });
  });
}
