/// The drag proxy's clip: a move's proxy paints inside the board's bounds
/// under `Board.clipBehavior`, its whole paint included, a shadow its
/// builder adds past the proxy's own rect too, and floats free of them
/// under `Clip.none`.
///
/// The clip is observed in the PIXELS of the frame, read back from a
/// repaint boundary around the screen: a clip on the canvas pushes no
/// layer unless something under it composites, so a layer count cannot
/// see it.
library;

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _screenKey = ValueKey<String>("screen");

const Color _white = Color(0xFFFFFFFF);
const Color _green = Color(0xFF4CAF50);
const Color _red = Color(0xFFFF0000);

/// The board's top edge on the screen, under a white box this tall.
const double _boardTop = 100.0;

BoardController<String, _Item> _controller(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(4, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  controller.addItem(
    const _Item("m"),
    const BoardSpan(rowStart: 0, colStart: 1),
  );
  return controller;
}

/// A 280 x 200 board under a white box [_boardTop] tall, on a white
/// screen, its one item green. The cells paint nothing.
Widget _screen(
  BoardController<String, _Item> controller, {
  Clip clipBehavior = Clip.hardEdge,
  Widget Function(BuildContext, String, Widget)? dragProxyBuilder,
}) {
  return RepaintBoundary(
    key: _screenKey,
    child: MaterialApp(
      home: ColoredBox(
        color: _white,
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(width: 280.0, height: _boardTop),
              SizedBox(
                width: 280.0,
                height: 200.0,
                child: Board<String, _Item>(
                  controller: controller,
                  clipBehavior: clipBehavior,
                  drag: BoardDragConfig<String>(
                    onItemMoved: (key, span) {
                      controller.moveItem(key, span);
                    },
                    dragProxyBuilder: dragProxyBuilder,
                  ),
                  cellBuilder: (context, cell) {
                    return const SizedBox(width: 40.0, height: 50.0);
                  },
                  itemBuilder: (context, item) {
                    return const ColoredBox(color: _green);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Lifts the item, whose cell is (40, 100) to (80, 150) on the screen,
/// from its centre, then moves the pointer to [to]: the proxy's top left
/// is [to] less the (20, 25) grab offset.
Future<TestGesture> _liftTo(WidgetTester tester, Offset to) async {
  final gesture = await tester.startGesture(const Offset(60.0, 125.0));
  await tester.pump(kLongPressTimeout + kPressTimeout);
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

/// The colours the last frame shows at [points], in screen pixels.
Future<List<Color>> _pixelsAt(WidgetTester tester, List<Offset> points) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenKey),
  );
  final colors = <Color>[];
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (final point in points) {
      final at = (point.dy.floor() * image.width + point.dx.floor()) * 4;
      colors.add(
        Color.fromARGB(
          bytes.getUint8(at + 3),
          bytes.getUint8(at),
          bytes.getUint8(at + 1),
          bytes.getUint8(at + 2),
        ),
      );
    }
    image.dispose();
  });
  return colors;
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(400.0, 400.0);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.single.reset();
  });

  testWidgets("PC1 a proxy dragged across the board's top edge paints only "
      "inside the board", (tester) async {
    final controller = _controller(tester);
    await tester.pumpWidget(_screen(controller));

    // The proxy spans (160, 60) to (200, 110), across the edge at 100.
    final gesture = await _liftTo(tester, const Offset(180.0, 85.0));
    expect(controller.isDragging("m"), isTrue);
    final pixels = await _pixelsAt(tester, const <Offset>[
      Offset(180.0, _boardTop),
      Offset(180.0, _boardTop - 1.0),
    ]);
    // Setup sanity: the proxy paints, up to the board's edge.
    expect(pixels[0], _green);
    // TARGET. Nothing of it past the edge.
    expect(pixels[1], _white);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("PC2 a shadow the proxy builder adds is clipped at the "
      "board's edge though the proxy's rect lies inside the board", (
    tester,
  ) async {
    final controller = _controller(tester);
    await tester.pumpWidget(
      _screen(
        controller,
        dragProxyBuilder: (context, key, proxy) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: <BoxShadow>[
                BoxShadow(color: _red, spreadRadius: 20.0),
              ],
            ),
            child: proxy,
          );
        },
      ),
    );

    // The proxy spans (160, 110) to (200, 160), 10 px inside the edge;
    // its shadow reaches up to 90.
    final gesture = await _liftTo(tester, const Offset(180.0, 135.0));
    expect(controller.isDragging("m"), isTrue);
    final pixels = await _pixelsAt(tester, const <Offset>[
      Offset(180.0, _boardTop + 5.0),
      Offset(180.0, _boardTop - 5.0),
    ]);
    // Setup sanity: the shadow paints inside the board.
    expect(pixels[0], _red);
    // TARGET. And not past its edge.
    expect(pixels[1], _white);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("PC3 under Clip.none the proxy paints past the board's "
      "edge", (tester) async {
    final controller = _controller(tester);
    await tester.pumpWidget(_screen(controller, clipBehavior: Clip.none));

    final gesture = await _liftTo(tester, const Offset(180.0, 85.0));
    expect(controller.isDragging("m"), isTrue);
    final pixels = await _pixelsAt(tester, const <Offset>[
      Offset(180.0, _boardTop - 1.0),
    ]);
    expect(pixels.single, _green);

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
