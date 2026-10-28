/// The module's default builders: what a view draws for an entry, an add
/// button, a loading and a failure state when it is given no builder, from
/// what it is given and [CalendarTheme] alone, with no Material ancestor.
library;

import 'package:flutter/widgets.dart';

import '../store/calendar_store.dart';
import 'calendar_activity_indicator.dart';
import 'calendar_builders.dart';
import 'calendar_localizations.dart';
import 'calendar_theme.dart';

/// The height of the default card of an entry without strips at a text
/// scale of 1, along the list's scroll axis: its padding, 8 above and
/// below, and the one line of its title, which the card forces to
/// [CalendarThemeData.entryCardTitleStyle]'s font size times its height,
/// [kDefaultFontSize] and 1.25 where the style gives none.
double defaultCalendarCardExtent(CalendarThemeData theme) {
  return 16.0 +
      _cardTitleLineOf(theme.entryCardTitleStyle, TextScaler.noScaling);
}

/// The strut the default card lays its title's line out with: [style]'s
/// font size and height, with no leading.
StrutStyle _cardTitleStrutOf(TextStyle style) {
  return StrutStyle(
    fontSize: style.fontSize ?? kDefaultFontSize,
    height: style.height ?? 1.25,
    leading: 0.0,
    forceStrutHeight: true,
  );
}

/// The height of the default card's title line under [scaler]: the font
/// size of [_cardTitleStrutOf] scaled, times its height. The card holds
/// the line at exactly this height, since a paragraph rounds its own.
double _cardTitleLineOf(TextStyle style, TextScaler scaler) {
  final strut = _cardTitleStrutOf(style);
  return scaler.scale(strut.fontSize!) * strut.height!;
}

/// The tint the default entries fill their box with: [color] at the
/// theme's [CalendarThemeData.entryTintOpacity] over its
/// [CalendarThemeData.surface].
Color _tintOf(Color color, CalendarThemeData theme) {
  return Color.alphaBlend(
    color.withValues(alpha: theme.entryTintOpacity),
    theme.surface,
  );
}

/// The default block of Week's and Day's timed grid: the entry's tint with
/// a 4 px edge of its colour, its title, and on a [detailed] block its
/// times beside the title, an arrow at each end the grid's hours cut, all
/// dimmed and beside an activity indicator while the entry is pending.
///
/// The text is laid out at its own height and clipped to the block, so a
/// block the board lays out at a new extent each frame neither overflows
/// nor rebuilds.
Widget defaultCalendarBlockBuilder<T>(
  BuildContext context,
  CalendarShownEntry<T> entry,
  CalendarBlockDetails details,
) {
  final theme = CalendarTheme.of(context);
  final strings = CalendarLocalizations.of(context);
  final calendarEntry = entry.entry;
  final Widget lines;
  if (details.detailed) {
    lines = Padding(
      padding: const EdgeInsets.fromLTRB(6.0, 3.0, 6.0, 3.0),
      child: Wrap(
        spacing: 8.0,
        children: <Widget>[
          Text(
            calendarEntry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.detailedBlockTitleStyle.copyWith(color: theme.text),
          ),
          Text(
            strings.entryTimes(calendarEntry.start, calendarEntry.end),
            maxLines: 1,
            style: theme.detailedBlockDetailStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        ],
      ),
    );
  } else {
    lines = Padding(
      padding: const EdgeInsets.fromLTRB(4.0, 2.0, 4.0, 2.0),
      child: Text(
        calendarEntry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.blockTitleStyle.copyWith(color: theme.text),
      ),
    );
  }
  Widget block = DecoratedBox(
    decoration: BoxDecoration(
      color: _tintOf(calendarEntry.color, theme),
      border: Border(left: BorderSide(color: calendarEntry.color, width: 4.0)),
    ),
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0.0,
        maxHeight: double.infinity,
        child: lines,
      ),
    ),
  );
  if (details.cutAtStart || details.cutAtEnd) {
    block = Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        block,
        if (details.cutAtStart)
          Positioned(
            top: 0.0,
            right: 0.0,
            child: Icon(
              theme.beforeHoursIcon,
              size: 14.0,
              color: theme.textSecondary,
            ),
          ),
        if (details.cutAtEnd)
          Positioned(
            bottom: 0.0,
            right: 0.0,
            child: Icon(
              theme.afterHoursIcon,
              size: 14.0,
              color: theme.textSecondary,
            ),
          ),
      ],
    );
  }
  if (!entry.pending) {
    return block;
  }
  return Stack(
    fit: StackFit.passthrough,
    children: <Widget>[
      Opacity(opacity: theme.pendingEntryOpacity, child: block),
      const Positioned(
        top: 2.0,
        right: 2.0,
        child: CalendarActivityIndicator(size: 12.0, strokeWidth: 2.0),
      ),
    ],
  );
}

/// The default bar of Month's board and of Week's and Day's all-day strip:
/// the entry's tint holding a 4 px band of its colour and its title, and in
/// the [CalendarChipDetails.card] form its times under the title; rounded at
/// an end the entry does not continue past and square where it does, and
/// dimmed while the entry is pending.
Widget defaultCalendarChipBuilder<T>(
  BuildContext context,
  CalendarShownEntry<T> entry,
  CalendarChipDetails details,
) {
  final theme = CalendarTheme.of(context);
  final strings = CalendarLocalizations.of(context);
  final calendarEntry = entry.entry;
  const radius = Radius.circular(4.0);
  final Widget content;
  if (details.card) {
    content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          calendarEntry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: theme.monthCardTitleStyle.copyWith(color: theme.text),
        ),
        Text(
          strings.entryTimes(calendarEntry.start, calendarEntry.end),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: theme.monthCardTimeStyle.copyWith(color: theme.textSecondary),
        ),
      ],
    );
  } else {
    content = Align(
      alignment: Alignment.centerLeft,
      child: Text(
        calendarEntry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: theme.chipTitleStyle.copyWith(color: theme.text),
      ),
    );
  }
  final Widget bar = ClipRRect(
    borderRadius: BorderRadius.horizontal(
      left: details.continuesBefore ? Radius.zero : radius,
      right: details.continuesAfter ? Radius.zero : radius,
    ),
    child: ColoredBox(
      color: _tintOf(calendarEntry.color, theme),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(width: 4.0, child: ColoredBox(color: calendarEntry.color)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: content,
            ),
          ),
        ],
      ),
    ),
  );
  if (!entry.pending) {
    return bar;
  }
  return Opacity(opacity: theme.pendingEntryOpacity, child: bar);
}

/// The default card of Agenda's day list: a rounded box of the entry's
/// tint with a 4 px edge of its colour, holding its title on one line,
/// [defaultCalendarCardExtent] tall at a text scale of 1, and a
/// [calendarCardStripExtent] tall strip across its top stating
/// [CalendarCardDetails.startsAt] and one across its bottom stating
/// [CalendarCardDetails.endsAt], where given; dimmed and beside an activity
/// indicator while the entry is pending.
///
/// It reads neither [CalendarCardDetails.onEdit] nor
/// [CalendarCardDetails.onDelete], takes no gesture and offers no Edit or
/// Delete.
Widget defaultCalendarCardBuilder<T>(
  BuildContext context,
  CalendarShownEntry<T> entry,
  CalendarCardDetails details,
) {
  final theme = CalendarTheme.of(context);
  final strings = CalendarLocalizations.of(context);
  final calendarEntry = entry.entry;
  final titleStyle = theme.entryCardTitleStyle;
  final startsAt = details.startsAt;
  final endsAt = details.endsAt;
  final Widget card = ClipRRect(
    borderRadius: BorderRadius.circular(16.0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _tintOf(calendarEntry.color, theme),
        border: Border(
          left: BorderSide(color: calendarEntry.color, width: 4.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (startsAt != null) _strip(strings.startsAt(startsAt), theme),
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 8.0, 8.0, 8.0),
            child: SizedBox(
              height: _cardTitleLineOf(
                titleStyle,
                MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
              ),
              child: Text(
                calendarEntry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: titleStyle.copyWith(color: theme.text),
                strutStyle: _cardTitleStrutOf(titleStyle),
              ),
            ),
          ),
          if (endsAt != null) _strip(strings.endsAt(endsAt), theme),
        ],
      ),
    ),
  );
  if (!entry.pending) {
    return card;
  }
  return Stack(
    children: <Widget>[
      Opacity(opacity: theme.pendingEntryOpacity, child: card),
      Positioned(
        top: startsAt == null ? 8.0 : 8.0 + calendarCardStripExtent,
        right: 8.0,
        child: const CalendarActivityIndicator(size: 12.0, strokeWidth: 2.0),
      ),
    ],
  );
}

/// A [calendarCardStripExtent] tall strip of the theme's
/// [CalendarThemeData.notice] holding [label] centred on one line.
Widget _strip(String label, CalendarThemeData theme) {
  return SizedBox(
    height: calendarCardStripExtent,
    child: ColoredBox(
      color: theme.notice,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: theme.noticeStyle.copyWith(color: theme.onNotice),
        ),
      ),
    ),
  );
}

/// The default add button of a gap of Agenda's day list: a circle of the
/// theme's [CalendarThemeData.primaryTint] filling the square the list
/// gives it, holding the theme's add icon, which calls
/// [CalendarAddButtonDetails.onPressed] for a press on the circle. It
/// draws no ink.
Widget defaultCalendarAddButtonBuilder(
  BuildContext context,
  CalendarAddButtonDetails details,
) {
  final theme = CalendarTheme.of(context);
  return GestureDetector(
    onTap: details.onPressed,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: theme.primaryTint,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(theme.addEntryIcon, size: 16.0, color: theme.primary),
      ),
    ),
  );
}

/// The default loading state: a [CalendarActivityIndicator] in the theme's
/// [CalendarThemeData.primary], 36 square on the cover, and 16 square at
/// the start of a day row, centred across it.
Widget defaultCalendarLoadingBuilder(
  BuildContext context,
  CalendarLoadingState state,
) {
  switch (state.site) {
    case CalendarStateSite.cover:
      return const CalendarActivityIndicator();
    case CalendarStateSite.dayRow:
      return const Align(
        alignment: AlignmentDirectional.centerStart,
        child: CalendarActivityIndicator(size: 16.0, strokeWidth: 2.0),
      );
  }
}

/// The default failure state: the sentence
/// [CalendarLocalizations.readFailed] and a [CalendarLocalizations.retry]
/// that calls [CalendarFailureState.retry], a semantics button of its own;
/// on the cover the sentence centred above the Retry, in a day row the
/// sentence beside it. It never shows the error.
Widget defaultCalendarFailureBuilder(
  BuildContext context,
  CalendarFailureState state,
) {
  final theme = CalendarTheme.of(context);
  final strings = CalendarLocalizations.of(context);
  final retry = Semantics(
    container: true,
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: state.retry,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Text(
          strings.retry,
          style: theme.actionLabelStyle.copyWith(color: theme.primary),
        ),
      ),
    ),
  );
  final message = theme.messageStyle.copyWith(color: theme.error);
  switch (state.site) {
    case CalendarStateSite.cover:
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              strings.readFailed,
              textAlign: TextAlign.center,
              style: message,
            ),
          ),
          const SizedBox(height: 12.0),
          retry,
        ],
      );
    case CalendarStateSite.dayRow:
      return Row(
        children: <Widget>[
          Expanded(child: Text(strings.readFailed, style: message)),
          retry,
        ],
      );
  }
}
