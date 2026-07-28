/// T5 tests: opt-in drag haptics, debounced on SEMANTIC SLOT identity.
///
/// The F4 audit finding drives the central assertion: the reorder
/// controller's coalesced channel fires on same-slot EXPRESSION changes
/// (targetKey/zone/painted geometry differ while `(parentKey, index)` is
/// unchanged), so a haptic keyed to raw notifications would buzz while
/// the gap stands still. The haptic must fire only on lift and on actual
/// slot changes.
///
/// Repro-test methodology: every haptic expectation fails on pre-T5 code
/// (no haptics exist).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "hapticsOnDrag: one click on lift, one per SLOT change, none on "
    "same-slot expression changes or micro-moves",
    (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == "HapticFeedback.vibrate") {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      tree.setRoots([
        for (var i = 0; i < 5; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
        // Flat policy: crossed rows use the two-zone split, and the
        // same-slot expression boundary below is easy to construct.
        canAcceptDrop: ({required movingKey, newParent, index}) =>
            newParent == null,
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
        reorder.dispose();
        tree.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  makeRoomOnDrag: true,
                  showDragProxy: true,
                  hapticsOnDrag: true,
                  nodeBuilder: (context, key, depth, wrap) {
                    return wrap(
                      longPressToDrag: true,
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lift r0 (center grab → probeDy 0, probe = pointer).
      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(reorder.isDragging, isTrue, reason: "setup: lifted");
      expect(haptics.length, 1, reason: "one click on lift");

      // Micro-move within the same zone: no notification, no haptic.
      await gesture.moveTo(const Offset(400, 26));
      await tester.pump();
      expect(haptics.length, 1, reason: "micro-moves are silent");

      // Same-slot EXPRESSION change (F4): moving within r0/r1's upper
      // region flips between above-r1 / self expressions of the SAME
      // current-position slot — the coalesced channel notifies, the
      // haptic must not.
      await gesture.moveTo(const Offset(400, 55));
      await tester.pump();
      expect(
        reorder.currentTarget?.indexInFinalList,
        0,
        reason: "setup: still the current-position slot",
      );
      expect(haptics.length, 1,
          reason: "same-slot expression changes must be silent — a raw "
              "notification listener would buzz here");

      // Real slot change: cross r1's midpoint.
      await gesture.moveTo(const Offset(400, 77));
      await tester.pump();
      expect(reorder.currentTarget?.indexInFinalList, 1,
          reason: "setup: the slot flipped");
      expect(haptics.length, 2, reason: "one click per slot change");

      // Next slot.
      await gesture.moveTo(const Offset(400, 127));
      await tester.pump();
      expect(reorder.currentTarget?.indexInFinalList, 2,
          reason: "setup: flipped again");
      expect(haptics.length, 3);

      // Drop: no extra click.
      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(haptics.length, 3, reason: "release itself is silent");
    },
  );

  testWidgets(
    "a mid-flight hapticsOnDrag toggle cannot swallow the next lift",
    (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == "HapticFeedback.vibrate") {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      tree.setRoots([
        for (var i = 0; i < 3; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
        reorder.dispose();
        tree.dispose();
      });

      final hapticsEnabled = ValueNotifier<bool>(true);
      addTearDown(hapticsEnabled.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: hapticsEnabled,
              builder: (context, enabled, _) => CustomScrollView(
                slivers: [
                  SliverReorderableTree<String, String>(
                    controller: tree,
                    reorderController: reorder,
                    hapticsOnDrag: enabled,
                    nodeBuilder: (context, key, depth, wrap) {
                      return wrap(
                        longPressToDrag: true,
                        child: SizedBox(
                          key: ValueKey("row-$key"),
                          height: 50,
                          child: Text(key),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag 1: lift with haptics ON, then disable MID-FLIGHT and end.
      var gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(haptics.length, 1, reason: "setup: lift click fired");
      hapticsEnabled.value = false;
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();

      // Drag 2: re-enable and lift again — the stale mid-flight state
      // must not swallow this lift.
      hapticsEnabled.value = true;
      await tester.pump();
      gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(haptics.length, 2,
          reason: "the second session's lift must click — stale "
              "_hapticsDragging from the disabled window would swallow "
              "it");
      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets("haptics are off by default", (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == "HapticFeedback.vibrate") {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final tree = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    tree.setRoots([
      for (var i = 0; i < 3; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    addTearDown(() {
      if (reorder.isDragging) {
        reorder.cancelDrag();
      }
      reorder.dispose();
      tree.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverReorderableTree<String, String>(
                controller: tree,
                reorderController: reorder,
                nodeBuilder: (context, key, depth, wrap) {
                  return wrap(
                    longPressToDrag: true,
                    child: SizedBox(
                      key: ValueKey("row-$key"),
                      height: 50,
                      child: Text(key),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 25));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 145));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(haptics, isEmpty, reason: "opt-in only");
  });
}
