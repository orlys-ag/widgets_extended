import "package:flutter_test/flutter_test.dart";
import "package:widgets_extended/sliver_tree/tree_controller.dart";
import "package:widgets_extended/sliver_tree/tree_sync_controller.dart";
import "package:widgets_extended/sliver_tree/types.dart";

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("TreeController.runBatch", () {
    testWidgets("coalesces many structural mutations into one notification",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "a", data: "A")]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.runBatch(() {
        for (int i = 0; i < 50; i++) {
          controller.insertRoot(TreeNode(key: "r$i", data: "R$i"));
        }
      });

      expect(notifyCount, 1, reason: "50 inserts should coalesce into 1 notify");
      // And the mutations actually applied.
      expect(controller.rootCount, 51);
    });

    testWidgets("nested runBatch fires exactly once at outermost exit",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "a", data: "A")]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.runBatch(() {
        controller.insertRoot(TreeNode(key: "b", data: "B"));
        controller.runBatch(() {
          controller.insertRoot(TreeNode(key: "c", data: "C"));
          controller.runBatch(() {
            controller.insertRoot(TreeNode(key: "d", data: "D"));
          });
          controller.insertRoot(TreeNode(key: "e", data: "E"));
        });
        controller.insertRoot(TreeNode(key: "f", data: "F"));
      });

      expect(notifyCount, 1);
      expect(controller.rootCount, 6);
    });

    testWidgets("fires notification even when body throws", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "a", data: "A")]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      expect(
        () => controller.runBatch(() {
          controller.insertRoot(TreeNode(key: "b", data: "B"));
          controller.insertRoot(TreeNode(key: "c", data: "C"));
          throw StateError("boom");
        }),
        throwsStateError,
      );

      expect(notifyCount, 1,
          reason: "partial mutations still committed must notify listeners");
      expect(controller.rootCount, 3);
    });

    testWidgets("empty runBatch fires zero notifications", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "a", data: "A")]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.runBatch(() {});

      expect(notifyCount, 0);
    });

    testWidgets("runBatch returns body's value", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      final result = controller.runBatch<String>(() {
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        return "ok";
      });

      expect(result, "ok");
    });

    testWidgets("does not suppress animation tick listeners", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);

      int structuralNotifyCount = 0;
      int animationTickCount = 0;
      controller.addListener(() => structuralNotifyCount++);
      controller.addAnimationListener(() => animationTickCount++);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);

      final preBatchStructural = structuralNotifyCount;

      controller.runBatch(() {
        controller.expand(key: "a");
      });

      expect(structuralNotifyCount, preBatchStructural + 1);
      // Pump animation frames; animation listener should fire for ticks
      // regardless of batching.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(animationTickCount, greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets(
        "animation completion inside runBatch coalesces with batch notify",
        (tester) async {
      // When a zero-duration expand completes synchronously inside the
      // batch body, the completion-path _notifyStructural must also be
      // suppressed rather than firing a second notification.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.runBatch(() {
        controller.expand(key: "a");
        controller.collapse(key: "a");
        controller.expand(key: "a");
      });

      expect(notifyCount, 1);
    });
  });

  group("TreeSyncController batching", () {
    testWidgets("syncRoots with many mutations fires one notification",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      // Seed.
      sync.syncRoots([
        for (int i = 0; i < 10; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Replace the entire root set — forces 10 removes + 10 inserts.
      sync.syncRoots([
        for (int i = 10; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      expect(notifyCount, 1,
          reason: "20 mutations should coalesce into 1 notify");
      expect(controller.rootCount, 10);
    });

    testWidgets(
        "syncRoots with childrenOf recurses into one batch",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      sync.syncRoots(
        [
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ],
        childrenOf: (k) {
          if (k == "a") {
            return [
              TreeNode(key: "a1", data: "A1"),
              TreeNode(key: "a2", data: "A2"),
            ];
          }
          if (k == "b") {
            return [TreeNode(key: "b1", data: "B1")];
          }
          return const [];
        },
      );

      expect(notifyCount, 1,
          reason: "recursive syncRoots should fire exactly 1 notify");
    });

    testWidgets("syncChildren on unknown parent fires zero notifications",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      sync.syncChildren("ghost", [TreeNode(key: "x", data: "X")]);

      expect(notifyCount, 0,
          reason: "syncChildren on unknown parent should early-return "
              "without opening a batch that fires a spurious notify");
    });

    testWidgets(
        "syncMultipleChildren coalesces reparenting into one notification",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      sync.syncRoots(
        [TreeNode(key: "a", data: "A"), TreeNode(key: "b", data: "B")],
        childrenOf: (k) {
          if (k == "a") {
            return [TreeNode(key: "x", data: "X")];
          }
          return const [];
        },
      );
      // Pre-condition: x is under a.
      expect(controller.getParent("x"), "a");

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      // Reparent x from a to b.
      sync.syncMultipleChildren({
        "a": const [],
        "b": [TreeNode(key: "x", data: "X")],
      });

      expect(notifyCount, 1);
      expect(controller.getParent("x"), "b");
    });
  });
}
