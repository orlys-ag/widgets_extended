/// The cards a calendar's header sits on: Agenda's and Day's calendar
/// card, whose month folds into the week strip under a pull tab, and Week's
/// and Month's header card, each with the area the month picker comes into.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../dates/calendar_dates.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';
import '../views/day_cell.dart';
import '../views/month_strip.dart';
import '../views/week_strip.dart';

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
/// [pickerShown] runs from 0 to 1, taking pointers while [picksMonth]
/// holds.
class CalendarHeaderCard extends StatelessWidget {
  const CalendarHeaderCard({
    super.key,
    required this.header,
    required this.pickerShown,
    required this.picksMonth,
    required this.buildPicker,
  });

  final Widget header;
  final Animation<double> pickerShown;
  final bool picksMonth;
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
                animation: pickerShown,
                builder: (context, child) {
                  return _PickerArea(
                    shown: pickerShown.value,
                    picksMonth: picksMonth,
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
/// [MonthStrip] under the weekdays' three-letter names, which fold into
/// the week of [monthFoldDay] as [collapse] runs from 0 to 1, and at 1
/// give way to a [WeekStrip] opening on that week, over a pull tab; the
/// month picker, which [buildPicker] builds, comes in over the days as
/// [pickerShown] runs from 0 to 1.
///
/// A drag on the pull tab moves [collapse] with the finger, the card
/// losing a row for each week the month folds and the weekday names'
/// height; a release reports through [onSettle] the fold to settle on,
/// the way a fast one moves and otherwise the nearer one, and so does a
/// tap, which switches. A drag down the folded strip of 16 logical pixels
/// reports [onUnfold]. The strips report a day selected through
/// [onSelectDay], and a month or a day browsed to through [onBrowseMonth]
/// and [onBrowseStrip].
///
/// Its rows are as tall as a week strip's cell under the [CalendarTheme]
/// above it ([stripCellHeight]).
class CalendarCard<T> extends StatefulWidget {
  const CalendarCard({
    super.key,
    required this.store,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.weekdays,
    required this.stripRecalls,
    required this.collapse,
    required this.collapsed,
    required this.pickerShown,
    required this.picksMonth,
    required this.header,
    required this.buildPicker,
    required this.onSelectDay,
    required this.onBrowseMonth,
    required this.onBrowseStrip,
    required this.onSettle,
    required this.onUnfold,
  });

  final CalendarStore<T> store;

  /// The first day of the month the card shows.
  final DateTime month;

  final DateTime selectedDay;
  final DateTime today;
  final WeekdaySet weekdays;

  /// [WeekStrip.recalls].
  final int stripRecalls;

  /// How far the month has folded into its week, 0 for the month and 1
  /// for the week.
  final AnimationController collapse;

  /// Whether the card settles folded, which names what a tap on the pull
  /// tab shows.
  final bool collapsed;

  /// How far the month picker has come in, 0 for out and 1 for in.
  final Animation<double> pickerShown;

  /// Whether the month picker shows, and so takes pointers.
  final bool picksMonth;

  /// The header row over the days; null for no header row and no gap
  /// under it.
  final Widget? header;

  final Widget Function() buildPicker;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onBrowseMonth;
  final ValueChanged<DateTime> onBrowseStrip;

  /// The fold to settle on, true for the week, after a release or a tap
  /// of the pull tab.
  final ValueChanged<bool> onSettle;

  /// A drag down the folded strip asks to unfold the month.
  final VoidCallback onUnfold;

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
    final grid = MonthGrid(month.year, month.month, weekdays: widget.weekdays);
    return (grid.weekCount - 1) * _rowHeight + weekdayHeaderHeight;
  }

  void _dragFold(DragUpdateDetails details) {
    widget.collapse.value -= details.primaryDelta! / _foldDistance;
  }

  void _endFoldDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    widget.onSettle(
      velocity.abs() >= _foldFlingVelocity
          ? velocity < 0.0
          : widget.collapse.value >= 0.5,
    );
  }

  /// The strip of days the folded month becomes, opening on the week the
  /// month folded into. Its weekdays are fixed for its life, so new ones
  /// build a new strip.
  Widget _buildStrip() {
    return WeekStrip<T>(
      key: ValueKey<WeekdaySet>(widget.weekdays),
      store: widget.store,
      selectedDay: widget.selectedDay,
      today: widget.today,
      weekdays: widget.weekdays,
      recalls: widget.stripRecalls,
      initialDay: monthFoldDay(
        widget.month,
        selectedDay: widget.selectedDay,
        today: widget.today,
        weekdays: widget.weekdays,
      ),
      onSelectDay: widget.onSelectDay,
      onBrowse: widget.onBrowseStrip,
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
                      widget.onUnfold();
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
    // Built once per build of this card and handed to the collapse builder
    // as its child, so the fold does not rebuild the strip, which follows
    // the fold itself. Its weekdays are fixed for its life, so new ones
    // build a new strip.
    final months = MonthStrip<T>(
      key: ValueKey<WeekdaySet>(widget.weekdays),
      store: widget.store,
      month: widget.month,
      selectedDay: widget.selectedDay,
      today: widget.today,
      weekdays: widget.weekdays,
      rowHeight: _rowHeight,
      collapse: widget.collapse,
      onSelectDay: widget.onSelectDay,
      onBrowse: widget.onBrowseMonth,
    );
    final header = widget.header;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CalendarTheme.of(context).surface,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (header != null) ...<Widget>[
              header,
              const SizedBox(height: 4.0),
            ],
            AnimatedBuilder(
              animation: widget.pickerShown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: widget.collapse,
                    child: months,
                    builder: (context, child) {
                      return _buildGrid(widget.collapse.value, child!);
                    },
                  ),
                  _PullTab(
                    folded: widget.collapsed,
                    onDragStart: (details) {
                      widget.collapse.stop();
                    },
                    onDragUpdate: _dragFold,
                    onDragEnd: _endFoldDrag,
                    onTap: () {
                      widget.onSettle(!widget.collapsed);
                    },
                  ),
                ],
              ),
              builder: (context, days) {
                // The picker does not fold, so it has no pull tab; under it
                // the card pads its bottom as the header card does.
                return _PickerArea(
                  shown: widget.pickerShown.value,
                  picksMonth: widget.picksMonth,
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
    return Semantics(
      button: true,
      label: folded ? "Show the month" : "Show the week",
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
