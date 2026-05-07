import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sectioned_sliver_list/sectioned_list_controller.dart';

/// Map from section key → item keys for the helpers below. The test
/// uses `Section = String, Item = String, K = String` with identity
/// `sectionKeyOf` / `itemKeyOf` callbacks, so each "key" doubles as
/// the payload.
SectionedListController<String, String, String> _make(WidgetTester tester) {
  return SectionedListController<String, String, String>(
    vsync: tester,
    sectionKeyOf: (s) => s,
    itemKeyOf: (i) => i,
    animationDuration: Duration.zero,
  );
}

void main() {
  group("SectionedListController", () {
    testWidgets("setSections seeds sections and items in order", (
      tester,
    ) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      final byKey = {
        "a": ["a1", "a2"],
        "b": ["b1"],
      };
      controller.setSections(
        ["a", "b"],
        itemsOf: (s) => byKey[s] ?? const [],
      );

      expect(controller.sectionKeys, equals(["a", "b"]));
      expect(controller.sections, equals(["a", "b"]));
      expect(controller.itemKeysOf("a"), equals(["a1", "a2"]));
      expect(controller.itemsOf("a"), equals(["a1", "a2"]));
      expect(controller.itemsOf("b"), equals(["b1"]));
      expect(controller.itemsOf("missing"), isEmpty);
      expect(controller.hasSection("a"), isTrue);
      expect(controller.hasSection("missing"), isFalse);
      expect(controller.itemCount("a"), equals(2));
      expect(controller.getSection("a"), equals("a"));
      expect(controller.getItem("a1"), equals("a1"));
      expect(controller.sectionOf("a1"), equals("a"));
      expect(controller.getSection("missing"), isNull);
      expect(controller.getItem("missing"), isNull);
      expect(controller.sectionOf("missing"), isNull);
    });

    testWidgets("addSection inserts at index", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(["a", "c"], itemsOf: (_) => const []);
      controller.addSection("b", index: 1);

      expect(controller.sectionKeys, equals(["a", "b", "c"]));
    });

    testWidgets("addSection with items populates children", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.addSection("a", items: ["a1", "a2"]);

      expect(controller.sectionKeys, equals(["a"]));
      expect(controller.itemKeysOf("a"), equals(["a1", "a2"]));
    });

    testWidgets("addItem / removeItem / updateItem / moveItem", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(["a", "b"], itemsOf: (_) => const []);

      controller.addItem("a1", toSection: "a");
      controller.addItem("a2", toSection: "a");
      expect(controller.itemKeysOf("a"), equals(["a1", "a2"]));

      controller.updateItem("a1", "a1!");
      expect(controller.getItem("a1"), equals("a1!"));

      controller.moveItem("a1", toSection: "b");
      expect(controller.itemKeysOf("a"), equals(["a2"]));
      expect(controller.itemKeysOf("b"), equals(["a1"]));
      expect(controller.sectionOf("a1"), equals("b"));

      controller.removeItem("a1");
      expect(controller.itemKeysOf("b"), isEmpty);
    });

    testWidgets("setItems diffs against current children", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(
        ["a"],
        itemsOf: (_) => ["x", "y"],
      );

      controller.setItems("a", ["y", "z"]);
      expect(controller.itemKeysOf("a"), equals(["y", "z"]));
    });

    testWidgets("reorderSections / moveSection", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(
        ["a", "b", "c", "d"],
        itemsOf: (_) => const [],
      );

      controller.reorderSections(["d", "c", "b", "a"]);
      expect(controller.sectionKeys, equals(["d", "c", "b", "a"]));

      controller.moveSection("a", 0);
      expect(controller.sectionKeys, equals(["a", "d", "c", "b"]));

      controller.moveSection("a", 99); // clamps
      expect(controller.sectionKeys, equals(["d", "c", "b", "a"]));
    });

    testWidgets("reorderItems / moveItemInSection", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(
        ["a"],
        itemsOf: (_) => ["1", "2", "3"],
      );

      controller.reorderItems("a", ["3", "2", "1"]);
      expect(controller.itemKeysOf("a"), equals(["3", "2", "1"]));

      controller.moveItemInSection("1", 0);
      expect(controller.itemKeysOf("a"), equals(["1", "3", "2"]));
    });

    testWidgets("expandSection / collapseSection / isExpanded", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(["a"], itemsOf: (_) => ["x"]);

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
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(["a"], itemsOf: (_) => const []);

      expect(
        () => controller.removeSection("nope"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.updateSection("nope", "x"),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.setItems("nope", const []),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => controller.addItem("x", toSection: "nope"),
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
        () => controller.reorderItems("nope", const []),
        throwsA(isA<AssertionError>()),
      );
    });

    testWidgets("runBatch coalesces multiple structural mutations into one "
        "addListener fire", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.setSections(["a"], itemsOf: (_) => const []);

      var notifications = 0;
      void onChange() {
        notifications++;
      }

      controller.addListener(onChange);
      addTearDown(() {
        controller.removeListener(onChange);
      });

      controller.runBatch(() {
        controller.addItem("1", toSection: "a");
        controller.addItem("2", toSection: "a");
        controller.addItem("3", toSection: "a");
      });

      expect(notifications, equals(1));
    });

    testWidgets("dispose is idempotent", (tester) async {
      final controller = _make(tester);
      controller.dispose();
      expect(controller.dispose, returnsNormally);
    });

    testWidgets("section/item key disjointness with same string in both "
        "domains", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      // Section "x" with item "x" — must not collide.
      controller.addSection("x", items: ["x"]);

      expect(controller.hasSection("x"), isTrue);
      expect(controller.hasItem("x"), isTrue);
      expect(controller.getSection("x"), equals("x"));
      expect(controller.getItem("x"), equals("x"));
      expect(controller.itemKeysOf("x"), equals(["x"]));
      expect(controller.sectionOf("x"), equals("x"));
    });

    testWidgets("debugBindWidget asserts on second binding", (tester) async {
      final controller = _make(tester);
      addTearDown(controller.dispose);

      controller.debugBindWidget();
      expect(
        () => controller.debugBindWidget(),
        throwsA(isA<AssertionError>()),
      );
      controller.debugUnbindWidget();
      expect(() => controller.debugBindWidget(), returnsNormally);
      controller.debugUnbindWidget();
    });

    testWidgets(
      "addListener does NOT fire on payload-only mutations (updateSection / "
      "updateItem)",
      (tester) async {
        final controller = _make(tester);
        addTearDown(controller.dispose);
        controller.setSections(["a"], itemsOf: (_) => ["a1"]);

        var structuralFires = 0;
        controller.addListener(() {
          structuralFires++;
        });

        controller.updateSection("a", "a");
        controller.updateItem("a1", "a1");

        expect(
          structuralFires,
          equals(0),
          reason: "Listenable.addListener fires on STRUCTURAL changes only. "
              "updateSection / updateItem are payload-only — they go "
              "through the typed payload listeners.",
        );
      },
    );

    testWidgets(
      "typed payload listeners fire only on their domain and only for the "
      "affected key",
      (tester) async {
        final controller = _make(tester);
        addTearDown(controller.dispose);
        controller.setSections(["a", "b"], itemsOf: (s) => ["${s}1", "${s}2"]);

        final sectionFires = <String>[];
        final itemFires = <String>[];
        controller.addSectionPayloadListener(sectionFires.add);
        controller.addItemPayloadListener(itemFires.add);

        controller.updateSection("a", "a");
        expect(sectionFires, equals(["a"]));
        expect(itemFires, isEmpty);

        controller.updateItem("a1", "a1");
        expect(sectionFires, equals(["a"]));
        expect(itemFires, equals(["a1"]));
      },
    );

    testWidgets(
      "typed payload listeners coalesce inside runBatch — multiple updates "
      "for the same key fire once; different keys fire each once",
      (tester) async {
        final controller = _make(tester);
        addTearDown(controller.dispose);
        controller.setSections(["a", "b"], itemsOf: (_) => const ["x", "y"]);

        final itemFires = <String>[];
        controller.addItemPayloadListener(itemFires.add);

        controller.runBatch(() {
          controller.updateItem("x", "x");
          controller.updateItem("x", "x");
          controller.updateItem("x", "x");
          controller.updateItem("y", "y");
        });

        expect(
          itemFires.where((k) => k == "x").length,
          equals(1),
          reason: "Three updateItem calls for 'x' inside runBatch should "
              "fire the listener exactly once at batch exit.",
        );
        expect(
          itemFires.where((k) => k == "y").length,
          equals(1),
        );
      },
    );

    testWidgets(
      "structural firings precede payload firings at runBatch exit",
      (tester) async {
        final controller = _make(tester);
        addTearDown(controller.dispose);
        controller.setSections(["a"], itemsOf: (_) => ["x"]);

        final order = <String>[];
        controller.addListener(() {
          order.add("structural");
        });
        controller.addItemPayloadListener((_) {
          order.add("item-payload");
        });

        controller.runBatch(() {
          controller.addItem("y", toSection: "a"); // structural
          controller.updateItem("x", "x"); // payload
        });

        expect(
          order,
          equals(["structural", "item-payload"]),
          reason: "TreeController.runBatch fires structural listeners "
              "before payload listeners at batch exit.",
        );
      },
    );

    testWidgets(
      "live-by-default queries: sections / itemsOf / sectionKeys / "
      "itemKeysOf exclude pending-deletion, all* include them",
      (tester) async {
        final controller = SectionedListController<String, String, String>(
          vsync: tester,
          sectionKeyOf: (s) => s,
          itemKeyOf: (i) => i,
          animationDuration: const Duration(milliseconds: 200),
        );
        addTearDown(controller.dispose);

        controller.setSections(
          ["a", "b", "c"],
          itemsOf: (s) => s == "a" ? ["a1", "a2", "a3"] : const [],
        );
        controller.expandSection("a", animate: false);

        controller.removeItem("a2", animate: true);
        controller.removeSection("b", animate: true);

        // Mid-animation: pending entries excluded from default queries.
        expect(controller.sectionKeys, equals(["a", "c"]));
        expect(controller.itemKeysOf("a"), equals(["a1", "a3"]));

        // all* variants include pending-deletion.
        expect(controller.allSectionKeys, equals(["a", "b", "c"]));
        expect(controller.allItemKeysOf("a"), equals(["a1", "a2", "a3"]));

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "sync-after-drift: imperative addItem between two setSections doesn't "
      "leave drifted nodes after the second setSections",
      (tester) async {
        // Validates _sync.initializeTracking() being called from
        // setSections — without it, the diff would be computed against
        // the sync controller's stale baseline (state captured before the
        // drift) and fail to remove drifted nodes.
        final controller = _make(tester);
        addTearDown(controller.dispose);

        controller.setSections(["a"], itemsOf: (_) => ["a1"]);

        // Imperative drift outside the sync controller's bookkeeping.
        controller.addItem("a2", toSection: "a");
        expect(controller.itemKeysOf("a"), equals(["a1", "a2"]));

        // Re-sync with input that still only has a1. a2 is drift —
        // must be removed.
        controller.setSections(["a"], itemsOf: (_) => ["a1"]);

        expect(
          controller.itemKeysOf("a"),
          equals(["a1"]),
          reason: "Without _sync.initializeTracking() before syncRoots, "
              "the second setSections diffs against a stale baseline (no "
              "a2) and fails to remove the drifted a2.",
        );
      },
    );

    testWidgets("itemIndent forwards to TreeController.indentWidth",
        (tester) async {
      final controller = SectionedListController<String, String, String>(
        vsync: tester,
        sectionKeyOf: (s) => s,
        itemKeyOf: (i) => i,
        animationDuration: Duration.zero,
        itemIndent: 12.0,
      );
      addTearDown(controller.dispose);

      expect(controller.itemIndent, equals(12.0));
      expect(controller.treeController.indentWidth, equals(12.0));

      controller.itemIndent = 24.0;
      expect(controller.itemIndent, equals(24.0));
      expect(controller.treeController.indentWidth, equals(24.0));
    });
  });
}
