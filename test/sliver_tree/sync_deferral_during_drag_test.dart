/// D1d: a data sync must not run underneath a live drag, and a deferred
/// one must never be lost.
///
/// The trap is that the two failure modes pull in opposite directions.
/// Applying the held sync at drag end reverts the drop it was protecting,
/// because the app has not recorded the move yet. Waiting for the next
/// `didUpdateWidget` strands the data forever, because a descendant's
/// setState never triggers an ancestor's, and an ancestor rebuild with
/// `identical` inputs early-returns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Harness {
  _Harness(this.reorder, this.tree);
  final TreeReorderController<String> reorder;
  final TreeController<String, String> tree;
}

void main() {
  late _Harness harness;
  late List<String> data;
  late void Function(void Function()) rebuildWith;
  late int handlerCalls;
  late bool handlerRecords;

  Future<void> mount(WidgetTester tester, List<String> initial) async {
    data = initial;
    handlerCalls = 0;
    handlerRecords = true;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuildWith = (fn) {
            setState(fn);
          };
          return MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  SyncedSliverTree<String, String>.hierarchy(
                    roots: data,
                    keyOf: (s) {
                      return s;
                    },
                    childrenOf: (s) {
                      return const <String>[];
                    },
                    animationStyle: TreeAnimationStyle.disabled,
                    onControllerCreated: (c) {
                      harness = _Harness(harness.reorder, c);
                    },
                    reorder: TreeReorderConfig<String>(
                      showDragProxy: false,
                      onControllerCreated: (c) {
                        harness = _Harness(c, harness.tree);
                      },
                      onReorder: (key, parent, index) {
                        handlerCalls++;
                        if (handlerRecords) {
                          rebuildWith(() {
                            final next = List<String>.of(data)..remove(key);
                            next.insert(index, key);
                            data = next;
                          });
                        }
                      },
                    ),
                    itemBuilder: (context, view) {
                      return SizedBox(
                        key: ValueKey("row-${view.key}"),
                        height: 50,
                        child: Text(view.item),
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
  }

  Future<TestGesture> startDrag(WidgetTester tester, String key) async {
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey("row-$key"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return g;
  }

  setUp(() {
    harness = _Harness(
      // Placeholder; replaced by onControllerCreated during mount.
      // ignore: invalid_use_of_protected_member
      TreeReorderController<String>(
        treeController: TreeController<String, String>(
          vsync: const TestVSync(),
        ),
        vsync: const TestVSync(),
      ),
      TreeController<String, String>(vsync: const TestVSync()),
    );
  });

  testWidgets("a mid-drag rebuild does not diff underneath the session", (
    tester,
  ) async {
    await mount(tester, <String>["a", "b", "c"]);
    final gesture = await startDrag(tester, "a");
    expect(harness.reorder.isDragging, isTrue);

    final generationBefore = harness.tree.structureGeneration;
    rebuildWith(() {
      data = <String>["a", "b", "c", "d"];
    });
    await tester.pump();

    expect(harness.reorder.isDragging, isTrue, reason: "session survives");
    expect(
      harness.tree.structureGeneration,
      generationBefore,
      reason: "no structural diff may land mid-drag",
    );

    await gesture.up();
    await tester.pumpAndSettle();
    // Deferred data becomes visible once the drag is over.
    expect(harness.tree.liveRootKeys, contains("d"));
  });

  testWidgets("cancelling applies the deferred sync a frame later", (
    tester,
  ) async {
    await mount(tester, <String>["a", "b", "c"]);
    final gesture = await startDrag(tester, "a");
    rebuildWith(() {
      data = <String>["a", "b", "c", "d"];
    });
    await tester.pump();
    expect(harness.tree.liveRootKeys, isNot(contains("d")));

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(
      harness.tree.liveRootKeys,
      contains("d"),
      reason: "a cancel has no commit to conflict with",
    );
  });

  testWidgets("no deferral means the identity gate still governs", (
    tester,
  ) async {
    // The optimistic window: a drop that raced no data change must not
    // force a sync, or an async handler is reverted by the first
    // unrelated rebuild.
    await mount(tester, <String>["a", "b", "c"]);
    handlerRecords = false;

    final gesture = await startDrag(tester, "a");
    await gesture.moveBy(const Offset(0.0, 120.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(handlerCalls, 1, reason: "setup: the drop committed");
    final afterDrop = harness.tree.liveRootKeys;
    expect(afterDrop.first, isNot("a"), reason: "setup: it actually moved");

    // An ancestor rebuild passing the SAME instance.
    final generation = harness.tree.structureGeneration;
    rebuildWith(() {});
    await tester.pumpAndSettle();

    expect(
      harness.tree.structureGeneration,
      generation,
      reason: "nothing was deferred, so nothing may be forced",
    );
    expect(harness.tree.liveRootKeys, afterDrop);
  });

  testWidgets("a no-op handler still gets the deferred data applied", (
    tester,
  ) async {
    // Waiting for a didUpdateWidget that never comes would strand it.
    await mount(tester, <String>["a", "b", "c"]);
    handlerRecords = false;

    final gesture = await startDrag(tester, "a");
    rebuildWith(() {
      data = <String>["a", "b", "c", "d"];
    });
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 120.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(handlerCalls, 1);
    expect(
      harness.tree.liveRootKeys,
      contains("d"),
      reason: "the mid-drag push must never be lost",
    );
  });

  testWidgets("dragGeneration only counts installed sessions", (tester) async {
    await mount(tester, <String>["a", "b", "c"]);
    final start = harness.reorder.dragGeneration;

    final gesture = await startDrag(tester, "a");
    expect(harness.reorder.dragGeneration, start + 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      harness.reorder.dragGeneration,
      start + 1,
      reason: "ending a session consumes no generation",
    );

    harness.reorder.cancelDrag();
    expect(harness.reorder.dragGeneration, start + 1);
  });
}
