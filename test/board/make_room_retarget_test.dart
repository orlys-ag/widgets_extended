/// The make-room engine's re-target and fold rules, on stubbed inputs. A
/// snap re-target lands a moving entry and hands off its clock, as a snap
/// release does; a live re-send of an entry's own target changes nothing,
/// snapped or not; a snap hands off no entry that is mid-clock but not
/// moving, at every site that folds one; and a held extent eases on the
/// session's curve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_make_room_engine.dart';
import 'package:widgets_extended/board/board_animation_style.dart';

const BoardAnimationSpec _ms240 = BoardAnimationSpec(
  duration: Duration(milliseconds: 240),
  curve: Curves.linear,
);

const BoardSpan _prospective = BoardSpan(rowStart: 0, colStart: 0);

const Duration _half = Duration(milliseconds: 120);

const Duration _quarter = Duration(milliseconds: 60);

/// What the engine's callbacks answer on the next install, so a test can
/// change it between installs.
class _Inputs {
  /// The lane of three that the dry run puts id 2 on; each lane is 18 px
  /// below the last, and id 2 rests on lane 0 of 1.
  int lane = 0;

  /// The prospective extent of id 1.
  Offset extent = Offset.zero;
}

/// An engine on a vertical lane axis whose dry run lanes the dragged id
/// on lane 0 of 3, so a lifted install holds a slot on track 0 and the
/// dragged id holds no offset, and puts id 2 on [_Inputs.lane].
MakeRoomEngine _engine(WidgetTester tester, _Inputs inputs) {
  final engine = MakeRoomEngine(
    vsync: tester,
    styleOf: () {
      return const BoardAnimationStyle(makeRoom: _ms240);
    },
    notifyNow: () {},
    notifyCoalesced: () {},
    laneAxisOf: () {
      return Axis.vertical;
    },
    dryRunOf: (draggedId, prospective) {
      return <int, ({int lane, int laneCount, int laneSpan})>{
        draggedId: (lane: 0, laneCount: 3, laneSpan: 1),
        2: (lane: inputs.lane, laneCount: 3, laneSpan: 1),
      };
    },
    laneOriginOfId: (id, lane, laneCount) {
      return lane * 18.0;
    },
    neighbourExtentOf: (id, assignment) {
      return Offset.zero;
    },
    laneOfId: (id) {
      return 0;
    },
    laneCountOfId: (id) {
      return 1;
    },
    resizeGeometryOf: (id, prospective, assignment, out) {
      out
        ..leadDx = 0.0
        ..leadDy = 0.0
        ..extentDx = id == 1 ? inputs.extent.dx : 0.0
        ..extentDy = id == 1 ? inputs.extent.dy : 0.0;
    },
    resizeTermOf: (id, prospective, assignment, out) {
      out
        ..band = 0.0
        ..vacates = false
        ..joins = false;
    },
  );
  addTearDown(engine.dispose);
  return engine;
}

/// A live install of [draggedId]'s drag on [_ms240].
void _live(MakeRoomEngine engine, {int draggedId = 1, bool lifted = false}) {
  engine.previewGap(
    draggedId: draggedId,
    prospective: _prospective,
    lifted: lifted,
    duration: _ms240.duration,
    curve: _ms240.curve,
  );
}

/// A snap install of [draggedId]'s drag.
void _snap(MakeRoomEngine engine, {int draggedId = 1, bool lifted = false}) {
  engine.previewGap(
    draggedId: draggedId,
    prospective: _prospective,
    lifted: lifted,
    duration: Duration.zero,
  );
}

/// Holds id 2's offset at 18 px, unsnapped, mid-clock and not moving:
/// half way to 36 px, then re-targeted to where it paints.
Future<MakeRoomEngine> _stillOffset(WidgetTester tester) async {
  final inputs = _Inputs()..lane = 2;
  final engine = _engine(tester, inputs);
  _live(engine);
  await tester.pump();
  await tester.pump(_half);
  inputs.lane = 1;
  _live(engine);
  // Setup sanity: still at 18 px, with its clock running.
  expect(engine.deltaOf(2), const Offset(0.0, 18.0));
  expect(engine.hasMotion, isTrue);
  await tester.pump(_quarter);
  // Setup sanity: a quarter of its clock later it has not moved.
  expect(engine.deltaOf(2), const Offset(0.0, 18.0));
  return engine;
}

/// Holds id 1's extent at 40 px, unsnapped, mid-clock and not moving:
/// half way to 80 px, then re-targeted to where it paints.
Future<MakeRoomEngine> _stillExtent(WidgetTester tester) async {
  final inputs = _Inputs()..extent = const Offset(80.0, 0.0);
  final engine = _engine(tester, inputs);
  _live(engine);
  await tester.pump();
  await tester.pump(_half);
  inputs.extent = const Offset(40.0, 0.0);
  _live(engine);
  // Setup sanity: still at 40 px, with its clock running.
  expect(engine.extentDeltaOf(1), const Offset(40.0, 0.0));
  expect(engine.hasMotion, isTrue);
  await tester.pump(_quarter);
  // Setup sanity: a quarter of its clock later it has not moved.
  expect(engine.extentDeltaOf(1), const Offset(40.0, 0.0));
  return engine;
}

/// Holds one slot on track 0 at 0, unsnapped, mid-clock and not moving:
/// a lifted install opens it, and a live release before any tick closes
/// it from where it paints.
Future<MakeRoomEngine> _stillSlot(WidgetTester tester) async {
  final engine = _engine(tester, _Inputs());
  _live(engine, lifted: true);
  engine.releasePreview(duration: _ms240.duration, curve: _ms240.curve);
  // Setup sanity: one slot at 0, with its clock running.
  expect(engine.slotsOn(0).single.value, 0.0);
  expect(engine.hasMotion, isTrue);
  await tester.pump();
  await tester.pump(_quarter);
  // Setup sanity: a quarter of its clock later it has not moved.
  expect(engine.slotsOn(0).single.value, 0.0);
  return engine;
}

void main() {
  group("a snap re-target lands a moving entry and hands off its clock", () {
    testWidgets("a held offset", (tester) async {
      final engine = _engine(tester, _Inputs()..lane = 1);
      _live(engine);
      await tester.pump();
      await tester.pump(_half);
      // Setup sanity: half way to 18 px, and no hand-off yet.
      expect(engine.deltaOf(2), const Offset(0.0, 9.0));
      expect(engine.handOff, isNull);

      _snap(engine);
      // TARGET a: the offset is at its target.
      expect(engine.deltaOf(2), const Offset(0.0, 18.0));
      // TARGET b: nothing is left in motion.
      expect(engine.hasMotion, isFalse);
      // TARGET c: the snap handed off the offset's clock.
      expect(engine.handOff, isNotNull);
    });

    testWidgets("a held extent", (tester) async {
      final engine = _engine(
        tester,
        _Inputs()..extent = const Offset(40.0, 0.0),
      );
      _live(engine);
      await tester.pump();
      await tester.pump(_half);
      // Setup sanity: half way to 40 px, and no hand-off yet.
      expect(engine.extentDeltaOf(1), const Offset(20.0, 0.0));
      expect(engine.handOff, isNull);

      _snap(engine);
      // TARGET a: the extent is at its target.
      expect(engine.extentDeltaOf(1), const Offset(40.0, 0.0));
      // TARGET b: nothing is left in motion.
      expect(engine.hasMotion, isFalse);
      // TARGET c: the snap handed off the extent's clock.
      expect(engine.handOff, isNotNull);
    });
  });

  group("a snap release hands off the clock of an entry still moving", () {
    testWidgets("a held offset", (tester) async {
      final engine = _engine(tester, _Inputs()..lane = 1);
      _live(engine);
      await tester.pump();
      await tester.pump(_half);
      // Setup sanity: half way to 18 px, and no hand-off yet.
      expect(engine.deltaOf(2), const Offset(0.0, 9.0));
      expect(engine.handOff, isNull);

      engine.releasePreview(duration: Duration.zero);
      // TARGET: the hand-off continues from the offset's clock.
      expect(engine.handOff?.remaining, _ms240.duration * 0.5);
    });

    testWidgets("a held extent", (tester) async {
      final engine = _engine(
        tester,
        _Inputs()..extent = const Offset(40.0, 0.0),
      );
      _live(engine);
      await tester.pump();
      await tester.pump(_half);
      // Setup sanity: half way to 40 px, and no hand-off yet.
      expect(engine.extentDeltaOf(1), const Offset(20.0, 0.0));
      expect(engine.handOff, isNull);

      engine.releasePreview(duration: Duration.zero);
      // TARGET: the hand-off continues from the extent's clock.
      expect(engine.handOff?.remaining, _ms240.duration * 0.5);
    });

    testWidgets("a slot", (tester) async {
      final engine = _engine(tester, _Inputs());
      _live(engine, lifted: true);
      await tester.pump();
      await tester.pump(_half);
      // Setup sanity: the slot is half open, and no hand-off yet.
      expect(engine.slotsOn(0).single.value, 0.5);
      expect(engine.handOff, isNull);

      engine.releasePreview(duration: Duration.zero);
      // TARGET: the hand-off continues from the slot's clock.
      expect(engine.handOff?.remaining, _ms240.duration * 0.5);
    });
  });

  group("a live re-send of a snapped entry's own target changes nothing", () {
    testWidgets("a held offset", (tester) async {
      final engine = _engine(tester, _Inputs()..lane = 1);
      _snap(engine);
      // Setup sanity: snapped to 18 px.
      expect(engine.deltaOf(2), const Offset(0.0, 18.0));
      expect(engine.hasMotion, isFalse);

      _live(engine);
      // TARGET: nothing is put in motion.
      expect(engine.hasMotion, isFalse);
    });

    testWidgets("a held extent", (tester) async {
      final engine = _engine(
        tester,
        _Inputs()..extent = const Offset(40.0, 0.0),
      );
      _snap(engine);
      // Setup sanity: snapped to 40 px.
      expect(engine.extentDeltaOf(1), const Offset(40.0, 0.0));
      expect(engine.hasMotion, isFalse);

      _live(engine);
      // TARGET: nothing is put in motion.
      expect(engine.hasMotion, isFalse);
    });
  });

  group("a snap hands off no entry that is mid-clock but not moving", () {
    testWidgets("a held offset, snapped by an install", (tester) async {
      final engine = await _stillOffset(tester);

      _snap(engine);
      // Setup sanity: the snap landed the offset.
      expect(engine.hasMotion, isFalse);
      // TARGET: there is no clock to hand off.
      expect(engine.handOff, isNull);
    });

    testWidgets("a held offset, dropped by a snap release", (tester) async {
      final engine = await _stillOffset(tester);

      engine.releasePreview(duration: Duration.zero);
      // Setup sanity: the release dropped the offset.
      expect(engine.hasActive, isFalse);
      // TARGET: there is no clock to hand off.
      expect(engine.handOff, isNull);
    });

    testWidgets("a held extent, snapped by an install", (tester) async {
      final engine = await _stillExtent(tester);

      _snap(engine);
      // Setup sanity: the snap landed the extent.
      expect(engine.hasMotion, isFalse);
      // TARGET: there is no clock to hand off.
      expect(engine.handOff, isNull);
    });

    testWidgets("a held extent, dropped by a snap release", (tester) async {
      final engine = await _stillExtent(tester);

      engine.releasePreview(duration: Duration.zero);
      // Setup sanity: the release dropped the extent.
      expect(engine.hasHeldExtent, isFalse);
      // TARGET: there is no clock to hand off.
      expect(engine.handOff, isNull);
    });

    testWidgets("a slot, snapped by its session's lifted install", (
      tester,
    ) async {
      final engine = await _stillSlot(tester);

      _snap(engine, lifted: true);
      // Setup sanity: the snap landed the slot open.
      expect(engine.slotsOn(0).single.value, 1.0);
      // TARGET: there is no clock to hand off.
      expect(engine.handOff, isNull);
    });

    testWidgets("a slot, removed by another session's snap install", (
      tester,
    ) async {
      final engine = await _stillSlot(tester);

      _snap(engine, draggedId: 3);
      // Setup sanity: the snap removed the closing slot.
      expect(engine.slotsOn(0), isEmpty);
      // TARGET: there is no clock to hand off.
      expect(engine.handOff, isNull);
    });

    testWidgets("a slot, dropped by a snap release", (tester) async {
      final engine = await _stillSlot(tester);

      engine.releasePreview(duration: Duration.zero);
      // Setup sanity: the release dropped the slot.
      expect(engine.slotsOn(0), isEmpty);
      // TARGET: there is no clock to hand off.
      expect(engine.handOff, isNull);
    });
  });

  testWidgets("a held extent eases on the session's curve", (tester) async {
    final engine = _engine(tester, _Inputs()..extent = const Offset(40.0, 0.0));
    engine.previewGap(
      draggedId: 1,
      prospective: _prospective,
      duration: _ms240.duration,
      curve: Curves.easeIn,
    );
    await tester.pump();
    await tester.pump(_half);
    // TARGET: the extent at half its clock is its target times the curve
    // there.
    expect(
      engine.extentDeltaOf(1).dx,
      closeTo(40.0 * Curves.easeIn.transform(0.5), 1e-9),
    );
    engine.releasePreview(duration: Duration.zero);
  });
}
