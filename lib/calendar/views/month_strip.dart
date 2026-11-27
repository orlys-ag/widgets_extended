/// The strip of months in Agenda's and Day's calendar card, one month at a
/// time, which slides month by month and folds into a week.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_theme.dart';
import 'day_cell.dart';
import 'stale_days_ask.dart';
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
/// [month]'s first shown day. With [firstDay], a shown day in [month] or
/// before it, below which the card browses no week, [firstDay] in place of
/// a day whose week starts before [firstDay]'s.
DateTime monthFoldDay(
  DateTime month, {
  required DateTime selectedDay,
  required DateTime today,
  required CalendarWeekdaySet weekdays,
  DateTime? firstDay,
}) {
  bool holds(DateTime day) {
    return day.year == month.year && day.month == month.month;
  }

  final DateTime day;
  if (holds(selectedDay)) {
    day = selectedDay;
  } else if (holds(today)) {
    // `shownDayNear` stays inside the month of the day it is given.
    day = CalendarDates.shownDayNear(today, weekdays);
  } else {
    day = CalendarDates.shownDayNear(
      DateTime(month.year, month.month),
      weekdays,
    );
  }
  if (firstDay != null &&
      weekdays.weekStartOfDay(CalendarDates.dayNumber(day)) <
          weekdays.weekStartOfDay(CalendarDates.dayNumber(firstDay))) {
    return firstDay;
  }
  return day;
}

/// The months side by side, opening on [month], one at a time across the
/// strip, each a grid of [weekdays]' columns and a row [rowHeight] tall for
/// each of its weeks ([CalendarMonthGrid]), its days as [DayCell]s: the
/// selected day's in the primary colour, today's ringed, and badges on a day
/// with items once the store has read it, one for each kind [dayBadges] gives
/// its entries. The cells before a month's first day
/// and after its last are blank. A tap on a day reports [onSelectDay]. A
/// day [isDayEnabled] refuses draws disabled and takes no tap, and with no
/// [onSelectDay] no day takes one.
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
/// show, as it asks a new [store] after the frame that gives it, for the
/// month it rests on or slides to. After the frame that the store reports
/// stale days of that month's grid
/// ([CalendarEntryReader.addStaleDaysListener]), it reads again each run of
/// them the store answers [CalendarEntryReader.isStale] for. A new [month]
/// the strip does not rest on slides it there, after the frame, over the
/// [CalendarTheme]'s motion, or at once where its duration is zero, from a
/// month short of it when it is further away.
///
/// [collapse] runs from 0, the month, to 1, its week. As it runs the strip
/// shrinks to one row and moves up by the rows above the week of
/// [foldDay] where the month it rests on holds it, and otherwise of
/// [monthFoldDay], while the days of the months beside it fade into that
/// week's blank cells, so at 1 the strip shows that week as [WeekStrip]
/// shows it. Once [collapse] leaves 0 the strip comes to rest on the
/// nearest whole month at once and takes no pointers.
///
/// The strip answers the height it lays out at, at any width, as its
/// intrinsic height, and lays out again whatever asked it as that height
/// moves.
///
/// With [browseFrom], the strip slides back no further than that day's
/// month, and folds into that day's week where the week it would fold into
/// starts before it.
///
/// Once a tap has given it focus, the arrow keys select the shown day
/// before or after the selected one, and the day a week before or after
/// it, through [onSelectDay]; an arrow onto a day [isDayEnabled] refuses
/// selects nothing, and with no [onSelectDay] the strip takes no key.
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
    this.dayBadges,
    this.isDayEnabled,
    this.foldDay,
    this.browseFrom,
  });

  final CalendarStore<T> store;

  /// The first day of the month the strip shows.
  final DateTime month;

  /// The selected day, on a weekday [weekdays] holds.
  final DateTime selectedDay;

  /// The day the strip marks as today.
  final DateTime today;

  final CalendarWeekdaySet weekdays;

  /// The height of a week's row.
  final double rowHeight;

  /// How far the strip has folded into a week, from 0 to 1.
  final Animation<double> collapse;

  /// Reports a day tapped or reached by an arrow key; null for a strip
  /// whose days take no tap and which takes no key.
  final ValueChanged<DateTime>? onSelectDay;

  /// Reports the first day of the month that a scroll has brought to the
  /// middle of the strip.
  final ValueChanged<DateTime> onBrowse;

  final MonthStripSnap snap;

  /// The kinds of entry the days' badges mark; null for one primary dot
  /// on a day with entries.
  final CalendarDayBadges<T>? dayBadges;

  /// Whether a day may be picked, asked of each day's cell, a plain day
  /// (the local midnight of its date), as the cell builds; null takes
  /// every day.
  final bool Function(DateTime day)? isDayEnabled;

  /// The day, on a shown weekday, whose week the month folds into while the
  /// month the strip rests on holds it; null, or a day of another month,
  /// for [monthFoldDay]'s.
  final DateTime? foldDay;

  /// A shown day the strip slides back no further than the month of, and
  /// whose week the month folds into in place of an earlier one
  /// ([monthFoldDay]'s `firstDay`); null for no limit. Fixed for the
  /// strip's life by its month: give a strip a limit in another month its
  /// own key.
  final DateTime? browseFrom;

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
  /// built, or [MonthStrip.browseFrom]'s month where that is later. Each
  /// index after or before it is the next or previous month.
  late final DateTime _origin = _openingMonth();

  DateTime _openingMonth() {
    final month = DateTime(widget.month.year, widget.month.month);
    final from = _browseFrom;
    if (from != null && from.isAfter(month)) {
      return DateTime(from.year, from.month);
    }
    return month;
  }

  /// [MonthStrip.browseFrom] as a plain day; null for no limit.
  late final DateTime? _browseFrom = _foldTwinOf(widget.browseFrom);

  /// The index of [MonthStrip.browseFrom]'s month, 0 or before it, which
  /// the strip slides back no further than; null for no limit.
  late final int? _limit = _browseFrom == null
      ? null
      : _indexOf(DateTime(_browseFrom.year, _browseFrom.month));

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

  /// Whether a frame will read the month the strip rests on.
  bool _prefetchScheduled = false;

  /// Reads again, after the frame, the days of [_month]'s grid the store
  /// reports stale ([StaleDaysAsk]).
  late final StaleDaysAsk<T> _staleAsk;

  /// The theme above the strip, whose motion a slide takes when it starts.
  late CalendarThemeData _theme;

  /// [MonthStrip.selectedDay] and [MonthStrip.today] as plain days, the
  /// local midnights of their dates, which the cells, the plain days of
  /// [CalendarMonthGrid]s, compare with by `==` however the days given are
  /// zoned. Made only where the day they twin changes.
  late DateTime _selectedDay;
  late DateTime _today;

  /// [MonthStrip.foldDay] as a plain day, made only where it changes.
  DateTime? _foldDay;

  /// The local midnight of [day]'s date.
  static DateTime _plainTwinOf(DateTime day) {
    return CalendarDates.dateOfDayNumber(CalendarDates.dayNumber(day));
  }

  static DateTime? _foldTwinOf(DateTime? day) {
    return day == null ? null : _plainTwinOf(day);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _plainTwinOf(widget.selectedDay);
    _today = _plainTwinOf(widget.today);
    _foldDay = _foldTwinOf(widget.foldDay);
    widget.collapse.addListener(_handleCollapse);
    _staleAsk = StaleDaysAsk<T>(_monthDays)..listen(widget.store);
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
    assert(
      _sameMonth(widget.browseFrom, oldWidget.browseFrom),
      "A MonthStrip keeps the month of its browseFrom; give a strip a limit "
      "in another month its own key.",
    );
    if (widget.selectedDay != oldWidget.selectedDay) {
      _selectedDay = _plainTwinOf(widget.selectedDay);
    }
    if (widget.today != oldWidget.today) {
      _today = _plainTwinOf(widget.today);
    }
    if (widget.foldDay != oldWidget.foldDay) {
      _foldDay = _foldTwinOf(widget.foldDay);
    }
    if (widget.collapse != oldWidget.collapse) {
      oldWidget.collapse.removeListener(_handleCollapse);
      widget.collapse.addListener(_handleCollapse);
    }
    _staleAsk.listen(widget.store);
    if (widget.store != oldWidget.store) {
      // After the frame, as in initState. The month the strip rests on or
      // slides to, which a slide's end reads again where it moves on.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _prefetch(_month);
        }
      });
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
    _staleAsk.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  static bool _sameMonth(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return a == b;
    }
    return a.year == b.year && a.month == b.month;
  }

  DateTime _monthAt(int index) {
    return DateTime(_origin.year, _origin.month + index);
  }

  int _indexOf(DateTime month) {
    return (month.year - _origin.year) * 12 + month.month - _origin.month;
  }

  CalendarMonthGrid _gridOf(DateTime month) {
    return CalendarMonthGrid(
      month.year,
      month.month,
      weekdays: widget.weekdays,
    );
  }

  double _heightAt(int index) {
    return _gridOf(_monthAt(index)).weekCount * widget.rowHeight;
  }

  void _prefetch(DateTime month) {
    final grid = _gridOf(month);
    widget.store.prefetch(grid.firstDay, grid.lastDay);
  }

  /// The day numbers of the grid of [_month], the month the strip rests on
  /// or slides to.
  ({int first, int last}) _monthDays() {
    final grid = _gridOf(_month);
    return (
      first: CalendarDates.dayNumber(grid.firstDay),
      last: CalendarDates.dayNumber(grid.lastDay),
    );
  }

  /// Slides the strip to [month], or to [MonthStrip.browseFrom]'s month
  /// where [month] lies before it, unless it rests there. A month more than
  /// one away is jumped to a month short of first, so the slide is a
  /// month's at most, as fast whatever the distance.
  void _slideTo(DateTime month) {
    final extent = _extent;
    if (!mounted || !_scroll.hasClients || extent == null) {
      return;
    }
    final position = _scroll.position;
    var index = _indexOf(month);
    final limit = _limit;
    if (limit != null && index < limit) {
      index = limit;
    }
    final target = index * extent;
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
    if (widget.collapse.value <= 0.0 || !_scroll.hasClients || extent == null) {
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
  /// follow [MonthStrip.month], and reads the month it rests on, after the
  /// frame ([_schedulePrefetch]).
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
      _schedulePrefetch();
    }
    return false;
  }

  /// After the frame, reads the month the strip rests on, once however
  /// many scrolls end in it, and asks for that frame where none is under
  /// way: a scroll can end during layout, as
  /// [BallisticScrollActivity.applyNewDimensions] ends one where the
  /// physics gives it no new simulation, when the store must not notify.
  void _schedulePrefetch() {
    if (_prefetchScheduled) {
      return;
    }
    _prefetchScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _prefetchScheduled = false;
      final extent = _extent;
      if (mounted && _scroll.hasClients && extent != null && extent > 0.0) {
        _prefetch(_monthAt((_scroll.position.pixels / extent).round()));
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final onSelectDay = widget.onSelectDay;
    if (onSelectDay == null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final selected = _selectedDay;
    final forward = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final DateTime day;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      day = CalendarDates.nextShownDay(selected, -forward, widget.weekdays);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      day = CalendarDates.nextShownDay(selected, forward, widget.weekdays);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      day = CalendarDates.addDays(selected, -DateTime.daysPerWeek);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      day = CalendarDates.addDays(selected, DateTime.daysPerWeek);
    } else {
      return KeyEventResult.ignored;
    }
    if (widget.isDayEnabled?.call(day) ?? true) {
      onSelectDay(day);
    }
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

  /// How many months the strip has scrolled from index 0, fractional while
  /// it slides: its pixels over the width of a month as the last layout
  /// gave it, a ratio a new width keeps ([_keepMonth]), so it holds at any
  /// width; 0 before the first layout.
  double get _position {
    final extent = _extent;
    if (!_scroll.hasClients || extent == null || extent <= 0.0) {
      return 0.0;
    }
    return _scroll.position.pixels / extent;
  }

  @override
  Widget build(BuildContext context) {
    final rowHeight = widget.rowHeight;
    final fullHeight = MonthStrip.maxWeeks * rowHeight;
    final months = LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.maxWidth;
        _keepMonth(extent);
        return NotificationListener<ScrollNotification>(
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
                }, childCount: _limit == null ? null : -_limit),
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
    );
    return Focus(
      focusNode: _focus,
      onKeyEvent: _handleKey,
      // The strip's height, which holds at any width ([_position]), is set
      // above the LayoutBuilder, which answers no intrinsic size: a SizedBox
      // of a given height answers it as its intrinsic height without asking
      // its child ([RenderConstrainedBox]), and a new one lays out again
      // whatever asked it.
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_scroll, widget.collapse]),
        child: months,
        builder: (context, child) {
          final t = widget.collapse.value;
          final position = _position;
          final index = (position + _epsilon).floor();
          final fraction = (position - index).clamp(0.0, 1.0);
          final open = lerpDouble(
            _heightAt(index),
            _heightAt(index + 1),
            fraction,
          )!;
          final resting = _monthAt(position.round());
          final foldDay = _foldDay;
          final foldRow = t > 0.0
              ? _gridOf(resting)
                    .cellOf(
                      foldDay != null &&
                              foldDay.year == resting.year &&
                              foldDay.month == resting.month
                          ? foldDay
                          : monthFoldDay(
                              resting,
                              selectedDay: _selectedDay,
                              today: _today,
                              weekdays: widget.weekdays,
                              firstDay: _browseFrom,
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

  Widget _buildDay(CalendarMonthGrid grid, DateTime day) {
    final enabled = widget.isDayEnabled?.call(day);
    if (!grid.contains(day)) {
      return _NeighbourDay<T>(
        store: widget.store,
        day: day,
        isSelected: day == _selectedDay,
        isToday: day == _today,
        enabled: enabled,
        collapse: widget.collapse,
        dayBadges: widget.dayBadges,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSelectDay == null || enabled == false
          ? null
          : () {
              _focus.requestFocus();
              widget.onSelectDay?.call(day);
            },
      child: DayMarkerListener<T>(
        store: widget.store,
        day: day,
        badges: widget.dayBadges,
        builder: (context, badges) {
          return DayCell(
            key: dayCellKey(day),
            day: day,
            inMonth: true,
            isSelected: day == _selectedDay,
            isToday: day == _today,
            badges: badges,
            collapse: widget.collapse,
            enabled: enabled,
          );
        },
      ),
    );
  }
}

/// A day of the month beside a [MonthStrip]'s in one of its blank cells:
/// nothing while [collapse] is 0, and otherwise its [DayCell], unkeyed,
/// faded in by [collapse], taking no pointers, drawn disabled where
/// [enabled] is false, as the week strip draws it.
class _NeighbourDay<T> extends StatelessWidget {
  const _NeighbourDay({
    required this.store,
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.enabled,
    required this.collapse,
    required this.dayBadges,
  });

  final CalendarStore<T> store;
  final DateTime day;
  final bool isSelected;
  final bool isToday;

  /// [DayCell.enabled].
  final bool? enabled;

  final Animation<double> collapse;
  final CalendarDayBadges<T>? dayBadges;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: collapse,
        child: DayMarkerListener<T>(
          store: store,
          day: day,
          badges: dayBadges,
          builder: (context, badges) {
            return DayCell(
              day: day,
              inMonth: false,
              isSelected: isSelected,
              isToday: isToday,
              badges: badges,
              collapse: collapse,
              enabled: enabled,
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
