/// The month picker the calendar header's title opens: a year's months in
/// rows, which slides from year to year.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calendar_data.dart';
import 'day_cell.dart';
import 'harbor_theme.dart';

/// The key of the month picker's cell showing [month].
ValueKey<String> monthPickerMonthKey(DateTime month) {
  return ValueKey<String>("picker-month-${month.year}-${month.month}");
}

/// How many months a row of the [MonthPicker] holds.
const int monthPickerColumns = 3;

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

  @override
  void initState() {
    super.initState();
    _year = widget.year;
  }

  @override
  void didUpdateWidget(MonthPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.year != _year) {
      _year = widget.year;
      _slideTo(widget.year);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _slideTo(int year) {
    _position.animateTo(
      year.toDouble(),
      duration: harborMotionDuration,
      curve: harborMotionCurve,
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
  static TextScaler _nameScaler(BuildContext context, double cellWidth) {
    var scaler = MediaQuery.textScalerOf(context);
    final room = math.max(
      0.0,
      cellWidth -
          MonthCell.pillMargin.horizontal -
          MonthCell.pillPadding.horizontal,
    );
    var style = DefaultTextStyle.of(context).style.merge(
      const TextStyle(
        fontSize: MonthCell.nameSize,
        fontWeight: FontWeight.w600,
      ),
    );
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
      final size = scaler.scale(MonthCell.nameSize) * (room - 0.5) / widest;
      scaler = TextScaler.linear(math.max(0.0, size) / MonthCell.nameSize);
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
/// [isSelected] and ringed as today's number is when [isCurrent]. A screen
/// reader hears the cell as a button named by the month and the year.
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

  /// The name's font size before [nameScaler].
  static const double nameSize = 15.0;

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
    final Color nameColor;
    if (isSelected) {
      nameColor = HarborColors.onPrimary;
    } else if (isCurrent) {
      nameColor = HarborColors.primary;
    } else {
      nameColor = HarborColors.text;
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
        decoration: BoxDecoration(
          color: isSelected ? HarborColors.primary : HarborColors.background,
          borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
        ),
        foregroundDecoration: isCurrent
            ? harborTodayRing(dayCircleSize / 2.0)
            : null,
        child: Text(
          monthNames[month.month - 1],
          maxLines: 1,
          softWrap: false,
          textScaler: nameScaler,
          style: TextStyle(
            fontSize: nameSize,
            fontWeight: isSelected || isCurrent
                ? FontWeight.w600
                : FontWeight.w400,
            color: nameColor,
          ),
        ),
      ),
    );
  }
}
