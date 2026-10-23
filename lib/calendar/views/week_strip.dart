/// The strip of a week's worth of days over Day mode's grid and in place
/// of Agenda's folded month, which slides day by day.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../dates/calendar_dates.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';
import 'day_cell.dart';

/// The key of the week strip's cell showing [day].
ValueKey<String> weekStripDayKey(DateTime day) {
  return ValueKey<String>("strip-day-${isoDate(day)}");
}

/// As many days side by side as [weekdays] holds of a week, opening on the
/// shown days of [initialDay]'s week, or where it is null [selectedDay]'s,
/// which starts on [weekdays]' first weekday. Each is a [DayCell]
/// as Agenda's folded month shows it: its weekday's three-letter name
/// over its number on a circle, the selected day's in the primary colour,
/// today's ringed, and a badge on a day with items once the store has read
/// it. The strip is as tall as a day ([stripCellHeight]), at any text
/// size. A tap on a day reports [onSelectDay].
///
/// A horizontal drag slides the strip through the shown days, one after
/// another across weeks and months, and selects nothing; a release comes
/// to rest on a whole day, the nearest to where a fling would carry the
/// strip. While the strip moves other than to follow the selected day, it
/// reports each day that comes to its middle through [onBrowse]; once it
/// rests, it asks the store to read the shown days of the weeks of the
/// days it shows, so their markers show, and Day, which reads
/// a selected day's whole week, shows any of them at once on a tap. A new
/// [selectedDay] the strip does not show the middle of brings the strip,
/// after the frame, to the shown days of that day's week, sliding there
/// over the [CalendarTheme]'s motion, or at once where its duration is
/// zero, from a week short of them when they are further away; a new
/// [recalls] does too, wherever [selectedDay] is.
///
/// [weekdays] are fixed for the strip's life: give a strip that changes
/// them its own key.
class WeekStrip<T> extends StatefulWidget {
  const WeekStrip({
    super.key,
    required this.store,
    required this.selectedDay,
    required this.today,
    required this.weekdays,
    required this.onSelectDay,
    required this.onBrowse,
    this.recalls = 0,
    this.initialDay,
  });

  final CalendarStore<T> store;

  /// The selected day, on a weekday [weekdays] holds.
  final DateTime selectedDay;

  /// The day the strip marks as today.
  final DateTime today;

  final WeekdaySet weekdays;
  final ValueChanged<DateTime> onSelectDay;

  /// Reports the day that has come to the middle of the strip, which for an
  /// odd count of days is in the month most of the days it shows are in.
  final ValueChanged<DateTime> onBrowse;

  /// Counts the calls to bring the strip back to [selectedDay]'s week,
  /// from wherever a drag left it, even where it shows [selectedDay].
  final int recalls;

  /// A day of the week the strip opens on; null opens it on
  /// [selectedDay]'s.
  final DateTime? initialDay;

  @override
  State<WeekStrip<T>> createState() {
    return _WeekStripState<T>();
  }
}

class _WeekStripState<T> extends State<WeekStrip<T>> {
  /// Below this, a fraction of a day width is taken for float error in
  /// the scroll offset.
  static const double _epsilon = 1e-6;

  /// The key of the sliver of the days from index 0 on, which the scroll
  /// view centres on, so the days before index 0 lie at negative offsets.
  static const Key _forwardKey = ValueKey<String>("strip-forward");

  /// The first day of the week the strip opened on. Index 0 is that week's
  /// first shown day, and each index after or before it the next or the
  /// previous shown day.
  late final DateTime _origin = widget.weekdays.weekStartOf(
    widget.initialDay ?? widget.selectedDay,
  );

  /// The days from a week's first day to each weekday [WeekStrip.weekdays]
  /// holds, ascending.
  late final List<int> _columns = <int>[
    for (final column in widget.weekdays.columns)
      widget.weekdays.offsetOf(column),
  ];

  final ScrollController _scroll = ScrollController();

  /// The width of a day as the last layout gave it; null before it.
  double? _extent;

  /// The index of the day at the strip's middle as last seen.
  late int _middle = _columns.length ~/ 2;

  /// Whether the strip is moving to follow the selected day, which
  /// reports no day through [WeekStrip.onBrowse].
  bool _following = false;

  /// Counts the slides that follow the selected day, so the end of one a
  /// later slide stopped leaves [_following] to that later one.
  int _follows = 0;

  /// The theme above the strip, whose motion a slide takes when it starts.
  late CalendarThemeData _theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = CalendarTheme.of(context);
  }

  @override
  void didUpdateWidget(WeekStrip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.weekdays == oldWidget.weekdays,
      "A WeekStrip keeps its weekdays; give a strip that changes them its "
      "own key.",
    );
    // Any new selected day, even one the strip showed, since a drag may
    // have moved it away since.
    final recalled = widget.recalls != oldWidget.recalls;
    if (recalled || widget.selectedDay != oldWidget.selectedDay) {
      // After the frame, because a scroll dispatches scroll notifications,
      // which must not reach their listeners mid-build.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _showSelected(always: recalled);
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
    final offset = _columns[index - week * _count];
    return addDays(_origin, week * DateTime.daysPerWeek + offset);
  }

  /// The index of [day], or where [day] is not shown, of the first shown
  /// day after it.
  int _indexOf(DateTime day) {
    final days = daysBetween(_origin, day);
    final week = _floorDiv(days, DateTime.daysPerWeek);
    final offset = days - week * DateTime.daysPerWeek;
    var position = 0;
    while (position < _count && _columns[position] < offset) {
      position++;
    }
    return week * _count + position;
  }

  /// Slides the strip to the shown days of the selected day's week where
  /// the middle of that day's cell lies outside it, or [always]. Days more
  /// than a week away are jumped to a week short of first, so the slide is
  /// a week's at most, as fast whatever the distance.
  void _showSelected({required bool always}) {
    final extent = _extent;
    if (!mounted || !_scroll.hasClients || extent == null) {
      return;
    }
    final position = _scroll.position;
    final middle = (_indexOf(widget.selectedDay) + 0.5) * extent;
    if (!always &&
        middle >= position.pixels &&
        middle <= position.pixels + position.viewportDimension) {
      return;
    }
    final target =
        _indexOf(widget.weekdays.weekStartOf(widget.selectedDay)) * extent;
    final week = _count * extent;
    final distance = target - position.pixels;
    final follow = ++_follows;
    _following = true;
    if (distance.abs() > week) {
      _scroll.jumpTo(target - distance.sign * week);
    }
    final duration = _theme.motionDuration;
    if (duration <= Duration.zero) {
      // The jump dispatches its scroll notifications before it returns, so
      // the follow ends here.
      _scroll.jumpTo(target);
      if (follow == _follows) {
        _following = false;
      }
      return;
    }
    _scroll
        .animateTo(target, duration: duration, curve: _theme.motionCurve)
        .whenComplete(() {
          if (follow == _follows) {
            _following = false;
          }
        });
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
      widget.store.prefetch(
        shownDaysOfWeek(first, widget.weekdays).first,
        shownDaysOfWeek(last, widget.weekdays).last,
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: stripCellHeight(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extent = constraints.maxWidth / _count;
          _keepFirstDay(extent);
          return NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: CustomScrollView(
              scrollDirection: Axis.horizontal,
              controller: _scroll,
              physics: StripSnapPhysics(cellCount: _count),
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
      child: DayMarkerListener<T>(
        store: widget.store,
        day: day,
        builder: (context, hasEntries) {
          return DayCell(
            day: day,
            inMonth: true,
            isSelected: day == widget.selectedDay,
            isToday: day == widget.today,
            hasEntries: hasEntries,
            collapse: kAlwaysCompleteAnimation,
          );
        },
      ),
    );
  }
}

/// Scroll physics that bring a release, a fling or a wheel's scroll to
/// rest on a whole cell, a day of the week strip or a month of the month
/// strip: the one nearest to where the parent's physics would bring it to
/// rest, a cell being the viewport's width over [cellCount]. Read from the
/// metrics, so a new width needs no new physics, which a scroll view only
/// takes up for a new type of physics.
class StripSnapPhysics extends ScrollPhysics {
  const StripSnapPhysics({required this.cellCount, super.parent});

  final int cellCount;

  @override
  StripSnapPhysics applyTo(ScrollPhysics? ancestor) {
    return StripSnapPhysics(
      cellCount: cellCount,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final extent = position.viewportDimension / cellCount;
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
