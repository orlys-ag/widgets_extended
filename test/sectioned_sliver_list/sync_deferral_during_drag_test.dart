/// A prop sync must not run underneath a live drag, and a deferred one
/// must never be lost. The sectioned mirror of
/// `test/sliver_tree/sync_deferral_during_drag_test.dart`, pinning the
/// shared `DeferredSyncGate` for the declarative `SectionedSliverList`.
///
/// The sectioned module exposes no `onControllerCreated` hook and its
/// `TreeReorderController` lives inside the reorder bridge, so unlike the
/// tree suite nothing here reads `isDragging` or `dragGeneration`.
/// Instead the `SectionedListController` is captured from the first
/// `itemBuilder` call, session liveness is proven by its observable
/// consequences (a commit reported by the handler, data held back until
/// release), and "no diff landed mid-drag" is pinned via the underlying
/// tree controller's `structureGeneration`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Sec {
  const _Sec(this.id, this.items);
  final String id;
  final List<String> items;
}

List<_Sec> _applyMove(
  List<_Sec> input,
  String item,
  String section,
  int index,
) {
  return input.map((s) {
    final items = List<String>.of(s.items)..remove(item);
    if (s.id == section) {
      items.insert(index, item);
    }
    return _Sec(s.id, items);
  }).toList();
}

void main() {
  late SectionedListController<String, _Sec, String> controller;
  late List<_Sec> data;
  late void Function(void Function()) rebuildWith;
  late int handlerCalls;
  late bool handlerRecords;

  Future<void> mount(WidgetTester tester, List<_Sec> initial) async {
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
                  SectionedSliverList<String, _Sec, String>(
                    sections: data,
                    itemsOf: (s) {
                      return s.items;
                    },
                    sectionKeyOf: (s) {
                      return s.id;
                    },
                    itemKeyOf: (item) {
                      return item;
                    },
                    animationStyle: TreeAnimationStyle.disabled,
                    reorder: SectionedReorderConfig<String, _Sec, String>(
                      showDragProxy: false,
                      onItemReorder: (item, section, index) {
                        handlerCalls++;
                        if (handlerRecords) {
                          rebuildWith(() {
                            data = _applyMove(data, item, section, index);
                          });
                        }
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
                      controller = view.controller;
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
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<TestGesture> startDrag(WidgetTester tester, String itemKey) async {
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey("item-$itemKey"))),
    );
    // Items keep the long-press default.
    await tester.pump(const Duration(milliseconds: 600));
    return g;
  }

  // Rows: s1(0-50) a(50-100) b(100-150) c(150-200) s2(200-250) d(250-300).
  const initial = <_Sec>[
    _Sec("s1", <String>["a", "b", "c"]),
    _Sec("s2", <String>["d"]),
  ];
  const pushed = <_Sec>[
    _Sec("s1", <String>["a", "b", "c"]),
    _Sec("s2", <String>["d", "x"]),
  ];

  testWidgets("a mid-drag rebuild does not diff underneath the session", (
    tester,
  ) async {
    await mount(tester, initial);
    final gesture = await startDrag(tester, "a");

    final generationBefore = controller.treeController.structureGeneration;
    rebuildWith(() {
      data = pushed;
    });
    await tester.pump();

    expect(
      controller.itemKeysOf("s2"),
      isNot(contains("x")),
      reason: "the pushed item is held while the drag is live",
    );
    expect(
      controller.treeController.structureGeneration,
      generationBefore,
      reason: "no structural diff may land mid-drag",
    );

    // From a's center (y 75), +190 lands at y 265: d's upper half, so
    // the drop commits above d in s2.
    await gesture.moveBy(const Offset(0.0, 190.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // The commit is the liveness proof: a refused start would have
    // reported nothing, making the held-diff assertions above vacuous.
    expect(handlerCalls, 1, reason: "setup: the drop committed");
    expect(
      controller.itemKeysOf("s2"),
      contains("x"),
      reason: "deferred data becomes visible once the drag is over",
    );
    expect(
      controller.itemKeysOf("s2"),
      contains("a"),
      reason: "the recorded move and the deferred push both apply",
    );
  });

  testWidgets("cancelling applies the deferred sync a frame later", (
    tester,
  ) async {
    await mount(tester, initial);
    final gesture = await startDrag(tester, "a");
    rebuildWith(() {
      data = pushed;
    });
    await tester.pump();
    expect(controller.itemKeysOf("s2"), isNot(contains("x")));

    await gesture.cancel();
    await tester.pumpAndSettle();
    // No commit, so no app rebuild consumed the bit: this pins the
    // gate's own post-frame route.
    expect(handlerCalls, 0, reason: "setup: a cancel commits nothing");
    expect(
      controller.itemKeysOf("s2"),
      contains("x"),
      reason: "a cancel has no commit to conflict with",
    );
  });

  testWidgets("a no-op handler still gets the deferred data applied", (
    tester,
  ) async {
    // Waiting for a didUpdateWidget that never comes would strand it.
    await mount(tester, initial);
    handlerRecords = false;

    final gesture = await startDrag(tester, "a");
    rebuildWith(() {
      data = pushed;
    });
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 190.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(handlerCalls, 1, reason: "setup: the drop committed");
    expect(
      controller.itemKeysOf("s2"),
      contains("x"),
      reason: "the mid-drag push must never be lost",
    );
    // The props are authoritative and the handler recorded nothing, so
    // the deferred sync also reverts the uncommitted move.
    expect(controller.itemKeysOf("s1"), <String>["a", "b", "c"]);
  });
}
