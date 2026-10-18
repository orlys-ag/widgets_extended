/// The tree drops a row during the layout that leaves it unretained, so the
/// frame that drops it also disposes it, as Flutter's own slivers dispose
/// theirs. A row is never left deactivated between frames, where the next
/// pointer event would still reach a widget that listens to every pointer
/// event until it is disposed, such as a Tooltip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// A row that records its key when its State is created, deactivated and
/// disposed.
class _Row extends StatefulWidget {
  const _Row({required this.id, required this.log});

  final String id;
  final _Log log;

  @override
  State<_Row> createState() {
    return _RowState();
  }
}

class _RowState extends State<_Row> {
  @override
  void initState() {
    super.initState();
    widget.log.mounted.add(widget.id);
  }

  @override
  void deactivate() {
    widget.log.deactivated.add(widget.id);
    super.deactivate();
  }

  @override
  void dispose() {
    widget.log.disposed.add(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 48.0, child: Text(widget.id));
  }
}

class _Log {
  final Set<String> mounted = <String>{};
  final Set<String> deactivated = <String>{};
  final Set<String> disposed = <String>{};
}

TreeController<String, String> _controllerOf(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  controller.setRoots(<TreeNode<String, String>>[
    for (var i = 0; i < 100; i++) TreeNode(key: "n$i", data: "n$i"),
  ]);
  return controller;
}

Widget _harness(
  TreeController<String, String> controller,
  ScrollController scroll,
  Widget Function(String key) row,
) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 300.0,
        child: CustomScrollView(
          controller: scroll,
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return row(key);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("a row scrolled out of the cache region is disposed by the "
      "frame that drops it", (tester) async {
    final controller = _controllerOf(tester);
    addTearDown(controller.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final log = _Log();
    await tester.pumpWidget(
      _harness(controller, scroll, (key) {
        return _Row(id: key, log: log);
      }),
    );
    // Setup sanity: the first row is built.
    expect(log.mounted, contains("n0"));

    scroll.jumpTo(3000.0);
    await tester.pump();
    // Setup sanity: the frame dropped the first row.
    expect(log.deactivated, contains("n0"));
    expect(log.disposed, contains("n0"));
  });

  testWidgets("a row of a removed node is disposed by the frame that drops "
      "it", (tester) async {
    final controller = _controllerOf(tester);
    addTearDown(controller.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final log = _Log();
    await tester.pumpWidget(
      _harness(controller, scroll, (key) {
        return _Row(id: key, log: log);
      }),
    );
    // Setup sanity: the row is built.
    expect(log.mounted, contains("n1"));

    controller.remove(key: "n1");
    await tester.pump();
    // Setup sanity: the frame dropped the row.
    expect(log.deactivated, contains("n1"));
    expect(log.disposed, contains("n1"));
  });

  testWidgets("a pointer event after the frame that drops a row holding a "
      "Tooltip reaches no deactivated Tooltip", (tester) async {
    final controller = _controllerOf(tester);
    addTearDown(controller.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _harness(controller, scroll, (key) {
        return SizedBox(
          height: 48.0,
          child: Tooltip(message: key, child: Text(key)),
        );
      }),
    );
    scroll.jumpTo(3000.0);
    await tester.pump();
    // Setup sanity: the first row's Tooltip is no longer in the tree.
    expect(find.byTooltip("n0"), findsNothing);

    final gesture = await tester.startGesture(const Offset(10.0, 10.0));
    await gesture.up();
    expect(tester.takeException(), isNull);
  });
}
