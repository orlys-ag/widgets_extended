/// One day of the calendar's month grid, and the letters or the
/// three-letter names of the weekdays over the grid.
library;

import 'package:flutter/widgets.dart';

import '../dates/calendar_dates.dart';
import '../dates/calendar_labels.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';

/// The key of the cell showing [day].
ValueKey<String> dayCellKey(DateTime day) {
  return ValueKey<String>("day-${day.year}-${day.month}-${day.day}");
}

/// Builds [builder] with whether [store] shows a marker for [day], and
/// builds it again only when that answer changes.
///
/// A store change reaches no cell of the month board, whose cell builder
/// re-runs only when an axis or a cell's selection changes; this listener
/// is how a cell follows the store, rebuilding only itself.
class DayMarkerListener<T> extends StatefulWidget {
  const DayMarkerListener({
    super.key,
    required this.store,
    required this.day,
    required this.builder,
  });

  final CalendarStore<T> store;
  final DateTime day;
  final Widget Function(BuildContext context, bool hasItems) builder;

  @override
  State<DayMarkerListener<T>> createState() {
    return _DayMarkerListenerState<T>();
  }
}

class _DayMarkerListenerState<T> extends State<DayMarkerListener<T>> {
  late bool _hasItems = widget.store.dayHasShownEntries(widget.day);

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStore);
  }

  @override
  void didUpdateWidget(DayMarkerListener<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.store != oldWidget.store) {
      oldWidget.store.removeListener(_handleStore);
      widget.store.addListener(_handleStore);
    }
    if (widget.store != oldWidget.store || widget.day != oldWidget.day) {
      _hasItems = widget.store.dayHasShownEntries(widget.day);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStore);
    super.dispose();
  }

  void _handleStore() {
    final hasItems = widget.store.dayHasShownEntries(widget.day);
    if (hasItems == _hasItems) {
      return;
    }
    setState(() {
      _hasItems = hasItems;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _hasItems);
  }
}

/// The diameter of a [DayCell]'s circle.
const double dayCircleSize = 32.0;

/// The space between a strip cell's label line and its circle.
const double stripLabelGap = 2.0;

/// The height of a cell of the week strip, a [DayCell] at a full collapse:
/// a line of the weekday name's style, the
/// [CalendarThemeData.stripWeekdayStyle] of the theme above [context], as
/// Text lays it out in [context], at its text style and scale, then
/// [stripLabelGap] and [dayCircleSize]. The line's height is set by the
/// style's height, whatever the line reads. Makes [context] depend on the
/// theme.
double stripCellHeight(BuildContext context) {
  final defaultStyle = DefaultTextStyle.of(context);
  final painter = TextPainter(
    text: TextSpan(
      text: weekdayAbbreviations.first,
      style: defaultStyle.style.merge(_DayCellStyles.of(context).stripWeekday),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior:
        defaultStyle.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
    maxLines: 1,
  )..layout();
  final line = painter.height;
  painter.dispose();
  return line + stripLabelGap + dayCircleSize;
}

/// The key of the badge on the circle of a [DayCell] for [day] that has
/// items.
ValueKey<String> dayBadgeKey(DateTime day) {
  return ValueKey<String>("day-badge-${day.year}-${day.month}-${day.day}");
}

/// What a [DayCell] and a [WeekdayHeader] draw with, made from one
/// [CalendarThemeData] by [forTheme] and never changed.
@immutable
class _DayCellStyles {
  _DayCellStyles._(this.theme)
    : selectedNumber = theme.dayNumberMarkedStyle.copyWith(
        color: theme.onPrimary,
      ),
      todayNumber = theme.dayNumberMarkedStyle.copyWith(color: theme.primary),
      numberFrom = theme.dayNumberStyle.copyWith(color: theme.text),
      numberFromMuted = theme.dayNumberStyle.copyWith(color: theme.textMuted),
      numberTo = theme.dayNumberMarkedStyle.copyWith(color: theme.text),
      stripWeekday = theme.stripWeekdayStyle.copyWith(color: theme.textMuted),
      weekdayName = theme.weekdayHeaderStyle.copyWith(color: theme.textMuted),
      weekdayLetter = theme.weekdayLetterStyle.copyWith(color: theme.text),
      selectedCircle = BoxDecoration(
        color: theme.primary,
        shape: BoxShape.circle,
      ),
      circle = BoxDecoration(color: theme.background, shape: BoxShape.circle),
      ring = BoxDecoration(
        border: Border.all(color: theme.todayRing, width: theme.todayRingWidth),
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      ),
      badge = BoxDecoration(
        color: theme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: theme.surface, width: 1.5),
      ),
      weightOnly =
          theme.dayNumberStyle.copyWith(
            color: theme.text,
            fontWeight: theme.dayNumberMarkedStyle.fontWeight,
          ) ==
          theme.dayNumberMarkedStyle.copyWith(color: theme.text);

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _DayCellStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _DayCellStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _DayCellStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_DayCellStyles> _memo = Expando<_DayCellStyles>();
  static _DayCellStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_DayCellStyles>();
    _last = null;
  }

  final CalendarThemeData theme;
  final TextStyle selectedNumber;
  final TextStyle todayNumber;

  /// An unmarked number where the month is unfolded: in the shown month,
  /// and in another.
  final TextStyle numberFrom;
  final TextStyle numberFromMuted;

  /// Every number where the month is folded into its week.
  final TextStyle numberTo;

  /// Whether [numberFrom] and [numberTo] differ in their weight alone.
  final bool weightOnly;

  final TextStyle stripWeekday;
  final TextStyle weekdayName;
  final TextStyle weekdayLetter;
  final BoxDecoration selectedCircle;
  final BoxDecoration circle;
  final BoxDecoration ring;
  final BoxDecoration badge;

  /// The style of an unmarked number [t] of the way through the fold, for a
  /// day of the shown month when [inMonth]: the prepared style itself at
  /// either end; between them [TextStyle.lerp] of the two ends, or where
  /// they differ in weight alone, the unfolded style at the lerped weight,
  /// which keeps the colour and shadows the two ends share.
  TextStyle numberAt(double t, {required bool inMonth}) {
    final from = inMonth ? numberFrom : numberFromMuted;
    if (t <= 0.0) {
      return from;
    }
    if (t >= 1.0) {
      return numberTo;
    }
    if (!weightOnly) {
      return TextStyle.lerp(from, numberTo, t)!;
    }
    final weight = FontWeight.lerp(from.fontWeight, numberTo.fontWeight, t);
    if (inMonth) {
      return from.copyWith(fontWeight: weight);
    }
    return from.copyWith(
      fontWeight: weight,
      color: Color.lerp(theme.textMuted, theme.text, t),
    );
  }
}

/// The element of a [DayCell] and a [WeekdayHeader], which drops the
/// styles made so far on a hot reload, before its widget builds again.
class _DayCellElement extends StatelessElement {
  _DayCellElement(super.widget);

  @override
  void reassemble() {
    _DayCellStyles._reset();
    super.reassemble();
  }
}

/// A day number on a circle: the background grey, the primary colour when
/// selected, ringed when today, and with a small badge on its top right
/// corner when the day has items, in the [CalendarTheme] above it.
///
/// [collapse] runs from 0, the month grid, to 1, the week strip. At 0 a
/// day outside the shown month is muted on no circle and the weekday name
/// is left to the header above the grid; at 1 every day reads at full
/// strength on its circle and carries its weekday's three-letter name
/// above it. The
/// cell listens to [collapse] itself, so the transition rebuilds the cells
/// and not the board.
class DayCell extends StatelessWidget {
  const DayCell({
    super.key,
    required this.day,
    required this.inMonth,
    required this.isSelected,
    required this.isToday,
    required this.hasItems,
    required this.collapse,
  });

  final DateTime day;
  final bool inMonth;
  final bool isSelected;
  final bool isToday;
  final bool hasItems;
  final Animation<double> collapse;

  @override
  StatelessElement createElement() {
    return _DayCellElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final name = weekdayNames[weekdayColumn(day)];
    final date = "${monthNames[day.month - 1]} ${day.day}";
    final styles = _DayCellStyles.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: hasItems ? "$name, $date, has items" : "$name, $date",
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: collapse,
        builder: (context, child) {
          return _buildAt(collapse.value, styles);
        },
      ),
    );
  }

  Widget _buildAt(double t, _DayCellStyles styles) {
    final TextStyle numberStyle;
    if (isSelected) {
      numberStyle = styles.selectedNumber;
    } else if (isToday) {
      numberStyle = styles.todayNumber;
    } else {
      numberStyle = styles.numberAt(t, inMonth: inMonth);
    }
    final BoxDecoration fill;
    if (isSelected) {
      fill = styles.selectedCircle;
    } else if (inMonth) {
      fill = styles.circle;
    } else {
      fill = BoxDecoration(
        color: styles.theme.background.withValues(alpha: t),
        shape: BoxShape.circle,
      );
    }
    Widget circle = Container(
      width: dayCircleSize,
      height: dayCircleSize,
      alignment: Alignment.center,
      decoration: fill,
      foregroundDecoration: isToday ? styles.ring : null,
      child: Text("${day.day}", style: numberStyle),
    );
    if (hasItems) {
      circle = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          circle,
          // Centred near the circle's edge at 45 degrees, which lies
          // 0.29 of the radius in from the box's corner on each axis.
          Positioned(
            top: 0.0,
            right: 0.0,
            child: DecoratedBox(
              key: dayBadgeKey(day),
              decoration: styles.badge,
              child: const SizedBox(width: 9.0, height: 9.0),
            ),
          ),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: t,
              child: Opacity(
                opacity: t,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: stripLabelGap),
                  child: Text(
                    weekdayAbbreviations[weekdayColumn(day)],
                    style: styles.stripWeekday,
                  ),
                ),
              ),
            ),
          ),
          circle,
        ],
      ),
    );
  }
}

/// The height of a [WeekdayHeader].
const double weekdayHeaderHeight = 32.0;

/// The letters of the shown weekdays over a month grid, in [weekdays]'
/// order, or with [abbreviated] their three-letter names as a [DayCell] in
/// the week strip shows them, one per column: equal shares of the header's
/// width, or with [columnWidth], columns that wide, scrolled across by
/// [horizontal]'s offset as the grid under them is, and clipped to the
/// header.
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({
    super.key = const ValueKey<String>("weekday-header"),
    required this.weekdays,
    this.abbreviated = false,
    this.columnWidth,
    this.horizontal,
  });

  final WeekdaySet weekdays;

  /// Whether each column shows its weekday's three-letter name, "Mon",
  /// rather than its letter.
  final bool abbreviated;

  /// The width of each column; null for equal shares of the width.
  final double? columnWidth;

  /// The grid's horizontal scroll, which a header of [columnWidth] wide
  /// columns follows.
  final ScrollController? horizontal;

  @override
  StatelessElement createElement() {
    return _DayCellElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final width = columnWidth;
    final styles = _DayCellStyles.of(context);
    final letters = <Widget>[
      for (final column in weekdays.columns)
        if (width == null)
          Expanded(child: _buildLetter(column, styles))
        else
          SizedBox(width: width, child: _buildLetter(column, styles)),
    ];
    if (width == null) {
      return SizedBox(
        height: weekdayHeaderHeight,
        child: Row(children: letters),
      );
    }
    final scroll = horizontal;
    final row = Row(mainAxisSize: MainAxisSize.min, children: letters);
    return SizedBox(
      height: weekdayHeaderHeight,
      child: ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          maxWidth: double.infinity,
          child: scroll == null
              ? row
              : AnimatedBuilder(
                  animation: scroll,
                  child: row,
                  builder: (context, child) {
                    final offset = scroll.hasClients ? scroll.offset : 0.0;
                    return Transform.translate(
                      offset: Offset(-offset, 0.0),
                      child: child,
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildLetter(int column, _DayCellStyles styles) {
    if (abbreviated) {
      return Center(
        child: Text(weekdayAbbreviations[column], style: styles.weekdayName),
      );
    }
    return Center(
      child: Text(weekdayLetters[column], style: styles.weekdayLetter),
    );
  }
}
