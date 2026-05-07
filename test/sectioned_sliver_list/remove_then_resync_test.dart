/// Regression: deleting a section then re-syncing while the section's
/// exit animation is still in flight must not throw inside reorderRoots.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sectioned_sliver_list/sectioned_list_controller.dart';

SectionedListController<String, String, String> _make(WidgetTester tester) {
  return SectionedListController<String, String, String>(
    vsync: tester,
    sectionKeyOf: (s) => s,
    itemKeyOf: (i) => i,
    animationDuration: const Duration(milliseconds: 100),
  );
}

void main() {
  testWidgets(
    "removeSection followed by resync with all-set mirror survives "
    "mid-animation",
    (tester) async {
      final c = _make(tester);
      addTearDown(c.dispose);

      c.setSections(
        ["a", "b", "c", "d", "e"],
        itemsOf: (_) => const [],
      );
      await tester.pump();

      c.removeSection("c");

      // All-set mirror — includes 'c' which is pending-deletion. This is
      // a less-common pattern in v2 (live-by-default), but valid via
      // allSectionKeys.
      final mirroredKeys = c.allSectionKeys;
      expect(mirroredKeys.length, equals(5));

      // The call that previously threw inside reorderRoots.
      c.setSections(mirroredKeys, itemsOf: (_) => const []);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "removeSection followed by resync with shrunk inputs survives "
    "mid-animation",
    (tester) async {
      final c = _make(tester);
      addTearDown(c.dispose);

      c.setSections(
        ["a", "b", "c", "d", "e"],
        itemsOf: (_) => const [],
      );
      await tester.pump();

      c.removeSection("c");

      // Caller's source-of-truth has dropped 'c'. Re-sync with 4
      // inputs while the controller still tracks 'c' as exiting.
      c.setSections(
        ["a", "b", "d", "e"],
        itemsOf: (_) => const [],
      );
      await tester.pumpAndSettle();
    },
  );
}
