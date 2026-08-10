/// End-to-end: a real pointer drag in a mounted declarative sectioned
/// list, asserting where the row actually LANDS.
///
/// Everything else in this feature is tested at the resolver, controller
/// or single-widget level. This is the one that would catch a break in
/// the chain between them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Col {
  const _Col(this.id, this.tasks);
  final String id;
  final List<String> tasks;
}

void main() {
  late List<_Col> board;
  late SectionedListController<String, _Col, String> controller;

  Future<void> mount(
    WidgetTester tester,
    List<_Col> initial, {
    bool collapseSecond = false,
  }) async {
    board = initial;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  SectionedSliverList<String, _Col, String>(
                    sections: board,
                    itemsOf: (c) {
                      return c.tasks;
                    },
                    sectionKeyOf: (c) {
                      return c.id;
                    },
                    itemKeyOf: (t) {
                      return t;
                    },
                    animationStyle: TreeAnimationStyle.disabled,
                    initialSectionExpansion: (key, section) {
                      return !(collapseSecond && key == initial.last.id);
                    },
                    reorder: SectionedReorderConfig<String, _Col, String>(
                      showDragProxy: false,
                      // Record the move, exactly as the docs instruct, so
                      // the follow-up sync is a no-op instead of a revert.
                      onItemReorder: (item, section, index) {
                        setState(() {
                          final next = <_Col>[
                            for (final c in board)
                              _Col(c.id, <String>[
                                for (final t in c.tasks)
                                  if (t != item) t,
                              ]),
                          ];
                          final target = next.firstWhere((c) {
                            return c.id == section;
                          });
                          final tasks = List<String>.of(target.tasks)
                            ..insert(index.clamp(0, target.tasks.length), item);
                          board = <_Col>[
                            for (final c in next)
                              c.id == section ? _Col(c.id, tasks) : c,
                          ];
                        });
                      },
                    ),
                    headerBuilder: (ctx, view) {
                      controller = view.controller;
                      return SizedBox(
                        key: ValueKey("sec-${view.key}"),
                        height: 50,
                        child: Text(view.key),
                      );
                    },
                    itemBuilder: (ctx, view) {
                      controller = view.controller;
                      return SizedBox(
                        key: ValueKey("item-${view.key}"),
                        height: 50,
                        child: Text(view.key),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, String row, double dy) async {
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey(row))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    // Move in steps so the resolver sees intermediate positions, as a
    // real gesture would.
    for (var i = 0; i < 4; i++) {
      await g.moveBy(Offset(0.0, dy / 4));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets("an item dragged across sections lands in the target section", (
    tester,
  ) async {
    // Rows: todo(0) t1(50) t2(100) done(150) d1(200).
    await mount(tester, const <_Col>[
      _Col("todo", <String>["t1", "t2"]),
      _Col("done", <String>["d1"]),
    ]);
    expect(controller.itemKeysOf("todo"), <String>["t1", "t2"]);

    await drag(tester, "item-t1", 180.0);

    expect(controller.itemKeysOf("todo"), isNot(contains("t1")));
    expect(controller.itemKeysOf("done"), contains("t1"));
    // And the app's own model agrees, so the next sync is a no-op rather
    // than a revert.
    expect(board.firstWhere((c) => c.id == "done").tasks, contains("t1"));
  });

  testWidgets("a within-section drag reorders without changing section", (
    tester,
  ) async {
    await mount(tester, const <_Col>[
      _Col("todo", <String>["t1", "t2", "t3"]),
    ]);
    await drag(tester, "item-t1", 110.0);

    expect(controller.itemKeysOf("todo").length, 3);
    expect(
      controller.itemKeysOf("todo").first,
      isNot("t1"),
      reason: "t1 moved down",
    );
    expect(board.single.tasks.length, 3);
  });

  testWidgets("a cancelled drag changes nothing", (tester) async {
    await mount(tester, const <_Col>[
      _Col("todo", <String>["t1", "t2"]),
      _Col("done", <String>["d1"]),
    ]);
    final before = controller.itemKeysOf("todo");

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("item-t1"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0.0, 160.0));
    await tester.pump();
    await g.cancel();
    await tester.pumpAndSettle();

    expect(controller.itemKeysOf("todo"), before);
    expect(controller.itemKeysOf("done"), <String>["d1"]);
  });

  testWidgets("dropping into a COLLAPSED section still lands in it", (
    tester,
  ) async {
    await mount(tester, const <_Col>[
      _Col("todo", <String>["t1", "t2"]),
      _Col("done", <String>["d1"]),
    ], collapseSecond: true);
    expect(controller.isExpanded("done"), isFalse, reason: "setup");
    // Rows: todo(0) t1(50) t2(100) done(150). Aim at the middle of the
    // collapsed header, which is the `into` zone.
    await drag(tester, "item-t1", 125.0);

    expect(controller.itemKeysOf("done"), contains("t1"));
    expect(controller.itemKeysOf("todo"), isNot(contains("t1")));
  });
}
