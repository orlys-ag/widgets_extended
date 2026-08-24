import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Inherited value a `nodeBuilder` can read, standing in for `Theme` in the
/// cases that need to isolate the dependency channel from `AnimatedTheme`
/// timing.
class _ValueScope extends InheritedWidget {
  const _ValueScope({required this.value, required super.child});

  final int value;

  static int of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ValueScope>()!.value;
  }

  @override
  bool updateShouldNotify(_ValueScope old) {
    return value != old.value;
  }
}

/// Flips the inherited value WITHOUT rebuilding the subtree.
///
/// The hoist is load-bearing, not incidental: `build` passes the identical
/// `widget.child` instance through, so `Element.updateChild` short-circuits
/// and `SliverTree` is never rebuilt. Without it the toggle would rebuild
/// `SliverTree` too, `SliverTreeElement.update` would queue every mounted
/// key, and the row would pick up the new value even on unfixed code, so
/// the test would pass today and prove nothing. This mirrors what
/// `AnimatedTheme` does with its own child.
class _Toggler extends StatefulWidget {
  const _Toggler({required this.child});

  final Widget child;

  @override
  State<_Toggler> createState() {
    return _TogglerState();
  }
}

class _TogglerState extends State<_Toggler> {
  int _value = 1;

  void bump() {
    setState(() {
      _value += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ValueScope(value: _value, child: widget.child);
  }
}

/// Holds the theme for case 1, hoisting the subtree the same way.
class _ThemeHost extends StatefulWidget {
  const _ThemeHost({required this.child});

  final Widget child;

  @override
  State<_ThemeHost> createState() {
    return _ThemeHostState();
  }
}

class _ThemeHostState extends State<_ThemeHost> {
  ThemeData _theme = ThemeData.light();

  void goDark() {
    setState(() {
      _theme = ThemeData.dark();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: _theme, home: Scaffold(body: widget.child));
  }
}

TreeController<String, String> _controllerWith(
  WidgetTester tester,
  int count,
) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  controller.setRoots([
    for (int i = 0; i < count; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);
  return controller;
}

void main() {
  group("H6: inherited-widget reads in nodeBuilder refresh rows", () {
    testWidgets("case 1: a MaterialApp theme toggle reaches mounted rows", (
      tester,
    ) async {
      final controller = _controllerWith(tester, 20);
      addTearDown(controller.dispose);
      final log = <Brightness>[];

      await tester.pumpWidget(
        _ThemeHost(
          child: CustomScrollView(
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                nodeBuilder: (context, nodeId, depth) {
                  final brightness = Theme.of(context).brightness;
                  log.add(brightness);
                  return SizedBox(
                    height: 48,
                    child: ColoredBox(
                      color: brightness == Brightness.dark
                          ? const Color(0xFF000000)
                          : const Color(0xFFFFFFFF),
                      child: Text(nodeId),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );

      expect(log, isNotEmpty, reason: "sanity: rows built at least once");
      expect(
        log.last,
        Brightness.light,
        reason: "sanity: the tree starts on the light theme",
      );

      final before = tester.widget<SliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      log.clear();
      tester.state<_ThemeHostState>(find.byType(_ThemeHost)).goDark();
      await tester.pumpAndSettle();

      final after = tester.widget<SliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      expect(
        identical(before, after),
        isTrue,
        reason:
            "sanity: the SliverTree widget instance must be hoisted through "
            "the theme change, or update() would queue every key and the "
            "dependency channel would not be under test",
      );

      // Guard before reading `log.last`: on unfixed code the log is EMPTY,
      // and an unguarded `.last` dies with a bare StateError that never
      // prints the reason below. Cases 2 and 4 guard the same way.
      expect(
        log,
        isNotEmpty,
        reason:
            "an inherited change must rebuild mounted rows; today the "
            "notification never reaches them",
      );
      expect(
        log.last,
        Brightness.dark,
        reason:
            "a Theme.of(context) read inside nodeBuilder must see the new "
            "brightness after the theme animation settles",
      );
      // Scope to the ColoredBox belonging to the row: Material chrome
      // contributes others, so an unscoped byType finder asserts on the
      // wrong widget.
      final box = tester.widget<ColoredBox>(
        find
            .ancestor(of: find.text("r0"), matching: find.byType(ColoredBox))
            .first,
      );
      expect(
        box.color,
        const Color(0xFF000000),
        reason: "the mounted row must carry the dark colour, not just the log",
      );
    });

    testWidgets("case 2: a non-animated inherited change reaches mounted rows", (
      tester,
    ) async {
      final controller = _controllerWith(tester, 20);
      addTearDown(controller.dispose);
      final log = <int>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _Toggler(
            child: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, nodeId, depth) {
                    log.add(_ValueScope.of(context));
                    return SizedBox(height: 48, child: Text(nodeId));
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(log, isNotEmpty, reason: "sanity: rows built at least once");
      expect(log.last, 1, reason: "sanity: rows start on the initial value");

      final before = tester.widget<SliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      log.clear();
      tester.state<_TogglerState>(find.byType(_Toggler)).bump();
      await tester.pump();

      final after = tester.widget<SliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      expect(
        identical(before, after),
        isTrue,
        reason:
            "sanity: the hoist must hold, or update() queues every key and "
            "this stops testing the dependency channel",
      );

      expect(
        log,
        isNotEmpty,
        reason:
            "an inherited change must rebuild mounted rows; today the "
            "notification lands in performRebuild and is dropped",
      );
      expect(log.last, 2, reason: "rows must observe the new inherited value");
    });

    testWidgets("case 3: SliverList control proves the harness is sound", (
      tester,
    ) async {
      final log = <int>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _Toggler(
            child: CustomScrollView(
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    log.add(_ValueScope.of(context));
                    return SizedBox(height: 48, child: Text("i$index"));
                  }, childCount: 20),
                ),
              ],
            ),
          ),
        ),
      );

      expect(log, isNotEmpty, reason: "sanity: rows built at least once");
      expect(log.last, 1);

      final before = tester.widget<SliverList>(find.byType(SliverList));

      log.clear();
      tester.state<_TogglerState>(find.byType(_Toggler)).bump();
      await tester.pump();

      final after = tester.widget<SliverList>(find.byType(SliverList));
      expect(
        identical(before, after),
        isTrue,
        reason: "sanity: the same hoist applies to the control",
      );

      expect(
        log.last,
        2,
        reason:
            "SliverList refreshes on the same harness, so a SliverTree "
            "failure is specific to SliverTreeElement and not to this setup",
      );
    });

    testWidgets("case 4: one notification rebuilds admitted rows at most once", (
      tester,
    ) async {
      final controller = _controllerWith(tester, 200);
      addTearDown(controller.dispose);
      final log = <String>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _Toggler(
            child: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, nodeId, depth) {
                    _ValueScope.of(context);
                    log.add(nodeId);
                    return SizedBox(height: 48, child: Text(nodeId));
                  },
                ),
              ],
            ),
          ),
        ),
      );

      final initial = log.toSet();
      expect(
        initial.length,
        lessThan(200),
        reason:
            "sanity: admission must be bounded, or (a) below cannot "
            "discriminate a rebuild-everything regression",
      );

      final before = tester.widget<SliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      log.clear();
      tester.state<_TogglerState>(find.byType(_Toggler)).bump();
      await tester.pump();

      final after = tester.widget<SliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      expect(
        identical(before, after),
        isTrue,
        reason:
            "sanity: the hoist must hold. Without it the toggle rebuilds "
            "SliverTree, update() queues every mounted key, and the three "
            "assertions below pass even on unfixed code",
      );

      expect(log, isNotEmpty, reason: "the notification must reach some rows");
      expect(
        log.toSet().difference(initial),
        isEmpty,
        reason:
            "a dependency change admits no new row, so every rebuild must "
            "name a key that was already mounted",
      );
      expect(
        log.length,
        log.toSet().length,
        reason:
            "one notification produces one queue and one layout, so no key "
            "may be rebuilt twice",
      );
    });
  });
}
