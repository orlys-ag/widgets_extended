/// End-to-end for the declarative tree: a real pointer drag in a mounted
/// `SyncedSliverTree`, asserting the exact final structure AND the exact
/// reported slot.
///
/// The index is the load-bearing part. It is live-space and names a
/// position in the FINAL child list, so a handler computing against the
/// pre-removal list lands same-parent downward moves one slot off, and
/// cross-parent moves look fine, which is how that bug ships green.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  late List<String> data;
  late TreeController<String, String> tree;
  late List<(String, String?, int)> events;

  Future<void> mount(
    WidgetTester tester,
    List<String> initial, {
    bool record = true,
    bool Function({required String movingKey, String? newParent, int? index})?
    canAcceptDrop,
    bool Function(String key)? canReorder,
    bool defaultHandles = true,
  }) async {
    data = initial;
    events = <(String, String?, int)>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
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
                      tree = c;
                    },
                    reorder: TreeReorderConfig<String>(
                      showDragProxy: false,
                      buildDefaultDragHandles: defaultHandles,
                      canReorder: canReorder,
                      canAcceptDrop: canAcceptDrop,
                      onReorder: (key, parent, index) {
                        events.add((key, parent, index));
                        if (!record) {
                          return;
                        }
                        setState(() {
                          final next = List<String>.of(data)..remove(key);
                          next.insert(index.clamp(0, next.length), key);
                          data = next;
                        });
                      },
                    ),
                    itemBuilder: (context, view) {
                      return SizedBox(
                        key: ValueKey("row-${view.key}"),
                        height: 50,
                        child: Text(view.key),
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

  Future<void> drag(WidgetTester tester, String row, double dy) async {
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey("row-$row"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(Offset(0.0, dy / 4));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets("dragging the first row to the end reports the FINAL index", (
    tester,
  ) async {
    await mount(tester, <String>["a", "b", "c"]);
    // Rows a(0-50) b(50-100) c(100-150). From a's centre (25) down 110
    // lands at 135, c's lower third.
    await drag(tester, "a", 110.0);

    expect(tree.liveRootKeys, <String>["b", "c", "a"]);
    // After removing a, the list is [b, c], so the end is index 2.
    expect(events.single, ("a", null, 2));
    expect(data, <String>[
      "b",
      "c",
      "a",
    ], reason: "the app's own model agrees, so the sync is a no-op");
  });

  testWidgets("a config-level canAcceptDrop veto is honoured", (tester) async {
    // Closes the config -> forwarder -> controller plumbing, which no
    // test exercised: the policy was only ever tested on the resolver.
    await mount(
      tester,
      <String>["a", "b", "c"],
      canAcceptDrop: ({required movingKey, newParent, index}) {
        return index == null || index < 2;
      },
    );
    await drag(tester, "a", 110.0);

    for (final e in events) {
      expect(e.$3, lessThan(2), reason: "the vetoed slot must be refused");
    }
    expect(tree.liveRootKeys.length, 3);
  });

  testWidgets("a config-level canReorder refusal blocks the drag entirely", (
    tester,
  ) async {
    await mount(
      tester,
      <String>["a", "b", "c"],
      canReorder: (key) {
        return key != "a";
      },
    );
    await drag(tester, "a", 110.0);

    expect(events, isEmpty);
    expect(tree.liveRootKeys, <String>["a", "b", "c"]);
  });

  testWidgets("buildDefaultDragHandles: false installs no gesture", (
    tester,
  ) async {
    // The escape hatch: the package must install NO handle, and a row
    // whose builder places none must not drag. The row is still wrapped,
    // which is what keeps it a drop target and keeps its semantics
    // actions; it simply has no drag surface.
    await mount(tester, <String>["a", "b", "c"], defaultHandles: false);
    await drag(tester, "a", 110.0);

    expect(events, isEmpty, reason: "no handle was placed anywhere");
    expect(tree.liveRootKeys, <String>["a", "b", "c"]);
  });

  testWidgets("a cancelled drag leaves the structure bit-identical", (
    tester,
  ) async {
    await mount(tester, <String>["a", "b", "c"]);
    final before = tree.liveRootKeys;
    final generation = tree.structureGeneration;

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-a"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0.0, 110.0));
    await tester.pump();
    await g.cancel();
    await tester.pumpAndSettle();

    expect(tree.liveRootKeys, before);
    expect(tree.structureGeneration, generation);
    expect(events, isEmpty);
  });

  testWidgets("dragging the only row is a no-op", (tester) async {
    await mount(tester, <String>["solo"]);
    await drag(tester, "solo", 40.0);
    expect(events, isEmpty);
    expect(tree.liveRootKeys, <String>["solo"]);
  });

  testWidgets("unmounting mid-drag does not throw or leak", (tester) async {
    await mount(tester, <String>["a", "b", "c"]);
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-a"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0.0, 60.0));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await g.up();
    await tester.pumpAndSettle();
    // A leaked ticker or a teardown that reached a disposed controller
    // would surface here.
    expect(tester.takeException(), isNull);
  });
}
