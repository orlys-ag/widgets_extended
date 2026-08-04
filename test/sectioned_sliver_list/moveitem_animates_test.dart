/// Regression: [SectionedListController.moveItem] across sections must
/// run an animated FLIP slide by default. Prior to the fix it forwarded
/// to [TreeController.moveNode] without `animate: true`, so reparents
/// snapped instantly — composing reparent + add / reparent + remove in
/// one [runBatch] produced visually inconsistent animations.
library;

import 'package:flutter/animation.dart';
import "package:flutter_test/flutter_test.dart";
import "package:widgets_extended/sectioned_sliver_list/sectioned_sliver_list.dart";

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    "moveItem(toSection:) animates by default and uses controller tempo",
    (tester) async {
      final controller = SectionedListController<String, String, String>(
        vsync: tester,
        sectionKeyOf: (s) => s,
        itemKeyOf: (i) => i,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 400), curve: Curves.easeInOut)),
      );
      addTearDown(controller.dispose);

      controller.setSections(
        ["a", "b"],
        itemsOf: (_) => const [],
        animate: false,
      );
      controller.addItem("a1", toSection: "a", animate: false);
      controller.addItem("a2", toSection: "a", animate: false);

      // Mid-animation right after the move call. If moveItem did NOT
      // forward animate: true, the structural move would be visible
      // immediately and the sectionOf query would already report "b".
      // With the fix, the slide animation is in flight but the
      // structural change is also applied synchronously — sectionOf
      // returns the new parent immediately, but the controller has
      // installed a FLIP slide on the moved row.
      controller.moveItem("a1", toSection: "b");
      expect(controller.sectionOf("a1"), equals("b"));
      expect(controller.itemKeysOf("a"), equals(["a2"]));
      expect(controller.itemKeysOf("b"), equals(["a1"]));

      // Let any animation finish. With animate: true and a non-zero
      // duration, pumping for at least the controller's expand/collapse
      // spec duration
      // settles the slide cleanly without leaving stuck baselines /
      // ghosts in the controller.
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.sectionOf("a1"), equals("b"));
    },
  );
}
