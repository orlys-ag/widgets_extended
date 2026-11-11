/// The calendar's views as its menu names them, the units its chevrons
/// step by, what its header shows and calls, and the header built in.
library;

import 'package:flutter/material.dart';

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
/// with its icon and name. The Today button, the toggle and the view
/// button are 32 px circles around 22 px icons. The title gives up width, scaling down, only
/// where the row is too narrow for the rest.
///
/// The Today button shows while [CalendarHeaderDetails.canGoToToday] is
/// true, fading in and out over the theme's motion, and keeps its width
/// while hidden, when it takes no pointer, no focus and no screen reader's
/// attention. Drawn in the [CalendarTheme] above [context], under a
/// transparent [Material] of the ambient text style that it puts in where
/// no [Material] is above it. Its menu needs [MaterialLocalizations] above
/// it.
Widget defaultCalendarHeaderBuilder(
  BuildContext context,
  CalendarHeaderDetails details,
) {
  return CalendarHeader(details: details);
}

/// The built-in header of a calendar: [defaultCalendarHeaderBuilder]'s.
class CalendarHeader extends StatelessWidget {
  const CalendarHeader({super.key, required this.details});

  final CalendarHeaderDetails details;

  /// The style of the Today button, the edit mode toggle and the view
  /// button: a 32 px circle around a 22 px icon, in a tap target as tall
  /// as the chevrons'.
  static const ButtonStyle _roundButton = ButtonStyle(
    visualDensity: VisualDensity.compact,
    fixedSize: WidgetStatePropertyAll<Size>(Size.square(32.0)),
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
    final titleStyle = TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w600,
      color: theme.text,
    );
    final strings = CalendarLocalizations.of(context);
    final year = details.pickerYear;
    final day = details.day;
    final onToday = details.onToday;
    final onEditableChanged = details.onEditableChanged;
    final picksView = details.views.length > 1;
    final row = Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: _previousTooltip(strings, details.stepUnit),
                color: theme.text,
                visualDensity: VisualDensity.compact,
                onPressed: details.onPrevious,
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
                visualDensity: VisualDensity.compact,
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
                            Flexible(child: Text(_viewLabel(strings, value))),
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
