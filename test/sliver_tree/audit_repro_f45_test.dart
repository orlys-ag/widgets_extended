import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Audit repro for finding f45:
/// BulkAnimationData.containsMember throws a TypeError on the inactive
/// sentinel instead of returning false.
///
/// The inactive sentinel is a const BulkAnimationData<Never> that
/// `BulkAnimationData.inactive<TKey>()` casts to BulkAnimationData<TKey>.
/// Because `containsMember` takes a TKey parameter, Dart's generic
/// covariance check validates the argument against the ACTUAL type
/// argument (Never) before the method body runs, so any call with a real
/// key must throw — despite the class docs promising "Always false on an
/// invalid snapshot."
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("f45: BulkAnimationData.containsMember on inactive snapshot", () {
    testWidgets(
      "returns false instead of throwing when no bulk animation is active",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        // No bulk animation has been started, so this is the documented
        // "no bulk animation active" snapshot.
        final BulkAnimationData<String> data = controller.bulkAnimationData();

        // Sanity: we are exercising the inactive path the finding targets.
        expect(data.isValid, isFalse);

        // Per the class documentation, containsMember is "Always false on
        // an invalid snapshot" — it must not throw.
        expect(data.containsMember("a"), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
