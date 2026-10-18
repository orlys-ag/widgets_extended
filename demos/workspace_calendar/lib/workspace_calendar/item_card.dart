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

/// The key of the strip across the top of the card showing the item [id]
/// that states its start, [ItemCard.startsAt].
ValueKey<String> itemCardStartsAtKey(String id) {
  return ValueKey<String>("card-starts-$id");
}

/// The key of the strip across the bottom of the card showing the item
/// [id] that states its end, [ItemCard.endsAt].
ValueKey<String> itemCardEndsAtKey(String id) {
  return ValueKey<String>("card-ends-$id");
}

enum _CardAction { edit, delete }

/// An item's card: a rounded box in its type's tint holding the type's
/// icon and the title, beside them a compact menu of Edit, for [onEdit],
/// and Delete, for [onDelete], holding those of the two given, and the
/// schema's summaries under them. With neither given the card has no menu,
/// and the title's row keeps the menu button's height, so the card's
/// height stays the same. While [ShownItem.pending] the card is dimmed
/// with a progress indicator and its menu is disabled. A yellow strip
/// across the card's top states [startsAt], and one across its bottom
/// [endsAt], where given.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    this.startsAt,
    this.endsAt,
  });

  final ShownItem entry;

  /// The time the item starts at, for one that starts before the hours
  /// its list shows; null for one that starts inside them.
  final String? startsAt;

  /// The time the item ends at, for one that ends after the hours its list
  /// shows; null for one that ends inside them.
  final String? endsAt;

  /// The height of the strip stating [startsAt] or [endsAt]: a line of its
  /// text at the default text size and 4 px above and below it.
  static const double stripHeight = 25.0;

  /// The radius of the card's corners.
  static const double _radius = 16.0;

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

  /// The height of the title's row: the menu button's, at its compact
  /// size.
  static const double _titleRowHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final style = harborTypeStyleOf(item.type);
    final summaries = summariesOf(item);
    final pending = entry.pending;
    final onEdit = this.onEdit;
    final onDelete = this.onDelete;
    final startsAt = this.startsAt;
    final endsAt = this.endsAt;
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: style.tint,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (startsAt != null)
            _strip(
              itemCardStartsAtKey(entry.id),
              "Starts at $startsAt",
              top: true,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 8.0),
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
                          fontSize: 14.0,
                          fontWeight: FontWeight.w600,
                          color: HarborColors.text,
                        ),
                      ),
                    ),
                    if (onEdit == null && onDelete == null)
                      const SizedBox(height: _titleRowHeight)
                    else
                      PopupMenuButton<_CardAction>(
                        tooltip: "Item actions",
                        enabled: !pending,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
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
                    padding: const EdgeInsets.fromLTRB(
                      _iconIndent,
                      0.0,
                      8.0,
                      0.0,
                    ),
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
          if (endsAt != null)
            _strip(itemCardEndsAtKey(entry.id), "Ends at $endsAt", top: false),
        ],
      ),
    );
    if (pending) {
      card = Stack(
        children: <Widget>[
          Opacity(opacity: 0.5, child: card),
          Positioned(
            top: startsAt == null ? 8.0 : 8.0 + stripHeight,
            right: 48.0,
            child: const SizedBox.square(
              dimension: 12.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
        ],
      );
    }
    return card;
  }

  /// A strip in the soft yellow of the list's banners across the card's
  /// top, or its bottom where not [top], rounded as the card's corners
  /// there, holding [label] in its middle, [stripHeight] tall at any text
  /// size.
  static Widget _strip(Key key, String label, {required bool top}) {
    const corner = Radius.circular(_radius);
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: HarborColors.notice,
        borderRadius: top
            ? const BorderRadius.vertical(top: corner)
            : const BorderRadius.vertical(bottom: corner),
      ),
      child: SizedBox(
        height: stripHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Align(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                color: HarborColors.onNotice,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
