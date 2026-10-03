/// Tests for item 7A of the board audit fixes: the model keeps its own
/// invariants against the inputs a release build lets through, and its
/// capture sites see every item they must.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7A", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 6 left, with every setup sanity
/// assertion before it passing.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';

class _Item {
  const _Item(this.key);

  final String key;

  @override
  String toString() {
    return "_Item($key)";
  }
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  required BoardAxisConfig columns,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns,
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Slides on, everything else off.
const BoardAnimationStyle _slideOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemEnterExit: _zero,
  itemSlide: BoardAnimationSpec(
    duration: Duration(milliseconds: 300),
    curve: Curves.linear,
  ),
);

/// A span that bypasses [BoardSpan]'s constructor asserts, which is what
/// every [BoardSpan] built in a RELEASE build is.
class _ReleaseModeSpan implements BoardSpan {
  const _ReleaseModeSpan({
    required this.rowStart,
    required this.colStart,
    required this.rowFraction,
  });

  @override
  final int rowStart;
  @override
  final int colStart;
  @override
  int get rowSpan {
    return 1;
  }

  @override
  int get colSpan {
    return 1;
  }

  @override
  final double rowFraction;
  @override
  double get colFraction {
    return 0.0;
  }

  @override
  double get rowSpanFraction {
    return 0.0;
  }

  @override
  double get colSpanFraction {
    return 0.0;
  }

  @override
  int spanOn(Axis axis) {
    return 1;
  }

  @override
  int startOn(Axis axis) {
    return axis == Axis.vertical ? rowStart : colStart;
  }

  @override
  double startTrackOn(Axis axis) {
    return axis == Axis.vertical ? rowStart + rowFraction : colStart + 0.0;
  }

  @override
  double endTrackOn(Axis axis) {
    return startTrackOn(axis) + 1.0;
  }

  @override
  BoardSpan copyWith({
    int? rowStart,
    int? colStart,
    int? rowSpan,
    int? colSpan,
    double? rowFraction,
    double? colFraction,
    double? rowSpanFraction,
    double? colSpanFraction,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  // Test 1 (F2).
  test("UniformAxis.trackAt clamps a non-finite offset like the other "
      "three axes", () {
    final explicit = ExplicitAxis(List<double>.filled(10, 40.0));
    final derived = DerivedAxis(10, (track) {
      return 40.0;
    });
    final lazy = LazyContentAxis(10, 40.0);
    // Setup sanity: the other three answer the documented clamp.
    for (final axis in <BoardAxis>[explicit, derived, lazy]) {
      expect(axis.trackAt(double.infinity), 9);
      expect(axis.trackAt(double.negativeInfinity), 0);
      expect(axis.trackAt(double.nan), 0);
    }
    final uniform = UniformAxis(10, 40.0);
    // TARGET: the same three answers, where the division threw.
    expect(uniform.trackAt(double.infinity), 9);
    expect(uniform.trackAt(double.negativeInfinity), 0);
    expect(uniform.trackAt(double.nan), 0);
  });

  // Test 2 (F3). The extents came from the callback exactly; a difference
  // of prefix sums rounds some of them below the value given, and below
  // the minimum the axis promises never to report under.
  test("DerivedAxis.extentOf reports the extent it was given", () {
    final axis = DerivedAxis(2000, (track) {
      return 23.4;
    });
    expect(axis.minTrackExtent, 23.4);
    var off = 0;
    for (var track = 0; track < 2000; track++) {
      if (axis.extentOf(track) != 23.4) {
        off++;
      }
    }
    // TARGET.
    expect(off, 0);
  });

  // Test 3 (F4). A structural listener that re-adds the key removeItem
  // just retired gets the released id back; the relanes installed after
  // the notification matched it by key and slid it from the dead
  // incarnation's rectangle.
  testWidgets("a key re-added from inside removeItem's notification does "
      "not slide from the removed incarnation's rectangle", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: 12.0),
      columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
      style: _slideOnly,
    );
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 0, colStart: 1, colSpan: 2),
    );
    final removedId = controller.idOfKey("a");
    // Setup sanity: the two chips share row 0's lane bucket.
    expect(controller.laneCountOf("a"), 2);
    expect(controller.laneOf("b"), 1);

    var reAdded = false;
    void listener(Set<String>? affectedKeys) {
      if (reAdded || controller.contains("a")) {
        return;
      }
      reAdded = true;
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 5, colSpan: 1),
      );
    }

    controller.addStructuralListener(listener);
    addTearDown(() {
      controller.removeStructuralListener(listener);
    });
    controller.removeItem("a");
    final freshId = controller.idOfKey("a");
    // Setup sanity: the listener ran, and the fresh incarnation took the
    // released id back.
    expect(reAdded, isTrue);
    expect(freshId, removedId);
    final fresh = controller.anim.offsetOfItem(freshId);
    final neighbourLead = controller.anim.offsetOfItem(controller.idOfKey("b"));
    // Purge before asserting, so a failure leaves no ticker running.
    controller.animationStyle = BoardAnimationStyle.disabled;
    // TARGET: the fresh item did not slide in from the dead one's place.
    expect(fresh, Offset.zero);
    // And the survivor, which moved from lane 1 to lane 0, still slides.
    expect(neighbourLead, isNot(Offset.zero));
  });

  // Test 3b (F4, the order). The relanes used to install AFTER the
  // notification, so a listener that removed and re-added a NEIGHBOUR
  // handed the install that neighbour's recycled id under the same key,
  // and the fresh neighbour slid from the dead one's rectangle. The skip
  // of the removed id cannot reach this; only installing first does.
  testWidgets("a neighbour re-added from inside removeItem's notification "
      "does not slide from its removed incarnation's rectangle",
      (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: 12.0),
      columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
      style: _slideOnly,
    );
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 0, colStart: 1, colSpan: 2),
    );
    final oldB = controller.idOfKey("b");
    expect(controller.laneOf("b"), 1);

    var swapped = false;
    void listener(Set<String>? affectedKeys) {
      if (swapped) {
        return;
      }
      swapped = true;
      controller.removeItem("b");
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 3, colStart: 5, colSpan: 1),
      );
    }

    controller.addStructuralListener(listener);
    addTearDown(() {
      controller.removeStructuralListener(listener);
    });
    controller.removeItem("a");
    final freshB = controller.idOfKey("b");
    // Setup sanity: the listener swapped b, and the fresh b took the old
    // id back.
    expect(swapped, isTrue);
    expect(freshB, oldB);
    final offset = controller.anim.offsetOfItem(freshB);
    controller.animationStyle = BoardAnimationStyle.disabled;
    // TARGET: the fresh b, on row 3, did not slide from row 0.
    expect(offset, Offset.zero);
  });

  // Test 4 (F5). The capture walked the resolver's live bucket while its
  // first geometry read resolved that bucket, sorting it in place.
  testWidgets("addItem inside runBatch captures every neighbour of a lane "
      "bucket an earlier in-batch setItems left dirty", (tester) async {
    BoardController<String, _Item> make() {
      return _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: 12.0),
        columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
        style: _slideOnly,
      );
    }

    // y1 sorts AFTER y2 on the sweep axis but is placed first, so the
    // unsorted bucket is [y1, y2] and the sorted one [y2, y1].
    final placements = <BoardPlacement<_Item>>[
      const BoardPlacement<_Item>(
        _Item("y1"),
        BoardSpan(rowStart: 0, colStart: 3, colSpan: 2),
      ),
      const BoardPlacement<_Item>(
        _Item("y2"),
        BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      ),
    ];
    const y3 = BoardSpan(rowStart: 0, colStart: 0, colSpan: 2);

    // Control: the same two steps OUTSIDE a batch.
    final control = make();
    control.setItems(placements);
    control.addItem(const _Item("y3"), y3);
    expect(control.laneCountOf("y2"), 2);
    final controlExtent = control.anim.extentDeltaOf(control.idOfKey("y2"));
    control.animationStyle = BoardAnimationStyle.disabled;
    expect(controlExtent, isNot(Offset.zero));

    final batched = make();
    batched.runBatch(() {
      batched.setItems(placements);
      batched.addItem(const _Item("y3"), y3);
    });
    expect(batched.laneCountOf("y2"), 2);
    expect(batched.laneCountOf("y1"), 1);
    final batchedExtent = batched.anim.extentDeltaOf(batched.idOfKey("y2"));
    batched.animationStyle = BoardAnimationStyle.disabled;
    // TARGET: y2 was captured and slides to its new band.
    expect(batchedExtent, controlExtent);
  });

  // Test 5 (F6). A span a release build lets through, a NaN fraction, is
  // refused at the door, before anything is written.
  testWidgets("a span with a NaN fraction is refused before it touches the "
      "board", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 40.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
    );
    const bad = _ReleaseModeSpan(
      rowStart: 1,
      colStart: 1,
      rowFraction: double.nan,
    );
    // TARGET: addItem refuses and registers nothing ...
    expect(() {
      controller.addItem(const _Item("bad"), bad);
    }, throwsArgumentError);
    expect(controller.contains("bad"), isFalse);

    // ... moveItem refuses and leaves the item where it was ...
    controller.addItem(const _Item("a"), const BoardSpan(rowStart: 2, colStart: 2));
    expect(() {
      controller.moveItem("a", bad);
    }, throwsArgumentError);
    expect(controller.spanOf("a"), const BoardSpan(rowStart: 2, colStart: 2));

    // ... and setItems refuses the whole call, applying no placement.
    expect(() {
      controller.setItems(<BoardPlacement<_Item>>[
        const BoardPlacement<_Item>(
          _Item("c"),
          BoardSpan(rowStart: 0, colStart: 0),
        ),
        const BoardPlacement<_Item>(_Item("d"), bad),
      ]);
    }, throwsArgumentError);
    expect(controller.contains("c"), isFalse);
    expect(controller.contains("a"), isTrue);
  });

  // Test 6 (F7).
  testWidgets("updateItem with another key's payload throws StateError",
      (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 40.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
    );
    controller.addItem(const _Item("a"), const BoardSpan(rowStart: 0, colStart: 0));
    // Setup sanity: the house's own key errors are StateError.
    expect(() {
      controller.updateItem("missing", const _Item("missing"));
    }, throwsStateError);
    // TARGET.
    expect(() {
      controller.updateItem("a", const _Item("b"));
    }, throwsStateError);
    expect(controller.itemOf("a")!.key, "a");
  });
}
