part of 'calendar_view.dart';

/// What a controller's view, selected day and visible range read.
typedef _Observed = ({CalendarViewKind? view, DateTime? day, _Range? range});

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
/// a menu pick, a tap, a chevron step or a scroll that selects a day,
/// notifies the same way, within the event. A change the calendar makes
/// as it is built, given this controller, new weekdays, new views or a new
/// store, or left, applies its values at once and notifies once after
/// that frame, never inside a build. A set on an unbound controller is
/// kept until a calendar binds it.
base class CalendarController extends ChangeNotifier {
  /// A controller of [view] and [selectedDay], each null for the
  /// calendar's own choice when it binds it, the first view it lists and
  /// today's nearest shown day, and of the least sizes, logical pixels of
  /// layout, positive and finite.
  CalendarController({
    CalendarViewKind? view,
    DateTime? selectedDay,
    double minDayWidth = minDayWidthLow,
    double minSlotHeight = defaultMinSlotHeight,
  }) : assert(
         _isSize(minDayWidth),
         "A CalendarController's minDayWidth must be positive and finite.",
       ),
       assert(
         _isSize(minSlotHeight),
         "A CalendarController's minSlotHeight must be positive and finite.",
       ),
       _view = view,
       _selectedDay = selectedDay == null ? null : dateOnly(selectedDay),
       _minDayWidth = minDayWidth,
       _minSlotHeight = minSlotHeight;

  /// A controller holding what [other] holds: its view, selected day,
  /// sizes and range.
  CalendarController._copyOf(CalendarController other)
    : _view = other._view,
      _selectedDay = other._selectedDay,
      _minDayWidth = other._minDayWidth,
      _minSlotHeight = other._minSlotHeight,
      _visibleRange = other._visibleRange;

  static bool _isSize(double value) {
    return value > 0.0 && value < double.infinity;
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

  /// The selected day, a local midnight on a weekday the calendar shows.
  /// Throws a [StateError] for a controller given no day and bound to no
  /// calendar; a bound one always has one.
  ///
  /// Set on a bound controller, the calendar selects the shown day nearest
  /// [value]'s day ([shownDayNear]); on an unbound one, [value]'s day is
  /// kept until a calendar binds it.
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
    final day = dateOnly(value);
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
  /// lesser of [minSlotHeight] and [defaultMinSlotHeight].
  double get monthWeekScale {
    return math.max(1.0, _minSlotHeight / defaultMinSlotHeight);
  }

  set monthWeekScale(double value) {
    setZoom(monthWeekScale: value);
  }

  /// Sets the sizes given, [minSlotHeight] or [monthWeekScale] but not
  /// both, each as its setter does, and notifies once where any changed.
  void setZoom({
    double? minDayWidth,
    double? minSlotHeight,
    double? monthWeekScale,
  }) {
    assert(
      minSlotHeight == null || monthWeekScale == null,
      "setZoom sets minSlotHeight or monthWeekScale, not both.",
    );
    assert(
      minDayWidth == null || _isSize(minDayWidth),
      "A CalendarController's minDayWidth must be positive and finite.",
    );
    assert(
      minSlotHeight == null || _isSize(minSlotHeight),
      "A CalendarController's minSlotHeight must be positive and finite.",
    );
    assert(
      monthWeekScale == null ||
          (monthWeekScale >= 1.0 && monthWeekScale < double.infinity),
      "A CalendarController's monthWeekScale must be finite and at least 1.",
    );
    var slot = minSlotHeight ?? _minSlotHeight;
    if (monthWeekScale != null) {
      slot = monthWeekScale > 1.0
          ? defaultMinSlotHeight * monthWeekScale
          : math.min(_minSlotHeight, defaultMinSlotHeight);
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
    return (view: _view, day: _selectedDay, range: visibleRange);
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
