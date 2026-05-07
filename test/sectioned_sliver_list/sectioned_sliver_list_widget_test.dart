import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Widget _wrap(Widget sliver) {
  return MaterialApp(
    home: Scaffold(body: CustomScrollView(slivers: [sliver])),
  );
}

SectionedListController<String, String, String> _makeController(
  WidgetTester tester, {
  Duration animationDuration = Duration.zero,
}) {
  return SectionedListController<String, String, String>(
    vsync: tester,
    sectionKeyOf: (s) => s,
    itemKeyOf: (i) => i,
    animationDuration: animationDuration,
  );
}

void main() {
  group("SectionedSliverList — declarative", () {
    testWidgets("renders sections and items in order", (tester) async {
      final byKey = {
        "a": ["a1", "a2"],
        "b": ["b1"],
      };
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a", "b"],
            itemsOf: (s) => byKey[s] ?? const [],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("H:a"), findsOneWidget);
      expect(find.text("I:a1"), findsOneWidget);
      expect(find.text("I:a2"), findsOneWidget);
      expect(find.text("H:b"), findsOneWidget);
      expect(find.text("I:b1"), findsOneWidget);
    });

    testWidgets("respects initiallyExpanded: false", (tester) async {
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a"],
            itemsOf: (_) => const ["a1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
            initiallyExpanded: false,
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("H:a"), findsOneWidget);
      expect(find.text("I:a1"), findsNothing);
    });

    testWidgets("initialSectionExpansion overrides per section", (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a", "b"],
            itemsOf: (s) => ["${s}1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
            initiallyExpanded: true,
            initialSectionExpansion: (key, _) => key == "a" ? false : null,
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("I:a1"), findsNothing);
      expect(find.text("I:b1"), findsOneWidget);
    });

    testWidgets("hideEmptySections filters input", (tester) async {
      final byKey = {
        "a": ["a1"],
        "b": <String>[],
        "c": ["c1"],
      };
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a", "b", "c"],
            itemsOf: (s) => byKey[s] ?? const [],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
            hideEmptySections: true,
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("H:a"), findsOneWidget);
      expect(find.text("H:b"), findsNothing);
      expect(find.text("H:c"), findsOneWidget);
    });

    testWidgets("declarative rebuild diffs with animations", (tester) async {
      Widget build(Map<String, List<String>> map) {
        return _wrap(
          SectionedSliverList<String, String, String>(
            sections: map.keys.toList(),
            itemsOf: (s) => map[s] ?? const [],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
            animationDuration: Duration.zero,
          ),
        );
      }

      await tester.pumpWidget(build({"a": ["a1"]}));
      expect(find.text("I:a1"), findsOneWidget);

      await tester.pumpWidget(build({"a": ["a1", "a2"]}));
      await tester.pump();
      expect(find.text("I:a2"), findsOneWidget);
    });
  });

  group("SectionedSliverList.fromMap", () {
    testWidgets("renders from a Map<Section, List<Item>>", (tester) async {
      final grouped = <String, List<String>>{
        "Folder A": ["a1", "a2"],
        "Folder B": ["b1"],
      };
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.fromMap(
            sections: grouped,
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("H:Folder A"), findsOneWidget);
      expect(find.text("I:a1"), findsOneWidget);
      expect(find.text("I:a2"), findsOneWidget);
      expect(find.text("H:Folder B"), findsOneWidget);
      expect(find.text("I:b1"), findsOneWidget);
    });
  });

  group("SectionedSliverList.controlled", () {
    testWidgets(
      "external controller wires through and exposes itself via GlobalKey",
      (tester) async {
        final globalKey =
            GlobalKey<SectionedSliverListState<String, String, String>>();
        final controller = _makeController(tester);
        addTearDown(controller.dispose);
        controller.addSection("a", items: ["a1"]);
        controller.expandSection("a", animate: false);

        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>.controlled(
              key: globalKey,
              controller: controller,
              headerBuilder: (ctx, view) => Text("H:${view.section}"),
              itemBuilder: (ctx, view) => Text("I:${view.item}"),
            ),
          ),
        );

        expect(globalKey.currentState?.controller, same(controller));
        expect(controller.sectionKeys, equals(["a"]));
        expect(controller.itemKeysOf("a"), equals(["a1"]));

        controller.addItem("a2", toSection: "a");
        await tester.pumpAndSettle();
        expect(find.text("I:a2"), findsOneWidget);
      },
    );

    testWidgets(
      "external controller is NOT disposed when the widget unmounts",
      (tester) async {
        final external = _makeController(tester);
        addTearDown(external.dispose);
        external.addSection("a");

        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>.controlled(
              controller: external,
              headerBuilder: (ctx, view) => Text("H:${view.section}"),
              itemBuilder: (ctx, view) => Text("I:${view.item}"),
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());

        expect(() => external.hasSection("a"), returnsNormally);
      },
    );

    testWidgets(
      "controlled mode treats the controller as source of truth — widget "
      "doesn't apply initiallyExpanded; pre-set state survives",
      (tester) async {
        final controller = _makeController(tester);
        addTearDown(controller.dispose);
        controller.addSection("a", items: ["a1"]);
        controller.addSection("b", items: ["b1"]);
        controller.expandSection("a", animate: false);
        // 'b' is intentionally left collapsed.

        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>.controlled(
              controller: controller,
              headerBuilder: (ctx, view) => Text("H:${view.section}"),
              itemBuilder: (ctx, view) => Text("I:${view.item}"),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          controller.isExpanded("a"),
          isTrue,
          reason: "Pre-mount expanded state must survive mount.",
        );
        expect(
          controller.isExpanded("b"),
          isFalse,
          reason: "Controlled mode must not force-expand pre-collapsed "
              "sections — the controller is the source of truth.",
        );
        expect(find.text("I:a1"), findsOneWidget);
        expect(find.text("I:b1"), findsNothing);
      },
    );

    testWidgets("controller swap rebinds; old is unbound, new is adopted",
        (tester) async {
      final c1 = _makeController(tester);
      final c2 = _makeController(tester);
      addTearDown(c1.dispose);
      addTearDown(c2.dispose);
      c1.addSection("a", items: ["a1"]);
      c2.addSection("z", items: ["z1"]);

      Widget build(SectionedListController<String, String, String> c) {
        return _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: c,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
          ),
        );
      }

      await tester.pumpWidget(build(c1));
      await tester.pumpAndSettle();
      expect(find.text("H:a"), findsOneWidget);

      await tester.pumpWidget(build(c2));
      await tester.pumpAndSettle();
      expect(find.text("H:a"), findsNothing);
      expect(find.text("H:z"), findsOneWidget);

      // c1 must be unbound (rebindable now).
      expect(c1.debugBindWidget, returnsNormally);
      c1.debugUnbindWidget();
    });

    testWidgets(
      "collapsible: false in controlled mode is advisory — does NOT "
      "force-expand controller-collapsed sections",
      (tester) async {
        final controller = _makeController(tester);
        addTearDown(controller.dispose);
        controller.addSection("a", items: ["a1"]);
        // Section 'a' starts collapsed (controller default).

        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>.controlled(
              controller: controller,
              collapsible: false,
              headerBuilder: (ctx, view) =>
                  Text("H:${view.section} c=${view.isCollapsible}"),
              itemBuilder: (ctx, view) => Text("I:${view.item}"),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          controller.isExpanded("a"),
          isFalse,
          reason: "collapsible: false in controlled mode must NOT alter "
              "the controller's expansion state — it is an advisory flag "
              "only.",
        );
        expect(find.text("H:a c=false"), findsOneWidget);
        expect(find.text("I:a1"), findsNothing);
      },
    );

    testWidgets(
      "collapsible: false in iterable mode force-expands every section",
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>(
              sections: const ["a"],
              itemsOf: (_) => const ["a1"],
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              collapsible: false,
              initiallyExpanded: false, // would normally hide a1
              headerBuilder: (ctx, view) => Text("H:${view.section}"),
              itemBuilder: (ctx, view) => Text("I:${view.item}"),
              animationDuration: Duration.zero,
            ),
          ),
        );

        // collapsible:false trumps initiallyExpanded:false.
        expect(find.text("I:a1"), findsOneWidget);
      },
    );
  });

  group("SectionedSliverList — view shortcuts", () {
    Future<ItemView<String, String, String>> captureItemView(
      WidgetTester tester,
      SectionedListController<String, String, String> controller,
      String itemKey,
    ) async {
      final captured = <String, ItemView<String, String, String>>{};
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) {
              captured[view.key] = view;
              return Text("I:${view.item}");
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return captured[itemKey]!;
    }

    testWidgets("ItemView.update writes through to the controller",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1"]);
      controller.expandSection("a", animate: false);

      final view = await captureItemView(tester, controller, "a1");
      view.update("a1!");
      expect(controller.getItem("a1"), equals("a1!"));
    });

    testWidgets("ItemView.moveTo (section + index) → moveItem(toSection, index)",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1", "a2"]);
      controller.addSection("b", items: const ["b1"]);
      controller.expandSection("a", animate: false);
      controller.expandSection("b", animate: false);

      final view = await captureItemView(tester, controller, "a1");
      view.moveTo(section: "b", index: 0);
      expect(controller.itemKeysOf("a"), equals(["a2"]));
      expect(controller.itemKeysOf("b"), equals(["a1", "b1"]));
    });

    testWidgets("ItemView.moveTo (section only) → moveItem appends",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1"]);
      controller.addSection("b", items: ["b1"]);
      controller.expandSection("a", animate: false);
      controller.expandSection("b", animate: false);

      final view = await captureItemView(tester, controller, "a1");
      view.moveTo(section: "b");
      expect(controller.itemKeysOf("a"), isEmpty);
      expect(controller.itemKeysOf("b"), equals(["b1", "a1"]));
    });

    testWidgets("ItemView.moveTo (index only) → moveItemInSection",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1", "a2", "a3"]);
      controller.expandSection("a", animate: false);

      final view = await captureItemView(tester, controller, "a1");
      view.moveTo(index: 2);
      expect(controller.itemKeysOf("a"), equals(["a2", "a3", "a1"]));
    });

    testWidgets("ItemView.moveTo (both null) → no-op", (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1", "a2"]);
      controller.expandSection("a", animate: false);

      final view = await captureItemView(tester, controller, "a1");
      view.moveTo();
      expect(controller.itemKeysOf("a"), equals(["a1", "a2"]));
    });

    testWidgets("ItemView.remove writes through", (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1"]);
      controller.expandSection("a", animate: false);

      final view = await captureItemView(tester, controller, "a1");
      view.remove(animate: false);
      expect(controller.hasItem("a1"), isFalse);
    });

    testWidgets("SectionView.expand/collapse/toggle ignore isCollapsible",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1"]);

      late SectionView<String, String, String> view;
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            collapsible: false, // isCollapsible == false
            headerBuilder: (ctx, v) {
              view = v;
              return Text("H:${v.section} c=${v.isCollapsible}");
            },
            itemBuilder: (ctx, v) => Text("I:${v.item}"),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(view.isCollapsible, isFalse);
      // Even though isCollapsible is false, expand/collapse pass through.
      view.expand(animate: false);
      expect(controller.isExpanded("a"), isTrue);
      view.collapse(animate: false);
      expect(controller.isExpanded("a"), isFalse);
    });
  });

  group("SectionedSliverList — watch", () {
    testWidgets("SectionView.watch rebuilds on expand/collapse only",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1"]);
      // Section starts collapsed.

      var headerBuilds = 0;
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, view) => view.watch(
              builder: (ctx, v) {
                headerBuilds++;
                return Text("${v.section} ${v.isExpanded ? 'open' : 'closed'}");
              },
            ),
            itemBuilder: (ctx, view) => Text(view.item),
          ),
        ),
      );
      final initial = headerBuilds;
      expect(find.text("a closed"), findsOneWidget);

      controller.expandSection("a");
      await tester.pumpAndSettle();
      expect(find.text("a open"), findsOneWidget);
      expect(headerBuilds, greaterThan(initial));
    });

    testWidgets("SectionView.watch rebuilds on item add/remove (count change)",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1"]);
      controller.expandSection("a", animate: false);

      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, view) => view.watch(
              builder: (ctx, v) => Text("${v.section}: ${v.itemCount}"),
            ),
            itemBuilder: (ctx, view) => Text(view.item),
          ),
        ),
      );
      expect(find.text("a: 1"), findsOneWidget);

      controller.addItem("a2", toSection: "a");
      await tester.pumpAndSettle();
      expect(find.text("a: 2"), findsOneWidget);

      controller.addItem("a3", toSection: "a");
      await tester.pumpAndSettle();
      expect(find.text("a: 3"), findsOneWidget);

      controller.removeItem("a1");
      await tester.pumpAndSettle();
      expect(find.text("a: 2"), findsOneWidget);

      controller.setItems("a", const []);
      await tester.pumpAndSettle();
      expect(find.text("a: 0"), findsOneWidget);
    });

    testWidgets("ItemView.watch rebuilds on updateItem", (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["v1"]);
      controller.expandSection("a", animate: false);

      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) =>
                view.watch(builder: (ctx, v) => Text("item:${v.item}")),
          ),
        ),
      );
      expect(find.text("item:v1"), findsOneWidget);

      controller.updateItem("v1", "v2");
      await tester.pumpAndSettle();
      expect(find.text("item:v2"), findsOneWidget);
    });

    testWidgets(
      "ItemView.watch only rebuilds the affected item, not its neighbors",
      (tester) async {
        final controller = _makeController(tester);
        addTearDown(controller.dispose);
        controller.addSection("a", items: ["a1", "a2"]);
        controller.expandSection("a", animate: false);

        final builds = <String, int>{"a1": 0, "a2": 0};
        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>.controlled(
              controller: controller,
              headerBuilder: (ctx, view) => Text(view.section),
              itemBuilder: (ctx, view) => view.watch(
                builder: (ctx, v) {
                  builds[v.key] = (builds[v.key] ?? 0) + 1;
                  return Text("item:${v.item}");
                },
              ),
            ),
          ),
        );
        final a1Initial = builds["a1"]!;
        final a2Initial = builds["a2"]!;

        controller.updateItem("a1", "a1!");
        await tester.pumpAndSettle();

        expect(builds["a1"], greaterThan(a1Initial),
            reason: "a1's watcher must rebuild — its payload changed.");
        expect(
          builds["a2"],
          equals(a2Initial),
          reason: "a2's watcher must NOT rebuild — its payload didn't "
              "change, and the typed payload listener is filtered by key.",
        );
      },
    );
  });

  group("SectionedSliverList — itemIndent", () {
    testWidgets("default-mode itemIndent forwards to controller.itemIndent",
        (tester) async {
      final globalKey =
          GlobalKey<SectionedSliverListState<String, String, String>>();
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            key: globalKey,
            sections: const ["a"],
            itemsOf: (_) => const ["a1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            itemIndent: 24.0,
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
            animationDuration: Duration.zero,
          ),
        ),
      );
      expect(globalKey.currentState!.controller.itemIndent, equals(24.0));
      expect(
        globalKey.currentState!.controller.treeController.indentWidth,
        equals(24.0),
      );

      // didUpdateWidget should propagate a new itemIndent.
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            key: globalKey,
            sections: const ["a"],
            itemsOf: (_) => const ["a1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            itemIndent: 32.0,
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
            animationDuration: Duration.zero,
          ),
        ),
      );
      expect(globalKey.currentState!.controller.itemIndent, equals(32.0));
    });
  });

  group("SectionedSliverList — mode transitions", () {
    testWidgets(
      "mode transition across rebuild asserts (default → .controlled)",
      (tester) async {
        const widgetKey = ValueKey("same");
        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>(
              key: widgetKey,
              sections: const ["a"],
              itemsOf: (_) => const [],
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              headerBuilder: (ctx, view) => Text(view.section),
              itemBuilder: (ctx, view) => Text(view.item),
              animationDuration: Duration.zero,
            ),
          ),
        );

        // Mode transition leaves the widget tree in an inconsistent
        // state, producing cascading framework errors during teardown.
        // Capture all errors for the rest of the test and verify the
        // mode-transition assertion is among them. We DON'T restore
        // FlutterError.onError — teardown errors must also be silenced.
        final caught = <Object>[];
        FlutterError.onError = (details) {
          caught.add(details.exception);
        };

        // Reuse the same key — Flutter routes this through
        // didUpdateWidget instead of unmount+remount.
        final controller = _makeController(tester);
        addTearDown(() {
          // Swallow any throws from dispose() against a bad-state controller.
          try {
            controller.dispose();
          } catch (_) {}
        });

        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>.controlled(
              key: widgetKey,
              controller: controller,
              headerBuilder: (ctx, view) => Text(view.section),
              itemBuilder: (ctx, view) => Text(view.item),
            ),
          ),
        );

        expect(
          caught.whereType<AssertionError>().any(
                (e) => e.message.toString().contains("mode transition"),
              ),
          isTrue,
          reason: "Expected the mode-transition assertion among cascading "
              "errors (got ${caught.map((e) => e.runtimeType).toList()})",
        );
      },
    );
  });
}

