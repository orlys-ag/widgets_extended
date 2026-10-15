/// The make-room engine's own-preview join record under the states a
/// short drag does not reach: two entries of one id, ids whose pairs
/// collide in the record's index or wrap past its end, a record grown
/// past its first capacity, a scope toggling one neighbour many times, a
/// re-base of an entry the scope did not write, a settle that closes
/// slots on both sides of a standing one, and a changed clock.
///
/// The record's index holds twice its dense capacity, sixteen positions
/// while at most eight pairs stand, and files a pair `(a, b)` at
/// `(a * 31 + b) & 15`, which is `(b - a) & 15`: gap offsets of ids 16
/// and 17 file at 0 and 15, and ids 2, 3 and 4 at 14, 13 and 12.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_make_room_engine.dart';
import 'package:widgets_extended/board/board_animation_style.dart';

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

const BoardAnimationStyle _off = BoardAnimationStyle(makeRoom: _zero);

const BoardAnimationStyle _live = BoardAnimationStyle(makeRoom: _ms200);

/// What the engine's callbacks answer on the next install or refresh.
class _Inputs {
  BoardAnimationStyle style = _off;

  /// Whether the engine has a (vertical) lane axis.
  bool laned = true;

  /// The lane of three the dry run puts each neighbour on, in this map's
  /// order; each lane is 18 px below the last, and every neighbour rests
  /// on lane 0 of 1. The dragged id is laned on lane 0 of 3.
  Map<int, int> lanes = <int, int>{};

  /// The resize term the dragged id's preview gives it.
  double band = 0.0;
  bool vacates = false;
}

MakeRoomEngine _engine(WidgetTester tester, _Inputs inputs) {
  final engine = MakeRoomEngine(
    vsync: tester,
    styleOf: () {
      return inputs.style;
    },
    notifyNow: () {},
    notifyCoalesced: () {},
    laneAxisOf: () {
      return inputs.laned ? Axis.vertical : null;
    },
    dryRunOf: (draggedId, prospective) {
      return <int, ({int lane, int laneCount, int laneSpan})>{
        draggedId: (lane: 0, laneCount: 3, laneSpan: 1),
        for (final entry in inputs.lanes.entries)
          entry.key: (lane: entry.value, laneCount: 3, laneSpan: 1),
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
        ..extentDx = 0.0
        ..extentDy = 0.0;
    },
    resizeTermOf: (id, prospective, assignment, out) {
      out
        ..band = inputs.band
        ..vacates = inputs.vacates
        ..joins = false;
    },
  );
  addTearDown(engine.dispose);
  return engine;
}

/// A resize install of [draggedId], or a lifted one at row [row], on
/// [spec]'s clock.
void _install(
  MakeRoomEngine engine, {
  int draggedId = 1,
  bool lifted = false,
  int row = 0,
  BoardAnimationSpec spec = _ms200,
}) {
  engine.previewGap(
    draggedId: draggedId,
    prospective: BoardSpan(rowStart: row, colStart: 0),
    lifted: lifted,
    duration: spec.duration,
    curve: spec.curve,
  );
}

List<int> _ownIds(MakeRoomEngine engine) {
  return <int>[
    for (var index = 0; index < engine.ownIdCount; index++)
      engine.ownIdAt(index),
  ];
}

List<int> _ownSlotTracks(MakeRoomEngine engine) {
  return <int>[
    for (var index = 0; index < engine.ownSlotTrackCount; index++)
      engine.ownSlotTrackAt(index),
  ];
}

/// The neighbours in [ids] held at 18 px by an install with no scope,
/// settled, released and 100 ms into their close, so each is at 9 px.
Future<void> _closingAtNine(
  WidgetTester tester,
  MakeRoomEngine engine,
  _Inputs inputs,
  Iterable<int> ids,
) async {
  inputs
    ..style = _live
    ..lanes = <int, int>{for (final id in ids) id: 1};
  _install(engine);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  engine.releasePreview(duration: _ms200.duration, curve: _ms200.curve);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  for (final id in ids) {
    expect(engine.termDeltaOf(id).dy, 9.0, reason: "id $id");
  }
}

void main() {
  testWidgets("a band the scope did not write reads whole beside the same id's "
      "vacate the scope wrote", (tester) async {
    // Id 1's band files at 0 and its vacate at 1, and neighbour 16's
    // offset at 0, which the vacate's pair is past.
    final inputs = _Inputs()
      ..style = _live
      ..band = 18.0;
    final engine = _engine(tester, inputs);
    _install(engine);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(engine.termDeltaOf(1).dy, 18.0);

    engine.beginOwnPreview();
    inputs
      ..vacates = true
      ..lanes = <int, int>{16: 1};
    _install(engine);
    expect(_ownIds(engine), <int>[1, 16]);
    expect(engine.vacatedWithoutOwnOf(1), 0.0);
    expect(engine.termDeltaWithoutOwnOf(16), 0.0);
    expect(engine.termDeltaWithoutOwnOf(1), 18.0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets("a removal keeps the pair it moves findable", (tester) async {
    final inputs = _Inputs()..lanes = <int, int>{2: 1, 3: 1};
    final engine = _engine(tester, inputs);
    engine.beginOwnPreview();
    _install(engine);
    expect(_ownIds(engine), <int>[2, 3]);

    // Removing 2 moves 3's pair into 2's dense position; 4's pair then
    // takes the position 3's held.
    engine.clearForId(2);
    inputs.lanes = <int, int>{3: 1, 4: 1};
    _install(engine);
    expect(_ownIds(engine), <int>[3, 4]);
    expect(engine.termDeltaOf(3).dy, 18.0);
    expect(engine.termDeltaWithoutOwnOf(3), 0.0);
    expect(engine.termDeltaWithoutOwnOf(4), 0.0);
  });

  testWidgets(
    "a removal before a pair at its home past the index's end leaves that "
    "pair findable",
    (tester) async {
      // 17's offset files at 15, the index's last position, and 16's at
      // 0, its own home, which the probe from 15 wraps to.
      final inputs = _Inputs()..lanes = <int, int>{17: 1, 16: 1};
      final engine = _engine(tester, inputs);
      engine.beginOwnPreview();
      _install(engine);
      expect(_ownIds(engine), <int>[17, 16]);
      engine.clearForId(17);
      expect(_ownIds(engine), <int>[16]);
      expect(engine.termDeltaOf(16).dy, 18.0);
      expect(engine.termDeltaWithoutOwnOf(16), 0.0);
    },
  );

  testWidgets(
    "a scope that toggles a neighbour's displacement many times keeps one "
    "pair for it",
    (tester) async {
      // Under motion off each toggle back removes 2's offset and drops
      // its pair, and each toggle out files a new one: more filings than
      // the index has positions, so each removal must free the position
      // its pair held.
      final inputs = _Inputs()..lanes = <int, int>{2: 1};
      final engine = _engine(tester, inputs);
      engine.beginOwnPreview();
      _install(engine);
      for (var round = 1; round <= 24; round++) {
        inputs.lanes = <int, int>{2: 0};
        _install(engine);
        expect(_ownIds(engine), isEmpty, reason: "round $round");
        inputs.lanes = <int, int>{2: 1};
        _install(engine);
        expect(_ownIds(engine), <int>[2], reason: "round $round");
        expect(engine.termDeltaWithoutOwnOf(2), 0.0, reason: "round $round");
      }
      expect(engine.termDeltaOf(2).dy, 18.0);
    },
  );

  testWidgets(
    "a record grown past eight pairs keeps every pair and its remainder",
    (tester) async {
      final ids = <int>[for (var id = 2; id <= 10; id++) id];
      final inputs = _Inputs();
      final engine = _engine(tester, inputs);
      await _closingAtNine(tester, engine, inputs, ids);
      engine.beginOwnPreview();
      inputs.lanes = <int, int>{for (final id in ids) id: 2};
      _install(engine);
      expect(_ownIds(engine), ids);
      for (final id in ids) {
        expect(engine.termDeltaWithoutOwnOf(id), 9.0, reason: "id $id");
      }
      await tester.pump(const Duration(milliseconds: 100));
      for (final id in ids) {
        expect(engine.termDeltaOf(id).dy, moreOrLessEquals(22.5));
        expect(
          engine.termDeltaWithoutOwnOf(id),
          moreOrLessEquals(4.5),
          reason: "id $id",
        );
      }
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets("a scope opened over an open one starts from an empty record", (
    tester,
  ) async {
    final inputs = _Inputs()..lanes = <int, int>{2: 1};
    final engine = _engine(tester, inputs);
    engine.beginOwnPreview();
    _install(engine);
    expect(_ownIds(engine), <int>[2]);
    expect(engine.termDeltaWithoutOwnOf(2), 0.0);
    engine.beginOwnPreview();
    expect(_ownIds(engine), isEmpty);
    expect(engine.termDeltaWithoutOwnOf(2), 18.0);
  });

  testWidgets("with no lane axis the own-free term delta is zero", (
    tester,
  ) async {
    final inputs = _Inputs()
      ..laned = false
      ..band = 18.0;
    final engine = _engine(tester, inputs);
    _install(engine);
    engine.beginOwnPreview();
    expect(engine.termDeltaOf(1), Offset.zero);
    expect(engine.termDeltaWithoutOwnOf(1), 0.0);
  });

  testWidgets("a band the scope writes reads zero without it", (tester) async {
    final inputs = _Inputs()..band = 18.0;
    final engine = _engine(tester, inputs);
    engine.beginOwnPreview();
    _install(engine);
    expect(engine.termDeltaOf(1).dy, 18.0);
    expect(engine.termDeltaWithoutOwnOf(1), 0.0);
  });

  testWidgets(
    "a band another session left closing keeps decaying without the own "
    "preview",
    (tester) async {
      final inputs = _Inputs()
        ..style = _live
        ..band = 18.0;
      final engine = _engine(tester, inputs);
      _install(engine);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      engine.releasePreview(duration: _ms200.duration, curve: _ms200.curve);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.termDeltaOf(1).dy, 9.0);

      engine.beginOwnPreview();
      inputs.band = 0.0;
      _install(engine, draggedId: 5);
      expect(_ownIds(engine), isEmpty);
      expect(engine.termDeltaWithoutOwnOf(1), 9.0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.termDeltaWithoutOwnOf(1), moreOrLessEquals(4.5));
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets(
    "a snapped band a re-base joins reads zero without the own preview",
    (tester) async {
      final inputs = _Inputs()..band = 18.0;
      final engine = _engine(tester, inputs);
      _install(engine);
      engine.beginOwnPreview();
      inputs.band = 36.0;
      engine.refreshResizeTerm();
      expect(_ownIds(engine), <int>[1]);
      expect(engine.termDeltaOf(1).dy, 36.0);
      expect(engine.termDeltaWithoutOwnOf(1), 0.0);
    },
  );

  testWidgets(
    "a re-base of a band another session left closing keeps its share of "
    "the close foreign",
    (tester) async {
      final inputs = _Inputs()
        ..style = _live
        ..band = 18.0;
      final engine = _engine(tester, inputs);
      _install(engine);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      engine.releasePreview(duration: _ms200.duration, curve: _ms200.curve);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.termDeltaOf(1).dy, 9.0);

      // A new session of the same item whose install leaves the closing
      // band alone, then a refresh that re-bases it onto 4 px: from 22
      // toward 4, half way, is 13, of which 18 * (1 - 0.5) is foreign.
      engine.beginOwnPreview();
      inputs.band = 0.0;
      _install(engine);
      expect(_ownIds(engine), isEmpty);
      inputs.band = 4.0;
      engine.refreshResizeTerm();
      expect(_ownIds(engine), <int>[1]);
      expect(engine.termDeltaOf(1).dy, moreOrLessEquals(13.0));
      expect(engine.termDeltaWithoutOwnOf(1), moreOrLessEquals(9.0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.termDeltaOf(1).dy, moreOrLessEquals(8.5));
      expect(engine.termDeltaWithoutOwnOf(1), moreOrLessEquals(4.5));
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets("a band a re-base creates reads zero without the own preview", (
    tester,
  ) async {
    final inputs = _Inputs();
    final engine = _engine(tester, inputs);
    engine.beginOwnPreview();
    _install(engine);
    expect(engine.termDeltaOf(1).dy, 0.0);
    inputs.band = 18.0;
    engine.refreshResizeTerm();
    expect(_ownIds(engine), <int>[1]);
    expect(engine.termDeltaOf(1).dy, 18.0);
    expect(engine.termDeltaWithoutOwnOf(1), 0.0);
  });

  testWidgets(
    "a settle that closes the slots on both sides of a standing one drops "
    "both their pairs",
    (tester) async {
      final inputs = _Inputs()..style = _live;
      final engine = _engine(tester, inputs);
      engine.beginOwnPreview();
      // One frame: the slots on rows 2 and 4 close on clocks that start
      // together, and row 3's, recorded between them, stands.
      for (final row in <int>[2, 3, 4, 3]) {
        _install(engine, draggedId: 5, lifted: true, row: row);
      }
      expect(_ownSlotTracks(engine), <int>[2, 3, 4]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.slotCountOn(2), 0);
      expect(engine.slotCountOn(4), 0);
      expect(engine.slotValueAt(3, 0), 1.0);
      expect(_ownSlotTracks(engine), <int>[3]);
      expect(engine.slotValueWithoutOwnAt(3, 0), 0.0);
      await tester.pump(const Duration(milliseconds: 16));
    },
  );

  testWidgets(
    "a changed clock keeps a joined offset's foreign share decaying from "
    "where it stood",
    (tester) async {
      final inputs = _Inputs();
      final engine = _engine(tester, inputs);
      await _closingAtNine(tester, engine, inputs, <int>[2]);
      engine.beginOwnPreview();
      inputs.lanes = <int, int>{2: 2};
      _install(engine);
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.termDeltaOf(2).dy, moreOrLessEquals(22.5));
      expect(engine.termDeltaWithoutOwnOf(2), moreOrLessEquals(4.5));

      // The same targets on a 400 ms clock: the offset restarts from 22.5
      // and its foreign share from 4.5, both half way 200 ms later.
      _install(
        engine,
        spec: const BoardAnimationSpec(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      expect(engine.termDeltaWithoutOwnOf(2), moreOrLessEquals(4.5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(engine.termDeltaOf(2).dy, moreOrLessEquals(29.25));
      expect(engine.termDeltaWithoutOwnOf(2), moreOrLessEquals(2.25));
      await tester.pump(const Duration(milliseconds: 250));
    },
  );

  testWidgets(
    "a changed clock keeps a joined slot's foreign share decaying from "
    "where it stood",
    (tester) async {
      final inputs = _Inputs()..style = _live;
      final engine = _engine(tester, inputs);
      _install(engine, draggedId: 5, lifted: true, row: 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      engine.releasePreview(duration: _ms200.duration, curve: _ms200.curve);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.slotValueAt(3, 0), moreOrLessEquals(0.5));
      engine.beginOwnPreview();
      _install(engine, draggedId: 5, lifted: true, row: 3);
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.slotValueAt(3, 0), moreOrLessEquals(0.75));
      expect(engine.slotValueWithoutOwnAt(3, 0), moreOrLessEquals(0.25));

      _install(
        engine,
        draggedId: 5,
        lifted: true,
        row: 3,
        spec: const BoardAnimationSpec(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      expect(engine.slotValueWithoutOwnAt(3, 0), moreOrLessEquals(0.25));
      await tester.pump(const Duration(milliseconds: 200));
      expect(engine.slotValueAt(3, 0), moreOrLessEquals(0.875));
      expect(engine.slotValueWithoutOwnAt(3, 0), moreOrLessEquals(0.125));
      await tester.pump(const Duration(milliseconds: 250));
    },
  );
}
