/// An inline picker of a day and a time of it: a [CalendarDayPicker] over a
/// [CalendarTimePicker], with a toggle that shows and hides the time.
library;

import 'package:flutter/material.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import '../views/time_picker.dart';
import 'calendar_day_picker.dart';
import 'calendar_theme_extension.dart';

/// The key of a [CalendarDateTimePicker]'s Time toggle.
const ValueKey<String> dateTimePickerToggleKey = ValueKey<String>(
  "date-time-picker-toggle",
);

/// The key of the part of a [CalendarDateTimePicker] under its day picker,
/// which holds the divider and the time picker and grows and shrinks as the
/// time shows and hides.
const ValueKey<String> dateTimePickerTimeKey = ValueKey<String>(
  "date-time-picker-time",
);

/// The key of the line between a [CalendarDateTimePicker]'s day picker and
/// its time picker.
const ValueKey<String> dateTimePickerDividerKey = ValueKey<String>(
  "date-time-picker-divider",
);

/// An inline picker of a day and a time of it, put together of a
/// [CalendarDayPicker] and a [CalendarTimePicker], each as it is on its
/// own: the day picker on top, its header holding, at its end, a Time
/// toggle, and under it a hairline in the theme's
/// [CalendarThemeData.outline] over the time picker, while the toggle is on.
///
/// The picker's value is [day] and [minute], a minute after midnight of it
/// on the clock of [store]'s zone, or of the device where [store] is null.
/// A tap on a day reports that day with the minute through [onChanged], and
/// a pick of a time reports the time with [day], so a host takes the two
/// together. With a null [minute] the picker picks a day alone: it shows no
/// toggle and no time, and a tap on a day reports the day with null.
///
/// The time picker offers the times of [day] alone: from the first to the
/// last time [timeBoundsOf] gives for it, those [isTimeEnabled] accepts on
/// it, and of those the ones the clock reads that day, so a time the clock
/// skips, as at a change to summer time, draws disabled and takes no pick.
/// Where the time a tap on a day would keep is not one of those on the new
/// day, the tap reports the offered time of that day nearest it on the
/// [minuteStep], the later of two as near, or the time unchanged where the
/// day offers none. The time picker's Now shows only on [today]'s day.
///
/// The toggle, a pill labelled with
/// [CalendarLocalizations.dateTimePickerTimeLabel], is on while the time
/// shows: filled with the theme's [CalendarThemeData.primaryTint], its
/// label in [CalendarThemeData.primary]; and off filled with
/// [CalendarThemeData.background], its label in
/// [CalendarThemeData.textSecondary]; its label in the theme's
/// [CalendarThemeData.actionLabelStyle]. A screen reader hears it as a
/// button that is toggled or not. A tap on it turns it, reports the time's
/// new state through [onShowsTimeChanged], and changes nothing of the
/// value. The picker opens with the time shown where [initialShowsTime]
/// says, and a later build's has no effect.
///
/// As the time shows, the part under the day picker grows from no height
/// to the divider's and the time picker's over the theme's
/// [CalendarThemeData.motionDuration] on its
/// [CalendarThemeData.motionCurve], the divider and the time picker fading
/// in over the motion's last half; as it hides, the part shrinks over the
/// motion, still showing the time it showed, its divider and time picker
/// fading out over the motion's first half, taking no pointer and no pick,
/// so a column held or spinning picks nothing. The toggle turns between
/// its colours over that motion. A [minute] that turns null hides the time
/// as the toggle does, the time picker keeping the bounds and the times it
/// offered, so the picker asks [timeBoundsOf] and [isTimeEnabled] nothing
/// more, and the toggle fades out over the motion; one that turns back
/// shows them again. All of it happens at once where the
/// platform asks for no animations. Where the toggle hides the time with
/// the focus in the time picker, the focus moves to the toggle.
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
    this.now,
    this.nowPicksLater = false,
    this.timeFocusNode,
    this.hapticFeedback = false,
    this.subject,
    this.initialShowsTime = true,
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

  /// The selected day, which the day picker shows selected and opens on.
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

  /// The store whose entries badge the days, and whose zone's clock the
  /// day and the time are read on; null for no badges and the device's
  /// clock.
  final CalendarStore<T>? store;

  /// The day the day picker rings as today, and on which the time picker
  /// shows Now; null for the date the device's clock reads on [store]'s
  /// zone as the picker builds.
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
  /// its sides, as [CalendarDayPicker.daysToEdges].
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

  /// The current minute after midnight on the clock of [store]'s zone,
  /// which the time picker's Now picks, as [CalendarTimePicker.now], on
  /// [today]'s day alone; null shows no Now.
  final ValueGetter<int>? now;

  /// Whether Now picks the first later time the time picker offers, as
  /// [CalendarTimePicker.nowPicksLater].
  final bool nowPicksLater;

  /// The focus node of the time picker's first shown column, as
  /// [CalendarTimePicker.focusNode].
  final FocusNode? timeFocusNode;

  /// Whether the time picker's columns click as they move, as
  /// [CalendarTimePicker.hapticFeedback].
  final bool hapticFeedback;

  /// What the picker edits, as [CalendarTimePicker.subject].
  final Object? subject;

  /// Whether the picker opens with the time shown.
  final bool initialShowsTime;

  /// Reports whether the time shows, as a tap on the toggle turns it; null
  /// reports nothing.
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

  /// Whether the toggle is on.
  late bool _showsTime;

  /// How far the time is in, from 0, hidden, to 1, shown.
  late final AnimationController _time;

  /// [_time] on the theme's curve, which the time part's height reads.
  late final CurvedAnimation _timeSize;

  /// [_time] over its last half on the theme's curve, which the opacity of
  /// the divider and the time picker reads.
  late final CurvedAnimation _timeFade;

  /// How far the toggle is in, from 0, gone, to 1, shown: shown while
  /// [CalendarDateTimePicker.minute] is not null.
  late final AnimationController _toggle;

  /// [_toggle] on the theme's curve, which the toggle's opacity reads.
  late final CurvedAnimation _toggleFade;

  /// The toggle's focus node, which takes the focus from the time picker
  /// as the toggle hides it.
  final FocusNode _toggleFocus = FocusNode(debugLabel: "Time toggle");

  /// The node of the time part, which has the focus while the time picker
  /// does.
  final FocusNode _timeArea = FocusNode(
    debugLabel: "Time",
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// The time the time part shows: [CalendarDateTimePicker.minute], or
  /// while it shrinks out after that turned null, the last it was.
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
  /// null, which it keeps, with [_offers], while it hides after the minute
  /// turned null, so it asks the host nothing more.
  ({int min, int max})? _shownBounds;

  bool get _timeShown {
    return _showsTime && widget.minute != null;
  }

  @override
  void initState() {
    super.initState();
    _showsTime = widget.initialShowsTime;
    _shownMinute = widget.minute;
    _time = AnimationController(vsync: this, value: _timeShown ? 1.0 : 0.0)
      ..addStatusListener(_timeStatusChanged);
    _timeSize = CurvedAnimation(parent: _time, curve: Curves.linear);
    _timeFade = CurvedAnimation(parent: _time, curve: Curves.linear);
    _toggle = AnimationController(
      vsync: this,
      value: widget.minute != null ? 1.0 : 0.0,
    )..addStatusListener(_toggleStatusChanged);
    _toggleFade = CurvedAnimation(parent: _toggle, curve: Curves.linear);
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
        _toggle.forward();
      } else {
        _toggle.reverse();
      }
    }
    _showTime();
  }

  @override
  void dispose() {
    _timeSize.dispose();
    _timeFade.dispose();
    _time.dispose();
    _toggleFade.dispose();
    _toggle.dispose();
    _toggleFocus.dispose();
    _timeArea.dispose();
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
    _time.duration = duration;
    _toggle.duration = duration;
    final curve = theme.motionCurve;
    // A reverse reads its curve from 1 down to 0, so the flip of the curve
    // eases a hiding as the curve eases a showing.
    final flipped = FlippedCurve(curve);
    _timeSize
      ..curve = curve
      ..reverseCurve = flipped;
    _timeFade
      ..curve = Interval(0.5, 1.0, curve: curve)
      ..reverseCurve = Interval(0.5, 1.0, curve: flipped);
    _toggleFade
      ..curve = curve
      ..reverseCurve = flipped;
  }

  /// Shows or hides the time as the toggle and the minute say.
  void _showTime() {
    if (_timeShown) {
      _time.forward();
    } else {
      _time.reverse();
    }
  }

  /// Builds the time part anew as it comes and as it goes.
  void _timeStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.forward) {
      setState(() {
        if (status == AnimationStatus.dismissed) {
          _shownMinute = widget.minute;
        }
      });
    }
  }

  /// Builds the toggle anew as it comes and as it goes.
  void _toggleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.forward) {
      setState(() {});
    }
  }

  void _toggleTime() {
    final shows = !_showsTime;
    if (!shows && _timeArea.hasFocus) {
      _toggleFocus.requestFocus();
    }
    setState(() {
      _showsTime = shows;
    });
    _showTime();
    widget.onShowsTimeChanged?.call(shows);
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
      widget.onChanged?.call(widget.day, minute);
    }
  }

  /// Whether [CalendarDateTimePicker.day] is today, on the clock of the
  /// store's zone.
  bool get _onToday {
    final today =
        widget.today ??
        CalendarDates.inZone(DateTime.now(), zone: widget.store?.zone);
    return CalendarDates.dayNumber(today) ==
        CalendarDates.dayNumber(widget.day);
  }

  Widget _timePart(CalendarThemeData theme) {
    final minute = _shownMinute;
    if (minute == null || _time.isDismissed) {
      return const SizedBox.shrink();
    }
    final live = widget.minute != null;
    final bounds = live ? _boundsOn(widget.day) : _shownBounds!;
    final offers = live ? _offersOfDay() : _offers!;
    _shownBounds = bounds;
    final shown = _timeShown;
    final onChanged = widget.onChanged;
    return SizeTransition(
      key: dateTimePickerTimeKey,
      sizeFactor: _timeSize,
      alignment: AlignmentDirectional.topStart,
      child: FadeTransition(
        opacity: _timeFade,
        child: IgnorePointer(
          ignoring: !shown,
          child: ExcludeSemantics(
            excluding: !shown,
            child: Focus(
              focusNode: _timeArea,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: SizedBox(
                      key: dateTimePickerDividerKey,
                      height: 1.0,
                      child: ColoredBox(color: theme.outline),
                    ),
                  ),
                  CalendarTimePicker(
                    value: minute,
                    onChanged: onChanged == null || !shown ? null : _pickTime,
                    hourLabelFormat: widget.hourLabelFormat,
                    minuteStep: widget.minuteStep,
                    min: bounds.min,
                    max: bounds.max,
                    isEnabled: offers,
                    now: _onToday ? widget.now : null,
                    nowPicksLater: widget.nowPicksLater,
                    focusNode: widget.timeFocusNode,
                    hapticFeedback: widget.hapticFeedback,
                    subject: widget.subject,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themes.theme;
    final strings = CalendarLocalizations.of(context);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.motionDuration;
    Widget content = KeyedSubtree(
      key: _contentKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CalendarDayPicker<T>(
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
            headerTrailing: _toggle.isDismissed
                ? null
                : FadeTransition(
                    opacity: _toggleFade,
                    child: IgnorePointer(
                      ignoring: widget.minute == null,
                      child: ExcludeSemantics(
                        excluding: widget.minute == null,
                        child: _TimeToggle(
                          on: _showsTime,
                          label: strings.dateTimePickerTimeLabel,
                          theme: theme,
                          duration: motion,
                          focusNode: _toggleFocus,
                          onPressed: _toggleTime,
                        ),
                      ),
                    ),
                  ),
          ),
          _timePart(theme),
        ],
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

/// The Time toggle: a pill labelled [label], on filled with [theme]'s
/// primary tint, its label in its primary colour, and off filled with its
/// background, its label in its secondary text colour, turning between the
/// two over [duration] on the theme's curve; a tap reaches [onPressed].
class _TimeToggle extends StatelessWidget {
  const _TimeToggle({
    required this.on,
    required this.label,
    required this.theme,
    required this.duration,
    required this.focusNode,
    required this.onPressed,
  });

  final bool on;
  final String label;
  final CalendarThemeData theme;
  final Duration duration;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  static const ShapeBorder _shape = StadiumBorder();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      toggled: on,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: on ? 1.0 : 0.0),
        duration: duration,
        curve: theme.motionCurve,
        builder: (context, t, child) {
          final fill = Color.lerp(theme.background, theme.primaryTint, t)!;
          final ink = Color.lerp(theme.textSecondary, theme.primary, t)!;
          return DecoratedBox(
            decoration: ShapeDecoration(color: fill, shape: _shape),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: dateTimePickerToggleKey,
                focusNode: focusNode,
                customBorder: _shape,
                onTap: onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 6.0,
                  ),
                  child: Text(
                    label,
                    style: theme.actionLabelStyle.copyWith(color: ink),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
