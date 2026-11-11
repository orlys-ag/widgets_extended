/// The app bar's Today pill, which shows while a tap on it would change
/// what the calendar shows.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'harbor_theme.dart';

/// The key of the app bar's Today pill.
const ValueKey<String> todayPillKey = ValueKey<String>("today-pill");

/// A filled pill reading "Today" that reports [onPressed], filled with the
/// colour its app bar gives its actions and written in the bar's fill.
///
/// It shows while Today would change what the calendar shows: while the
/// selected day of [controller] is not the shown day nearest today, which
/// is the day Today selects, or the calendar does not show its selected
/// day ([CalendarController.showsSelectedDay]). It fades in and out over
/// [harborMotionDuration] on [harborMotionCurve], keeping its width in the
/// app bar, and while it is hidden it takes no pointer, no focus and no
/// screen reader's attention. It reads [today] again on each notify of
/// [controller], each new widget and the start of each minute of [clock],
/// so it shows once midnight leaves the selected day behind.
class TodayPill extends StatefulWidget {
  const TodayPill({
    super.key,
    required this.controller,
    required this.today,
    required this.weekdays,
    required this.clock,
    required this.onPressed,
  });

  /// The calendar's controller, holding a selected day before a calendar
  /// binds it.
  final CalendarController controller;

  /// Reads the day the calendar marks as today when called.
  final DateTime Function() today;

  /// The weekdays the calendar shows.
  final CalendarWeekdaySet weekdays;

  /// Reads the current time, whose minutes the pill reads [today] again
  /// at the start of.
  final DateTime Function() clock;

  final VoidCallback onPressed;

  @override
  State<TodayPill> createState() {
    return _TodayPillState();
  }
}

class _TodayPillState extends State<TodayPill> {
  late bool _shown = _readShown();

  /// Fires at the start of the next minute of [TodayPill.clock].
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_follow);
    _scheduleMinute();
  }

  @override
  void didUpdateWidget(TodayPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_follow);
      widget.controller.addListener(_follow);
    }
    if (widget.clock != oldWidget.clock) {
      _minute?.cancel();
      _scheduleMinute();
    }
    // A new zone moves today, and new weekdays the day Today selects.
    _shown = _readShown();
  }

  @override
  void dispose() {
    _minute?.cancel();
    widget.controller.removeListener(_follow);
    super.dispose();
  }

  bool _readShown() {
    final controller = widget.controller;
    if (!controller.showsSelectedDay) {
      return true;
    }
    final target = CalendarDates.shownDayNear(widget.today(), widget.weekdays);
    return CalendarDates.dayNumber(controller.selectedDay) !=
        CalendarDates.dayNumber(target);
  }

  void _follow() {
    final shown = _readShown();
    if (shown != _shown) {
      setState(() {
        _shown = shown;
      });
    }
  }

  void _scheduleMinute() {
    final now = widget.clock();
    final intoMinute = Duration(
      seconds: now.second,
      milliseconds: now.millisecond,
      microseconds: now.microsecond,
    );
    _minute = Timer(const Duration(minutes: 1) - intoMinute, () {
      _follow();
      _scheduleMinute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final theme = Theme.of(context);
    final fill = IconTheme.of(context).color;
    final text = theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
    // An app bar stretches its actions to its height; the pill keeps its
    // own, centred in it.
    return ExcludeFocus(
      excluding: !shown,
      child: ExcludeSemantics(
        excluding: !shown,
        child: IgnorePointer(
          ignoring: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1.0 : 0.0,
            duration: harborMotionDuration,
            curve: harborMotionCurve,
            child: Center(
              child: TextButton(
                key: todayPillKey,
                style: TextButton.styleFrom(
                  backgroundColor: fill,
                  foregroundColor: text,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  minimumSize: const Size(0.0, 32.0),
                  textStyle: const TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: widget.onPressed,
                child: const Text("Today"),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
