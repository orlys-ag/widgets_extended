/// Internal sync-time helpers shared by widgets that drive a
/// [TreeController] through a [TreeSyncController]. Not exported from
/// the package barrel.
library;

import 'tree_controller.dart';

/// Auto-expands parents whose first children appeared in the most recent
/// sync.
///
/// Iterates [newChildrenByParent] and expands every parent that:
///   - has at least one child in the new state, AND
///   - had zero children in [oldChildrenByParent] (so this is a genuine
///     first-children gain, not a sibling addition), AND
///   - was NOT in [rememberedBeforeSync] (so we don't override a user's
///     deliberate collapse that the sync controller will restore on its
///     own), AND
///   - currently exists in the controller and is not already expanded.
///
/// The iteration is wrapped in [TreeController.runBatch] so K
/// gained-children parents produce one structural notification instead
/// of K separate fan-outs across every mounted row.
///
/// Used by both `SyncedSliverTree` and `SectionedSliverList`. Keep the
/// rules in one place — the `rememberedBeforeSync` filter exists to
/// prevent silently re-expanding a user-collapsed, re-added subtree, and
/// duplicating that logic risks divergence.
void expandParentsThatGainedChildren<TKey, TData>({
  required TreeController<TKey, TData> controller,
  required Map<TKey, List<TKey>> oldChildrenByParent,
  required Map<TKey, List<TKey>> newChildrenByParent,
  required Set<TKey> rememberedBeforeSync,
  required bool animate,
}) {
  controller.runBatch(() {
    for (final entry in newChildrenByParent.entries) {
      final parentKey = entry.key;

      if (entry.value.isEmpty) {
        continue;
      }

      final oldChildren = oldChildrenByParent[parentKey];
      final hadChildrenBefore = oldChildren != null && oldChildren.isNotEmpty;
      if (hadChildrenBefore) {
        continue;
      }

      if (rememberedBeforeSync.contains(parentKey)) {
        continue;
      }

      if (controller.getNodeData(parentKey) != null &&
          !controller.isExpanded(parentKey)) {
        controller.expand(key: parentKey, animate: animate);
      }
    }
  });
}
