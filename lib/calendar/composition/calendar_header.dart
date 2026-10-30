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
}

/// Builds a calendar's header from [details], in place of the built-in
/// one.
typedef CalendarHeaderBuilder =
    Widget Function(BuildContext context, CalendarHeaderDetails details);

/// The built-in header for [details]: the previous and next chevrons
/// around the title, which names [CalendarHeaderDetails.day]'s month and
/// year, or the month picker's year while it shows, and opens or closes
/// the picker when tapped; and the name of the view shown, with a menu of
/// [CalendarHeaderDetails.views] where it lists more than one. Drawn in the
/// [CalendarTheme] above [context]. Its menu needs [MaterialLocalizations]
/// above it.
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
    final viewName = Text(_viewLabel(strings, details.view), style: titleStyle);
    return Row(
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
            ],
          ),
        ),
        if (details.views.length == 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: viewName,
          )
        else
          PopupMenuButton<CalendarViewKind>(
            tooltip: strings.viewMenuTooltip,
            initialValue: details.view,
            color: theme.surface,
            onSelected: details.onSelectView,
            itemBuilder: (context) {
              return <PopupMenuEntry<CalendarViewKind>>[
                for (final value in details.views)
                  PopupMenuItem<CalendarViewKind>(
                    value: value,
                    child: Text(_viewLabel(strings, value)),
                  ),
              ];
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 8.0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  viewName,
                  const SizedBox(width: 4.0),
                  Icon(Icons.keyboard_arrow_down, color: theme.text),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
