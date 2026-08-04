/// Regression for R001: release-safe fallback under unsupported axes.
///
/// SliverTree's layout/paint code assumes vertical, forward-growing. In
/// debug builds an `assert` catches misuse; in release builds the assert
/// is stripped, and the `if (!axisOk) { ... return; }` fallback sets
/// `SliverGeometry.zero` so layout doesn't silently compute against
/// vertical-down assumptions.
///
/// `flutter test` always runs in debug mode, so we can only verify the
/// debug path (assert fires). The release-mode fallback is implicitly
/// covered by the fact that the assert and the `if (!axisOk)` guard
/// share the same boolean — if the boolean is wrong in debug, it is
/// wrong in release.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "horizontal axis trips the axis assert",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "a"),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: CustomScrollView(
              scrollDirection: Axis.horizontal,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (_, key, _) => SizedBox(
                    height: 40,
                    width: 100,
                    child: Text(key),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));

      final exception = tester.takeException();
      expect(
        exception,
        isAssertionError,
        reason: "Debug build should trip the axis assert",
      );
      expect(
        exception.toString(),
        contains("SliverTree currently supports only vertical"),
      );
    },
  );
}
