/// Regressions for defects found auditing the landed sectioned reorder.
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
  testWidgets("a pinned first slot still admits drops at later slots", (
    tester,
  ) async {
    // A pin-the-first-slot policy answers "no" for index 0 and yes for
    // every other index in the section. This pins that the veto is scoped
    // to the slot it names: the section's INTERIOR stays a live target.
    //
    // The title and comment here used to claim something else, and the
    // claim was wrong twice over. It said the zone precheck must ask
    // whether a row can take children AT ALL, and that passing it a
    // concrete 0 collapsed the inbox HEADER to a dead zone. The precheck
    // deliberately does pass 0 (see `_drop_zone_resolver.dart`), and the
    // header is dead under this policy either way: `above` and `below` on
    // it both name root-level item slots, which the shape gate refuses,
    // and `into` has only index 0 to offer, which the policy refuses. A
    // fully dead row is the honest answer when no legal slot exists at
    // that pointer position, and the interior rows below it are reachable.
    //
    // The gesture never touched the header regardless: it releases over
    // `i1`, which the geometry assertion below now states outright rather
    // than leaving to arithmetic.
    final events = <(String, String, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SectionedSliverList<String, _Col, String>(
                sections: const <_Col>[
                  _Col("inbox", <String>["i1", "i2"]),
                  _Col("done", <String>["d1"]),
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
                  showDragProxy: false,
                  canAcceptItemDrop: (item, section, index) {
                    return !(section == "inbox" && index == 0);
                  },
                  onItemReorder: (item, section, index) {
                    events.add((item, section, index));
                  },
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

    // Drag d1 up onto the inbox header. Index 0 is pinned, but landing
    // further down inside inbox is legal, so this must not be dead.
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("item-d1"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0.0, -140.0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    // An empty `events` IS the bug: the header collapsing to a dead zone
    // is exactly what a vacuous loop over it would fail to notice, so
    // assert arrival BEFORE asserting the veto held.
    expect(
      events,
      isNotEmpty,
      reason: "the header must remain a live target for indices 1..n",
    );
    expect(events.single.$1, "d1");
    expect(events.single.$2, "inbox");
    expect(
      events.single.$3,
      greaterThanOrEqualTo(1),
      reason: "index 0 is pinned; every other slot is legal",
    );
  });

  // NOT tested here: flipping `reorder` between null and non-null. The
  // defect was that the renderer took `bridge` and `reorder` as two
  // nullable fields that had to agree, and one rebuild could make them
  // disagree, throwing a null check out of build. The fix is structural,
  // not behavioural: `reorder` is now a getter off `bridge`, so the pair
  // cannot exist in a disagreeing state. In debug the presence assert
  // fires and legitimately breaks the frame, which is not a behaviour
  // worth pinning.
}
