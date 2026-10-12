/// The make-room engine's rules for a resize session's own LEAD, BAND and
/// VACATE, on stubbed inputs: how an install, a refresh, a clock change,
/// a release, a commit's snap, a removal and the settle treat each hold,
/// and when a resize keeps a lane slot.
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

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

const BoardSpan _prospective = BoardSpan(rowStart: 0, colStart: 0);

const Duration _quarter = Duration(milliseconds: 60);

const Duration _half = Duration(milliseconds: 120);

const Duration _whole = Duration(milliseconds: 240);

/// The three holds a resize session's own item can hold beside its
/// extent.
enum _Hold { lead, band, vacate }

/// The target each hold is given: the lead and the band in content-space
/// pixels on the vertical lane axis, the vacate a share.
double _full(_Hold hold) {
  switch (hold) {
    case _Hold.lead:
      return 40.0;
    case _Hold.band:
      return 20.0;
    case _Hold.vacate:
      return 1.0;
  }
}

/// [hold]'s value for [id], read through the reader the render uses for
/// it.
double _value(MakeRoomEngine engine, _Hold hold, {int id = 1}) {
  switch (hold) {
    case _Hold.lead:
      return engine.deltaOf(id).dy;
    case _Hold.band:
      return engine.termDeltaOf(id).dy;
    case _Hold.vacate:
      return engine.vacatedOf(id);
  }
}

/// What the engine's callbacks answer on the next install or refresh, so
/// a test can change it between them.
class _Inputs {
  BoardAnimationStyle style = const BoardAnimationStyle(makeRoom: _ms240);

  bool laneAxis = true;

  /// The session item's targets.
  Offset lead = Offset.zero;
  double band = 0.0;
  bool vacates = false;
  bool joins = false;

  /// The lane the dry run gives the dragged item, null when it lanes it
  /// in no track.
  int? lane;

  /// The extent the dry run gives each neighbour it lanes.
  Map<int, Offset> neighbours = <int, Offset>{};

  /// Targets [hold] alone, at its full value.
  void target(_Hold hold) {
    clear();
    switch (hold) {
      case _Hold.lead:
        lead = Offset(0.0, _full(hold));
      case _Hold.band:
        band = _full(hold);
      case _Hold.vacate:
        vacates = true;
    }
  }

  /// Targets every hold at zero.
  void clear() {
    lead = Offset.zero;
    band = 0.0;
    vacates = false;
  }
}

/// An engine on a vertical lane axis, or none, whose resize callbacks
/// answer [inputs] for whichever item the session drags and whose dry run
/// moves no item's lane origin.
MakeRoomEngine _engine(WidgetTester tester, _Inputs inputs) {
  final engine = MakeRoomEngine(
    vsync: tester,
    styleOf: () {
      return inputs.style;
    },
    notifyNow: () {},
    notifyCoalesced: () {},
    laneAxisOf: () {
      return inputs.laneAxis ? Axis.vertical : null;
    },
    dryRunOf: (draggedId, prospective) {
      final lane = inputs.lane;
      return <int, ({int lane, int laneCount, int laneSpan})>{
        if (lane != null) draggedId: (lane: lane, laneCount: 2, laneSpan: 1),
        for (final id in inputs.neighbours.keys)
          id: (lane: 1, laneCount: 2, laneSpan: 1),
      };
    },
    laneOriginOfId: (id, lane, laneCount) {
      return 0.0;
    },
    neighbourExtentOf: (id, assignment) {
      return inputs.neighbours[id] ?? Offset.zero;
    },
    laneOfId: (id) {
      return 0;
    },
    laneCountOfId: (id) {
      return 1;
    },
    resizeGeometryOf: (id, prospective, assignment, out) {
      out
        ..leadDx = inputs.lead.dx
        ..leadDy = inputs.lead.dy
        ..extentDx = 0.0
        ..extentDy = 0.0;
    },
    resizeTermOf: (id, prospective, assignment, out) {
      out
        ..band = inputs.band
        ..vacates = inputs.vacates
        ..joins = inputs.joins;
    },
  );
  addTearDown(engine.dispose);
  return engine;
}

/// A resize install of [id]'s drag on a linear clock of [duration], a
/// snap for a zero one.
void _install(MakeRoomEngine engine, {int id = 1, Duration duration = _whole}) {
  engine.previewGap(
    draggedId: id,
    prospective: _prospective,
    duration: duration,
    curve: Curves.linear,
  );
}

/// A release on a linear clock of [duration], a snap for a zero one.
void _release(MakeRoomEngine engine, {Duration duration = _whole}) {
  engine.releasePreview(duration: duration, curve: Curves.linear);
}

/// The frame a just-started ticker takes its first tick on, then [by].
Future<void> _advance(WidgetTester tester, Duration by) async {
  await tester.pump();
  await tester.pump(by);
}

/// [hold] at its full value for item 1, settled, then released and
/// closing for a quarter of its clock.
Future<(_Inputs, MakeRoomEngine)> _closing(
  WidgetTester tester,
  _Hold hold,
) async {
  final inputs = _Inputs()..target(hold);
  final engine = _engine(tester, inputs);
  _install(engine);
  await _advance(tester, _whole);
  _release(engine);
  await _advance(tester, _quarter);
  // Setup sanity: a quarter of the way back.
  expect(_value(engine, hold), _full(hold) * 0.75);
  return (inputs, engine);
}

/// A test of the engine that runs every clock out before the framework
/// checks that no ticker is left active.
void _testEngine(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpAndSettle();
  });
}

void main() {
  for (final hold in _Hold.values) {
    group("a resize's ${hold.name}", () {
      _testEngine("stays on its clock across a re-install of its target", (
        tester,
      ) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        await _advance(tester, _quarter);
        // Setup sanity: a quarter of the way.
        expect(_value(engine, hold), _full(hold) * 0.25);
        _install(engine);
        await tester.pump(_quarter);
        // TARGET: half way, on the clock the first install started.
        expect(_value(engine, hold), _full(hold) * 0.5);
      });

      _testEngine("closes on its clock under another item's install", (
        tester,
      ) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        await _advance(tester, _whole);
        inputs.clear();
        _install(engine, id: 3);
        await _advance(tester, _half);
        // TARGET: half way back.
        expect(_value(engine, hold), _full(hold) * 0.5);
      });

      _testEngine("is created at rest by a refresh", (tester) async {
        final inputs = _Inputs();
        final engine = _engine(tester, inputs);
        _install(engine);
        inputs.target(hold);
        engine
          ..refreshResizeTerm()
          ..refreshResizeGeometry();
        // TARGET a: it holds its target.
        expect(_value(engine, hold), _full(hold));
        // TARGET b: at rest.
        expect(engine.hasMotion, isFalse);
      });

      _testEngine("at rest is removed by a refresh to zero", (tester) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        await _advance(tester, _whole);
        inputs.clear();
        engine
          ..refreshResizeTerm()
          ..refreshResizeGeometry()
          ..debugResizeHoldReadCount = 0;
        // TARGET: it is gone, so its reader looks nothing up.
        expect(_value(engine, hold), 0.0);
        expect(engine.debugResizeHoldReadCount, 0);
      });

      _testEngine("re-bases onto a changed clock", (tester) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        await _advance(tester, _half);
        _install(engine, duration: _whole * 2);
        await tester.pump(_half);
        // TARGET: a quarter of the new clock on from half way.
        expect(_value(engine, hold), _full(hold) * 0.625);
      });

      _testEngine("alone is motion", (tester) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        // TARGET: the engine has motion, so its ticker runs.
        expect(engine.hasMotion, isTrue);
      });

      _testEngine("is counted by its reader", (tester) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine, duration: Duration.zero);
        engine.debugResizeHoldReadCount = 0;
        _value(engine, hold);
        // TARGET: one lookup.
        expect(engine.debugResizeHoldReadCount, 1);
      });

      _testEngine("closing re-bases onto a release's changed clock", (
        tester,
      ) async {
        final (_, engine) = await _closing(tester, hold);
        _release(engine, duration: _whole * 2);
        await tester.pump(_half);
        // TARGET: a quarter of the new clock on from three quarters.
        expect(_value(engine, hold), _full(hold) * 0.5625);
      });

      _testEngine("closes on its clock at a live release", (tester) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        await _advance(tester, _whole);
        _release(engine);
        await _advance(tester, _half);
        // TARGET: half way back.
        expect(_value(engine, hold), _full(hold) * 0.5);
      });

      _testEngine("is not re-opened by a refresh after a snap release", (
        tester,
      ) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        _release(engine, duration: Duration.zero);
        engine
          ..refreshResizeTerm()
          ..refreshResizeGeometry();
        // TARGET: the snap ended the session's source.
        expect(_value(engine, hold), 0.0);
      });

      _testEngine("closing goes with its own session's commit snap", (
        tester,
      ) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine);
        await _advance(tester, _whole);
        inputs.clear();
        _install(engine);
        await _advance(tester, _quarter);
        // Setup sanity: its own re-install closes it.
        expect(_value(engine, hold), _full(hold) * 0.75);
        _release(engine, duration: Duration.zero);
        // TARGET: the commit discards it.
        expect(_value(engine, hold), 0.0);
      });

      _testEngine("closing outlives another session's commit snap", (
        tester,
      ) async {
        final (inputs, engine) = await _closing(tester, hold);
        inputs.clear();
        _install(engine, id: 3);
        _release(engine, duration: Duration.zero);
        // TARGET a: it stays where it painted.
        expect(_value(engine, hold), _full(hold) * 0.75);
        await tester.pump(_quarter);
        // TARGET b: and closes on its clock.
        expect(_value(engine, hold), _full(hold) * 0.5);
      });

      _testEngine("closing goes with a commit snap under an off family", (
        tester,
      ) async {
        final (inputs, engine) = await _closing(tester, hold);
        inputs.style = const BoardAnimationStyle(makeRoom: _zero);
        _release(engine, duration: Duration.zero);
        // TARGET: nothing survives the kill switch.
        expect(_value(engine, hold), 0.0);
      });

      _testEngine("goes with its item's removal", (tester) async {
        final inputs = _Inputs()..target(hold);
        final engine = _engine(tester, inputs);
        _install(engine, duration: Duration.zero);
        engine.clearForId(1);
        // TARGET: nothing is held for the id.
        expect(_value(engine, hold), 0.0);
      });

      _testEngine("closed is removed at the settle", (tester) async {
        final (_, engine) = await _closing(tester, hold);
        await tester.pump(_whole);
        engine.debugResizeHoldReadCount = 0;
        _value(engine, hold);
        // TARGET: nothing is left for its reader to look up.
        expect(engine.debugResizeHoldReadCount, 0);
      });

      for (final laneAxis in <bool>[true, false]) {
        _testEngine("closing is removed by another item's snapped install "
            "${laneAxis ? "with" : "without"} a lane axis", (tester) async {
          final (inputs, engine) = await _closing(tester, hold);
          inputs
            ..clear()
            ..laneAxis = laneAxis;
          _install(engine, id: 3, duration: Duration.zero);
          engine.debugResizeHoldReadCount = 0;
          _value(engine, hold);
          // TARGET: nothing is left for its reader to look up.
          expect(engine.debugResizeHoldReadCount, 0);
        });
      }
    });
  }

  for (final hold in <_Hold>[_Hold.lead, _Hold.band]) {
    _testEngine("a resize's moving ${hold.name} re-bases onto a refresh to "
        "zero and keeps its clock", (tester) async {
      final inputs = _Inputs()..target(hold);
      final engine = _engine(tester, inputs);
      _install(engine);
      await _advance(tester, _half);
      inputs.clear();
      engine
        ..refreshResizeTerm()
        ..refreshResizeGeometry();
      // TARGET: moved by the change of its target, still closing.
      expect(_value(engine, hold), -_full(hold) * 0.5);
    });
  }

  _testEngine("a resize's moving band re-bases onto a refresh by its "
      "target's change", (tester) async {
    final inputs = _Inputs()..band = 20.0;
    final engine = _engine(tester, inputs);
    _install(engine);
    await _advance(tester, _half);
    inputs.band = 30.0;
    engine.refreshResizeTerm();
    // TARGET: half way to 20, moved by the 10 its target moved.
    expect(engine.termDeltaOf(1).dy, 20.0);
  });

  _testEngine("a commit's snap discards a survivor's extent that is not "
      "closing", (tester) async {
    final (inputs, engine) = await _closing(tester, _Hold.lead);
    inputs
      ..clear()
      ..neighbours = <int, Offset>{1: const Offset(0.0, 10.0)};
    _install(engine, id: 3);
    await tester.pump(_quarter);
    // Setup sanity: the install opened an extent for item 1.
    expect(engine.extentDeltaOf(1), const Offset(0.0, 2.5));
    _release(engine, duration: Duration.zero);
    // TARGET: only a closing extent survives with its closing lead.
    expect(engine.extentDeltaOf(1), Offset.zero);
  });

  _testEngine("a resize that stops joining a track keeps no slot", (
    tester,
  ) async {
    final inputs = _Inputs()
      ..joins = true
      ..lane = 0;
    final engine = _engine(tester, inputs);
    _install(engine, duration: Duration.zero);
    // Setup sanity: joining a track, it holds a slot there.
    expect(engine.slotsOn(0).toList(), hasLength(1));
    inputs.joins = false;
    _install(engine, duration: Duration.zero);
    // TARGET: laned in its own track, it desires none.
    expect(engine.slotsOn(0).toList(), isEmpty);
  });
}
