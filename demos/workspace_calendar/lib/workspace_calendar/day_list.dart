/// The selected day's items, as cards beside their start times and
/// lengths, with a dashed row for each hour between them that no item
/// covers, all animating the changes the API confirms.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_data.dart';
import 'calendar_item.dart';
import 'calendar_model.dart';
import 'calendar_settings.dart';
import 'harbor_theme.dart';
import 'item_card.dart';

/// The style the day list animates its rows with: every family over
/// [harborMotionDuration] on [harborMotionCurve].
const TreeAnimationStyle dayListAnimationStyle = TreeAnimationStyle(
  expandCollapse: _dayListAnimationSpec,
  reorderSlide: _dayListAnimationSpec,
);

const TreeAnimationSpec _dayListAnimationSpec = TreeAnimationSpec(
  duration: harborMotionDuration,
  curve: harborMotionCurve,
);

/// The width of the column of times left of the cards and the dashed
/// lines.
const double dayListTimeWidth = 72.0;

/// The key of the start time and length beside the card of the item [id].
ValueKey<String> dayListTimeKey(String id) {
  return ValueKey<String>("day-list-time-$id");
}

/// The key of the dashed row of the hour [minute] minutes after midnight.
ValueKey<String> dayListHourKey(int minute) {
  return ValueKey<String>("day-list-hour-$minute");
}

/// One row of the day list: an item ([DayListItem]), or a whole hour no
/// item covers ([DayListHour]).
@immutable
sealed class DayListRow {
  const DayListRow();

  /// The row's key in the list: the item's id, or "hour-" and the
  /// hour's minute.
  String get key;
}

/// The row of the item [entry].
final class DayListItem extends DayListRow {
  const DayListItem(this.entry);

  final ShownItem entry;

  @override
  String get key {
    return entry.id;
  }

  @override
  bool operator ==(Object other) {
    return other is DayListItem && other.entry == entry;
  }

  @override
  int get hashCode {
    return entry.hashCode;
  }

  @override
  String toString() {
    return "DayListItem($entry)";
  }
}

/// The dashed row of the whole hour [minute] minutes after midnight.
final class DayListHour extends DayListRow {
  const DayListHour(this.minute);

  final int minute;

  @override
  String get key {
    return "hour-$minute";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListHour && other.minute == minute;
  }

  @override
  int get hashCode {
    return minute.hashCode;
  }

  @override
  String toString() {
    return "DayListHour(${clockLabel(minute)})";
  }
}

/// The rows of a day showing [entries], sorted by start as
/// [CalendarModel.itemsOn] sorts them: each item, and before it an hour
/// row for each whole hour from the latest end among the earlier items to
/// before the item's start. So each whole hour after the first item's
/// start and before the last item's that no item covers, an item covering
/// the minutes from its start to before its end, has a row, and no hour
/// before the first item or after the last has one.
List<DayListRow> dayListRowsOf(List<ShownItem> entries) {
  final rows = <DayListRow>[];
  // The latest end among the items so far.
  int? covered;
  for (final entry in entries) {
    final item = entry.item;
    final from = covered;
    if (from != null) {
      for (
        var hour = (from + 59) ~/ 60 * 60;
        hour < item.startMinute;
        hour += 60
      ) {
        rows.add(DayListHour(hour));
      }
    }
    rows.add(DayListItem(entry));
    if (from == null || item.endMinute > from) {
      covered = item.endMinute;
    }
  }
  return rows;
}

/// The rows of [entries] ([dayListRowsOf]) on a flat [SyncedSliverTree],
/// which removes a row through an exit animation and slides the rows a
/// reorder moves. Each item's card sits right of its start time and its
/// length, and each hour row is the hour and a dashed line, all times in
/// [format]. While [status] is not ready, a progress indicator, or [error]
/// and a Retry button, takes the rows' place.
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
    required this.format,
    required this.onEdit,
    required this.onDelete,
  });

  final CalendarLoadStatus status;

  /// The failed read's message while [status] is failed.
  final String? error;

  final VoidCallback onRetry;

  /// The day's items, sorted by start. A new list instance is the tree's
  /// signal to diff.
  final List<ShownItem> entries;

  /// How the times beside the cards, on the hour rows and on the cards
  /// read, as [hourLabel] writes them.
  final HourLabelFormat format;

  final void Function(String id) onEdit;
  final void Function(String id) onDelete;

  static const TextStyle _timeStyle = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.textSecondary,
  );

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
          sliver: SyncedSliverTree<String, DayListRow>.flat(
            items: dayListRowsOf(entries),
            keyOf: (row) {
              return row.key;
            },
            parentOf: (row) {
              return null;
            },
            // A flat list has no expansion to run or remember.
            initiallyExpanded: false,
            expansionMemory: 0,
            animationStyle: dayListAnimationStyle,
            itemBuilder: (context, node) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: switch (node.item) {
                  DayListItem(:final entry) => _buildItem(entry),
                  DayListHour(:final minute) => _buildHour(minute),
                },
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

  /// The item's start time over its length, and its card.
  Widget _buildItem(ShownItem entry) {
    final item = entry.item;
    return Row(
      children: <Widget>[
        SizedBox(
          key: dayListTimeKey(entry.id),
          width: dayListTimeWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(hourLabel(item.startMinute, format), style: _timeStyle),
              const SizedBox(height: 2.0),
              Text(
                durationLabel(item.endMinute - item.startMinute),
                style: const TextStyle(
                  fontSize: 12.0,
                  color: HarborColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ItemCard(
            key: itemCardKey(entry.id),
            entry: entry,
            format: format,
            onEdit: () {
              onEdit(entry.id);
            },
            onDelete: () {
              onDelete(entry.id);
            },
          ),
        ),
      ],
    );
  }

  /// The hour and a dashed line across the cards' width.
  Widget _buildHour(int minute) {
    return SizedBox(
      key: dayListHourKey(minute),
      height: 24.0,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: dayListTimeWidth,
            child: Text(
              hourLabel(minute, format),
              style: _timeStyle.copyWith(color: HarborColors.textMuted),
            ),
          ),
          const Expanded(
            child: CustomPaint(
              painter: _DashedLinePainter(),
              child: SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dashed line in the outline colour across the middle of its box.
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  static const double _dash = 4.0;
  static const double _gap = 4.0;

  static final Paint _paint = Paint()
    ..color = HarborColors.outline
    ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = (size.height / 2.0).floorToDouble() + 0.5;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      final end = x + _dash < size.width ? x + _dash : size.width;
      canvas.drawLine(Offset(x, y), Offset(end, y), _paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) {
    return false;
  }
}
