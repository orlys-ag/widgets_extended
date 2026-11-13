/// The time picker: an Hour column and a Minute column that scroll and snap
/// to a band across the panel's middle, an AM/PM toggle on the 12-hour
/// clock, and optional Now and Clear actions.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';

/// The key of a [CalendarTimePicker]'s Hour column.
const ValueKey<String> timePickerHourColumnKey = ValueKey<String>(
  "time-picker-hour-column",
);

/// The key of a [CalendarTimePicker]'s Minute column.
const ValueKey<String> timePickerMinuteColumnKey = ValueKey<String>(
  "time-picker-minute-column",
);

/// The key of a [CalendarTimePicker]'s AM/PM toggle.
const ValueKey<String> timePickerToggleKey = ValueKey<String>(
  "time-picker-toggle",
);

/// The key of the AM half of a [CalendarTimePicker]'s toggle.
const ValueKey<String> timePickerAmKey = ValueKey<String>("time-picker-am");

/// The key of the PM half of a [CalendarTimePicker]'s toggle.
const ValueKey<String> timePickerPmKey = ValueKey<String>("time-picker-pm");

/// The key of the band a [CalendarTimePicker] draws behind its selected
/// rows.
const ValueKey<String> timePickerBandKey = ValueKey<String>(
  "time-picker-band",
);

/// The key of a [CalendarTimePicker]'s footer, which holds Now and Clear.
const ValueKey<String> timePickerFooterKey = ValueKey<String>(
  "time-picker-footer",
);

/// The key of a [CalendarTimePicker]'s Now action.
const ValueKey<String> timePickerNowKey = ValueKey<String>("time-picker-now");

/// The key of a [CalendarTimePicker]'s Clear action.
const ValueKey<String> timePickerClearKey = ValueKey<String>(
  "time-picker-clear",
);

/// The key of the Hour row of [number], the hour of the day, 0 to 24, as
/// [CalendarLocalizations.timePickerHour] takes it.
ValueKey<String> timePickerHourRowKey(int number) {
  return ValueKey<String>("time-picker-hour-$number");
}

/// The key of the Minute row of [minute], 0 to 59.
ValueKey<String> timePickerMinuteRowKey(int minute) {
  return ValueKey<String>("time-picker-minute-$minute");
}

const int _hourColumn = 0;
const int _minuteColumn = 1;

/// The columns the per-column state holds, which every per-column loop
/// runs over.
const int _columnCount = 2;

/// The rows a column shows; the band lies across the middle one.
const int _shownRows = 5;

const double _leastRowExtent = 40.0;
const double _rowPadding = 12.0;
const double _unboundedColumnWidth = 72.0;
const double _togglePadding = 24.0;
const double _controlRadius = 8.0;
const double _ringWidth = 2.0;
const Duration _digitWait = Duration(seconds: 1);

/// An inline time picker: an Hour column and a Minute column, five rows
/// tall, each scrolling and snapping its selected row to a band across the
/// panel's middle; on the 12-hour clock an AM/PM toggle right of the
/// Minute column; and a footer of Now and Clear where either is given.
///
/// [value] is a minute after midnight on the host's clock: 0 to 1439, or
/// 1440 for the 24:00 that ends a day; null selects no time and draws no
/// band. On the 24-hour clock the Hour column runs from 00 to 23, and to 24,
/// whose one minute is 00, where [max] is 1440. On the 12-hour clock it runs
/// 12, 01 to 11 in the toggle's half; 12 AM 00 picks 1440 where the range
/// holds 1440 and not 0, as an end's does, and where it holds both, picks
/// 1440 while [value] is 1440.
///
/// The rows are the times from [min] to [max] that are multiples of
/// [minuteStep]: an hour has a row where one of its times lies in range,
/// and the Minute column lists the selected hour's. A time [isEnabled]
/// refuses draws disabled and takes no pick, as does an hour with no time
/// it accepts and a toggle half with none. [isEnabled] is asked only of a
/// multiple of [minuteStep] from [min] to [max], each such time at most
/// once until the picker is given new parameters or its dependencies
/// change, and never per frame of a motion: only as the picker is built
/// anew, and as a pick, Now or Clear settles. The value always shows,
/// selected, off the step, out of range or refused included. Changing the
/// hour or the half keeps the minute where the new hour accepts it, and
/// otherwise takes the accepted minute of that hour nearest it, the
/// earlier on a tie.
///
/// A drag or fling snaps a column to a row, a tap picks a row, a mouse
/// wheel moves a column one row, and the keys move over the rows: Up and
/// Down, Home and End, Page Up and Page Down five rows, two digits typed
/// within a second, Left and Right between the columns and the toggle, and
/// A and P on the 12-hour clock. A pick is reported through [onChanged]
/// once, after every column has come to rest; a new [value] moves the
/// columns to it over the theme's motion and reports nothing, waiting while
/// a column is held in a drag. With a null [onChanged] the picker shows
/// its value and takes no input.
///
/// [now] gives the current minute after midnight on the host's clock; with
/// it, the footer's Now picks that minute rounded down to [minuteStep],
/// and draws disabled where that time cannot be picked. With [clearable],
/// the footer's Clear reports null. With neither, the picker has no
/// footer.
///
/// The picker draws in the theme [CalendarTheme.of] gives, the nearest
/// [CalendarTheme] or the built-in one, and reads no Material theme: a
/// Material app puts a [CalendarTheme] above it of its
/// `CalendarThemeExtension`'s `data`, or of
/// `CalendarThemeExtension.fromColorScheme(scheme).data`. Its words come
/// from [CalendarLocalizations].
class CalendarTimePicker extends StatefulWidget {
  /// Creates a time picker of [value].
  ///
  /// Throws an [ArgumentError], in every build, naming the first of: a
  /// [minuteStep] under 1 or not dividing 60; a [min] outside 0 to 1440; a
  /// [max] outside 0 to 1440; a [max] below [min]; a [value] outside 0 to
  /// 1440.
  CalendarTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.hourLabelFormat = CalendarHourLabelFormat.twentyFourHour,
    this.minuteStep = CalendarDates.defaultSlotMinutes,
    this.min = 0,
    this.max = CalendarDates.minutesPerDay - 1,
    this.isEnabled,
    this.now,
    this.clearable = false,
    this.focusNode,
  }) {
    _check(value, minuteStep, min, max);
  }

  /// The selected minute after midnight, 0 to 1440, or null for none.
  final int? value;

  /// Reports a pick once the columns have come to rest: a minute after
  /// midnight, or null from Clear. Null makes the picker take no input.
  final ValueChanged<int?>? onChanged;

  /// The clock the Hour column follows, and whether the toggle shows.
  final CalendarHourLabelFormat hourLabelFormat;

  /// The minutes between the Minute column's rows; it divides 60.
  final int minuteStep;

  /// The earliest time with a row, 0 to 1440.
  final int min;

  /// The latest time with a row, [min] to 1440.
  final int max;

  /// Whether a time may be picked; null accepts every time.
  final bool Function(int minute)? isEnabled;

  /// The current minute after midnight on the host's clock, which Now
  /// picks; null shows no Now.
  final ValueGetter<int>? now;

  /// Whether the footer shows Clear, which reports null.
  final bool clearable;

  /// The Hour column's focus node; the picker makes its own where null.
  final FocusNode? focusNode;

  static void _check(int? value, int minuteStep, int min, int max) {
    const day = CalendarDates.minutesPerDay;
    if (minuteStep < 1 || 60 % minuteStep != 0) {
      throw ArgumentError.value(
        minuteStep,
        "minuteStep",
        "is under 1 or does not divide 60",
      );
    }
    if (min < 0 || min > day) {
      throw ArgumentError.value(min, "min", "is outside 0 to 1440");
    }
    if (max < 0 || max > day) {
      throw ArgumentError.value(max, "max", "is outside 0 to 1440");
    }
    if (max < min) {
      throw ArgumentError.value(max, "max", "is below min, $min");
    }
    if (value != null && (value < 0 || value > day)) {
      throw ArgumentError.value(value, "value", "is outside 0 to 1440");
    }
  }

  @override
  State<CalendarTimePicker> createState() {
    return _CalendarTimePickerState();
  }
}

/// Which times a [CalendarTimePicker] offers, read from its parameters
/// when made: the grid of times its rows lie on, its range, and the times
/// [CalendarTimePicker.isEnabled] accepts. The picker builds its rows from
/// the one it makes of its widget, so any reader of [TimePickerRules.of] a
/// picker gets the answers its rows give.
///
/// Times are minutes after midnight, 0 to 1440; an hour is an hour row's
/// number, 0 to 24, as [timePickerHourRowKey] takes it. It holds no value
/// and no state of the picker's columns. It asks
/// [CalendarTimePicker.isEnabled] only of a time in range on the grid, each
/// at most once in its life.
final class TimePickerRules {
  /// The rules of [picker]'s parameters.
  factory TimePickerRules.of(CalendarTimePicker picker) {
    const day = CalendarDates.minutesPerDay;
    final twelveHour =
        picker.hourLabelFormat == CalendarHourLabelFormat.twelveHour;
    final isEnabled = picker.isEnabled;
    return TimePickerRules._(
      min: picker.min,
      max: picker.max,
      minuteStep: picker.minuteStep,
      twelveHour: twelveHour,
      midnightEnds:
          twelveHour &&
          picker.max == day &&
          (picker.min > 0 || picker.value == day),
      isEnabled: isEnabled,
      answers: isEnabled == null
          ? const <bool?>[]
          : List<bool?>.filled(day ~/ picker.minuteStep + 1, null),
    );
  }

  TimePickerRules._({
    required this.min,
    required this.max,
    required this.minuteStep,
    required this.twelveHour,
    required bool midnightEnds,
    required bool Function(int minute)? isEnabled,
    required List<bool?> answers,
  }) : _midnightEnds = midnightEnds,
       _isEnabled = isEnabled,
       _answers = answers;

  /// The earliest time in range, 0 to 1440.
  final int min;

  /// The latest time in range, [min] to 1440.
  final int max;

  /// The minutes between the Minute grid's times; it divides 60.
  final int minuteStep;

  /// Whether the Hour column follows the 12-hour clock: its rows are of
  /// one half of the day, which the AM/PM control picks.
  final bool twelveHour;

  /// Whether 12 AM 00 is 1440 ([compose]).
  final bool _midnightEnds;

  final bool Function(int minute)? _isEnabled;

  /// [_isEnabled]'s answers, by time over [minuteStep]; empty without it.
  final List<bool?> _answers;

  /// Whether [time] lies from [min] to [max].
  bool inRange(int time) {
    return time >= min && time <= max;
  }

  /// Whether [time] lies on the steps of the grid: 1440, or a multiple of
  /// [minuteStep].
  bool _onSteps(int time) {
    return time == CalendarDates.minutesPerDay || time % 60 % minuteStep == 0;
  }

  /// Whether [time] lies on the grid of times the rows offer.
  bool onGrid(int time) {
    return _onSteps(time);
  }

  /// Whether the picker offers [time]: it lies in range, on the grid, and
  /// [CalendarTimePicker.isEnabled] accepts it, which is asked only once
  /// the first two hold.
  ///
  /// On the 12-hour clock with a range holding both 0 and 1440, 12 AM 00
  /// picks 1440 only while the picker's value is 1440 ([compose]), so
  /// there whichever of 0 and 1440 it does not pick has no row, though
  /// [offers] may take it.
  bool offers(int time) {
    if (!inRange(time) || !onGrid(time)) {
      return false;
    }
    final isEnabled = _isEnabled;
    if (isEnabled == null) {
      return true;
    }
    return _answers[time ~/ minuteStep] ??= isEnabled(time);
  }

  /// The time of hour row [hour] and minute [minute]: on the 12-hour clock
  /// 12 AM 00 is 1440 where the range holds 1440 and not 0, and where it
  /// holds both while the picker's value is 1440.
  int compose(int hour, int minute) {
    final time = hour * 60 + minute;
    if (time == 0 && _midnightEnds) {
      return CalendarDates.minutesPerDay;
    }
    return time;
  }

  /// The hour row of [time]: its hour of the day, and for 1440 the row 24
  /// on the 24-hour clock and 12 AM, 0, on the 12-hour clock.
  int hourOf(int time) {
    if (time == CalendarDates.minutesPerDay) {
      return twelveHour ? 0 : 24;
    }
    return time ~/ 60;
  }

  /// Whether [time] lies in the PM half, 720 to 1439; 1440 shows as 12 AM.
  static bool isPm(int time) {
    return time >= 12 * 60 && time < CalendarDates.minutesPerDay;
  }

  /// The minutes of hour row [hour] on the Minute grid, ascending; the row
  /// 24 holds 0 alone.
  Iterable<int> minutesOf(int hour) sync* {
    if (hour == 24) {
      yield 0;
      return;
    }
    for (var minute = 0; minute < 60; minute += minuteStep) {
      yield minute;
    }
  }

  /// Whether hour row [hour] has a time on the grid in range.
  bool holdsHour(int hour) {
    for (final minute in minutesOf(hour)) {
      final time = compose(hour, minute);
      if (inRange(time) && onGrid(time)) {
        return true;
      }
    }
    return false;
  }

  /// Whether hour row [hour] has a time the picker [offers].
  bool offersHour(int hour) {
    for (final minute in minutesOf(hour)) {
      if (offers(compose(hour, minute))) {
        return true;
      }
    }
    return false;
  }

  /// The times on the grid from [min] to [max], ascending.
  Iterable<int> gridTimes() sync* {
    final step = minuteStep;
    for (var time = (min + step - 1) ~/ step * step; time <= max; time += step) {
      if (onGrid(time)) {
        yield time;
      }
    }
  }

  /// The [gridTimes] the picker [offers], ascending.
  Iterable<int> offeredTimes() {
    return gridTimes().where(offers);
  }

  /// The time Now picks at the minute after midnight [minute]: the latest
  /// time at or before it on the grid's steps, where the picker [offers]
  /// it; null where it does not, or where [minute] lies outside 0 to 1439.
  int? nowTime(int minute) {
    if (minute < 0 || minute >= CalendarDates.minutesPerDay) {
      return null;
    }
    var time = minute - minute % minuteStep;
    while (!_onSteps(time)) {
      time -= minuteStep;
    }
    return offers(time) ? time : null;
  }
}

/// One row of a column: an hour of the day (24 for the hour that holds
/// only 1440 on the 24-hour clock) or a minute of the hour.
@immutable
class _Row {
  const _Row(this.number, {required this.enabled, required this.isValue});

  final int number;

  /// Whether one of the row's times may be picked.
  final bool enabled;

  /// Whether the row is the value's.
  final bool isValue;

  /// Whether a column comes to rest on the row.
  bool get rests {
    return enabled || isValue;
  }
}

class _CalendarTimePickerState extends State<CalendarTimePicker>
    with TickerProviderStateMixin {
  /// Each column's offset: `k * _rowExtent` puts row `k` on the band.
  late final List<AnimationController> _offsets =
      List<AnimationController>.generate(_columnCount, (column) {
        return AnimationController.unbounded(vsync: this);
      });

  /// Each column's rows, the rows a held column had at the drag's down.
  final List<List<_Row>> _rows = List<List<_Row>>.filled(
    _columnCount,
    const <_Row>[],
  );

  /// The rows a sync computed for a held column, which its release takes.
  final List<List<_Row>?> _syncedRows = List<List<_Row>?>.filled(
    _columnCount,
    null,
  );

  /// The row each column rests on or moves to; null for a column with no
  /// rows.
  final List<int?> _targets = List<int?>.filled(_columnCount, null);

  /// The offset each column's running motion ends at.
  final List<double?> _ends = List<double?>.filled(_columnCount, null);

  final List<bool> _held = List<bool>.filled(_columnCount, false);

  /// Whether a user motion runs: one whose settle composes and reports.
  final List<bool> _moving = List<bool>.filled(_columnCount, false);

  /// Bumped as a user motion starts or ends, so the settle of a motion
  /// that was replaced or ended never runs.
  final List<int> _motionCounts = List<int>.filled(_columnCount, 0);

  final List<bool> _restAtDown = List<bool>.filled(_columnCount, false);
  final List<double> _offsetAtDown = List<double>.filled(_columnCount, 0.0);

  /// Whether a held column's release picks even where it moved nothing,
  /// as a settle or the toggle ran while it was held.
  final List<bool> _picksAtRelease = List<bool>.filled(_columnCount, false);

  /// The pointers down on the columns.
  final Set<int> _pointersDown = <int>{};

  /// The pointers down on the columns as [_endHolds] ended their holds,
  /// whose lift taps no row.
  final Set<int> _voidedPointers = <int>{};

  /// Whether the pointer last lifted from the columns was voided, so the
  /// row tap its lift fires picks nothing.
  bool _tapVoided = false;

  /// The time the picker shows.
  int? _time;

  /// Whether a new value waits for a held column's release.
  bool _valueWaits = false;

  bool _started = false;

  /// The toggle's half: PM where true.
  bool _pm = false;

  /// The half the Hour column's rows are of.
  bool _rowsPm = false;

  /// The hour the Minute column's rows are of.
  int? _minuteRowsHour;

  /// The rules of the widget since the last sync, which every row, target
  /// and flag reads the offered times from.
  late TimePickerRules _rules;

  bool _amEnabled = false;
  bool _pmEnabled = false;
  bool _nowEnabled = false;

  double _rowExtent = _leastRowExtent;
  double _toggleWidth = 0.0;
  Duration _motionDuration = Duration.zero;
  Curve _motionCurve = Curves.linear;

  FocusNode? _ownedHourNode;
  late final FocusNode _minuteNode = FocusNode(debugLabel: "Minute column");
  late final FocusNode _toggleNode = FocusNode(debugLabel: "AM/PM toggle");

  /// Whether the focus manager draws focus, so a focused control shows its
  /// ring.
  late final ValueNotifier<bool> _traditional = ValueNotifier<bool>(
    _isTraditional(FocusManager.instance.highlightMode),
  );

  Timer? _digitTimer;
  int? _digitColumn;
  int? _firstDigit;

  FocusNode get _hourNode {
    return widget.focusNode ??
        (_ownedHourNode ??= FocusNode(debugLabel: "Hour column"));
  }

  bool get _twelveHour {
    return _rules.twelveHour;
  }

  bool get _takesInput {
    return widget.onChanged != null;
  }

  static bool _isTraditional(FocusHighlightMode mode) {
    return mode == FocusHighlightMode.traditional;
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveMotion();
    _measure();
    _sync();
  }

  @override
  void didUpdateWidget(CalendarTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveMotion();
    if (oldWidget.focusNode != widget.focusNode) {
      if (widget.focusNode != null) {
        _ownedHourNode?.dispose();
        _ownedHourNode = null;
      }
    }
    if (oldWidget.onChanged != null && widget.onChanged == null) {
      _cancelDigitWait();
      _endHolds();
      _resetRules();
      _applyTime(widget.value, jump: false);
      return;
    }
    _sync();
  }

  @override
  void reassemble() {
    super.reassemble();
    _sync();
  }

  @override
  void dispose() {
    _cancelDigitWait();
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    _traditional.dispose();
    for (final offset in _offsets) {
      offset.dispose();
    }
    _ownedHourNode?.dispose();
    _minuteNode.dispose();
    _toggleNode.dispose();
    super.dispose();
  }

  void _highlightChanged(FocusHighlightMode mode) {
    _traditional.value = _isTraditional(mode);
  }

  /// Reads the theme's motion, the one every motion but a landing runs on.
  void _resolveMotion() {
    final theme = CalendarTheme.of(context);
    _motionDuration = theme.motionDuration;
    _motionCurve = theme.motionCurve;
  }

  /// Measures the row extent and the toggle's width, rescaling the columns
  /// where the extent changes.
  void _measure() {
    final theme = CalendarTheme.of(context);
    final strings = CalendarLocalizations.of(context);
    var style = DefaultTextStyle.of(context).style.merge(
      theme.timePickerRowStyle,
    );
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    painter.text = TextSpan(text: "00", style: style);
    painter.layout();
    final extent = math.max(_leastRowExtent, painter.height + _rowPadding);
    var widest = 0.0;
    for (final label in <String>[
      strings.timePickerAmLabel,
      strings.timePickerPmLabel,
    ]) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      widest = math.max(widest, painter.width);
    }
    painter.dispose();
    _toggleWidth = widest + _togglePadding;
    if (extent != _rowExtent) {
      _rescale(extent);
    }
  }

  /// Sets the row extent to [extent]: a column at rest moves to its target
  /// times [extent], and a held or moving one keeps its place between rows,
  /// a running motion restarting toward its target.
  void _rescale(double extent) {
    final old = _rowExtent;
    _rowExtent = extent;
    if (!_started) {
      return;
    }
    for (var column = 0; column < _columnCount; column++) {
      final offset = _offsets[column];
      final target = _targets[column];
      if (_held[column]) {
        offset.value = offset.value * extent / old;
        _offsetAtDown[column] = _offsetAtDown[column] * extent / old;
        continue;
      }
      if (!offset.isAnimating) {
        if (target != null) {
          offset.value = target * extent;
        }
        continue;
      }
      // Setting the value stops the running motion, whose future then
      // never completes, so _moveTo starts it again.
      offset.value = offset.value * extent / old;
      _ends[column] = null;
      _moveTo(column);
    }
  }

  /// Makes the rules of the widget, and from them which halves of the day
  /// have a time the picker offers, on the 12-hour clock, and whether
  /// Now's time is offered.
  void _resetRules() {
    final rules = TimePickerRules.of(widget);
    _rules = rules;
    var am = false;
    var pm = false;
    if (rules.twelveHour) {
      for (final time in rules.offeredTimes()) {
        if (TimePickerRules.isPm(time)) {
          pm = true;
        } else {
          am = true;
        }
        if (am && pm) {
          break;
        }
      }
    }
    _amEnabled = am;
    _pmEnabled = pm;
    _nowEnabled = _nowTime() != null;
  }

  /// Brings the picker to its widget: a new value, or with none the rows
  /// of the current targets.
  void _sync() {
    _resetRules();
    if (!_started) {
      _applyTime(widget.value, jump: true);
      _started = true;
    } else if (widget.value != _time) {
      if (_held.contains(true)) {
        _valueWaits = true;
        _refreshRows();
      } else {
        _valueWaits = false;
        _applyTime(widget.value, jump: false);
      }
    } else {
      _valueWaits = false;
      _refreshRows();
    }
  }

  // The times and the rows.

  int _minuteOf(int time) {
    return time % 60;
  }

  /// The rows of [column]: the Hour column's of the half [pm], the Minute
  /// column's of hour row [hour], each the value's row added where it is
  /// missing.
  List<_Row> _rowsOf(int column, {required bool pm, required int hour}) {
    final rules = _rules;
    final value = widget.value;
    final rows = <_Row>[];
    if (column == _hourColumn) {
      final valueHour =
          value == null ||
              (rules.twelveHour && TimePickerRules.isPm(value) != pm)
          ? null
          : rules.hourOf(value);
      final first = rules.twelveHour && pm ? 12 : 0;
      final last = rules.twelveHour
          ? first + 11
          : (rules.max == CalendarDates.minutesPerDay || valueHour == 24
                ? 24
                : 23);
      for (var number = first; number <= last; number++) {
        final isValue = number == valueHour;
        if (rules.holdsHour(number) || isValue) {
          rows.add(
            _Row(number, enabled: rules.offersHour(number), isValue: isValue),
          );
        }
      }
      return rows;
    }
    final valueMinute = value != null && rules.hourOf(value) == hour
        ? _minuteOf(value)
        : null;
    var valueAdded = valueMinute == null;
    for (final minute in rules.minutesOf(hour)) {
      if (!valueAdded && valueMinute! < minute) {
        rows.add(_Row(valueMinute, enabled: false, isValue: true));
        valueAdded = true;
      }
      final time = rules.compose(hour, minute);
      final isValue = minute == valueMinute;
      if (rules.inRange(time) || isValue) {
        rows.add(_Row(minute, enabled: rules.offers(time), isValue: isValue));
      }
      if (isValue) {
        valueAdded = true;
      }
    }
    if (!valueAdded) {
      rows.add(_Row(valueMinute!, enabled: false, isValue: true));
    }
    return rows;
  }

  /// The half of a null value: that of the first time offered, or with
  /// none of the first on the grid in range, or AM.
  bool _nullHalf() {
    final time =
        _rules.offeredTimes().firstOrNull ?? _rules.gridTimes().firstOrNull;
    return time != null && TimePickerRules.isPm(time);
  }

  /// What [number] compares by between rows: on the 12-hour clock an hour
  /// row's place in its half, so a row keeps its place across the halves.
  int _keyOf(int column, int number) {
    return column == _hourColumn && _twelveHour ? number % 12 : number;
  }

  int? _indexOf(int column, List<_Row> rows, int number) {
    final key = _keyOf(column, number);
    for (var index = 0; index < rows.length; index++) {
      if (_keyOf(column, rows[index].number) == key) {
        return index;
      }
    }
    return null;
  }

  /// The row of [rows] nearest [number] that [where] takes, the lower on a
  /// tie; null where it takes none.
  int? _nearestBy(
    int column,
    List<_Row> rows,
    int number,
    bool Function(_Row row) where,
  ) {
    final key = _keyOf(column, number);
    int? best;
    var distance = 0;
    for (var index = 0; index < rows.length; index++) {
      if (!where(rows[index])) {
        continue;
      }
      final next = (_keyOf(column, rows[index].number) - key).abs();
      if (best == null || next < distance) {
        best = index;
        distance = next;
      }
    }
    return best;
  }

  /// The row a column of [rows] rests on with no time: its first enabled
  /// row, or its first row with none.
  int? _firstResting(List<_Row> rows) {
    if (rows.isEmpty) {
      return null;
    }
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].enabled) {
        return index;
      }
    }
    return 0;
  }

  /// The target in [rows] of the row [oldRows]`[target]`: its new index
  /// where it still rests, else the resting row nearest it by number, the
  /// lower on a tie, else the first row.
  int? _retarget(int column, List<_Row> oldRows, int? target, List<_Row> rows) {
    if (rows.isEmpty) {
      return null;
    }
    if (target == null || target >= oldRows.length) {
      return _firstResting(rows);
    }
    final number = oldRows[target].number;
    final index = _indexOf(column, rows, number);
    if (index != null && rows[index].rests) {
      return index;
    }
    return _nearestBy(column, rows, number, (row) {
          return row.rests;
        }) ??
        0;
  }

  /// Shows [time]: ends every user motion without a report, sets the
  /// half, the rows and the targets, and moves each column that is not
  /// held to its row, at once where [jump].
  void _applyTime(int? time, {required bool jump}) {
    for (var column = 0; column < _columnCount; column++) {
      if (!_held[column]) {
        _motionCounts[column]++;
        _moving[column] = false;
      }
    }
    _time = time;
    final pm = time == null ? _nullHalf() : TimePickerRules.isPm(time);
    _pm = pm;
    _rowsPm = pm;
    final hourRows = _rowsOf(_hourColumn, pm: pm, hour: 0);
    var hourTarget = time == null
        ? null
        : _indexOf(_hourColumn, hourRows, _rules.hourOf(time));
    hourTarget ??= _firstResting(hourRows);
    final hour = hourTarget == null ? null : hourRows[hourTarget].number;
    final minuteRows = hour == null
        ? const <_Row>[]
        : _rowsOf(_minuteColumn, pm: pm, hour: hour);
    var minuteTarget = time == null
        ? null
        : _indexOf(_minuteColumn, minuteRows, _minuteOf(time));
    minuteTarget ??= _firstResting(minuteRows);
    _minuteRowsHour = hour;
    _setRows(_hourColumn, hourRows, hourTarget, jump: jump);
    _setRows(_minuteColumn, minuteRows, minuteTarget, jump: jump);
  }

  /// Computes the rows of the current targets again, as the bounds,
  /// [CalendarTimePicker.isEnabled] or the value may have changed.
  void _refreshRows() {
    final pm = _pm;
    final hourRows = _rowsOf(_hourColumn, pm: pm, hour: 0);
    final hourTarget = _retarget(
      _hourColumn,
      _rows[_hourColumn],
      _targets[_hourColumn],
      hourRows,
    );
    _rowsPm = pm;
    final hour = hourTarget == null ? null : hourRows[hourTarget].number;
    final minuteRows = hour == null
        ? const <_Row>[]
        : _rowsOf(_minuteColumn, pm: pm, hour: hour);
    final minuteTarget = _retarget(
      _minuteColumn,
      _rows[_minuteColumn],
      _targets[_minuteColumn],
      minuteRows,
    );
    _minuteRowsHour = hour;
    _setRows(_hourColumn, hourRows, hourTarget, jump: false);
    _setRows(_minuteColumn, minuteRows, minuteTarget, jump: false);
  }

  /// Gives [column] [rows] and [target]: a held column keeps its rows
  /// until its release; any other keeps the row nearest the band in place
  /// and moves to [target], unless [move] is false.
  void _setRows(
    int column,
    List<_Row> rows,
    int? target, {
    required bool jump,
    bool move = true,
  }) {
    if (_held[column]) {
      _syncedRows[column] = rows;
      return;
    }
    final offset = _offsets[column];
    final old = _rows[column];
    _rows[column] = rows;
    _targets[column] = target;
    if (target == null) {
      offset.stop();
      _ends[column] = null;
      return;
    }
    if (jump) {
      offset.value = target * _rowExtent;
      _ends[column] = null;
      return;
    }
    if (old.isNotEmpty) {
      final near = (offset.value / _rowExtent).round().clamp(0, old.length - 1);
      final number = old[near].number;
      final moved =
          (_indexOf(column, rows, number) ??
              _nearestBy(column, rows, number, (row) {
                return true;
              })!) -
          near;
      if (moved != 0) {
        // Setting the value stops the running motion, whose future then
        // never completes, so _moveTo starts it again.
        offset.value += moved * _rowExtent;
        _ends[column] = null;
      }
    }
    if (move) {
      _moveTo(column);
    }
  }

  /// Moves [column] to its target over the theme's motion: a user motion
  /// continues as the same one, its settle kept; a motion already running
  /// to the target runs on.
  void _moveTo(int column) {
    final target = _targets[column];
    if (target == null) {
      return;
    }
    final end = target * _rowExtent;
    final offset = _offsets[column];
    if (offset.isAnimating && _ends[column] == end) {
      return;
    }
    if (_moving[column]) {
      _settleWhenDone(column, _motionCounts[column], _animate(column, end));
      return;
    }
    if (offset.value != end || offset.isAnimating) {
      _animate(column, end);
    }
  }

  TickerFuture _animate(int column, double end) {
    _ends[column] = end;
    return _offsets[column].animateTo(
      end,
      duration: _motionDuration,
      curve: _motionCurve,
    );
  }

  // Motion and the settle.

  /// Starts a user motion of [column] to row [target].
  void _startUserMotion(int column, int target) {
    if (_held[column]) {
      return;
    }
    _targets[column] = target;
    final count = ++_motionCounts[column];
    _moving[column] = true;
    _settleWhenDone(column, count, _animate(column, target * _rowExtent));
  }

  void _settleWhenDone(int column, int count, TickerFuture future) {
    future.then((_) {
      if (!mounted || _motionCounts[column] != count || !_moving[column]) {
        return;
      }
      _settle(column);
    });
  }

  /// Brings [column] to rest on its target and, once no column is held and
  /// no user motion runs, composes the time and reports it.
  void _settle(int column) {
    _moving[column] = false;
    final target = _targets[column];
    if (target != null) {
      _offsets[column].value = target * _rowExtent;
      _ends[column] = null;
    }
    if (_held.contains(true) || _moving.contains(true)) {
      _deferToRelease();
      return;
    }
    _commit();
  }

  void _deferToRelease() {
    for (var column = 0; column < _columnCount; column++) {
      if (_held[column]) {
        _picksAtRelease[column] = true;
      }
    }
  }

  /// Ends every hold without a report: no release then picks or shows a
  /// value that waited for it, and no pointer down on the columns now taps
  /// a row at its lift.
  void _endHolds() {
    for (var column = 0; column < _columnCount; column++) {
      _held[column] = false;
      _syncedRows[column] = null;
      _picksAtRelease[column] = false;
    }
    _valueWaits = false;
    _voidedPointers.addAll(_pointersDown);
  }

  /// Composes the time from the targets, shows it, and reports it where
  /// it changed.
  void _commit() {
    final before = _time;
    final time = _composeTargets();
    setState(() {
      _applyTime(time, jump: false);
    });
    if (time != before) {
      widget.onChanged?.call(time);
    }
  }

  /// The time of the targets: where the hour or the half changed, the
  /// minute kept where the new hour accepts it and otherwise the nearest
  /// it accepts, the earlier on a tie; a half whose hour accepts none, the
  /// half's nearest; an hour that accepts none, the value.
  int? _composeTargets() {
    final rules = _rules;
    final hourTarget = _targets[_hourColumn];
    if (hourTarget == null) {
      return _time;
    }
    var hour = _rows[_hourColumn][hourTarget].number;
    if (rules.twelveHour) {
      hour = hour % 12 + (_pm ? 12 : 0);
    }
    final minuteTarget = _targets[_minuteColumn];
    final minute = minuteTarget == null
        ? 0
        : _rows[_minuteColumn][minuteTarget].number;
    final kept = rules.compose(hour, minute);
    if (hour == _minuteRowsHour && minuteTarget != null) {
      return rules.offers(kept) ? kept : widget.value;
    }
    if (rules.offers(kept)) {
      return kept;
    }
    int? nearest;
    var distance = 0;
    for (final other in rules.minutesOf(hour)) {
      final time = rules.compose(hour, other);
      final next = (other - minute).abs();
      if (rules.offers(time) && (nearest == null || next < distance)) {
        nearest = time;
        distance = next;
      }
    }
    if (nearest != null) {
      return nearest;
    }
    if (rules.twelveHour && _pm != _rowsPm) {
      for (final time in rules.offeredTimes()) {
        final next = (time - kept).abs();
        if (TimePickerRules.isPm(time) == _pm &&
            (nearest == null || next < distance)) {
          nearest = time;
          distance = next;
        }
      }
      if (nearest != null) {
        return nearest;
      }
    }
    return widget.value;
  }

  /// Shows and reports [time], from Now or Clear: every hold and user
  /// motion ends without a report.
  void _pickTime(int? time) {
    final before = _time;
    _endHolds();
    setState(() {
      _applyTime(time, jump: false);
    });
    if (time != before) {
      widget.onChanged?.call(time);
    }
  }

  /// Now's time ([TimePickerRules.nowTime]), or null with no
  /// [CalendarTimePicker.now].
  int? _nowTime() {
    final now = widget.now;
    if (now == null) {
      return null;
    }
    return _rules.nowTime(now());
  }

  void _pickNow() {
    if (!_takesInput) {
      return;
    }
    final time = _nowTime();
    if (time != null) {
      _pickTime(time);
    }
  }

  void _pickClear() {
    if (_takesInput) {
      _pickTime(null);
    }
  }

  /// Picks the half [pm] from the toggle, settling at once.
  void _pickHalf(bool pm) {
    if (!_takesInput || !(pm ? _pmEnabled : _amEnabled)) {
      return;
    }
    if (pm == _pm && pm == _rowsPm) {
      return;
    }
    if (_held.contains(true) || _moving.contains(true)) {
      _deferToRelease();
      setState(() {
        _pm = pm;
      });
      return;
    }
    _pm = pm;
    _commit();
  }

  // Gestures.

  void _pointerDown(PointerDownEvent event) {
    _pointersDown.add(event.pointer);
  }

  /// Forgets a lifted or cancelled pointer, noting whether [_endHolds]
  /// voided it. A lift reaches the columns' [Listener] before
  /// [GestureBinding.handleEvent], the last entry of its hit-test path,
  /// fires the row tap it makes, so that tap reads [_tapVoided] for its own
  /// pointer.
  void _pointerGone(PointerEvent event) {
    _pointersDown.remove(event.pointer);
    _tapVoided = _voidedPointers.remove(event.pointer);
  }

  void _dragDown(int column) {
    if (!_takesInput || _rows[column].isEmpty) {
      return;
    }
    final offset = _offsets[column];
    final target = _targets[column];
    _restAtDown[column] =
        !offset.isAnimating &&
        target != null &&
        offset.value == target * _rowExtent;
    offset.stop();
    _ends[column] = null;
    _motionCounts[column]++;
    _moving[column] = false;
    _held[column] = true;
    _picksAtRelease[column] = false;
    _offsetAtDown[column] = offset.value;
  }

  void _dragUpdate(int column, double delta) {
    if (!_held[column]) {
      return;
    }
    final offset = _offsets[column];
    final last = (_rows[column].length - 1) * _rowExtent;
    offset.value = clampDouble(offset.value - delta, 0.0, last);
  }

  /// Ends [column]'s hold, its offset moving at [velocity].
  void _release(int column, double velocity) {
    if (!_held[column]) {
      return;
    }
    _held[column] = false;
    if (_valueWaits) {
      if (!_held.contains(true)) {
        _valueWaits = false;
        setState(() {
          _applyTime(widget.value, jump: false);
        });
      }
      return;
    }
    final picks = _picksAtRelease[column];
    _picksAtRelease[column] = false;
    final synced = _syncedRows[column];
    if (synced != null) {
      _syncedRows[column] = null;
      final target = _retarget(
        column,
        _rows[column],
        _targets[column],
        synced,
      );
      setState(() {
        _setRows(column, synced, target, jump: false, move: false);
      });
    }
    final rows = _rows[column];
    if (rows.isEmpty) {
      return;
    }
    final offset = _offsets[column];
    if (!picks &&
        _restAtDown[column] &&
        offset.value == _offsetAtDown[column]) {
      return;
    }
    final place = offset.value / _rowExtent;
    final on = place.round();
    if (on == place && on >= 0 && on < rows.length && rows[on].rests) {
      _targets[column] = on;
      _settle(column);
      return;
    }
    _land(column, velocity);
  }

  /// Lands [column] on the resting row nearest where the ambient scroll
  /// physics would bring it from [velocity], the lower on a tie.
  void _land(int column, double velocity) {
    final rows = _rows[column];
    final offset = _offsets[column];
    final start = offset.value;
    final extent = _rowExtent;
    final physics = ScrollConfiguration.of(context).getScrollPhysics(context);
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0.0,
      maxScrollExtent: (rows.length - 1) * extent,
      pixels: start,
      viewportDimension: _shownRows * extent,
      axisDirection: AxisDirection.down,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
    );
    final simulation = physics.createBallisticSimulation(metrics, velocity);
    final place = (simulation?.x(double.infinity) ?? start) / extent;
    int? target;
    var distance = 0.0;
    for (var index = 0; index < rows.length; index++) {
      final next = (index - place).abs();
      if (rows[index].rests && (target == null || next < distance)) {
        target = index;
        distance = next;
      }
    }
    target ??= _targets[column] ?? 0;
    _targets[column] = target;
    final count = ++_motionCounts[column];
    _moving[column] = true;
    final end = target * extent;
    _ends[column] = end;
    final tolerance = physics.toleranceFor(metrics);
    final TickerFuture future;
    if (_motionDuration == Duration.zero) {
      future = offset.animateTo(end, duration: Duration.zero);
    } else if (end != start &&
        (end - start).sign == velocity.sign &&
        velocity.abs() > tolerance.velocity) {
      future = offset.animateWith(
        FrictionSimulation.through(
          start,
          end,
          velocity,
          tolerance.velocity * velocity.sign,
        ),
      );
    } else {
      future = offset.animateWith(
        SpringSimulation(
          physics.spring,
          start,
          end,
          velocity,
          tolerance: tolerance,
        ),
      );
    }
    _settleWhenDone(column, count, future);
  }

  void _tapRow(int column, int number) {
    if (!_takesInput || _tapVoided) {
      return;
    }
    final index = _indexOf(column, _rows[column], number);
    if (index != null && _rows[column][index].enabled) {
      _startUserMotion(column, index);
    }
  }

  void _wheel(int column, PointerSignalEvent event) {
    if (!_takesInput || event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta.dy;
    if (delta == 0.0 || _enabledFrom(column, delta > 0.0 ? 1 : -1, 1) == null) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final next = _enabledFrom(column, delta > 0.0 ? 1 : -1, 1);
      if (_takesInput && next != null) {
        _startUserMotion(column, next);
      }
    });
  }

  // Keys.

  /// The enabled row [count] enabled rows from [column]'s target the way
  /// [direction] goes, stopping at the last; null where there is none that
  /// way.
  int? _enabledFrom(int column, int direction, int count) {
    final rows = _rows[column];
    final target = _targets[column];
    if (target == null) {
      return null;
    }
    int? found;
    var left = count;
    for (
      var index = target + direction;
      index >= 0 && index < rows.length && left > 0;
      index += direction
    ) {
      if (rows[index].enabled) {
        found = index;
        left--;
      }
    }
    return found;
  }

  int? _firstEnabled(int column, {required bool last}) {
    final rows = _rows[column];
    int? found;
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].enabled) {
        found = index;
        if (!last) {
          break;
        }
      }
    }
    return found;
  }

  /// The number a row shows: on the 12-hour clock an hour row's 12, then
  /// 1 to 11.
  int _shownNumber(int column, int number) {
    if (column == _hourColumn && _twelveHour) {
      return number % 12 == 0 ? 12 : number % 12;
    }
    return number;
  }

  /// Steps [column] one enabled row the way [direction] goes; with no time
  /// shown, picks the row it rests on.
  void _stepColumn(int column, int direction) {
    final target = _targets[column];
    if (!_takesInput || target == null) {
      return;
    }
    if (_time == null) {
      _startUserMotion(column, target);
      return;
    }
    final next = _enabledFrom(column, direction, 1);
    if (next != null) {
      _startUserMotion(column, next);
    }
  }

  FocusNode? _neighbourOf(int column, {required bool right}) {
    if (column == _hourColumn) {
      return right ? _minuteNode : null;
    }
    if (right) {
      return _twelveHour ? _toggleNode : null;
    }
    return _hourNode;
  }

  static int? _digitOf(LogicalKeyboardKey key) {
    const digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const numpad = <LogicalKeyboardKey>[
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    final digit = digits.indexOf(key);
    if (digit >= 0) {
      return digit;
    }
    final pad = numpad.indexOf(key);
    return pad >= 0 ? pad : null;
  }

  /// A column's keys. A key the column knows is handled whether or not it
  /// moves anything, so it never moves the focus out of the picker; Left
  /// and Right are ignored where no control lies that way.
  KeyEventResult _handleColumnKey(int column, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (!_takesInput) {
        return KeyEventResult.handled;
      }
      final neighbour = _neighbourOf(
        column,
        right: key == LogicalKeyboardKey.arrowRight,
      );
      if (neighbour == null) {
        return KeyEventResult.ignored;
      }
      neighbour.requestFocus();
      return KeyEventResult.handled;
    }
    if (_twelveHour &&
        (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.keyP)) {
      if (event is KeyDownEvent) {
        _pickHalf(key == LogicalKeyboardKey.keyP);
      }
      return KeyEventResult.handled;
    }
    final digit = _digitOf(key);
    if (digit != null) {
      if (_takesInput && event is KeyDownEvent) {
        _typeDigit(column, digit);
      }
      return KeyEventResult.handled;
    }
    final target = _targets[column];
    int? next;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_time == null) {
        next = target;
      } else {
        next = _enabledFrom(column, 1, 1);
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_time == null) {
        next = target;
      } else {
        next = _enabledFrom(column, -1, 1);
      }
    } else if (key == LogicalKeyboardKey.home) {
      next = _firstEnabled(column, last: false);
    } else if (key == LogicalKeyboardKey.end) {
      next = _firstEnabled(column, last: true);
    } else if (key == LogicalKeyboardKey.pageDown) {
      next = _enabledFrom(column, 1, _shownRows);
    } else if (key == LogicalKeyboardKey.pageUp) {
      next = _enabledFrom(column, -1, _shownRows);
    } else {
      return KeyEventResult.ignored;
    }
    if (_takesInput &&
        next != null &&
        (next != target || _time == null || _offsets[column].isAnimating)) {
      _startUserMotion(column, next);
    }
    return KeyEventResult.handled;
  }

  void _typeDigit(int column, int digit) {
    final first = _firstDigit;
    final same = _digitColumn == column;
    _cancelDigitWait();
    if (first != null && same && _pickNumber(column, first * 10 + digit)) {
      return;
    }
    final waits = _rows[column].any((row) {
      return row.enabled && _shownNumber(column, row.number) ~/ 10 == digit;
    });
    if (!waits) {
      _pickNumber(column, digit);
      return;
    }
    _firstDigit = digit;
    _digitColumn = column;
    _digitTimer = Timer(_digitWait, () {
      _digitTimer = null;
      _firstDigit = null;
      _digitColumn = null;
      if (mounted && _takesInput) {
        _pickNumber(column, digit);
      }
    });
  }

  /// Picks the enabled row of [column] that shows [number].
  bool _pickNumber(int column, int number) {
    final rows = _rows[column];
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].enabled &&
          _shownNumber(column, rows[index].number) == number) {
        _startUserMotion(column, index);
        return true;
      }
    }
    return false;
  }

  void _cancelDigitWait() {
    _digitTimer?.cancel();
    _digitTimer = null;
    _firstDigit = null;
    _digitColumn = null;
  }

  KeyEventResult _handleToggleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_takesInput) {
        _minuteNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    bool? pm;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyA) {
      pm = false;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyP) {
      pm = true;
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      pm = !_pm;
    } else {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _pickHalf(pm);
    }
    return KeyEventResult.handled;
  }

  // Building.

  String _labelOf(CalendarLocalizations strings, int column, int number) {
    return column == _hourColumn
        ? strings.timePickerHour(number, widget.hourLabelFormat)
        : strings.timePickerMinute(number);
  }

  /// [colour] at the theme's disabled opacity where not [enabled].
  static Color _faded(CalendarThemeData theme, Color colour, bool enabled) {
    return enabled
        ? colour
        : colour.withValues(alpha: colour.a * theme.disabledOpacity);
  }

  /// The text of [row] of [column], drawn in the theme's text colour, a
  /// disabled row's at the disabled opacity.
  Widget _rowText(
    CalendarThemeData theme,
    CalendarLocalizations strings,
    int column,
    _Row row,
  ) {
    return Text(
      _labelOf(strings, column, row.number),
      maxLines: 1,
      softWrap: false,
      style: theme.timePickerRowStyle.copyWith(
        color: _faded(theme, theme.text, row.enabled),
      ),
    );
  }

  /// [child] with the theme's focus ring while the focus under it is drawn.
  Widget _ring(Widget child) {
    return ListenableBuilder(
      listenable: _traditional,
      child: child,
      builder: (context, child) {
        final theme = CalendarTheme.of(context);
        final shown = _traditional.value && Focus.of(context).hasFocus;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: shown
              ? BoxDecoration(
                  border: Border.all(color: theme.primary, width: _ringWidth),
                  borderRadius: BorderRadius.circular(_controlRadius),
                )
              : const BoxDecoration(),
          child: child,
        );
      },
    );
  }

  Widget _column(
    CalendarThemeData theme,
    CalendarLocalizations strings,
    int column,
  ) {
    final rows = _rows[column];
    final takesInput = _takesInput && rows.isNotEmpty;
    final target = _targets[column];
    final shows = _time != null && target != null;
    final next = shows ? _enabledFrom(column, 1, 1) : null;
    final previous = shows ? _enabledFrom(column, -1, 1) : null;
    Widget box = _TimeColumn(
      offset: _offsets[column],
      rowExtent: _rowExtent,
      fadeColor: theme.surface,
      children: <Widget>[
        for (final row in rows)
          GestureDetector(
            key: column == _hourColumn
                ? timePickerHourRowKey(row.number)
                : timePickerMinuteRowKey(row.number),
            behavior: HitTestBehavior.opaque,
            onTap: takesInput && row.enabled
                ? () {
                    _tapRow(column, row.number);
                  }
                : null,
            child: Center(child: _rowText(theme, strings, column, row)),
          ),
      ],
    );
    box = ExcludeSemantics(child: box);
    if (takesInput) {
      box = GestureDetector(
        onVerticalDragDown: (details) {
          _dragDown(column);
        },
        onVerticalDragUpdate: (details) {
          _dragUpdate(column, details.primaryDelta ?? 0.0);
        },
        onVerticalDragEnd: (details) {
          _release(column, -(details.primaryVelocity ?? 0.0));
        },
        onVerticalDragCancel: () {
          _release(column, 0.0);
        },
        child: box,
      );
    }
    box = Listener(
      onPointerSignal: (event) {
        _wheel(column, event);
      },
      child: box,
    );
    return Semantics(
      key: column == _hourColumn
          ? timePickerHourColumnKey
          : timePickerMinuteColumnKey,
      container: true,
      label: column == _hourColumn
          ? strings.timePickerHourLabel
          : strings.timePickerMinuteLabel,
      value: shows ? _labelOf(strings, column, rows[target].number) : null,
      increasedValue: next == null
          ? null
          : _labelOf(strings, column, rows[next].number),
      decreasedValue: previous == null
          ? null
          : _labelOf(strings, column, rows[previous].number),
      onIncrease: !takesInput || (shows && next == null)
          ? null
          : () {
              _stepColumn(column, 1);
            },
      onDecrease: !takesInput || previous == null
          ? null
          : () {
              _stepColumn(column, -1);
            },
      child: FocusTraversalOrder(
        order: NumericFocusOrder(column + 1.0),
        child: Focus(
          focusNode: column == _hourColumn ? _hourNode : _minuteNode,
          skipTraversal: !_takesInput,
          onKeyEvent: (node, event) {
            return _handleColumnKey(column, event);
          },
          child: _ring(box),
        ),
      ),
    );
  }

  Widget _toggle(CalendarThemeData theme, CalendarLocalizations strings) {
    Widget half(bool pm) {
      final selected = _pm == pm;
      final enabled = pm ? _pmEnabled : _amEnabled;
      final colour = selected ? theme.onPrimary : theme.text;
      return Semantics(
        key: pm ? timePickerPmKey : timePickerAmKey,
        container: true,
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: selected,
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _takesInput && enabled
              ? () {
                  _pickHalf(pm);
                }
              : null,
          child: Container(
            width: _toggleWidth,
            height: _rowExtent,
            alignment: Alignment.center,
            decoration: selected
                ? BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(_controlRadius),
                  )
                : null,
            child: Text(
              pm ? strings.timePickerPmLabel : strings.timePickerAmLabel,
              maxLines: 1,
              softWrap: false,
              style: theme.timePickerRowStyle.copyWith(
                color: _faded(theme, colour, enabled),
              ),
            ),
          ),
        ),
      );
    }

    return FocusTraversalOrder(
      order: const NumericFocusOrder(3.0),
      child: Focus(
        focusNode: _toggleNode,
        skipTraversal: !_takesInput,
        onKeyEvent: (node, event) {
          return _handleToggleKey(event);
        },
        child: _ring(
          Semantics(
            key: timePickerToggleKey,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[half(false), half(true)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({
    required CalendarThemeData theme,
    required Key key,
    required String label,
    required double order,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: Focus(
        skipTraversal: !enabled,
        onKeyEvent: (node, event) {
          final key = event.logicalKey;
          if (event is KeyDownEvent &&
              (key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.numpadEnter ||
                  key == LogicalKeyboardKey.space)) {
            if (enabled) {
              onTap();
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _ring(
          Semantics(
            key: key,
            container: true,
            button: true,
            enabled: enabled,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.actionLabelStyle.copyWith(
                    color: _faded(theme, theme.primary, enabled),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = CalendarTheme.of(context);
    final strings = CalendarLocalizations.of(context);
    final extent = _rowExtent;
    final headerStyle = theme.timePickerHeaderStyle.copyWith(
      color: theme.textSecondary,
    );
    final hasFooter = widget.now != null || widget.clearable;
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(color: theme.outline),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bounded = constraints.hasBoundedWidth;
              Widget sized(Widget child) {
                return bounded
                    ? Expanded(child: child)
                    : SizedBox(width: _unboundedColumnWidth, child: child);
              }

              Widget header(String label) {
                return sized(
                  ExcludeSemantics(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: headerStyle,
                    ),
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: bounded
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: <Widget>[
                  Listener(
                    onPointerDown: _pointerDown,
                    onPointerUp: _pointerGone,
                    onPointerCancel: _pointerGone,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            mainAxisSize: bounded
                                ? MainAxisSize.max
                                : MainAxisSize.min,
                            children: <Widget>[
                              header(strings.timePickerHourLabel),
                              header(strings.timePickerMinuteLabel),
                              if (_twelveHour) SizedBox(width: _toggleWidth),
                            ],
                          ),
                          SizedBox(
                            height: _shownRows * extent,
                            child: Stack(
                              children: <Widget>[
                                if (_time != null)
                                  Positioned(
                                    key: timePickerBandKey,
                                    left: 0.0,
                                    right: 0.0,
                                    top: 2 * extent,
                                    height: extent,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: theme.primaryTint,
                                        borderRadius: BorderRadius.circular(
                                          _controlRadius,
                                        ),
                                      ),
                                    ),
                                  ),
                                Row(
                                  mainAxisSize: bounded
                                      ? MainAxisSize.max
                                      : MainAxisSize.min,
                                  children: <Widget>[
                                    sized(
                                      _column(theme, strings, _hourColumn),
                                    ),
                                    sized(
                                      _column(theme, strings, _minuteColumn),
                                    ),
                                    if (_twelveHour)
                                      SizedBox(
                                        width: _toggleWidth,
                                        child: Center(
                                          child: _toggle(theme, strings),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (hasFooter)
                    Row(
                      key: timePickerFooterKey,
                      mainAxisSize: bounded
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (widget.now != null)
                          _action(
                            theme: theme,
                            key: timePickerNowKey,
                            label: strings.timePickerNowLabel,
                            order: 4.0,
                            enabled: _takesInput && _nowEnabled,
                            onTap: _pickNow,
                          ),
                        if (widget.clearable)
                          _action(
                            theme: theme,
                            key: timePickerClearKey,
                            label: strings.timePickerClearLabel,
                            order: 5.0,
                            enabled: _takesInput,
                            onTap: _pickClear,
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A column of rows over [offset], which paints row `i` at
/// `(2 + i) * rowExtent - offset.value` and repaints, with no layout, as
/// [offset] changes.
class _TimeColumn extends MultiChildRenderObjectWidget {
  const _TimeColumn({
    required this.offset,
    required this.rowExtent,
    required this.fadeColor,
    required super.children,
  });

  final Animation<double> offset;
  final double rowExtent;
  final Color fadeColor;

  @override
  _RenderTimeColumn createRenderObject(BuildContext context) {
    return _RenderTimeColumn(
      offset: offset,
      rowExtent: rowExtent,
      fadeColor: fadeColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTimeColumn renderObject,
  ) {
    renderObject
      ..offset = offset
      ..rowExtent = rowExtent
      ..fadeColor = fadeColor;
  }
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {
  /// The row's place in its column.
  int index = 0;
}

class _RenderTimeColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  _RenderTimeColumn({
    required Animation<double> offset,
    required double rowExtent,
    required Color fadeColor,
  }) : _offset = offset,
       _rowExtent = rowExtent,
       _fadeColor = fadeColor;

  Animation<double> _offset;

  set offset(Animation<double> value) {
    if (identical(value, _offset)) {
      return;
    }
    if (attached) {
      _offset.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _offset = value;
    markNeedsPaint();
  }

  double _rowExtent;

  set rowExtent(double value) {
    if (value == _rowExtent) {
      return;
    }
    _rowExtent = value;
    markNeedsLayout();
  }

  Color _fadeColor;

  set fadeColor(Color value) {
    if (value == _fadeColor) {
      return;
    }
    _fadeColor = value;
    markNeedsPaint();
  }

  /// The rows in order, filled at each layout.
  final List<RenderBox> _rows = <RenderBox>[];

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  /// The fades, made for [_fadeSize], [_fadeExtent] and [_fadeFor].
  Paint? _topFade;
  Paint? _bottomFade;
  Rect _topRect = Rect.zero;
  Rect _bottomRect = Rect.zero;
  Size? _fadeSize;
  double? _fadeExtent;
  Color? _fadeFor;

  /// The row [_hitRow] tests, so a hit test makes no closure per row.
  RenderBox? _hitChild;
  late final BoxHitTest _hitRowTest = _hitRow;

  /// [_paintRows] torn off once, so a paint makes no closure.
  late final PaintingContextCallback _paintRowsCallback = _paintRows;

  @override
  bool get isRepaintBoundary {
    return true;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) {
      child.parentData = _RowParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _offset.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _disposeFades();
    super.dispose();
  }

  void _disposeFades() {
    _topFade?.shader?.dispose();
    _bottomFade?.shader?.dispose();
    _topFade = null;
    _bottomFade = null;
  }

  Size _sizeFor(BoxConstraints constraints) {
    return constraints.constrain(
      Size(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _unboundedColumnWidth,
        _shownRows * _rowExtent,
      ),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _shownRows * _rowExtent;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _shownRows * _rowExtent;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return _sizeFor(constraints);
  }

  @override
  void performLayout() {
    size = _sizeFor(constraints);
    _rows.clear();
    final rowConstraints = BoxConstraints.tight(Size(size.width, _rowExtent));
    var child = firstChild;
    var index = 0;
    while (child != null) {
      child.layout(rowConstraints);
      final parentData = child.parentData! as _RowParentData;
      parentData.index = index;
      parentData.offset = Offset(0.0, (2 + index) * _rowExtent);
      _rows.add(child);
      index++;
      child = parentData.nextSibling;
    }
  }

  /// The first and the last row whose box meets the column at the offset
  /// [place]: those `i` with `(2 + i) * rowExtent - place` strictly inside
  /// one row of the column's edges, at most six.
  int _firstShown(double place) {
    return math.max(0, (place / _rowExtent - 3).floor() + 1);
  }

  int _lastShown(double place) {
    return math.min(_rows.length - 1, (place / _rowExtent + 3).ceil() - 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintRowsCallback,
      oldLayer: _clip.layer,
    );
  }

  void _paintRows(PaintingContext context, Offset offset) {
    final place = _offset.value;
    final last = _lastShown(place);
    for (var index = _firstShown(place); index <= last; index++) {
      context.paintChild(
        _rows[index],
        offset.translate(0.0, (2 + index) * _rowExtent - place),
      );
    }
    _paintFades(context.canvas, offset, place);
  }

  /// Fades the rows into [_fadeColor] at each edge rows lie past, sliding
  /// each fade in from past its edge over the row before it is needed.
  void _paintFades(Canvas canvas, Offset offset, double place) {
    final extent = _rowExtent;
    final top = clampDouble((place - 2 * extent) / extent, 0.0, 1.0);
    final bottom = clampDouble(
      ((_rows.length - 3) * extent - place) / extent,
      0.0,
      1.0,
    );
    if (top <= 0.0 && bottom <= 0.0) {
      return;
    }
    if (_topFade == null ||
        _fadeSize != size ||
        _fadeExtent != extent ||
        _fadeFor != _fadeColor) {
      _disposeFades();
      final clear = _fadeColor.withValues(alpha: 0.0);
      _topRect = Rect.fromLTWH(0.0, 0.0, size.width, extent);
      _bottomRect = Rect.fromLTWH(0.0, 4 * extent, size.width, extent);
      _topFade = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[_fadeColor, clear],
        ).createShader(_topRect);
      _bottomFade = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[clear, _fadeColor],
        ).createShader(_bottomRect);
      _fadeSize = size;
      _fadeExtent = extent;
      _fadeFor = _fadeColor;
    }
    if (top > 0.0) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy - (1.0 - top) * extent);
      canvas.drawRect(_topRect, _topFade!);
      canvas.restore();
    }
    if (bottom > 0.0) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy + (1.0 - bottom) * extent);
      canvas.drawRect(_bottomRect, _bottomFade!);
      canvas.restore();
    }
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_rows.isEmpty) {
      return false;
    }
    final place = _offset.value;
    final first = _firstShown(place);
    for (var index = _lastShown(place); index >= first; index--) {
      _hitChild = _rows[index];
      final hit = result.addWithPaintOffset(
        offset: Offset(0.0, (2 + index) * _rowExtent - place),
        position: position,
        hitTest: _hitRowTest,
      );
      if (hit) {
        _hitChild = null;
        return true;
      }
    }
    _hitChild = null;
    return false;
  }

  bool _hitRow(BoxHitTestResult result, Offset position) {
    return _hitChild!.hitTest(result, position: position);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final index = (child.parentData! as _RowParentData).index;
    transform.translateByDouble(
      0.0,
      (2 + index) * _rowExtent - _offset.value,
      0.0,
      1.0,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    return Offset.zero & size;
  }
}
