/// The strip of a week's worth of days over Day mode's grid and in place
/// of Agenda's folded month, which slides day by day.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'calendar_data.dart';
import 'calendar_model.dart';
import 'day_cell.dart';
import 'harbor_theme.dart';

/// The key of the week strip's cell showing [day].
ValueKey<String> weekStripDayKey(DateTime day) {
  return ValueKey<String>("strip-day-${isoDate(day)}");
}

/// The strip's height, which is a row of Agenda's month grid.
const double weekStripHeight = 48.0;

/// As many days side by side as [weekdays] holds of a week, opening on the
/// shown days of [selectedDay]'s Monday-to-Sunday week. Each is a [DayCell]
/// as Agenda's folded month shows it: its weekday's three-letter name
/// over its number on a circle, the selected day's in the primary colour,
/// today's ringed, and a badge on a day with items once the model has read
/// it. A tap on a day reports [onSelectDay].
///
/// A horizontal drag slides the strip through the shown days, one after
/// another across weeks and months, and selects nothing; a release comes
/// to rest on a whole day, the nearest to where a fling would carry the
/// strip. While the strip moves other than to follow the selected day, it
/// reports each day that comes to its middle through [onBrowse]; once it
/// rests, it asks the model to read the shown days of the Monday-to-Sunday
/// weeks of the days it shows, so their markers show, and Day, which reads
/// a selected day's whole week, shows any of them at once on a tap. A new
/// [selectedDay] the strip does not show the middle of brings the strip,
/// after the frame, to the shown days of that day's week, sliding when
/// they are at most a week away and jumping otherwise.
///
/// [weekdays] are fixed for the strip's life: give a strip that changes
/// them its own key.
class WeekStrip extends StatefulWidget {
  const WeekStrip({
    super.key,
    required this.model,
    required this.selectedDay,
    required this.today,
    required this.weekdays,
    required this.onSelectDay,
    required this.onBrowse,
  });

  final CalendarModel model;

  /// The selected day, on a weekday [weekdays] holds.
  final DateTime selectedDay;

  /// The day the strip marks as today.
  final DateTime today;

  final WeekdaySet weekdays;
  final ValueChanged<DateTime> onSelectDay;

  /// Reports the day that has come to the middle of the strip, which for an
  /// odd count of days is in the month most of the days it shows are in.
  final ValueChanged<DateTime> onBrowse;

  @override
  State<WeekStrip> createState() {
    return _WeekStripState();
  }
}

class _WeekStripState extends State<WeekStrip> {
  /// Below this, a fraction of a day width is taken for float error in
  /// the scroll offset.
  static const double _epsilon = 1e-6;

  /// The key of the sliver of the days from index 0 on, which the scroll
  /// view centres on, so the days before index 0 lie at negative offsets.
  static const Key _forwardKey = ValueKey<String>("strip-forward");

  /// The Monday of [WeekStrip.selectedDay]'s week when the strip was
  /// first built. Index 0 is that week's first shown day, and each index
  /// after or before it the next or the previous shown day.
  late final DateTime _origin = weekStartOf(widget.selectedDay);

  /// The weekday columns [WeekStrip.weekdays] holds, ascending.
  late final List<int> _columns = <int>[
    for (var column = 0; column < DateTime.daysPerWeek; column++)
      if (widget.weekdays.containsColumn(column)) column,
  ];

  final ScrollController _scroll = ScrollController();

  /// The width of a day as the last layout gave it; null before it.
  double? _extent;

  /// The index of the day at the strip's middle as last seen.
  late int _middle = _columns.length ~/ 2;

  /// Whether the strip is moving to follow the selected day, which
  /// reports no day through [WeekStrip.onBrowse].
  bool _following = false;

  @override
  void didUpdateWidget(WeekStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.weekdays == oldWidget.weekdays,
      "A WeekStrip keeps its weekdays; give a strip that changes them its "
      "own key.",
    );
    // Any new selected day, even one the strip showed, since a drag may
    // have moved it away since.
    if (widget.selectedDay != oldWidget.selectedDay) {
      // After the frame, because a scroll dispatches scroll notifications,
      // which must not reach their listeners mid-build.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _showSelected();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _count {
    return _columns.length;
  }

  /// [a] divided by the positive [b], rounded down.
  static int _floorDiv(int a, int b) {
    return (a - a % b) ~/ b;
  }

  /// The day at [index].
  DateTime _dayAt(int index) {
    final week = _floorDiv(index, _count);
    final column = _columns[index - week * _count];
    return addDays(_origin, week * DateTime.daysPerWeek + column);
  }

  /// The index of [day], or where [day] is not shown, of the first shown
  /// day after it.
  int _indexOf(DateTime day) {
    final days = daysBetween(_origin, day);
    final week = _floorDiv(days, DateTime.daysPerWeek);
    final column = days - week * DateTime.daysPerWeek;
    var position = 0;
    while (position < _count && _columns[position] < column) {
      position++;
    }
    return week * _count + position;
  }

  /// Brings the strip to the shown days of the selected day's week where
  /// the middle of that day's cell lies outside it.
  void _showSelected() {
    final extent = _extent;
    if (!mounted || !_scroll.hasClients || extent == null) {
      return;
    }
    final position = _scroll.position;
    final middle = (_indexOf(widget.selectedDay) + 0.5) * extent;
    if (middle >= position.pixels &&
        middle <= position.pixels + position.viewportDimension) {
      return;
    }
    final target = _indexOf(weekStartOf(widget.selectedDay)) * extent;
    _following = true;
    if ((target - position.pixels).abs() <= _count * extent) {
      _scroll
          .animateTo(
            target,
            duration: harborMotionDuration,
            curve: harborMotionCurve,
          )
          .whenComplete(() {
            _following = false;
          });
    } else {
      _scroll.jumpTo(target);
      _following = false;
    }
  }

  /// Keeps the day at the strip's start where a new width gives a day a
  /// new [extent]. Called from the layout callback, before the scroll view
  /// lays out at the offset it corrects.
  void _keepFirstDay(double extent) {
    final old = _extent;
    _extent = extent;
    if (old == null || old == extent || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    position.correctPixels(position.pixels / old * extent);
  }

  /// Reports a new day at the middle while the strip moves other than to
  /// follow the selected day, and reads the weeks of the days it shows
  /// once it rests.
  bool _handleScroll(ScrollNotification notification) {
    final extent = _extent;
    if (notification.depth != 0 || extent == null) {
      return false;
    }
    final metrics = notification.metrics;
    final start = metrics.pixels / extent;
    if (notification is ScrollUpdateNotification) {
      final middle = (start + _count / 2 + _epsilon).floor();
      if (middle != _middle) {
        _middle = middle;
        if (!_following) {
          widget.onBrowse(_dayAt(middle));
        }
      }
    } else if (notification is ScrollEndNotification) {
      final first = _dayAt((start + _epsilon).floor());
      final last = _dayAt((start + _count - _epsilon).ceil() - 1);
      widget.model.prefetch(
        shownDaysOfWeek(first, widget.weekdays).first,
        shownDaysOfWeek(last, widget.weekdays).last,
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: weekStripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extent = constraints.maxWidth / _count;
          _keepFirstDay(extent);
          return NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: CustomScrollView(
              scrollDirection: Axis.horizontal,
              controller: _scroll,
              physics: _DaySnapPhysics(dayCount: _count),
              scrollBehavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              center: _forwardKey,
              slivers: <Widget>[
                SliverFixedExtentList(
                  itemExtent: extent,
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildDay(_dayAt(-1 - index));
                  }),
                ),
                SliverFixedExtentList(
                  key: _forwardKey,
                  itemExtent: extent,
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildDay(_dayAt(index));
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDay(DateTime day) {
    return GestureDetector(
      key: weekStripDayKey(day),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onSelectDay(day);
      },
      child: DayMarkerListener(
        model: widget.model,
        day: day,
        builder: (context, hasItems) {
          return DayCell(
            day: day,
            inMonth: true,
            isSelected: day == widget.selectedDay,
            isToday: day == widget.today,
            hasItems: hasItems,
            collapse: kAlwaysCompleteAnimation,
          );
        },
      ),
    );
  }
}

/// Scroll physics that bring a release, a fling or a wheel's scroll to
/// rest on a whole day: the one nearest to where the parent's physics
/// would bring it to rest, a day being the viewport's width over
/// [dayCount]. Read from the metrics, so a new width needs no new physics,
/// which a scroll view only takes up for a new type of physics.
class _DaySnapPhysics extends ScrollPhysics {
  const _DaySnapPhysics({required this.dayCount, super.parent});

  final int dayCount;

  @override
  _DaySnapPhysics applyTo(ScrollPhysics? ancestor) {
    return _DaySnapPhysics(dayCount: dayCount, parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final extent = position.viewportDimension / dayCount;
    final free = super.createBallisticSimulation(position, velocity);
    final rest = free?.x(double.infinity) ?? position.pixels;
    final target = (rest / extent).roundToDouble() * extent;
    final tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}
