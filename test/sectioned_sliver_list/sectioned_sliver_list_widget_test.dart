import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Widget _wrap(Widget sliver) {
  return MaterialApp(
    home: Scaffold(body: CustomScrollView(slivers: [sliver])),
  );
}

SectionInput<String, String, String, String> _section(
  String key,
  String header, [
  List<ItemInput<String, String>> items = const [],
]) {
  return SectionInput<String, String, String, String>(
    key: key,
    section: header,
    items: items,
  );
}

ItemInput<String, String> _item(String key, String label) {
  return ItemInput<String, String>(key: key, item: label);
}

void main() {
  group("SectionedSliverList — declarative", () {
    testWidgets("renders sections and items in order", (tester) async {
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>(
            sections: [
              _section("a", "Section A", [
                _item("a1", "Item A1"),
                _item("a2", "Item A2"),
              ]),
              _section("b", "Section B", [_item("b1", "Item B1")]),
            ],
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("Section A"), findsOneWidget);
      expect(find.text("Item A1"), findsOneWidget);
      expect(find.text("Item A2"), findsOneWidget);
      expect(find.text("Section B"), findsOneWidget);
      expect(find.text("Item B1"), findsOneWidget);
    });

    testWidgets("respects initiallyExpanded: false", (tester) async {
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>(
            sections: [
              _section("a", "Section A", [_item("a1", "Item A1")]),
            ],
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
            initiallyExpanded: false,
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("Section A"), findsOneWidget);
      expect(find.text("Item A1"), findsNothing);
    });

    testWidgets("initialSectionExpansion overrides per section", (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>(
            sections: [
              _section("a", "Section A", [_item("a1", "Item A1")]),
              _section("b", "Section B", [_item("b1", "Item B1")]),
            ],
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
            initiallyExpanded: true,
            initialSectionExpansion: (key, _) => key == "a" ? false : null,
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("Item A1"), findsNothing);
      expect(find.text("Item B1"), findsOneWidget);
    });

    testWidgets("hideEmptySections filters input", (tester) async {
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>(
            sections: [
              _section("a", "Section A", [_item("a1", "Item A1")]),
              _section("b", "Section B"),
              _section("c", "Section C", [_item("c1", "Item C1")]),
            ],
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
            hideEmptySections: true,
            animationDuration: Duration.zero,
          ),
        ),
      );

      expect(find.text("Section A"), findsOneWidget);
      expect(find.text("Section B"), findsNothing);
      expect(find.text("Section C"), findsOneWidget);
    });

    testWidgets("declarative rebuild diffs with animations", (tester) async {
      Widget build(
        List<SectionInput<String, String, String, String>> sections,
      ) {
        return _wrap(
          SectionedSliverList<String, String, String, String>(
            sections: sections,
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
            animationDuration: Duration.zero,
          ),
        );
      }

      await tester.pumpWidget(
        build([
          _section("a", "A", [_item("a1", "A1")]),
        ]),
      );
      expect(find.text("A1"), findsOneWidget);

      await tester.pumpWidget(
        build([
          _section("a", "A", [_item("a1", "A1"), _item("a2", "A2")]),
        ]),
      );
      await tester.pump();
      expect(find.text("A2"), findsOneWidget);
    });
  });

  group("SectionedSliverList.grouped", () {
    testWidgets("renders from a Map<Section, List<Item>>", (tester) async {
      final grouped = <String, List<String>>{
        "Folder A": ["a1", "a2"],
        "Folder B": ["b1"],
      };
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>.grouped(
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

  group("SectionedSliverList — controller integration", () {
    testWidgets(
      "external controller wires through and exposes itself via GlobalKey",
      (tester) async {
        final key =
            GlobalKey<
              SectionedSliverListState<String, String, String, String>
            >();
        final controller =
            SectionedListController<String, String, String, String>(
              vsync: tester,
              animationDuration: Duration.zero,
            );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String, String>(
              key: key,
              controller: controller,
              sections: [
                _section("a", "A", [_item("a1", "A1")]),
              ],
              headerBuilder: (ctx, view) => Text(view.section),
              itemBuilder: (ctx, view) => Text(view.item),
            ),
          ),
        );

        expect(key.currentState?.controller, same(controller));
        expect(controller.sections, equals(["a"]));
        expect(controller.itemsOf("a"), equals(["a1"]));

        controller.addItem("a", _item("a2", "A2"));
        await tester.pumpAndSettle();
        expect(find.text("A2"), findsOneWidget);
      },
    );

    testWidgets("internal controller is disposed; external is NOT", (
      tester,
    ) async {
      final external = SectionedListController<String, String, String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(external.dispose);

      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>(
            controller: external,
            sections: [_section("a", "A")],
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());

      // External must still be usable.
      expect(() => external.hasSection("a"), returnsNormally);
    });

    testWidgets("source-of-truth: parent rebuild overrides controller drift", (
      tester,
    ) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      Widget build(
        List<SectionInput<String, String, String, String>> sections,
      ) {
        return _wrap(
          SectionedSliverList<String, String, String, String>(
            controller: controller,
            sections: sections,
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
          ),
        );
      }

      await tester.pumpWidget(
        build([
          _section("a", "A", [_item("a1", "A1")]),
        ]),
      );
      controller.addItem("a", _item("a2", "A2"));
      await tester.pumpAndSettle();
      expect(controller.itemsOf("a"), equals(["a1", "a2"]));

      // Rebuild with new sections that doesn't include a2.
      await tester.pumpWidget(
        build([
          _section("a", "A", [_item("a1", "A1")]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(controller.itemsOf("a"), equals(["a1"]));
    });

    testWidgets("controller swap re-syncs from sections", (tester) async {
      final c1 = SectionedListController<String, String, String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final c2 = SectionedListController<String, String, String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(c1.dispose);
      addTearDown(c2.dispose);

      Widget build(SectionedListController<String, String, String, String>? c) {
        return _wrap(
          SectionedSliverList<String, String, String, String>(
            controller: c,
            sections: [
              _section("a", "A", [_item("a1", "A1")]),
            ],
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) => Text(view.item),
          ),
        );
      }

      await tester.pumpWidget(build(c1));
      expect(c1.sections, equals(["a"]));

      await tester.pumpWidget(build(c2));
      await tester.pumpAndSettle();
      expect(c2.sections, equals(["a"]));
      expect(c2.itemsOf("a"), equals(["a1"]));
    });
  });

  group("SectionedSliverList — watch", () {
    testWidgets("SectionView.watch rebuilds on expand/collapse only", (
      tester,
    ) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      var headerBuilds = 0;
      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>(
            controller: controller,
            sections: [
              _section("a", "A", [_item("a1", "A1")]),
            ],
            initiallyExpanded: false,
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
      expect(find.text("A closed"), findsOneWidget);

      controller.expandSection("a");
      await tester.pumpAndSettle();
      expect(find.text("A open"), findsOneWidget);
      expect(headerBuilds, greaterThan(initial));
    });

    testWidgets(
      "SectionView.watch rebuilds on item add/remove (count change)",
      (tester) async {
        final controller =
            SectionedListController<String, String, String, String>(
              vsync: tester,
              animationDuration: Duration.zero,
            );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _wrap(
            SectionedSliverList<String, String, String, String>(
              controller: controller,
              sections: [
                _section("a", "A", [_item("a1", "A1")]),
              ],
              headerBuilder: (ctx, view) => view.watch(
                builder: (ctx, v) => Text("${v.section}: ${v.itemCount}"),
              ),
              itemBuilder: (ctx, view) => Text(view.item),
            ),
          ),
        );
        expect(find.text("A: 1"), findsOneWidget);

        controller.addItem("a", _item("a2", "A2"));
        await tester.pumpAndSettle();
        expect(find.text("A: 2"), findsOneWidget);

        controller.addItem("a", _item("a3", "A3"));
        await tester.pumpAndSettle();
        expect(find.text("A: 3"), findsOneWidget);

        controller.removeItem("a1");
        await tester.pumpAndSettle();
        expect(find.text("A: 2"), findsOneWidget);

        controller.setItems("a", []);
        await tester.pumpAndSettle();
        expect(find.text("A: 0"), findsOneWidget);
      },
    );

    testWidgets("ItemView.watch rebuilds on updateItem", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          SectionedSliverList<String, String, String, String>(
            controller: controller,
            sections: [
              _section("a", "A", [_item("a1", "v1")]),
            ],
            headerBuilder: (ctx, view) => Text(view.section),
            itemBuilder: (ctx, view) =>
                view.watch(builder: (ctx, v) => Text("item:${v.item}")),
          ),
        ),
      );
      expect(find.text("item:v1"), findsOneWidget);

      controller.updateItem("a1", "v2");
      await tester.pumpAndSettle();
      expect(find.text("item:v2"), findsOneWidget);
    });
  });

  testWidgets("SectionedSliverList passes itemIndent through to indentWidth", (
    tester,
  ) async {
    final controller = SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        SectionedSliverList<String, String, String, String>(
          controller: controller,
          sections: [
            _section("a", "A", [_item("a1", "A1")]),
          ],
          itemIndent: 24.0,
          headerBuilder: (ctx, view) => Text(view.section),
          itemBuilder: (ctx, view) => Text(view.item),
        ),
      ),
    );

    expect(controller.treeController.indentWidth, equals(24.0));
  });
}
