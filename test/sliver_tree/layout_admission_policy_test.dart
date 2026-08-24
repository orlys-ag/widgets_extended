import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_layout_admission_policy.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Focused unit tests for [LayoutAdmissionPolicy.admit].
///
/// Drives the policy directly with a real [TreeController] and synthesized
/// per-nid offset/extent arrays. Verifies the dual-view (live/post) admission
/// cap. The full render pipeline (Pass 2 measurement, sticky integration)
/// continues to be exercised by the widget-level tests in
/// `concurrent_extents_test.dart`, `animation_transitions_test.dart`, etc.
void main() {
  group('LayoutAdmissionPolicy.admit', () {
    late TreeController<String, String> controller;
    late LayoutAdmissionPolicy<String, String> policy;
    late Float64List offsets;
    late Float64List extents;
    late Uint8List inRegion;
    late List<int> writtenNids;

    void seedSteadyState() {
      // 10 visible nodes, each 50px tall, no animations.
      final nodes = List.generate(
        10,
        (i) => TreeNode<String, String>(key: 'k$i', data: 'v$i'),
      );
      controller.setRoots(nodes);
      // Seed offset/extent arrays at the controller's nidCapacity. Pass 1
      // would normally do this; we synthesize it directly here.
      final cap = controller.nidCapacity;
      offsets = Float64List(cap);
      extents = Float64List(cap);
      inRegion = Uint8List(cap);
      double off = 0.0;
      for (int i = 0; i < controller.visibleNodeCount; i++) {
        final nid = controller.visibleNidAt(i);
        offsets[nid] = off;
        extents[nid] = 50.0;
        off += 50.0;
      }
    }

    setUp(() {
      controller = TreeController<String, String>(
        vsync: const TestVSync(),
        animationStyle: TreeAnimationStyle.disabled,
      );
      policy = LayoutAdmissionPolicy<String, String>(controller: controller);
      writtenNids = <int>[];
    });

    tearDown(() {
      controller.dispose();
    });

    test('pure-scrolling: admits exactly the rows up to effectiveCacheEnd', () {
      seedSteadyState();
      // Cache budget: 200px from offset 0 → admits indices [0, 4) (4 rows × 50px).
      final end = policy.admit(
        cacheStartIndex: 0,
        visibleNodes: controller.visibleNodes,
        nodeOffsetsByNid: offsets,
        nodeExtentsByNid: extents,
        inCacheRegionByNid: inRegion,
        onCacheRegionAdmit: (int nid, int _) => writtenNids.add(nid),
        paintRegionStart: 0.0,
        paintRegionEnd: 0.0,
        effectiveCacheStart: 0.0,
        effectiveCacheEnd: 200.0,
        slideOverreach: 0.0,
        remainingCacheExtent: 200.0,
      );
      expect(end, 4);
      expect(writtenNids.length, 4);
      for (int i = 0; i < 4; i++) {
        expect(inRegion[controller.visibleNidAt(i)], 1);
      }
      for (int i = 4; i < 10; i++) {
        expect(inRegion[controller.visibleNidAt(i)], 0);
      }
    });

    test('cacheStartIndex > 0 admits the trailing slice', () {
      seedSteadyState();
      // Start at index 5, budget 100px → admits [5, 7).
      final end = policy.admit(
        cacheStartIndex: 5,
        visibleNodes: controller.visibleNodes,
        nodeOffsetsByNid: offsets,
        nodeExtentsByNid: extents,
        inCacheRegionByNid: inRegion,
        onCacheRegionAdmit: (int nid, int _) => writtenNids.add(nid),
        paintRegionStart: 0.0,
        paintRegionEnd: 0.0,
        effectiveCacheStart: 250.0,
        effectiveCacheEnd: 350.0, // offset of row 5 (250) + 100
        slideOverreach: 0.0,
        remainingCacheExtent: 100.0,
      );
      expect(end, 7);
      expect(writtenNids.length, 2);
    });

    test('empty visible order returns cacheStartIndex unchanged', () {
      seedSteadyState();
      // setRoots with empty list to clear visibility.
      controller.setRoots(<TreeNode<String, String>>[]);
      final end = policy.admit(
        cacheStartIndex: 0,
        visibleNodes: controller.visibleNodes,
        nodeOffsetsByNid: Float64List(0),
        nodeExtentsByNid: Float64List(0),
        inCacheRegionByNid: Uint8List(0),
        onCacheRegionAdmit: (int nid, int _) => writtenNids.add(nid),
        paintRegionStart: 0.0,
        paintRegionEnd: 0.0,
        effectiveCacheStart: 0.0,
        effectiveCacheEnd: 200.0,
        slideOverreach: 0.0,
        remainingCacheExtent: 200.0,
      );
      expect(end, 0);
      expect(writtenNids, isEmpty);
    });

    test("seed: the leading row's out-of-window part is handed back", () {
      seedSteadyState();
      // Window [275, 375): starts 25 px inside row 5 (rows are 50 px, so
      // row 5 spans [250, 300)). The seed (250 - 275 = -25) hands back
      // the part of row 5 above the window, so the 100 px budget covers
      // rows 5, 6 AND 7; unseeded accumulators would refuse row 7 (two
      // 50 px charges exhaust the cap). The floor is inert
      // (paintRegionEnd 0), so this pins the seed alone.
      final end = policy.admit(
        cacheStartIndex: 5,
        visibleNodes: controller.visibleNodes,
        nodeOffsetsByNid: offsets,
        nodeExtentsByNid: extents,
        inCacheRegionByNid: inRegion,
        onCacheRegionAdmit: (int nid, int _) => writtenNids.add(nid),
        paintRegionStart: 0.0,
        paintRegionEnd: 0.0,
        effectiveCacheStart: 275.0,
        effectiveCacheEnd: 375.0,
        slideOverreach: 0.0,
        remainingCacheExtent: 100.0,
      );
      expect(end, 8);
      expect(writtenNids.length, 3);
    });

    test("paint floor: rows the viewport paints are admitted past "
        "exhausted budgets", () {
      seedSteadyState();
      // Make row 0 taller than the whole budget and re-derive offsets.
      final nid0 = controller.visibleNidAt(0);
      extents[nid0] = 700.0;
      double off = 0.0;
      for (int i = 0; i < controller.visibleNodeCount; i++) {
        final nid = controller.visibleNidAt(i);
        offsets[nid] = off;
        off += extents[nid];
      }
      // The 100 px budget is exhausted by row 0 alone; the floor must
      // still admit every non-animating row intersecting the paint
      // region [0, 1000): rows 0..6 (row 6 spans [950, 1000)). This pins
      // the floor alone: without it the walk ends at row 1.
      final end = policy.admit(
        cacheStartIndex: 0,
        visibleNodes: controller.visibleNodes,
        nodeOffsetsByNid: offsets,
        nodeExtentsByNid: extents,
        inCacheRegionByNid: inRegion,
        onCacheRegionAdmit: (int nid, int _) => writtenNids.add(nid),
        paintRegionStart: 0.0,
        paintRegionEnd: 1000.0,
        effectiveCacheStart: 0.0,
        effectiveCacheEnd: 100.0,
        slideOverreach: 0.0,
        remainingCacheExtent: 100.0,
      );
      expect(end, 7);
      expect(writtenNids.length, 7);
    });

    test('controller setter updates the back-pointer', () {
      final c2 = TreeController<String, String>(
        vsync: const TestVSync(),
        animationStyle: TreeAnimationStyle.disabled,
      );
      try {
        expect(policy.controller, same(controller));
        policy.controller = c2;
        expect(policy.controller, same(c2));
        // Idempotent — same instance is a no-op.
        policy.controller = c2;
        expect(policy.controller, same(c2));
      } finally {
        c2.dispose();
      }
    });
  });
}
