/// One item in the selected day's list.
library;

import 'package:flutter/material.dart';

import 'calendar_item.dart';
import 'calendar_schema.dart';
import 'harbor_theme.dart';

/// The key of the card showing the item [id].
ValueKey<String> itemCardKey(String id) {
  return ValueKey<String>("card-$id");
}

enum _CardAction { edit, delete }

/// An item's card: a rounded box in its type's tint holding the type's
/// icon and the title, beside them a menu of Edit, for [onEdit], and
/// Delete, for [onDelete], holding those of the two given, and the
/// schema's summaries under them. With neither given the card has no menu,
/// and the title's row keeps the menu button's height, so the card's
/// height stays the same. While [ShownItem.pending] the card is dimmed
/// with a progress indicator and its menu is disabled.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final ShownItem entry;

  /// The summaries [item]'s schema gives it, in the schema's order, which
  /// the card shows under its title.
  static List<String> summariesOf(CalendarItem item) {
    final schema = schemaOf(item.type);
    final summaries = <String>[];
    for (final key in schema.summaryKeys) {
      final summary = schema.fieldOf(key)?.summaryOf(item.fields[key]);
      if (summary != null) {
        summaries.add(summary);
      }
    }
    return summaries;
  }

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// The width of the icon column and the gap after it, which the lines
  /// under the title are indented by.
  static const double _iconIndent = 26.0;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final style = harborTypeStyleOf(item.type);
    final summaries = summariesOf(item);
    final pending = entry.pending;
    final onEdit = this.onEdit;
    final onDelete = this.onDelete;
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: style.tint,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14.0, 6.0, 4.0, 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(style.icon, size: 18.0, color: style.edge),
                const SizedBox(width: _iconIndent - 18.0),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                      color: HarborColors.text,
                    ),
                  ),
                ),
                if (onEdit == null && onDelete == null)
                  const SizedBox(height: kMinInteractiveDimension)
                else
                  PopupMenuButton<_CardAction>(
                    tooltip: "Item actions",
                    enabled: !pending,
                    icon: const Icon(
                      Icons.more_horiz,
                      color: HarborColors.textMuted,
                    ),
                    color: HarborColors.surface,
                    onSelected: (action) {
                      switch (action) {
                        case _CardAction.edit:
                          onEdit?.call();
                        case _CardAction.delete:
                          onDelete?.call();
                      }
                    },
                    itemBuilder: (context) {
                      return <PopupMenuEntry<_CardAction>>[
                        if (onEdit != null)
                          const PopupMenuItem<_CardAction>(
                            value: _CardAction.edit,
                            child: Text("Edit"),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem<_CardAction>(
                            value: _CardAction.delete,
                            child: Text("Delete"),
                          ),
                      ];
                    },
                  ),
              ],
            ),
            if (summaries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(_iconIndent, 0.0, 10.0, 0.0),
                child: Text(
                  summaries.join(", "),
                  style: const TextStyle(
                    fontSize: 14.0,
                    color: HarborColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (pending) {
      card = Stack(
        children: <Widget>[
          Opacity(opacity: 0.5, child: card),
          const Positioned(
            top: 8.0,
            right: 48.0,
            child: SizedBox.square(
              dimension: 12.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
        ],
      );
    }
    return card;
  }
}
