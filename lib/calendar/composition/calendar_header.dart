/// The calendar's views as its menu names them, the units its chevrons
/// step by, what its header shows and calls, and the header built in.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';

/// A view of a `CalendarView`: Agenda's month over a list of its days,
/// Day's timed grid of one day under the week strip, Week's timed grid of
/// a week, and Month's weeks of chips.
enum CalendarViewKind {
  /// Agenda: the calendar card's month over a list of days.
  agenda,

  /// Day: the timed grid of one day under the week strip.
  day,

  /// Week: the timed grid of a week.
  week,

  /// Month: the month's weeks of chips.
  month,
}

/// What the header's chevrons step by: a day, a week, a month, or a year
/// of the month picker.
enum CalendarStepUnit {
  /// A day, as Day steps.
  day,

  /// A week, as Week steps, and Agenda while its calendar card is folded
  /// into the week strip.
  week,

  /// A month, as Month steps, and Agenda while its calendar card shows
  /// the month.
  month,

  /// A year, as the month picker steps while it is open.
  year,
}

/// What a calendar header shows and the actions it calls, which a
/// [CalendarHeaderBuilder] receives.
@immutable
final class CalendarHeaderDetails {
  /// The header's state and actions.
  const CalendarHeaderDetails({
    required this.view,
    required this.views,
    required this.day,
    required this.pickerYear,
    required this.stepUnit,
    required this.onPrevious,
    required this.onNext,
    required this.onSelectView,
    required this.onOpenPicker,
    required this.onClosePicker,
    this.onToday,
    this.canGoToToday = false,
    this.editable = false,
    this.onEditableChanged,
    this.canStepBack = true,
  });

  /// The view shown.
  final CalendarViewKind view;

  /// The views the calendar offers, in the order its menu lists them; an
  /// unmodifiable list.
  final List<CalendarViewKind> views;

  /// The day whose month and year the title names: the day the calendar
  /// card or the week strip shows while a drag or a chevron has moved it
  /// off the selected day, and otherwise the selected day.
  final DateTime day;

  /// The year the month picker shows; null while it does not show.
  final int? pickerYear;

  /// What [onPrevious] and [onNext] step by: the year while the month
  /// picker shows, and otherwise the day in Day, the week in Week and in
  /// folded Agenda, and the month in unfolded Agenda and in Month.
  final CalendarStepUnit stepUnit;

  /// Steps back by [stepUnit].
  final VoidCallback onPrevious;

  /// Whether [onPrevious] steps back: false where the calendar browses no
  /// further back, as a `CalendarDayPicker` that browses no week or month
  /// before its first day does at that day's week, month or year. The
  /// built-in header then draws its previous chevron disabled.
  final bool canStepBack;

  /// Steps on by [stepUnit].
  final VoidCallback onNext;

  /// Shows a view, which [views] must list: a debug build asserts it, and
  /// a release build shows the first view [views] lists in place of one it
  /// does not.
  final ValueChanged<CalendarViewKind> onSelectView;

  /// Opens the month picker on the selected day's year.
  final VoidCallback onOpenPicker;

  /// Closes the month picker.
  final VoidCallback onClosePicker;

  /// Brings the calendar to today, as [CalendarController.goTo] of today
  /// does: closes the month picker, and selects the shown day nearest
  /// today, or where that day is selected, brings the calendar card or
  /// the week strip a slide, a chevron or a drag moved back to it. Null
  /// where whoever made these details gives none; a `CalendarView` gives
  /// one.
  final VoidCallback? onToday;

  /// Whether [onToday] would change the day the calendar shows: while the
  /// selected day is not the shown day nearest today, on the clock of the
  /// store's zone, or the calendar card or the week strip has moved off
  /// the selected day. The month picker alone does not make it true.
  final bool canGoToToday;

  /// Whether the calendar is in edit mode (`CalendarView.editable`).
  final bool editable;

  /// Reports a toggle of edit mode with the mode asked for, the opposite
  /// of [editable] (`CalendarView.onEditableChanged`); null where the
  /// host takes none.
  final ValueChanged<bool>? onEditableChanged;
}

/// The key of the built-in header's Today button.
const ValueKey<String> calendarTodayButtonKey = ValueKey<String>(
  "calendar-today",
);

/// The key of the built-in header's edit mode toggle.
const ValueKey<String> calendarEditToggleKey = ValueKey<String>(
  "calendar-edit-toggle",
);

/// The key of the built-in header's view button.
const ValueKey<String> calendarViewButtonKey = ValueKey<String>(
  "calendar-view-button",
);

/// Builds a calendar's header from [details], in place of the built-in
/// one.
typedef CalendarHeaderBuilder =
    Widget Function(BuildContext context, CalendarHeaderDetails details);

/// The built-in header for [details], in one row. At its start: the
/// previous and next chevrons around the title, which names
/// [CalendarHeaderDetails.day]'s month and year, or the month picker's year
/// while it shows, and opens or closes the picker when tapped; then, where
/// [CalendarHeaderDetails.onToday] is given, the Today button, a calendar
/// icon that calls it. At its end: where
/// [CalendarHeaderDetails.onEditableChanged] is given, the edit mode
/// toggle, a pencil, filled and tinted while
/// [CalendarHeaderDetails.editable] is true, which reports the opposite
/// mode; then, 4 px on, where [CalendarHeaderDetails.views] lists more
/// than one view, the view button, the icon of the view shown, which a
/// screen reader hears named, and which opens a menu of the views, each
/// with its icon and name. The chevrons are 32 px circles around 24 px
/// icons, the previous chevron's circle lying at the row's start; the Today
/// button, the toggle and the view button are 32 px circles around 22 px
/// icons. The title gives up width, scaling down, only where the row is too
/// narrow for the rest. While [CalendarHeaderDetails.canStepBack] is false
/// the previous chevron draws at the theme's
/// [CalendarThemeData.disabledOpacity] and takes no press.
///
/// The Today button shows while [CalendarHeaderDetails.canGoToToday] is
/// true, fading in and out over the theme's motion, and keeps its width
/// while hidden, when it takes no pointer, no focus and no screen reader's
/// attention. Drawn in the [CalendarTheme] above [context], under a
/// transparent [Material] of the ambient text style that it puts in where
/// no [Material] is above it. Its menu reads the [MaterialLocalizations]
/// above it, which a `CalendarView` puts in where the app gives none.
Widget defaultCalendarHeaderBuilder(
  BuildContext context,
  CalendarHeaderDetails details,
) {
  return CalendarHeader(details: details);
}

/// The built-in header of a calendar: [defaultCalendarHeaderBuilder]'s.
class CalendarHeader extends StatelessWidget {
  const CalendarHeader({super.key, required this.details, this.trailing});

  final CalendarHeaderDetails details;

  /// What lies at the row's end, after the edit mode toggle and the view
  /// button, 4 logical pixels after whichever of them shows, and centred on
  /// the row, at its own width, at most the rest of the row's, or, as a
  /// [Flexible] or an [Expanded], at its flex's part of the row beside
  /// the rest, whose flex is 1, as in a [Row], and within the share
  /// of the row a [CalendarHeaderTrailingShare] at its top gives; null for
  /// nothing. The row is a [CalendarHeaderRow] whether given one or not,
  /// so one coming or going keeps the rest of the row's state, its focus
  /// included.
  final Widget? trailing;

  /// The diameter of the header's round buttons, the chevrons included.
  static const double _circle = 32.0;

  /// The style of the header's title in [theme].
  static TextStyle titleStyleOf(CalendarThemeData theme) {
    return TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w600,
      color: theme.text,
    );
  }

  /// The height of the chevrons' tap targets under the Material theme at
  /// [context], which the header's row is at least as tall as: a
  /// [_chevronButton]'s, whose compact density takes 8 logical pixels from
  /// the theme's [MaterialTapTargetSize.padded] target, and which with
  /// [MaterialTapTargetSize.shrinkWrap] is its [_circle].
  static double chevronExtentOf(BuildContext context) {
    switch (Theme.of(context).materialTapTargetSize) {
      case MaterialTapTargetSize.padded:
        return math.max(
          _circle,
          kMinInteractiveDimension +
              VisualDensity.compact.baseSizeAdjustment.dy,
        );
      case MaterialTapTargetSize.shrinkWrap:
        return _circle;
    }
  }

  /// The style of the chevrons: a [_circle] circle around a 24 px icon.
  static const ButtonStyle _chevronButton = ButtonStyle(
    visualDensity: VisualDensity.compact,
    fixedSize: WidgetStatePropertyAll<Size>(Size.square(_circle)),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    iconSize: WidgetStatePropertyAll<double>(24.0),
    shape: WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
  );

  /// The style of the Today button, the edit mode toggle and the view
  /// button: a [_circle] circle around a 22 px icon, in a tap target as
  /// tall as the chevrons'.
  static const ButtonStyle _roundButton = ButtonStyle(
    visualDensity: VisualDensity.compact,
    fixedSize: WidgetStatePropertyAll<Size>(Size.square(_circle)),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    iconSize: WidgetStatePropertyAll<double>(22.0),
    shape: WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
  );

  static String _viewLabel(
    CalendarLocalizations strings,
    CalendarViewKind view,
  ) {
    switch (view) {
      case CalendarViewKind.agenda:
        return strings.agendaView;
      case CalendarViewKind.day:
        return strings.dayView;
      case CalendarViewKind.week:
        return strings.weekView;
      case CalendarViewKind.month:
        return strings.monthView;
    }
  }

  static IconData _viewIcon(CalendarViewKind view) {
    switch (view) {
      case CalendarViewKind.agenda:
        return Icons.view_agenda_outlined;
      case CalendarViewKind.day:
        return Icons.calendar_view_day_outlined;
      case CalendarViewKind.week:
        return Icons.calendar_view_week_outlined;
      case CalendarViewKind.month:
        return Icons.calendar_view_month_outlined;
    }
  }

  static String _previousTooltip(
    CalendarLocalizations strings,
    CalendarStepUnit unit,
  ) {
    switch (unit) {
      case CalendarStepUnit.day:
        return strings.previousDayTooltip;
      case CalendarStepUnit.week:
        return strings.previousWeekTooltip;
      case CalendarStepUnit.month:
        return strings.previousMonthTooltip;
      case CalendarStepUnit.year:
        return strings.previousYearTooltip;
    }
  }

  static String _nextTooltip(
    CalendarLocalizations strings,
    CalendarStepUnit unit,
  ) {
    switch (unit) {
      case CalendarStepUnit.day:
        return strings.nextDayTooltip;
      case CalendarStepUnit.week:
        return strings.nextWeekTooltip;
      case CalendarStepUnit.month:
        return strings.nextMonthTooltip;
      case CalendarStepUnit.year:
        return strings.nextYearTooltip;
    }
  }

  /// The width of the widest of [year]'s titles as the title's [Text] lays
  /// it out in [style]: merged over the default one, bold where the
  /// platform asks for bold text, at the platform's text scale. The title
  /// takes that width whatever the month, so the next chevron after it
  /// stays put.
  static double _titleWidth(BuildContext context, TextStyle style, int year) {
    var merged = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      merged = merged.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    final strings = CalendarLocalizations.of(context);
    var widest = 0.0;
    for (var month = 1; month <= DateTime.monthsPerYear; month++) {
      painter.text = TextSpan(
        text: strings.shortMonthYear(DateTime(year, month)),
        style: merged,
      );
      painter.layout();
      if (painter.width > widest) {
        widest = painter.width;
      }
    }
    painter.dispose();
    return widest.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CalendarTheme.of(context);
    final titleStyle = titleStyleOf(theme);
    final strings = CalendarLocalizations.of(context);
    final year = details.pickerYear;
    final day = details.day;
    final onToday = details.onToday;
    final onEditableChanged = details.onEditableChanged;
    final picksView = details.views.length > 1;
    final trailing = this.trailing;
    final buttons = Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              _CircleAtStart(
                extent: _circle,
                child: IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: _previousTooltip(strings, details.stepUnit),
                  color: theme.text,
                  disabledColor: theme.text.withValues(
                    alpha: theme.text.a * theme.disabledOpacity,
                  ),
                  style: _chevronButton,
                  onPressed: details.canStepBack ? details.onPrevious : null,
                ),
              ),
              // Shrinks, and the title in it, only where the row is too
              // narrow for it.
              Flexible(
                child: Tooltip(
                  message: year == null
                      ? strings.pickMonthTooltip
                      : strings.closeMonthsTooltip,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8.0),
                    onTap: year == null
                        ? details.onOpenPicker
                        : details.onClosePicker,
                    child: SizedBox(
                      width: _titleWidth(context, titleStyle, year ?? day.year),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          year == null ? strings.shortMonthYear(day) : "$year",
                          style: titleStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: _nextTooltip(strings, details.stepUnit),
                color: theme.text,
                style: _chevronButton,
                onPressed: details.onNext,
              ),
              if (onToday != null)
                _TodayButton(
                  shown: details.canGoToToday,
                  tooltip: strings.todayTooltip,
                  theme: theme,
                  onPressed: onToday,
                ),
            ],
          ),
        ),
        if (onEditableChanged != null)
          IconButton(
            key: calendarEditToggleKey,
            isSelected: details.editable,
            icon: const Icon(Icons.edit_outlined),
            selectedIcon: const Icon(Icons.edit),
            tooltip: strings.editModeTooltip,
            style: _roundButton.copyWith(
              foregroundColor: WidgetStateProperty.fromMap(
                <WidgetStatesConstraint, Color>{
                  WidgetState.selected: theme.primary,
                  WidgetState.any: theme.text,
                },
              ),
              backgroundColor:
                  WidgetStateProperty.fromMap(<WidgetStatesConstraint, Color>{
                    WidgetState.selected: theme.primaryTint,
                    WidgetState.any: Colors.transparent,
                  }),
            ),
            onPressed: () {
              onEditableChanged(!details.editable);
            },
          ),
        if (onEditableChanged != null && picksView) const SizedBox(width: 4.0),
        if (picksView)
          // One node, so a screen reader hears the view shown with the
          // button's tooltip.
          MergeSemantics(
            child: Semantics(
              value: _viewLabel(strings, details.view),
              child: PopupMenuButton<CalendarViewKind>(
                key: calendarViewButtonKey,
                tooltip: strings.viewMenuTooltip,
                initialValue: details.view,
                color: theme.surface,
                icon: Icon(_viewIcon(details.view)),
                iconColor: theme.text,
                style: _roundButton,
                onSelected: details.onSelectView,
                itemBuilder: (context) {
                  return <PopupMenuEntry<CalendarViewKind>>[
                    for (final value in details.views)
                      PopupMenuItem<CalendarViewKind>(
                        value: value,
                        child: Row(
                          children: <Widget>[
                            Icon(_viewIcon(value), color: theme.text),
                            const SizedBox(width: 12.0),
                            Flexible(
                              child: Text(
                                _viewLabel(strings, value),
                                // The menu's own label style sets the
                                // size; the colour is the calendar's, on
                                // the calendar's surface.
                                style: TextStyle(color: theme.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ];
                },
              ),
            ),
          ),
      ],
    );
    final row = CalendarHeaderRow(
      gap: onEditableChanged != null || picksView ? 4.0 : 0.0,
      lead: buttons,
      trailing: trailing,
    );
    // The chevrons, the title's ink and the menu need a Material above
    // them. One put in keeps the ambient text style, which _titleWidth
    // measures the title in.
    if (LookupBoundary.findAncestorWidgetOfExactType<Material>(context) !=
        null) {
      return row;
    }
    return Material(
      type: MaterialType.transparency,
      textStyle: DefaultTextStyle.of(context).style,
      child: row,
    );
  }
}

/// [lead] and, where given, [trailing] in one row, laid out as a [Row] of
/// an [Expanded] [lead], [gap] logical pixels and [trailing] lays them out:
/// [trailing] at its own width, at most the row's width less [gap], or,
/// where it is a [Flexible] or an [Expanded] and the width is bounded, at
/// its flex's part of the row less [gap], [lead]'s flex being 1; and at
/// most [CalendarHeaderTrailingShare.share] of the row's width where one
/// lies at its top. [lead] takes the rest of a bounded width, or its flex's
/// part where [trailing] is flexible, and lies at its own width under an
/// unbounded one, as does a flexible [trailing]. [lead] lies at the row's
/// start and [trailing] [gap] after it, each centred on the row, which is
/// as tall as the taller. Without [trailing], [lead] takes the whole row
/// and [gap] counts for nothing.
///
/// Its intrinsic width is the one at which both lie at their own intrinsic
/// widths, as such a [Row] answers it, [trailing] within its share; its
/// intrinsic height, the taller of the two at the widths a row that wide
/// gives them.
class CalendarHeaderRow extends MultiChildRenderObjectWidget {
  CalendarHeaderRow({
    super.key,
    required Widget lead,
    Widget? trailing,
    this.gap = 0.0,
  }) : super(children: <Widget>[lead, ?trailing]);

  /// The space between the lead and the trailing widget, in logical pixels.
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderHeaderRow(
      gap: gap,
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderHeaderRow)
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

/// The parent data of a [CalendarHeaderRow]'s children, whose flex and fit
/// a [Flexible] or an [Expanded] trailing widget sets as under a [Row].
class CalendarHeaderRowParentData extends FlexParentData {
  /// The most of the row's width the trailing widget takes, over 0 and at
  /// most 1; null for no limit but the row's.
  double? share;
}

/// Limits [child], the trailing widget of a [CalendarHeaderRow], to [share]
/// of the row's width, over 0 and at most 1. It lies directly under the
/// row, as a [Flexible] lies under a [Flex].
class CalendarHeaderTrailingShare
    extends ParentDataWidget<CalendarHeaderRowParentData> {
  const CalendarHeaderTrailingShare({
    super.key,
    required this.share,
    required super.child,
  }) : assert(share > 0.0 && share <= 1.0);

  final double share;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as CalendarHeaderRowParentData;
    if (parentData.share != share) {
      parentData.share = share;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass {
    return CalendarHeaderRow;
  }
}

class _RenderHeaderRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, CalendarHeaderRowParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          CalendarHeaderRowParentData
        > {
  _RenderHeaderRow({required double gap, required TextDirection textDirection})
    : _gap = gap,
      _textDirection = textDirection;

  double _gap;

  set gap(double value) {
    if (value == _gap) {
      return;
    }
    _gap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! CalendarHeaderRowParentData) {
      child.parentData = CalendarHeaderRowParentData();
    }
  }

  RenderBox get _lead {
    return firstChild!;
  }

  RenderBox? get _trailing {
    return childCount > 1 ? lastChild : null;
  }

  static CalendarHeaderRowParentData _dataOf(RenderBox child) {
    return child.parentData! as CalendarHeaderRowParentData;
  }

  /// The flex of [trailing]: 0 where it lies at its own width.
  static int _flexOf(RenderBox trailing) {
    return _dataOf(trailing).flex ?? 0;
  }

  /// The width a [Row] gives each unit of flex in a row [width] wide, the
  /// lead's flex being 1, where [trailing] is flexible and [width] bounded;
  /// null otherwise, as [trailing] then lies at its own width.
  double? _spacePerFlex(RenderBox trailing, double width) {
    final flex = _flexOf(trailing);
    if (flex <= 0 || !width.isFinite) {
      return null;
    }
    return math.max(0.0, width - _gap) / (flex + 1);
  }

  /// The most of a row [width] wide that [trailing] takes.
  double _roomOf(RenderBox trailing, double width) {
    final share = _dataOf(trailing).share;
    final perFlex = _spacePerFlex(trailing, width);
    final room = perFlex == null
        ? math.max(0.0, width - _gap)
        : perFlex * _flexOf(trailing);
    return share == null ? room : math.min(room, width * share);
  }

  /// The width of a row whose lead is [lead] wide and whose [trailing],
  /// [width] wide, lies within its room: a flexible one's flex fraction
  /// against the lead's, as a [Row] answers it.
  double _widthHolding(double lead, RenderBox trailing, double width) {
    final share = _dataOf(trailing).share;
    final flex = _flexOf(trailing);
    final whole = flex > 0
        ? math.max(lead, width / flex) * (flex + 1) + _gap
        : lead + _gap + width;
    return share == null ? whole : math.max(whole, width / share);
  }

  double _intrinsicWidth(double Function(RenderBox child) extent) {
    final lead = extent(_lead);
    final trailing = _trailing;
    if (trailing == null) {
      return lead;
    }
    return _widthHolding(lead, trailing, extent(trailing));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return _intrinsicWidth((child) {
      return child.getMinIntrinsicWidth(height);
    });
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return _intrinsicWidth((child) {
      return child.getMaxIntrinsicWidth(height);
    });
  }

  /// The taller child's [extent] at the widths a row [width] wide gives
  /// them, the trailing widget at its intrinsic width within its room.
  double _intrinsicHeight(
    double width,
    double Function(RenderBox child, double width) extent,
  ) {
    final trailing = _trailing;
    if (trailing == null) {
      return extent(_lead, width);
    }
    final perFlex = _spacePerFlex(trailing, width);
    final room = _roomOf(trailing, width);
    final trailingWidth = perFlex == null
        ? math.min(trailing.getMaxIntrinsicWidth(double.infinity), room)
        : room;
    final double leadWidth;
    if (!width.isFinite) {
      leadWidth = double.infinity;
    } else if (perFlex != null) {
      leadWidth = perFlex;
    } else {
      leadWidth = math.max(0.0, width - _gap - trailingWidth);
    }
    return math.max(extent(_lead, leadWidth), extent(trailing, trailingWidth));
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _intrinsicHeight(width, (child, width) {
      return child.getMinIntrinsicHeight(width);
    });
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _intrinsicHeight(width, (child, width) {
      return child.getMaxIntrinsicHeight(width);
    });
  }

  /// Sizes the children through [sizeOf] under [constraints], the trailing
  /// widget first, and gives the row's size with each child's.
  ({Size size, Size lead, Size? trailing}) _measure(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) sizeOf,
  ) {
    final width = constraints.maxWidth;
    final trailing = _trailing;
    Size? trailingSize;
    double? perFlex;
    var taken = 0.0;
    if (trailing != null) {
      perFlex = _spacePerFlex(trailing, width);
      final room = _roomOf(trailing, width);
      final tight =
          perFlex != null &&
          (_dataOf(trailing).fit ?? FlexFit.tight) == FlexFit.tight;
      trailingSize = sizeOf(
        trailing,
        BoxConstraints(
          minWidth: tight ? room : 0.0,
          maxWidth: room,
          maxHeight: constraints.maxHeight,
        ),
      );
      taken = _gap + trailingSize.width;
    }
    final BoxConstraints leadConstraints;
    if (width.isFinite) {
      final rest = perFlex ?? math.max(0.0, width - taken);
      leadConstraints = BoxConstraints(
        minWidth: rest,
        maxWidth: rest,
        maxHeight: constraints.maxHeight,
      );
    } else {
      leadConstraints = BoxConstraints(maxHeight: constraints.maxHeight);
    }
    final leadSize = sizeOf(_lead, leadConstraints);
    final size = constraints.constrain(
      Size(
        width.isFinite ? width : leadSize.width + taken,
        math.max(leadSize.height, trailingSize?.height ?? 0.0),
      ),
    );
    return (size: size, lead: leadSize, trailing: trailingSize);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return _measure(constraints, (child, constraints) {
      return child.getDryLayout(constraints);
    }).size;
  }

  @override
  void performLayout() {
    final measured = _measure(constraints, (child, constraints) {
      child.layout(constraints, parentUsesSize: true);
      return child.size;
    });
    size = measured.size;
    final ltr = _textDirection == TextDirection.ltr;
    final lead = measured.lead;
    (_lead.parentData! as BoxParentData).offset = Offset(
      ltr ? 0.0 : size.width - lead.width,
      (size.height - lead.height) / 2.0,
    );
    final trailing = _trailing;
    final trailingSize = measured.trailing;
    if (trailing != null && trailingSize != null) {
      final after = lead.width + _gap;
      (trailing.parentData! as BoxParentData).offset = Offset(
        ltr ? after : size.width - after - trailingSize.width,
        (size.height - trailingSize.height) / 2.0,
      );
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToHighestActualBaseline(baseline);
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

/// The header's Today button: a calendar icon in the theme's text colour,
/// as the header's other icons, at full opacity while [shown] and at none
/// otherwise, fading between them over the theme's motion. Hidden, it keeps its size and
/// takes no pointer, no focus and no screen reader's attention.
class _TodayButton extends StatelessWidget {
  const _TodayButton({
    required this.shown,
    required this.tooltip,
    required this.theme,
    required this.onPressed,
  });

  final bool shown;
  final String tooltip;
  final CalendarThemeData theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: !shown,
      child: ExcludeSemantics(
        excluding: !shown,
        child: IgnorePointer(
          ignoring: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1.0 : 0.0,
            duration: theme.motionDuration,
            curve: theme.motionCurve,
            child: IconButton(
              key: calendarTodayButtonKey,
              icon: const Icon(Icons.today_outlined),
              tooltip: tooltip,
              color: theme.text,
              style: CalendarHeader._roundButton,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

/// [child], a button whose [extent]-wide circle is centred in its tap
/// target, placed so that the circle lies at the box's start. The box is as
/// wide as the child less the target's margin beside the circle on that
/// side, which the child overhangs past the start; there it takes no
/// pointer, as a [RenderBox] hit-tests only inside its own size. A target
/// no wider than the circle leaves no margin.
class _CircleAtStart extends SingleChildRenderObjectWidget {
  const _CircleAtStart({required this.extent, required Widget super.child});

  final double extent;

  @override
  _RenderCircleAtStart createRenderObject(BuildContext context) {
    return _RenderCircleAtStart(
      extent: extent,
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCircleAtStart renderObject,
  ) {
    renderObject
      ..extent = extent
      ..textDirection = Directionality.of(context);
  }
}

class _RenderCircleAtStart extends RenderShiftedBox {
  _RenderCircleAtStart({
    required double extent,
    required TextDirection textDirection,
  }) : _extent = extent,
       _textDirection = textDirection,
       super(null);

  double get extent {
    return _extent;
  }

  double _extent;

  set extent(double value) {
    if (value == _extent) {
      return;
    }
    _extent = value;
    markNeedsLayout();
  }

  TextDirection get textDirection {
    return _textDirection;
  }

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  /// The margin beside the circle on each side of a child [width] wide.
  double _marginOf(double width) {
    return math.max(0.0, (width - _extent) / 2.0);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final width = child?.getMinIntrinsicWidth(height) ?? 0.0;
    return width - _marginOf(width);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final width = child?.getMaxIntrinsicWidth(height) ?? 0.0;
    return width - _marginOf(width);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) {
      return constraints.smallest;
    }
    final size = child.getDryLayout(constraints.loosen());
    return constraints.constrain(
      Size(size.width - _marginOf(size.width), size.height),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    final childSize = child.size;
    final margin = _marginOf(childSize.width);
    size = constraints.constrain(
      Size(childSize.width - margin, childSize.height),
    );
    final dx = _textDirection == TextDirection.ltr
        ? -margin
        : size.width - childSize.width + margin;
    (child.parentData! as BoxParentData).offset = Offset(
      dx,
      (size.height - childSize.height) / 2.0,
    );
  }
}
