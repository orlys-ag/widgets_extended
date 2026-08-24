/// Repro: flipping `canReorder` false for the row that currently owns the
/// drag leaves that drag running.
///
/// `canReorder` is NOT a widget field, so refusing the dragged row
/// rebuilds it with identical widget fields and nothing else notices.
/// Disarming the handle does not end the drag it started, because the
/// recognizer lives on the ROW's `State`, not in the handle's build
/// output: it keeps driving a drag the policy has just forbidden, and the
/// row stays at zero opacity with make-room re-targeting until the finger
/// lifts.
///
/// The build-time backstop in `_ReorderableRowState.build` is what ends
/// it, and it is load-bearing rather than belt-and-braces.
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

bool _isVisible(WidgetTester tester, String key) {
  return tester
      .widget<Visibility>(
        find
            .ancestor(
              of: find.byKey(ValueKey("row-$key")),
              matching: find.byType(Visibility),
            )
            .first,
      )
      .visible;
}

void main() {
  testWidgets("refusing the dragged row mid-drag ends its session", (
    tester,
  ) async {
    final locked = <String>{};
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return CustomScrollView(
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
                      canReorder: (key) {
                        return !locked.contains(key);
                      },
                      onReorder: (key, newParent, index) {},
                    ),
                    itemBuilder: (context, view) {
                      return SizedBox(
                        key: ValueKey("row-${view.key}"),
                        height: 50,
                        child: Row(
                          children: <Widget>[
                            Expanded(child: Text(view.item.id)),
                            const TreeDragHandle(child: _Grip()),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Take hold of "b" by its grip and get a real session running.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_Grip).at(1)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 20.0));
    await tester.pump();

    // Setup sanity: the session genuinely exists and owns THIS row, so
    // what follows exercises the claimed path rather than a no-op.
    expect(
      _isVisible(tester, "b"),
      isFalse,
      reason: "make-room hides the row that owns the drag",
    );

    // Now refuse it, with every widget field left untouched.
    setOuter(() {
      locked.add("b");
    });
    await tester.pump();
    await tester.pump();

    expect(
      _isVisible(tester, "b"),
      isTrue,
      reason: "the orphaned session must be torn down, not left running",
    );

    // The pointer is still down and now belongs to nothing. Releasing it
    // must not resurrect or re-commit anything.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_isVisible(tester, "b"), isTrue);
  });

  // Coverage, NOT a repro: verified to still pass with the build-time
  // backstop disabled. That is NOT because recognizer disposal cleans up
  // after itself, which an earlier version of this comment claimed and
  // which is false. The session is ended by the controller-side policy
  // re-check in `TreeReorderController._resolveAndNotify`, which fires on
  // the next re-resolution. Pinned because the guarantee below (an
  // interrupted drag commits nothing and leaves the tree usable) is one
  // this package makes, whichever layer happens to deliver it.
  testWidgets("a refused mid-drag row leaves the tree able to drag again", (
    tester,
  ) async {
    final locked = <String>{};
    final events = <(String, String?, int)>[];
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return CustomScrollView(
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
                      // Long-press, deliberately: this mode drops the
                      // whole detector when the policy refuses.
                      showDragProxy: false,
                      canReorder: (key) {
                        return !locked.contains(key);
                      },
                      onReorder: (key, newParent, index) {
                        events.add((key, newParent, index));
                      },
                    ),
                    itemBuilder: (context, view) {
                      return SizedBox(
                        key: ValueKey("row-${view.key}"),
                        height: 50,
                        child: Row(
                          children: <Widget>[
                            Expanded(child: Text(view.item.id)),
                            const TreeDragHandle(child: _Grip()),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-b"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0.0, 20.0));
    await tester.pump();
    expect(
      _isVisible(tester, "b"),
      isFalse,
      reason: "setup sanity: the long-press drag is genuinely running",
    );

    setOuter(() {
      locked.add("b");
    });
    await tester.pump();
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(events, isEmpty, reason: "an interrupted drag commits nothing");

    // A leaked session refuses the next `startDrag` outright (one drag at
    // a time), so a working second drag is what proves the first was
    // released rather than merely looking released.
    final gesture2 = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-c"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture2.moveBy(const Offset(0.0, -90.0));
    await tester.pump();
    await gesture2.up();
    await tester.pumpAndSettle();

    expect(events, isNotEmpty, reason: "the tree still reorders afterwards");
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
