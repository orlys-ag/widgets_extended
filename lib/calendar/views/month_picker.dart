/// The month picker the calendar header's title opens: a year's months in
/// rows, which slides from year to year.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/widgets.dart';

import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import 'day_cell.dart';

/// The key of the month picker's cell showing [month].
ValueKey<String> monthPickerMonthKey(DateTime month) {
  return ValueKey<String>("picker-month-${month.year}-${month.month}");
}

/// How many months a row of the [MonthPicker] holds.
const int monthPickerColumns = 3;

/// What a [MonthPicker] and its [MonthCell]s draw and run with, made from
/// one [CalendarThemeData] by [forTheme] and never changed.
@immutable
class _PickerStyles {
  _PickerStyles._(this.theme)
    : name = theme.monthNameStyle.copyWith(color: theme.text),
      selectedName = theme.monthNameMarkedStyle.copyWith(
        color: theme.onPrimary,
      ),
      currentName = theme.monthNameMarkedStyle.copyWith(color: theme.primary),
      disabledName = theme.monthNameStyle.copyWith(
        color: _disabled(theme, theme.text),
      ),
      disabledCurrentName = theme.monthNameMarkedStyle.copyWith(
        color: _disabled(theme, theme.primary),
      ),
      pill = BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      ),
      selectedPill = BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      ),
      ring = BoxDecoration(
        border: Border.all(color: theme.todayRing, width: theme.todayRingWidth),
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      );

  /// [colour] at [theme]'s [CalendarThemeData.disabledOpacity].
  static Color _disabled(CalendarThemeData theme, Color colour) {
    return colour.withValues(alpha: colour.a * theme.disabledOpacity);
  }

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _PickerStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _PickerStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _PickerStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_PickerStyles> _memo = Expando<_PickerStyles>();
  static _PickerStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_PickerStyles>();
    _last = null;
  }

  final CalendarThemeData theme;

  /// A month's name, unmarked, which the picker measures names in beside
  /// [selectedName].
  final TextStyle name;

  /// The selected month's name, which the picker measures names in beside
  /// [name].
  final TextStyle selectedName;

  final TextStyle currentName;

  /// [name] and [currentName] at the theme's
  /// [CalendarThemeData.disabledOpacity].
  final TextStyle disabledName;
  final TextStyle disabledCurrentName;

  final BoxDecoration pill;
  final BoxDecoration selectedPill;
  final BoxDecoration ring;
}

/// [year]'s months in rows of [monthPickerColumns], January first, each
/// month a [MonthCell] on an equal share of the picker's width,
/// [selectedMonth]'s filled with the primary colour and [currentMonth]'s
/// ringed as today's number is. Every name reads at the text size, or
/// where the widest, in the theme's [CalendarThemeData.monthNameStyle] or
/// its [CalendarThemeData.monthNameMarkedStyle], would not fit its pill at
/// it, at the one smaller size that fits it. Every row is as tall as a cell
/// whose name is the tallest in either style at that size
/// ([MonthCell.heightFor]), whichever months are marked, its cells
/// stretched to it, and the picker is as tall as its rows: a height it
/// answers as its intrinsic height at any width asked, at the size the
/// names take at that width, its intrinsic width being 0. A tap on a
/// month reports [onSelectMonth]. A month before [firstMonth] draws
/// disabled and takes no tap.
///
/// A horizontal drag slides the picker with the finger, the next year's
/// months coming in from the right and the previous year's from the left,
/// and selects nothing; a release comes to rest on a whole year, the next
/// one the way a fling moves, and otherwise the nearest. The picker reports
/// through [onBrowse] each new year it is to rest on: the nearest while the
/// finger moves it, then the one a release slides to. A new [year] the
/// picker is not on slides it there. The picker shows, slides to and
/// reports no year before [firstMonth]'s, a drag stopping at it.
class MonthPicker extends StatefulWidget {
  const MonthPicker({
    super.key,
    required this.year,
    required this.selectedMonth,
    required this.currentMonth,
    required this.onSelectMonth,
    required this.onBrowse,
    this.firstMonth,
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

  /// The first day of the first month the picker takes; null for no first
  /// month.
  final DateTime? firstMonth;

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

  /// How many rows of [monthPickerColumns] a year's months take.
  static const int _rowCount = DateTime.monthsPerYear ~/ monthPickerColumns;

  /// The year over the picker, fractional while it slides: at 2026.25 the
  /// picker shows the last three quarters of 2026's months at its left and
  /// the first quarter of 2027's at its right.
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: _yearFrom(widget.year).toDouble(),
  );

  /// The year the picker rests on or slides to: the last [MonthPicker.year]
  /// given, or the last year reported through [MonthPicker.onBrowse] since.
  late int _year;

  /// What the picker measures names in and slides with.
  late _PickerStyles _styles;

  @override
  void initState() {
    super.initState();
    _year = widget.year;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _styles = _PickerStyles.of(context);
  }

  @override
  void didUpdateWidget(MonthPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A frame that brings a new theme with the new year calls this before
    // the rebuild that calls didChangeDependencies, so the slide below
    // reads the theme here.
    _styles = _PickerStyles.of(context);
    if (widget.year != _year) {
      _year = widget.year;
      _slideTo(widget.year);
    }
  }

  @override
  void reassemble() {
    _PickerStyles._reset();
    super.reassemble();
    _styles = _PickerStyles.of(context);
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  /// [year], or [MonthPicker.firstMonth]'s year where [year] lies before
  /// it.
  int _yearFrom(int year) {
    final first = widget.firstMonth?.year;
    return first != null && year < first ? first : year;
  }

  /// Slides to [year], or [MonthPicker.firstMonth]'s year where [year] lies
  /// before it, over the theme's motion, or at a zero duration, in this
  /// call.
  void _slideTo(int year) {
    final theme = _styles.theme;
    _position.animateTo(
      _yearFrom(year).toDouble(),
      duration: theme.motionDuration,
      curve: theme.motionCurve,
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

  /// Moves the picker with the finger, back no further than
  /// [MonthPicker.firstMonth]'s year.
  void _drag(DragUpdateDetails details) {
    var position =
        _position.value - details.primaryDelta! / context.size!.width;
    final first = widget.firstMonth?.year;
    if (first != null && position < first) {
      position = first.toDouble();
    }
    _position.value = position;
    _report(position.round());
  }

  /// A fling slides to the next whole year the way it moves, and any other
  /// release, whose [DragEndDetails.primaryVelocity] is zero, to the
  /// nearest year; none to a year before [MonthPicker.firstMonth]'s.
  void _endDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    final position = _position.value;
    final int fling;
    if (velocity < 0.0) {
      fling = (position + _epsilon).floor() + 1;
    } else if (velocity > 0.0) {
      fling = (position - _epsilon).ceil() - 1;
    } else {
      fling = position.round();
    }
    final target = _yearFrom(fling);
    _report(target);
    _slideTo(target);
  }

  /// The text scaler of the names on cells [cellWidth] wide: the
  /// context's, or where the widest name, in either style a cell draws a
  /// name in ([_PickerStyles.name] or [_PickerStyles.selectedName]) as its
  /// [Text] lays it out ([labelSizeIn]), would not fit a pill at it, a
  /// smaller one that fits it, so every name draws whole at one text scale
  /// whichever month is marked.
  TextScaler _nameScaler(BuildContext context, double cellWidth) {
    var scaler = MediaQuery.textScalerOf(context);
    final room = math.max(
      0.0,
      cellWidth -
          MonthCell.pillMargin.horizontal -
          MonthCell.pillPadding.horizontal,
    );
    final names = _monthNames(context);
    final defaults = DefaultTextStyle.of(context).style;
    final styles = <TextStyle>[_styles.name, _styles.selectedName];
    // A name's width does not quite follow its font size, so a smaller
    // scaler aims half a pixel inside the pill and is measured again, until
    // the widest name fits.
    for (var tries = 0; tries < 4; tries++) {
      var widest = 0.0;
      var fontSize = kDefaultFontSize;
      for (final style in styles) {
        final width = labelSizeIn(context, style, names, scaler: scaler).width;
        if (width > widest) {
          widest = width;
          fontSize = defaults.merge(style).fontSize ?? kDefaultFontSize;
        }
      }
      if (widest <= room) {
        break;
      }
      final size = scaler.scale(fontSize) * (room - 0.5) / widest;
      scaler = TextScaler.linear(math.max(0.0, size) / fontSize);
    }
    return scaler;
  }

  /// The names of the months in [context]'s localizations, January first.
  static List<String> _monthNames(BuildContext context) {
    final strings = CalendarLocalizations.of(context);
    return <String>[
      for (var month = 1; month <= DateTime.monthsPerYear; month++)
        strings.monthName(month),
    ];
  }

  /// The height of each row of cells whose names [scaler] scales: a
  /// [MonthCell]'s ([MonthCell.heightFor]) whose name is as tall as the
  /// tallest, in either style a cell draws a name in, as its [Text] lays it
  /// out ([labelSizeIn]), so every row is as tall whichever months are
  /// marked.
  double _rowHeight(BuildContext context, TextScaler scaler) {
    final names = _monthNames(context);
    var tallest = 0.0;
    for (final style in <TextStyle>[_styles.name, _styles.selectedName]) {
      tallest = math.max(
        tallest,
        labelSizeIn(context, style, names, scaler: scaler).height,
      );
    }
    return MonthCell.heightFor(tallest);
  }

  /// The height the picker lays out at [width] wide: its rows', each as
  /// tall as [_rowHeight] gives at the scaler [_nameScaler] gives that
  /// width's cells, as [build] lays them out. Read in the state's own
  /// context, which so depends on what it reads, so a new text scale or
  /// new localizations build the picker again, which lays out again
  /// whatever asked ([_RenderHeightBy.heightAt]).
  double _heightAt(double width) {
    final scaler = _nameScaler(context, width / monthPickerColumns);
    return _rowHeight(context, scaler) * _rowCount;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _startDrag,
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _endDrag,
      // The years beside the one over the picker paint outside it.
      child: ClipRect(
        child: _HeightBy(
          heightAt: _heightAt,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scaler = _nameScaler(
                context,
                constraints.maxWidth / monthPickerColumns,
              );
              final rowHeight = _rowHeight(context, scaler);
              return AnimatedBuilder(
                animation: _position,
                builder: (context, child) {
                  final position = _position.value;
                  final first = (position + _epsilon).floor();
                  return Stack(
                    children: <Widget>[
                      _buildYearAt(first, position, scaler, rowHeight),
                      if (position - first > _epsilon)
                        _buildYearAt(first + 1, position, scaler, rowHeight),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// [year]'s months, a picker's width to the right for each year it lies
  /// past [position], their names scaled by [scaler], in rows [rowHeight]
  /// tall.
  Widget _buildYearAt(
    int year,
    double position,
    TextScaler scaler,
    double rowHeight,
  ) {
    return FractionalTranslation(
      key: ValueKey<int>(year),
      translation: Offset(year - position, 0.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var row = 0; row < _rowCount; row++)
            SizedBox(
              height: rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (
                    var month = row * monthPickerColumns + 1;
                    month <= (row + 1) * monthPickerColumns;
                    month++
                  )
                    Expanded(child: _buildMonth(DateTime(year, month), scaler)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonth(DateTime month, TextScaler scaler) {
    final first = widget.firstMonth;
    final enabled = first == null ? null : !month.isBefore(first);
    return GestureDetector(
      key: monthPickerMonthKey(month),
      behavior: HitTestBehavior.opaque,
      onTap: enabled == false
          ? null
          : () {
              widget.onSelectMonth(month);
            },
      child: MonthCell(
        month: month,
        isSelected: month == widget.selectedMonth,
        isCurrent: month == widget.currentMonth,
        nameScaler: scaler,
        enabled: enabled,
      ),
    );
  }
}

/// One month of the [MonthPicker]: its full name, scaled by [nameScaler],
/// on a pill across the cell, as tall as the cell is given less
/// [pillMargin], and at least as tall as a [DayCell]'s circle and as the
/// name ([heightFor]), filled with the primary colour when
/// [isSelected] and ringed as today's number is when [isCurrent], in the
/// [CalendarTheme] above it. A screen reader hears the cell as a button
/// named by the month and the year. Where [enabled] is false the name
/// draws at the theme's [CalendarThemeData.disabledOpacity] unless the
/// month is selected, and a screen reader hears the month disabled.
class MonthCell extends StatelessWidget {
  const MonthCell({
    super.key,
    required this.month,
    required this.isSelected,
    required this.isCurrent,
    required this.nameScaler,
    this.enabled,
  });

  /// The first day of the month the cell shows.
  final DateTime month;

  final bool isSelected;
  final bool isCurrent;

  /// The text scaler of the name.
  final TextScaler nameScaler;

  /// Whether the month may be picked: false draws it disabled; null, as
  /// true, draws it enabled and gives its [Semantics] no enabled state.
  final bool? enabled;

  /// The space around the pill, which makes a row of pills at the default
  /// text size as tall as a row of the month's days.
  static const EdgeInsets pillMargin = EdgeInsets.symmetric(
    horizontal: 4.0,
    vertical: 8.0,
  );

  /// The space between the pill's ends and the name.
  static const EdgeInsets pillPadding = EdgeInsets.symmetric(horizontal: 4.0);

  /// The height of a cell whose name is [nameHeight] tall, where its height
  /// is not bounded: its pill's, at least a [DayCell]'s circle, as its
  /// [Container] gives it, within [pillMargin].
  static double heightFor(double nameHeight) {
    return pillMargin.vertical +
        math.max(dayCircleSize, pillPadding.vertical + nameHeight);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _PickerStyles.of(context);
    final strings = CalendarLocalizations.of(context);
    final disabled = enabled == false;
    final TextStyle nameStyle;
    if (isSelected) {
      nameStyle = styles.selectedName;
    } else if (isCurrent) {
      nameStyle = disabled ? styles.disabledCurrentName : styles.currentName;
    } else {
      nameStyle = disabled ? styles.disabledName : styles.name;
    }
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      label: strings.monthYear(month),
      excludeSemantics: true,
      child: Container(
        margin: pillMargin,
        constraints: const BoxConstraints(minHeight: dayCircleSize),
        padding: pillPadding,
        alignment: Alignment.center,
        decoration: isSelected ? styles.selectedPill : styles.pill,
        foregroundDecoration: isCurrent ? styles.ring : null,
        child: Text(
          strings.monthName(month.month),
          maxLines: 1,
          softWrap: false,
          textScaler: nameScaler,
          style: nameStyle,
        ),
      ),
    );
  }
}

/// [child], which builds under a [LayoutBuilder] and so answers no
/// intrinsic size, answering for its intrinsic heights what [heightAt]
/// gives for the width asked at, and 0 for its intrinsic widths, without
/// asking [child].
class _HeightBy extends SingleChildRenderObjectWidget {
  const _HeightBy({required this.heightAt, required Widget super.child});

  final double Function(double width) heightAt;

  @override
  _RenderHeightBy createRenderObject(BuildContext context) {
    return _RenderHeightBy(heightAt);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderHeightBy renderObject) {
    renderObject.heightAt = heightAt;
  }
}

class _RenderHeightBy extends RenderProxyBox {
  _RenderHeightBy(this._heightAt);

  double Function(double width) _heightAt;

  /// Takes [value] and lays the box out again, whatever it is: what the box
  /// answers reads the state that builds it, which the build may have
  /// changed, and laying out again makes an ancestor that asked the box's
  /// intrinsic height ask again ([RenderBox.markNeedsLayout]); the
  /// [LayoutBuilder] under it, which the same build lays out again, makes
  /// none ask where tight constraints make it a relayout boundary.
  set heightAt(double Function(double width) value) {
    _heightAt = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _heightAt(width);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _heightAt(width);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return 0.0;
  }
}
