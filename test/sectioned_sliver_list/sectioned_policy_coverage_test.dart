/// The sectioned config members with no other coverage: the per-kind
/// drag policies and the `.controlled` enablement difference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Col {
  const _Col(this.id, this.tasks);
  final String id;
  final List<String> tasks;
}

Finder _gripIn(String rowKey) {
  return find.descendant(
    of: find.byKey(ValueKey(rowKey)),
    matching: find.byType(_Grip),
  );
}

void main() {
  testWidgets("canDragItem and canDragSection refuse per kind", (tester) async {
    late SectionedListController<String, _Col, String> controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SectionedSliverList<String, _Col, String>(
                sections: const <_Col>[
                  _Col("a", <String>["pinned", "free"]),
                  _Col("b", <String>["b1"]),
                ],
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
                reorder: SectionedReorderConfig<String, _Col, String>(
                  reorderSections: true,
                  showDragProxy: false,
                  buildDefaultItemDragHandles: false,
                  buildDefaultSectionDragHandles: false,
                  canDragItem: (item) {
                    return item != "pinned";
                  },
                  canDragSection: (section) {
                    return section != "a";
                  },
                  onItemReorder: (i, s, idx) {},
                  onSectionReorder: (s, idx) {},
                ),
                headerBuilder: (ctx, view) {
                  controller = view.controller;
                  return SizedBox(
                    key: ValueKey("sec-${view.key}"),
                    height: 50,
                    child: Row(
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
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(view.key)),
                        const TreeDragHandle(child: _Grip()),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.sectionKeys(), <String>["a", "b"]);

    // Every row still RENDERS its caller-placed grip, refused or not:
    // what a refusal withholds is the arming, not the widget. Hiding a
    // disarmed grip is the caller's decision, through
    // `TreeRowDragScope.canDrag`.
    expect(_gripIn("item-pinned"), findsOneWidget);
    expect(_gripIn("item-free"), findsOneWidget);
    expect(_gripIn("sec-a"), findsOneWidget);
    expect(_gripIn("sec-b"), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey("item-pinned"))).width,
      tester.getSize(find.byKey(const ValueKey("item-free"))).width,
      reason: "a refused row must not lay out wider than a droppable one",
    );

    // And the affordance is withheld. Note the drag legs below cannot
    // fail on the widget layer alone: the controller refuses a blocked
    // key twice over, so they pin the pairing of policy to KIND, which is
    // this module's own contract. That the hidden cell is inert rather
    // than merely invisible is proven in
    // `test/sliver_tree/refused_gutter_is_inert_test.dart`.
    Future<void> dragGrip(Finder grip, double dy) async {
      final gesture = await tester.startGesture(tester.getCenter(grip));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(Offset(0.0, dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragGrip(_gripIn("item-pinned"), 60.0);
    expect(
      controller.itemKeysOf("a"),
      <String>["pinned", "free"],
      reason: "canDragItem refused, so the grip must start nothing",
    );

    await dragGrip(_gripIn("item-free"), -60.0);
    expect(
      controller.itemKeysOf("a"),
      <String>["free", "pinned"],
      reason: "the allowed grip still drags, so the refusal above is real",
    );
  });

  testWidgets("canAcceptSectionDrop narrows where a section may land", (
    tester,
  ) async {
    final events = <(String, int)>[];
    late SectionedListController<String, _Col, String> controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SectionedSliverList<String, _Col, String>(
                sections: const <_Col>[
                  _Col("a", <String>[]),
                  _Col("b", <String>[]),
                  _Col("c", <String>[]),
                ],
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
                reorder: SectionedReorderConfig<String, _Col, String>(
                  reorderSections: true,
                  showDragProxy: false,
                  canAcceptSectionDrop: (section, index) {
                    return index == 0;
                  },
                  onSectionReorder: (section, index) {
                    events.add((section, index));
                  },
                ),
                headerBuilder: (ctx, view) {
                  controller = view.controller;
                  return SizedBox(
                    key: ValueKey("sec-${view.key}"),
                    height: 50,
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(view.key)),
                        const TreeDragHandle(child: _Grip()),
                      ],
                    ),
                  );
                },
                itemBuilder: (ctx, view) {
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> dragSection(String key, double dy) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey("sec-$key"))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(Offset(0.0, dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // Rows are 50 tall: a(0-50), b(50-100), c(100-150).
    //
    // Leg 1, the PERMITTED half. Drag "c" clear to the top so the drop
    // resolves at index 0, which the policy allows. Without this leg the
    // test cannot tell "narrows" from "forbids everything": a policy
    // implementation that refused every section drop passed the earlier
    // version of this test, and the whole suite, unchanged.
    await dragSection("c", -110.0);
    expect(events, <(String, int)>[
      ("c", 0),
    ], reason: "index 0 is legal, so the drop must commit and be reported");
    expect(controller.sectionKeys(), <String>["c", "a", "b"]);

    // Leg 2, the REFUSED half. From the top, drag "c" down by one row to
    // aim at index 1, which the policy rejects. Nothing may change.
    events.clear();
    await dragSection("c", 60.0);
    expect(events, isEmpty, reason: "index 1 is vetoed, so nothing commits");
    expect(
      controller.sectionKeys(),
      <String>["c", "a", "b"],
      reason: "a vetoed drop must leave the order exactly as it was",
    );
  });

  testWidgets("controlled form enables a kind without needing its callback", (
    tester,
  ) async {
    // The documented difference from the declarative form: here the
    // controller IS the truth and nothing re-diffs, so a drop simply
    // sticks and the callbacks are informational.
    final controller = SectionedListController<String, _Col, String>(
      vsync: const TestVSync(),
      sectionKeyOf: (c) {
        return c.id;
      },
      itemKeyOf: (t) {
        return t;
      },
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addSection(
      const _Col("a", <String>[]),
      items: const <String>["t1", "t2"],
    );
    // `.controlled` never alters expansion state, so a freshly added
    // section starts collapsed and its items are not rendered.
    controller.expandSection("a", animate: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SectionedSliverList<String, _Col, String>.controlled(
                controller: controller,
                reorder: const SectionedReorderConfig<String, _Col, String>(
                  showDragProxy: false,
                  // Deliberately NO onItemReorder.
                ),
                headerBuilder: (ctx, view) {
                  return SizedBox(
                    key: ValueKey("sec-${view.key}"),
                    height: 50,
                    child: Text(view.key),
                  );
                },
                itemBuilder: (ctx, view) {
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
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.itemKeysOf("a"), <String>["t1", "t2"]);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("item-t1"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 60.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      controller.itemKeysOf("a"),
      <String>["t2", "t1"],
      reason: "the drop sticks with no callback, and nothing reverts it",
    );
  });
}

/// A test-local grip. The package no longer ships one, so tests supply
/// their own.
///
/// Deliberately OPAQUE: a disarmed [TreeDragHandle] defers hit-testing to
/// its child, so a transparent grip would not be hit at all and a
/// refusal test would pass without asking its question.
class _Grip extends StatelessWidget {
  const _Grip();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey("grip"),
      width: 24.0,
      height: 24.0,
      child: ColoredBox(color: Color(0xFF000000)),
    );
  }
}
