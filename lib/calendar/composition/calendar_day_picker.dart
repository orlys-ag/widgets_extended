/// An inline picker of a day: the calendar card of Agenda and Day on its
/// own.
library;

import 'package:material_ui/material_ui.dart';
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

/// An inline picker of a day: the calendar card of a `CalendarView`'s Agenda
/// and Day, drawn in the theme a `CalendarView` would resolve there, with
/// its words from [CalendarLocalizations]. It opens on [initialView], by
/// default folded into its week row on the week of [value], showing all
/// seven weekdays from the weekday column [firstColumn] (0 for Monday to 6
/// for Sunday), [value] selected and [today] ringed; the pull tab and a drag
/// down the week row unfold it into the month, and the pull tab folds it
/// back. Its header names the month it shows, whose tap opens the month
/// picker, between chevrons that step a week while folded, a month while
/// unfolded and a year in the month picker. A fold, an unfold, and the month
/// picker's opening and closing report the view they turn to through
/// [onViewChanged]. A tap on a day, the selected day included, reports it
/// through [onChanged] as the start of its date on the clock of [store]'s
/// zone; the picker selects nothing itself and shows a new [value] once
/// given. Its strips scroll as
/// Agenda's: a swipe of the week row comes to rest on the whole day nearest
/// to where a fling would carry it, a swipe of the month on the nearest
/// whole month, and neither selects anything. By default the chevrons and a
/// month pick only move the card, a month pick closing the month picker;
/// with [headerSelects], a chevron step while folded reports the day a week
/// from [value], and a month pick the day of that month a month step from
/// [value] reaches, the month picker staying open, as `CalendarView`'s
/// Agenda does, a pick of [value]'s own month reporting nothing; and where
/// the picker refuses that day the card moves instead. A day before
/// [firstDay] or after [lastDay], compared by date, or
/// a day [isEnabled] refuses, draws disabled, at the theme's
/// [CalendarThemeData.disabledOpacity], and takes no tap; an arrow key onto
/// it selects nothing. The chevrons, the strips and the month picker browse
/// past [firstDay] and [lastDay], unless [browsesBeforeFirstDay] is false. A
/// [value] the picker refuses still draws selected. With [store], a day with
/// entries carries a badge for each kind [dayBadges] gives them, or the
/// primary dot without [dayBadges], once the store has read the day; the
/// picker asks the store to read the grid of the month it shows after its
/// first frame, and after a build that gives it another store. Without
/// [store] no day carries a badge. With a null [onChanged] the picker
/// reports nothing and its days take no tap. A null [today] rings the date
/// the device's clock reads on [store]'s zone when the picker builds, so a
/// picker open across midnight rings the new date at its next build; a host
/// with a clock of its own gives [today]. Opening moves no focus into the
/// picker; the unfolded month takes the arrow keys once a tap has given it
/// focus, and the week row takes none. The picker pads its sides by 8
/// logical pixels and centres each day's circle in its column; with
/// [daysToEdges] the circles of the first and last columns reach its sides
/// instead, so its days line up with what lies above and below it. Asked
/// its intrinsic height at the width it lays out at, as an
/// `IntrinsicHeight` asks, the picker answers the height it lays out at:
/// folded, unfolded or with its month picker open, and as it moves between
/// them.
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
    this.daysToEdges = false,
    this.browsesBeforeFirstDay = true,
    this.initialView = const CalendarDayPickerView(),
    this.onViewChanged,
    this.headerTrailing,
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
  /// picker takes it, but for [value] itself, which a pick of its own month
  /// reaches and which reports nothing, and moving the card where the
  /// picker does not take it. False, the default, leaves both to move the
  /// card only.
  final bool headerSelects;

  /// The kinds of entry the days' badges mark; null for one primary dot on
  /// a day with entries.
  final CalendarDayBadges<T>? dayBadges;

  /// Whether the circles of the first and last columns reach the picker's
  /// sides: the picker pads no side, and its weekday names and days lie in
  /// columns spread wider than equal shares of its width, by up to half a
  /// column less half a circle on each side. An edge column's badges then
  /// draw up to 5 logical pixels past the picker's side, which a host that
  /// clips the picker leaves room for. False, the default, pads each side
  /// by 8 logical pixels and centres each circle in its column.
  final bool daysToEdges;

  /// Whether the picker browses to weeks and months before [firstDay]'s.
  /// True, the default, lets the strips, the chevrons and the month picker
  /// browse past it. False stops them at the week, the month and the year
  /// of [firstDay], or of [value] where that is earlier, compared by date:
  /// the week row slides back no further than that week and the month no
  /// further than that month; the previous chevron draws disabled there
  /// ([CalendarHeaderDetails.canStepBack]), as it does in the month picker
  /// at that year; the month picker draws the months before that month
  /// disabled, at the theme's [CalendarThemeData.disabledOpacity], and
  /// takes no tap on them; and the month folds into no week before that
  /// week. A build that moves that day brings the card back to [value].
  /// With no [firstDay] it has no effect.
  final bool browsesBeforeFirstDay;

  /// The view the picker opens on, with no motion: by default its week
  /// row, the month picker closed. The month picker opens on the year of
  /// [value], and closing it shows the week row or the month as the view's
  /// [CalendarDayPickerView.folded] says. A later build's view has no
  /// effect.
  final CalendarDayPickerView initialView;

  /// Reports the view the picker turns to as a fold, an unfold, or the
  /// month picker opening or closing starts, whether a tap, a drag or a
  /// month pick turns it; null reports nothing. Opening reports nothing,
  /// and neither does a chevron, a swipe or a pick of a day, which leave
  /// the view as it is.
  final ValueChanged<CalendarDayPickerView>? onViewChanged;

  /// A widget at the end of the header's row, after its next chevron and
  /// centred on the row, at its own width, at most the row's, or, given
  /// as a [Flexible] or an [Expanded], sharing the row with the chevrons
  /// and the title by its flex, theirs being 1, as in a [Row]; whether
  /// the picker shows its week row, its month or its month picker; null
  /// for none. A host that puts the picker together with controls of its own,
  /// as [CalendarDateTimePicker] does with its Time toggle, gives them
  /// here.
  final Widget? headerTrailing;

  @override
  State<CalendarDayPicker<T>> createState() {
    return _CalendarDayPickerState<T>();
  }
}

/// The view a [CalendarDayPicker] shows: its week row or its month, and
/// whether its month picker shows over it, which a host keeps to open
/// another picker on ([CalendarDayPicker.initialView]). Two are equal where
/// their fields are.
final class CalendarDayPickerView {
  /// Creates a view, by default the week row, the month picker closed.
  const CalendarDayPickerView({this.folded = true, this.picksMonth = false});

  /// Whether the picker is folded into its week row rather than showing
  /// its month, under the month picker where [picksMonth].
  final bool folded;

  /// Whether the month picker shows.
  final bool picksMonth;

  @override
  bool operator ==(Object other) {
    return other is CalendarDayPickerView &&
        other.folded == folded &&
        other.picksMonth == picksMonth;
  }

  @override
  int get hashCode {
    return Object.hash(folded, picksMonth);
  }

  @override
  String toString() {
    return "CalendarDayPickerView(folded: $folded, picksMonth: $picksMonth)";
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

  /// The view [_card] shows, as [CalendarDayPicker.onViewChanged] last
  /// reported it or [CalendarDayPicker.initialView] gave it.
  late CalendarDayPickerView _view;

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

  /// The day before whose week and month the picker browses nothing, as a
  /// plain day ([_browseFromOf]).
  DateTime? get _browseFrom {
    return _browseFromOf(widget);
  }

  /// The day before whose week and month [picker] browses nothing, as a
  /// plain day: the date of its [CalendarDayPicker.firstDay], or of its
  /// [CalendarDayPicker.value] where that is earlier; null where it
  /// browses before its first day or has none.
  static DateTime? _browseFromOf(CalendarDayPicker<Object?> picker) {
    final first = _plainOf(picker.firstDay);
    if (picker.browsesBeforeFirstDay || first == null) {
      return null;
    }
    final value = _plainOf(picker.value)!;
    return value.isBefore(first) ? value : first;
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
      folded: widget.initialView.folded,
      picksMonth: widget.initialView.picksMonth,
    )..addListener(_handleCard);
    _view = widget.initialView;
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
    // A browse can lie before a new limit, where neither strip goes.
    final from = _browseFrom;
    if (from != null && !_sameDate(from, _browseFromOf(oldWidget))) {
      _card.recall();
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

  /// Rebuilds the card, and reports a view the card has turned to.
  void _handleCard() {
    setState(() {});
    final view = CalendarDayPickerView(
      folded: _card.folded,
      picksMonth: _card.picksMonth,
    );
    if (view != _view) {
      _view = view;
      widget.onViewChanged?.call(view);
    }
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
  DateTime? get cardBrowseFrom {
    return _browseFrom;
  }

  @override
  DateTime cardDayIn(DateTime day) {
    return CalendarDates.dateOfDayNumber(
      CalendarDates.dayNumber(day),
      zone: _store.zone,
    );
  }

  /// A chevron step or a month pick under [CalendarDayPicker.headerSelects]:
  /// reports [day] where the picker takes it and it is not
  /// [CalendarDayPicker.value]'s date, which it leaves as it is.
  @override
  bool selectCardDay(DateTime day) {
    if (!_takes(day)) {
      return false;
    }
    if (!_sameDate(day, widget.value)) {
      widget.onChanged!(cardDayIn(day));
    }
    return true;
  }

  @override
  void runCardEvent(VoidCallback change) {
    change();
  }

  /// A tap on [day] in either strip, or an arrow key's move onto it in the
  /// month: reports it where the picker takes it, the selected day
  /// included.
  void _selectDay(DateTime day) {
    if (_takes(day)) {
      widget.onChanged!(cardDayIn(day));
    }
  }

  /// Whether the picker takes a pick of [day]: it reports picks and does
  /// not refuse the day.
  bool _takes(DateTime day) {
    return widget.onChanged != null && _isDayEnabled(_plainOf(day)!);
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
      canStepBack: _card.canStepBack,
      onSelectView: _selectView,
      onOpenPicker: _card.openPicker,
      onClosePicker: _card.closePicker,
    );
  }

  /// The month picker, on the card's year, filling the month of
  /// [CalendarDayPicker.value] and ringing today's, and taking no month
  /// before [_browseFrom]'s.
  Widget _buildMonthPicker() {
    final today = cardToday;
    final value = widget.value;
    final from = _browseFrom;
    return MonthPicker(
      key: const ValueKey<String>("month-picker"),
      year: _card.pickerYear,
      selectedMonth: DateTime(value.year, value.month),
      currentMonth: DateTime(today.year, today.month),
      onSelectMonth: _card.pickMonth,
      onBrowse: _card.browseYear,
      firstMonth: from == null ? null : DateTime(from.year, from.month),
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
        header: CalendarHeader(
          details: _headerDetails(),
          trailing: widget.headerTrailing,
        ),
        buildPicker: _buildMonthPicker,
        onSelectDay: widget.onChanged == null ? null : _selectDay,
        dayBadges: widget.dayBadges,
        isDayEnabled: asks ? _isDayEnabled : null,
        daysToEdges: widget.daysToEdges,
        browseFrom: _browseFrom,
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
