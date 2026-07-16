import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

// Audit repro for finding f3:
//
// insert() and setChildren() guard against a pending-deletion parent with
// an `assert` only (tree_controller.dart:1957-1962 and 1797-1802), while
// moveNode() enforces the identical precondition with a runtime
// `throw StateError` in ALL build modes -- and moveNode's comment claims it
// merely mirrors "the policy insert(parentKey:) already enforces". Asserts
// are stripped in release builds, so exactly the corruption moveNode's
// comment warns about is reachable in production: a child inserted under a
// mid-exit parent is not itself pending-deletion, survives the parent's
// purge with a dangling parent nid, and leaks its registry entry forever.
//
// EXPECTED (correct) behavior asserted here: both mutators reject a
// pending-deletion parent with a runtime error that exists in release
// builds -- StateError (matching moveNode's policy) or ArgumentError (the
// alternative named in the suggested fix). A debug-only AssertionError does
// NOT satisfy this expectation. On unfixed code these tests fail because
// the guard fires as an AssertionError, proving it is assert-only.

void main() {
  late TreeController<String, String> controller;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  final Matcher throwsRuntimeGuardError = throwsA(
    anyOf(isA<StateError>(), isA<ArgumentError>()),
  );

  group("f3: pending-deletion parent guard must be a runtime check", () {
    testWidgets(
      "insert() under a mid-exit parent throws StateError (not a debug-only "
      "assert), matching moveNode's all-build-modes policy",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 100),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.expand(key: "a", animate: false);
        await tester.pump();

        // Start an animated remove; "a" is now mid-exit (pending deletion).
        controller.remove(key: "a", animate: true);
        await tester.pump(const Duration(milliseconds: 20));

        // Sanity: the scenario's precondition holds -- the parent is inside
        // its exit window, so the guard under test is actually reached.
        expect(
          controller.isPendingDeletion("a"),
          isTrue,
          reason: "test setup must place 'a' in its animated exit window",
        );

        // Correct behavior: reject with a runtime error present in release
        // builds. On unfixed code this throws AssertionError instead,
        // which matches neither StateError nor ArgumentError.
        expect(
          () => controller.insert(
            parentKey: "a",
            node: TreeNode(key: "x", data: "X"),
          ),
          throwsRuntimeGuardError,
          reason: "insert() under a pending-deletion parent must throw a "
              "runtime StateError/ArgumentError in all build modes, as "
              "moveNode's guard comment claims it already does; an "
              "assert-only guard silently corrupts state in release",
        );

        // Let the exit animation finish (bounded pumps, no pumpAndSettle).
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      "setChildren() on a mid-exit parent throws StateError (not a "
      "debug-only assert), matching moveNode's all-build-modes policy",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 100),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.expand(key: "a", animate: false);
        await tester.pump();

        controller.remove(key: "a", animate: true);
        await tester.pump(const Duration(milliseconds: 20));

        expect(
          controller.isPendingDeletion("a"),
          isTrue,
          reason: "test setup must place 'a' in its animated exit window",
        );

        expect(
          () => controller.setChildren("a", [TreeNode(key: "x", data: "X")]),
          throwsRuntimeGuardError,
          reason: "setChildren() on a pending-deletion parent must throw a "
              "runtime StateError/ArgumentError in all build modes; an "
              "assert-only guard silently orphans the new children and "
              "leaks their registry entries in release",
        );

        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
