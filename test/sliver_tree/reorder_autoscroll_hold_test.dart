/// A reorder drag's edge autoscroll: an edge whose zone holds the lift
/// scrolls nothing until the finger moves toward that edge by more than
/// the slop, measured from the farthest the finger has been from it since
/// the lift; and the speed a zone asks for rises no faster than the
/// controller's ramp allows, while slowing and stopping are immediate.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const Duration _frame = Duration(milliseconds: 16);

/// The x every finger sits at, clear of the rows' edges.
const double _x = 400.0;

/// One hundred 50 px rows in a viewport filling the 800 x 600 test
/// window, scrolled about 1000 px down so either edge has room to scroll
/// toward. The tree corrects the offset as it measures rows, so a test
/// reads where it starts from [ScrollPosition.pixels]. The reorder
/// controller runs under [ramp] when one is given.
Future<({TreeReorderController<String> reorder, ScrollPosition position})>
_mount(WidgetTester tester, {Duration? ramp}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots([
    for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  if (ramp != null) {
    reorder.autoScrollRampDuration = ramp;
  }
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
    tree.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              nodeBuilder: (context, key, depth) {
                return TreeDelayedDragHandle(
                  child: SizedBox(
                    key: ValueKey("row-$key"),
                    height: 50,
                    child: Text(key),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable))
      .position;
  position.jumpTo(1000.0);
  await tester.pumpAndSettle();
  return (reorder: reorder, position: position);
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

/// Long-presses the row under a finger at viewport y [dy].
Future<TestGesture> _lift(
  WidgetTester tester,
  TreeReorderController<String> reorder,
  double dy,
) async {
  final gesture = await tester.startGesture(Offset(_x, dy));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  // Setup sanity: the long press started a session.
  expect(reorder.isDragging, isTrue);
  return gesture;
}

Future<void> _end(WidgetTester tester, TestGesture gesture) async {
  await gesture.up();
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

/// Where the ramp tests lift: the middle of the viewport, clear of both
/// zones.
const double _middle = 300.0;

void main() {
  group("the hold", () {
    testWidgets("a held top edge stays held until the finger moves toward "
        "it by more than the slop from its farthest", (tester) async {
      final h = await _mount(tester);
      final start = h.position.pixels;
      // The finger lifts 25 px from the top edge, inside its 48 px zone.
      final gesture = await _lift(tester, h.reorder, 25.0);
      await _frames(tester, 20);
      // TARGET: a resting finger scrolls nothing.
      expect(h.position.pixels, start);

      // Away from the edge, still inside the zone.
      await gesture.moveTo(const Offset(_x, 40.0));
      await _frames(tester, 10);
      // TARGET.
      expect(h.position.pixels, start);

      // Back toward the edge by 3 px, within the slop of the farthest.
      await gesture.moveTo(const Offset(_x, 37.0));
      await _frames(tester, 10);
      // TARGET.
      expect(h.position.pixels, start);

      // 5 px toward the edge from the farthest, though still farther from
      // it than the lift.
      await gesture.moveTo(const Offset(_x, 35.0));
      await _frames(tester, 10);
      // TARGET: released, the zone scrolls toward its edge.
      expect(h.position.pixels, lessThan(start));
      await _end(tester, gesture);
    });

    testWidgets("a held bottom edge stays held until the finger moves "
        "toward it by more than the slop", (tester) async {
      final h = await _mount(tester);
      final start = h.position.pixels;
      // 25 px from the bottom edge.
      final gesture = await _lift(tester, h.reorder, 575.0);
      await _frames(tester, 20);
      // TARGET.
      expect(h.position.pixels, start);

      await gesture.moveTo(const Offset(_x, 578.0));
      await _frames(tester, 10);
      // TARGET: 3 px toward the edge is within the slop.
      expect(h.position.pixels, start);

      await gesture.moveTo(const Offset(_x, 580.0));
      await _frames(tester, 10);
      // TARGET.
      expect(h.position.pixels, greaterThan(start));
      await _end(tester, gesture);
    });

    testWidgets("a zone the lift was not in scrolls as soon as the finger "
        "enters it", (tester) async {
      final h = await _mount(tester);
      final start = h.position.pixels;
      // 1 px above the bottom zone, which starts below 552.
      final gesture = await _lift(tester, h.reorder, 551.0);
      await _frames(tester, 10);
      // Setup sanity: outside every zone, nothing scrolls.
      expect(h.position.pixels, start);

      // 3 px down: 2 px into the zone, a move within the slop.
      await gesture.moveTo(const Offset(_x, 554.0));
      await _frames(tester, 10);
      // TARGET.
      expect(h.position.pixels, greaterThan(start));
      await _end(tester, gesture);
    });
  });

  group("the ramp", () {
    testWidgets("the ramp defaults to 300 ms", (tester) async {
      final tree = TreeController<String, String>(vsync: tester);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
      );
      addTearDown(() {
        reorder.dispose();
        tree.dispose();
      });
      expect(reorder.autoScrollRampDuration, const Duration(milliseconds: 300));
    });

    testWidgets("from rest the speed rises at the ramp's rate and reaches "
        "the zone's when the ramp ends", (tester) async {
      final h = await _mount(tester, ramp: _ramp);
      final gesture = await _lift(tester, h.reorder, _middle);
      // At the top edge itself, which asks for the full 1200 px/s.
      await gesture.moveTo(const Offset(_x, 0.0));
      final moving = (await _steps(tester, h.position, 25)).where((step) {
        return step > 0.0;
      }).toList();
      // TARGET: the first step is a small part of the full one.
      expect(moving.first, lessThan(_fullStep / 4));
      // TARGET: halfway through the ramp it is still short of it.
      expect(moving[5], lessThan(_fullStep * 3 / 4));
      // TARGET: past the ramp's 12.5 frames it is the full step.
      expect(moving[13], closeTo(_fullStep, 1e-6));
      await _end(tester, gesture);
    });

    testWidgets("a push deeper after the ramp is still capped", (tester) async {
      final h = await _mount(tester, ramp: _ramp);
      final gesture = await _lift(tester, h.reorder, _middle);
      // 5 px into the top zone: 125 px/s.
      await gesture.moveTo(const Offset(_x, 43.0));
      final shallow = await _steps(tester, h.position, 20);
      // Setup sanity: past the ramp, the scroll runs at the 125 px/s the
      // finger asks for.
      expect(shallow.last, closeTo(125.0 * 0.016, 1e-6));

      await gesture.moveTo(const Offset(_x, 0.0));
      final steps = await _steps(tester, h.position, 1);
      // TARGET: one frame's gain on the 125 px/s, not the full speed.
      expect(steps.single, closeTo((125.0 + _gainPerFrame) * 0.016, 1e-6));
      await _end(tester, gesture);
    });

    testWidgets("an entry gentler than the ramp is followed exactly", (
      tester,
    ) async {
      final h = await _mount(tester, ramp: _ramp);
      final gesture = await _lift(tester, h.reorder, _middle);
      // The zone's inner edge, which asks for nothing.
      await gesture.moveTo(const Offset(_x, 48.0));
      await _frames(tester, 2);
      final steps = <double>[];
      // One pixel deeper a frame asks for 25 px/s more a frame, under the
      // 96 px/s a frame the ramp allows.
      for (var depth = 1; depth <= 24; depth++) {
        await gesture.moveTo(Offset(_x, 48.0 - depth));
        steps.addAll(await _steps(tester, h.position, 1));
      }
      for (var depth = 1; depth <= 24; depth++) {
        // TARGET: each frame scrolls at the speed its depth asks for.
        expect(
          steps[depth - 1],
          closeTo(depth * 25.0 * 0.016, 1e-6),
          reason: "$depth px deep",
        );
      }
      await _end(tester, gesture);
    });

    testWidgets("slowing down and stopping are immediate, and a new start "
        "rises from rest again", (tester) async {
      final h = await _mount(tester, ramp: _ramp);
      final gesture = await _lift(tester, h.reorder, _middle);
      await gesture.moveTo(const Offset(_x, 0.0));
      final full = await _steps(tester, h.position, 20);
      // Setup sanity: past the ramp, the full speed.
      expect(full.last, closeTo(_fullStep, 1e-6));

      // Halfway into the zone: 600 px/s.
      await gesture.moveTo(const Offset(_x, 24.0));
      // TARGET.
      expect(
        (await _steps(tester, h.position, 1)).single,
        closeTo(_fullStep / 2, 1e-6),
      );

      // Out of the zone.
      await gesture.moveTo(const Offset(_x, _middle));
      // TARGET.
      expect((await _steps(tester, h.position, 1)).single, 0.0);

      await gesture.moveTo(const Offset(_x, 0.0));
      final steps = await _steps(tester, h.position, 1);
      // TARGET: the speed starts over from zero.
      expect(steps.single, lessThan(_fullStep / 4));
      await _end(tester, gesture);
    });

    testWidgets("a zero ramp starts at the speed the zone asks for", (
      tester,
    ) async {
      final h = await _mount(tester, ramp: Duration.zero);
      final gesture = await _lift(tester, h.reorder, _middle);
      await gesture.moveTo(const Offset(_x, 0.0));
      final steps = await _steps(tester, h.position, 1);
      // TARGET.
      expect(steps.single, closeTo(_fullStep, 1e-6));
      await _end(tester, gesture);
    });
  });
}
