/// `buildDefaultDragHandles: false` end to end.
///
/// Turning the package's default handle off hands the affordance to the
/// item builder, and this pins that each of the three shapes a caller can
/// write actually reaches the controller: an immediate grip, a delayed
/// whole-row handle, and no handle at all.
///
/// The third case records a sharp edge rather than a bug. Writing no
/// handle produces a row that cannot be lifted by a finger, and an assert
/// against it was written and then withdrawn: the configuration is
/// LEGITIMATE. The wrapper still earns its place there by hiding the
/// dragged row, keeping it a drop target and exposing its reorder
/// semantics actions, which is exactly the surface a keyboard or
/// screen-reader reorder needs.
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

Future<List<(String, String?, int)>> _mount(
  WidgetTester tester, {
  required Widget Function(Widget row) place,
  void Function(TreeReorderController<String> controller)? onControllerCreated,
}) async {
  final events = <(String, String?, int)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SyncedSliverTree<String, _Node>.hierarchy(
              roots: const <_Node>[_Node("a"), _Node("b"), _Node("c")],
              keyOf: (n) {
                return n.id;
              },
              childrenOf: (n) {
                return n.children;
              },
              animationStyle: TreeAnimationStyle.disabled,
              reorder: TreeReorderConfig<String>(
                buildDefaultDragHandles: false,
                showDragProxy: false,
                onReorder: (key, newParent, index) {
                  events.add((key, newParent, index));
                },
                onControllerCreated: onControllerCreated,
              ),
              itemBuilder: (context, view) {
                return place(
                  SizedBox(
                    key: ValueKey("row-${view.key}"),
                    height: 50,
                    child: Text(view.key),
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
  return events;
}

void main() {
  testWidgets("a caller-placed grip commits a drag", (tester) async {
    final events = await _mount(
      tester,
      place: (row) {
        return Row(
          children: <Widget>[
            Expanded(child: row),
            const TreeDragHandle(child: _Grip()),
          ],
        );
      },
    );

    // Setup sanity: the caller's grip really is in the tree, so the
    // gesture below starts where the test claims it does.
    expect(find.byType(_Grip), findsNWidgets(3));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_Grip).first),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 120.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(events, isNotEmpty, reason: "the caller's grip starts a real drag");
    expect(events.single.$1, "a");
  });

  testWidgets("a caller-placed delayed handle commits a long-press drag", (
    tester,
  ) async {
    final events = await _mount(
      tester,
      place: (row) {
        return TreeDelayedDragHandle(child: row);
      },
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-a"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 120.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(events, isNotEmpty);
    expect(events.single.$1, "a");
  });

  testWidgets("no handle at all ignores touch but still reorders", (
    tester,
  ) async {
    late TreeReorderController<String> reorder;
    final events = await _mount(
      tester,
      place: (row) {
        // No handle anywhere: no pointer surface, everything else the
        // wrapper gives intact.
        return row;
      },
      onControllerCreated: (c) {
        reorder = c;
      },
    );

    // A long press and drag, the gesture the OTHER two tests commit with,
    // must do nothing at all here.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-a"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 120.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      events,
      isEmpty,
      reason: "no handle was placed, so no gesture was installed",
    );

    // The same row is nevertheless fully reorderable through the
    // controller, which is what makes this configuration worth having
    // rather than merely tolerable: it is the surface a keyboard or
    // screen-reader driven reorder uses.
    reorder.moveDown("a");
    await tester.pumpAndSettle();

    expect(events, <(String, String?, int)>[("a", null, 1)]);
  });
}
