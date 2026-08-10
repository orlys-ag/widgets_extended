/// D2e: cross-section moves for assistive technology.
///
/// Under the two-level invariant the built-in four collapse to up/down
/// within an item's own section, so cross-section reparenting would be
/// reachable by pointer and by nothing else. WCAG 2.2 SC 2.5.7 requires a
/// non-dragging alternative for anything a drag can do.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

const CustomSemanticsAction _prev = CustomSemanticsAction(
  label: "Move to previous section",
);
const CustomSemanticsAction _next = CustomSemanticsAction(
  label: "Move to next section",
);

class _Col {
  const _Col(this.id, this.tasks);
  final String id;
  final List<String> tasks;
}

void main() {
  late List<(String, String, int)> events;

  Future<SectionedListController<String, _Col, String>> mount(
    WidgetTester tester,
    List<_Col> board, {
    bool Function(String item, String section, int index)? canAccept,
    bool collapseSecond = false,
  }) async {
    events = <(String, String, int)>[];
    late SectionedListController<String, _Col, String> captured;
    await tester.pumpWidget(
      MaterialApp(
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
                  return !(collapseSecond && key == board.last.id);
                },
                reorder: SectionedReorderConfig<String, _Col, String>(
                  showDragProxy: false,
                  canAcceptItemDrop: canAccept,
                  onItemReorder: (item, section, index) {
                    events.add((item, section, index));
                  },
                ),
                headerBuilder: (ctx, view) {
                  captured = view.controller;
                  return SizedBox(
                    key: ValueKey("sec-${view.key}"),
                    height: 50,
                    child: Text(view.key),
                  );
                },
                itemBuilder: (ctx, view) {
                  captured = view.controller;
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
    return captured;
  }

  bool has(WidgetTester tester, String key, CustomSemanticsAction a) {
    final node = tester.getSemantics(find.byKey(ValueKey(key)));
    final ids = node.getSemanticsData().customSemanticsActionIds;
    return (ids ?? const <int>[]).contains(
      CustomSemanticsAction.getIdentifier(a),
    );
  }

  void perform(WidgetTester tester, String key, CustomSemanticsAction a) {
    final node = tester.getSemantics(find.byKey(ValueKey(key)));
    // The non-deprecated routes do not expose the semantics owner that
    // holds widget-test nodes.
    // ignore: deprecated_member_use
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(a),
    );
  }

  testWidgets("an item exposes both cross-section moves in the middle", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mount(tester, const <_Col>[
      _Col("a", <String>["a1"]),
      _Col("b", <String>["b1"]),
      _Col("c", <String>["c1"]),
    ]);
    expect(has(tester, "item-b1", _prev), isTrue);
    expect(has(tester, "item-b1", _next), isTrue);
    handle.dispose();
  });

  testWidgets("boundaries omit the direction that does not exist", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mount(tester, const <_Col>[
      _Col("a", <String>["a1"]),
      _Col("b", <String>["b1"]),
    ]);
    expect(has(tester, "item-a1", _prev), isFalse);
    expect(has(tester, "item-a1", _next), isTrue);
    expect(has(tester, "item-b1", _prev), isTrue);
    expect(has(tester, "item-b1", _next), isFalse);
    handle.dispose();
  });

  testWidgets("section rows get neither", (tester) async {
    final handle = tester.ensureSemantics();
    await mount(tester, const <_Col>[
      _Col("a", <String>["a1"]),
      _Col("b", <String>["b1"]),
    ]);
    expect(has(tester, "sec-a", _prev), isFalse);
    expect(has(tester, "sec-a", _next), isFalse);
    handle.dispose();
  });

  testWidgets("moving next PREPENDS, moving previous APPENDS", (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await mount(tester, const <_Col>[
      _Col("a", <String>["a1", "a2"]),
      _Col("b", <String>["b1", "b2"]),
    ]);

    perform(tester, "item-a1", _next);
    await tester.pumpAndSettle();
    expect(
      controller.itemKeysOf("b"),
      <String>["a1", "b1", "b2"],
      reason: "next lands at the TOP of the section below",
    );
    expect(events.single, ("a1", "b", 0));

    events.clear();
    perform(tester, "item-a1", _prev);
    await tester.pumpAndSettle();
    expect(
      controller.itemKeysOf("a"),
      <String>["a2", "a1"],
      reason: "previous lands at the END of the section above",
    );
    expect(events.single, ("a1", "a", 1));
    handle.dispose();
  });

  testWidgets("a vetoed destination removes the action", (tester) async {
    final handle = tester.ensureSemantics();
    await mount(
      tester,
      const <_Col>[
        _Col("a", <String>["a1"]),
        _Col("b", <String>["b1"]),
      ],
      canAccept: (item, section, index) {
        return section != "b";
      },
    );
    expect(has(tester, "item-a1", _next), isFalse);
    handle.dispose();
  });

  testWidgets("a collapsed destination is expanded rather than refused", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = await mount(tester, const <_Col>[
      _Col("a", <String>["a1"]),
      _Col("b", <String>["b1"]),
    ], collapseSecond: true);
    expect(controller.isExpanded("b"), isFalse, reason: "setup");

    perform(tester, "item-a1", _next);
    await tester.pumpAndSettle();
    expect(controller.isExpanded("b"), isTrue);
    expect(controller.itemKeysOf("b"), <String>["a1", "b1"]);
    handle.dispose();
  });
}
