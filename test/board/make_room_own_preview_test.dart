/// The make-room engine's own-preview scope: the entries a scope's writes
/// change join its record and read as their FOREIGN share through the
/// reads named `WithoutOwn`, an entry another session left closing keeps
/// decaying there, and the record holds only the entries that stand, so it
/// does not grow while a pointer toggles a neighbour's displacement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_make_room_engine.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Duration _frame = Duration(milliseconds: 16);

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

/// Make-room on a 200 ms linear clock, which it inherits from itemSlide.
const BoardAnimationStyle _animated = BoardAnimationStyle(
  trackResize: _ms200,
  itemSlide: _ms200,
);

/// What the engine's callbacks answer on the next install or refresh, so
/// a test can change it between them.
class _Inputs {
  BoardAnimationStyle style = _off;

  /// The lane of three that the dry run puts id 2 on; each lane is 18 px
  /// below the last, and id 2 rests on lane 0 of 1.
  int lane = 0;

  /// The resize term the dragged id's preview gives it.
  double band = 0.0;
  bool vacates = false;
  bool joins = false;
}

/// An engine on a vertical lane axis whose dry run lanes the dragged id
/// on lane 0 of 3 and id 2 on [_Inputs.lane], under [_Inputs.style].
MakeRoomEngine _engine(WidgetTester tester, _Inputs inputs) {
  final engine = MakeRoomEngine(
    vsync: tester,
    styleOf: () {
      return inputs.style;
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

/// An install of id [draggedId]'s drag resolving to [prospective], on the
/// live style's clock.
void _install(
  MakeRoomEngine engine, {
  int draggedId = 1,
  bool lifted = false,
  BoardSpan prospective = const BoardSpan(rowStart: 0, colStart: 0),
}) {
  engine.previewGap(
    draggedId: draggedId,
    prospective: prospective,
    lifted: lifted,
    duration: _ms200.duration,
    curve: _ms200.curve,
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

List<int> _controllerOwnIds(BoardController<String, _Item> controller) {
  return <int>[
    for (var index = 0; index < controller.makeRoomOwnIdCount; index++)
      controller.makeRoomOwnIdAt(index),
  ];
}

List<int> _controllerOwnSlotTracks(BoardController<String, _Item> controller) {
  return <int>[
    for (var index = 0; index < controller.makeRoomOwnSlotTrackCount; index++)
      controller.makeRoomOwnSlotTrackAt(index),
  ];
}

/// Criterion 1's board, B: content-sized rows carrying 18 px lanes under
/// a 4 px padding over seven 40 px columns, `a` laned in row 1 and `d` on
/// rows [0, 2), unlaned; [rows] replaces the row axis, and [extra] adds
/// one single-row item laned in each of rows 3, 4 and 5 at columns
/// [5, 7). Mounted in a 280 x 300 frame of 10 px cells.
Future<BoardController<String, _Item>> _board(
  WidgetTester tester, {
  required BoardAnimationStyle style,
  BoardAxis? rows,
  bool extra = false,
}) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: rows ?? LazyContentAxis(6, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2, colSpan: 5),
  );
  if (extra) {
    for (var row = 3; row <= 5; row++) {
      controller.addItem(
        _Item("x$row"),
        BoardSpan(rowStart: row, colStart: 5, colSpan: 2),
      );
    }
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: ObjectKey(controller),
            width: 280.0,
            height: 300.0,
            child: Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, view) {
                return const SizedBox(width: 40.0, height: 10.0);
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
  await tester.pumpAndSettle(_frame);
  return controller;
}

const BoardSpan _storedSpan = BoardSpan(
  rowStart: 0,
  colStart: 0,
  rowSpan: 2,
  colSpan: 5,
);

const BoardSpan _joinSpan = BoardSpan(rowStart: 1, colStart: 0, colSpan: 5);

void main() {
  testWidgets("an entry the own preview writes reads zero without it", (
    tester,
  ) async {
    final inputs = _Inputs()..lane = 1;
    final engine = _engine(tester, inputs);
    final first = engine.beginOwnPreview();
    final second = engine.beginOwnPreview();
    _install(engine);
    expect(engine.termDeltaOf(2).dy, 18.0);
    expect(engine.termDeltaWithoutOwnOf(2), 0.0);
    expect(_ownIds(engine), <int>[2]);

    engine.endOwnPreview(first);
    expect(engine.termDeltaOf(2).dy, 18.0);
    expect(engine.termDeltaWithoutOwnOf(2), 0.0);
    expect(_ownIds(engine), <int>[2]);

    inputs.lane = 0;
    _install(engine);
    expect(_ownIds(engine), isEmpty);

    inputs.lane = 1;
    _install(engine);
    expect(_ownIds(engine), <int>[2]);
    engine.clearForId(2);
    expect(_ownIds(engine), isEmpty);

    engine.endOwnPreview(second);
    _install(engine);
    expect(engine.termDeltaWithoutOwnOf(2), 18.0);
    expect(_ownIds(engine), isEmpty);
  });

  group("an entry another session left closing keeps decaying without the own "
      "preview", () {
    /// Neighbour 2 held at 18 px by an install with no scope, settled,
    /// released and 100 ms into its close, at 9 px; then a scope opens
    /// and an install re-targets it to 36 px.
    Future<(MakeRoomEngine, _Inputs)> joined(WidgetTester tester) async {
      final inputs = _Inputs()
        ..style = _live
        ..lane = 1;
      final engine = _engine(tester, inputs);
      _install(engine);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.termDeltaOf(2).dy, 18.0);
      engine.releasePreview(duration: _ms200.duration, curve: _ms200.curve);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.termDeltaOf(2).dy, 9.0);
      engine.beginOwnPreview();
      inputs.lane = 2;
      _install(engine);
      return (engine, inputs);
    }

    testWidgets("on its clock and past its end", (tester) async {
      final (engine, _) = await joined(tester);
      expect(engine.termDeltaWithoutOwnOf(2), 9.0);
      expect(engine.termDeltaOf(2).dy, 9.0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.termDeltaWithoutOwnOf(2), moreOrLessEquals(4.5));
      expect(engine.termDeltaOf(2).dy, moreOrLessEquals(22.5));
      await tester.pump(const Duration(milliseconds: 150));
      expect(engine.termDeltaWithoutOwnOf(2), 0.0);
      expect(engine.termDeltaOf(2).dy, 36.0);
    });

    testWidgets("under a makeRoom restyled off", (tester) async {
      final (engine, inputs) = await joined(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.termDeltaWithoutOwnOf(2), moreOrLessEquals(4.5));
      inputs.style = _off;
      await tester.pump(_frame);
      expect(engine.termDeltaWithoutOwnOf(2), 0.0);
      expect(engine.termDeltaOf(2).dy, 36.0);
    });
  });

  testWidgets("a slot the scope opened is not in the own-free read and another "
      "session's closing slot is", (tester) async {
    final inputs = _Inputs()..style = _live;
    final engine = _engine(tester, inputs);
    _install(
      engine,
      draggedId: 5,
      lifted: true,
      prospective: const BoardSpan(rowStart: 3, colStart: 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    engine.releasePreview(duration: _ms200.duration, curve: _ms200.curve);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.slotValueAt(3, 0), moreOrLessEquals(0.5));

    engine.beginOwnPreview();
    _install(engine);
    expect(engine.slotCountOn(3), 1);
    expect(engine.slotValueWithoutOwnAt(3, 0), engine.slotValueAt(3, 0));

    inputs.joins = true;
    _install(engine, prospective: const BoardSpan(rowStart: 2, colStart: 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.slotCountOn(2), 1);
    expect(engine.slotValueAt(2, 0), moreOrLessEquals(0.5));
    expect(engine.slotValueWithoutOwnAt(2, 0), 0.0);
    expect(_ownSlotTracks(engine), <int>[2]);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets("a vacate the scope writes reads zero without it", (
    tester,
  ) async {
    final inputs = _Inputs()..vacates = true;
    final engine = _engine(tester, inputs);
    engine.beginOwnPreview();
    _install(engine);
    expect(engine.vacatedOf(1), 1.0);
    expect(engine.vacatedWithoutOwnOf(1), 0.0);
  });

  testWidgets("a removal outside the snap tail drops its pair", (tester) async {
    final inputs = _Inputs()..band = 18.0;
    final engine = _engine(tester, inputs);
    engine.beginOwnPreview();
    _install(engine);
    expect(_ownIds(engine), <int>[1]);
    inputs.band = 0.0;
    engine.refreshResizeTerm();
    expect(_ownIds(engine), isEmpty);

    inputs
      ..joins = true
      ..lane = 1;
    _install(engine);
    expect(_ownIds(engine), <int>[2]);
    expect(_ownSlotTracks(engine), <int>[0]);
    engine.releasePreview();
    expect(_ownIds(engine), isEmpty);
    expect(_ownSlotTracks(engine), isEmpty);
  });

  testWidgets("the own scope holds only the entries its preview has standing", (
    tester,
  ) async {
    final boards = <String, Future<BoardController<String, _Item>> Function()>{
      "B": () {
        return _board(tester, style: BoardAnimationStyle.disabled);
      },
      "B with three more laned items": () {
        return _board(tester, style: BoardAnimationStyle.disabled, extra: true);
      },
      "F": () {
        return _board(
          tester,
          style: BoardAnimationStyle.disabled,
          rows: UniformAxis(6, 40.0),
        );
      },
    };
    for (final board in boards.entries) {
      final controller = await board.value();
      final a = controller.idOfKey("a");
      final epoch = controller.beginOwnMakeRoomPreview();
      controller.previewMakeRoomGap(draggedKey: "d", prospective: _joinSpan);
      expect(controller.anim.makeRoomTermDeltaOf(a).dy, isNot(0.0));
      expect(_controllerOwnIds(controller), <int>[a], reason: board.key);
      expect(_controllerOwnSlotTracks(controller), <int>[1], reason: board.key);
      for (var round = 1; round <= 5; round++) {
        controller.previewMakeRoomGap(
          draggedKey: "d",
          prospective: _storedSpan,
        );
        expect(
          _controllerOwnIds(controller),
          isEmpty,
          reason: "${board.key}, round $round",
        );
        expect(
          _controllerOwnSlotTracks(controller),
          isEmpty,
          reason: "${board.key}, round $round",
        );
        controller.previewMakeRoomGap(draggedKey: "d", prospective: _joinSpan);
        expect(_controllerOwnIds(controller), <int>[
          a,
        ], reason: "${board.key}, round $round");
        expect(
          _controllerOwnSlotTracks(controller),
          <int>[1],
          reason: "${board.key}, round $round",
        );
      }
      controller.endOwnMakeRoomPreview(epoch);
      expect(_controllerOwnIds(controller), isEmpty, reason: board.key);
      expect(_controllerOwnSlotTracks(controller), isEmpty, reason: board.key);
      controller.releaseMakeRoomPreview();
    }

    final controller = await _board(
      tester,
      style: _animated,
      rows: UniformAxis(6, 40.0),
    );
    final a = controller.idOfKey("a");
    final epoch = controller.beginOwnMakeRoomPreview();
    controller.previewMakeRoomGap(draggedKey: "d", prospective: _joinSpan);
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(controller.anim.makeRoomTermDeltaOf(a).dy, isNot(0.0));
    for (var round = 1; round <= 5; round++) {
      controller.previewMakeRoomGap(draggedKey: "d", prospective: _storedSpan);
      await tester.pump(_frame);
      expect(_controllerOwnIds(controller), <int>[a], reason: "round $round");
      expect(_controllerOwnSlotTracks(controller), <int>[
        1,
      ], reason: "round $round");
      controller.previewMakeRoomGap(draggedKey: "d", prospective: _joinSpan);
      await tester.pump(_frame);
      expect(_controllerOwnIds(controller), <int>[a], reason: "round $round");
      expect(_controllerOwnSlotTracks(controller), <int>[
        1,
      ], reason: "round $round");
    }
    controller.previewMakeRoomGap(draggedKey: "d", prospective: _storedSpan);
    for (var pump = 1; pump <= 20; pump++) {
      await tester.pump(_frame);
    }
    expect(_controllerOwnIds(controller), isEmpty);
    expect(_controllerOwnSlotTracks(controller), isEmpty);
    controller.endOwnMakeRoomPreview(epoch);
    expect(_controllerOwnIds(controller), isEmpty);
    expect(_controllerOwnSlotTracks(controller), isEmpty);
    controller.releaseMakeRoomPreview();
  });
}
