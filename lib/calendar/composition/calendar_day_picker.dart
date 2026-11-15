/// An inline picker of a day: the calendar card of Agenda and Day on its
/// own.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import '../views/month_picker.dart';
import 'calendar_card.dart';
import 'calendar_card_controller.dart';
import 'calendar_header.dart';
import 'calendar_theme_extension.dart';

/// An inline picker of a day: the calendar card of a `CalendarView`'s
/// Agenda and Day, drawn in the theme a `CalendarView` would resolve there,
/// with its words from [CalendarLocalizations]. It opens folded into its
/// week row on the week of [value], showing all seven weekdays from the
/// weekday column [firstColumn] (0 for Monday to 6 for Sunday), [value]
/// selected and [today] ringed; the pull tab and a drag down the week row
/// unfold it into the month, and the pull tab folds it back. Its header
/// names the month it shows, whose tap opens the month picker, between
/// chevrons that step a week while folded, a month while unfolded and a
/// year in the month picker. A tap on a day reports it through [onChanged]
/// as the start of its date on the clock of [store]'s zone; the picker
/// selects nothing itself and shows a new [value] once given. Its strips
/// scroll as Agenda's: a swipe of the week row comes to rest on the whole
/// day nearest to where a fling would carry it, a swipe of the month on the
/// nearest whole month, and neither selects anything. By default the
/// chevrons and a month pick only move the card, a month pick closing the
/// month picker; with [headerSelects], a chevron step while folded reports
/// the day a week from [value], and a month pick the day of that month a
/// month step from [value] reaches, the month picker staying open, as
/// `CalendarView`'s Agenda does, and where the picker refuses that day the
/// card moves instead. A day before [firstDay] or after [lastDay], compared
/// by date, or a day [isEnabled] refuses, draws disabled, at the theme's
/// [CalendarThemeData.disabledOpacity], and takes no tap; an arrow key onto
/// it selects nothing. The chevrons, the strips and the month picker browse
/// past [firstDay] and [lastDay]. A [value] the picker refuses still draws
/// selected. With [store], a day with entries carries a badge for each kind
/// [dayBadges] gives them, or the primary dot without [dayBadges], once the
/// store has read the day; the picker asks the store to read the grid of
/// the month it opens on after its first frame. Without [store] no day
/// carries a badge. With a null [onChanged] the picker reports nothing and
/// its days take no tap. A null [today] rings the date the device's clock
/// reads on [store]'s zone when the picker builds, so a picker open across
/// midnight rings the new date at its next build; a host with a clock of
/// its own gives [today]. Opening moves no focus into the picker; the
/// unfolded month takes the arrow keys once a tap has given it focus, and
/// the week row takes none.
class CalendarDayPicker<T> extends StatefulWidget {
  /// Creates a day picker of [value].
  ///
  /// Throws an [ArgumentError], in every build, naming `firstColumn` for a
  /// [firstColumn] outside 0 to 6.
  CalendarDayPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.store,
    this.today,
    this.firstDay,
    this.lastDay,
    this.isEnabled,
    this.firstColumn = 0,
    this.headerSelects = false,
    this.dayBadges,
  }) {
    if (firstColumn < 0 || firstColumn >= DateTime.daysPerWeek) {
      throw ArgumentError.value(
        firstColumn,
        "firstColumn",
        "is outside 0 to 6",
      );
    }
  }

  /// The selected day, which the picker shows selected and opens on.
  final DateTime value;

  /// Reports a day picked, as the start of its date on the clock of
  /// [store]'s zone; null makes the picker take no pick.
  final ValueChanged<DateTime>? onChanged;

  /// The store whose entries badge the days; null for no badges.
  final CalendarStore<T>? store;

  /// The day the picker rings as today; null for the date the device's
  /// clock reads on [store]'s zone as the picker builds.
  final DateTime? today;

  /// The first day the picker takes, compared by date; null for no first
  /// day. A day before it draws disabled and takes no tap.
  final DateTime? firstDay;

  /// The last day the picker takes, compared by date; null for no last
  /// day. A day after it draws disabled and takes no tap. Where it lies
  /// before [firstDay], the picker takes no day.
  final DateTime? lastDay;

  /// Whether the picker takes `day`, a day from [firstDay] to [lastDay],
  /// given as the start of its date on the clock of [store]'s zone; null
  /// takes every such day. A day it refuses draws disabled and takes no
  /// tap. Asked of a day as the day's cell first builds, or as a step or a
  /// pick under [headerSelects] would select it, at most once for each
  /// [isEnabled], compared by `==`, and date of [value], and again after a
  /// hot reload, and never of a day outside [firstDay] and [lastDay]; a
  /// predicate whose answers change is given as a function not `==` to the
  /// last.
  final bool Function(DateTime day)? isEnabled;

  /// The weekday column a week starts on, 0 for Monday to 6 for Sunday.
  final int firstColumn;

  /// Whether a chevron step while the card is folded and a pick in the
  /// month picker select a day, as `CalendarView`'s Agenda does: the step
  /// the day a week from [value], the pick the day of that month a month
  /// step from [value] reaches, each reported through [onChanged] where the
  /// picker takes it, and moving the card where it does not. False, the
  /// default, leaves both to move the card only.
  final bool headerSelects;

  /// The kinds of entry the days' badges mark; null for one primary dot on
  /// a day with entries.
  final CalendarDayBadges<T>? dayBadges;

  @override
  State<CalendarDayPicker<T>> createState() {
    return _CalendarDayPickerState<T>();
  }
}

class _CalendarDayPickerState<T> extends State<CalendarDayPicker<T>>
    with TickerProviderStateMixin
    implements CalendarCardHost {
  /// All seven weekdays, in weeks from [CalendarDayPicker.firstColumn].
  late CalendarWeekdaySet _weekdays;

  /// The store the card reads where [CalendarDayPicker.store] is null: an
  /// empty one, kept until [dispose], as strips that still listen to it
  /// take a new store only in their own update.
  MemoryCalendarStore<T>? _ownStore;

  late final CalendarCardController _card;

  /// Resolves the theme the card draws with, as a `CalendarView` does.
  final CalendarThemeResolver _themes = CalendarThemeResolver();

  /// The key of the card, under the optional [Material] and
  /// [CalendarTheme], so a resolve that adds or drops one keeps its state.
  final GlobalKey _contentKey = GlobalKey();

  /// [CalendarDayPicker.firstDay] and [CalendarDayPicker.lastDay] as plain
  /// days, the local midnights of their dates, as the strips' cells are.
  DateTime? _first;
  DateTime? _last;

  /// [CalendarDayPicker.isEnabled]'s answers, keyed by plain day, for the
  /// predicate and the date of [CalendarDayPicker.value] they were asked
  /// under.
  Map<DateTime, bool> _answers = <DateTime, bool>{};

  CalendarStore<T> get _store {
    return widget.store ?? _ownStore!;
  }

  /// The local midnight of [day]'s date; null for null.
  static DateTime? _plainOf(DateTime? day) {
    if (day == null) {
      return null;
    }
    return CalendarDates.dateOfDayNumber(CalendarDates.dayNumber(day));
  }

  static bool _sameDate(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return a == b;
    }
    return CalendarDates.dayNumber(a) == CalendarDates.dayNumber(b);
  }

  @override
  void initState() {
    super.initState();
    _weekdays = CalendarWeekdaySet.all.startingOn(widget.firstColumn);
    if (widget.store == null) {
      _ownStore = MemoryCalendarStore<T>();
    }
    _card = CalendarCardController(
      vsync: this,
      host: this,
      headerSelects: widget.headerSelects,
      folded: true,
    )..addListener(_handleCard);
    _first = _plainOf(widget.firstDay);
    _last = _plainOf(widget.lastDay);
    _readShownMonthAfterFrame();
  }

  /// Asks the store to read the days of the shown month's grid, after the
  /// frame, as a read can notify the cells' listeners, which must not
  /// rebuild mid-build. Neither strip reads when its store changes, so a
  /// store given in a later build reads here.
  void _readShownMonthAfterFrame() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final month = _card.month;
      final grid = CalendarMonthGrid(
        month.year,
        month.month,
        weekdays: _weekdays,
      );
      _store.prefetch(grid.firstDay, grid.lastDay);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTheme();
  }

  @override
  void reassemble() {
    _themes.reset();
    // A reload can change what the predicate answers while it stays `==`
    // to itself.
    _answers = <DateTime, bool>{};
    super.reassemble();
    _resolveTheme();
  }

  @override
  void didUpdateWidget(CalendarDayPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final valueMoved = !_sameDate(widget.value, oldWidget.value);
    if (valueMoved) {
      _card.forgetBrowse();
    }
    if (widget.firstColumn != oldWidget.firstColumn) {
      _weekdays = CalendarWeekdaySet.all.startingOn(widget.firstColumn);
      _card.endStripBrowse();
    }
    if (widget.headerSelects != oldWidget.headerSelects) {
      _card.headerSelects = widget.headerSelects;
    }
    if (widget.store == null && _ownStore == null) {
      _ownStore = MemoryCalendarStore<T>();
    }
    if (!identical(widget.store, oldWidget.store)) {
      _readShownMonthAfterFrame();
    }
    if (!_sameDate(widget.firstDay, oldWidget.firstDay)) {
      _first = _plainOf(widget.firstDay);
    }
    if (!_sameDate(widget.lastDay, oldWidget.lastDay)) {
      _last = _plainOf(widget.lastDay);
    }
    if (valueMoved || widget.isEnabled != oldWidget.isEnabled) {
      _answers = <DateTime, bool>{};
    }
  }

  @override
  void dispose() {
    _card.removeListener(_handleCard);
    _card.dispose();
    _ownStore?.dispose();
    super.dispose();
  }

  /// Resolves the theme the card draws with, and whether a [Material] goes
  /// above it, and gives the card the theme's motion.
  void _resolveTheme() {
    _themes.resolve(context);
    final theme = _themes.theme;
    _card.setMotion(theme.motionDuration, theme.motionCurve);
  }

  void _handleCard() {
    setState(() {});
  }

  @override
  DateTime get cardSelectedDay {
    return widget.value;
  }

  @override
  DateTime get cardToday {
    return widget.today ??
        CalendarDates.inZone(DateTime.now(), zone: _store.zone);
  }

  @override
  CalendarWeekdaySet get cardWeekdays {
    return _weekdays;
  }

  @override
  DateTime cardDayIn(DateTime day) {
    return CalendarDates.dateOfDayNumber(
      CalendarDates.dayNumber(day),
      zone: _store.zone,
    );
  }

  @override
  bool selectCardDay(DateTime day) {
    final onChanged = widget.onChanged;
    if (onChanged == null || !_isDayEnabled(_plainOf(day)!)) {
      return false;
    }
    if (_sameDate(day, widget.value)) {
      return true;
    }
    onChanged(cardDayIn(day));
    return true;
  }

  @override
  void runCardEvent(VoidCallback change) {
    change();
  }

  /// A tap on [day] in either strip.
  void _selectDay(DateTime day) {
    selectCardDay(day);
  }

  /// Whether the picker takes [day], a plain day: not before the first day
  /// or after the last, compared as plain days, which order as their dates;
  /// and then [CalendarDayPicker.isEnabled]'s answer, asked once for each
  /// day under one predicate and value date.
  bool _isDayEnabled(DateTime day) {
    final first = _first;
    if (first != null && day.isBefore(first)) {
      return false;
    }
    final last = _last;
    if (last != null && day.isAfter(last)) {
      return false;
    }
    final isEnabled = widget.isEnabled;
    if (isEnabled == null) {
      return true;
    }
    final kept = _answers[day];
    if (kept != null) {
      return kept;
    }
    return _answers[day] = isEnabled(cardDayIn(day));
  }

  void _stepBack() {
    _card.step(-1);
  }

  void _stepOn() {
    _card.step(1);
  }

  /// The header lists Agenda alone, so it shows no view button and this
  /// is never called.
  void _selectView(CalendarViewKind view) {}

  CalendarHeaderDetails _headerDetails() {
    return CalendarHeaderDetails(
      view: CalendarViewKind.agenda,
      views: const <CalendarViewKind>[CalendarViewKind.agenda],
      day: _card.browsedDay ?? widget.value,
      pickerYear: _card.picksMonth ? _card.pickerYear : null,
      stepUnit: _card.stepUnit,
      onPrevious: _stepBack,
      onNext: _stepOn,
      onSelectView: _selectView,
      onOpenPicker: _card.openPicker,
      onClosePicker: _card.closePicker,
    );
  }

  /// The month picker, on the card's year, filling the month of
  /// [CalendarDayPicker.value] and ringing today's.
  Widget _buildMonthPicker() {
    final today = cardToday;
    final value = widget.value;
    return MonthPicker(
      key: const ValueKey<String>("month-picker"),
      year: _card.pickerYear,
      selectedMonth: DateTime(value.year, value.month),
      currentMonth: DateTime(today.year, today.month),
      onSelectMonth: _card.pickMonth,
      onBrowse: _card.browseYear,
    );
  }

  @override
  Widget build(BuildContext context) {
    final asks =
        widget.firstDay != null ||
        widget.lastDay != null ||
        widget.isEnabled != null;
    Widget content = KeyedSubtree(
      key: _contentKey,
      child: CalendarCard<T>(
        controller: _card,
        store: _store,
        month: _card.month,
        selectedDay: widget.value,
        today: cardToday,
        weekdays: _weekdays,
        header: CalendarHeader(details: _headerDetails()),
        buildPicker: _buildMonthPicker,
        onSelectDay: widget.onChanged == null ? null : _selectDay,
        dayBadges: widget.dayBadges,
        isDayEnabled: asks ? _isDayEnabled : null,
      ),
    );
    final inserted = _themes.inserted;
    if (inserted != null) {
      content = CalendarTheme(data: inserted, child: content);
    }
    if (_themes.hasTheme && !_themes.hasMaterial) {
      content = Material(type: MaterialType.transparency, child: content);
    }
    return content;
  }
}
