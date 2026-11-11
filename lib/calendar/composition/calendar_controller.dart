part of 'calendar_view.dart';

/// What a controller's view, selected day, visible range and
/// [CalendarController.showsSelectedDay] read.
typedef _Observed = ({
  CalendarViewKind? view,
  DateTime? day,
  _Range? range,
  bool shows,
});

/// The view, the selected day, the visible range and the zoom sizes of a
/// [CalendarView], which its host sets and listens to.
///
/// A controller serves one [CalendarView] at a time, the one it is bound
/// to: the one it is given to, from the frame that builds it until it is
/// given another controller or leaves the tree. A second [CalendarView]
/// given a controller another one holds takes it, and a debug build
/// reports the first, which goes on with a copy.
///
/// A set on a bound controller goes through its calendar, which applies
/// it as the header would and notifies once where a value changed, so
/// each listener reads what the calendar shows. An event in the calendar,
/// a menu pick, a tap, a chevron step or a scroll that selects a day, or
/// a browse, a fold or the month picker that changes [showsSelectedDay],
/// notifies the same way, within the event. A change the calendar makes
/// as it is built, given this controller, new weekdays, new views or a new
/// store, or left, applies its values at once and notifies once after
/// that frame, never inside a build. A set on an unbound controller is
/// kept until a calendar binds it.
base class CalendarController extends ChangeNotifier {
  /// The least [minDayWidth] a pinch zooms to, and its default.
  static const double minDayWidthLow = pinch.minDayWidthLow;

  /// The most [minDayWidth] a pinch zooms to.
  static const double minDayWidthHigh = pinch.minDayWidthHigh;

  /// The least [minSlotHeight] a pinch zooms to.
  static const double minSlotHeightLow = pinch.minSlotHeightLow;

  /// The most [minSlotHeight] a pinch zooms to.
  static const double minSlotHeightHigh = pinch.minSlotHeightHigh;

  /// The default [minSlotHeight], at and under which [monthWeekScale] is 1.
  static const double defaultMinSlotHeight = pinch.defaultMinSlotHeight;

  /// The most [monthWeekScale] a pinch zooms to: [minSlotHeightHigh] over
  /// [defaultMinSlotHeight].
  static const double maxMonthWeekScale = pinch.maxMonthWeekScale;

  /// A controller of [view] and [selectedDay], each null for the
  /// calendar's own choice when it binds it, the first view it lists and
  /// today's nearest shown day, and of the least sizes, logical pixels of
  /// layout, positive and finite.
  ///
  /// Throws an [ArgumentError], in every build, naming `minDayWidth` or
  /// `minSlotHeight` for a size that is not positive and finite, NaN
  /// included.
  CalendarController({
    CalendarViewKind? view,
    DateTime? selectedDay,
    double minDayWidth = minDayWidthLow,
    double minSlotHeight = defaultMinSlotHeight,
  }) : _view = view,
       _selectedDay = selectedDay == null
           ? null
           : CalendarDates.dateOnly(selectedDay),
       _minDayWidth = minDayWidth,
       _minSlotHeight = minSlotHeight {
    _checkSize(minDayWidth, "minDayWidth");
    _checkSize(minSlotHeight, "minSlotHeight");
  }

  /// A controller holding what [other] holds: its view, selected day,
  /// sizes and range.
  CalendarController._copyOf(CalendarController other)
    : _view = other._view,
      _selectedDay = other._selectedDay,
      _minDayWidth = other._minDayWidth,
      _minSlotHeight = other._minSlotHeight,
      _visibleRange = other._visibleRange;

  /// Whether [value] is positive and finite; a NaN is not.
  static bool _isSize(double value) {
    return value > 0.0 && value < double.infinity;
  }

  /// Throws an [ArgumentError] named [name] for a [value] that is not a
  /// size ([_isSize]).
  static void _checkSize(double value, String name) {
    if (!_isSize(value)) {
      throw ArgumentError.value(value, name, "is not positive and finite");
    }
  }

  CalendarViewKind? _view;
  DateTime? _selectedDay;
  double _minDayWidth;
  double _minSlotHeight;
  _Range? _visibleRange;

  /// The calendar this controller is bound to, or null.
  _CalendarViewState<Object?>? _binding;

  /// What the getters read before the first change a calendar's lifecycle
  /// made to this controller this frame; null while none has.
  _Observed? _beforeFrame;

  bool _disposed = false;

  /// The view the calendar shows. Throws a [StateError] for a controller
  /// given no view and bound to no calendar; a bound one always has one.
  ///
  /// Set on a bound controller, the calendar shows [value], which its
  /// views must list: a debug build asserts it, and a release build shows
  /// the first view listed in its place.
  CalendarViewKind get view {
    final view = _view;
    if (view == null) {
      throw StateError(
        "This CalendarController was given no view and is bound to no "
        "CalendarView, which gives it one.",
      );
    }
    return view;
  }

  set view(CalendarViewKind value) {
    final binding = _binding;
    if (binding != null) {
      if (value != _view) {
        binding._selectView(value);
      }
      return;
    }
    if (value == _view) {
      return;
    }
    _view = value;
    notifyListeners();
  }

  /// The selected day, on a weekday the calendar shows. On a controller a
  /// calendar binds, it is the start of a day on the clock of that
  /// calendar's store's zone ([CalendarStore.zone]): a `TZDateTime` of the
  /// zone typed [DateTime], or a local midnight where the store has none.
  /// On an unbound one, it is the start of the given day's date on that
  /// day's own clock ([CalendarDates.dateOnly]). Throws a [StateError] for
  /// a controller given no day and bound to no calendar; a bound one always
  /// has one.
  ///
  /// Set on a bound controller, the calendar selects the shown day nearest
  /// [value]'s day; on an unbound one, [value]'s day is kept until a
  /// calendar binds it.
  DateTime get selectedDay {
    final day = _selectedDay;
    if (day == null) {
      throw StateError(
        "This CalendarController was given no selected day and is bound to "
        "no CalendarView, which gives it one.",
      );
    }
    return day;
  }

  set selectedDay(DateTime value) {
    final binding = _binding;
    if (binding != null) {
      binding._selectDay(value);
      return;
    }
    final day = CalendarDates.dateOnly(value);
    if (day == _selectedDay) {
      return;
    }
    _selectedDay = day;
    notifyListeners();
  }

  /// The least width of a day in Week, Day and Month, in logical pixels,
  /// positive and finite; the days stretch past it to fill the calendar.
  /// A pinch across sets it within [minDayWidthLow] and [minDayWidthHigh],
  /// so the views move a value outside them into them at its first report.
  ///
  /// Set to a value that is not positive and finite, NaN included, it
  /// throws an [ArgumentError], in every build, naming `minDayWidth`, and
  /// changes nothing.
  double get minDayWidth {
    return _minDayWidth;
  }

  set minDayWidth(double value) {
    setZoom(minDayWidth: value);
  }

  /// The least height of one slot of Week's and Day's grids, in logical
  /// pixels, positive and finite; the slots stretch past it to fill the
  /// calendar. A pinch up and down sets it within [minSlotHeightLow] and
  /// [minSlotHeightHigh], so the views move a value outside them into
  /// them at its first report.
  ///
  /// Set to a value that is not positive and finite, NaN included, it
  /// throws an [ArgumentError], in every build, naming `minSlotHeight`, and
  /// changes nothing.
  double get minSlotHeight {
    return _minSlotHeight;
  }

  set minSlotHeight(double value) {
    setZoom(minSlotHeight: value);
  }

  /// How many times its share of Month's height a week rests at:
  /// [minSlotHeight] over [defaultMinSlotHeight], and never less than 1,
  /// so at the default slot height and under it the weeks fit the screen.
  ///
  /// Set to a finite scale of at least 1, it sets [minSlotHeight] to
  /// [defaultMinSlotHeight] times the scale above 1, and at 1 to the
  /// lesser of [minSlotHeight] and [defaultMinSlotHeight]. Set to a scale
  /// under 1 or not finite, NaN included, or to one whose slot height is
  /// not finite, it throws an [ArgumentError], in every build, naming
  /// `monthWeekScale`, and changes nothing.
  double get monthWeekScale {
    return math.max(1.0, _minSlotHeight / defaultMinSlotHeight);
  }

  set monthWeekScale(double value) {
    setZoom(monthWeekScale: value);
  }

  /// Sets the sizes given, [minSlotHeight] or [monthWeekScale] but not
  /// both, each as its setter does, and notifies once where any changed.
  ///
  /// Throws an [ArgumentError], in every build, before it writes a size,
  /// so a call that throws changes no size and notifies nothing: naming
  /// `monthWeekScale` where it is given with [minSlotHeight]; then
  /// `minDayWidth` or `minSlotHeight` for a size that is not positive and
  /// finite, NaN included; and `monthWeekScale` for a scale under 1 or not
  /// finite, or one whose slot height, [defaultMinSlotHeight] times it, is
  /// not finite.
  void setZoom({
    double? minDayWidth,
    double? minSlotHeight,
    double? monthWeekScale,
  }) {
    if (minSlotHeight != null && monthWeekScale != null) {
      throw ArgumentError.value(
        monthWeekScale,
        "monthWeekScale",
        "is given with minSlotHeight, and setZoom sets one of them",
      );
    }
    if (minDayWidth != null) {
      _checkSize(minDayWidth, "minDayWidth");
    }
    if (minSlotHeight != null) {
      _checkSize(minSlotHeight, "minSlotHeight");
    }
    var slot = minSlotHeight ?? _minSlotHeight;
    if (monthWeekScale != null) {
      if (!(monthWeekScale >= 1.0 && monthWeekScale < double.infinity)) {
        throw ArgumentError.value(
          monthWeekScale,
          "monthWeekScale",
          "is under 1 or not finite",
        );
      }
      slot = monthWeekScale > 1.0
          ? defaultMinSlotHeight * monthWeekScale
          : math.min(_minSlotHeight, defaultMinSlotHeight);
      // A finite scale can still overflow the product.
      if (!_isSize(slot)) {
        throw ArgumentError.value(
          monthWeekScale,
          "monthWeekScale",
          "gives a slot height that is not finite",
        );
      }
    }
    final day = minDayWidth ?? _minDayWidth;
    if (slot == _minSlotHeight && day == _minDayWidth) {
      return;
    }
    _minSlotHeight = slot;
    _minDayWidth = day;
    notifyListeners();
  }

  /// The range of days, both inclusive, the bound calendar last asked its
  /// store to show; null while the controller is bound to no calendar.
  ///
  /// In Agenda and Month the month grid's first to last day; in Week the
  /// seven days from the selected day's week's first; in Day the first to
  /// the last shown day of the selected day's week.
  ({DateTime first, DateTime last})? get visibleRange {
    return _binding == null ? null : _visibleRange;
  }

  /// Whether the bound calendar shows its selected day as [goTo] of that
  /// day leaves it. False while the month picker shows; while the
  /// calendar card of Agenda or Day, unfolded, shows a month other than
  /// the selected day's, which a slide or a chevron moved it to; and while
  /// the card's week strip, folded, shows a week's count of shown days
  /// without the selected day, a drag having moved it. True otherwise, and
  /// on a controller bound to no calendar.
  ///
  /// The strip's days are a week's count of shown days around the day a
  /// drag last brought to its middle, which are the days it shows at rest.
  /// The card opens a new strip, on a week of the month the card shows, at
  /// each fold, once a drag on its pull tab moves the fold, and for new
  /// weekdays; until a drag moves that strip, its days are the shown days
  /// of the week it opened on.
  bool get showsSelectedDay {
    return _binding?._showsSelectedDay ?? true;
  }

  /// Brings the calendar to [day]: on a bound controller, closes the month
  /// picker, then where the shown day nearest [day] is selected brings the
  /// calendar card or the week strip back to it from where a drag or a
  /// chevron moved it, and otherwise selects it; on an unbound one, sets
  /// [selectedDay].
  void goTo(DateTime day) {
    final binding = _binding;
    if (binding != null) {
      binding._goTo(day);
      return;
    }
    selectedDay = day;
  }

  /// Releases the controller. A [CalendarView] disposes the controller it
  /// made, never a host's.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  _Observed get _observed {
    return (
      view: _view,
      day: _selectedDay,
      range: visibleRange,
      shows: showsSelectedDay,
    );
  }

  /// Binds [state]. A state bound before switches to a copy of this
  /// controller, so it writes this controller no more.
  void _attach(_CalendarViewState<Object?> state) {
    final other = _binding;
    if (other != null && !identical(other, state)) {
      other._takeCopyOf(this);
    }
    _binding = state;
  }

  /// Unbinds [state], where it is the state bound.
  void _detach(_CalendarViewState<Object?> state) {
    if (identical(_binding, state)) {
      _binding = null;
    }
  }

  /// Notes, before a calendar's lifecycle writes this controller, what the
  /// getters read, and after the frame, which runs after the frame's build
  /// and finalize phases, runs the bound calendar's pending ask of the
  /// store first and then notifies once where they read otherwise. A
  /// controller disposed meanwhile notifies nothing.
  void _noteLifecycle() {
    if (_beforeFrame != null || _disposed) {
      return;
    }
    _beforeFrame = _observed;
    SchedulerBinding.instance.addPostFrameCallback(_notifyAfterFrame);
  }

  void _notifyAfterFrame(Duration timeStamp) {
    final before = _beforeFrame;
    _beforeFrame = null;
    if (_disposed || before == null) {
      return;
    }
    _binding?._askPendingRange();
    if (_observed != before) {
      notifyListeners();
    }
  }

  /// Notifies for an event; a notify after the frame then compares from
  /// what the event left.
  void _notifyEvent() {
    if (_beforeFrame != null) {
      _beforeFrame = _observed;
    }
    notifyListeners();
  }
}
