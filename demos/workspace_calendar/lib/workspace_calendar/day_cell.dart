/// One day of the workspace calendar grid, and the letters or the
/// three-letter names of the weekdays over the grid.
library;

import 'package:flutter/material.dart';

import 'calendar_data.dart';
import 'calendar_model.dart';
import 'harbor_theme.dart';

/// The key of the cell showing [day].
ValueKey<String> dayCellKey(DateTime day) {
  return ValueKey<String>("day-${day.year}-${day.month}-${day.day}");
}

/// Builds [builder] with whether [model] shows a marker for [day], and
/// builds it again only when that answer changes.
///
/// A model change reaches no cell of the month board, whose cell builder
/// re-runs only when an axis or a cell's selection changes; this listener
/// is how a cell follows the model, rebuilding only itself.
class DayMarkerListener extends StatefulWidget {
  const DayMarkerListener({
    super.key,
    required this.model,
    required this.day,
    required this.builder,
  });

  final CalendarModel model;
  final DateTime day;
  final Widget Function(BuildContext context, bool hasItems) builder;

  @override
  State<DayMarkerListener> createState() {
    return _DayMarkerListenerState();
  }
}

class _DayMarkerListenerState extends State<DayMarkerListener> {
  late bool _hasItems = widget.model.dayHasShownItems(widget.day);

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_handleModel);
  }

  @override
  void didUpdateWidget(DayMarkerListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.model != oldWidget.model) {
      oldWidget.model.removeListener(_handleModel);
      widget.model.addListener(_handleModel);
    }
    if (widget.model != oldWidget.model || widget.day != oldWidget.day) {
      _hasItems = widget.model.dayHasShownItems(widget.day);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_handleModel);
    super.dispose();
  }

  void _handleModel() {
    final hasItems = widget.model.dayHasShownItems(widget.day);
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

/// The style of the line over a strip cell's circle or pill: a [DayCell]'s
/// weekday name and a MonthCell's year.
const TextStyle stripLabelStyle = TextStyle(
  fontSize: 12.0,
  height: 1.2,
  color: HarborColors.textMuted,
);

/// The space between a strip cell's label line and its circle or pill.
const double stripLabelGap = 2.0;

/// The height of a cell of the week or the month strip, a [DayCell] at a
/// full collapse or a MonthCell: a line of [stripLabelStyle] as Text lays
/// it out in [context], at its text style and scale, then [stripLabelGap]
/// and [dayCircleSize]. The line's height is set by the style's height,
/// whatever the line reads.
double stripCellHeight(BuildContext context) {
  final defaultStyle = DefaultTextStyle.of(context);
  final painter = TextPainter(
    text: TextSpan(
      text: weekdayAbbreviations.first,
      style: defaultStyle.style.merge(stripLabelStyle),
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

/// A day number on a circle: the background grey, the primary colour when
/// selected, ringed ([harborTodayRing]) when today, and with a small badge
/// on its top right corner when the day has items.
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
  Widget build(BuildContext context) {
    final name = weekdayNames[weekdayColumn(day)];
    final date = "${monthNames[day.month - 1]} ${day.day}";
    return Semantics(
      button: true,
      selected: isSelected,
      label: hasItems ? "$name, $date, has items" : "$name, $date",
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: collapse,
        builder: (context, child) {
          return _buildAt(collapse.value);
        },
      ),
    );
  }

  Widget _buildAt(double t) {
    final Color numberColor;
    if (isSelected) {
      numberColor = HarborColors.onPrimary;
    } else if (isToday) {
      numberColor = HarborColors.primary;
    } else if (inMonth) {
      numberColor = HarborColors.text;
    } else {
      numberColor = Color.lerp(HarborColors.textMuted, HarborColors.text, t)!;
    }
    final numberWeight = isSelected || isToday
        ? FontWeight.w600
        : FontWeight.lerp(FontWeight.w400, FontWeight.w600, t)!;
    final Color fill;
    if (isSelected) {
      fill = HarborColors.primary;
    } else if (inMonth) {
      fill = HarborColors.background;
    } else {
      fill = HarborColors.background.withValues(alpha: t);
    }
    Widget circle = Container(
      width: dayCircleSize,
      height: dayCircleSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      foregroundDecoration: isToday
          ? harborTodayRing(dayCircleSize / 2.0)
          : null,
      child: Text(
        "${day.day}",
        style: TextStyle(
          fontSize: 15.0,
          fontWeight: numberWeight,
          color: numberColor,
        ),
      ),
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
              decoration: BoxDecoration(
                color: HarborColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: HarborColors.surface, width: 1.5),
              ),
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
                    style: stripLabelStyle,
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
  Widget build(BuildContext context) {
    final width = columnWidth;
    final letters = <Widget>[
      for (final column in weekdays.columns)
        if (width == null)
          Expanded(child: _buildLetter(column))
        else
          SizedBox(width: width, child: _buildLetter(column)),
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

  Widget _buildLetter(int column) {
    if (abbreviated) {
      return Center(
        child: Text(
          weekdayAbbreviations[column],
          style: const TextStyle(fontSize: 12.0, color: HarborColors.textMuted),
        ),
      );
    }
    return Center(
      child: Text(
        weekdayLetters[column],
        style: const TextStyle(
          fontSize: 15.0,
          fontWeight: FontWeight.w600,
          color: HarborColors.text,
        ),
      ),
    );
  }
}
