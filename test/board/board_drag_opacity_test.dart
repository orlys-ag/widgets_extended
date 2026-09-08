/// Tests for the drag opacity pair: `BoardDragConfig.dragProxyOpacity`,
/// which times the moved visual, and `BoardDragConfig.draggedItemOpacity`,
/// which fades the item left behind in the lattice.
///
/// The fade is observed through the COMPOSITING it forces, not through a
/// debug seam: the wrapper pushes an `OpacityLayer` exactly while it
/// fades, so `tester.layers` counts the fades on screen and the
/// compositing bit between an item and its own repaint boundary says
/// WHICH item is faded.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_drag_handle.dart';
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

BoardController<String, _Item> _controller(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
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
  BoardDragConfig<String>? drag,
}) {
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
            drag: drag,
            cellBuilder: (context, cell) {
              return const SizedBox(width: 40.0, height: 50.0);
            },
            itemBuilder: (context, item) {
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

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

/// A standalone drag controller for the scripted cases, which drive the
/// session directly rather than through a handle.
BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  BoardDragConfig<String> config,
) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: config,
  );
  addTearDown(drag.dispose);
  return drag;
}

/// Every FADE currently painted anywhere in the tree, by alpha. Material's
/// own chrome contributes opacity layers at full strength, so a partial
/// alpha is the discriminator; [_opacityLayerCount] is what catches a
/// layer that should not exist at all.
/// A board whose item builder counts the PROXY's builds. A LATTICE build
/// runs with the viewport element itself as its context (the delegate
/// route) or below the viewport (the host route); every other item build
/// is the proxy's. The flag cannot tell the two apart, since the lattice
/// item's own mid-session rebuild carries `isDragging` too.
Widget _countingBoard(
  BoardController<String, _Item> controller,
  BoardDragConfig<String> drag,
  Map<String, int> proxyBuilds,
) {
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
            drag: drag,
            cellBuilder: (context, cell) {
              return const SizedBox(width: 40.0, height: 50.0);
            },
            itemBuilder: (context, item) {
              final inLattice =
                  context.widget is TwoDimensionalViewport ||
                  context.findAncestorRenderObjectOfType<
                        RenderBoardViewport<String>
                      >() !=
                      null;
              if (!inLattice) {
                proxyBuilds[item.key] = (proxyBuilds[item.key] ?? 0) + 1;
              }
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

/// Lifts item `m` at (2,1) and moves it into five DIFFERENT cells, so
/// every move re-targets and rebuilds the Board state. Returns the live
/// gesture.
Future<TestGesture> _liftAndMoveFive(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_itemKey("m"))),
  );
  await tester.pump(kLongPressTimeout + kPressTimeout);
  for (var col = 2; col <= 6; col++) {
    await gesture.moveTo(_global(tester, Offset(20.0 + 40.0 * col, 125.0)));
    await tester.pump();
  }
  return gesture;
}

List<int> _fades(WidgetTester tester) {
  return tester.layers
      .whereType<OpacityLayer>()
      .map((layer) {
        return layer.alpha ?? 255;
      })
      .where((alpha) {
        return alpha < 255;
      })
      .toList();
}

/// Every opacity layer, fading or not. The wrapper pushes none at full
/// strength, so this is flat across a session that fades nothing.
int _opacityLayerCount(WidgetTester tester) {
  return tester.layers.whereType<OpacityLayer>().length;
}

/// The LATTICE occurrence of [key]'s item. During a move the proxy builds
/// the same `itemBuilder` output under the same value key, and only the
/// lattice one sits under a [BoardItemDragScope].
Finder _inPlace(String key) {
  return find.descendant(
    of: find.byType(BoardItemDragScope),
    matching: find.byKey(_itemKey(key)),
  );
}

/// Whether anything between the item [finder] locates and its own repaint
/// boundary composites, which for a board item is the fade and nothing
/// else. The walk stops at the boundary the delegate wraps every child
/// in, so one item's answer cannot be another's.
bool _isFaded(WidgetTester tester, Finder finder) {
  RenderObject? node = tester.renderObject(finder);
  while (node != null && node is! RenderRepaintBoundary) {
    if (node.needsCompositing) {
      return true;
    }
    node = node.parent;
  }
  return false;
}

void main() {
  // The pair as asked for: the moved visual opaque, the item left behind
  // at half strength, and neither faded once the session is over.
  // Performance plan T8.
  // Asserts: a move session invokes the app's itemBuilder for the proxy
  // once, at the lift, across five re-targeting moves.
  // Falsification: a proxy built inside the pointer builder reports 6;
  // a cached host recreated per Board build reports the same 6.
  testWidgets("the proxy builds its content once per session", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final proxyBuilds = <String, int>{};
    await tester.pumpWidget(
      _countingBoard(
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
        proxyBuilds,
      ),
    );
    // Setup sanity: nothing built a proxy before the lift.
    expect(proxyBuilds["m"], isNull);

    final gesture = await _liftAndMoveFive(tester);
    // Setup sanity: the session is live with the proxy up.
    expect(controller.isDragging("m"), isTrue);
    expect(find.byKey(_itemKey("m")), findsNWidgets(2));

    expect(proxyBuilds["m"], 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  // Performance plan T8b.
  // Asserts: a payload write to the dragged key mid-session rebuilds the
  // proxy, through the data relay its host listens to.
  // Falsification: a cache with no relay leaves the count at 1.
  testWidgets("a payload write mid-session rebuilds the proxy", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final proxyBuilds = <String, int>{};
    await tester.pumpWidget(
      _countingBoard(
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
        proxyBuilds,
      ),
    );
    final gesture = await _liftAndMoveFive(tester);
    expect(proxyBuilds["m"], 1);

    controller.updateItem("m", const _Item("m"));
    await tester.pump();

    expect(proxyBuilds["m"], 2);
    expect(controller.isDragging("m"), isTrue);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("a move fades the item left behind and not the proxy", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
      ),
    );

    // Setup sanity: nothing fades before the lift, so every fade below is
    // the session's.
    expect(_fades(tester), isEmpty);
    expect(_isFaded(tester, _inPlace("m")), isFalse);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();

    // Setup sanity: the session is live and the proxy is up, so both
    // halves of the pair are on screen.
    expect(controller.isDragging("m"), isTrue);
    expect(find.byKey(_itemKey("m")), findsNWidgets(2));
    // TARGET. One fade on screen, at the configured default, and it is
    // the item left behind.
    expect(_fades(tester), <int>[128]);
    expect(_isFaded(tester, _inPlace("m")), isTrue);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_fades(tester), isEmpty);
    expect(_isFaded(tester, _inPlace("m")), isFalse);
  });

  // The fade is per item, not per board.
  testWidgets("a move fades only the dragged item", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    controller.addItem(
      const _Item("n"),
      const BoardSpan(rowStart: 4, colStart: 1),
    );
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
      ),
    );

    // Setup sanity: both items are mounted, so "n" is genuinely a
    // candidate for the fade rather than absent from the tree.
    expect(_inPlace("m"), findsOneWidget);
    expect(_inPlace("n"), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();

    // TARGET.
    expect(_isFaded(tester, _inPlace("m")), isTrue);
    expect(_isFaded(tester, _inPlace("n")), isFalse);
    expect(_fades(tester), <int>[128]);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  // The kind gate: a resize paints no proxy, so fading its item would
  // leave nothing at full strength.
  testWidgets("a resize session fades nothing", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("r"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    final resizes = <BoardSpan>[];
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          onItemResized: (key, span) {
            resizes.add(span);
          },
          resizeEdges: BoardResizeEdges.trailing,
        ),
      ),
    );

    // The item spans columns 1..3: x 40..120, y 100..150. The trailing
    // strip is the right-edge band, 12 wide.
    final gesture = await tester.startGesture(
      _global(tester, const Offset(114.0, 125.0)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40.0, 0.0));
    await tester.pump();

    // Setup sanity: a session really is live, and it is a resize.
    expect(controller.isDragging("r"), isTrue);
    expect(find.byKey(_itemKey("r")), findsOneWidget);
    // TARGET.
    expect(_fades(tester), isEmpty);
    expect(_isFaded(tester, _inPlace("r")), isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(resizes, hasLength(1));
  });

  // The other half of the pair, and the discriminator between them: with
  // the values swapped the only fade on screen is the proxy's.
  testWidgets("the proxy fades under dragProxyOpacity", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
          dragProxyOpacity: 0.5,
          draggedItemOpacity: 1.0,
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();

    // Setup sanity: the proxy is up, so the fade below has something to
    // be about.
    expect(find.byKey(_itemKey("m")), findsNWidgets(2));
    // TARGET. One fade, and the item left behind is not it.
    expect(_fades(tester), <int>[128]);
    expect(_isFaded(tester, _inPlace("m")), isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_fades(tester), isEmpty);
  });

  // A full-strength pair leaves no layer anywhere, which is what makes
  // the wrapper free to sit in the tree unconditionally.
  testWidgets("a full-strength pair pushes no layer", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
          draggedItemOpacity: 1.0,
        ),
      ),
    );
    // Material's own chrome owns whatever opacity layers stand before the
    // lift; the session must add none.
    final settled = _opacityLayerCount(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();

    // Setup sanity: the session is live and BOTH halves of the pair are
    // built, so the count below is measuring two full-strength wrappers
    // rather than a drag that never started.
    expect(controller.isDragging("m"), isTrue);
    expect(find.byKey(_itemKey("m")), findsNWidgets(2));
    // TARGET.
    expect(_opacityLayerCount(tester), settled);
    expect(_fades(tester), isEmpty);
    expect(_isFaded(tester, _inPlace("m")), isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  // A session torn down by a mutation rather than by the finger. The
  // teardown is one site, so this covers the whole cancel family.
  testWidgets("a mutation-cancelled session restores full strength", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await tester.pump();
    // Setup sanity: the fade is up, so the assertion after the mutation
    // measures a fade that was there to lose.
    expect(_fades(tester), <int>[128]);

    // A span mutator touching the dragged key cancels the session BEFORE
    // it mutates.
    controller.moveItem("m", const BoardSpan(rowStart: 5, colStart: 5));
    await tester.pump();

    // TARGET.
    expect(controller.isDragging("m"), isFalse);
    expect(_fades(tester), isEmpty);
    expect(_isFaded(tester, _inPlace("m")), isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  // The channel's own contract: the item host watches it per item, so it
  // must not fire per pointer move.
  testWidgets("movedItem is written at the session edges only", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final seen = <String?>[];
    drag.movedItem.addListener(() {
      seen.add(drag.movedItem.value);
    });

    // The item covers x 40..80, y 100..150.
    expect(
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
    drag.updateDrag(_global(tester, const Offset(140.0, 125.0)));
    drag.updateDrag(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();

    // Setup sanity: the session is live and the moves really landed, so a
    // channel that fired per move would have shown it.
    expect(controller.isDragging("m"), isTrue);
    expect(drag.pointerPosition.value, isNotNull);
    // TARGET: the lift, and nothing per move.
    expect(seen, <String?>["m"]);

    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();
    // TARGET: the teardown, and nothing more.
    expect(seen, <String?>["m", null]);
  });

  // A resize leaves the channel null, which is what gates the fade on the
  // session's kind.
  testWidgets("movedItem stays null across a resize session", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("r"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {},
        resizeEdges: BoardResizeEdges.trailing,
      ),
    );

    // The item covers x 40..120; 119 is inside its trailing edge.
    expect(
      drag.startDrag(
        key: "r",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(119.0, 125.0)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(160.0, 125.0)));
    await tester.pump();

    // Setup sanity: the session is live, so the null below is the kind
    // gate and not an absent drag.
    expect(controller.isDragging("r"), isTrue);
    expect(drag.draggedKind, isNot(BoardDragKind.move));
    // TARGET.
    expect(drag.movedItem.value, isNull);

    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();
  });

  group("the configured values", () {
    // The subject IS the default, which is what licenses the literal pin.
    test("default to an opaque proxy over a half-strength item", () {
      final config = BoardDragConfig<String>(onItemMoved: (key, span) {});
      expect(config.dragProxyOpacity, 1.0);
      expect(config.draggedItemOpacity, 0.5);
    });

    test("are rejected outside 0.0 through 1.0", () {
      expect(() {
        return BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          dragProxyOpacity: 1.5,
        );
      }, throwsAssertionError);
      expect(() {
        return BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          draggedItemOpacity: -0.5,
        );
      }, throwsAssertionError);
    });
  });
}
