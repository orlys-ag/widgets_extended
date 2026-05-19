import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Widget _wrap(Widget sliver) {
  return MaterialApp(
    home: Scaffold(body: CustomScrollView(slivers: [sliver])),
  );
}

SectionedListController<String, String, String> _makeController(
  WidgetTester tester,
) {
  return SectionedListController<String, String, String>(
    vsync: tester,
    sectionKeyOf: (s) => s,
    itemKeyOf: (i) => i,
    animationDuration: Duration.zero,
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

    testWidgets("collapsible: false force-expands every section",
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
    });
  });

  group("SectionedSliverList.controlled", () {
    testWidgets("renders the controller's current state", (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1", "a2"]);
      controller.expandSection("a", animate: false);

      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
          ),
        ),
      );

      expect(find.text("H:a"), findsOneWidget);
      expect(find.text("I:a1"), findsOneWidget);
      expect(find.text("I:a2"), findsOneWidget);
    });

    testWidgets("controller mutations reflect without a prop rebuild",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a", items: ["a1"]);
      controller.expandSection("a", animate: false);

      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
          ),
        ),
      );
      expect(find.text("I:a1"), findsOneWidget);

      controller.addItem("a2", toSection: "a");
      await tester.pumpAndSettle();
      expect(find.text("I:a2"), findsOneWidget);

      controller.removeItem("a1", animate: false);
      await tester.pumpAndSettle();
      expect(find.text("I:a1"), findsNothing);
    });

    testWidgets("collapsible: false is advisory — does NOT force-expand",
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

      expect(find.text("H:a c=false"), findsOneWidget);
      expect(
        controller.isExpanded("a"),
        isFalse,
        reason: "collapsible:false must not alter the controller's "
            "expansion state in the controlled form.",
      );
      expect(find.text("I:a1"), findsNothing);
    });

    testWidgets("external controller is NOT disposed when the widget unmounts",
        (tester) async {
      final controller = _makeController(tester);
      addTearDown(controller.dispose);
      controller.addSection("a");

      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>.controlled(
            controller: controller,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) => Text("I:${view.item}"),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());

      expect(() => controller.hasSection("a"), returnsNormally);
    });
  });

  group("SectionedSliverList — view shortcuts", () {
    // Mounts a declarative list and returns the [ItemView] handed to the
    // builder for [itemKey]. Sections are expanded by default, so every
    // item's builder runs.
    Future<ItemView<String, String, String>> captureItemView(
      WidgetTester tester, {
      required List<String> sections,
      required Map<String, List<String>> items,
      required String itemKey,
    }) async {
      final captured = <String, ItemView<String, String, String>>{};
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: sections,
            itemsOf: (s) => items[s] ?? const [],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) => Text("H:${view.section}"),
            itemBuilder: (ctx, view) {
              captured[view.key] = view;
              return Text("I:${view.item}");
            },
            animationDuration: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return captured[itemKey]!;
    }

    testWidgets("ItemView.update writes through to the controller",
        (tester) async {
      final view = await captureItemView(
        tester,
        sections: ["a"],
        items: {"a": ["a1"]},
        itemKey: "a1",
      );
      view.update("a1!");
      expect(view.controller.getItem("a1"), equals("a1!"));
    });

    testWidgets(
        "ItemView.moveTo (section + index) → moveItem(toSection, index)",
        (tester) async {
      final view = await captureItemView(
        tester,
        sections: ["a", "b"],
        items: {
          "a": ["a1", "a2"],
          "b": ["b1"],
        },
        itemKey: "a1",
      );
      view.moveTo(section: "b", index: 0);
      expect(view.controller.itemKeysOf("a"), equals(["a2"]));
      expect(view.controller.itemKeysOf("b"), equals(["a1", "b1"]));
    });

    testWidgets("ItemView.moveTo (section only) → moveItem appends",
        (tester) async {
      final view = await captureItemView(
        tester,
        sections: ["a", "b"],
        items: {
          "a": ["a1"],
          "b": ["b1"],
        },
        itemKey: "a1",
      );
      view.moveTo(section: "b");
      expect(view.controller.itemKeysOf("a"), isEmpty);
      expect(view.controller.itemKeysOf("b"), equals(["b1", "a1"]));
    });

    testWidgets("ItemView.moveTo (index only) → in-section reorder",
        (tester) async {
      final view = await captureItemView(
        tester,
        sections: ["a"],
        items: {"a": ["a1", "a2", "a3"]},
        itemKey: "a1",
      );
      view.moveTo(index: 2);
      expect(view.controller.itemKeysOf("a"), equals(["a2", "a3", "a1"]));
    });

    testWidgets("ItemView.moveTo (both null) → no-op", (tester) async {
      final view = await captureItemView(
        tester,
        sections: ["a"],
        items: {"a": ["a1", "a2"]},
        itemKey: "a1",
      );
      view.moveTo();
      expect(view.controller.itemKeysOf("a"), equals(["a1", "a2"]));
    });

    testWidgets("ItemView.remove writes through", (tester) async {
      final view = await captureItemView(
        tester,
        sections: ["a"],
        items: {"a": ["a1"]},
        itemKey: "a1",
      );
      view.remove(animate: false);
      expect(view.controller.hasItem("a1"), isFalse);
    });

    testWidgets(
        "SectionView expand/collapse pass through despite isCollapsible:false",
        (tester) async {
      late SectionView<String, String, String> view;
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a"],
            itemsOf: (_) => const ["a1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            collapsible: false, // isCollapsible == false
            headerBuilder: (ctx, v) {
              view = v;
              return Text("H:${v.section} c=${v.isCollapsible}");
            },
            itemBuilder: (ctx, v) => Text("I:${v.item}"),
            animationDuration: Duration.zero,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(view.isCollapsible, isFalse);
      expect(find.text("H:a c=false"), findsOneWidget);
      // collapsible:false force-expands; expand/collapse still pass through.
      view.collapse(animate: false);
      expect(view.controller.isExpanded("a"), isFalse);
      view.expand(animate: false);
      expect(view.controller.isExpanded("a"), isTrue);
    });
  });

  group("SectionedSliverList — watch", () {
    testWidgets("SectionView.watch rebuilds on expand/collapse only",
        (tester) async {
      late SectionedListController<String, String, String> controller;
      var headerBuilds = 0;
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a"],
            itemsOf: (_) => const ["a1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            initiallyExpanded: false,
            headerBuilder: (ctx, view) {
              controller = view.controller;
              return view.watch(
                builder: (ctx, v) {
                  headerBuilds++;
                  return Text(
                    "${v.section} ${v.isExpanded ? 'open' : 'closed'}",
                  );
                },
              );
            },
            itemBuilder: (ctx, view) => Text(view.item),
            animationDuration: Duration.zero,
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
      late SectionedListController<String, String, String> controller;
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a"],
            itemsOf: (_) => const ["a1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) {
              controller = view.controller;
              return view.watch(
                builder: (ctx, v) => Text("${v.section}: ${v.itemCount}"),
              );
            },
            itemBuilder: (ctx, view) => Text(view.item),
            animationDuration: Duration.zero,
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
      late SectionedListController<String, String, String> controller;
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
            sections: const ["a"],
            itemsOf: (_) => const ["v1"],
            sectionKeyOf: (s) => s,
            itemKeyOf: (i) => i,
            headerBuilder: (ctx, view) {
              controller = view.controller;
              return Text(view.section);
            },
            itemBuilder: (ctx, view) =>
                view.watch(builder: (ctx, v) => Text("item:${v.item}")),
            animationDuration: Duration.zero,
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
        late SectionedListController<String, String, String> controller;
        final builds = <String, int>{"a1": 0, "a2": 0};
        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String>(
              sections: const ["a"],
              itemsOf: (_) => const ["a1", "a2"],
              sectionKeyOf: (s) => s,
              itemKeyOf: (i) => i,
              headerBuilder: (ctx, view) {
                controller = view.controller;
                return Text(view.section);
              },
              itemBuilder: (ctx, view) => view.watch(
                builder: (ctx, v) {
                  builds[v.key] = (builds[v.key] ?? 0) + 1;
                  return Text("item:${v.item}");
                },
              ),
              animationDuration: Duration.zero,
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
    testWidgets("itemIndent offsets item rows and propagates on rebuild",
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
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
      // Items live one depth below their header, so their painted
      // cross-axis offset is exactly one itemIndent past the header.
      final headerX = tester.getTopLeft(find.text("a")).dx;
      expect(
        tester.getTopLeft(find.text("a1")).dx - headerX,
        equals(24.0),
      );

      // didUpdateWidget should propagate a new itemIndent.
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String>(
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
      await tester.pump();
      expect(
        tester.getTopLeft(find.text("a1")).dx - headerX,
        equals(32.0),
      );
    });
  });
}
