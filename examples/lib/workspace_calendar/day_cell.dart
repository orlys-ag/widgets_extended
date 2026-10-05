/// One day of the workspace calendar grid.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'calendar_data.dart';
import 'harbor_theme.dart';

/// The key of the cell showing [day].
ValueKey<String> dayCellKey(DateTime day) {
  return ValueKey<String>("day-${day.year}-${day.month}-${day.day}");
}

/// A day number with its task marker, on a pill when selected.
///
/// [collapse] runs from 0, the month grid, to 1, the week strip. At 0 a
/// day outside the shown month is muted and the weekday name is left to
/// the header above the grid; at 1 every day reads at full strength and
/// carries its own weekday name under the number, and the pill turns from
/// a wide lozenge into a tall tab. The cell listens to [collapse] itself,
/// so the transition rebuilds the cells and not the board.
class DayCell extends StatelessWidget {
  const DayCell({
    super.key,
    required this.day,
    required this.inMonth,
    required this.isSelected,
    required this.isToday,
    required this.hasTasks,
    required this.collapse,
  });

  final DateTime day;
  final bool inMonth;
  final bool isSelected;
  final bool isToday;
  final bool hasTasks;
  final Animation<double> collapse;

  @override
  Widget build(BuildContext context) {
    final name = weekdayNames[weekdayColumn(day)];
    final date = "${monthNames[day.month - 1]} ${day.day}";
    return Semantics(
      button: true,
      selected: isSelected,
      label: hasTasks ? "$name, $date, has tasks" : "$name, $date",
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
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          "${day.day}",
          style: TextStyle(
            fontSize: 16.0,
            height: 1.25,
            fontWeight: numberWeight,
            color: numberColor,
          ),
        ),
        ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: Opacity(
              opacity: t,
              child: Text(
                weekdayShortNames[weekdayColumn(day)],
                style: TextStyle(
                  fontSize: 12.0,
                  height: 1.25,
                  color: isSelected
                      ? HarborColors.onPrimary
                      : HarborColors.textMuted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3.0),
        _buildMarker(),
      ],
    );
    return Center(
      child: Container(
        width: lerpDouble(44.0, 36.0, t),
        height: lerpDouble(38.0, 46.0, t),
        alignment: Alignment.center,
        decoration: isSelected
            ? BoxDecoration(
                color: HarborColors.primary,
                borderRadius: BorderRadius.circular(lerpDouble(19.0, 6.0, t)!),
              )
            : null,
        child: content,
      ),
    );
  }

  /// A dot on the selected pill, a ring elsewhere, and the same space
  /// when the day has no tasks, so every number sits at the same height.
  Widget _buildMarker() {
    if (!hasTasks) {
      return const SizedBox(width: 5.0, height: 5.0);
    }
    if (isSelected) {
      return const SizedBox(
        width: 5.0,
        height: 5.0,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: HarborColors.onPrimary,
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: 4.0, height: 4.0),
          ),
        ),
      );
    }
    return Container(
      width: 5.0,
      height: 5.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HarborColors.primary, width: 1.2),
      ),
    );
  }
}
