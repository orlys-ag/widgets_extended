/// Second audit pass: the gestures a row must STILL get once a handle is
/// wrapped around it.
///
/// The default `buildDefaultDragHandles` puts a
/// `DelayedMultiDragGestureRecognizer` in the arena on every pointer-down
/// anywhere on the row, where the old code put a
/// `LongPressGestureRecognizer` there through a `GestureDetector`. The
/// two are meant to be equivalent for everything that is NOT a drag, and
/// that equivalence is exactly the kind of thing a recognizer swap
/// breaks quietly: a list that stops scrolling under a finger, or a row
/// whose `onTap` never fires, reads as a broken app rather than as a
/// reorder bug.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Node {
  const _Node(this.id);
  final String id;
}

Future<ScrollController> _mount(
  WidgetTester tester, {
  required List<String> taps,
  required bool defaultHandles,
}) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400.0,
          child: CustomScrollView(
            controller: scroll,
            slivers: <Widget>[
              SyncedSliverTree<String, _Node>.hierarchy(
                roots: List<_Node>.generate(40, (i) {
                  return _Node("n$i");
                }),
                keyOf: (n) {
                  return n.id;
                },
                childrenOf: (n) {
                  return const <_Node>[];
                },
                animationStyle: TreeAnimationStyle.disabled,
                reorder: TreeReorderConfig<String>(
                  buildDefaultDragHandles: defaultHandles,
                  showDragProxy: false,
                  onReorder: (key, newParent, index) {},
                ),
                itemBuilder: (context, view) {
                  final row = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      taps.add(view.key);
                    },
                    child: SizedBox(
                      key: ValueKey("row-${view.key}"),
                      height: 50.0,
                      child: Text(view.key),
                    ),
                  );
                  if (defaultHandles) {
                    return row;
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: row),
                      TreeDragHandle(
                        child: SizedBox(
                          key: ValueKey("grip-${view.key}"),
                          width: 40.0,
                          height: 50.0,
                          child: const ColoredBox(color: Color(0xFF000000)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scroll;
}

void main() {
  testWidgets("a tap on a row with the default handle still reaches onTap", (
    tester,
  ) async {
    final taps = <String>[];
    await _mount(tester, taps: taps, defaultHandles: true);

    await tester.tap(find.byKey(const ValueKey("row-n1")));
    await tester.pumpAndSettle();

    expect(
      taps,
      ["n1"],
      reason:
          "a delayed multi-drag rejects on an up before its timeout, so "
          "the app's own tap must still win the arena",
    );
  });

  testWidgets("a scroll drag on a row with the default handle still scrolls", (
    tester,
  ) async {
    final taps = <String>[];
    final scroll = await _mount(tester, taps: taps, defaultHandles: true);

    // Setup sanity: there is somewhere to scroll to.
    expect(scroll.position.maxScrollExtent, greaterThan(0.0));
    expect(scroll.position.pixels, 0.0);

    await tester.drag(
      find.byKey(const ValueKey("row-n1")),
      const Offset(0.0, -200.0),
    );
    await tester.pumpAndSettle();

    expect(
      scroll.position.pixels,
      greaterThan(0.0),
      reason:
          "the drag begins before the long-press timeout, so the "
          "scrollable must keep the gesture",
    );
    expect(taps, isEmpty, reason: "a drag is not a tap");
  });

  testWidgets("a quick tap on an ARMED grip does not lift the row", (
    tester,
  ) async {
    // The immediate recognizer accepts on DISTANCE, so a press and
    // release with no movement must resolve as a rejection and leave the
    // tree alone rather than starting and abandoning a session.
    final taps = <String>[];
    await _mount(tester, taps: taps, defaultHandles: false);

    // Also pins that the scope really is published where a caller-placed
    // handle can find it.
    final scopeContext = tester.element(find.byKey(const ValueKey("grip-n1")));
    expect(
      TreeRowDragScope.maybeOf(scopeContext),
      isNotNull,
      reason: "setup: a caller-placed grip really does see a row scope",
    );

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("grip-n1"))),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await g.up();
    await tester.pumpAndSettle();

    expect(taps, isEmpty, reason: "the grip is not the app's tap target");
    // Nothing was dragged, and nothing threw.
    expect(tester.takeException(), isNull);
  });

  testWidgets("a scroll drag starting on a DISARMED grip still scrolls", (
    tester,
  ) async {
    // The migrated `refused_gutter_is_inert_test` covers a policy
    // refusal; this covers the other way a grip is disarmed, and pins
    // that an inert handle does not become a dead zone in the list.
    final taps = <String>[];
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400.0,
            child: CustomScrollView(
              controller: scroll,
              slivers: <Widget>[
                SyncedSliverTree<String, _Node>.hierarchy(
                  roots: List<_Node>.generate(40, (i) {
                    return _Node("n$i");
                  }),
                  keyOf: (n) {
                    return n.id;
                  },
                  childrenOf: (n) {
                    return const <_Node>[];
                  },
                  animationStyle: TreeAnimationStyle.disabled,
                  reorder: TreeReorderConfig<String>(
                    buildDefaultDragHandles: false,
                    showDragProxy: false,
                    onReorder: (key, newParent, index) {},
                  ),
                  itemBuilder: (context, view) {
                    return SizedBox(
                      key: ValueKey("row-${view.key}"),
                      height: 50.0,
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(view.key)),
                          TreeDragHandle(
                            // Locally disarmed by the caller.
                            enabled: false,
                            child: SizedBox(
                              key: ValueKey("grip-${view.key}"),
                              width: 40.0,
                              height: 50.0,
                              child: const ColoredBox(color: Color(0xFF000000)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(scroll.position.pixels, 0.0);
    await tester.drag(
      find.byKey(const ValueKey("grip-n1")),
      const Offset(0.0, -200.0),
    );
    await tester.pumpAndSettle();

    expect(
      scroll.position.pixels,
      greaterThan(0.0),
      reason: "an enabled:false grip must not claim the scroll gesture",
    );
    expect(taps, isEmpty);
  });

  testWidgets("kLongPressTimeout is the boundary, both sides", (tester) async {
    // Guards against the default silently becoming an IMMEDIATE drag,
    // which would stop the list scrolling.
    final taps = <String>[];
    final scroll = await _mount(tester, taps: taps, defaultHandles: true);

    final early = await tester.startGesture(const Offset(200.0, 25.0));
    await tester.pump(kLongPressTimeout - const Duration(milliseconds: 20));
    // TWO moves, deliberately. `Scrollable` uses
    // `DragStartBehavior.start`, which DISCARDS the slop distance that
    // won the arena, so a single large move both wins and is swallowed
    // and the list would not move at all. `tester.drag` splits the same
    // way for the same reason.
    await early.moveBy(const Offset(0.0, -30.0));
    await tester.pump();
    await early.moveBy(const Offset(0.0, -120.0));
    await tester.pump();
    await early.up();
    await tester.pumpAndSettle();

    expect(
      scroll.position.pixels,
      greaterThan(0.0),
      reason: "before the timeout the gesture belongs to the scrollable",
    );
  });
}
