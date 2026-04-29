/// Regression: deleting a section then re-syncing while the section's
/// exit animation is still in flight must not throw inside reorderRoots.
library;

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

void main() {
  testWidgets(
    "removeSection followed by resync with unchanged inputs survives "
    "mid-animation",
    (tester) async {
      final c = SectionedListController<String, String, String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(c.dispose);

      c.setSections([
        _section("a", "A"),
        _section("b", "B"),
        _section("c", "C"),
        _section("d", "D"),
        _section("e", "E"),
      ]);
      await tester.pump();

      // Animated removal — the section is still in the controller's
      // root list (in pending deletion) until its exit animation
      // completes.
      c.removeSection("c");

      // Mid-animation: re-sync with the "current state" view that
      // mirrors the controller (this is what the example does after
      // setState). Because the controller still reports `c` as a
      // section, the re-sync passes 5 inputs including `c`.
      final mirroredInputs = [
        for (final sKey in c.sections)
          _section(sKey, c.getSection(sKey) ?? sKey),
      ];
      expect(mirroredInputs.length, equals(5));

      // This is the call that previously threw inside reorderRoots.
      c.setSections(mirroredInputs);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "removeSection followed by resync with shrunk inputs survives "
    "mid-animation",
    (tester) async {
      final c = SectionedListController<String, String, String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(c.dispose);

      c.setSections([
        _section("a", "A"),
        _section("b", "B"),
        _section("c", "C"),
        _section("d", "D"),
        _section("e", "E"),
      ]);
      await tester.pump();

      c.removeSection("c");

      // Caller's source-of-truth has dropped `c`. Re-sync with 4
      // inputs while the controller still tracks `c` as exiting.
      c.setSections([
        _section("a", "A"),
        _section("b", "B"),
        _section("d", "D"),
        _section("e", "E"),
      ]);
      await tester.pumpAndSettle();
    },
  );
}
