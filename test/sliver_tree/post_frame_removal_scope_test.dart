/// The tree removes rows from post-frame callbacks: rows that scrolled out
/// of the cache region, and rows whose nodes were removed. Those removals
/// must not build widgets outside the tree, which a post-frame callback
/// registered before them may have marked dirty.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

class _Host extends StatefulWidget {
  const _Host({super.key, required this.controller, required this.scroll});

  final TreeController<String, String> controller;
  final ScrollController scroll;

  @override
  State<_Host> createState() {
    return _HostState();
  }
}

class _HostState extends State<_Host> {
  int builds = 0;

  void rebuild() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    builds += 1;
    return CustomScrollView(
      controller: widget.scroll,
      slivers: <Widget>[
        SliverTree<String, String>(
          controller: widget.controller,
          nodeBuilder: (context, key, depth) {
            return SizedBox(height: 48.0, child: Text(key));
          },
        ),
      ],
    );
  }
}

/// Pumps 200 rows of 48 px under a [_Host] and returns its key, the
/// controller and the scroll controller.
Future<
  (GlobalKey<_HostState>, TreeController<String, String>, ScrollController)
>
_pumpHost(WidgetTester tester) async {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  controller.setRoots(<TreeNode<String, String>>[
    for (var i = 0; i < 200; i++) TreeNode(key: "r$i", data: "r$i"),
  ]);
  final host = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _Host(key: host, controller: controller, scroll: scroll),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (host, controller, scroll);
}

/// Schedules a post-frame callback that rebuilds [host], ahead of any the
/// tree schedules during the next frame.
void _rebuildAfterFrame(GlobalKey<_HostState> host) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    host.currentState!.rebuild();
  });
}

void main() {
  testWidgets("evicting rows that scrolled away builds nothing outside the "
      "tree, and an ancestor's post-frame setState still rebuilds it in "
      "the next frame", (tester) async {
    final (host, _, scroll) = await _pumpHost(tester);
    expect(find.text("r0"), findsOneWidget);
    final builds = host.currentState!.builds;

    _rebuildAfterFrame(host);
    scroll.jumpTo(3000.0);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text("r0", skipOffstage: false), findsNothing);

    await tester.pump();
    expect(host.currentState!.builds, builds + 1);
  });

  testWidgets("removing the rows of removed nodes builds nothing outside "
      "the tree, and an ancestor's post-frame setState still rebuilds it "
      "in the next frame", (tester) async {
    final (host, controller, _) = await _pumpHost(tester);
    expect(find.text("r1"), findsOneWidget);
    final builds = host.currentState!.builds;

    _rebuildAfterFrame(host);
    controller.remove(key: "r1", animate: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text("r1", skipOffstage: false), findsNothing);

    await tester.pump();
    expect(host.currentState!.builds, builds + 1);
  });
}
