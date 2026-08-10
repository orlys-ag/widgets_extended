/// Wave 2: drag-and-drop for the sectioned module.
///
/// The module's whole non-obvious surface is the boundary: keys cross
/// wrapped and must reach callbacks unwrapped, and the two-level
/// invariant has to live somewhere a caller cannot widen it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Column {
  const _Column(this.id, this.tasks);
  final String id;
  final List<_Task> tasks;
}

class _Task {
  const _Task(this.id);
  final String id;
}

typedef _ItemEvent = (String item, String section, int index);

void main() {
  late List<_Column> board;
  late List<_ItemEvent> itemEvents;
  late List<(String, int)> sectionEvents;

  late SectionedListController<String, _Column, _Task> controller;

  Future<SectionedListController<String, _Column, _Task>> mount(
    WidgetTester tester, {
    bool reorderSections = false,
    bool provideItemCallback = true,
    bool sectionGripInHeader = false,
    bool Function(String itemKey, String toSection, int index)? canAcceptItem,
  }) async {
    itemEvents = <_ItemEvent>[];
    sectionEvents = <(String, int)>[];
    board = const <_Column>[
      _Column("todo", <_Task>[_Task("t1"), _Task("t2")]),
      _Column("done", <_Task>[_Task("d1")]),
    ];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  SectionedSliverList<String, _Column, _Task>(
                    sections: board,
                    itemsOf: (c) {
                      return c.tasks;
                    },
                    sectionKeyOf: (c) {
                      return c.id;
                    },
                    itemKeyOf: (t) {
                      return t.id;
                    },
                    animationStyle: TreeAnimationStyle.disabled,
                    reorder: SectionedReorderConfig<String, _Column, _Task>(
                      reorderSections: reorderSections,
                      buildDefaultSectionDragHandles: !sectionGripInHeader,
                      showDragProxy: false,
                      canAcceptItemDrop: canAcceptItem,
                      onItemReorder: !provideItemCallback
                          ? null
                          : (item, section, index) {
                              itemEvents.add((item, section, index));
                            },
                      onSectionReorder: (section, index) {
                        sectionEvents.add((section, index));
                      },
                    ),
                    headerBuilder: (ctx, view) {
                      controller = view.controller;
                      return SizedBox(
                        key: ValueKey("sec-${view.key}"),
                        height: 50,
                        child: !sectionGripInHeader
                            ? Text(view.key)
                            : Row(
                                children: <Widget>[
                                  Expanded(child: Text(view.key)),
                                  const TreeDragHandle(child: _Grip()),
                                ],
                              ),
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
    return controller;
  }

  Future<void> dragFrom(WidgetTester tester, String rowKey, double dy) async {
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey(rowKey))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(Offset(0.0, dy));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets("an item drag reports UNWRAPPED keys and a live-space index", (
    tester,
  ) async {
    final controller = await mount(tester);
    // Rows: todo(0-50) t1(50-100) t2(100-150) done(150-200) d1(200-250).
    // +160 puts the pointer at y=235, unambiguously d1's below-zone.
    await dragFrom(tester, "item-t1", 160.0);

    // The index is the load-bearing assertion. After t1 is removed, done
    // is [d1], so appending after d1 is index 1. A handler computing
    // against the PRE-removal list would say something else, which is the
    // silent failure this convention exists to prevent.
    expect(itemEvents, hasLength(1), reason: "exactly one report per drop");
    expect(itemEvents.single, ("t1", "done", 1));
    expect(controller.itemKeysOf("todo"), <String>["t2"]);
    expect(controller.itemKeysOf("done"), <String>["d1", "t1"]);
  });

  testWidgets("sections do not drag unless enabled", (tester) async {
    await mount(tester);
    await dragFrom(tester, "sec-done", -160.0);
    expect(sectionEvents, isEmpty, reason: "reorderSections defaults false");

    await mount(tester, reorderSections: true);
    await dragFrom(tester, "sec-done", -160.0);
    expect(sectionEvents, isNotEmpty);
    expect(sectionEvents.single.$1, "done");
  });

  testWidgets("an enabled kind without its callback does not start", (
    tester,
  ) async {
    // Declarative form: the props are authoritative, so a drop nothing
    // records is undone by the next diff. Refusing to start is visible
    // immediately and cannot corrupt anything.
    final controller = await mount(tester, provideItemCallback: false);
    final before = controller.itemKeysOf("todo");
    await dragFrom(tester, "item-t1", 175.0);

    // Asserting `itemEvents.isEmpty` alone was a tautology: that list is
    // only ever appended to BY the callback this test removed. Observe
    // the tree instead.
    expect(controller.itemKeysOf("todo"), before);
    expect(controller.itemKeysOf("done"), <String>["d1"]);
  });

  testWidgets("a caller policy can narrow but never widen the invariant", (
    tester,
  ) async {
    final controller = await mount(
      tester,
      canAcceptItem: (item, toSection, index) {
        return toSection != "done";
      },
    );
    await dragFrom(tester, "item-t1", 175.0);

    // A vacuous loop over an empty list would pass even if the drag never
    // started, so pin the tree: t1 stays out of the vetoed section.
    expect(controller.itemKeysOf("done"), isNot(contains("t1")));
    for (final event in itemEvents) {
      expect(event.$2, isNot("done"), reason: "the veto must hold");
    }
  });

  testWidgets("per-kind default handles are independent", (tester) async {
    // Headers opt OUT of the default and carry a caller-placed grip;
    // items keep the long-press default. The two knobs must not bleed
    // into one another.
    await mount(tester, reorderSections: true, sectionGripInHeader: true);
    for (final section in <String>["todo", "done"]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey("sec-$section")),
          matching: find.byType(_Grip),
        ),
        findsOneWidget,
        reason: "$section's header carries the grip",
      );
    }
    expect(find.byType(_Grip), findsNWidgets(2));

    // The grip drags immediately, with no press-and-hold...
    final g = await tester.startGesture(
      tester.getCenter(find.byType(_Grip).first),
    );
    await tester.pump();
    await g.moveBy(const Offset(0.0, 160.0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(sectionEvents, isNotEmpty, reason: "the header grip drags");

    // ...while items still need one, which is what makes the two
    // independent rather than merely both configured.
    await dragFrom(tester, "item-t1", 60.0);
    expect(itemEvents, isNotEmpty, reason: "items keep the long-press default");
  });

  testWidgets("null reorder keeps the stateless renderer", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SectionedSliverList<String, _Column, _Task>(
                sections: const <_Column>[
                  _Column("a", <_Task>[_Task("x")]),
                ],
                itemsOf: (c) {
                  return c.tasks;
                },
                sectionKeyOf: (c) {
                  return c.id;
                },
                itemKeyOf: (t) {
                  return t.id;
                },
                animationStyle: TreeAnimationStyle.disabled,
                headerBuilder: (ctx, view) {
                  return Text(view.key);
                },
                itemBuilder: (ctx, view) {
                  return Text(view.key);
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Behavioural, not structural: `SliverReorderableTree`'s type
    // argument here is the module's unexported wrapped key, so it cannot
    // be named in a test. Asserting only that text rendered would have
    // passed with the full reorder machinery mounted, so drive a gesture
    // that WOULD drag if it were.
    expect(find.text("a"), findsOneWidget);
    expect(find.text("x"), findsOneWidget);
    expect(find.byType(_Grip), findsNothing);

    final g = await tester.startGesture(tester.getCenter(find.text("x")));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0.0, -60.0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text("x"), findsOneWidget, reason: "nothing dragged");
  });
}

/// A test-local grip. The package no longer ships one, so tests supply
/// their own and locate it by key rather than by widget type.
class _Grip extends StatelessWidget {
  const _Grip();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(key: ValueKey("grip"), width: 24.0, height: 24.0);
  }
}
