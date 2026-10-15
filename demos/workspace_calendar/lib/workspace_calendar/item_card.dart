/// One item in the selected day's list.
library;

import 'package:flutter/material.dart';

import 'calendar_data.dart';
import 'calendar_item.dart';
import 'calendar_schema.dart';
import 'harbor_theme.dart';

/// The key of the card showing the item [id].
ValueKey<String> itemCardKey(String id) {
  return ValueKey<String>("card-$id");
}

enum _CardAction { edit, delete }

/// An item's card: its type's tint with a 4 px edge in the type's colour,
/// the type's icon, the time range, the title, the schema's summaries, and
/// a menu with Edit and Delete. While [ShownItem.pending] the card is
/// dimmed with a progress indicator and its menu is disabled.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final ShownItem entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final style = harborTypeStyleOf(item.type);
    final schema = schemaOf(item.type);
    final summaries = <String>[];
    for (final key in schema.summaryKeys) {
      final summary = schema.fieldOf(key)?.summaryOf(item.fields[key]);
      if (summary != null) {
        summaries.add(summary);
      }
    }
    final pending = entry.pending;
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: style.tint,
        border: Border(left: BorderSide(color: style.edge, width: 4.0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 10.0, 4.0, 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Icon(style.icon, size: 20.0, color: style.edge),
            ),
            const SizedBox(width: 10.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "${clockLabel(item.startMinute)}-"
                    "${clockLabel(item.endMinute)}",
                    style: const TextStyle(
                      fontSize: 14.0,
                      color: HarborColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                      color: HarborColors.text,
                    ),
                  ),
                  if (summaries.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4.0),
                    Text(
                      summaries.join(", "),
                      style: const TextStyle(
                        fontSize: 14.0,
                        color: HarborColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<_CardAction>(
              tooltip: "Item actions",
              enabled: !pending,
              icon: const Icon(Icons.more_horiz, color: HarborColors.textMuted),
              color: HarborColors.surface,
              onSelected: (action) {
                switch (action) {
                  case _CardAction.edit:
                    onEdit();
                  case _CardAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) {
                return const <PopupMenuEntry<_CardAction>>[
                  PopupMenuItem<_CardAction>(
                    value: _CardAction.edit,
                    child: Text("Edit"),
                  ),
                  PopupMenuItem<_CardAction>(
                    value: _CardAction.delete,
                    child: Text("Delete"),
                  ),
                ];
              },
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
