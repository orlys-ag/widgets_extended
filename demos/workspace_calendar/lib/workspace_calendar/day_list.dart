/// The selected day's items, as cards that animate the changes the API
/// confirms.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_item.dart';
import 'calendar_model.dart';
import 'harbor_theme.dart';
import 'item_card.dart';

/// The style the day list animates its cards with: every family over
/// [harborMotionDuration] on [harborMotionCurve].
const TreeAnimationStyle dayListAnimationStyle = TreeAnimationStyle(
  expandCollapse: _dayListAnimationSpec,
  reorderSlide: _dayListAnimationSpec,
);

const TreeAnimationSpec _dayListAnimationSpec = TreeAnimationSpec(
  duration: harborMotionDuration,
  curve: harborMotionCurve,
);

/// The cards of [entries] on a flat [SyncedSliverTree], which removes a
/// card through an exit animation and slides the cards a reorder moves.
/// While [status] is not ready, a progress indicator, or [error] and a
/// Retry button, takes the cards' place.
///
/// Every state stays inside one always-scrollable scroll view, so a drag
/// on a short list, a loading one or a failed one still reports the
/// overscroll an ancestor's scroll listener reads.
class DayList extends StatelessWidget {
  const DayList({
    super.key,
    required this.status,
    this.error,
    required this.onRetry,
    required this.entries,
    required this.onEdit,
    required this.onDelete,
  });

  final CalendarLoadStatus status;

  /// The failed read's message while [status] is failed.
  final String? error;

  final VoidCallback onRetry;

  /// The day's items, in display order. A new list instance is the tree's
  /// signal to diff.
  final List<ShownItem> entries;

  final void Function(String id) onEdit;
  final void Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    switch (status) {
      case CalendarLoadStatus.loading:
        content = const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(
              key: ValueKey<String>("day-list-loading"),
            ),
          ),
        );
      case CalendarLoadStatus.failed:
        content = SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    error ?? "The items could not be read.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: HarborColors.error),
                  ),
                  const SizedBox(height: 12.0),
                  TextButton(onPressed: onRetry, child: const Text("Retry")),
                ],
              ),
            ),
          ),
        );
      case CalendarLoadStatus.ready:
        content = SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          sliver: SyncedSliverTree<String, ShownItem>.flat(
            items: entries,
            keyOf: (entry) {
              return entry.id;
            },
            parentOf: (entry) {
              return null;
            },
            // A flat list has no expansion to run or remember.
            initiallyExpanded: false,
            expansionMemory: 0,
            animationStyle: dayListAnimationStyle,
            itemBuilder: (context, node) {
              final entry = node.item;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ItemCard(
                  key: itemCardKey(entry.id),
                  entry: entry,
                  onEdit: () {
                    onEdit(entry.id);
                  },
                  onDelete: () {
                    onDelete(entry.id);
                  },
                ),
              );
            },
          ),
        );
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        content,
        if (status == CalendarLoadStatus.ready && entries.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 32.0),
              child: Text(
                "No items on this day.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.0, color: HarborColors.textMuted),
              ),
            ),
          ),
        // Room under the last card for the floating action button.
        if (status == CalendarLoadStatus.ready)
          const SliverToBoxAdapter(child: SizedBox(height: 88.0)),
      ],
    );
  }
}
