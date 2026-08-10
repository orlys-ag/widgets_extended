/// Repro: flipping `canReorder` destroys the app's `State` under the row.
///
/// Consulting the policy at build time made the row's WIDGET SHAPE depend
/// on it: a refused row omitted its gesture detector, and a row whose
/// action set went empty omitted its `Semantics` wrapper. Either omission
/// makes `Widget.canUpdate` fail against the previous build, so the
/// framework deactivates and re-inflates the whole row subtree.
///
/// Everything the app owns underneath goes with it. An "edit mode" toggle
/// is the ordinary way to hit this, and the symptom is not a reorder bug:
/// it is a half-typed text field going blank, a nested list jumping to the
/// top, an animation restarting.
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

Future<void> _run(
  WidgetTester tester, {
  required List<_Node> roots,
  bool callerPlacedGrip = false,
}) async {
  final log = <String>[];
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
                  roots: roots,
                  keyOf: (n) {
                    return n.id;
                  },
                  childrenOf: (n) {
                    return n.children;
                  },
                  animationStyle: TreeAnimationStyle.disabled,
                  reorder: TreeReorderConfig<String>(
                    buildDefaultDragHandles: !callerPlacedGrip,
                    showDragProxy: false,
                    canReorder: (key) {
                      return !locked.contains(key);
                    },
                    onReorder: (key, newParent, index) {},
                  ),
                  itemBuilder: (context, view) {
                    final row = _Fragile(id: view.key, log: log);
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
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final before = tester.state<_FragileState>(
    find.byWidgetPredicate((w) => w is _Fragile && w.id == "a"),
  );
  before.counter = 42;

  // Setup sanity: exactly one init and no dispose so far, so a later
  // dispose can only come from the flip below.
  expect(log, <String>["init:a", ...roots.skip(1).map((n) => "init:${n.id}")]);

  setOuter(() {
    locked.add("a");
  });
  await tester.pumpAndSettle();

  expect(
    log.where((e) => e.startsWith("dispose")),
    isEmpty,
    reason: "a policy flip must not tear down the app's row subtree",
  );
  final after = tester.state<_FragileState>(
    find.byWidgetPredicate((w) => w is _Fragile && w.id == "a"),
  );
  expect(identical(before, after), isTrue, reason: "same State object");
  expect(after.counter, 42, reason: "the app's own state survives intact");
}

void main() {
  // A LONE ROOT has no legal move, so its built-in action set is empty and
  // the `Semantics` wrapper is the shape that used to appear and vanish.
  testWidgets("default handle, lone root: policy flip preserves row state", (
    tester,
  ) async {
    await _run(tester, roots: const <_Node>[_Node("a")]);
  });

  // With siblings the action set is non-empty, so the surviving shape
  // difference is the handle's own arming.
  testWidgets("default handle, three roots: policy flip preserves row state", (
    tester,
  ) async {
    await _run(
      tester,
      roots: const <_Node>[_Node("a"), _Node("b"), _Node("c")],
    );
  });

  // The caller-placed case, which is the one that regressed historically:
  // a handle that is OMITTED rather than disarmed changes the row's shape
  // and re-inflates everything beneath it.
  testWidgets("caller-placed grip: policy flip preserves row state", (
    tester,
  ) async {
    await _run(
      tester,
      roots: const <_Node>[_Node("a"), _Node("b"), _Node("c")],
      callerPlacedGrip: true,
    );
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
