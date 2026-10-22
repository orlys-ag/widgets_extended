/// The month picker the calendar header's title opens: a year's months in
/// rows, which slides from year to year.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../dates/calendar_labels.dart';
import '../presentation/calendar_theme.dart';
import 'day_cell.dart';

/// The key of the month picker's cell showing [month].
ValueKey<String> monthPickerMonthKey(DateTime month) {
  return ValueKey<String>("picker-month-${month.year}-${month.month}");
}

/// How many months a row of the [MonthPicker] holds.
const int monthPickerColumns = 3;

/// What a [MonthPicker] and its [MonthCell]s draw and run with, made from
/// one [CalendarThemeData] by [forTheme] and never changed.
@immutable
class _PickerStyles {
  _PickerStyles._(this.theme)
    : name = theme.monthNameStyle.copyWith(color: theme.text),
      selectedName = theme.monthNameMarkedStyle.copyWith(
        color: theme.onPrimary,
      ),
      currentName = theme.monthNameMarkedStyle.copyWith(color: theme.primary),
      pill = BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      ),
      selectedPill = BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      ),
      ring = BoxDecoration(
        border: Border.all(color: theme.todayRing, width: theme.todayRingWidth),
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      );

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _PickerStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _PickerStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _PickerStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_PickerStyles> _memo = Expando<_PickerStyles>();
  static _PickerStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_PickerStyles>();
    _last = null;
  }

  final CalendarThemeData theme;
  final TextStyle name;

  /// The selected month's name, which the picker also measures names in.
  final TextStyle selectedName;

  final TextStyle currentName;
  final BoxDecoration pill;
  final BoxDecoration selectedPill;
  final BoxDecoration ring;
}

/// [year]'s months in rows of [monthPickerColumns], January first, each
/// month a [MonthCell] on an equal share of the picker's width,
/// [selectedMonth]'s filled with the primary colour and [currentMonth]'s
/// ringed as today's number is. Every name reads at the text size, or
/// where the widest would not fit its pill at it, at the one smaller size
/// that fits it. The picker is as tall as its rows of cells. A tap on a
/// month reports [onSelectMonth].
///
/// A horizontal drag slides the picker with the finger, the next year's
/// months coming in from the right and the previous year's from the left,
/// and selects nothing; a release comes to rest on a whole year, the next
/// one the way a fling moves, and otherwise the nearest. The picker reports
/// through [onBrowse] each new year it is to rest on: the nearest while the
/// finger moves it, then the one a release slides to. A new [year] the
/// picker is not on slides it there.
class MonthPicker extends StatefulWidget {
  const MonthPicker({
    super.key,
    required this.year,
    required this.selectedMonth,
    required this.currentMonth,
    required this.onSelectMonth,
    required this.onBrowse,
  });

  /// The year whose months the picker shows.
  final int year;

  /// The first day of the month the picker fills.
  final DateTime selectedMonth;

  /// The first day of the month the picker rings.
  final DateTime currentMonth;

  /// Reports the first day of the month tapped.
  final ValueChanged<DateTime> onSelectMonth;

  /// Reports the year a drag has brought the picker to.
  final ValueChanged<int> onBrowse;

  @override
  State<MonthPicker> createState() {
    return _MonthPickerState();
  }
}

class _MonthPickerState extends State<MonthPicker>
    with SingleTickerProviderStateMixin {
  /// Below this, a fraction of a year is taken for float error in
  /// [_position].
  static const double _epsilon = 1e-6;

  /// The year over the picker, fractional while it slides: at 2026.25 the
  /// picker shows the last three quarters of 2026's months at its left and
  /// the first quarter of 2027's at its right.
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.year.toDouble(),
  );

  /// The year the picker rests on or slides to: the last [MonthPicker.year]
  /// given, or the last year reported through [MonthPicker.onBrowse] since.
  late int _year;

  /// What the picker measures names in and slides with.
  late _PickerStyles _styles;

  @override
  void initState() {
    super.initState();
    _year = widget.year;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _styles = _PickerStyles.of(context);
  }

  @override
  void didUpdateWidget(MonthPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A frame that brings a new theme with the new year calls this before
    // the rebuild that calls didChangeDependencies, so the slide below
    // reads the theme here.
    _styles = _PickerStyles.of(context);
    if (widget.year != _year) {
      _year = widget.year;
      _slideTo(widget.year);
    }
  }

  @override
  void reassemble() {
    _PickerStyles._reset();
    super.reassemble();
    _styles = _PickerStyles.of(context);
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  /// Slides to [year] over the theme's motion, or at a zero duration, in
  /// this call.
  void _slideTo(int year) {
    final theme = _styles.theme;
    _position.animateTo(
      year.toDouble(),
      duration: theme.motionDuration,
      curve: theme.motionCurve,
    );
  }

  void _report(int year) {
    if (year != _year) {
      _year = year;
      widget.onBrowse(year);
    }
  }

  void _startDrag(DragStartDetails details) {
    _position.stop();
  }

  void _drag(DragUpdateDetails details) {
    _position.value -= details.primaryDelta! / context.size!.width;
    _report(_position.value.round());
  }

  /// A fling slides to the next whole year the way it moves, and any other
  /// release, whose [DragEndDetails.primaryVelocity] is zero, to the
  /// nearest year.
  void _endDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    final position = _position.value;
    final int target;
    if (velocity < 0.0) {
      target = (position + _epsilon).floor() + 1;
    } else if (velocity > 0.0) {
      target = (position - _epsilon).ceil() - 1;
    } else {
      target = position.round();
    }
    _report(target);
    _slideTo(target);
  }

  /// The text scaler of the names on cells [cellWidth] wide: the
  /// context's, or where the widest name, as a selected cell's [Text] lays
  /// it out, would not fit a pill at it, a smaller one that fits it.
  TextScaler _nameScaler(BuildContext context, double cellWidth) {
    var scaler = MediaQuery.textScalerOf(context);
    final room = math.max(
      0.0,
      cellWidth -
          MonthCell.pillMargin.horizontal -
          MonthCell.pillPadding.horizontal,
    );
    var style = DefaultTextStyle.of(context).style.merge(_styles.selectedName);
    final fontSize = style.fontSize ?? kDefaultFontSize;
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      maxLines: 1,
    );
    // A name's width does not quite follow its font size, so a smaller
    // scaler aims half a pixel inside the pill and is measured again, until
    // the widest name fits.
    for (var tries = 0; tries < 4; tries++) {
      painter.textScaler = scaler;
      var widest = 0.0;
      for (final name in monthNames) {
        painter.text = TextSpan(text: name, style: style);
        painter.layout();
        widest = math.max(widest, painter.width);
      }
      if (widest <= room) {
        break;
      }
      final size = scaler.scale(fontSize) * (room - 0.5) / widest;
      scaler = TextScaler.linear(math.max(0.0, size) / fontSize);
    }
    painter.dispose();
    return scaler;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _startDrag,
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _endDrag,
      // The years beside the one over the picker paint outside it.
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaler = _nameScaler(
              context,
              constraints.maxWidth / monthPickerColumns,
            );
            return AnimatedBuilder(
              animation: _position,
              builder: (context, child) {
                final position = _position.value;
                final first = (position + _epsilon).floor();
                return Stack(
                  children: <Widget>[
                    _buildYearAt(first, position, scaler),
                    if (position - first > _epsilon)
                      _buildYearAt(first + 1, position, scaler),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// [year]'s months, a picker's width to the right for each year it lies
  /// past [position], their names scaled by [scaler].
  Widget _buildYearAt(int year, double position, TextScaler scaler) {
    return FractionalTranslation(
      key: ValueKey<int>(year),
      translation: Offset(year - position, 0.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var row = 0; row < 12; row += monthPickerColumns)
            Row(
              children: <Widget>[
                for (
                  var month = row + 1;
                  month <= row + monthPickerColumns;
                  month++
                )
                  Expanded(child: _buildMonth(DateTime(year, month), scaler)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMonth(DateTime month, TextScaler scaler) {
    return GestureDetector(
      key: monthPickerMonthKey(month),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onSelectMonth(month);
      },
      child: MonthCell(
        month: month,
        isSelected: month == widget.selectedMonth,
        isCurrent: month == widget.currentMonth,
        nameScaler: scaler,
      ),
    );
  }
}

/// One month of the [MonthPicker]: its full name, scaled by [nameScaler],
/// on a pill across the cell, at least as tall as a [DayCell]'s circle and
/// otherwise as tall as the name, filled with the primary colour when
/// [isSelected] and ringed as today's number is when [isCurrent], in the
/// [CalendarTheme] above it. A screen reader hears the cell as a button
/// named by the month and the year.
class MonthCell extends StatelessWidget {
  const MonthCell({
    super.key,
    required this.month,
    required this.isSelected,
    required this.isCurrent,
    required this.nameScaler,
  });

  /// The first day of the month the cell shows.
  final DateTime month;

  final bool isSelected;
  final bool isCurrent;

  /// The text scaler of the name.
  final TextScaler nameScaler;

  /// The space around the pill, which makes a row of pills at the default
  /// text size as tall as a row of the month's days.
  static const EdgeInsets pillMargin = EdgeInsets.symmetric(
    horizontal: 4.0,
    vertical: 8.0,
  );

  /// The space between the pill's ends and the name.
  static const EdgeInsets pillPadding = EdgeInsets.symmetric(horizontal: 4.0);

  @override
  Widget build(BuildContext context) {
    final styles = _PickerStyles.of(context);
    final TextStyle nameStyle;
    if (isSelected) {
      nameStyle = styles.selectedName;
    } else if (isCurrent) {
      nameStyle = styles.currentName;
    } else {
      nameStyle = styles.name;
    }
    return Semantics(
      button: true,
      selected: isSelected,
      label: "${monthNames[month.month - 1]} ${month.year}",
      excludeSemantics: true,
      child: Container(
        margin: pillMargin,
        constraints: const BoxConstraints(minHeight: dayCircleSize),
        padding: pillPadding,
        alignment: Alignment.center,
        decoration: isSelected ? styles.selectedPill : styles.pill,
        foregroundDecoration: isCurrent ? styles.ring : null,
        child: Text(
          monthNames[month.month - 1],
          maxLines: 1,
          softWrap: false,
          textScaler: nameScaler,
          style: nameStyle,
        ),
      ),
    );
  }
}
