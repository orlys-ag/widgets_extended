/// Pins `TreeReorderConfig.enabled`, the supported way to switch reorder
/// off and on at runtime while the config stays present.
///
/// The contract under test: `enabled` is config CONTENT, so it is live on
/// rebuild; false refuses every path a move could take (drag start, a
/// drag already in flight, programmatic `moveTo`, semantics actions) and
/// dominates a permissive `canReorder`; flipping it never changes a row's
/// widget shape, so the app's `State` under the row survives; and true
/// restores dragging without rebuilding anything by hand.
///
/// Written before the field existed (repro-first): each test asserts the
/// EXPECTED behavior, so the suite fails on unfixed code.
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

List<int> _customActionIds(WidgetTester tester, String key) {
  final node = tester.getSemantics(find.byKey(ValueKey("row-$key")));
  return node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
}

/// Mutable knobs the config reads on every rebuild, plus the captured
/// channels. One instance per test.
class _Rig {
  bool enabled = true;
  bool Function(String key)? canReorder;
  final List<(String, String?, int)> events = <(String, String?, int)>[];
  TreeReorderController<String>? controller;
  late StateSetter rebuild;
}

Widget _defaultRow(BuildContext context, TreeItemView<String, _Node> view) {
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
}

Future<void> _pumpTree(
  WidgetTester tester,
  _Rig rig, {
  TreeItemBuilder<String, _Node>? itemBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rig.rebuild = setState;
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
                    enabled: rig.enabled,
                    buildDefaultDragHandles: false,
                    showDragProxy: false,
                    canReorder: rig.canReorder,
                    onControllerCreated: (controller) {
                      rig.controller = controller;
                    },
                    onReorder: (key, newParent, index) {
                      rig.events.add((key, newParent, index));
                    },
                  ),
                  itemBuilder: itemBuilder ?? _defaultRow,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Grabs the grip of the row at [gripIndex], drags by [delta], releases,
/// and settles. Whether anything committed is read off the rig's events.
Future<void> _attemptDrag(
  WidgetTester tester,
  int gripIndex,
  Offset delta,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(_Grip).at(gripIndex)),
  );
  await tester.pump();
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("enabled: false from construction refuses drags and "
      "withdraws semantics actions", (tester) async {
    final handle = tester.ensureSemantics();
    final rig = _Rig()..enabled = false;
    await _pumpTree(tester, rig);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_Grip).at(1)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 20.0));
    await tester.pump();
    expect(
      _isVisible(tester, "b"),
      isTrue,
      reason: "no session may start while the config is disabled",
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rig.events, isEmpty);

    expect(
      _customActionIds(tester, "b"),
      isEmpty,
      reason: "a disabled tree exposes no reorder actions",
    );

    // Prove the assertion above bites: the same row grows its actions the
    // moment the config is enabled, so an empty set was the flag's doing.
    rig.rebuild(() {
      rig.enabled = true;
    });
    await tester.pumpAndSettle();
    expect(
      _customActionIds(tester, "b"),
      isNotEmpty,
      reason: "setup sanity: enabling restores the built-in actions",
    );
    handle.dispose();
  });

  testWidgets("flipping enabled preserves the app's row State", (
    tester,
  ) async {
    final log = <String>[];
    final rig = _Rig();
    await _pumpTree(
      tester,
      rig,
      itemBuilder: (context, view) {
        return Row(
          children: <Widget>[
            Expanded(child: _Fragile(id: view.key, log: log)),
            const TreeDragHandle(child: _Grip()),
          ],
        );
      },
    );

    final before = tester.state<_FragileState>(
      find.byWidgetPredicate((w) => w is _Fragile && w.id == "a"),
    );
    before.counter = 42;
    expect(log, <String>["init:a", "init:b", "init:c"]);

    rig.rebuild(() {
      rig.enabled = false;
    });
    await tester.pumpAndSettle();

    expect(
      log.where((e) {
        return e.startsWith("dispose");
      }),
      isEmpty,
      reason: "an enabled flip must not tear down the app's row subtree",
    );
    final after = tester.state<_FragileState>(
      find.byWidgetPredicate((w) => w is _Fragile && w.id == "a"),
    );
    expect(identical(before, after), isTrue, reason: "same State object");
    expect(after.counter, 42, reason: "the app's own state survives intact");

    await _attemptDrag(tester, 0, const Offset(0.0, 90.0));
    expect(rig.events, isEmpty, reason: "and the flip genuinely disabled");
  });

  testWidgets("disabling mid-drag ends the session without committing", (
    tester,
  ) async {
    final rig = _Rig();
    await _pumpTree(tester, rig);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_Grip).at(1)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 20.0));
    await tester.pump();
    expect(
      _isVisible(tester, "b"),
      isFalse,
      reason: "setup sanity: the session genuinely owns this row",
    );

    rig.rebuild(() {
      rig.enabled = false;
    });
    await tester.pump();
    await tester.pump();

    expect(
      _isVisible(tester, "b"),
      isTrue,
      reason: "the orphaned session must be torn down, not left running",
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rig.events, isEmpty, reason: "an interrupted drag commits nothing");
  });

  testWidgets("enabled: false dominates a permissive canReorder", (
    tester,
  ) async {
    final rig = _Rig()
      ..enabled = false
      ..canReorder = (key) {
        return true;
      };
    await _pumpTree(tester, rig);

    await _attemptDrag(tester, 1, const Offset(0.0, 90.0));
    expect(
      rig.events,
      isEmpty,
      reason: "a per-row allow cannot override the config-level off switch",
    );
  });

  testWidgets("moveTo is refused while disabled and onReorder never fires", (
    tester,
  ) async {
    final rig = _Rig()..enabled = false;
    await _pumpTree(tester, rig);

    expect(rig.controller, isNotNull, reason: "setup sanity");
    expect(rig.controller!.moveTo("c", null, index: 0), isFalse);
    expect(rig.events, isEmpty);

    // The same call succeeds once enabled, so the refusal above was the
    // flag's doing rather than an illegal move.
    rig.rebuild(() {
      rig.enabled = true;
    });
    await tester.pumpAndSettle();
    expect(rig.controller!.moveTo("c", null, index: 0), isTrue);
    expect(rig.events, <(String, String?, int)>[("c", null, 0)]);
  });

  testWidgets("flipping enabled back on restores dragging", (tester) async {
    final rig = _Rig()..enabled = false;
    await _pumpTree(tester, rig);

    await _attemptDrag(tester, 1, const Offset(0.0, 90.0));
    expect(rig.events, isEmpty, reason: "setup sanity: starts disabled");

    rig.rebuild(() {
      rig.enabled = true;
    });
    await tester.pumpAndSettle();

    await _attemptDrag(tester, 1, const Offset(0.0, 90.0));
    expect(
      rig.events,
      isNotEmpty,
      reason: "the gate reads live state, not a construction-time capture",
    );
  });
}

/// Stands in for anything an app keeps in a row: a text field's contents,
/// a scroll offset, an AnimationController.
class _Fragile extends StatefulWidget {
  const _Fragile({required this.id, required this.log});
  final String id;
  final List<String> log;

  @override
  State<_Fragile> createState() => _FragileState();
}

class _FragileState extends State<_Fragile> {
  int counter = 0;

  @override
  void initState() {
    super.initState();
    widget.log.add("init:${widget.id}");
  }

  @override
  void dispose() {
    widget.log.add("dispose:${widget.id}");
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(key: ValueKey("row-${widget.id}"), height: 50);
  }
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
