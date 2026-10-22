/// The strip of months in Agenda's and Day's calendar card, one month at a
/// time, which slides month by month and folds into a week.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../dates/calendar_dates.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';
import 'day_cell.dart';
import 'week_strip.dart';

/// How a release of a [MonthStrip] comes to rest.
enum MonthStripSnap {
  /// On the whole month nearest to where a free fling would carry the
  /// strip, so a fast fling passes several months.
  nearest,

  /// On the next month the way a fling moves, and otherwise the nearest
  /// month, so a release moves a month at most.
  next,
}

/// The day of [month]'s week that the calendar card folds into while it
/// shows [month]: [selectedDay] where [month] holds it; otherwise [today],
/// or the shown day nearest it, where [month] holds today; otherwise
/// [month]'s first shown day.
DateTime monthFoldDay(
  DateTime month, {
  required DateTime selectedDay,
  required DateTime today,
  required WeekdaySet weekdays,
}) {
  bool holds(DateTime day) {
    return day.year == month.year && day.month == month.month;
  }

  if (holds(selectedDay)) {
    return selectedDay;
  }
  if (holds(today)) {
    // `shownDayNear` stays inside the month of the day it is given.
    return shownDayNear(today, weekdays);
  }
  return shownDayNear(DateTime(month.year, month.month), weekdays);
}

/// The months side by side, opening on [month], one at a time across the
/// strip, each a grid of [weekdays]' columns and a row [rowHeight] tall for
/// each of its weeks ([MonthGrid]), its days as [DayCell]s: the selected
/// day's in the primary colour, today's ringed, and a badge on a day with
/// items once the store has read it. The cells before a month's first day
/// and after its last are blank. A tap on a day reports [onSelectDay].
///
/// A horizontal drag slides the strip with the finger, the next month
/// coming in from the right and the previous from the left, and selects
/// nothing; the strip is as tall as the month it shows, and between two
/// months as tall as their heights blended by how far it has slid. A
/// release comes to rest on a whole month as [snap] says. While the strip
/// moves other than to follow [month], it reports through [onBrowse] the
/// first day of the month at its middle each time a scroll brings a new
/// one there, the last report naming the month it rests on; once it rests, it
/// asks [store] to read the days of that month's grid, so their markers
/// show. A new [month] the strip does not rest on slides it there, after
/// the frame, over the [CalendarTheme]'s motion, or at once where its
/// duration is zero, from a month short of it when it is further away.
///
/// [collapse] runs from 0, the month, to 1, its week. As it runs the strip
/// shrinks to one row and moves up by the rows above the week of
/// [monthFoldDay], while the days of the months beside it fade into that
/// week's blank cells, so at 1 the strip shows that week as [WeekStrip]
/// shows it. Once [collapse] leaves 0 the strip comes to rest on the
/// nearest whole month at once and takes no pointers.
///
/// Once a tap has given it focus, the arrow keys select the shown day
/// before or after the selected one, and the day a week before or after
/// it, through [onSelectDay].
///
/// [weekdays] are fixed for the strip's life: give a strip that changes
/// them its own key.
class MonthStrip<T> extends StatefulWidget {
  const MonthStrip({
    super.key,
    required this.store,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.weekdays,
    required this.rowHeight,
    required this.collapse,
    required this.onSelectDay,
    required this.onBrowse,
    this.snap = MonthStripSnap.nearest,
  });

  final CalendarStore<T> store;

  /// The first day of the month the strip shows.
  final DateTime month;

  /// The selected day, on a weekday [weekdays] holds.
  final DateTime selectedDay;

  /// The day the strip marks as today.
  final DateTime today;

  final WeekdaySet weekdays;

  /// The height of a week's row.
  final double rowHeight;

  /// How far the strip has folded into a week, from 0 to 1.
  final Animation<double> collapse;

  final ValueChanged<DateTime> onSelectDay;

  /// Reports the first day of the month that a scroll has brought to the
  /// middle of the strip.
  final ValueChanged<DateTime> onBrowse;

  final MonthStripSnap snap;

  /// The most weeks a month's grid takes.
  static const int maxWeeks = 6;

  @override
  State<MonthStrip<T>> createState() {
    return _MonthStripState<T>();
  }
}

class _MonthStripState<T> extends State<MonthStrip<T>> {
  /// Below this, a fraction of a month is taken for float error in the
  /// scroll offset.
  static const double _epsilon = 1e-6;

  /// The key of the sliver of the months from index 0 on, which the scroll
  /// view centres on, so the months before index 0 lie at negative
  /// offsets.
  static const Key _forwardKey = ValueKey<String>("month-strip-forward");

  /// The month at index 0: [MonthStrip.month] when the strip was first
  /// built. Each index after or before it is the next or previous month.
  late final DateTime _origin = DateTime(
    widget.month.year,
    widget.month.month,
  );

  final ScrollController _scroll = ScrollController();

  final FocusNode _focus = FocusNode(debugLabel: "MonthStrip");

  /// The width of a month as the last layout gave it; null before it.
  double? _extent;

  /// The month the strip rests on or slides to: the last
  /// [MonthStrip.month] given, or the last month reported through
  /// [MonthStrip.onBrowse] since.
  late DateTime _month = _origin;

  /// The index of the month at the strip's middle as last seen.
  int _middle = 0;

  /// Whether the strip is moving to follow [MonthStrip.month], which
  /// reports no month through [MonthStrip.onBrowse].
  bool _following = false;

  /// Counts the slides that follow [MonthStrip.month], so the end of one a
  /// later slide stopped leaves [_following] to that later one.
  int _follows = 0;

  /// The theme above the strip, whose motion a slide takes when it starts.
  late CalendarThemeData _theme;

  @override
  void initState() {
    super.initState();
    widget.collapse.addListener(_handleCollapse);
    // After the frame, because a read may notify the day cells' listeners,
    // which must not rebuild mid-build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prefetch(_origin);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = CalendarTheme.of(context);
  }

  @override
  void didUpdateWidget(MonthStrip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.weekdays == oldWidget.weekdays,
      "A MonthStrip keeps its weekdays; give a strip that changes them its "
      "own key.",
    );
    if (widget.collapse != oldWidget.collapse) {
      oldWidget.collapse.removeListener(_handleCollapse);
      widget.collapse.addListener(_handleCollapse);
    }
    if (widget.month != _month) {
      _month = widget.month;
      // After the frame, because a scroll dispatches scroll notifications,
      // which must not reach their listeners mid-build.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _slideTo(_month);
      });
    }
  }

  @override
  void dispose() {
    widget.collapse.removeListener(_handleCollapse);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime _monthAt(int index) {
    return DateTime(_origin.year, _origin.month + index);
  }

  int _indexOf(DateTime month) {
    return (month.year - _origin.year) * 12 + month.month - _origin.month;
  }

  MonthGrid _gridOf(DateTime month) {
    return MonthGrid(month.year, month.month, weekdays: widget.weekdays);
  }

  double _heightAt(int index) {
    return _gridOf(_monthAt(index)).weekCount * widget.rowHeight;
  }

  void _prefetch(DateTime month) {
    final grid = _gridOf(month);
    widget.store.prefetch(grid.firstDay, grid.lastDay);
  }

  /// Slides the strip to [month], unless it rests there. A month more than
  /// one away is jumped to a month short of first, so the slide is a
  /// month's at most, as fast whatever the distance.
  void _slideTo(DateTime month) {
    final extent = _extent;
    if (!mounted || !_scroll.hasClients || extent == null) {
      return;
    }
    final position = _scroll.position;
    final target = _indexOf(month) * extent;
    final distance = target - position.pixels;
    if (distance.abs() < _epsilon * extent) {
      return;
    }
    final follow = ++_follows;
    _following = true;
    if (distance.abs() > extent) {
      _scroll.jumpTo(target - distance.sign * extent);
    }
    final duration = _theme.motionDuration;
    if (duration <= Duration.zero || widget.collapse.value > 0.0) {
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

  /// Brings the strip to rest on the nearest whole month once the fold
  /// starts, so the fold shrinks one month to one of its weeks.
  void _handleCollapse() {
    final extent = _extent;
    if (widget.collapse.value <= 0.0 ||
        !_scroll.hasClients ||
        extent == null) {
      return;
    }
    final pixels = _scroll.position.pixels;
    final nearest = (pixels / extent).roundToDouble() * extent;
    if ((pixels - nearest).abs() > _epsilon * extent) {
      _scroll.jumpTo(nearest);
    }
  }

  /// Keeps the month the strip shows where a new width gives a month a new
  /// [extent]. Called from the layout callback, before the scroll view
  /// lays out at the offset it corrects.
  void _keepMonth(double extent) {
    final old = _extent;
    _extent = extent;
    if (old == null || old == extent || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    position.correctPixels(position.pixels / old * extent);
  }

  /// Reports a new month at the middle while the strip moves other than to
  /// follow [MonthStrip.month], and reads the month it rests on.
  bool _handleScroll(ScrollNotification notification) {
    final extent = _extent;
    if (notification.depth != 0 || extent == null || extent <= 0.0) {
      return false;
    }
    final position = notification.metrics.pixels / extent;
    if (notification is ScrollUpdateNotification) {
      final middle = (position + 0.5 + _epsilon).floor();
      if (middle != _middle) {
        _middle = middle;
        if (!_following) {
          _month = _monthAt(middle);
          widget.onBrowse(_month);
        }
      }
    } else if (notification is ScrollEndNotification) {
      _prefetch(_monthAt(position.round()));
    }
    return false;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final selected = widget.selectedDay;
    final forward = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final DateTime day;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      day = nextShownDay(selected, -forward, widget.weekdays);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      day = nextShownDay(selected, forward, widget.weekdays);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      day = addDays(selected, -DateTime.daysPerWeek);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      day = addDays(selected, DateTime.daysPerWeek);
    } else {
      return KeyEventResult.ignored;
    }
    widget.onSelectDay(day);
    return KeyEventResult.handled;
  }

  ScrollPhysics get _physics {
    switch (widget.snap) {
      case MonthStripSnap.nearest:
        return const StripSnapPhysics(cellCount: 1);
      case MonthStripSnap.next:
        return const PageScrollPhysics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rowHeight = widget.rowHeight;
    final fullHeight = MonthStrip.maxWeeks * rowHeight;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final extent = constraints.maxWidth;
          _keepMonth(extent);
          final view = NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: CustomScrollView(
              scrollDirection: Axis.horizontal,
              controller: _scroll,
              physics: _physics,
              // Only the months the strip shows are built, so a month's
              // days, and their keys, are in the tree once at rest.
              scrollCacheExtent: const ScrollCacheExtent.pixels(0.0),
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
          return AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_scroll, widget.collapse]),
            child: view,
            builder: (context, child) {
              final t = widget.collapse.value;
              var position = 0.0;
              if (_scroll.hasClients && extent > 0.0) {
                position = _scroll.position.pixels / extent;
              }
              final index = (position + _epsilon).floor();
              final fraction = (position - index).clamp(0.0, 1.0);
              final open = lerpDouble(
                _heightAt(index),
                _heightAt(index + 1),
                fraction,
              )!;
              final resting = _monthAt(position.round());
              final foldRow = t > 0.0
                  ? _gridOf(resting)
                        .cellOf(
                          monthFoldDay(
                            resting,
                            selectedDay: widget.selectedDay,
                            today: widget.today,
                            weekdays: widget.weekdays,
                          ),
                        )
                        .row
                  : 0;
              return SizedBox(
                height: lerpDouble(open, rowHeight, t),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: fullHeight,
                    maxHeight: fullHeight,
                    child: Transform.translate(
                      offset: Offset(0.0, -t * foldRow * rowHeight),
                      child: IgnorePointer(ignoring: t > 0.0, child: child),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMonth(DateTime month) {
    final grid = _gridOf(month);
    return Align(
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var row = 0; row < grid.weekCount; row++)
            SizedBox(
              height: widget.rowHeight,
              child: Row(
                children: <Widget>[
                  for (var col = 0; col < grid.columnCount; col++)
                    Expanded(child: _buildDay(grid, grid.dateAt(row, col))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDay(MonthGrid grid, DateTime day) {
    if (!grid.contains(day)) {
      return _NeighbourDay<T>(
        store: widget.store,
        day: day,
        isSelected: day == widget.selectedDay,
        isToday: day == widget.today,
        collapse: widget.collapse,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focus.requestFocus();
        widget.onSelectDay(day);
      },
      child: DayMarkerListener<T>(
        store: widget.store,
        day: day,
        builder: (context, hasItems) {
          return DayCell(
            key: dayCellKey(day),
            day: day,
            inMonth: true,
            isSelected: day == widget.selectedDay,
            isToday: day == widget.today,
            hasItems: hasItems,
            collapse: widget.collapse,
          );
        },
      ),
    );
  }
}

/// A day of the month beside a [MonthStrip]'s in one of its blank cells:
/// nothing while [collapse] is 0, and otherwise its [DayCell], unkeyed,
/// faded in by [collapse], taking no pointers.
class _NeighbourDay<T> extends StatelessWidget {
  const _NeighbourDay({
    required this.store,
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.collapse,
  });

  final CalendarStore<T> store;
  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final Animation<double> collapse;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: collapse,
        child: DayMarkerListener<T>(
          store: store,
          day: day,
          builder: (context, hasItems) {
            return DayCell(
              day: day,
              inMonth: false,
              isSelected: isSelected,
              isToday: isToday,
              hasItems: hasItems,
              collapse: collapse,
            );
          },
        ),
        builder: (context, child) {
          final t = collapse.value;
          if (t <= 0.0) {
            return const SizedBox.shrink();
          }
          return Opacity(opacity: t, child: child);
        },
      ),
    );
  }
}
