/// The state of a calendar card: its fold, the month or week it has
/// browsed to, the month picker over it and the motions of both, which a
/// host's State owns and the card reads.
library;

import 'package:flutter/widgets.dart';

import '../../scheduling/scheduling.dart';
import '../views/month_strip.dart' show monthFoldDay;
import 'calendar_header.dart' show CalendarStepUnit;

/// What a [CalendarCardController] reads of the State that owns it, and how
/// it runs its changes as that State's events.
abstract interface class CalendarCardHost {
  /// The day the card shows selected.
  DateTime get cardSelectedDay;

  /// The day the card marks as today.
  DateTime get cardToday;

  /// The weekdays the card shows.
  CalendarWeekdaySet get cardWeekdays;

  /// The start of [day]'s date on the host's clock.
  DateTime cardDayIn(DateTime day);

  /// Selects [day] as one event of the host and answers true, or answers
  /// false where the host refuses it. The controller never calls it inside
  /// [runCardEvent].
  bool selectCardDay(DateTime day);

  /// Runs [change] as one event of the host.
  void runCardEvent(VoidCallback change);
}

/// Who set [CalendarCardController.browsedDay] to the day at the middle of
/// the week strip.
enum _StripBrowse {
  /// Not the strip: a slide of the month strip or a chevron, or no browse.
  none,

  /// A drag of the week strip.
  dragged,
}

/// The calendar card's state, owned by a host State that makes it in its
/// `initState` with its own [TickerProvider] and disposes it in its
/// `dispose`.
///
/// Each event runs its change through [CalendarCardHost.runCardEvent],
/// then notifies, then starts its motion; a select calls
/// [CalendarCardHost.selectCardDay] outside the event. The silent members,
/// [forgetBrowse], [recall], [hidePicker], [retakeBrowse] and
/// [endStripBrowse], change state alone, start no motion and notify
/// nothing, for a host to call inside its own event.
final class CalendarCardController extends ChangeNotifier {
  CalendarCardController({
    required TickerProvider vsync,
    required CalendarCardHost host,
    bool folded = false,
  }) : _host = host,
       _folded = folded,
       _collapse = AnimationController(vsync: vsync, value: folded ? 1.0 : 0.0),
       _pickerShown = AnimationController(vsync: vsync) {
    _collapse.addListener(_handleFold);
  }

  final CalendarCardHost _host;

  /// How far the card has folded, 0 for the month and 1 for its week:
  /// linear, so a drag on the pull tab moves it with the finger.
  AnimationController get collapse {
    return _collapse;
  }

  final AnimationController _collapse;

  /// How far the month picker has come in, 0 for out and 1 for in.
  Animation<double> get pickerShown {
    return _pickerShown;
  }

  final AnimationController _pickerShown;

  /// The curve [setMotion] last gave, on which the fold and the picker
  /// move.
  Curve _curve = Curves.linear;

  /// Whether the card settles on its week strip rather than its month.
  bool get folded {
    return _folded;
  }

  bool _folded;

  /// Whether the month picker shows, and so takes pointers.
  bool get picksMonth {
    return _picksMonth;
  }

  bool _picksMonth = false;

  /// The year the month picker shows.
  int get pickerYear {
    return _pickerYear;
  }

  int _pickerYear = 0;

  /// A day of the month the card shows and the header names since a slide
  /// of the month strip, a chevron or a drag of the week strip moved the
  /// card off the selected day's month or week: the first day of the month
  /// the month strip rests on, or the day at the middle of the week strip.
  /// Null while the card shows the selected day.
  DateTime? get browsedDay {
    return _browsedDay;
  }

  DateTime? _browsedDay;

  /// Counts the calls that bring the week strip back to the selected day,
  /// which `WeekStrip.recalls` passes on.
  int get stripRecalls {
    return _stripRecalls;
  }

  int _stripRecalls = 0;

  /// Who set [_browsedDay] to the day at the week strip's middle. A strip
  /// browse ends once a fold short of the week ([_handleFold]) or new
  /// weekdays end that strip, as the next one opens on the week of
  /// [monthFoldDay].
  _StripBrowse _stripBrowse = _StripBrowse.none;

  /// The day at the middle of the week strip a drag left, which a strip the
  /// card builds opens with at its middle; null for the week of
  /// [monthFoldDay].
  DateTime? get stripMiddleDay {
    return _stripBrowse == _StripBrowse.none ? null : _browsedDay;
  }

  /// The first day of the month the card shows.
  DateTime get month {
    final day = _browsedDay ?? _host.cardSelectedDay;
    return DateTime(day.year, day.month);
  }

  /// Whether the card or the week strip, as a slide, a chevron or a drag
  /// left it, holds the selected day, whether the month picker shows over
  /// it or not.
  bool get holdsSelectedDay {
    final browsed = _browsedDay;
    if (browsed == null) {
      return true;
    }
    final day = _host.cardSelectedDay;
    if (!_folded) {
      return browsed.year == day.year && browsed.month == day.month;
    }
    final target = CalendarDates.dayNumber(day);
    return _stripDays().any((shown) {
      return CalendarDates.dayNumber(shown) == target;
    });
  }

  /// The shown days the folded card's week strip holds: a week's count of
  /// them around [_browsedDay], the day a drag brought to the strip's
  /// middle, the first half of the count before it, as `WeekStrip` finds
  /// its middle; or, where a slide or a chevron browsed the card, or none
  /// did, the shown days of the week the strip opens on ([monthFoldDay]).
  List<DateTime> _stripDays() {
    final weekdays = _host.cardWeekdays;
    final browsed = _browsedDay;
    if (browsed == null || _stripBrowse == _StripBrowse.none) {
      return CalendarDates.shownDaysOfWeek(
        monthFoldDay(
          month,
          selectedDay: _host.cardSelectedDay,
          today: _host.cardToday,
          weekdays: weekdays,
        ),
        weekdays,
      );
    }
    final count = weekdays.columns.length;
    var shown = browsed;
    for (var step = 0; step < count ~/ 2; step++) {
      shown = CalendarDates.nextShownDay(shown, -1, weekdays);
    }
    final days = <DateTime>[];
    for (var step = 0; step < count; step++) {
      days.add(shown);
      shown = CalendarDates.nextShownDay(shown, 1, weekdays);
    }
    return days;
  }

  /// What a chevron steps by: a year while the month picker shows, a week
  /// while the card is folded, and a month otherwise.
  CalendarStepUnit get stepUnit {
    if (_picksMonth) {
      return CalendarStepUnit.year;
    }
    return _folded ? CalendarStepUnit.week : CalendarStepUnit.month;
  }

  /// Sets the duration of the fold's and the picker's motions, and the
  /// curve each motion an event starts takes.
  void setMotion(Duration duration, Curve curve) {
    _collapse.duration = duration;
    _pickerShown.duration = duration;
    _curve = curve;
  }

  /// Runs [change] as one event of the host, then notifies.
  void _event(VoidCallback change) {
    _host.runCardEvent(change);
    notifyListeners();
  }

  /// Moves the card to the month of [day], selecting nothing.
  void browseMonth(DateTime day) {
    _event(() {
      _browsedDay = _host.cardDayIn(DateTime(day.year, day.month));
      _stripBrowse = _StripBrowse.none;
    });
  }

  /// Notes [day], which a drag brought to the week strip's middle.
  void browseStrip(DateTime day) {
    _event(() {
      _browsedDay = _host.cardDayIn(day);
      _stripBrowse = _StripBrowse.dragged;
    });
  }

  /// Ends a strip browse once the fold leaves the week: the card builds
  /// its `WeekStrip` only at a full fold, so the strip a drag moved is
  /// gone, and the one the card folds into next opens on the week of
  /// [monthFoldDay].
  void _handleFold() {
    if (_stripBrowse == _StripBrowse.dragged && _collapse.value < 1.0) {
      _event(() {
        _stripBrowse = _StripBrowse.none;
      });
    }
  }

  /// Steps by [stepUnit]: a year moves the month picker alone; a week
  /// selects the day a week from the selected one; and a month moves the
  /// card alone.
  void step(int direction) {
    switch (stepUnit) {
      case CalendarStepUnit.year:
        _event(() {
          _pickerYear += direction;
        });
      case CalendarStepUnit.week:
        _host.selectCardDay(
          CalendarDates.addDays(
            _host.cardSelectedDay,
            DateTime.daysPerWeek * direction,
          ),
        );
      case CalendarStepUnit.month:
      case CalendarStepUnit.day:
        browseMonth(CalendarDates.addMonths(month, direction));
    }
  }

  /// Opens the month picker on the selected day's year.
  void openPicker() {
    _event(() {
      _picksMonth = true;
      _pickerYear = _host.cardSelectedDay.year;
    });
    _pickerShown.animateTo(1.0, curve: _curve);
  }

  /// Closes the month picker.
  void closePicker() {
    _event(() {
      _picksMonth = false;
    });
    _pickerShown.animateTo(0.0, curve: _curve);
  }

  /// Selects the day of [month] a month step from the selected day would.
  /// The month picker stays open, filling [month].
  void pickMonth(DateTime month) {
    final day = _host.cardSelectedDay;
    final months = (month.year - day.year) * 12 + month.month - day.month;
    _host.selectCardDay(
      CalendarDates.shownDayNear(
        CalendarDates.addMonths(day, months),
        _host.cardWeekdays,
      ),
    );
  }

  /// Shows [year] in the month picker.
  void browseYear(int year) {
    _event(() {
      _pickerYear = year;
    });
  }

  /// Folds the card where [folded], or unfolds it, from however far it
  /// has folded, a drag on the pull tab having moved it. Unfolding closes
  /// the month picker and ends a strip browse, and leaves a browse the
  /// month the card shows, which a later fold opens the strip on a week of.
  void settle(bool folded) {
    if (folded != _folded || (!folded && _picksMonth)) {
      _event(() {
        _folded = folded;
        if (!folded) {
          _picksMonth = false;
          _stripBrowse = _StripBrowse.none;
        }
      });
    }
    _collapse.animateTo(_folded ? 1.0 : 0.0, curve: _curve);
  }

  /// Unfolds the card where it is folded.
  void unfold() {
    if (_folded) {
      settle(false);
    }
  }

  /// Leaves the browse, so the card shows the selected day.
  void forgetBrowse() {
    _browsedDay = null;
  }

  /// Leaves the browse and brings the week strip back to the selected
  /// day.
  void recall() {
    _browsedDay = null;
    _stripRecalls++;
  }

  /// Closes the month picker without its motion, which [followPicker]
  /// starts.
  void hidePicker() {
    _picksMonth = false;
  }

  /// Takes the browsed day anew through [CalendarCardHost.cardDayIn], as
  /// the host's clock has changed.
  void retakeBrowse() {
    final browsed = _browsedDay;
    if (browsed != null) {
      _browsedDay = _host.cardDayIn(browsed);
    }
  }

  /// Ends a strip browse, as new weekdays build a new strip.
  void endStripBrowse() {
    _stripBrowse = _StripBrowse.none;
  }

  /// Runs the picker's motion toward [picksMonth].
  void followPicker() {
    _pickerShown.animateTo(_picksMonth ? 1.0 : 0.0, curve: _curve);
  }

  @override
  void dispose() {
    _collapse.removeListener(_handleFold);
    _collapse.dispose();
    _pickerShown.dispose();
    super.dispose();
  }
}
