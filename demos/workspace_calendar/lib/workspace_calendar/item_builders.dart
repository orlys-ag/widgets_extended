/// The demo's builders: what the calendar's views draw for its items and
/// for their loading and failure states, in Harbor's look, and the bundle
/// the composition hands them to the views in.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';

import 'calendar_api_source.dart';
import 'calendar_item.dart';
import 'calendar_schema.dart';
import 'harbor_theme.dart';

/// The builders the composition passes the views; a null one gives the
/// view's default.
@immutable
class ItemBuilders {
  const ItemBuilders({this.block, this.loading, this.failure});

  /// Week's and Day's blocks.
  final CalendarBlockBuilder<ItemPayload>? block;

  /// What each view shows while its days are read.
  final CalendarLoadingBuilder? loading;

  /// What each view shows when the read of its days failed.
  final CalendarFailureBuilder? failure;
}

/// Harbor's builders, every field set.
const ItemBuilders harborItemBuilders = ItemBuilders(
  block: harborBlockBuilder,
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

  /// A failed read's sentence.
  final TextStyle message;
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
          ? _buildLines(item, styles)
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
  Widget _buildLines(CalendarItem item, _HarborStyles styles) {
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
                clockRangeLabel(item.startMinute, item.endMinute),
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
