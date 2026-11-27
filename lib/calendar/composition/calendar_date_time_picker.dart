/// An inline picker of a day and a time of it: a [CalendarDayPicker] and a
/// [CalendarTimePicker] that take turns, with a control that switches
/// between them.
library;

import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import '../views/time_picker.dart';
import 'calendar_day_picker.dart';
import 'calendar_header.dart';
import 'calendar_theme_extension.dart';

/// The key of the label of the Date segment of the view control in the
/// header of the view a [CalendarDateTimePicker] shows.
const ValueKey<String> dateTimePickerDateSegmentKey = ValueKey<String>(
  "date-time-picker-date-segment",
);

/// The key of the label of the Time segment of the view control in the
/// header of the view a [CalendarDateTimePicker] shows.
const ValueKey<String> dateTimePickerTimeSegmentKey = ValueKey<String>(
  "date-time-picker-time-segment",
);

/// The key of a [CalendarDateTimePicker]'s time view: the card that holds
/// its header, which names the day, over its time picker.
const ValueKey<String> dateTimePickerTimeKey = ValueKey<String>(
  "date-time-picker-time",
);

/// An inline picker of a day and a time of it, put together of a
/// [CalendarDayPicker] and a [CalendarTimePicker], each as it is on its
/// own, which take turns: its date view is the day picker, and its time
/// view, on a card as the day picker's, a header row naming [day], as
/// [CalendarLocalizations.dayTitle] names it against [today], over the time
/// picker. At the end of each view's header row lies a view control of two
/// segments, labelled [CalendarLocalizations.dateTimePickerDateLabel] and
/// [CalendarLocalizations.dateTimePickerTimeLabel], which switch to the
/// date view and the time view; the time view's header row is at least as
/// tall as the day picker's chevrons, so the control lies at the same place
/// in both views.
///
/// The picker's value is [day] and [minute], a minute after midnight of it
/// on the clock of [store]'s zone, or of the device where [store] is null.
/// A tap on a day reports that day with the minute through [onChanged], and
/// a pick of a time reports the time with [day], so a host takes the two
/// together. With a null [minute] the picker picks a day alone: it shows
/// its date view with no control, and a tap on a day reports the day with
/// null.
///
/// The time picker offers the times of [day] alone: from the first to the
/// last time [timeBoundsOf] gives for it, those [isTimeEnabled] accepts on
/// it, and of those the ones the clock reads that day, so a time the clock
/// skips, as at a change to summer time, draws disabled and takes no pick.
/// Where the time a tap on a day would keep is not one of those on the new
/// day, the tap reports the offered time of that day nearest it on the
/// [minuteStep], the later of two as near, or the time unchanged where the
/// day offers none.
///
/// The picker opens on its time view where [initialShowsTime] says, and on
/// its date view otherwise; a later build's has no effect. A tap on the
/// control's other segment switches the view, and nothing else does: a day
/// picked keeps the date view. Each switch reports through
/// [onShowsTimeChanged] whether it turned to the time view, and changes
/// nothing of the value.
///
/// The control is a stadium track filled with the theme's
/// [CalendarThemeData.background], whose two segments share its width; a
/// stadium pill filled with [CalendarThemeData.primaryTint] lies under the
/// shown view's segment, whose label is in [CalendarThemeData.primary], the
/// other's in [CalendarThemeData.textSecondary], both in the theme's
/// [CalendarThemeData.actionLabelStyle]. A screen reader hears each segment
/// as a button in a mutually exclusive group, the shown view's selected.
/// The control takes at most half its header row's width, scaling down as
/// a whole where its labels would take more, so the day picker's chevrons
/// and title keep the rest at any text size.
///
/// Under a bounded width the picker takes all of it. Under an unbounded
/// width, and to a parent that asks its intrinsic width, such as an
/// `AlertDialog`, it is as wide as the views it shows need for their header
/// rows to show unscaled, the control within half its row, and the time
/// view also for its time picker; the day picker's days take whatever width
/// they are given and add nothing to it.
///
/// As the view switches, the picker's height moves from the height of the
/// view it leaves to that of the view it turns to over the theme's
/// [CalendarThemeData.motionDuration] on its
/// [CalendarThemeData.motionCurve], clipping what lies below it; the view
/// it turns to lies at full opacity under the view it leaves, which fades
/// out over the motion, taking no pointer and no pick, so a column held or
/// spinning picks nothing; and the pill slides to the new segment as the
/// labels turn between their colours. A [minute] that turns null shows the
/// date view in the same way, the time view keeping the time, the bounds
/// and the times it offered, so the picker asks [timeBoundsOf] and
/// [isTimeEnabled] nothing more, and the control fades out over the motion;
/// one that turns back shows the view the control last turned to. All of it
/// happens at once where the platform asks for no animations. Where a
/// switch leaves the focus in the view it hides, the focus moves to the
/// segment that names the shown view in the shown view's control.
///
/// The date view keeps its state while the time view shows, its fold, its
/// browse and its month picker included, taking no pointer, no focus and no
/// screen reader's attention, and running no animation; the time view is
/// built only while it shows or fades out.
///
/// The picker draws in the theme a `CalendarView` would resolve there, as
/// [CalendarDayPicker] does, and its words come from
/// [CalendarLocalizations].
class CalendarDateTimePicker<T> extends StatefulWidget {
  /// Creates a picker of [day] and [minute].
  ///
  /// Throws an [ArgumentError], in every build, naming the first of: a
  /// [minute] outside 0 to 1440; a [minuteStep] under 1 or not dividing 60;
  /// and a [firstColumn] outside 0 to 6.
  CalendarDateTimePicker({
    super.key,
    required this.day,
    required this.minute,
    required this.onChanged,
    this.store,
    this.today,
    this.firstDay,
    this.lastDay,
    this.isDayEnabled,
    this.firstColumn = 0,
    this.dayBadges,
    this.daysToEdges = false,
    this.browsesBeforeFirstDay = true,
    this.initialView = const CalendarDayPickerView(),
    this.onViewChanged,
    this.hourLabelFormat = CalendarHourLabelFormat.twentyFourHour,
    this.minuteStep = CalendarDates.defaultSlotMinutes,
    this.timeBoundsOf,
    this.isTimeEnabled,
    this.timeFocusNode,
    this.hapticFeedback = false,
    this.subject,
    this.initialShowsTime = false,
    this.onShowsTimeChanged,
  }) {
    final minute = this.minute;
    if (minute != null &&
        (minute < 0 || minute > CalendarDates.minutesPerDay)) {
      throw ArgumentError.value(minute, "minute", "is outside 0 to 1440");
    }
    if (minuteStep < 1 || 60 % minuteStep != 0) {
      throw ArgumentError.value(
        minuteStep,
        "minuteStep",
        "is under 1 or does not divide 60",
      );
    }
    if (firstColumn < 0 || firstColumn >= DateTime.daysPerWeek) {
      throw ArgumentError.value(
        firstColumn,
        "firstColumn",
        "is outside 0 to 6",
      );
    }
  }

  /// The selected day, which the day picker shows selected and opens on,
  /// and which the time view's header names.
  final DateTime day;

  /// The selected time, a minute after midnight of [day], 0 to 1440, where
  /// 1440 is the midnight that ends it; null where the picker picks a day
  /// alone.
  final int? minute;

  /// Reports a pick: a day the user tapped, with the time it keeps or
  /// moves to, or a time the user picked, with [day]; the day as the start
  /// of its date on the clock of [store]'s zone, and the time null where
  /// [minute] is. Null makes the picker take no pick.
  final void Function(DateTime day, int? minute)? onChanged;

  /// The store, or any reader, whose entries badge the days, and whose
  /// zone's clock the day and the time are read on; null for no badges and
  /// the device's clock.
  final CalendarEntryReader<T>? store;

  /// The day the day picker rings as today, and against which the time
  /// view's header names [day]; null for the date the device's clock reads
  /// on [store]'s zone as the picker builds.
  final DateTime? today;

  /// The first day the picker takes, as [CalendarDayPicker.firstDay].
  final DateTime? firstDay;

  /// The last day the picker takes, as [CalendarDayPicker.lastDay].
  final DateTime? lastDay;

  /// Whether the picker takes a day, as [CalendarDayPicker.isEnabled].
  final bool Function(DateTime day)? isDayEnabled;

  /// The weekday column a week starts on, 0 for Monday to 6 for Sunday.
  final int firstColumn;

  /// The kinds of entry the days' badges mark, as
  /// [CalendarDayPicker.dayBadges].
  final CalendarDayBadges<T>? dayBadges;

  /// Whether the circles of the day picker's first and last columns reach
  /// its sides, as [CalendarDayPicker.daysToEdges]; the time view's header
  /// then pads no side either.
  final bool daysToEdges;

  /// Whether the day picker browses before [firstDay]'s week and month, as
  /// [CalendarDayPicker.browsesBeforeFirstDay].
  final bool browsesBeforeFirstDay;

  /// The view the day picker opens on, as [CalendarDayPicker.initialView].
  final CalendarDayPickerView initialView;

  /// Reports the view the day picker turns to, as
  /// [CalendarDayPicker.onViewChanged].
  final ValueChanged<CalendarDayPickerView>? onViewChanged;

  /// The clock the time picker's Hour column follows.
  final CalendarHourLabelFormat hourLabelFormat;

  /// The minutes between the time picker's Minute rows, which divides 60,
  /// and the step a tap on a day moves a time it does not keep by.
  final int minuteStep;

  /// The first and last time the time picker offers on a day, each 0 to
  /// 1440, the first not after the last; null for 0 to 1439 on every day.
  /// Asked of [day] at each build of the time picker while [minute] is not
  /// null, and of the day a tap picks.
  final ({int min, int max}) Function(DateTime day)? timeBoundsOf;

  /// Whether the time picker offers `minute` on `day`; null offers every
  /// time within [timeBoundsOf]'s. Asked of [day]'s times as the time
  /// picker asks [CalendarTimePicker.isEnabled], each at most once until
  /// the day, this predicate, compared by `==`, or [store]'s zone changes,
  /// while [minute] is not null; and of the times of the day a tap picks
  /// where the time it keeps is not offered there.
  final bool Function(DateTime day, int minute)? isTimeEnabled;

  /// The focus node of the time picker's first shown column, as
  /// [CalendarTimePicker.focusNode].
  final FocusNode? timeFocusNode;

  /// Whether the time picker's columns click as they move, as
  /// [CalendarTimePicker.hapticFeedback].
  final bool hapticFeedback;

  /// What the picker edits, as [CalendarTimePicker.subject].
  final Object? subject;

  /// Whether the picker opens on its time view; false, the default, opens
  /// it on its date view.
  final bool initialShowsTime;

  /// Reports the view a tap on the view control or on a day turns the
  /// picker to: true for the time view. Null reports nothing.
  final ValueChanged<bool>? onShowsTimeChanged;

  @override
  State<CalendarDateTimePicker<T>> createState() {
    return _CalendarDateTimePickerState<T>();
  }
}

class _CalendarDateTimePickerState<T> extends State<CalendarDateTimePicker<T>>
    with TickerProviderStateMixin {
  /// Resolves the theme the picker draws with, as a `CalendarView` does.
  final CalendarThemeResolver _themes = CalendarThemeResolver();

  /// The key of what the picker builds, under the optional [Material] and
  /// [CalendarTheme], so a resolve that adds or drops one keeps its state.
  final GlobalKey _contentKey = GlobalKey();

  /// Whether the view control last turned to the time view.
  late bool _showsTime;

  /// Where the picker lies between its views, from 0, the date view, to 1,
  /// the time view.
  late final AnimationController _view;

  /// [_view] on the theme's curve, which the picker's height, the
  /// control's pill and its labels' colours read, and the opacity of the
  /// time view as it fades out.
  late final CurvedAnimation _viewCurve;

  /// [_viewCurve] from 1 down, the opacity of the date view as it fades
  /// out.
  late final Animation<double> _dateFade;

  /// How far the control is in, from 0, gone, to 1, shown: shown while
  /// [CalendarDateTimePicker.minute] is not null.
  late final AnimationController _control;

  /// [_control] on the theme's curve, which the control's opacity reads.
  late final CurvedAnimation _controlFade;

  /// The focus nodes of the date view's control's segments, the Date
  /// segment's and the Time segment's.
  final List<FocusNode> _dateViewSegments = <FocusNode>[
    FocusNode(debugLabel: "Date view's Date segment"),
    FocusNode(debugLabel: "Date view's Time segment"),
  ];

  /// The focus nodes of the time view's control's segments, the Date
  /// segment's and the Time segment's.
  final List<FocusNode> _timeViewSegments = <FocusNode>[
    FocusNode(debugLabel: "Time view's Date segment"),
    FocusNode(debugLabel: "Time view's Time segment"),
  ];

  /// The nodes of the views, each of which has the focus while a node in
  /// its view does.
  final FocusNode _dateArea = FocusNode(
    debugLabel: "Date view",
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode _timeArea = FocusNode(
    debugLabel: "Time view",
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// The time the time view shows: [CalendarDateTimePicker.minute], or
  /// while the view fades out after that turned null, the last it was.
  int? _shownMinute;

  /// [_offers], the time picker's predicate of the day numbered
  /// [_offersDay], under the predicate [_offersPredicate] and on the clock
  /// of [_offersZone], which keeps its answers, kept so the host is asked
  /// of each time once.
  bool Function(int minute)? _offers;
  int? _offersDay;
  Object? _offersPredicate;
  Location? _offersZone;

  /// The bounds the time picker last built with while the minute was not
  /// null, which it keeps, with [_offers], while it fades out after the
  /// minute turned null, so it asks the host nothing more.
  ({int min, int max})? _shownBounds;

  /// Whether the picker shows its time view.
  bool get _timeShown {
    return _showsTime && widget.minute != null;
  }

  /// The day the picker counts as today, on the clock of the store's zone.
  DateTime get _today {
    return widget.today ??
        CalendarDates.inZone(DateTime.now(), zone: widget.store?.zone);
  }

  @override
  void initState() {
    super.initState();
    _showsTime = widget.initialShowsTime;
    _shownMinute = widget.minute;
    _view = AnimationController(vsync: this, value: _timeShown ? 1.0 : 0.0)
      ..addStatusListener(_viewStatusChanged);
    _viewCurve = CurvedAnimation(parent: _view, curve: Curves.linear);
    _dateFade = ReverseAnimation(_viewCurve);
    _control = AnimationController(
      vsync: this,
      value: widget.minute != null ? 1.0 : 0.0,
    )..addStatusListener(_controlStatusChanged);
    _controlFade = CurvedAnimation(parent: _control, curve: Curves.linear);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTheme();
  }

  @override
  void reassemble() {
    _themes.reset();
    super.reassemble();
    _resolveTheme();
  }

  @override
  void didUpdateWidget(CalendarDateTimePicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final minute = widget.minute;
    if (minute != null) {
      _shownMinute = minute;
    }
    if ((minute != null) != (oldWidget.minute != null)) {
      if (minute != null) {
        _control.forward();
      } else {
        _control.reverse();
      }
    }
    _showView();
  }

  @override
  void dispose() {
    _viewCurve.dispose();
    _view.dispose();
    _controlFade.dispose();
    _control.dispose();
    for (final node in <FocusNode>[
      ..._dateViewSegments,
      ..._timeViewSegments,
      _dateArea,
      _timeArea,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Resolves the theme the picker draws with, and gives the animations
  /// its motion, or none where the platform asks for no animations.
  void _resolveTheme() {
    _themes.resolve(context);
    final theme = _themes.theme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
    _view.duration = duration;
    _control.duration = duration;
    final curve = theme.motionCurve;
    // A reverse reads its curve from 1 down to 0, so the flip of the curve
    // eases a turn to the date view as the curve eases one to the time
    // view.
    final flipped = FlippedCurve(curve);
    _viewCurve
      ..curve = curve
      ..reverseCurve = flipped;
    _controlFade
      ..curve = curve
      ..reverseCurve = flipped;
  }

  /// Moves to the view the control and the minute say.
  void _showView() {
    if (_timeShown) {
      _view.forward();
    } else {
      _view.reverse();
    }
  }

  /// Builds the views anew as the switch starts, turns and ends: the time
  /// view comes and goes, and the date view runs its animations only while
  /// it paints.
  void _viewStatusChanged(AnimationStatus status) {
    setState(() {
      if (status == AnimationStatus.dismissed) {
        _shownMinute = widget.minute;
      }
    });
  }

  /// Builds the control anew as it comes and as it goes.
  void _controlStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.forward) {
      setState(() {});
    }
  }

  /// Turns to the time view where [time], and to the date view otherwise,
  /// from the control, and reports the turn.
  void _select(bool time) {
    if (time == _showsTime || widget.minute == null) {
      return;
    }
    final leaving = time ? _dateArea : _timeArea;
    final segment = time ? _timeViewSegments[1] : _dateViewSegments[0];
    if (leaving.hasFocus) {
      // The view turned to takes focus only once built anew: until then
      // the date view's nodes lie under its ExcludeFocus, and the time
      // view is not yet built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showsTime == time) {
          segment.requestFocus();
        }
      });
    }
    setState(() {
      _showsTime = time;
    });
    _showView();
    widget.onShowsTimeChanged?.call(time);
  }

  /// The first and last time [day] offers.
  ({int min, int max}) _boundsOn(DateTime day) {
    return widget.timeBoundsOf?.call(day) ??
        (min: 0, max: CalendarDates.minutesPerDay - 1);
  }

  /// Whether the clock of [zone] reads [minute] on the day numbered [day]:
  /// as a time of it, or for 1440 as the end of it.
  static bool _clockReads(int day, int minute, Location? zone) {
    final wall = day * CalendarDates.minutesPerDay + minute;
    if (minute == CalendarDates.minutesPerDay) {
      return CalendarDates.endAtWallMinute(wall, zone: zone) != null;
    }
    return CalendarDates.timeAtWallMinute(wall, zone: zone) != null;
  }

  /// Whether [day] offers [minute], within its bounds or not: the clock
  /// reads it that day and [CalendarDateTimePicker.isTimeEnabled] accepts
  /// it.
  bool _accepts(DateTime day, int minute) {
    final predicate = widget.isTimeEnabled;
    return _clockReads(
          CalendarDates.dayNumber(day),
          minute,
          widget.store?.zone,
        ) &&
        (predicate == null || predicate(day, minute));
  }

  /// The time picker's predicate of [CalendarDateTimePicker.day], kept
  /// while the day, the host's predicate and the zone stay.
  bool Function(int minute) _offersOfDay() {
    final day = widget.day;
    final number = CalendarDates.dayNumber(day);
    final predicate = widget.isTimeEnabled;
    final zone = widget.store?.zone;
    var offers = _offers;
    if (offers == null ||
        _offersDay != number ||
        _offersPredicate != predicate ||
        _offersZone != zone) {
      // The time picker remakes its rules, and asks again, at each of its
      // updates, so the answers are kept here.
      final answers = <int, bool>{};
      offers = (minute) {
        return answers[minute] ??= _accepts(day, minute);
      };
      _offers = offers;
      _offersDay = number;
      _offersPredicate = predicate;
      _offersZone = zone;
    }
    return offers;
  }

  /// The time a tap on [day] keeps from [minute]: [minute] where [day]
  /// offers it, and otherwise the offered time of [day] nearest it on the
  /// minute step, the later of two as near, or [minute] where [day] offers
  /// none.
  int _keptOn(DateTime day, int minute) {
    final bounds = _boundsOn(day);
    bool offers(int time) {
      return time >= bounds.min && time <= bounds.max && _accepts(day, time);
    }

    if (offers(minute)) {
      return minute;
    }
    final step = widget.minuteStep;
    int? nearest;
    for (
      var time = (bounds.min + step - 1) ~/ step * step;
      time <= bounds.max;
      time += step
    ) {
      if (!offers(time)) {
        continue;
      }
      final distance = (time - minute).abs();
      // Times rise, so a later one as near as the nearest replaces it.
      if (nearest == null || distance <= (nearest - minute).abs()) {
        nearest = time;
      }
    }
    return nearest ?? minute;
  }

  void _pickDay(DateTime day) {
    final minute = widget.minute;
    widget.onChanged?.call(day, minute == null ? null : _keptOn(day, minute));
  }

  void _pickTime(int? minute) {
    if (minute != null) {
      widget.onChanged?.call(
        CalendarDates.dateOfDayNumber(
          CalendarDates.dayNumber(widget.day),
          zone: widget.store?.zone,
        ),
        minute,
      );
    }
  }

  /// The view control in the header of the time view where [inTimeView],
  /// and of the date view otherwise, fading with [_controlFade], at most
  /// half its header row wide, scaled down to it where its labels take
  /// more; its segments carry their keys in the shown view's header alone.
  Widget _controlIn(
    CalendarThemeData theme,
    CalendarLocalizations strings, {
    required bool inTimeView,
  }) {
    final gone = widget.minute == null;
    final nodes = inTimeView ? _timeViewSegments : _dateViewSegments;
    return CalendarHeaderTrailingShare(
      share: 0.5,
      child: FadeTransition(
        opacity: _controlFade,
        child: ExcludeFocus(
          excluding: gone,
          child: IgnorePointer(
            ignoring: gone,
            child: ExcludeSemantics(
              excluding: gone,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _ViewControl(
                  position: _viewCurve,
                  showsTime: _timeShown,
                  keyed: inTimeView == _timeShown,
                  theme: theme,
                  dateLabel: strings.dateTimePickerDateLabel,
                  timeLabel: strings.dateTimePickerTimeLabel,
                  dateNode: nodes[0],
                  timeNode: nodes[1],
                  onSelect: _select,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [view] as the switch shows it: taking pointers, focus and a screen
  /// reader's attention only while [active], running its animations only
  /// while [painted], at [opacity], under the focus node [area].
  Widget _viewSlot({
    required Widget view,
    required FocusNode area,
    required bool active,
    required bool painted,
    required Animation<double> opacity,
  }) {
    return TickerMode(
      enabled: painted,
      child: ExcludeFocus(
        excluding: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: IgnorePointer(
            ignoring: !active,
            child: FadeTransition(
              opacity: opacity,
              child: Focus(focusNode: area, child: view),
            ),
          ),
        ),
      ),
    );
  }

  /// The time view: on a card as the day picker's, a header row naming the
  /// day, at least as tall as the day picker's chevrons, with the control
  /// at its end, over the time picker of the shown minute.
  Widget _timeView(CalendarThemeData theme, CalendarLocalizations strings) {
    final minute = _shownMinute!;
    final live = widget.minute != null;
    final bounds = live ? _boundsOn(widget.day) : _shownBounds!;
    final offers = live ? _offersOfDay() : _offers!;
    _shownBounds = bounds;
    final onChanged = widget.onChanged;
    return DecoratedBox(
      key: dateTimePickerTimeKey,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        // The day picker's card pads its header so.
        padding: widget.daysToEdges
            ? const EdgeInsets.only(top: 8.0)
            : const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: CalendarHeader.chevronExtentOf(context),
              ),
              child: CalendarHeaderRow(
                gap: 4.0,
                lead: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      strings.dayTitle(widget.day, _today),
                      maxLines: 1,
                      style: CalendarHeader.titleStyleOf(theme),
                    ),
                  ),
                ),
                trailing: _control.isDismissed
                    ? null
                    : _controlIn(theme, strings, inTimeView: true),
              ),
            ),
            const SizedBox(height: 4.0),
            CalendarTimePicker(
              value: minute,
              onChanged: onChanged == null || !_timeShown ? null : _pickTime,
              hourLabelFormat: widget.hourLabelFormat,
              minuteStep: widget.minuteStep,
              min: bounds.min,
              max: bounds.max,
              isEnabled: offers,
              focusNode: widget.timeFocusNode,
              hapticFeedback: widget.hapticFeedback,
              subject: widget.subject,
            ),
          ],
        ),
      ),
    );
  }

  /// The views: the date view, and the time view while it shows or fades
  /// out, under the switch between them.
  Widget _views(CalendarThemeData theme, CalendarLocalizations strings) {
    final timeShown = _timeShown;
    final dateView = CalendarDayPicker<T>(
      value: widget.day,
      onChanged: widget.onChanged == null ? null : _pickDay,
      store: widget.store,
      today: widget.today,
      firstDay: widget.firstDay,
      lastDay: widget.lastDay,
      isEnabled: widget.isDayEnabled,
      firstColumn: widget.firstColumn,
      dayBadges: widget.dayBadges,
      daysToEdges: widget.daysToEdges,
      browsesBeforeFirstDay: widget.browsesBeforeFirstDay,
      initialView: widget.initialView,
      onViewChanged: widget.onViewChanged,
      headerTrailing: _control.isDismissed
          ? null
          : _controlIn(theme, strings, inTimeView: false),
    );
    return _ViewSwitch(
      progress: _viewCurve,
      timeOnTop: !timeShown,
      date: _viewSlot(
        view: dateView,
        area: _dateArea,
        active: !timeShown,
        painted: !timeShown || !_view.isCompleted,
        opacity: timeShown ? _dateFade : kAlwaysCompleteAnimation,
      ),
      time: _view.isDismissed
          ? null
          : _viewSlot(
              view: _timeView(theme, strings),
              area: _timeArea,
              active: timeShown,
              painted: true,
              opacity: timeShown ? kAlwaysCompleteAnimation : _viewCurve,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themes.theme;
    final strings = CalendarLocalizations.of(context);
    Widget content = KeyedSubtree(
      key: _contentKey,
      child: _views(theme, strings),
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

/// The view control: a segment for each view, the date view's first,
/// sharing the control's width equally, on a stadium track filled with
/// [theme]'s background; a stadium pill filled with its primary tint lies
/// under the segment of the view [position] lies at, sliding between the
/// segments as [position] runs from 0, the date view, to 1, the time view,
/// and each label turns from the theme's secondary text colour to its
/// primary colour as the pill comes under it. A tap on a segment reaches
/// [onSelect] with whether it is the time view's. Where [keyed], its
/// segments' labels carry [dateTimePickerDateSegmentKey] and
/// [dateTimePickerTimeSegmentKey]; a label alone, so that the keys moving
/// between the views' controls at a switch build no segment anew.
class _ViewControl extends StatelessWidget {
  const _ViewControl({
    required this.position,
    required this.showsTime,
    required this.keyed,
    required this.theme,
    required this.dateLabel,
    required this.timeLabel,
    required this.dateNode,
    required this.timeNode,
    required this.onSelect,
  });

  final Animation<double> position;

  /// Whether the time view's segment is the selected one.
  final bool showsTime;

  final bool keyed;
  final CalendarThemeData theme;
  final String dateLabel;
  final String timeLabel;
  final FocusNode dateNode;
  final FocusNode timeNode;
  final ValueChanged<bool> onSelect;

  static const ShapeBorder _shape = StadiumBorder();

  Widget _segment(bool time, double at) {
    // How far the pill lies under this segment, from 0 to 1.
    final under = time ? at : 1.0 - at;
    final ink = Color.lerp(theme.textSecondary, theme.primary, under)!;
    return Semantics(
      container: true,
      button: true,
      selected: time == showsTime,
      inMutuallyExclusiveGroup: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          focusNode: time ? timeNode : dateNode,
          customBorder: _shape,
          onTap: () {
            onSelect(time);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 6.0,
            ),
            child: Center(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: Text(
                time ? timeLabel : dateLabel,
                key: keyed
                    ? (time
                          ? dateTimePickerTimeSegmentKey
                          : dateTimePickerDateSegmentKey)
                    : null,
                maxLines: 1,
                style: theme.actionLabelStyle.copyWith(color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: position,
      builder: (context, child) {
        final at = position.value;
        // Both segments take the width of the wider one's label.
        return IntrinsicWidth(
          child: DecoratedBox(
            decoration: ShapeDecoration(color: theme.background, shape: _shape),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Align(
                    alignment: AlignmentDirectional(at * 2.0 - 1.0, 0.0),
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1.0,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: theme.primaryTint,
                          shape: _shape,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(child: _segment(false, at)),
                    Expanded(child: _segment(true, at)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The slots of a [_ViewSwitch].
enum _View { date, time }

/// Lays out [date] and, where given, [time], each as wide as the switch and
/// as tall as it takes, from the switch's top; the switch is as wide as its
/// constraints let it be, or under an unbounded width as the wider view's
/// intrinsic width, and as tall as [date] at a [progress] of 0, as [time]
/// at 1, and between the two heights in between, clipping what lies below
/// it. Its intrinsic width is the wider view's, and its intrinsic height
/// lies between the views' as its height does. It paints [time] over [date]
/// where [timeOnTop] and [date] over [time] otherwise, and a hit reaches
/// the one on top first.
class _ViewSwitch
    extends SlottedMultiChildRenderObjectWidget<_View, RenderBox> {
  const _ViewSwitch({
    required this.progress,
    required this.timeOnTop,
    required this.date,
    required this.time,
  });

  final Animation<double> progress;
  final bool timeOnTop;
  final Widget date;
  final Widget? time;

  @override
  Iterable<_View> get slots {
    return _View.values;
  }

  @override
  Widget? childForSlot(_View slot) {
    switch (slot) {
      case _View.date:
        return date;
      case _View.time:
        return time;
    }
  }

  @override
  _RenderViewSwitch createRenderObject(BuildContext context) {
    return _RenderViewSwitch(progress: progress, timeOnTop: timeOnTop);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderViewSwitch renderObject,
  ) {
    renderObject
      ..progress = progress
      ..timeOnTop = timeOnTop;
  }
}

class _RenderViewSwitch extends RenderBox
    with SlottedContainerRenderObjectMixin<_View, RenderBox> {
  _RenderViewSwitch({
    required Animation<double> progress,
    required bool timeOnTop,
  }) : _progress = progress,
       _timeOnTop = timeOnTop;

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) {
      return;
    }
    if (attached) {
      _progress.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _progress = value;
    markNeedsLayout();
  }

  bool _timeOnTop;
  set timeOnTop(bool value) {
    if (value == _timeOnTop) {
      return;
    }
    _timeOnTop = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  RenderBox? get _date {
    return childForSlot(_View.date);
  }

  RenderBox? get _time {
    return childForSlot(_View.time);
  }

  /// The children from the one painted first to the one on top.
  List<RenderBox> get _paintOrder {
    final bottom = _timeOnTop ? _date : _time;
    final top = _timeOnTop ? _time : _date;
    return <RenderBox>[?bottom, ?top];
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  /// The switch's height between a date view [date] tall and a time view
  /// [time] tall, or none.
  double _heightBetween(double date, double? time) {
    if (time == null) {
      return date;
    }
    return lerpDouble(date, time, _progress.value)!;
  }

  /// The width the switch lays its views out at under [constraints]: their
  /// maximum, or under an unbounded width the widest view's intrinsic
  /// width, within their minimum.
  double _widthUnder(BoxConstraints constraints) {
    if (constraints.hasBoundedWidth) {
      return constraints.maxWidth;
    }
    return constraints.constrainWidth(
      _widest((child) {
        return child.getMaxIntrinsicWidth(double.infinity);
      }),
    );
  }

  @override
  void performLayout() {
    final width = _widthUnder(constraints);
    final inner = BoxConstraints.tightFor(width: width);
    final date = _date;
    final time = _time;
    date?.layout(inner, parentUsesSize: true);
    time?.layout(inner, parentUsesSize: true);
    size = constraints.constrain(
      Size(width, _heightBetween(date?.size.height ?? 0.0, time?.size.height)),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = _widthUnder(constraints);
    final inner = BoxConstraints.tightFor(width: width);
    return constraints.constrain(
      Size(
        width,
        _heightBetween(
          _date?.getDryLayout(inner).height ?? 0.0,
          _time?.getDryLayout(inner).height,
        ),
      ),
    );
  }

  double _widest(double Function(RenderBox child) extent) {
    var widest = 0.0;
    for (final child in children) {
      final width = extent(child);
      if (width > widest) {
        widest = width;
      }
    }
    return widest;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return _widest((child) {
      return child.getMinIntrinsicWidth(height);
    });
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return _widest((child) {
      return child.getMaxIntrinsicWidth(height);
    });
  }

  /// The switch's intrinsic height from its views' [extent], asking none of
  /// a view the switch's height gives no weight at its progress.
  double _intrinsicHeight(double Function(RenderBox child) extent) {
    final date = _date;
    final time = _time;
    final at = _progress.value;
    final dateHeight = date == null || (time != null && at == 1.0)
        ? 0.0
        : extent(date);
    if (time == null) {
      return dateHeight;
    }
    return _heightBetween(dateHeight, at == 0.0 ? 0.0 : extent(time));
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _intrinsicHeight((child) {
      return child.getMinIntrinsicHeight(width);
    });
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _intrinsicHeight((child) {
      return child.getMaxIntrinsicHeight(width);
    });
  }

  /// Whether a child lies taller than the switch, below its bottom.
  bool get _clips {
    for (final child in children) {
      if (child.size.height > size.height) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_clips) {
      _clip.layer = null;
      _paintChildren(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintChildren,
      oldLayer: _clip.layer,
    );
  }

  void _paintChildren(PaintingContext context, Offset offset) {
    for (final child in _paintOrder) {
      context.paintChild(child, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _paintOrder.reversed) {
      if (child.hitTest(result, position: position)) {
        return true;
      }
    }
    return false;
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    return _clips ? Offset.zero & size : null;
  }
}
