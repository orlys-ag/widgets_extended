/// Internal sync-time helpers shared by widgets that drive a
/// [TreeController] through a [TreeSyncController]. Not exported from
/// the package barrel.
library;

import 'tree_controller.dart';

/// Auto-expands parents whose first children appeared in the most recent
/// sync.
///
/// Iterates [newChildPresence] and expands every parent that:
///   - has at least one child in the new state, AND
///   - had zero children in [oldChildPresence] (so this is a genuine
///     first-children gain, not a sibling addition), AND
///   - was NOT in [rememberedBeforeSync] (so we don't override a user's
///     deliberate collapse that the sync controller will restore on its
///     own), AND
///   - passes [shouldExpand] when one is supplied, AND
///   - currently exists in the controller and is not already expanded.
///
/// Both maps come from [TreeSyncController.snapshotChildPresence]: one
/// entry per live node, mapped to whether it has live children. This
/// heuristic never needed the child keys themselves, only that flag, and
/// an absent entry reads the same as false (the node did not exist).
///
/// [shouldExpand] carries the caller's per-node initial-expansion policy.
/// Without it the heuristic expands every qualifying parent, which is the
/// behavior a caller with a blanket "expand everything" policy wants.
///
/// The iteration is wrapped in [TreeController.runBatch] so K
/// gained-children parents produce one structural notification instead
/// of K separate fan-outs across every mounted row.
///
/// Used by `SyncedSliverTree`. Keep the rules in one place: the
/// `rememberedBeforeSync` filter exists to prevent silently re-expanding
/// a user-collapsed, re-added subtree, and duplicating that logic risks
/// divergence.
void expandParentsThatGainedChildren<TKey, TData>({
  required TreeController<TKey, TData> controller,
  required Map<TKey, bool> oldChildPresence,
  required Map<TKey, bool> newChildPresence,
  required Set<TKey> rememberedBeforeSync,
  required bool animate,
  bool Function(TKey parentKey)? shouldExpand,
}) {
  controller.runBatch(() {
    for (final entry in newChildPresence.entries) {
      final parentKey = entry.key;

      if (!entry.value) {
        continue;
      }

      // Absent means the node did not exist before, which is not "had
      // children" either way.
      final hadChildrenBefore = oldChildPresence[parentKey] ?? false;
      if (hadChildrenBefore) {
        continue;
      }

      if (rememberedBeforeSync.contains(parentKey)) {
        continue;
      }

      if (shouldExpand != null && !shouldExpand(parentKey)) {
        continue;
      }

      if (controller.getNodeData(parentKey) != null &&
          !controller.isExpanded(parentKey)) {
        controller.expand(key: parentKey, animate: animate);
      }
    }
  });
}
