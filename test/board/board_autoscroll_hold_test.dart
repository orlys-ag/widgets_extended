/// A drag's edge autoscroll: an edge whose zone holds the lift scrolls
/// nothing until the finger moves toward that edge by more than the
/// slop, measured from the farthest the finger has been from it since
/// the lift; and the speed a zone asks for rises no faster than the
/// config's ramp allows, while slowing and stopping are immediate.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

const Duration _frame = Duration(milliseconds: 16);

/// The scroll offsets every test starts from: room to scroll toward each
/// of the four edges.
const double _top = 1000.0;
const double _left = 400.0;

/// A 280 x 300 board of 50 px rows and 40 px columns, scrolled to
/// ([_left], [_top]), holding [items]. Its drag controller runs under
/// [config].
Future<
  ({BoardDragController<String> drag, RenderBoardViewport<String> viewport})
>
_setup(
  WidgetTester tester, {
  required Map<String, BoardSpan> items,
  BoardDragConfig<String>? config,
}) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(40, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(30, 40.0)),
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
  for (final entry in items.entries) {
    controller.addItem(_Item(entry.key), entry.value);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: _frameKey,
            width: 280.0,
            height: 300.0,
            child: Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, cell) {
                return null;
              },
              itemBuilder: (context, item) {
                return const ColoredBox(color: Color(0xFF4CAF50));
              },
            ),
          ),
        ),
      ),
    ),
  );
  final viewport = tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
  viewport.verticalPosition!.jumpTo(_top);
  viewport.horizontalPosition!.jumpTo(_left);
  await tester.pump();
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: config ?? BoardDragConfig<String>(onItemMoved: (key, span) {}),
  );
  addTearDown(drag.dispose);
  return (drag: drag, viewport: viewport);
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

/// Lifts [key] with the finger at [local], in the board's paint space.
void _lift(
  WidgetTester tester,
  ({BoardDragController<String> drag, RenderBoardViewport<String> viewport}) s,
  String key,
  Offset local,
) {
  // Setup sanity: the finger lifts the item it names.
  expect(s.viewport.rectOfItem(key)!.contains(local), isTrue);
  expect(
    s.drag.startDrag(
      key: key,
      renderPort: s.viewport,
      pointerGlobal: _global(tester, local),
    ),
    isTrue,
  );
}

Future<void> _end(
  WidgetTester tester,
  ({BoardDragController<String> drag, RenderBoardViewport<String> viewport}) s,
) async {
  s.drag.endDrag(cancel: true);
  await tester.pumpAndSettle();
}

/// How far [position] moves in each of [count] frames.
Future<List<double>> _steps(
  WidgetTester tester,
  ScrollPosition position,
  int count,
) async {
  final steps = <double>[];
  for (var i = 0; i < count; i++) {
    final before = position.pixels;
    await tester.pump(_frame);
    steps.add((position.pixels - before).abs());
  }
  return steps;
}

/// The ramp the ramp tests run under, and the frame step of the default
/// 1200 px/s at the edge itself.
const Duration _ramp = Duration(milliseconds: 200);
const double _fullStep = 1200.0 * 0.016;

/// The speed a 200 ms ramp to 1200 px/s may gain in one frame: 96 px/s.
const double _gainPerFrame = 1200.0 / 0.2 * 0.016;

/// Item "m" paints at (120..160, 150..200), clear of every zone.
const Map<String, BoardSpan> _middle = {
  "m": BoardSpan(rowStart: 23, colStart: 13),
};

const Offset _middleLift = Offset(140.0, 175.0);

BoardDragConfig<String> _rampConfig(Duration ramp) {
  return BoardDragConfig<String>(
    onItemMoved: (key, span) {},
    autoScrollRampDuration: ramp,
  );
}

void main() {
  group("the hold", () {
    testWidgets("a held top edge stays held until the finger moves toward "
        "it by more than the slop from its farthest", (tester) async {
      // Paints at (120..160, 0..50).
      final s = await _setup(
        tester,
        items: {"m": const BoardSpan(rowStart: 20, colStart: 13)},
      );
      final vertical = s.viewport.verticalPosition!;
      // The finger lifts 25 px from the top edge, inside its 48 px zone.
      _lift(tester, s, "m", const Offset(140.0, 25.0));
      await _frames(tester, 20);
      // TARGET: a resting finger scrolls nothing.
      expect(vertical.pixels, _top);

      // Away from the edge, still inside the zone.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 40.0)));
      await _frames(tester, 10);
      // TARGET.
      expect(vertical.pixels, _top);

      // Back toward the edge by 3 px, within the slop of the farthest.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 37.0)));
      await _frames(tester, 10);
      // TARGET.
      expect(vertical.pixels, _top);

      // 5 px toward the edge from the farthest, though still farther from
      // it than the lift.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 35.0)));
      await _frames(tester, 10);
      // TARGET: released, the zone scrolls toward its edge.
      expect(vertical.pixels, lessThan(_top));
      await _end(tester, s);
    });

    testWidgets("a top-left lift holds both edges, and each is released "
        "on its own", (tester) async {
      // Paints at (0..40, 0..50).
      final s = await _setup(
        tester,
        items: {"m": const BoardSpan(rowStart: 20, colStart: 10)},
      );
      final vertical = s.viewport.verticalPosition!;
      final horizontal = s.viewport.horizontalPosition!;
      _lift(tester, s, "m", const Offset(20.0, 25.0));
      await _frames(tester, 10);
      // TARGET.
      expect(vertical.pixels, _top);
      // TARGET.
      expect(horizontal.pixels, _left);

      // 5 px toward the top edge, none toward the left one.
      s.drag.updateDrag(_global(tester, const Offset(20.0, 20.0)));
      await _frames(tester, 10);
      // Setup sanity: the top edge is released.
      expect(vertical.pixels, lessThan(_top));
      // TARGET: the left edge is still held.
      expect(horizontal.pixels, _left);

      s.drag.updateDrag(_global(tester, const Offset(15.0, 20.0)));
      await _frames(tester, 10);
      // TARGET: 5 px toward the left edge releases it too.
      expect(horizontal.pixels, lessThan(_left));
      await _end(tester, s);
    });

    testWidgets("a bottom-right lift holds both edges, and each is released "
        "on its own", (tester) async {
      // Paints at (240..280, 250..300).
      final s = await _setup(
        tester,
        items: {"m": const BoardSpan(rowStart: 25, colStart: 16)},
      );
      final vertical = s.viewport.verticalPosition!;
      final horizontal = s.viewport.horizontalPosition!;
      // 25 px from the bottom edge and 20 px from the right one.
      _lift(tester, s, "m", const Offset(260.0, 275.0));
      await _frames(tester, 10);
      // TARGET.
      expect(vertical.pixels, _top);
      // TARGET.
      expect(horizontal.pixels, _left);

      // 5 px toward the right edge, none toward the bottom one.
      s.drag.updateDrag(_global(tester, const Offset(265.0, 275.0)));
      await _frames(tester, 10);
      // TARGET: the right edge is released ...
      expect(horizontal.pixels, greaterThan(_left));
      // TARGET: ... and the bottom edge is still held.
      expect(vertical.pixels, _top);

      s.drag.updateDrag(_global(tester, const Offset(265.0, 280.0)));
      await _frames(tester, 10);
      // TARGET.
      expect(vertical.pixels, greaterThan(_top));
      await _end(tester, s);
    });

    testWidgets("a zone the lift was not in scrolls as soon as the finger "
        "enters it", (tester) async {
      // Paints at (120..160, 250..300).
      final s = await _setup(
        tester,
        items: {"m": const BoardSpan(rowStart: 25, colStart: 13)},
      );
      final vertical = s.viewport.verticalPosition!;
      // 1 px above the bottom zone, which starts below 252.
      _lift(tester, s, "m", const Offset(140.0, 251.0));
      await _frames(tester, 10);
      // Setup sanity: outside every zone, nothing scrolls.
      expect(vertical.pixels, _top);

      // 3 px down: 2 px into the zone, a move within the slop.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 254.0)));
      await _frames(tester, 10);
      // TARGET.
      expect(vertical.pixels, greaterThan(_top));
      await _end(tester, s);
    });
  });

  group("the ramp", () {
    test("the ramp defaults to 300 ms", () {
      expect(
        BoardDragConfig<String>(
          onItemMoved: (key, span) {},
        ).autoScrollRampDuration,
        const Duration(milliseconds: 300),
      );
    });

    testWidgets("from rest the speed rises at the ramp's rate and reaches "
        "the zone's when the ramp ends", (tester) async {
      final s = await _setup(
        tester,
        items: _middle,
        config: _rampConfig(_ramp),
      );
      final vertical = s.viewport.verticalPosition!;
      _lift(tester, s, "m", _middleLift);
      // At the top edge itself, which asks for the full 1200 px/s.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 0.0)));
      final moving = (await _steps(tester, vertical, 25)).where((step) {
        return step > 0.0;
      }).toList();
      // TARGET: the first step is a small part of the full one.
      expect(moving.first, lessThan(_fullStep / 4));
      // TARGET: halfway through the ramp it is still short of it.
      expect(moving[5], lessThan(_fullStep * 3 / 4));
      // TARGET: past the ramp's 12.5 frames it is the full step.
      expect(moving[13], closeTo(_fullStep, 1e-6));
      await _end(tester, s);
    });

    testWidgets("a push deeper after the ramp is still capped", (tester) async {
      final s = await _setup(
        tester,
        items: _middle,
        config: _rampConfig(_ramp),
      );
      final vertical = s.viewport.verticalPosition!;
      _lift(tester, s, "m", _middleLift);
      // 5 px into the top zone: 125 px/s.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 43.0)));
      final shallow = await _steps(tester, vertical, 20);
      // Setup sanity: past the ramp, the scroll runs at the 125 px/s the
      // finger asks for.
      expect(shallow.last, closeTo(125.0 * 0.016, 1e-6));

      s.drag.updateDrag(_global(tester, const Offset(140.0, 0.0)));
      final steps = await _steps(tester, vertical, 1);
      // TARGET: one frame's gain on the 125 px/s, not the full speed.
      expect(steps.single, closeTo((125.0 + _gainPerFrame) * 0.016, 1e-6));
      await _end(tester, s);
    });

    testWidgets("an entry gentler than the ramp is followed exactly", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        items: _middle,
        config: _rampConfig(_ramp),
      );
      final vertical = s.viewport.verticalPosition!;
      _lift(tester, s, "m", _middleLift);
      // The zone's inner edge, which asks for nothing.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 48.0)));
      await _frames(tester, 2);
      final steps = <double>[];
      // One pixel deeper a frame asks for 25 px/s more a frame, under the
      // 96 px/s a frame the ramp allows.
      for (var depth = 1; depth <= 24; depth++) {
        s.drag.updateDrag(_global(tester, Offset(140.0, 48.0 - depth)));
        steps.addAll(await _steps(tester, vertical, 1));
      }
      // The first frame of a start moves nothing: the ticker's first tick
      // has no time behind it.
      for (var depth = 2; depth <= 24; depth++) {
        // TARGET: each frame scrolls at the speed its depth asks for.
        expect(
          steps[depth - 1],
          closeTo(depth * 25.0 * 0.016, 1e-6),
          reason: "$depth px deep",
        );
      }
      await _end(tester, s);
    });

    testWidgets("slowing down and stopping are immediate, and a new start "
        "rises from rest again", (tester) async {
      final s = await _setup(
        tester,
        items: _middle,
        config: _rampConfig(_ramp),
      );
      final vertical = s.viewport.verticalPosition!;
      _lift(tester, s, "m", _middleLift);
      s.drag.updateDrag(_global(tester, const Offset(140.0, 0.0)));
      final full = await _steps(tester, vertical, 20);
      // Setup sanity: past the ramp, the full speed.
      expect(full.last, closeTo(_fullStep, 1e-6));

      // Halfway into the zone: 600 px/s.
      s.drag.updateDrag(_global(tester, const Offset(140.0, 24.0)));
      // TARGET.
      expect(
        (await _steps(tester, vertical, 1)).single,
        closeTo(_fullStep / 2, 1e-6),
      );

      // Out of the zone.
      s.drag.updateDrag(_global(tester, _middleLift));
      // TARGET.
      expect((await _steps(tester, vertical, 1)).single, 0.0);

      s.drag.updateDrag(_global(tester, const Offset(140.0, 0.0)));
      final moving = (await _steps(tester, vertical, 4)).where((step) {
        return step > 0.0;
      }).toList();
      // TARGET: the speed starts over from zero.
      expect(moving.first, lessThan(_fullStep / 4));
      await _end(tester, s);
    });

    testWidgets("a zero ramp starts at the speed the zone asks for", (
      tester,
    ) async {
      final s = await _setup(
        tester,
        items: _middle,
        config: _rampConfig(Duration.zero),
      );
      final vertical = s.viewport.verticalPosition!;
      _lift(tester, s, "m", _middleLift);
      s.drag.updateDrag(_global(tester, const Offset(140.0, 0.0)));
      final moving = (await _steps(tester, vertical, 3)).where((step) {
        return step > 0.0;
      }).toList();
      // TARGET.
      expect(moving.first, closeTo(_fullStep, 1e-6));
      await _end(tester, s);
    });

    testWidgets("a new ramp takes effect mid-session", (tester) async {
      final s = await _setup(
        tester,
        items: _middle,
        config: _rampConfig(const Duration(seconds: 10)),
      );
      final vertical = s.viewport.verticalPosition!;
      _lift(tester, s, "m", _middleLift);
      s.drag.updateDrag(_global(tester, const Offset(140.0, 0.0)));
      final slow = await _steps(tester, vertical, 5);
      // Setup sanity: a 10 s ramp is still far from the full speed.
      expect(slow.last, lessThan(_fullStep / 4));

      s.drag.config = _rampConfig(Duration.zero);
      // TARGET.
      expect(
        (await _steps(tester, vertical, 1)).single,
        closeTo(_fullStep, 1e-6),
      );
      await _end(tester, s);
    });
  });
}
