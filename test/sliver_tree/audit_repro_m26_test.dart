import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Probe for M26: after a hot reload (`BuildOwner.reassemble`), mounted
/// rows must re-run `nodeBuilder`, whose closure body is what a reload
/// replaces. A test cannot swap code, so the builder reads a variable the
/// test flips before the reassemble: a row showing the new value proves
/// the builder ran on the reassemble frame.
///
/// Case 1 hands `SliverTree` down as a hoisted child (the shape
/// `AnimatedBuilder`, `ValueListenableBuilder` and `AnimatedTheme`
/// produce), so the ancestor's rebuild yields the identical widget and
/// `SliverTreeElement.update` never runs. Case 2 constructs a fresh
/// `SliverTree` per build, the shape whose `update` path already
/// refreshes rows; it is the control that proves the probe measures the
/// reload path and not the harness.
///
/// Cases 3 and 4 measure the other half of hot reload's contract: row
/// `State` survives a reload. Each row is a `StatefulWidget` counting
/// `dispose`; a reload that re-inflates rows disposes their old `State`,
/// while a row newly admitted by the reload's layout pass disposes
/// nothing (the first layout admits rows against estimated extents, so
/// the second can admit more).
void main() {
  testWidgets("case 1: hoisted SliverTree re-runs nodeBuilder on reassemble", (
    tester,
  ) async {
    _suffix = "A";
    final controller = _controller(tester);
    final tree = SliverTree<String, String>(
      controller: controller,
      nodeBuilder: _buildRow,
    );
    await tester.pumpWidget(_Hoist(child: _scaffold(tree)));
    expect(find.text("r0 A"), findsOneWidget, reason: "setup sanity");
    expect(
      find.text("r0 B"),
      findsNothing,
      reason: "setup sanity: the probe value is unique to the new build",
    );

    final before = _treeWidget(tester);
    _suffix = "B";
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await tester.pump();

    expect(
      identical(before, _treeWidget(tester)),
      isTrue,
      reason:
          "setup sanity: the hoist must hand the identical SliverTree "
          "through, or update() refreshes the rows and the case proves "
          "nothing",
    );
    expect(
      find.text("r0 B"),
      findsOneWidget,
      reason:
          "the reassemble frame must re-run nodeBuilder for mounted rows; "
          "stale rows after a hot reload",
    );
    expect(find.text("r14 B"), findsOneWidget);
  });

  testWidgets(
    "case 2: control, a fresh SliverTree per build refreshes through update",
    (tester) async {
      _suffix = "A";
      final controller = _controller(tester);
      await tester.pumpWidget(_Fresh(controller: controller));
      expect(find.text("r0 A"), findsOneWidget, reason: "setup sanity");

      final before = _treeWidget(tester);
      _suffix = "B";
      tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
      await tester.pump();

      expect(
        identical(before, _treeWidget(tester)),
        isFalse,
        reason: "setup sanity: this shape rebuilds a new SliverTree",
      );
      expect(find.text("r0 B"), findsOneWidget);
    },
  );

  testWidgets("case 3: hoisted shape, row State survives the reassemble", (
    tester,
  ) async {
    _suffix = "A";
    _RowState.initCount = 0;
    _RowState.disposeCount = 0;
    final controller = _controller(tester);
    final tree = SliverTree<String, String>(
      controller: controller,
      nodeBuilder: _buildRow,
    );
    await tester.pumpWidget(_Hoist(child: _scaffold(tree)));
    expect(
      _RowState.initCount,
      greaterThan(0),
      reason: "setup sanity: rows mounted",
    );

    _suffix = "B";
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await tester.pump();

    expect(find.text("r0 B"), findsOneWidget, reason: "rows refreshed");
    expect(
      _RowState.disposeCount,
      0,
      reason:
          "hot reload keeps State: a refreshed row must be updated in "
          "place, not re-inflated",
    );
  });

  testWidgets("case 4: fresh-instance shape, row State survives the "
      "reassemble", (tester) async {
    _suffix = "A";
    _RowState.initCount = 0;
    _RowState.disposeCount = 0;
    final controller = _controller(tester);
    await tester.pumpWidget(_Fresh(controller: controller));
    expect(
      _RowState.initCount,
      greaterThan(0),
      reason: "setup sanity: rows mounted",
    );

    _suffix = "B";
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await tester.pump();

    expect(find.text("r0 B"), findsOneWidget, reason: "rows refreshed");
    expect(
      _RowState.disposeCount,
      0,
      reason:
          "hot reload keeps State: a refreshed row must be updated in "
          "place, not re-inflated",
    );
  });
}

/// The value a "hot reload" changes; read by [_buildRow] at build time.
String _suffix = "A";

Widget _buildRow(BuildContext context, String key, int depth) {
  return _Row(label: "$key $_suffix");
}

class _Row extends StatefulWidget {
  const _Row({required this.label});

  final String label;

  @override
  State<_Row> createState() {
    return _RowState();
  }
}

class _RowState extends State<_Row> {
  static int initCount = 0;
  static int disposeCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 40, child: Text(widget.label));
  }
}

TreeController<String, String> _controller(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  controller.setRoots([
    for (var i = 0; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);
  addTearDown(controller.dispose);
  return controller;
}

Widget _scaffold(Widget sliver) {
  return MaterialApp(
    home: Scaffold(body: CustomScrollView(slivers: [sliver])),
  );
}

SliverTree<String, String> _treeWidget(WidgetTester tester) {
  return tester.widget<SliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

/// Passes the identical `child` through on every build.
class _Hoist extends StatefulWidget {
  const _Hoist({required this.child});

  final Widget child;

  @override
  State<_Hoist> createState() {
    return _HoistState();
  }
}

class _HoistState extends State<_Hoist> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Constructs a new `SliverTree` on every build.
class _Fresh extends StatefulWidget {
  const _Fresh({required this.controller});

  final TreeController<String, String> controller;

  @override
  State<_Fresh> createState() {
    return _FreshState();
  }
}

class _FreshState extends State<_Fresh> {
  @override
  Widget build(BuildContext context) {
    return _scaffold(
      SliverTree<String, String>(
        controller: widget.controller,
        nodeBuilder: _buildRow,
      ),
    );
  }
}
