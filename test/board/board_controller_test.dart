/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 4, the L2 controller core. These are
/// `testWidgets` because the harness rule puts every case from L2 upward on
/// that spelling, and here the reason is the obvious one: the controller
/// takes a `TickerProvider`, and `tester` is it. No case pumps a widget;
/// there is no render object at step 4, which is exactly why the lane flush
/// needs its read-entry arm.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';

/// The caller payload used throughout. [label] exists so a payload-only
/// write is observable: without a second field, `updateItem` could not be
/// told from a no-op.
class _Item {
  const _Item(this.key, [this.label = ""]);

  final String key;
  final String label;

  @override
  String toString() {
    return "_Item($key, $label)";
  }
}

/// A board whose axes are both fixed, so no axis is content-sized and the
/// PRIMARY axis is the row axis by the derivation's "otherwise" arm.
BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAxisConfig? rows,
  BoardAxisConfig? columns,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows ?? BoardAxisConfig(axis: UniformAxis(6, 40.0)),
    columns: columns ?? BoardAxisConfig(axis: UniformAxis(7, 60.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// A ROW axis carrying a lane extent, which makes the ROW axis the lane
/// axis and the COLUMN axis the sweep axis: the month-calendar shape, where
/// chips span days inside one week row and stack in lanes within it.
BoardAxisConfig _lanedRows() {
  return BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: 12.0);
}

/// A span covering `colSpan` columns of one row, which is laned when the
/// row axis is the lane axis.
BoardSpan _chip(int row, int colStart, int colSpan) {
  return BoardSpan(rowStart: row, colStart: colStart, colSpan: colSpan);
}

/// Records every structural notification, copying each key set so a later
/// mutation cannot rewrite what was already delivered. The listener is
/// removed on tear-down, before the controller's own tear-down runs, which
/// is what keeps `dispose`'s empty-listener assert satisfied.
List<Set<String>?> _logStructural(BoardController<String, _Item> controller) {
  final log = <Set<String>?>[];
  void listener(Set<String>? affectedKeys) {
    log.add(affectedKeys == null ? null : Set<String>.of(affectedKeys));
  }

  controller.addStructuralListener(listener);
  addTearDown(() {
    controller.removeStructuralListener(listener);
  });
  return log;
}

/// Records every item-data notification, in order.
List<String> _logItemData(BoardController<String, _Item> controller) {
  final log = <String>[];
  void listener(String key) {
    log.add(key);
  }

  controller.addItemDataListener(listener);
  addTearDown(() {
    controller.removeItemDataListener(listener);
  });
  return log;
}

/// Counts animation-channel dispatches.
List<void> _logAnimation(BoardController<String, _Item> controller) {
  final log = <void>[];
  void listener() {
    log.add(null);
  }

  controller.addAnimationListener(listener);
  addTearDown(() {
    controller.removeAnimationListener(listener);
  });
  return log;
}

void main() {
  // Performance plan T3 (plans/2026-09-07-board-performance-plan.md).
  // Asserts: a setItems re-sync whose placements all share one lane-axis
  // track walks that bucket once. The SLIDE family is live: the capture
  // runs only under a non-zero itemSlide, and under the helper's default
  // both halves read 0. The two extent families stay at zero so the
  // first sync starts no enter ticker for the test to leak.
  // Falsification: one walk per collected track entry, two entries per
  // placement, reports 400.
  testWidgets(
    "a setItems re-sync reads each disturbed lane bucket once per distinct "
    "track",
    (tester) async {
      final controller = _controller(
        tester,
        rows: _lanedRows(),
        style: const BoardAnimationStyle(
          trackResize: BoardAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
          itemEnterExit: BoardAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
          itemSlide: BoardAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      final placements = <BoardPlacement<_Item>>[
        for (var i = 0; i < 200; i++)
          BoardPlacement<_Item>(_Item("k$i"), _chip(0, i % 7, 1)),
      ];
      controller.setItems(placements);
      // Setup sanity: the first sync read the bucket at all.
      expect(controller.debugLaneBucketMemberReadCount, greaterThan(0));
      controller.debugLaneBucketMemberReadCount = 0;
      controller.setItems(placements);
      expect(controller.debugLaneBucketMemberReadCount, 1);
    },
  );

  // DERIVED name. No AC; board_controller_test.dart is listed under the
  // tests not tied to one criterion.
  // Asserts: runBatch defers the structural and item-data channels; the
  // animation channel is NOT deferred and a batch manufactures no
  // dispatch for it. A key mutated BOTH structurally and by data inside
  // one batch receives BOTH notifications.
  // Falsification: an implementation that suppresses the data dispatch
  // for a key the structural set already names drops "a" from the data
  // log; one that defers all three would need an animation producer to
  // catch, which none exists here, so that half is pinned by the
  // non-manufacture assertion.
  testWidgets(
      "runBatch defers the structural and item-data channels, not the "
      "animation channel", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(const _Item("a"), _chip(0, 0, 1));
    controller.addItem(const _Item("b"), _chip(1, 0, 1));
    controller.addItem(const _Item("c"), _chip(2, 0, 1));
    final structural = _logStructural(controller);
    final data = _logItemData(controller);
    final animation = _logAnimation(controller);

    controller.runBatch(() {
      controller.moveItem("a", _chip(0, 3, 1));
      // Deferred: the mutation has happened, and nothing has been
      // delivered.
      expect(structural, isEmpty);
      expect(controller.spanOf("a")!.colStart, 3);
      controller.moveItem("c", _chip(2, 4, 1));
      controller.updateItem("b", const _Item("b", "changed"));
      // The both-channels key: "a" is structurally moved above AND
      // data-written here, inside one batch.
      controller.updateItem("a", const _Item("a", "changed"));
      expect(data, isEmpty);
      expect(animation, isEmpty);
    });

    // ONE structural dispatch for the batch, carrying the union.
    expect(structural, hasLength(1));
    expect(structural.single, <String>{"a", "c"});
    // Item data fires after structural, once per dirty key, and a key the
    // structural set already names STILL gets its data notification:
    // subsumption is a per-mutation rule, not a per-batch one.
    expect(data, containsAll(<String>["a", "b"]));
    // The animation channel is not deferred and has no producer here, so
    // a batch must not manufacture a dispatch for it.
    expect(animation, isEmpty);
  });

  // DERIVED name. No AC.
  // Asserts: unknown-key mutators throw StateError in both build modes.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets("unknown-key mutators throw StateError in both build modes", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(const _Item("a"), _chip(0, 0, 1));

    // Setup sanity, falsifiable in the direction it claims: the same four
    // calls against a KNOWN key do not throw and do reach the model, so
    // the four below fail on the key and not on the call.
    controller.moveItem("a", _chip(1, 0, 1));
    controller.resizeItem("a", _chip(1, 0, 2));
    // The resize's span write is otherwise unasserted anywhere.
    expect(controller.spanOf("a"), _chip(1, 0, 2));
    controller.updateItem("a", const _Item("a", "ok"));
    controller.removeItem("a");
    expect(controller.contains("a"), isFalse);

    expect(() {
      controller.removeItem("ghost");
    }, throwsA(isA<StateError>()));
    expect(() {
      controller.updateItem("ghost", const _Item("ghost"));
    }, throwsA(isA<StateError>()));
    expect(() {
      controller.moveItem("ghost", _chip(0, 0, 1));
    }, throwsA(isA<StateError>()));
    expect(() {
      controller.resizeItem("ghost", _chip(0, 0, 2));
    }, throwsA(isA<StateError>()));
  });

  // DERIVED name. No AC.
  // Asserts: the primary-axis and laneAxis derivations and both of I15's
  // asserts.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets(
    "the primary-axis and laneAxis derivations hold both of I15's asserts",
    (tester) async {
      // A lane extent on the ROW config makes the ROW axis the lane axis.
      final onRows = _controller(tester, rows: _lanedRows());
      expect(onRows.laneAxis, Axis.vertical);

      // A lane extent on the COLUMN config makes the COLUMN axis the lane
      // axis on a board whose PRIMARY axis is the ROW axis, because the
      // primary axis is the content-sized one and here that is the rows.
      // The two names denote DIFFERENT axes on this board, which is the
      // whole reason the plan keeps two of them: an implementation that
      // collapsed the lane axis onto the primary one would answer
      // vertical.
      final onColumns = _controller(
        tester,
        rows: BoardAxisConfig(axis: LazyContentAxis(6, 40.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 60.0), laneExtent: 12.0),
      );
      expect(onColumns.laneAxis, Axis.horizontal);

      // The accessor reads the live derivation. On the onColumns board the
      // primary axis (content-sized rows) and the lane axis (columns)
      // DENOTE DIFFERENT AXES, so an implementation that collapsed the two
      // names answers horizontal here and goes red.
      expect(onRows.primaryAxis, Axis.vertical);
      expect(onColumns.primaryAxis, Axis.vertical);

      // The first arm in the other direction: content-sized COLUMNS make
      // the column axis primary.
      final contentColumns = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(4, 40.0)),
        columns: BoardAxisConfig(axis: LazyContentAxis(6, 40.0)),
      );
      expect(contentColumns.primaryAxis, Axis.horizontal);

      // I14 at the constructor: TWO content-sized axes are refused. This
      // assert previously had no witness; deleting it reddened nothing.
      expect(() {
        BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(axis: LazyContentAxis(4, 40.0)),
          columns: BoardAxisConfig(axis: LazyContentAxis(6, 40.0)),
          keyOf: (item) {
            return item.key;
          },
        );
      }, throwsAssertionError);
      // I14 at both setters, reached at runtime.
      expect(() {
        contentColumns.rows = BoardAxisConfig(axis: LazyContentAxis(4, 40.0));
      }, throwsAssertionError);
      final contentRows = _controller(
        tester,
        rows: BoardAxisConfig(axis: LazyContentAxis(4, 40.0)),
        columns: BoardAxisConfig(axis: UniformAxis(6, 40.0)),
      );
      expect(() {
        contentRows.columns = BoardAxisConfig(axis: LazyContentAxis(6, 40.0));
      }, throwsAssertionError);

      // The animationStyle property itself: round trip plus the setter's
      // validation.
      const restyle = BoardAnimationStyle(
        itemSlide: BoardAnimationSpec(
          duration: Duration(milliseconds: 217),
          curve: Curves.easeIn,
        ),
      );
      contentRows.animationStyle = restyle;
      expect(contentRows.animationStyle, same(restyle));
      expect(() {
        contentRows.animationStyle = const BoardAnimationStyle(
          trackResize: BoardAnimationSpec(
            duration: Duration(milliseconds: -1),
            curve: Curves.linear,
          ),
        );
      }, throwsAssertionError);

      // I15 at the constructor: two lane extents leave the lane axis, and
      // with it every lane bucket's key, undefined.
      expect(() {
        BoardController<String, _Item>(
          vsync: tester,
          rows: _lanedRows(),
          columns: BoardAxisConfig(
            axis: UniformAxis(7, 60.0),
            laneExtent: 12.0,
          ),
          keyOf: (item) {
            return item.key;
          },
        );
      }, throwsAssertionError);

      // I15 at the `columns` setter: the same violation reached at
      // runtime, and a separate assert site from the constructor's.
      expect(() {
        onRows.columns = BoardAxisConfig(
          axis: UniformAxis(7, 60.0),
          laneExtent: 12.0,
        );
      }, throwsAssertionError);

      // I15 at the `rows` setter, which is a third site and fails on its
      // own.
      expect(() {
        onColumns.rows = _lanedRows();
      }, throwsAssertionError);
    },
  );

  // DERIVED name. No AC; the null-laneAxis board.
  // Asserts: the primary axis is the row axis and itemsAt still answers.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets(
    "a null laneAxis makes the row axis primary and itemsAt still answers",
    (tester) async {
      // Neither config carries a lane extent and neither axis is
      // content-sized: the spreadsheet and gantt configuration, where the
      // primary axis falls to the ROW axis by the derivation's second arm.
      final controller = _controller(tester);
      expect(controller.laneAxis, isNull);
      // The derivation's second arm: nothing content-sized, so the row
      // axis is primary.
      expect(controller.primaryAxis, Axis.vertical);

      // The unknown-key READ answers, beside the live ones this case
      // already asserts: reads answer their defaults and only contains
      // discriminates.
      expect(controller.spanOf("ghost"), isNull);
      expect(controller.itemOf("ghost"), isNull);
      expect(controller.contains("ghost"), isFalse);
      expect(controller.isDragging("ghost"), isFalse);
      expect(controller.laneOf("ghost"), 0);
      expect(controller.laneCountOf("ghost"), 1);

      controller.addItem(const _Item("wide"), _chip(1, 1, 3));
      controller.addItem(
        const _Item("tall"),
        const BoardSpan(rowStart: 0, colStart: 5, rowSpan: 3),
      );

      // itemsAt answers on a board that has no lane axis at all, for an
      // item spanning several columns and for one spanning several rows.
      expect(controller.itemsAt(1, 2), <String>["wide"]);
      expect(controller.itemsAt(2, 5), <String>["tall"]);
      // Half-open on the trailing side: the three-row item covers rows 0
      // to 2 and not row 3.
      expect(controller.itemsAt(3, 5), isEmpty);
      // De-duplication: the multi-row item is listed in three primary-axis
      // buckets and comes back ONCE from a query that visits all three.
      expect(controller.itemsIn(0, 3, 5, 6), <String>["tall"]);

      // Every item keeps lane 0 of 1 and no bucket is ever resolved, which
      // is what "a null lane axis costs nothing" means.
      expect(controller.laneOf("wide"), 0);
      expect(controller.laneCountOf("wide"), 1);
      expect(controller.debugLaneBucketResolveCount, 0);
    },
  );

  // DERIVED name. No AC; the first of I25's three affectedKeys meanings,
  // which the plan asks to be tested each separately.
  // Asserts: a full-refresh mutator delivers null.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets("a full-refresh mutator delivers a null affectedKeys", (
    tester,
  ) async {
    final controller = _controller(tester, rows: _lanedRows());
    controller.addItem(const _Item("a"), _chip(0, 0, 2));
    final structural = _logStructural(controller);
    controller.addItem(const _Item("b"), _chip(0, 1, 2));

    // Setup sanity: an ordinary mutator delivers a NON-null set, so the
    // nulls below are the axis swap's doing and not the channel's normal
    // shape.
    expect(structural, hasLength(1));
    expect(structural.single, <String>{"a", "b"});
    expect(controller.itemsAt(0, 1), unorderedEquals(<String>["a", "b"]));
    structural.clear();

    // Swapping in a content-sized COLUMN axis moves the primary axis from
    // the rows to the columns, which re-keys every span-index bucket.
    controller.columns = BoardAxisConfig(axis: LazyContentAxis(7, 60.0));
    expect(structural, hasLength(1));
    expect(structural.single, isNull);
    // The items are re-registered into the new partition rather than lost
    // with the old keys.
    expect(controller.itemsAt(0, 1), unorderedEquals(<String>["a", "b"]));
    structural.clear();

    // Dropping the lane extent moves the lane axis to null, which rebuilds
    // the lane partition rather than marking its old keys dirty, and
    // returns every laned item to lane 0 of 1.
    expect(controller.laneAxis, Axis.vertical);
    expect(controller.laneCountOf("a"), 2);
    controller.rows = BoardAxisConfig(axis: UniformAxis(6, 40.0));
    expect(structural, hasLength(1));
    expect(structural.single, isNull);
    expect(controller.laneAxis, isNull);
    expect(controller.laneCountOf("a"), 1);
  });

  // DERIVED name. No AC; the second of I25's three meanings, and the case
  // an implementer drops.
  // Asserts: a lane-only change delivers a non-empty set CONTAINING the
  // relaid key.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets(
    "a lane-only change delivers a non-empty affectedKeys containing the relaid key",
    (tester) async {
      final controller = _controller(tester, rows: _lanedRows());
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      controller.addItem(const _Item("b"), _chip(0, 1, 2));

      // Setup sanity: the two chips really do overlap on the sweep axis,
      // so there is a lane to lose. Two disjoint chips would report lane 0
      // of 1 here and the case would assert nothing.
      expect(controller.laneCountOf("b"), 2);
      expect(controller.laneOf("b"), 1);
      final spanBefore = controller.spanOf("b")!;

      final structural = _logStructural(controller);
      controller.removeItem("a");

      // The surviving neighbour was relaid, and the change was lane-ONLY:
      // nothing touched its span.
      expect(controller.spanOf("b"), spanBefore);
      expect(controller.laneOf("b"), 0);
      expect(controller.laneCountOf("b"), 1);

      expect(structural, hasLength(1));
      // NOT null and NOT empty: a built child's rendered inputs changed
      // even though nothing touched its span, and an empty set means no
      // built child's builder output changed.
      expect(structural.single, isNotNull);
      expect(structural.single, contains("b"));
      // The retired key is gone from the model, so it is never named.
      expect(structural.single, isNot(contains("a")));
    },
  );

  // DERIVED name. No AC; the third of I25's three meanings, the
  // structural-subsumes-data half.
  // Asserts: updateItem fires the data channel and NOT the structural one.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets("updateItem fires the data channel and not the structural one", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(const _Item("a", "before"), _chip(0, 0, 1));
    final structural = _logStructural(controller);
    final data = _logItemData(controller);

    controller.updateItem("a", const _Item("a", "after"));

    expect(data, <String>["a"]);
    expect(structural, isEmpty);
    expect(controller.itemOf("a")!.label, "after");
    // A payload write touches no span component, which is the reason the
    // two channels are separate at all.
    expect(controller.spanOf("a"), _chip(0, 0, 1));
  });

  // DERIVED name. No AC; the lane-change accumulator's defeater, which the
  // lane-only case alone cannot catch, because with no interleaved read a
  // dirty-set derivation answers identically.
  // Asserts: inside ONE runBatch, mutate, then READ laneCountOf on a
  // neighbour, which flushes and empties the dirty set, then mutate again,
  // and assert the coalesced exit notification still names every key whose
  // lane or lane count changed across BOTH mutations.
  // Falsification: a derivation that reads the dirty-bucket set delivers a
  // set missing the first mutation's keys, and per I25 a key absent from
  // the set never rebuilds.
  testWidgets(
    "a laneCountOf read between two in-batch mutations keeps both mutations' keys in the exit notification",
    (tester) async {
      final controller = _controller(tester, rows: _lanedRows());
      // Two independent lane-axis buckets, each holding an overlapping
      // pair, so the two in-batch mutations dirty two different buckets.
      controller.addItem(const _Item("a"), _chip(0, 0, 2));
      controller.addItem(const _Item("b"), _chip(0, 1, 2));
      controller.addItem(const _Item("c"), _chip(2, 0, 2));
      controller.addItem(const _Item("d"), _chip(2, 1, 2));

      // Setup sanity: both buckets really are two lanes deep before the
      // batch, so both mutations below have a lane change to report.
      expect(controller.laneCountOf("b"), 2);
      expect(controller.laneCountOf("d"), 2);

      final structural = _logStructural(controller);
      controller.runBatch(() {
        controller.removeItem("a");
        // The interleaved read. It flushes, which resolves bucket 0 and
        // EMPTIES the dirty set, and the value it returns is what proves
        // the flush ran on the read's own entry rather than waiting for
        // the batch exit.
        expect(controller.laneCountOf("b"), 1);
        controller.removeItem("c");
      });

      expect(structural, hasLength(1));
      expect(structural.single, isNotNull);
      // The FIRST mutation's relaid key. A derivation that asked "which
      // keys are in the buckets I dirtied" would see an empty set for
      // bucket 0, because the interleaved read cleared it, and would miss
      // this one.
      expect(structural.single, contains("b"));
      // The SECOND mutation's, which that derivation would still deliver.
      expect(structural.single, contains("d"));
      // Exactly the two surviving neighbours: neither retired key is
      // named, because both are gone from the model.
      expect(structural.single, <String>{"b", "d"});
      // The second removal reached the span index too, not only the lane
      // partition: a retire is two de-registrations, not one. Read through
      // the RENDER-facing form, which is the only one that can see it: the
      // caller-facing reads map ids through keyOfId and skip a null, so a
      // stale entry naming a released id is invisible to them.
      expect(
        controller.itemIdsInRectIncludingExiting(2, 3, 0, 1, <int>[]),
        isEmpty,
      );
    },
  );

  // DERIVED name. No AC; the poison-pill rule.
  // Asserts: one in-batch null makes the coalesced exit notification null
  // even when every other in-batch call carried a set.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets("one in-batch null makes the coalesced exit notification null", (
    tester,
  ) async {
    final controller = _controller(tester, rows: _lanedRows());
    controller.addItem(const _Item("a"), _chip(0, 0, 1));
    controller.addItem(const _Item("b"), _chip(1, 0, 1));
    final structural = _logStructural(controller);

    // Setup sanity: the same batch WITHOUT the null delivers a set, so the
    // null below is the pill's doing and not the batch's normal shape.
    controller.runBatch(() {
      controller.moveItem("a", _chip(0, 2, 1));
      controller.moveItem("b", _chip(1, 2, 1));
    });
    expect(structural, hasLength(1));
    expect(structural.single, <String>{"a", "b"});
    structural.clear();

    controller.runBatch(() {
      controller.moveItem("a", _chip(0, 3, 1));
      // The axis swap is the full-refresh call: it carries null.
      controller.rows = _lanedRows();
      controller.moveItem("b", _chip(1, 3, 1));
    });

    expect(structural, hasLength(1));
    expect(structural.single, isNull);
    // The mutations still happened; only the notification's SCOPE was
    // widened. The store took the write, and the index kept the entry the
    // swap ran over.
    expect(controller.spanOf("a")!.colStart, 3);
    expect(controller.itemsAt(0, 3), <String>["a"]);
  });

  // DERIVED name. No AC; setItems's diff over one
  // Iterable<BoardPlacement<TItem>>. The discriminator is the structural
  // channel, not a render counter, so no Board is needed.
  // Asserts: in one setItems carrying three placements, the unchanged key
  // is ABSENT from affectedKeys and the re-spanned key is PRESENT; a key
  // only in the argument enters and a key only in the live set exits.
  // Falsification: each half fails on its own, the first if setItems
  // re-applies every span unconditionally, the second if it skips the
  // notification for a span it did apply.
  testWidgets(
    "setItems keeps an unchanged key out of affectedKeys and puts a re-spanned key in",
    (tester) async {
      final controller = _controller(tester);
      const keptItem = _Item("kept");
      const movedItem = _Item("moved");
      controller.addItem(keptItem, _chip(0, 0, 1));
      controller.addItem(movedItem, _chip(1, 0, 1));
      controller.addItem(const _Item("dropped"), _chip(2, 0, 1));
      final idsBefore = <int>[
        controller.idOfKey("kept"),
        controller.idOfKey("moved"),
      ];
      final structural = _logStructural(controller);

      controller.setItems(<BoardPlacement<_Item>>[
        // Same key, same payload, same span.
        const BoardPlacement<_Item>(
          keptItem,
          BoardSpan(rowStart: 0, colStart: 0),
        ),
        // Same key, new span.
        const BoardPlacement<_Item>(
          movedItem,
          BoardSpan(rowStart: 1, colStart: 4),
        ),
        // A key only in the argument.
        const BoardPlacement<_Item>(
          _Item("added"),
          BoardSpan(rowStart: 3, colStart: 0),
        ),
      ]);

      expect(structural, hasLength(1));
      expect(structural.single, isNotNull);
      // A key in both KEEPS its id: the diff does not retire and re-add
      // it, so nothing downstream that recorded the id goes stale.
      expect(<int>[
        controller.idOfKey("kept"),
        controller.idOfKey("moved"),
      ], idsBefore);
      // The half that fails if setItems re-applies every span
      // unconditionally.
      expect(structural.single, isNot(contains("kept")));
      // The half that fails if it skips the notification for a span it did
      // apply.
      expect(structural.single, contains("moved"));
      expect(structural.single, contains("added"));

      // The diff's three outcomes, read off the model.
      expect(controller.spanOf("moved")!.colStart, 4);
      expect(controller.contains("added"), isTrue);
      expect(controller.contains("dropped"), isFalse);
      // The exiting key left the span index as well as the store, read
      // through the render-facing form for the reason above.
      expect(
        controller.itemIdsInRectIncludingExiting(2, 3, 0, 1, <int>[]),
        isEmpty,
      );
    },
  );

  // DERIVED name. No AC; the duplicate-key rule, which is the case I22 does
  // not cover.
  // Asserts: a setItems carrying one key twice, and an addItem for a key
  // already in the live set, each throw StateError.
  // Falsification: not stated in the Testing Plan section for this case.
  testWidgets(
    "a duplicate key in setItems and a re-added key in addItem each throw StateError",
    (tester) async {
      final controller = _controller(tester);

      // Setup sanity: the same two calls with DISTINCT keys do not throw
      // and do land, so the throws below are about the key arity and not
      // about the call.
      controller.setItems(const <BoardPlacement<_Item>>[
        BoardPlacement<_Item>(_Item("x"), BoardSpan(rowStart: 0, colStart: 0)),
        BoardPlacement<_Item>(_Item("y"), BoardSpan(rowStart: 1, colStart: 0)),
      ]);
      controller.addItem(const _Item("z"), _chip(2, 0, 1));
      expect(controller.contains("y"), isTrue);

      expect(() {
        controller.setItems(const <BoardPlacement<_Item>>[
          BoardPlacement<_Item>(
            _Item("p"),
            BoardSpan(rowStart: 0, colStart: 1),
          ),
          BoardPlacement<_Item>(
            _Item("p"),
            BoardSpan(rowStart: 1, colStart: 1),
          ),
        ]);
      }, throwsA(isA<StateError>()));
      expect(() {
        controller.addItem(const _Item("z"), _chip(3, 0, 1));
      }, throwsA(isA<StateError>()));

      // The duplicate check runs over the whole argument BEFORE any
      // mutation, so the refused call added nothing, retired nothing and
      // left the index alone.
      expect(controller.contains("p"), isFalse);
      expect(controller.contains("x"), isTrue);
      expect(controller.itemsAt(0, 0), <String>["x"]);
    },
  );

  // DERIVED name. No AC.
  // Asserts: for every live key, laneOfId(idOfKey(k)) equals laneOf(k) and
  // keyOfId(idOfKey(k)) equals k, and idOfKey of an unregistered key is -1.
  // Falsification: this is the cheapest way to catch a dense array read
  // that is off by one.
  testWidgets("the id-keyed reads agree with their TKey-keyed twins", (
    tester,
  ) async {
    final controller = _controller(tester, rows: _lanedRows());
    controller.addItem(const _Item("a"), _chip(0, 0, 2));
    controller.addItem(const _Item("b"), _chip(0, 1, 2));
    controller.addItem(
      const _Item("c"),
      const BoardSpan(
        rowStart: 2,
        colStart: 3,
        colSpan: 2,
        rowFraction: 0.25,
        colFraction: 0.5,
        rowSpanFraction: 0.5,
        colSpanFraction: 0.75,
      ),
    );

    // Setup sanity: the lane reads below are not all trivially 0 and 1, so
    // an id-keyed lane read answering a constant would be caught.
    expect(controller.laneOf("b"), 1);
    expect(controller.laneCountOf("b"), 2);

    for (final key in <String>["a", "b", "c"]) {
      final id = controller.idOfKey(key);
      final span = controller.spanOf(key)!;
      expect(controller.keyOfId(id), key);
      expect(controller.laneOfId(id), controller.laneOf(key));
      expect(controller.laneCountOfId(id), controller.laneCountOf(key));
      expect(controller.rowStartOfId(id), span.rowStart);
      expect(controller.rowSpanOfId(id), span.rowSpan);
      expect(controller.colStartOfId(id), span.colStart);
      expect(controller.colSpanOfId(id), span.colSpan);
      expect(controller.rowFractionOfId(id), span.rowFraction);
      expect(controller.colFractionOfId(id), span.colFraction);
      expect(controller.rowSpanFractionOfId(id), span.rowSpanFraction);
      expect(controller.colSpanFractionOfId(id), span.colSpanFraction);
      expect(controller.isDraggingId(id), controller.isDragging(key));
    }

    expect(controller.idOfKey("ghost"), -1);
    expect(controller.keyOfId(-1), isNull);
  });

  // DERIVED name. No AC; the selection VALUE, with no Board in the test.
  // Asserts: setSelection moves selection.value and flips isSelected for
  // exactly the enclosed cells.
  // Falsification: with no Board in the test, this is what shows the state
  // is on the controller rather than on the widget.
  testWidgets(
    "setSelection moves selection.value and flips isSelected for exactly the enclosed cells",
    (tester) async {
      final controller = _controller(tester);

      // Before any setSelection: the empty form, which is what
      // `selection`'s non-nullable type needs a value for.
      expect(controller.selection.value.isEmpty, isTrue);
      expect(controller.isSelected(1, 1), isFalse);

      var notifications = 0;
      void listener() {
        notifications++;
      }

      controller.selection.addListener(listener);
      addTearDown(() {
        controller.selection.removeListener(listener);
      });

      // Focus BEFORE anchor on both axes, so the bounds have to SORT the
      // two corners rather than assume an order.
      controller.setSelection(
        const BoardSelection(anchor: (row: 3, col: 4), focus: (row: 1, col: 1)),
      );

      expect(notifications, 1);
      expect(controller.selection.value.isEmpty, isFalse);
      expect(controller.selection.value.anchor, (row: 3, col: 4));
      expect(controller.selection.value.focus, (row: 1, col: 1));
      expect(controller.selection.value.cells.length, 12);

      final selected = <String>{};
      for (var row = 0; row < 6; row++) {
        for (var col = 0; col < 7; col++) {
          if (controller.isSelected(row, col)) {
            selected.add("$row,$col");
          }
        }
      }
      expect(selected, <String>{
        "1,1",
        "1,2",
        "1,3",
        "1,4",
        "2,1",
        "2,2",
        "2,3",
        "2,4",
        "3,1",
        "3,2",
        "3,3",
        "3,4",
      });

      controller.setSelection(const BoardSelection.none());
      expect(notifications, 2);
      expect(controller.isSelected(2, 2), isFalse);
      expect(controller.selection.value.isEmpty, isTrue);

      // VALUE equality gates the notifier: an equal-but-distinct write is
      // suppressed. Load-bearing since the render object answers every
      // dispatch with a full delegate rebuild.
      controller.setSelection(
        const BoardSelection(anchor: (row: 2, col: 2), focus: (row: 2, col: 2)),
      );
      expect(notifications, 3);
      controller.setSelection(
        // A distinct instance carrying the same corners.
        BoardSelection(anchor: (row: 2, col: 2), focus: (row: 2, col: 2)),
      );
      expect(notifications, 3);
    },
  );
}
