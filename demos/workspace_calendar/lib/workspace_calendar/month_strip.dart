/// The month picker the calendar header's title opens: a strip of months
/// side by side, as the week strip shows days, which slides month by
/// month, across years.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'calendar_data.dart';
import 'day_cell.dart';
import 'harbor_theme.dart';
import 'week_strip.dart';

/// The key of the month strip's cell showing [month].
ValueKey<String> monthStripMonthKey(DateTime month) {
  return ValueKey<String>("strip-month-${month.year}-${month.month}");
}

/// How many months the strip shows at a time.
const int monthStripCount = 7;

/// [monthStripCount] months side by side, as tall as a month
/// ([stripCellHeight]) at any text size, as the week strip is, opening
/// with [middleMonth] at its middle. Each month is a cell as the
/// week strip's days are: its three-letter name on a pill, under its year
/// in small type for January, [selectedMonth]'s filled with the primary
/// colour and [currentMonth]'s ringed as today's number is. A tap on a
/// month reports [onSelectMonth].
///
/// A horizontal drag slides the strip through the months, across years,
/// and selects nothing; a release comes to rest on a whole month, the
/// nearest to where a fling would carry the strip. While the strip moves
/// other than to follow [middleMonth], it reports each month that comes to
/// its middle through [onBrowse]. A new [middleMonth] the strip does not
/// have at its middle slides it there, after the frame, from a strip's
/// width short of it when it is further away.
class MonthStrip extends StatefulWidget {
  const MonthStrip({
    super.key,
    required this.middleMonth,
    required this.selectedMonth,
    required this.currentMonth,
    required this.onSelectMonth,
    required this.onBrowse,
  });

  /// The first day of the month at the strip's middle.
  final DateTime middleMonth;

  /// The first day of the month the strip fills.
  final DateTime selectedMonth;

  /// The first day of the month the strip rings.
  final DateTime currentMonth;

  /// Reports the first day of the month tapped.
  final ValueChanged<DateTime> onSelectMonth;

  /// Reports the first day of the month that has come to the strip's
  /// middle.
  final ValueChanged<DateTime> onBrowse;

  @override
  State<MonthStrip> createState() {
    return _MonthStripState();
  }
}

class _MonthStripState extends State<MonthStrip> {
  /// Below this, a fraction of a month's width is taken for float error in
  /// the scroll offset.
  static const double _epsilon = 1e-6;

  /// The key of the sliver of the months from index 0 on, which the scroll
  /// view centres on, so the months before index 0 lie at negative
  /// offsets.
  static const Key _forwardKey = ValueKey<String>("month-strip-forward");

  /// The month, counted as [_monthNumber] counts, at index 0: the strip's
  /// first when it was first built. Each index after or before it is the
  /// next or the previous month.
  late final int _origin =
      _monthNumber(widget.middleMonth) - monthStripCount ~/ 2;

  final ScrollController _scroll = ScrollController();

  /// The width of a month as the last layout gave it; null before it.
  double? _extent;

  /// The index of the month at the strip's middle as last seen.
  int _middle = monthStripCount ~/ 2;

  /// Whether the strip is sliding to follow [MonthStrip.middleMonth],
  /// which reports no month through [MonthStrip.onBrowse].
  bool _following = false;

  /// Counts the slides that follow [MonthStrip.middleMonth], so the end of
  /// one a later slide stopped leaves [_following] to that later one.
  int _follows = 0;

  /// Months since the start of year 0.
  static int _monthNumber(DateTime month) {
    return month.year * 12 + month.month - 1;
  }

  DateTime _monthAt(int index) {
    final number = _origin + index;
    return DateTime(number ~/ 12, number % 12 + 1);
  }

  @override
  void didUpdateWidget(MonthStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.middleMonth != oldWidget.middleMonth &&
        _monthNumber(widget.middleMonth) - _origin != _middle) {
      // After the frame, because a scroll dispatches scroll notifications,
      // which must not reach their listeners mid-build.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _showMiddle();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Slides the strip so [MonthStrip.middleMonth] is at its middle, from a
  /// strip's width short of it where it is further, so the slide is as
  /// fast whatever the distance.
  void _showMiddle() {
    final extent = _extent;
    if (!mounted || !_scroll.hasClients || extent == null) {
      return;
    }
    final target =
        (_monthNumber(widget.middleMonth) - _origin - monthStripCount ~/ 2) *
        extent;
    final width = monthStripCount * extent;
    final distance = target - _scroll.position.pixels;
    final follow = ++_follows;
    _following = true;
    if (distance.abs() > width) {
      _scroll.jumpTo(target - distance.sign * width);
    }
    _scroll
        .animateTo(
          target,
          duration: harborMotionDuration,
          curve: harborMotionCurve,
        )
        .whenComplete(() {
          if (follow == _follows) {
            _following = false;
          }
        });
  }

  /// Keeps the month at the strip's start where a new width gives a month
  /// a new [extent]. Called from the layout callback, before the scroll
  /// view lays out at the offset it corrects.
  void _keepFirstMonth(double extent) {
    final old = _extent;
    _extent = extent;
    if (old == null || old == extent || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    position.correctPixels(position.pixels / old * extent);
  }

  /// Reports a new month at the middle while the strip moves other than to
  /// follow [MonthStrip.middleMonth].
  bool _handleScroll(ScrollNotification notification) {
    final extent = _extent;
    if (notification.depth != 0 ||
        extent == null ||
        notification is! ScrollUpdateNotification) {
      return false;
    }
    final start = notification.metrics.pixels / extent;
    final middle = (start + monthStripCount / 2 + _epsilon).floor();
    if (middle != _middle) {
      _middle = middle;
      if (!_following) {
        widget.onBrowse(_monthAt(middle));
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: stripCellHeight(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extent = constraints.maxWidth / monthStripCount;
          _keepFirstMonth(extent);
          return NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: CustomScrollView(
              scrollDirection: Axis.horizontal,
              controller: _scroll,
              physics: const StripSnapPhysics(cellCount: monthStripCount),
              scrollBehavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              center: _forwardKey,
              slivers: <Widget>[
                SliverFixedExtentList(
                  itemExtent: extent,
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildMonth(_monthAt(-1 - index));
                  }),
                ),
                SliverFixedExtentList(
                  key: _forwardKey,
                  itemExtent: extent,
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildMonth(_monthAt(index));
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonth(DateTime month) {
    return GestureDetector(
      key: monthStripMonthKey(month),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onSelectMonth(month);
      },
      child: MonthCell(
        month: month,
        isSelected: month == widget.selectedMonth,
        isCurrent: month == widget.currentMonth,
      ),
    );
  }
}

/// One month of the [MonthStrip]: its three-letter name on a pill as tall
/// as a [DayCell]'s circle, filled with the primary colour when
/// [isSelected] and ringed as today's number is when [isCurrent], under a
/// line that holds the year in small muted type for January, where a year
/// starts, and is empty for every other month, so the pills line up. A
/// screen reader hears it as a button named by the month and the year.
class MonthCell extends StatelessWidget {
  const MonthCell({
    super.key,
    required this.month,
    required this.isSelected,
    required this.isCurrent,
  });

  /// The first day of the month the cell shows.
  final DateTime month;

  final bool isSelected;
  final bool isCurrent;

  /// The pill's width, which holds a three-letter name.
  static const double pillWidth = 44.0;

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
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: stripLabelGap),
              // The forced strut gives the empty line the year's height,
              // which an empty paragraph would otherwise take from the
              // font.
              child: Text(
                month.month == DateTime.january ? "${month.year}" : "",
                maxLines: 1,
                softWrap: false,
                strutStyle: StrutStyle.fromTextStyle(
                  stripLabelStyle,
                  forceStrutHeight: true,
                ),
                style: stripLabelStyle,
              ),
            ),
            Container(
              width: pillWidth,
              height: dayCircleSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? HarborColors.primary
                    : HarborColors.background,
                borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
              ),
              foregroundDecoration: isCurrent
                  ? harborTodayRing(dayCircleSize / 2.0)
                  : null,
              child: Text(
                monthShortNames[month.month - 1],
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 15.0,
                  fontWeight: isSelected || isCurrent
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: nameColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
