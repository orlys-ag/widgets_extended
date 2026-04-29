import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sectioned_sliver_list/section_input.dart';
import 'package:widgets_extended/sectioned_sliver_list/sectioned_list_controller.dart';

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
  group("SectionedListController", () {
    testWidgets("setSections seeds sections and items in order", (
      tester,
    ) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([
        _section("a", "A", [_item("a1", "A1"), _item("a2", "A2")]),
        _section("b", "B", [_item("b1", "B1")]),
      ]);

      expect(controller.sections, equals(["a", "b"]));
      expect(controller.itemsOf("a"), equals(["a1", "a2"]));
      expect(controller.itemsOf("b"), equals(["b1"]));
      expect(controller.itemsOf("missing"), isEmpty);
      expect(controller.hasSection("a"), isTrue);
      expect(controller.hasSection("missing"), isFalse);
      expect(controller.itemCount("a"), equals(2));
      expect(controller.getSection("a"), equals("A"));
      expect(controller.getItem("a1"), equals("A1"));
      expect(controller.sectionOf("a1"), equals("a"));
      expect(controller.getSection("missing"), isNull);
      expect(controller.getItem("missing"), isNull);
      expect(controller.sectionOf("missing"), isNull);
    });

    testWidgets("addSection inserts at index", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([_section("a", "A"), _section("c", "C")]);
      controller.addSection(_section("b", "B"), index: 1);

      expect(controller.sections, equals(["a", "b", "c"]));
    });

    testWidgets("addItem / removeItem / updateItem / moveItem", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([_section("a", "A"), _section("b", "B")]);

      controller.addItem("a", _item("a1", "A1"));
      controller.addItem("a", _item("a2", "A2"));
      expect(controller.itemsOf("a"), equals(["a1", "a2"]));

      controller.updateItem("a1", "A1!");
      expect(controller.getItem("a1"), equals("A1!"));

      controller.moveItem("a1", toSection: "b");
      expect(controller.itemsOf("a"), equals(["a2"]));
      expect(controller.itemsOf("b"), equals(["a1"]));
      expect(controller.sectionOf("a1"), equals("b"));

      controller.removeItem("a1");
      expect(controller.itemsOf("b"), isEmpty);
    });

    testWidgets("setItems diffs against current children", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([
        _section("a", "A", [_item("x", "X"), _item("y", "Y")]),
      ]);

      controller.setItems("a", [_item("y", "Y"), _item("z", "Z")]);
      expect(controller.itemsOf("a"), equals(["y", "z"]));
    });

    testWidgets("reorderSections / moveSection", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([
        _section("a", "A"),
        _section("b", "B"),
        _section("c", "C"),
        _section("d", "D"),
      ]);

      controller.reorderSections(["d", "c", "b", "a"]);
      expect(controller.sections, equals(["d", "c", "b", "a"]));

      controller.moveSection("a", 0);
      expect(controller.sections, equals(["a", "d", "c", "b"]));

      controller.moveSection("a", 99); // clamps
      expect(controller.sections, equals(["d", "c", "b", "a"]));
    });

    testWidgets("reorderItems / moveItemInSection", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([
        _section("a", "A", [_item("1", "1"), _item("2", "2"), _item("3", "3")]),
      ]);

      controller.reorderItems("a", ["3", "2", "1"]);
      expect(controller.itemsOf("a"), equals(["3", "2", "1"]));

      controller.moveItemInSection("1", 0);
      expect(controller.itemsOf("a"), equals(["1", "3", "2"]));
    });

    testWidgets("expandSection / collapseSection / isExpanded", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([
        _section("a", "A", [_item("x", "X")]),
      ]);

      expect(controller.isExpanded("a"), isFalse);
      controller.expandSection("a");
      expect(controller.isExpanded("a"), isTrue);
      controller.collapseSection("a");
      expect(controller.isExpanded("a"), isFalse);
      controller.toggleSection("a");
      expect(controller.isExpanded("a"), isTrue);
      expect(controller.isExpanded("missing"), isFalse);
    });

    testWidgets("missing-key throws / asserts uniformly", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([_section("a", "A")]);

      expect(
        () => controller.removeSection("nope"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.updateSection("nope", "x"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.setItems("nope", []),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.addItem("nope", _item("x", "X")),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.removeItem("nope"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.updateItem("nope", "x"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.moveItem("nope", toSection: "a"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.moveSection("nope", 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.moveItemInSection("nope", 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.expandSection("nope"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.collapseSection("nope"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.toggleSection("nope"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.reorderItems("nope", []),
        throwsA(isA<AssertionError>()),
      );
    });

    testWidgets("runBatch coalesces multiple mutations into one notification", (
      tester,
    ) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([_section("a", "A")]);

      var notifications = 0;
      void onChange() {
        notifications++;
      }

      controller.treeController.addListener(onChange);
      addTearDown(() {
        controller.treeController.removeListener(onChange);
      });

      controller.runBatch(() {
        controller.addItem("a", _item("1", "1"));
        controller.addItem("a", _item("2", "2"));
        controller.addItem("a", _item("3", "3"));
      });

      expect(notifications, equals(1));
    });

    testWidgets("dispose is idempotent", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      controller.dispose();
      expect(controller.dispose, returnsNormally);
    });

    testWidgets("section/item key disjointness with SKey == IKey", (
      tester,
    ) async {
      // Section "x" and item "x" must not collide.
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.setSections([
        _section("x", "section x", [_item("x", "item x")]),
      ]);

      expect(controller.hasSection("x"), isTrue);
      expect(controller.getSection("x"), equals("section x"));
      expect(controller.getItem("x"), equals("item x"));
      expect(controller.itemsOf("x"), equals(["x"]));
      expect(controller.sectionOf("x"), equals("x"));
    });

    testWidgets("debugBindWidget asserts on second binding", (tester) async {
      final controller =
          SectionedListController<String, String, String, String>(
            vsync: tester,
            animationDuration: Duration.zero,
          );
      addTearDown(controller.dispose);

      controller.debugBindWidget();
      expect(
        () => controller.debugBindWidget(),
        throwsA(isA<AssertionError>()),
      );
      controller.debugUnbindWidget();
      // After unbinding, can bind again.
      expect(() => controller.debugBindWidget(), returnsNormally);
      controller.debugUnbindWidget();
    });
  });
}
