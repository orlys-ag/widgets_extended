/// Regression tests for audit item 2.3: a cyclic or DAG-shaped
/// `childrenOf` passed to raw [TreeSyncController.syncRoots] (or
/// `SyncedSliverTree.nodes`, which routes through it) must throw
/// [ArgumentError] instead of hanging the UI thread (cycle) or walking
/// exponentially into last-write-wins thrash (DAG).
///
/// Four of five `SyncedSliverTree` input modes already validate this;
/// the `.nodes` mode and direct `syncRoots(childrenOf:)` callers got no
/// validation at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "syncRoots with a cyclic childrenOf throws ArgumentError instead of "
    "hanging",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // a -> b -> a: an infinite loop on unguarded DFS walks.
      List<TreeNode<String, String>> childrenOf(String key) {
        return switch (key) {
          "a" => const [TreeNode(key: "b", data: "B")],
          "b" => const [TreeNode(key: "a", data: "A")],
          _ => const <TreeNode<String, String>>[],
        };
      }

      expect(
        () => sync.syncRoots(
          [const TreeNode(key: "a", data: "A")],
          childrenOf: childrenOf,
          animate: false,
        ),
        // R7: match the guard's actual key-naming fragment — a bare
        // contains("a") matched virtually any English error text and
        // added zero discrimination over isA<ArgumentError>().
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          "message",
          contains("involving key \"a\""),
        )),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    "syncRoots with a DAG childrenOf (same key under two parents) throws "
    "ArgumentError",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // x appears under both a and b — last-write-wins thrash on
      // unguarded walks.
      List<TreeNode<String, String>> childrenOf(String key) {
        return switch (key) {
          "a" => const [TreeNode(key: "x", data: "X")],
          "b" => const [TreeNode(key: "x", data: "X")],
          _ => const <TreeNode<String, String>>[],
        };
      }

      expect(
        () => sync.syncRoots(
          [
            const TreeNode(key: "a", data: "A"),
            const TreeNode(key: "b", data: "B"),
          ],
          childrenOf: childrenOf,
          animate: false,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          "message",
          contains("involving key \"x\""),
        )),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    "syncRoots with a key that is both a root and a child throws "
    "ArgumentError",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // b is a desired root AND a child of a.
      List<TreeNode<String, String>> childrenOf(String key) {
        return switch (key) {
          "a" => const [TreeNode(key: "b", data: "B")],
          _ => const <TreeNode<String, String>>[],
        };
      }

      expect(
        () => sync.syncRoots(
          [
            const TreeNode(key: "a", data: "A"),
            const TreeNode(key: "b", data: "B"),
          ],
          childrenOf: childrenOf,
          animate: false,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          "message",
          contains("involving key \"b\""),
        )),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
