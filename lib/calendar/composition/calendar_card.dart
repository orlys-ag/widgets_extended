/// The cards a calendar's header sits on: Agenda's and Day's calendar
/// card, whose month folds into the week strip under a pull tab, and Week's
/// and Month's header card, each with the area the month picker comes into.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import '../views/day_cell.dart';
import '../views/month_strip.dart';
import '../views/week_strip.dart';
import 'calendar_card_controller.dart';

/// The key of the calendar card's pull tab.
const ValueKey<String> calendarPullTabKey = ValueKey<String>(
  "calendar-pull-tab",
);

/// The key of the area under the calendar header that the month picker
/// comes into: in Agenda's and Day's card in place of the days, and under
/// the header in Week's and Month's.
const ValueKey<String> calendarDaysAreaKey = ValueKey<String>(
  "calendar-days-area",
);

/// [header] on a card of its own, above the grids of Week and Month, with
/// the month picker, which [buildPicker] builds, coming in under it as
/// [controller]'s [CalendarCardController.pickerShown] runs from 0 to 1,
/// taking pointers while its [CalendarCardController.picksMonth] holds.
class CalendarHeaderCard extends StatelessWidget {
  const CalendarHeaderCard({
    super.key,
    required this.header,
    required this.controller,
    required this.buildPicker,
  });

  final Widget header;

  /// The card state the month picker's motion and pointers follow.
  final CalendarCardController controller;

  final Widget Function() buildPicker;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CalendarTheme.of(context).surface,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              AnimatedBuilder(
                animation: controller.pickerShown,
                builder: (context, child) {
                  return _PickerArea(
                    shown: controller.pickerShown.value,
                    picksMonth: controller.picksMonth,
                    days: const SizedBox.shrink(),
                    pickerPadding: const EdgeInsets.only(top: 4.0),
                    buildPicker: buildPicker,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Agenda's and Day's calendar card: [header] over [month]'s days as a
/// [MonthStrip] under the weekdays' abbreviations, which fold into
/// the week of [monthFoldDay] as [controller]'s
/// [CalendarCardController.collapse] runs from 0 to 1, and at 1 give way
/// to a [WeekStrip] opening on that week, over a pull tab; the month
/// picker, which [buildPicker] builds, comes in over the days as its
/// [CalendarCardController.pickerShown] runs from 0 to 1.
///
/// A drag on the pull tab moves the fold with the finger, the card losing
/// a row for each week the month folds and the weekday names' height; a
/// release settles the controller ([CalendarCardController.settle]) on
/// the fold the way a fast one moves and otherwise the nearer one, and so
/// does a tap, which switches. A drag down the folded strip of 16 logical
/// pixels unfolds it ([CalendarCardController.unfold]). The strips report
/// a day selected through [onSelectDay], and a month or a day browsed to
/// through the controller's [CalendarCardController.browseMonth] and
/// [CalendarCardController.browseStrip]; the week strip slides to the
/// controller's [CalendarCardController.recallDay] at a recall, and the
/// month folds into the week of its [CalendarCardController.foldDay]. A
/// day [isDayEnabled] refuses draws disabled in both strips and takes no
/// tap, and with no [onSelectDay] no day takes one. With [browseFrom] the
/// week strip browses no week before that day's, the month strip no month
/// before its month, and the month folds into no week before its week.
/// The card reads the
/// controller as it builds and listens to its motions alone, so its host
/// builds it again at each of the controller's events.
///
/// Its rows are as tall as a week strip's cell under the [CalendarTheme]
/// above it ([stripCellHeight]). The card pads its sides by 8 logical
/// pixels, and each day's circle is centred in its column; where
/// [daysToEdges], the card pads no side, and its weekday names and days lie
/// in columns spread so that the circles of the first and last columns
/// reach its sides (`_EdgeDays`).
class CalendarCard<T> extends StatefulWidget {
  const CalendarCard({
    super.key,
    required this.controller,
    required this.store,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.weekdays,
    required this.header,
    required this.buildPicker,
    required this.onSelectDay,
    this.dayBadges,
    this.isDayEnabled,
    this.daysToEdges = false,
    this.browseFrom,
  });

  /// The card's fold, browse and month picker, and their motions.
  final CalendarCardController controller;

  final CalendarStore<T> store;

  /// The first day of the month the card shows.
  final DateTime month;

  final DateTime selectedDay;
  final DateTime today;
  final CalendarWeekdaySet weekdays;

  /// The header row over the days; null for no header row and no gap
  /// under it.
  final Widget? header;

  final Widget Function() buildPicker;

  /// Reports a day tapped, or in the month reached by an arrow key; null
  /// for a card whose days take no tap.
  final ValueChanged<DateTime>? onSelectDay;

  /// The kinds of entry the days' badges mark, in the month and in the
  /// week strip; null for one primary dot on a day with entries.
  final CalendarDayBadges<T>? dayBadges;

  /// Whether a day may be picked, which both strips ask of each day's
  /// cell, a plain day, as it builds ([WeekStrip.isDayEnabled],
  /// [MonthStrip.isDayEnabled]); null takes every day.
  final bool Function(DateTime day)? isDayEnabled;

  /// Whether the circles of the first and last columns reach the card's
  /// sides, the card padding no side.
  final bool daysToEdges;

  /// A day, on a weekday [weekdays] holds, before whose week and month the
  /// strips browse nothing ([WeekStrip.browseFrom],
  /// [MonthStrip.browseFrom]); null for no limit.
  final DateTime? browseFrom;

  @override
  State<CalendarCard<T>> createState() {
    return _CalendarCardState<T>();
  }
}

class _CalendarCardState<T> extends State<CalendarCard<T>> {
  /// The speed, in logical pixels per second, past which a release of the
  /// pull tab folds or unfolds the way it moves, wherever it is.
  static const double _foldFlingVelocity = 365.0;

  /// The distance down, in logical pixels, a drag on the folded strip goes
  /// before it unfolds the month.
  static const double _unfoldDistance = 16.0;

  /// The height of a row of the month, in logical pixels: a strip cell's
  /// ([stripCellHeight]) under the theme the strips draw with, so a week
  /// folds into the strip with the weekday names its cells grow fitting.
  double _rowHeight = 48.0;

  /// How far down, in logical pixels, the drag on the folded strip has
  /// gone.
  double _unfoldDrag = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rowHeight = stripCellHeight(context);
  }

  /// The height the card loses as the month it shows folds into a week:
  /// every other week, and the weekday header.
  double get _foldDistance {
    final month = widget.month;
    final grid = CalendarMonthGrid(
      month.year,
      month.month,
      weekdays: widget.weekdays,
    );
    return (grid.weekCount - 1) * _rowHeight + weekdayHeaderHeight;
  }

  void _dragFold(DragUpdateDetails details) {
    widget.controller.collapse.value -= details.primaryDelta! / _foldDistance;
  }

  void _endFoldDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    widget.controller.settle(
      velocity.abs() >= _foldFlingVelocity
          ? velocity < 0.0
          : widget.controller.collapse.value >= 0.5,
    );
  }

  /// The strip of days the folded month becomes, opening on the week the
  /// month folded into, or with the controller's
  /// [CalendarCardController.stripMiddleDay] at its middle. Its weekdays
  /// and the week of its limit are fixed for its life, so new ones build a
  /// new strip.
  Widget _buildStrip() {
    final controller = widget.controller;
    final from = widget.browseFrom;
    return WeekStrip<T>(
      key: ValueKey<(CalendarWeekdaySet, int?)>((
        widget.weekdays,
        from == null
            ? null
            : widget.weekdays.weekStartOfDay(CalendarDates.dayNumber(from)),
      )),
      store: widget.store,
      selectedDay: widget.selectedDay,
      today: widget.today,
      weekdays: widget.weekdays,
      recalls: controller.stripRecalls,
      recallDay: controller.recallDay,
      initialDay: monthFoldDay(
        widget.month,
        selectedDay: widget.selectedDay,
        today: widget.today,
        weekdays: widget.weekdays,
        firstDay: from,
      ),
      initialMiddleDay: controller.stripMiddleDay,
      onSelectDay: widget.onSelectDay,
      onBrowse: controller.browseStrip,
      dayBadges: widget.dayBadges,
      isDayEnabled: widget.isDayEnabled,
      browseFrom: from,
    );
  }

  /// The weekday header and the month strip, [months], at collapse [t],
  /// the strip folding itself into a week. Once folded, at a [t] of 1, the
  /// week strip takes its place, as tall as a row, opening on the week it
  /// showed.
  Widget _buildGrid(double t, Widget months) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1.0 - t,
            child: Opacity(
              opacity: 1.0 - t,
              child: WeekdayHeader(
                weekdays: widget.weekdays,
                abbreviated: true,
              ),
            ),
          ),
        ),
        SizedBox(
          key: const ValueKey<String>("calendar-grid"),
          height: t == 1.0 ? _rowHeight : null,
          child: t == 1.0
              ? GestureDetector(
                  onVerticalDragStart: (details) {
                    _unfoldDrag = 0.0;
                  },
                  onVerticalDragUpdate: (details) {
                    _unfoldDrag += details.delta.dy;
                    if (_unfoldDrag >= _unfoldDistance) {
                      widget.controller.unfold();
                    }
                  },
                  child: _buildStrip(),
                )
              : months,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // Built once per build of this card and handed to the collapse builder
    // as its child, so the fold does not rebuild the strip, which follows
    // the fold itself. Its weekdays and the month of its limit are fixed
    // for its life, so new ones build a new strip.
    final from = widget.browseFrom;
    final months = MonthStrip<T>(
      key: ValueKey<(CalendarWeekdaySet, int?)>((
        widget.weekdays,
        from == null ? null : from.year * DateTime.monthsPerYear + from.month,
      )),
      store: widget.store,
      month: widget.month,
      selectedDay: widget.selectedDay,
      today: widget.today,
      weekdays: widget.weekdays,
      rowHeight: _rowHeight,
      collapse: controller.collapse,
      onSelectDay: widget.onSelectDay,
      onBrowse: controller.browseMonth,
      dayBadges: widget.dayBadges,
      isDayEnabled: widget.isDayEnabled,
      foldDay: controller.foldDay,
      browseFrom: from,
    );
    final header = widget.header;
    Widget grid = AnimatedBuilder(
      animation: controller.collapse,
      child: months,
      builder: (context, child) {
        return _buildGrid(controller.collapse.value, child!);
      },
    );
    if (widget.daysToEdges) {
      grid = _EdgeDays(columns: widget.weekdays.columns.length, child: grid);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CalendarTheme.of(context).surface,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: widget.daysToEdges
            ? const EdgeInsets.only(top: 8.0)
            : const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (header != null) ...<Widget>[
              header,
              const SizedBox(height: 4.0),
            ],
            AnimatedBuilder(
              animation: controller.pickerShown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  grid,
                  _PullTab(
                    folded: controller.folded,
                    onDragStart: (details) {
                      controller.collapse.stop();
                    },
                    onDragUpdate: _dragFold,
                    onDragEnd: _endFoldDrag,
                    onTap: () {
                      controller.settle(!controller.folded);
                    },
                  ),
                ],
              ),
              builder: (context, days) {
                // The picker does not fold, so it has no pull tab; under it
                // the card pads its bottom as the header card does.
                return _PickerArea(
                  shown: controller.pickerShown.value,
                  picksMonth: controller.picksMonth,
                  days: days!,
                  pickerPadding: const EdgeInsets.only(bottom: 8.0),
                  buildPicker: widget.buildPicker,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// [child], the weekday names over the days, in [columns] columns spread so
/// that the circles of the first and last reach the box's sides: each
/// column is `(width - dayCircleSize) / (columns - 1)` wide, never less
/// than an equal share of the box, and the child, that many columns wide,
/// is centred on the box, overhanging each side by half a column less half
/// a circle. Past the box's sides it is clipped [dayBadgeReach] out, where
/// an edge column's badges draw, so a slide shows no more of the columns
/// beyond than that. Its [LayoutBuilder] runs its builder only as the
/// box's constraints change, which a fold, changing the child's height
/// alone, leaves as they are.
class _EdgeDays extends StatelessWidget {
  const _EdgeDays({required this.columns, required this.child});

  final int columns;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || columns < 2) {
          return child;
        }
        final spread = math.max(
          width,
          (width - dayCircleSize) / (columns - 1) * columns,
        );
        return ClipRect(
          clipper: const _SideReach(),
          child: OverflowBox(
            minWidth: spread,
            maxWidth: spread,
            fit: OverflowBoxFit.deferToChild,
            child: child,
          ),
        );
      },
    );
  }
}

/// The box [dayBadgeReach] wider on each side, and as tall again above it
/// and below it: a clip of the sides.
class _SideReach extends CustomClipper<Rect> {
  const _SideReach();

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      -dayBadgeReach,
      -size.height,
      size.width + dayBadgeReach,
      size.height * 2.0,
    );
  }

  /// The clip itself, a rectangle, in place of the default box, so the
  /// semantics layer and [RenderObject.describeApproximatePaintClip] see
  /// the badges past the sides.
  @override
  Rect getApproximateClipRect(Size size) {
    return getClip(size);
  }

  @override
  bool shouldReclip(_SideReach oldClipper) {
    return false;
  }
}

/// [days] and the month picker, which [buildPicker] builds, padded by
/// [pickerPadding], in one place, the picker [shown] of the way in: each
/// fades by how far the other is in, only the one coming in or in takes
/// pointers, and the area is as tall as [days], [shown] of the way to the
/// padded picker's height. [days] are built until the picker is all the
/// way in, and the picker from when it starts in.
class _PickerArea extends StatelessWidget {
  const _PickerArea({
    required this.shown,
    required this.picksMonth,
    required this.days,
    required this.pickerPadding,
    required this.buildPicker,
  });

  final double shown;
  final bool picksMonth;
  final Widget days;
  final EdgeInsetsGeometry pickerPadding;
  final Widget Function() buildPicker;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      clipBehavior: shown > 0.0 && shown < 1.0 ? Clip.hardEdge : Clip.none,
      child: _HeightLerp(
        key: calendarDaysAreaKey,
        t: shown,
        first: shown < 1.0
            ? IgnorePointer(
                ignoring: picksMonth,
                child: Opacity(opacity: 1.0 - shown, child: days),
              )
            : const SizedBox.shrink(),
        second: shown > 0.0
            ? IgnorePointer(
                ignoring: !picksMonth,
                child: Opacity(
                  opacity: shown,
                  child: Padding(padding: pickerPadding, child: buildPicker()),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// [first] and [second] across its width at their own heights, both from
/// its top, [second] painted over [first], in an area as tall as [first],
/// [t] of the way to [second]'s height.
class _HeightLerp extends MultiChildRenderObjectWidget {
  _HeightLerp({
    super.key,
    required this.t,
    required Widget first,
    required Widget second,
  }) : super(children: <Widget>[first, second]);

  final double t;

  @override
  _RenderHeightLerp createRenderObject(BuildContext context) {
    return _RenderHeightLerp(t);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightLerp renderObject,
  ) {
    renderObject.t = t;
  }
}

class _HeightLerpParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeightLerp extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeightLerpParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeightLerpParentData> {
  _RenderHeightLerp(this._t);

  double _t;

  set t(double value) {
    if (value == _t) {
      return;
    }
    _t = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeightLerpParentData) {
      child.parentData = _HeightLerpParentData();
    }
  }

  Size _sizeFor(BoxConstraints constraints, double first, double second) {
    return constraints.constrain(
      Size(constraints.maxWidth, lerpDouble(first, second, _t)!),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    return _sizeFor(
      constraints,
      firstChild!.getDryLayout(childConstraints).height,
      lastChild!.getDryLayout(childConstraints).height,
    );
  }

  @override
  void performLayout() {
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      child = childAfter(child);
    }
    size = _sizeFor(
      constraints,
      firstChild!.size.height,
      lastChild!.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

/// A short bar under the calendar card's days that a vertical drag moves
/// with the finger, folding the month into its week or unfolding it, and
/// a tap switches.
class _PullTab extends StatelessWidget {
  const _PullTab({
    required this.folded,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
  });

  /// Whether the card shows the week, which names what a tap shows.
  final bool folded;

  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = CalendarLocalizations.of(context);
    return Semantics(
      button: true,
      label: folded ? strings.showMonthLabel : strings.showWeekLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: calendarPullTabKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onVerticalDragStart: onDragStart,
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: SizedBox(
          height: 20.0,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CalendarTheme.of(context).outline,
                borderRadius: BorderRadius.circular(2.0),
              ),
              child: const SizedBox(width: 36.0, height: 4.0),
            ),
          ),
        ),
      ),
    );
  }
}
