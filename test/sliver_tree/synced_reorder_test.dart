/// The declarative surface: configuring reorder IS enabling it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Node {
  const _Node(this.id);
  final String id;
  List<_Node> get children {
    return const <_Node>[];
  }
}

Future<List<(String, String?, int)>> _mount(
  WidgetTester tester, {
  required List<_Node> roots,
  bool callerPlacedGrip = false,
  bool Function(String key)? canReorder,
  bool enabled = true,
}) async {
  final events = <(String, String?, int)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SyncedSliverTree<String, _Node>.hierarchy(
              roots: roots,
              keyOf: (n) {
                return n.id;
              },
              childrenOf: (n) {
                return n.children;
              },
              animationStyle: TreeAnimationStyle.disabled,
              reorder: !enabled
                  ? null
                  : TreeReorderConfig<String>(
                      buildDefaultDragHandles: !callerPlacedGrip,
                      canReorder: canReorder,
                      showDragProxy: false,
                      onReorder: (key, newParent, index) {
                        events.add((key, newParent, index));
                      },
                    ),
              // No handle placed by the builder in the default case:
              // that is the point.
              itemBuilder: (context, view) {
                final row = SizedBox(
                  key: ValueKey("row-${view.key}"),
                  height: 50,
                  child: Text(view.item.id),
                );
                if (!callerPlacedGrip) {
                  return row;
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: row),
                    const TreeDragHandle(child: _Grip()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return events;
}

void main() {
  testWidgets("rows drag with no itemBuilder change at all", (tester) async {
    final events = await _mount(
      tester,
      roots: const <_Node>[_Node("a"), _Node("b"), _Node("c")],
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-a"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 120.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(events, isNotEmpty, reason: "the drop must be reported");
    expect(events.single.$1, "a");
  });

  testWidgets("null reorder mounts no reorder machinery", (tester) async {
    await _mount(
      tester,
      roots: const <_Node>[_Node("a"), _Node("b")],
      enabled: false,
    );
    // Asserted on the exported type, not the private renderer:
    // SliverReorderableTree builds a SliverTree internally, so finding
    // SliverTree would match either way.
    expect(find.byType(SliverReorderableTree<String, _Node>), findsNothing);
  });

  testWidgets("non-null reorder mounts it", (tester) async {
    await _mount(tester, roots: const <_Node>[_Node("a"), _Node("b")]);
    expect(find.byType(SliverReorderableTree<String, _Node>), findsOneWidget);
  });

  testWidgets("a caller-placed grip drags immediately, with no long press", (
    tester,
  ) async {
    final events = await _mount(
      tester,
      roots: const <_Node>[_Node("a"), _Node("b"), _Node("c")],
      callerPlacedGrip: true,
    );
    expect(find.byType(_Grip), findsNWidgets(3));

    final handle = find.descendant(
      of: find.ancestor(
        of: find.byKey(const ValueKey("row-a")),
        matching: find.byType(Row),
      ),
      matching: find.byType(_Grip),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle.first));
    await gesture.moveBy(const Offset(0.0, 120.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(events, isNotEmpty);
  });

  testWidgets("the default installs no grip of its own", (tester) async {
    await _mount(tester, roots: const <_Node>[_Node("a"), _Node("b")]);
    expect(find.byType(_Grip), findsNothing);
  });

  testWidgets("canReorder false leaves the row inert", (tester) async {
    final events = await _mount(
      tester,
      roots: const <_Node>[_Node("a"), _Node("b")],
      callerPlacedGrip: true,
      canReorder: (key) {
        return key != "a";
      },
    );
    // Both grips still RENDER: the package no longer decides what a
    // refused row looks like, only that its handle is disarmed. Hiding it
    // is the caller's call, through `TreeRowDragScope.canDrag`.
    //
    // The drag legs below are a weaker check than they look, because
    // `TreeReorderController` refuses a policy-blocked key at `startDrag`
    // and again at `_canCommit`, so an empty `events` is guaranteed by
    // the controller whatever the widget does. Inertness of the disarmed
    // handle is proven properly, through scroll pass-through, in
    // `refused_gutter_is_inert_test.dart`.
    expect(find.byType(_Grip), findsNWidgets(2));

    final grips = find.byType(_Grip);
    final refusedGrip = tester.getCenter(grips.at(0));
    final gesture = await tester.startGesture(refusedGrip);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 90.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      events,
      isEmpty,
      reason: "the refused row's grip must not start a drag",
    );

    // Sanity: the same gesture on the ALLOWED row does move it, so the
    // emptiness above is a refusal and not an inert test fixture.
    final gesture2 = await tester.startGesture(tester.getCenter(grips.at(1)));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture2.moveBy(const Offset(0.0, -60.0));
    await tester.pump();
    await gesture2.up();
    await tester.pumpAndSettle();
    expect(events, isNotEmpty);
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
