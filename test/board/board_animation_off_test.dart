/// A board animation duration that is not positive means OFF, for every
/// animation source and in every build mode, exactly as a zero one does:
/// an install is refused or snaps, a record already in flight settles on
/// its next tick, and no source hands a negative duration to another.
/// A family's own duration decides first and dominates a per-call one;
/// otherwise a per-call duration that is not positive is off as well.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_item_enter_exit_animator.dart';
import 'package:widgets_extended/board/_item_slide_engine.dart';
import 'package:widgets_extended/board/_make_room_engine.dart';
import 'package:widgets_extended/board/_track_resize_animator.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const BoardAnimationSpec _ms240 = BoardAnimationSpec(
  duration: Duration(milliseconds: 240),
  curve: Curves.linear,
);

const BoardAnimationSpec _neg240 = BoardAnimationSpec(
  duration: Duration(milliseconds: -240),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// itemEnterExit inherits the zero trackResize, so an add installs no
/// enter.
const BoardAnimationStyle _gapStyle = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms240,
  makeRoom: _ms240,
);

/// The ticker's first frame, at zero elapsed, then one frame past the
/// end of a motion started on [_ms240].
Future<void> _settlePump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// Content-sized rows carrying an 18px lane, so a neighbour displaced one
/// lane moves exactly 18px. Row 0 holds `a` and `b` on lanes 0 and 1 of
/// columns 2 to 5; `d` (columns 0 to 2) sits on row 3. Lifting `d` onto
/// row 0, columns 0 to 2, lanes it first and displaces both one lane
/// down.
Future<BoardController<String, _Item>> _gapFixture(WidgetTester tester) async {
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
    animationStyle: _gapStyle,
  );
  addTearDown(controller.dispose);
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 3, colStart: 0, colSpan: 3),
  );
  await _settlePump(tester);
  return controller;
}

const BoardSpan _dOnRow0 = BoardSpan(rowStart: 0, colStart: 0, colSpan: 3);

void main() {
  test("durationFor resolves a duration that is not positive to off", () {
    const ms100 = Duration(milliseconds: 100);
    final rows =
        <({BoardAnimationSpec spec, Duration? explicit, Duration expected})>[
          (spec: _ms240, explicit: null, expected: _ms240.duration),
          (spec: _ms240, explicit: ms100, expected: ms100),
          (spec: _ms240, explicit: Duration.zero, expected: Duration.zero),
          (spec: _ms240, explicit: -ms100, expected: Duration.zero),
          (spec: _zero, explicit: ms100, expected: Duration.zero),
          (spec: _neg240, explicit: ms100, expected: Duration.zero),
          (spec: _neg240, explicit: null, expected: Duration.zero),
        ];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final style = BoardAnimationStyle(itemSlide: row.spec);
      expect(
        style.durationFor(
          BoardAnimationFamily.itemSlide,
          explicit: row.explicit,
        ),
        row.expected,
        reason: "row ${i + 1}",
      );
      expect(
        style.isOff(BoardAnimationFamily.itemSlide, explicit: row.explicit),
        row.expected == Duration.zero,
        reason: "isOff, row ${i + 1}",
      );
    }
    // itemEnterExit left unset inherits a negative trackResize.
    const inheriting = BoardAnimationStyle(trackResize: _neg240);
    expect(
      inheriting.durationFor(BoardAnimationFamily.itemEnterExit),
      Duration.zero,
    );
    expect(inheriting.isOff(BoardAnimationFamily.itemEnterExit), isTrue);
  });

  testWidgets("a negative per-call duration moves and resizes without a "
      "slide", (tester) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms240,
      ),
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    final id = controller.idOfKey("m");
    final anim = controller.anim;

    controller.moveItem(
      "m",
      const BoardSpan(rowStart: 0, colStart: 1),
      duration: _ms240.duration,
    );
    // Setup sanity: the fixture slides on a positive duration, so the
    // reads below are not idle for want of a slide.
    expect(anim.hasActiveOffsets, isTrue);
    await _settlePump(tester);
    expect(anim.hasActiveOffsets, isFalse);

    controller.moveItem(
      "m",
      const BoardSpan(rowStart: 0, colStart: 3),
      duration: _neg240.duration,
    );
    // TARGET a: no slide record stands.
    expect(anim.hasActiveOffsets, isFalse);
    // TARGET b: the item paints at its new rectangle.
    expect(anim.offsetOfItem(id), Offset.zero);

    controller.resizeItem(
      "m",
      const BoardSpan(rowStart: 0, colStart: 3, colSpan: 2),
      duration: _neg240.duration,
    );
    // TARGET c: the item is laid out at its new extent.
    expect(anim.extentDeltaOf(id), Offset.zero);
    // TARGET d: nothing drives layout per frame.
    expect(anim.hasLayoutDrivingAnimations, isFalse);
  });

  testWidgets("a negative make-room release closes the gap at once", (
    tester,
  ) async {
    final controller = await _gapFixture(tester);
    final idA = controller.idOfKey("a");
    final anim = controller.anim;
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: _dOnRow0,
      lifted: true,
      duration: _ms240.duration,
    );
    await _settlePump(tester);
    // Setup sanity: the preview displaces `a` one lane.
    expect(anim.offsetOfItem(idA).dy, 18.0);

    controller.releaseMakeRoomPreview(duration: _neg240.duration);
    // TARGET a: `a` is back at rest with no frame pumped.
    expect(anim.offsetOfItem(idA), Offset.zero);
    // TARGET b: no held offset is left to close.
    expect(anim.hasActiveOffsets, isFalse);
  });

  testWidgets("a negative make-room install opens the gap at once", (
    tester,
  ) async {
    final controller = await _gapFixture(tester);
    final idA = controller.idOfKey("a");
    final anim = controller.anim;
    // Setup sanity: nothing holds an offset for `a`, so the install below
    // creates its entry rather than re-targeting one.
    expect(anim.hasActiveOffsets, isFalse);

    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: _dOnRow0,
      lifted: true,
      duration: _neg240.duration,
    );
    // TARGET a: `a` is displaced with no frame pumped.
    expect(anim.offsetOfItem(idA).dy, 18.0);
    // TARGET b: the gap is at its target, not moving.
    expect(anim.hasMakeRoomMotion, isFalse);
    controller.releaseMakeRoomPreview(duration: Duration.zero);
  });

  testWidgets("a negative make-room clock publishes no negative hand-off", (
    tester,
  ) async {
    final controller = await _gapFixture(tester);
    final anim = controller.anim;
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: _dOnRow0,
      lifted: true,
      duration: _ms240.duration,
    );
    // Setup sanity: `d`'s prospective lane slot is opening on row 0.
    expect(anim.makeRoomSlotsOn(0), isNotEmpty);

    // A lifted install for a different id discards `d`'s slot mid-motion.
    controller.previewMakeRoomGap(
      draggedKey: "b",
      prospective: const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      lifted: true,
      duration: _neg240.duration,
    );
    final handOff = anim.makeRoomHandOff;
    // Setup sanity: the discard published a hand-off.
    expect(handOff, isNotNull);
    // TARGET: the hand-off carries no time.
    expect(handOff!.remaining, Duration.zero);
    controller.releaseMakeRoomPreview(duration: Duration.zero);
  });

  group("every animation source settles under a negative family", () {
    testWidgets("the slide engine", (tester) async {
      var style = const BoardAnimationStyle(itemSlide: _neg240);
      final engine = ItemSlideEngine(
        vsync: tester,
        styleOf: () {
          return style;
        },
        notifyNow: () {},
        notifyCoalesced: () {},
      );
      addTearDown(engine.dispose);
      // TARGET a: the install is refused.
      expect(
        engine.animateSlideFrom(
          1,
          const Offset(10.0, 0.0),
          family: BoardAnimationFamily.itemSlide,
        ),
        isFalse,
      );
      style = const BoardAnimationStyle(itemSlide: _ms240);
      // Setup sanity: the engine installs on a positive family.
      expect(
        engine.animateSlideFrom(
          2,
          const Offset(10.0, 0.0),
          family: BoardAnimationFamily.itemSlide,
        ),
        isTrue,
      );
      style = const BoardAnimationStyle(itemSlide: _neg240);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // TARGET b: the record in flight settled.
      expect(engine.hasActive, isFalse);
    });

    testWidgets("the track animator", (tester) async {
      var style = const BoardAnimationStyle(trackResize: _neg240);
      final animator = TrackResizeAnimator(
        vsync: tester,
        styleOf: () {
          return style;
        },
        settledExtentOf: (axis, track) {
          return 20.0;
        },
        onTick: () {},
      );
      addTearDown(animator.dispose);
      animator.animateTrackResize(Axis.vertical, 1, 30.0);
      // TARGET a: the install is refused.
      expect(animator.hasActive, isFalse);
      style = const BoardAnimationStyle(trackResize: _ms240);
      animator.animateTrackResize(Axis.vertical, 1, 30.0);
      // Setup sanity: the animator installs on a positive family.
      expect(animator.hasActive, isTrue);
      style = const BoardAnimationStyle(trackResize: _neg240);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // TARGET b: the state in flight settled at the settled extent.
      expect(animator.hasActive, isFalse);
      expect(animator.animatedExtentOf(Axis.vertical, 1), 20.0);
    });

    testWidgets("the enter/exit animator", (tester) async {
      const style = BoardAnimationStyle(itemEnterExit: _neg240);
      final settled = <int>[];
      late final ItemEnterExitAnimator animator;
      animator = ItemEnterExitAnimator(
        vsync: tester,
        styleOf: () {
          return style;
        },
        isExitingOf: (id) {
          return false;
        },
        onSettle: (id) {
          settled.add(id);
          animator.clearForId(id);
        },
        onTick: () {},
      );
      addTearDown(animator.dispose);
      animator.animateEnter(1, family: BoardAnimationFamily.itemEnterExit);
      await tester.pump();
      // TARGET: the enter settled on its first tick.
      expect(settled, <int>[1]);
      expect(animator.hasActive, isFalse);
    });

    testWidgets("the make-room engine", (tester) async {
      var style = const BoardAnimationStyle(makeRoom: _neg240);
      final engine = MakeRoomEngine(
        vsync: tester,
        styleOf: () {
          return style;
        },
        notifyNow: () {},
        notifyCoalesced: () {},
        laneAxisOf: () {
          return null;
        },
        dryRunOf: (draggedId, prospective) {
          return const <int, ({int lane, int laneCount, int laneSpan})>{};
        },
        laneOriginOfId: (id, lane, laneCount) {
          return 0.0;
        },
        prospectiveExtentOf: (id, prospective, assignment) {
          return const Offset(40.0, 0.0);
        },
        laneOfId: (id) {
          return 0;
        },
        laneCountOfId: (id) {
          return 1;
        },
      );
      addTearDown(engine.dispose);
      const prospective = BoardSpan(rowStart: 0, colStart: 0);
      engine.previewGap(draggedId: 1, prospective: prospective);
      // TARGET a: the install snaps to its extent.
      expect(engine.extentDeltaOf(1), const Offset(40.0, 0.0));
      expect(engine.hasMotion, isFalse);
      engine.releasePreview(duration: Duration.zero);
      // Setup sanity: the snap release emptied the engine.
      expect(engine.hasHeldExtent, isFalse);

      style = const BoardAnimationStyle(makeRoom: _ms240);
      engine.previewGap(draggedId: 1, prospective: prospective);
      // Setup sanity: on a positive family the extent opens over time.
      expect(engine.hasMotion, isTrue);
      style = const BoardAnimationStyle(makeRoom: _neg240);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // TARGET b: the opening settled at its target.
      expect(engine.hasMotion, isFalse);
      expect(engine.extentDeltaOf(1), const Offset(40.0, 0.0));

      style = const BoardAnimationStyle(makeRoom: _ms240);
      engine.releasePreview(duration: _ms240.duration);
      style = const BoardAnimationStyle(makeRoom: _neg240);
      // A snap release discards the closing extent.
      engine.releasePreview(duration: Duration.zero);
      final handOff = engine.handOff;
      // Setup sanity: the discard published a hand-off.
      expect(handOff, isNotNull);
      // TARGET c: the hand-off carries no time.
      expect(handOff!.remaining, Duration.zero);
    });
  });
}
