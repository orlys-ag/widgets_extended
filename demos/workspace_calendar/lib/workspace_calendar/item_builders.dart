/// The demo's builders: what the calendar's views draw for its items, the
/// day list's add button and the loading and failure states, in Harbor's
/// look, and the bundle the composition hands them to the views in.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/calendar/calendar.dart';

import 'calendar_api_source.dart';
import 'calendar_item.dart';
import 'calendar_schema.dart';
import 'harbor_theme.dart';

/// The builders the composition passes the views; a null one gives the
/// view's default.
@immutable
class ItemBuilders {
  const ItemBuilders({
    this.block,
    this.chip,
    this.card,
    this.cardExtent,
    this.addButton,
    this.loading,
    this.failure,
  });

  /// Week's and Day's blocks.
  final CalendarBlockBuilder<ItemPayload>? block;

  /// Month's bars, in their chip and card forms, and the bars of the
  /// all-day strip of Week and Day.
  final CalendarChipBuilder<ItemPayload>? chip;

  /// Agenda's cards.
  final CalendarCardBuilder<ItemPayload>? card;

  /// The height of [card]'s card of an entry, its strips left out, which
  /// Agenda predicts a card it has not built by.
  final double Function(ShownItem entry)? cardExtent;

  /// The add button of each of Agenda's gaps.
  final CalendarAddButtonBuilder? addButton;

  /// What each view shows while its days are read.
  final CalendarLoadingBuilder? loading;

  /// What each view shows when the read of its days failed.
  final CalendarFailureBuilder? failure;
}

/// Harbor's builders, every field set.
const ItemBuilders harborItemBuilders = ItemBuilders(
  block: harborBlockBuilder,
  chip: harborChipBuilder,
  card: harborCardBuilder,
  cardExtent: ItemCard.extentOf,
  addButton: harborAddButtonBuilder,
  loading: harborLoadingBuilder,
  failure: harborFailureBuilder,
);

/// A [HarborBlock] of [entry] and [details].
Widget harborBlockBuilder(
  BuildContext context,
  ShownItem entry,
  CalendarBlockDetails details,
) {
  return HarborBlock(entry: entry, details: details);
}

/// A [HarborChip] of [entry] and [details].
Widget harborChipBuilder(
  BuildContext context,
  ShownItem entry,
  CalendarChipDetails details,
) {
  return HarborChip(entry: entry, details: details);
}

/// An [ItemCard] of [entry] with its strips and the actions [details]
/// hands it.
Widget harborCardBuilder(
  BuildContext context,
  ShownItem entry,
  CalendarCardDetails details,
) {
  return ItemCard(
    entry: entry,
    onEdit: details.onEdit,
    onDelete: details.onDelete,
    startsAt: details.startsAt,
    endsAt: details.endsAt,
  );
}

/// A [HarborAddButton] of [details].
Widget harborAddButtonBuilder(
  BuildContext context,
  CalendarAddButtonDetails details,
) {
  return HarborAddButton(details: details);
}

/// The label of [entry]'s type, which names its kind to a screen reader on
/// Month's bars.
String? harborEntryKind(CalendarEntry<ItemPayload> entry) {
  return entry.type.label;
}

/// The badge of each item type: its Harbor edge colour and its label.
final Map<CalendarItemType, CalendarBadgeKind> harborBadgeKinds =
    <CalendarItemType, CalendarBadgeKind>{
      for (final type in CalendarItemType.values)
        type: CalendarBadgeKind(
          color: harborTypeStyleOf(type).edge,
          label: type.label,
        ),
    };

/// The badges on the days of the calendar card: a dot for each type of
/// item a day has, in [CalendarItemType]'s order, in [harborBadgeKinds].
final CalendarDayBadges<ItemPayload> harborDayBadges =
    CalendarDayBadges<ItemPayload>(
      kinds: harborBadgeKinds.values.toList(),
      kindOf: (entry) {
        return harborBadgeKinds[entry.type];
      },
    );

/// A progress indicator: centred on the cover, and 16 square at the start
/// of a day row.
Widget harborLoadingBuilder(BuildContext context, CalendarLoadingState state) {
  switch (state.site) {
    case CalendarStateSite.cover:
      return const CircularProgressIndicator();
    case CalendarStateSite.dayRow:
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 16.0,
          child: CircularProgressIndicator(strokeWidth: 2.0),
        ),
      );
  }
}

/// A [_HarborFailure] of [state]: the sentence [readFailureMessage] gives
/// for its error and a Retry.
Widget harborFailureBuilder(BuildContext context, CalendarFailureState state) {
  return _HarborFailure(state: state);
}

/// What Harbor's widgets draw with, made from one [CalendarThemeData] by
/// [forTheme] and never changed.
@immutable
class _HarborStyles {
  _HarborStyles._(this.theme)
    : blockTitle = theme.blockTitleStyle.copyWith(color: theme.text),
      blockSummary = theme.blockSummaryStyle.copyWith(
        color: theme.textSecondary,
      ),
      detailedTitle = theme.detailedBlockTitleStyle.copyWith(color: theme.text),
      detail = theme.detailedBlockDetailStyle.copyWith(
        color: theme.textSecondary,
      ),
      cutStart = Positioned(
        top: 0.0,
        right: 0.0,
        child: Icon(
          theme.beforeHoursIcon,
          size: 14.0,
          color: theme.textSecondary,
        ),
      ),
      cutEnd = Positioned(
        bottom: 0.0,
        right: 0.0,
        child: Icon(
          theme.afterHoursIcon,
          size: 14.0,
          color: theme.textSecondary,
        ),
      ),
      chipTitle = theme.chipTitleStyle.copyWith(color: theme.text),
      cardTitle = theme.monthCardTitleStyle.copyWith(color: theme.text),
      cardTime = theme.monthCardTimeStyle.copyWith(color: theme.textSecondary),
      cardTitleText = theme.entryCardTitleStyle.copyWith(color: theme.text),
      cardSummary = theme.entryCardSummaryStyle.copyWith(
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
      menuIcon = Icon(
        theme.entryMenuIcon,
        color: theme.textMuted,
        semanticLabel: itemActionsLabel,
      ),
      addIcon = SizedBox.expand(
        child: Icon(theme.addEntryIcon, size: 16.0, color: theme.primary),
      ),
      message = theme.messageStyle.copyWith(color: theme.error);

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _HarborStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _HarborStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _HarborStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_HarborStyles> _memo = Expando<_HarborStyles>();
  static _HarborStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_HarborStyles>();
    _last = null;
  }

  final CalendarThemeData theme;

  /// A block's text, on a grid of several days and on a grid of one, and
  /// the arrows at the ends the hours cut.
  final TextStyle blockTitle;
  final TextStyle blockSummary;
  final TextStyle detailedTitle;
  final TextStyle detail;
  final Widget cutStart;
  final Widget cutEnd;

  /// A Month chip's title, and a Month card's title and times.
  final TextStyle chipTitle;
  final TextStyle cardTitle;
  final TextStyle cardTime;

  /// An [ItemCard]'s title, summaries, strips and menu icon.
  final TextStyle cardTitleText;
  final TextStyle cardSummary;
  final TextStyle stripLabel;
  final BoxDecoration topStrip;
  final BoxDecoration bottomStrip;
  final Widget menuIcon;

  /// A [HarborAddButton]'s plus, filling the button.
  final Widget addIcon;

  /// A failed read's sentence.
  final TextStyle message;
}

/// What a screen reader hears for an [ItemCard]'s menu button.
const String itemActionsLabel = "Item actions";

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

/// The element of each of Harbor's widgets, which drops the styles made so
/// far on a hot reload, before its widget builds again.
class _HarborElement extends StatelessElement {
  _HarborElement(super.widget);

  @override
  void reassemble() {
    _HarborStyles._reset();
    super.reassemble();
  }
}

/// One item's block: its type's tint with a 4 px edge, its text, and an
/// arrow at each end the grid's hours cut. Dimmed with a progress
/// indicator while [ShownItem.pending].
///
/// A [CalendarBlockDetails.detailed] block, which a grid of one day column
/// shows, has its title and its times on its first line, the times
/// wrapping under a title too long for both, and a line for each of its
/// type's summaries under them; it shows the lines that fit whole below
/// the first. Any other block shows its title, and its first summary when
/// [CalendarBlockDetails.tall].
class HarborBlock extends StatelessWidget {
  const HarborBlock({super.key, required this.entry, required this.details});

  final ShownItem entry;
  final CalendarBlockDetails details;

  @override
  StatelessElement createElement() {
    return _HarborElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _HarborStyles.of(context);
    final item = entry.entry;
    final style = harborTypeStyleOf(item.type);
    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: style.tint,
        border: Border(left: BorderSide(color: style.edge, width: 4.0)),
      ),
      child: details.detailed
          ? _buildLines(item, styles, CalendarLocalizations.of(context))
          : _buildCompact(item, styles),
    );
    if (details.cutAtStart || details.cutAtEnd) {
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          content,
          if (details.cutAtStart) styles.cutStart,
          if (details.cutAtEnd) styles.cutEnd,
        ],
      );
    }
    if (entry.pending) {
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          Opacity(opacity: 0.5, child: content),
          const Positioned(
            top: 2.0,
            right: 2.0,
            child: SizedBox.square(
              dimension: 12.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
        ],
      );
    }
    return content;
  }

  /// The title and, when [CalendarBlockDetails.tall], the first summary,
  /// laid out at their natural height and clipped to the block, so a block
  /// shorter than its text does not overflow.
  Widget _buildCompact(CalendarItem item, _HarborStyles styles) {
    final schema = schemaOf(item.type);
    String? summary;
    if (details.tall && schema.summaryKeys.isNotEmpty) {
      final key = schema.summaryKeys.first;
      summary = schema.fieldOf(key)?.summaryOf(item.fields[key]);
    }
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0.0,
        maxHeight: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4.0, 2.0, 4.0, 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.blockTitle,
              ),
              if (summary != null)
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.blockSummary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The title and the times, then each summary the item has, one per
  /// line, as [_BlockLinesDelegate] paints them.
  Widget _buildLines(
    CalendarItem item,
    _HarborStyles styles,
    CalendarLocalizations strings,
  ) {
    final schema = schemaOf(item.type);
    final summaries = <String>[];
    for (final key in schema.summaryKeys) {
      final summary = schema.fieldOf(key)?.summaryOf(item.fields[key]);
      if (summary != null) {
        summaries.add(summary);
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6.0, 3.0, 6.0, 3.0),
      child: Flow(
        delegate: const _BlockLinesDelegate(),
        children: <Widget>[
          Wrap(
            spacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.detailedTitle,
              ),
              Text(
                strings.entryTimes(
                  item.start,
                  item.end,
                  details.hourLabelFormat,
                ),
                maxLines: 1,
                style: styles.detail,
              ),
            ],
          ),
          for (final summary in summaries)
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.detail,
            ),
        ],
      ),
    );
  }
}

/// Lays a detailed block's lines out down its width, each at its natural
/// height, and paints the first line, clipped to the block when it is
/// taller, and each line after it while the lines down to its bottom fit,
/// so no line shows cut in half. The lines are laid out with the block,
/// so a block resized on each animation frame keeps the lines that fit
/// without a rebuild.
class _BlockLinesDelegate extends FlowDelegate {
  const _BlockLinesDelegate();

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    return BoxConstraints(maxWidth: constraints.maxWidth);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    var top = 0.0;
    for (var i = 0; i < context.childCount; i++) {
      final height = context.getChildSize(i)!.height;
      if (i > 0 && top + height > context.size.height) {
        return;
      }
      context.paintChild(
        i,
        transform: Matrix4.translationValues(0.0, top, 0.0),
      );
      top += height;
    }
  }

  @override
  bool shouldRepaint(_BlockLinesDelegate oldDelegate) {
    return false;
  }
}

/// One item's bar in one week of Month, or across its shown days in the
/// all-day strip of Week and Day: the type's tint with a 4 px edge in the
/// type's colour, as [HarborTypeStyle] draws an item, rounded at an end
/// where the item starts or ends and square where it continues. A chip
/// holds the title on one line; a [CalendarChipDetails.card] holds the
/// title over the type's icon and the item's times. Dimmed while pending.
class HarborChip extends StatelessWidget {
  const HarborChip({super.key, required this.entry, required this.details});

  final ShownItem entry;
  final CalendarChipDetails details;

  @override
  StatelessElement createElement() {
    return _HarborElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _HarborStyles.of(context);
    final item = entry.entry;
    final style = harborTypeStyleOf(item.type);
    const radius = Radius.circular(4.0);
    final title = Text(
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: details.card ? styles.cardTitle : styles.chipTitle,
    );
    Widget bar = ClipRRect(
      borderRadius: BorderRadius.horizontal(
        left: details.continuesBefore ? Radius.zero : radius,
        right: details.continuesAfter ? Radius.zero : radius,
      ),
      child: ColoredBox(
        color: style.tint,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: 4.0, child: ColoredBox(color: style.edge)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: details.card
                    ? _buildCardLines(
                        title,
                        item,
                        style,
                        styles,
                        CalendarLocalizations.of(context),
                      )
                    : Align(alignment: Alignment.centerLeft, child: title),
              ),
            ),
          ],
        ),
      ),
    );
    if (entry.pending) {
      bar = Opacity(opacity: 0.5, child: bar);
    }
    return bar;
  }

  /// A card's [title] over its type's icon and [item]'s times, as
  /// [CalendarLocalizations.entryTimes] writes them in the details' hour
  /// format, each line cut short where the day is too narrow for it.
  Widget _buildCardLines(
    Text title,
    CalendarItem item,
    HarborTypeStyle style,
    _HarborStyles styles,
    CalendarLocalizations strings,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        title,
        Row(
          children: <Widget>[
            Icon(style.icon, size: 11.0, color: style.edge),
            const SizedBox(width: 3.0),
            Flexible(
              child: Text(
                strings.entryTimes(
                  item.start,
                  item.end,
                  details.hourLabelFormat,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: styles.cardTime,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _CardAction { edit, delete }

/// An item's card: a rounded box in its type's tint holding the type's
/// icon and the title, beside them a compact menu of Edit, for [onEdit],
/// and Delete, for [onDelete], holding those of the two given, and the
/// schema's summaries under them. With neither given the card has no menu,
/// and the title's row keeps the menu button's height, so the card's
/// height stays the same. The menu button shows no tooltip; a screen
/// reader hears it as [itemActionsLabel]. While [ShownItem.pending] the
/// card is dimmed with a progress indicator and its menu is disabled. A
/// yellow strip [calendarCardStripExtent] tall across the card's top
/// states [startsAt], and one across its bottom [endsAt], where given. Its
/// text, strips and menu draw in the [CalendarTheme] above it, its tint,
/// edge and icon in its type's [HarborTypeStyle].
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

  /// The height of the strip stating [startsAt] or [endsAt]: the
  /// [calendarCardStripExtent] the day list places its current-time marker
  /// between and predicts a card by, a line of its text at the default
  /// text size and 4 px above and below it.
  static const double stripHeight = calendarCardStripExtent;

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

  /// The height of [entry]'s card, its strips left out: its top and bottom
  /// padding, the row of its title and menu button, and a line of
  /// summaries where it has some.
  static double extentOf(ShownItem entry) {
    final summaries = summariesOf(entry.entry).isEmpty ? 0.0 : 17.0;
    return 6.0 + _titleRowHeight + summaries + 8.0;
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
    return _HarborElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _HarborStyles.of(context);
    final item = entry.entry;
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
              CalendarLocalizations.of(context).startsAt(startsAt),
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
                        style: styles.cardTitleText,
                      ),
                    ),
                    if (onEdit == null && onDelete == null)
                      const SizedBox(height: _titleRowHeight)
                    else
                      PopupMenuButton<_CardAction>(
                        // No tooltip: its icon's label names the button.
                        tooltip: "",
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
                      style: styles.cardSummary,
                    ),
                  ),
              ],
            ),
          ),
          if (endsAt != null)
            _strip(
              itemCardEndsAtKey(entry.id),
              CalendarLocalizations.of(context).endsAt(endsAt),
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
    _HarborStyles styles, {
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

/// A gap's round add button, filling the square the list gives it: a plus
/// in the primary colour on the primary tint, with ink, which calls
/// [CalendarAddButtonDetails.onPressed] for a press.
class HarborAddButton extends StatelessWidget {
  const HarborAddButton({super.key, required this.details});

  final CalendarAddButtonDetails details;

  @override
  StatelessElement createElement() {
    return _HarborElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _HarborStyles.of(context);
    return Material(
      color: styles.theme.primaryTint,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: details.onPressed,
        child: styles.addIcon,
      ),
    );
  }
}

/// A failed read's sentence, [readFailureMessage] of the state's error, in
/// the theme's message style and error colour, and a Retry that reads the
/// days again: a column centred on the cover, a row in a day row.
class _HarborFailure extends StatelessWidget {
  const _HarborFailure({required this.state});

  final CalendarFailureState state;

  @override
  StatelessElement createElement() {
    return _HarborElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _HarborStyles.of(context);
    final message = readFailureMessage(state.error);
    final retry = TextButton(
      onPressed: state.retry,
      child: const Text("Retry"),
    );
    switch (state.site) {
      case CalendarStateSite.cover:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: styles.message,
              ),
            ),
            const SizedBox(height: 12.0),
            retry,
          ],
        );
      case CalendarStateSite.dayRow:
        return Row(
          children: <Widget>[
            Expanded(child: Text(message, style: styles.message)),
            retry,
          ],
        );
    }
  }
}
