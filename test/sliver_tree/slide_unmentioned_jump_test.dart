/// Regression for visual jump on FLIP slide when a subsequent
/// `animateSlideFromOffsets` call doesn't include a key whose slide is
/// already in flight.
///
/// The slide ticker is shared. `animateSlideFromOffsets` ends with
/// `ticker.stop(); ticker.start()` to reset elapsed time so all entries
/// in the new batch start from progress=0. Existing entries that weren't
/// mentioned in the new call get their progress recomputed from the new
/// elapsed=0 on the next tick — `lerp(startDelta, 0, curve(~0)) ≈
/// startDelta`. The visual `currentDelta` jumps from its mid-flight value
/// back to `startDelta`.
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("a slide whose key is omitted from a later "
      "animateSlideFromOffsets call must not visually jump back to "
      "startDelta when the ticker is reset", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 1000),
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "a", data: "a"),
      const TreeNode(key: "b", data: "b"),
    ]);

    // Install a 200ms slide on `a` with startDelta=100.
    controller.animateSlideFromOffsets(
      const {"a": 100.0},
      const {"a": 0.0},
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    );

    // Pump multiple frames so `a`'s slide actually progresses.
    // First tick has elapsed=0 (Ticker semantics); subsequent ticks
    // accumulate elapsed time.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final aDeltaBeforeSecondCall = controller.getSlideDelta("a");
    expect(
      aDeltaBeforeSecondCall,
      lessThan(100.0),
      reason: "Sanity: 'a' should have progressed from startDelta=100 toward 0 "
          "after 6 frames. Got $aDeltaBeforeSecondCall",
    );
    expect(
      aDeltaBeforeSecondCall,
      greaterThan(0.0),
      reason: "Sanity: 'a' shouldn't have settled yet. Got $aDeltaBeforeSecondCall",
    );

    // Now call animateSlideFromOffsets a second time WITHOUT mentioning `a`.
    // Bug: this stop+start of the shared ticker resets elapsed, so on the
    // next tick `a`'s progress is recomputed from ~0, jumping currentDelta
    // back to startDelta=100.
    controller.animateSlideFromOffsets(
      const {"b": 80.0},
      const {"b": 0.0},
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    );

    // Pump one frame. The first tick after ticker reset has elapsed=0,
    // so this is the moment of the jump.
    await tester.pump(const Duration(milliseconds: 16));

    final aDeltaAfterSecondCall = controller.getSlideDelta("a");
    // 'a' should NOT have jumped back to startDelta. It should be at
    // approximately the same value it had before the second call (small
    // tick advance is acceptable).
    expect(
      aDeltaAfterSecondCall,
      closeTo(aDeltaBeforeSecondCall, 10.0),
      reason:
          "Slide 'a' jumped back toward startDelta when the second "
          "animateSlideFromOffsets call reset the shared ticker without "
          "rebaselining 'a'. Before second call: $aDeltaBeforeSecondCall. "
          "After: $aDeltaAfterSecondCall.",
    );

    // Drain the slide ticker before dispose so the test runner doesn't
    // flag a leaked active ticker.
    await tester.pumpAndSettle();
  });
}
