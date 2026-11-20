/// The strip of a week's worth of days over Day mode's grid and in place
/// of Agenda's folded month, which slides day by day.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_theme.dart';
import 'day_cell.dart';

/// The key of the week strip's cell showing [day].
ValueKey<String> weekStripDayKey(DateTime day) {
  return ValueKey<String>("strip-day-${CalendarDates.isoDate(day)}");
}

/// As many days side by side as [weekdays] holds of a week, opening with
/// [initialMiddleDay] at its middle, or else on the shown days of
/// [initialDay]'s week, or where it is null [selectedDay]'s, which starts
/// on [weekdays]' first weekday. Each is a [DayCell]
/// as Agenda's folded month shows it: its weekday's abbreviation
/// over its number on a circle, the selected day's in the primary colour,
/// today's ringed, and badges on a day with items once the store has read
/// it, one for each kind [dayBadges] gives its entries. The strip is as tall as a day ([stripCellHeight]), at any text
/// size. A tap on a day reports [onSelectDay]. A day [isDayEnabled]
/// refuses draws disabled and takes no tap, and with no [onSelectDay] no
/// day takes one.
///
/// A horizontal drag slides the strip through the shown days, one after
/// another across weeks and months, and selects nothing; a release comes
/// to rest on a whole day, the nearest to where a fling would carry the
/// strip. While the strip moves other than to follow the selected day, it
/// reports each day that comes to its middle through [onBrowse]; once it
/// rests, and after the frame that gives it a new [store], it asks the
/// store to read the shown days of the weeks of the days it shows, so
/// their markers show, and Day, which reads
/// a selected day's whole week, shows any of them at once on a tap. A new
/// [selectedDay] the strip does not show the middle of brings the strip,
/// after the frame, to the shown days of that day's week, sliding there
/// over the [CalendarTheme]'s motion, or at once where its duration is
/// zero, from a week short of them when they are further away; a new
/// [recalls] does too, wherever [selectedDay] is, to the shown days of
/// [recallDay]'s week where it is given.
///
/// With [browseFrom], the strip opens, slides, follows and recalls no
/// further back than that day's week, whose first shown day is the first
/// it shows.
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
    this.onTapDay,
    this.recalls = 0,
    this.recallDay,
    this.initialDay,
    this.initialMiddleDay,
    this.dayBadges,
    this.isDayEnabled,
    this.browseFrom,
  });

  final CalendarStore<T> store;

  /// The selected day, on a weekday [weekdays] holds.
  final DateTime selectedDay;

  /// The day the strip marks as today.
  final DateTime today;

  final CalendarWeekdaySet weekdays;

  /// Reports a day tapped; null for a strip whose days take no tap.
  final ValueChanged<DateTime>? onSelectDay;

  /// Reports a day tapped, right after [onSelectDay] reports it; null
  /// reports nothing.
  final ValueChanged<DateTime>? onTapDay;

  /// Reports the day that has come to the middle of the strip, which for an
  /// odd count of days is in the month most of the days it shows are in.
  final ValueChanged<DateTime> onBrowse;

  /// Counts the calls to bring the strip back to [selectedDay]'s week,
  /// from wherever a drag left it, even where it shows [selectedDay].
  final int recalls;

  /// The day whose week a new [recalls] brings the strip to; null for
  /// [selectedDay]'s.
  final DateTime? recallDay;

  /// A day of the week the strip opens on; null opens it on
  /// [selectedDay]'s.
  final DateTime? initialDay;

  /// A day the strip opens with at its middle, as [onBrowse] reports the
  /// middle: half a week's count of shown days before it, rounded down,
  /// and the rest from it on. Where it is not a shown day, the first shown
  /// day after it. Null opens the strip as [initialDay] says.
  final DateTime? initialMiddleDay;

  /// The kinds of entry the days' badges mark; null for one primary dot
  /// on a day with entries.
  final CalendarDayBadges<T>? dayBadges;

  /// Whether a day may be picked, asked of each day's cell, a plain day
  /// (the local midnight of its date), as the cell builds; null takes
  /// every day.
  final bool Function(DateTime day)? isDayEnabled;

  /// A shown day whose week the strip slides back no further than: that
  /// week's first shown day is the first the strip shows; null for no
  /// limit. Fixed for the strip's life by its week: give a strip a limit in
  /// another week its own key.
  final DateTime? browseFrom;

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

  /// The first day of the week the strip opened on, or of
  /// [WeekStrip.browseFrom]'s where that is later. Index 0 is that week's
  /// first shown day, and each index after or before it the next or the
  /// previous shown day. A plain day, as the cells are.
  late final DateTime _origin = widget.weekdays.weekStartOf(_openingDay());

  DateTime _openingDay() {
    final day = _plainTwinOf(
      widget.initialMiddleDay ?? widget.initialDay ?? widget.selectedDay,
    );
    final from = _browseFrom;
    return from != null && from.isAfter(day) ? from : day;
  }

  /// [WeekStrip.browseFrom] as a plain day; null for no limit.
  late final DateTime? _browseFrom = widget.browseFrom == null
      ? null
      : _plainTwinOf(widget.browseFrom!);

  /// The index of the first shown day of [WeekStrip.browseFrom]'s week, 0
  /// or before it, which the strip slides back no further than; null for
  /// no limit.
  late final int? _limit = _browseFrom == null
      ? null
      : _indexOf(widget.weekdays.weekStartOf(_browseFrom));

  /// The index of the day at the strip's start as it opens: half a week's
  /// count of shown days before [WeekStrip.initialMiddleDay]'s, or where
  /// that is null 0, the first shown day of [_origin]'s week; and no index
  /// before [_limit].
  late final int _openingIndex = _openingIndexOf(widget.initialMiddleDay);

  int _openingIndexOf(DateTime? middle) {
    final index = middle == null
        ? 0
        : _indexOf(_plainTwinOf(middle)) - _count ~/ 2;
    final limit = _limit;
    return limit != null && index < limit ? limit : index;
  }

  /// [WeekStrip.selectedDay] and [WeekStrip.today] as plain days, the
  /// local midnights of their dates, which the cells, plain days stepped
  /// from [_origin], compare with by `==` however the days given are
  /// zoned. Made only where the day they twin changes.
  late DateTime _selectedDay;
  late DateTime _today;

  /// The local midnight of [day]'s date.
  static DateTime _plainTwinOf(DateTime day) {
    return CalendarDates.dateOfDayNumber(CalendarDates.dayNumber(day));
  }

  /// The days from a week's first day to each weekday [WeekStrip.weekdays]
  /// holds, ascending.
  late final List<int> _columns = <int>[
    for (final column in widget.weekdays.columns)
      widget.weekdays.offsetOf(column),
  ];

  final _OpeningScrollController _scroll = _OpeningScrollController();

  /// The width of a day as the last layout gave it; null before it.
  double? _extent;

  /// The index of the day at the strip's middle as last seen.
  late int _middle = _openingIndex + _count ~/ 2;

  /// Whether the strip is moving to follow the selected day, which
  /// reports no day through [WeekStrip.onBrowse].
  bool _following = false;

  /// Counts the slides that follow the selected day, so the end of one a
  /// later slide stopped leaves [_following] to that later one.
  int _follows = 0;

  /// Whether a frame will read the weeks of the days the strip shows.
  bool _prefetchScheduled = false;

  /// The theme above the strip, whose motion a slide takes when it starts.
  late CalendarThemeData _theme;

  @override
  void initState() {
    super.initState();
    _selectedDay = _plainTwinOf(widget.selectedDay);
    _today = _plainTwinOf(widget.today);
  }

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
    assert(
      _weekOf(widget.browseFrom) == _weekOf(oldWidget.browseFrom),
      "A WeekStrip keeps the week of its browseFrom; give a strip a limit in "
      "another week its own key.",
    );
    if (widget.today != oldWidget.today) {
      _today = _plainTwinOf(widget.today);
    }
    if (widget.store != oldWidget.store) {
      _schedulePrefetch();
    }
    // Any new selected date, even one the strip showed, since a drag may
    // have moved it away since; the same date given on another clock moves
    // nothing.
    var moved = false;
    if (widget.selectedDay != oldWidget.selectedDay) {
      final twin = _plainTwinOf(widget.selectedDay);
      moved = twin != _selectedDay;
      _selectedDay = twin;
    }
    final recalled = widget.recalls != oldWidget.recalls;
    if (recalled || moved) {
      final recallDay = widget.recallDay;
      final target = recalled && recallDay != null
          ? _plainTwinOf(recallDay)
          : _selectedDay;
      // After the frame, because a scroll dispatches scroll notifications,
      // which must not reach their listeners mid-build.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _showSelected(target, always: recalled);
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

  /// The day number of the first day of [day]'s week; null for null.
  int? _weekOf(DateTime? day) {
    if (day == null) {
      return null;
    }
    return widget.weekdays.weekStartOfDay(CalendarDates.dayNumber(day));
  }

  /// [a] divided by the positive [b], rounded down.
  static int _floorDiv(int a, int b) {
    return (a - a % b) ~/ b;
  }

  /// The day at [index].
  DateTime _dayAt(int index) {
    final week = _floorDiv(index, _count);
    final offset = _columns[index - week * _count];
    return CalendarDates.addDays(_origin, week * DateTime.daysPerWeek + offset);
  }

  /// The index of [day], or where [day] is not shown, of the first shown
  /// day after it.
  int _indexOf(DateTime day) {
    final days = CalendarDates.daysBetween(_origin, day);
    final week = _floorDiv(days, DateTime.daysPerWeek);
    final offset = days - week * DateTime.daysPerWeek;
    var position = 0;
    while (position < _count && _columns[position] < offset) {
      position++;
    }
    return week * _count + position;
  }

  /// Slides the strip to the shown days of [day]'s week, a plain day, or
  /// of [WeekStrip.browseFrom]'s where that is later, where the middle of
  /// that day's cell lies outside it, or [always]. Days more than a week
  /// away are jumped to a week short of first, so the slide is a week's at
  /// most, as fast whatever the distance.
  void _showSelected(DateTime day, {required bool always}) {
    final extent = _extent;
    if (!mounted || !_scroll.hasClients || extent == null) {
      return;
    }
    final position = _scroll.position;
    final middle = (_indexOf(day) + 0.5) * extent;
    if (!always &&
        middle >= position.pixels &&
        middle <= position.pixels + position.viewportDimension) {
      return;
    }
    var index = _indexOf(widget.weekdays.weekStartOf(day));
    final limit = _limit;
    if (limit != null && index < limit) {
      index = limit;
    }
    final target = index * extent;
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

  /// Opens the strip at [_openingIndex] where the first layout gives a day
  /// its [extent], and keeps the day at the strip's start where a new
  /// width gives it a new one. Called from the layout callback, before the
  /// scroll view makes its position or lays out at the offset it corrects.
  void _keepFirstDay(double extent) {
    final old = _extent;
    _extent = extent;
    if (old == null) {
      _scroll.opening = _openingIndex * extent;
      return;
    }
    if (old == extent || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    position.correctPixels(position.pixels / old * extent);
  }

  /// Reports a new day at the middle while the strip moves other than to
  /// follow the selected day, and reads the weeks of the days it shows
  /// once it rests, after the frame ([_schedulePrefetch]).
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
      _schedulePrefetch();
    }
    return false;
  }

  /// After the frame, reads the weeks of the days the strip shows, once
  /// however many scrolls end and stores are given in it, and asks for that
  /// frame where none is under way: a scroll can end during layout, as
  /// [BallisticScrollActivity.applyNewDimensions] ends one where the
  /// physics gives it no new simulation, when the store must not notify.
  void _schedulePrefetch() {
    if (_prefetchScheduled) {
      return;
    }
    _prefetchScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _prefetchScheduled = false;
      if (mounted) {
        _prefetchShown();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Reads the weeks of the days the strip shows.
  void _prefetchShown() {
    final extent = _extent;
    if (extent == null || !_scroll.hasClients) {
      return;
    }
    final start = _scroll.position.pixels / extent;
    final first = _dayAt((start + _epsilon).floor());
    final last = _dayAt((start + _count - _epsilon).ceil() - 1);
    widget.store.prefetch(
      CalendarDates.shownDaysOfWeek(first, widget.weekdays).first,
      CalendarDates.shownDaysOfWeek(last, widget.weekdays).last,
    );
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
                  }, childCount: _limit == null ? null : -_limit),
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
    final enabled = widget.isDayEnabled?.call(day);
    return GestureDetector(
      key: weekStripDayKey(day),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSelectDay == null || enabled == false
          ? null
          : () {
              widget.onSelectDay?.call(day);
              widget.onTapDay?.call(day);
            },
      child: DayMarkerListener<T>(
        store: widget.store,
        day: day,
        badges: widget.dayBadges,
        builder: (context, badges) {
          return DayCell(
            day: day,
            inMonth: true,
            isSelected: day == _selectedDay,
            isToday: day == _today,
            badges: badges,
            collapse: kAlwaysCompleteAnimation,
            enabled: enabled,
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

/// A [ScrollController] whose [initialScrollOffset], which a scroll view
/// reads as it makes its position, is [opening]: the week strip sets it at
/// its first layout, the first to give a day's width, before the scroll
/// view under it builds.
class _OpeningScrollController extends ScrollController {
  double opening = 0.0;

  @override
  double get initialScrollOffset {
    return opening;
  }
}
