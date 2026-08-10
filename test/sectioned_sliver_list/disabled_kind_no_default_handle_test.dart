/// A kind whose reordering is switched OFF gets no drag surface, and no
/// kind pays layout for one.
///
/// Successor to the 2026-08-04 disabled-kind batch. Those three tests
/// asserted that a disabled kind did not lose width to a reserved grip
/// gutter, and that a disabled kind's `view.draggable` returned its child
/// untouched. Neither statement can be made any more: there is no package
/// `Row`, no `Visibility(maintainSize:)` cell and no `draggable`. The
/// package composes NOTHING around the row a builder returns.
///
/// What survives is the question underneath, restated for the D2
/// always-wrap decision: every row is wrapped, so the thing that must be
/// gated per kind is the DEFAULT HANDLE, not the wrapper. A disabled kind
/// must get no gesture, keep its full width, and still be a drop target.
///
/// The declarative form makes the disabled case easy to hit without
/// touching a flag: a kind is enabled only when its flag is set AND its
/// callback exists, so `reorderItems` defaulting to true is NOT enough.
/// Forget `onItemReorder` and every item row silently stops dragging.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Col {
  const _Col(this.id, this.tasks);
  final String id;
  final List<String> tasks;
}

Future<void> _mount(
  WidgetTester tester, {
  required SectionedReorderConfig<String, _Col, String> reorder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SectionedSliverList<String, _Col, String>(
              sections: const <_Col>[
                _Col("a", <String>["a1", "a2"]),
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
              reorder: reorder,
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
}

/// Long-presses [rowKey] and drags it [dy], the gesture the default
/// handle installs.
Future<void> _longPressDrag(
  WidgetTester tester,
  String rowKey,
  double dy,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey(rowKey))),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveBy(Offset(0.0, dy));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("a disabled kind gets no default handle, an enabled one does", (
    tester,
  ) async {
    final itemMoves = <String>[];
    final sectionMoves = <String>[];
    await _mount(
      tester,
      reorder: SectionedReorderConfig<String, _Col, String>(
        // Items on, sections off. The default shape.
        reorderSections: false,
        showDragProxy: false,
        onItemReorder: (i, s, idx) {
          itemMoves.add(i);
        },
        onSectionReorder: (s, idx) {
          sectionMoves.add(s);
        },
      ),
    );

    // Setup sanity: the ENABLED kind really does drag, so an empty
    // `sectionMoves` below is a refusal and not an inert fixture.
    await _longPressDrag(tester, "item-a1", 60.0);
    expect(
      itemMoves,
      isNotEmpty,
      reason: "items are enabled, so the default handle is installed",
    );

    await _longPressDrag(tester, "sec-a", 160.0);
    expect(
      sectionMoves,
      isEmpty,
      reason: "a disabled kind must get no drag surface at all",
    );
  });

  testWidgets("a flag-on-but-callback-missing kind gets no default handle", (
    tester,
  ) async {
    // The declarative form's own rule: flag AND callback. `reorderItems`
    // defaults to true, so this is reachable purely by omission.
    var reordered = false;
    await _mount(
      tester,
      reorder: SectionedReorderConfig<String, _Col, String>(
        showDragProxy: false,
        onSectionReorder: (s, idx) {
          reordered = true;
        },
      ),
    );

    await _longPressDrag(tester, "item-a1", 60.0);
    expect(
      reordered,
      isFalse,
      reason: "no item callback, so items were never enabled",
    );
  });

  testWidgets("no kind reserves layout for a handle", (tester) async {
    // The layout half. The old apparatus took a grip's width out of every
    // row of a configured kind, whether or not that row could drag; the
    // package now composes nothing, so every row spans the viewport
    // regardless of which kinds are enabled.
    await _mount(
      tester,
      reorder: SectionedReorderConfig<String, _Col, String>(
        reorderSections: false,
        showDragProxy: false,
        onItemReorder: (i, s, idx) {},
      ),
    );

    final full = tester.getSize(find.byType(Scaffold)).width;
    for (final key in const ["sec-a", "sec-b", "item-a1", "item-a2"]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).width,
        full,
        reason: "$key must span the viewport",
      );
    }
  });

  testWidgets("a disabled kind's rows are still drop targets", (tester) async {
    // Always-wrap's payoff, and the first question a reader has. Section
    // headers cannot be lifted, but an item must still be droppable ONTO
    // one, which needs the header's row to take part in targeting.
    final moves = <(String, String)>[];
    await _mount(
      tester,
      reorder: SectionedReorderConfig<String, _Col, String>(
        reorderSections: false,
        showDragProxy: false,
        onItemReorder: (item, section, index) {
          moves.add((item, section));
        },
      ),
    );

    // Rows, in order: sec-a, a1, a2, sec-b, b1. Drag a1 down past sec-b
    // and onto b1's half of section b.
    await _longPressDrag(tester, "item-a1", 175.0);

    expect(moves, isNotEmpty, reason: "the drop must be reported");
    expect(
      moves.single.$2,
      "b",
      reason: "the un-draggable header was still a live drop destination",
    );
  });
}
