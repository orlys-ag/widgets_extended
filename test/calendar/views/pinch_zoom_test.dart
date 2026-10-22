/// The pinch: how a tracker reads a pinch of two touches from raw pointer
/// events, how a scroll holder keeps positions still, the limits of the
/// sizes a pinch zooms to, and the offsets that hold a point across a
/// swap of a board's axis.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';

/// A [PinchTracker] whose callbacks record what they hear, its `onStart`
/// answering [accepts].
class PinchRecord {
  PinchRecord({this.accepts = true}) {
    tracker = PinchTracker(
      onStart: (axis, focal) {
        starts.add((axis: axis, focal: focal));
        return accepts;
      },
      onUpdate: updates.add,
      onEnd: () {
        ends++;
      },
    );
  }

  final bool accepts;
  late final PinchTracker tracker;
  final List<({PinchAxis axis, Offset focal})> starts =
      <({PinchAxis axis, Offset focal})>[];
  final List<PinchUpdate> updates = <PinchUpdate>[];
  int ends = 0;
}

PointerDownEvent down(int pointer, Offset position, {PointerDeviceKind? kind}) {
  return PointerDownEvent(
    pointer: pointer,
    position: position,
    kind: kind ?? PointerDeviceKind.touch,
  );
}

PointerMoveEvent move(int pointer, Offset position, {PointerDeviceKind? kind}) {
  return PointerMoveEvent(
    pointer: pointer,
    position: position,
    kind: kind ?? PointerDeviceKind.touch,
  );
}

PointerUpEvent up(int pointer, Offset position) {
  return PointerUpEvent(
    pointer: pointer,
    position: position,
    kind: PointerDeviceKind.touch,
  );
}

void main() {
  test("PZ1 a pinch starts once the spread changes by more than kTouchSlop, "
      "on the axis it changed more along, and reports its scale from the "
      "spread it started at and the point between the fingers", () async {
    final record = PinchRecord();
    final tracker = record.tracker;
    addTearDown(tracker.dispose);
    tracker.handleEvent(down(1, const Offset(100.0, 100.0)));
    tracker.handleEvent(down(2, const Offset(100.0, 160.0)));
    expect(tracker.holding.value, isTrue);
    expect(record.starts, isEmpty);

    // A change of 10, within the slop.
    tracker.handleEvent(move(2, const Offset(100.0, 170.0)));
    expect(record.starts, isEmpty);
    tracker.handleEvent(move(2, const Offset(100.0, 180.0)));
    expect(record.starts, hasLength(1));
    expect(record.starts.single.axis, PinchAxis.vertical);
    expect(record.starts.single.focal, const Offset(100.0, 140.0));
    expect(tracker.pinched.value, isTrue);

    tracker.handleEvent(move(2, const Offset(100.0, 260.0)));
    expect(record.updates, hasLength(1));
    expect(record.updates.single.axis, PinchAxis.vertical);
    expect(record.updates.single.scale, 2.0);
    expect(record.updates.single.focal, const Offset(100.0, 180.0));

    tracker.handleEvent(up(2, const Offset(100.0, 260.0)));
    expect(record.ends, 1);
    expect(tracker.holding.value, isFalse);
    expect(tracker.pinched.value, isTrue);
    tracker.handleEvent(up(1, const Offset(100.0, 100.0)));
    expect(tracker.pinched.value, isTrue);
    await Future<void>.microtask(() {});
    expect(tracker.pinched.value, isFalse);
  });

  test("PZ2 a refused pinch reports nothing until a finger lifts, and the "
      "next pair may start again", () {
    final record = PinchRecord(accepts: false);
    final tracker = record.tracker;
    addTearDown(tracker.dispose);
    tracker.handleEvent(down(1, const Offset(100.0, 100.0)));
    tracker.handleEvent(down(2, const Offset(100.0, 160.0)));
    tracker.handleEvent(move(2, const Offset(100.0, 180.0)));
    expect(record.starts, hasLength(1));
    tracker.handleEvent(move(2, const Offset(100.0, 260.0)));
    tracker.handleEvent(move(2, const Offset(100.0, 300.0)));
    expect(record.starts, hasLength(1));
    expect(record.updates, isEmpty);
    expect(tracker.pinched.value, isFalse);

    tracker.handleEvent(up(2, const Offset(100.0, 300.0)));
    tracker.handleEvent(down(3, const Offset(100.0, 160.0)));
    tracker.handleEvent(move(3, const Offset(100.0, 180.0)));
    expect(record.starts, hasLength(2));
  });

  test("PZ3 a pinch ignores other kinds of pointer and touches past the "
      "first two", () {
    final record = PinchRecord();
    final tracker = record.tracker;
    addTearDown(tracker.dispose);
    tracker.handleEvent(down(1, const Offset(100.0, 100.0)));
    tracker.handleEvent(
      down(5, const Offset(100.0, 160.0), kind: PointerDeviceKind.mouse),
    );
    tracker.handleEvent(
      move(5, const Offset(100.0, 260.0), kind: PointerDeviceKind.mouse),
    );
    expect(tracker.holding.value, isFalse);

    tracker.handleEvent(down(2, const Offset(100.0, 160.0)));
    tracker.handleEvent(move(2, const Offset(100.0, 180.0)));
    tracker.handleEvent(down(3, const Offset(300.0, 300.0)));
    tracker.handleEvent(move(3, const Offset(400.0, 400.0)));
    tracker.handleEvent(move(3, const Offset(500.0, 500.0)));
    expect(tracker.holding.value, isTrue);
    expect(record.updates, isEmpty);
    tracker.handleEvent(move(2, const Offset(100.0, 260.0)));
    expect(record.updates.single.scale, 2.0);
  });

  testWidgets("PZ4 a scroll holder keeps a position still against the drag "
      "running when it holds and a drag started after, and release lets it "
      "scroll", (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final holder = ScrollHolder();
    addTearDown(holder.release);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200.0,
            height: 400.0,
            child: ListView(
              controller: controller,
              children: const <Widget>[SizedBox(height: 2000.0)],
            ),
          ),
        ),
      ),
    );
    const start = Offset(100.0, 300.0);
    final first = await tester.startGesture(start);
    await first.moveBy(const Offset(0.0, -20.0));
    await tester.pump();
    await first.moveBy(const Offset(0.0, -40.0));
    await tester.pump();
    final scrolled = controller.position.pixels;
    expect(scrolled, greaterThan(0.0));

    holder.hold(<ScrollPosition?>[controller.position]);
    await tester.pump();
    await first.moveBy(const Offset(0.0, -100.0));
    await tester.pump();
    expect(controller.position.pixels, scrolled);
    await first.up();
    await tester.pump();

    final second = await tester.startGesture(start);
    await second.moveBy(const Offset(0.0, -20.0));
    await tester.pump();
    final started = controller.position.pixels;
    await second.moveBy(const Offset(0.0, -50.0));
    await tester.pump();
    await second.moveBy(const Offset(0.0, -50.0));
    await tester.pump();
    expect(controller.position.pixels, started);
    await second.up();
    await tester.pump();

    holder.release();
    final third = await tester.startGesture(start);
    await third.moveBy(const Offset(0.0, -20.0));
    await tester.pump();
    await third.moveBy(const Offset(0.0, -50.0));
    await tester.pump();
    expect(controller.position.pixels, greaterThan(started));
    await third.up();
    await tester.pumpAndSettle();
  });

  test("PZ5 trackFractionAt gives the track at an offset and how far into "
      "it", () {
    final axis = ExplicitAxis(<double>[10.0, 20.0, 30.0]);
    expect(trackFractionAt(axis, 0.0), 0.0);
    expect(trackFractionAt(axis, 5.0), 0.5);
    expect(trackFractionAt(axis, 10.0), 1.0);
    expect(trackFractionAt(axis, 20.0), 1.5);
    expect(trackFractionAt(axis, 45.0), 2.5);
    expect(trackFractionAt(axis, 60.0), 3.0);
    expect(trackFractionAt(axis, 75.0), 3.0);
    expect(trackFractionAt(axis, -5.0), 0.0);
  });

  testWidgets("PZ6 holdFocalAcrossAxisSwap sets the offset that keeps the "
      "focal point in place across the swap, clamped into the new "
      "range", (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200.0,
            height: 400.0,
            child: SingleChildScrollView(
              controller: controller,
              child: const SizedBox(height: 2000.0),
            ),
          ),
        ),
      ),
    );
    final position = controller.position;
    final old = UniformAxis(100, 10.0);

    // Track 15.0 lies under the focal; the anchor carries track 12.5 at the
    // leading edge to 250, so the focal lands at 300, track 15.0 again.
    controller.jumpTo(100.0);
    holdFocalAcrossAxisSwap(
      position,
      old: old,
      next: UniformAxis(100, 20.0),
      band: 0.0,
      focal: 50.0,
    );
    expect(position.pixels, 125.0);

    // The target, 500, clamps to the new range's end, 100, track 20.0.
    controller.jumpTo(1000.0);
    holdFocalAcrossAxisSwap(
      position,
      old: old,
      next: UniformAxis(100, 5.0),
      band: 0.0,
      focal: 0.0,
    );
    expect(position.pixels, 200.0);

    controller.jumpTo(300.0);
    holdFocalAcrossAxisSwap(
      position,
      old: UniformAxis(0, 10.0),
      next: UniformAxis(100, 20.0),
      band: 0.0,
      focal: 50.0,
    );
    expect(position.pixels, 300.0);
  });

  test("C9 maxMonthWeekScale is the most slot height over the default", () {
    expect(maxMonthWeekScale, 3.0);
  });
}
