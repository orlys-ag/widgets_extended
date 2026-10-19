/// One item in the selected day's list.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/calendar/calendar.dart';

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

/// What an [ItemCard] draws with, made from one [CalendarThemeData] by
/// [forTheme] and never changed.
@immutable
class _CardStyles {
  _CardStyles._(this.theme)
    : title = theme.entryCardTitleStyle.copyWith(color: theme.text),
      summary = theme.entryCardSummaryStyle.copyWith(
        color: theme.textSecondary,
      ),
      stripLabel = theme.noticeStyle.copyWith(color: theme.onNotice),
      topStrip = BoxDecoration(
        color: theme.notice,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ItemCard._radius),
        ),
      ),
      bottomStrip = BoxDecoration(
        color: theme.notice,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(ItemCard._radius),
        ),
      ),
      menuIcon = Icon(theme.entryMenuIcon, color: theme.textMuted);

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _CardStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _CardStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _CardStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_CardStyles> _memo = Expando<_CardStyles>();
  static _CardStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_CardStyles>();
    _last = null;
  }

  final CalendarThemeData theme;
  final TextStyle title;
  final TextStyle summary;
  final TextStyle stripLabel;
  final BoxDecoration topStrip;
  final BoxDecoration bottomStrip;
  final Widget menuIcon;
}

/// The element of an [ItemCard], which drops the card styles made so far
/// on a hot reload, before its widget builds again.
class _CardElement extends StatelessElement {
  _CardElement(super.widget);

  @override
  void reassemble() {
    _CardStyles._reset();
    super.reassemble();
  }
}

/// An item's card: a rounded box in its type's tint holding the type's
/// icon and the title, beside them a compact menu of Edit, for [onEdit],
/// and Delete, for [onDelete], holding those of the two given, and the
/// schema's summaries under them. With neither given the card has no menu,
/// and the title's row keeps the menu button's height, so the card's
/// height stays the same. While [ShownItem.pending] the card is dimmed
/// with a progress indicator and its menu is disabled. A yellow strip
/// across the card's top states [startsAt], and one across its bottom
/// [endsAt], where given. Its text, strips and menu draw in the
/// [CalendarTheme] above it, its tint, edge and icon in its type's
/// [HarborTypeStyle].
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
  StatelessElement createElement() {
    return _CardElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _CardStyles.of(context);
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
              styles,
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
                        style: styles.title,
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
                        icon: styles.menuIcon,
                        color: styles.theme.surface,
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
                      style: styles.summary,
                    ),
                  ),
              ],
            ),
          ),
          if (endsAt != null)
            _strip(
              itemCardEndsAtKey(entry.id),
              "Ends at $endsAt",
              styles,
              top: false,
            ),
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
  static Widget _strip(
    Key key,
    String label,
    _CardStyles styles, {
    required bool top,
  }) {
    return DecoratedBox(
      key: key,
      decoration: top ? styles.topStrip : styles.bottomStrip,
      child: SizedBox(
        height: stripHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Align(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.stripLabel,
            ),
          ),
        ),
      ),
    );
  }
}
