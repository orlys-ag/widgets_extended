/// A refused row's grip must be INERT, not merely disarmed-looking.
///
/// A caller-placed handle keeps rendering when `canReorder` refuses the
/// row, so a full-size grip still sits under the finger. If it claimed
/// gestures anyway, a drag starting on a locked row's grip would be
/// swallowed: the recognizer wins the arena against the scrollable,
/// `startDrag` declines on policy, and the list simply refuses to scroll
/// under the user's finger with nothing to show for it.
///
/// The control leg is the other half, and it is what pins the gesture
/// ARENA outcome across the recognizer change from
/// `VerticalDragGestureRecognizer` to
/// `ImmediateMultiDragGestureRecognizer`: an ARMED grip must still beat
/// the enclosing `Scrollable`.
///
/// Asserted through SCROLLING, deliberately. Tests that assert "no reorder
/// happened" prove nothing here: `TreeReorderController` refuses a
/// policy-blocked key at `startDrag` and again at `_canCommit`, so the
/// tree is unchanged no matter what the widget layer does. Scroll position
/// is the one observable that distinguishes an inert grip from a greedy
/// one.
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

Future<ScrollController> _mount(WidgetTester tester) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
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
                  return n.children;
                },
                animationStyle: TreeAnimationStyle.disabled,
                reorder: TreeReorderConfig<String>(
                  buildDefaultDragHandles: false,
                  showDragProxy: false,
                  canReorder: (key) {
                    return key != "n0";
                  },
                  onReorder: (key, newParent, index) {},
                ),
                itemBuilder: (context, view) {
                  return SizedBox(
                    key: ValueKey("row-${view.key}"),
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
    ),
  );
  await tester.pumpAndSettle();
  return scroll;
}

/// The grip of [rowKey], armed or not.
Finder _grip(String rowKey) {
  return find.descendant(
    of: find.byKey(ValueKey("row-$rowKey")),
    matching: find.byType(_Grip),
  );
}

void main() {
  testWidgets("a refused row's grip lets the list scroll through it", (
    tester,
  ) async {
    final scroll = await _mount(tester);

    // Setup sanity: the cell really is there to be dragged from, which is
    // the whole reason it could swallow the gesture.
    expect(_grip("n0"), findsOneWidget);
    expect(scroll.position.pixels, 0.0);

    await tester.drag(_grip("n0"), const Offset(0.0, -200.0));
    await tester.pumpAndSettle();

    expect(
      scroll.position.pixels,
      greaterThan(0.0),
      reason: "a refused grip must not claim the gesture from the scrollable",
    );
  });

  testWidgets("an allowed row's grip still takes the gesture from the list", (
    tester,
  ) async {
    // The control that makes the test above meaningful: the very same
    // gesture on a droppable grip must be captured, not scroll the view.
    final scroll = await _mount(tester);

    final gesture = await tester.startGesture(tester.getCenter(_grip("n1")));
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, -200.0));
    await tester.pump();

    expect(
      scroll.position.pixels,
      0.0,
      reason: "the drag belongs to the row, so the list must not scroll",
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}

/// A test-local grip. The package no longer ships one, so tests supply
/// their own.
///
/// Deliberately OPAQUE (a `ColoredBox`, not a bare `SizedBox`). A
/// disarmed [TreeDragHandle] defers hit-testing to its child, so a
/// transparent grip would not be hit at all and the refused-row test
/// would pass vacuously: the list would scroll because nothing was under
/// the finger, not because the handle declined the gesture.
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
