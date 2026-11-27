/// The date-time picker through the package barrel: the date view it
/// opens on and the view control at the end of its header, the control's
/// look and what a screen reader hears of it, a switch to the time view and
/// back over the theme's motion, the control's place in both views, the
/// view it opens on, a tap on a day that keeps the date view, the state the
/// date view keeps, what a tap on a day and a pick of a time report, a
/// picked time's day as a day start on the store's clock, the time a tap on
/// a day keeps or moves to, the times the clock of the store's zone skips,
/// a minute that turns null, a column held as the view switches, the focus
/// a switch moves, the parameters it hands its pickers, the theme it draws
/// in, the values its constructor refuses and its days at large text.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show OpacityLayer, RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/composition/calendar_date_time_picker.dart'
    show
        dateTimePickerDateSegmentKey,
        dateTimePickerTimeKey,
        dateTimePickerTimeSegmentKey;
import 'package:widgets_extended/calendar/composition/calendar_header.dart'
    show CalendarHeaderRow;
import 'package:widgets_extended/calendar/views/day_cell.dart' show DayCell;
import 'package:widgets_extended/calendar/views/time_picker.dart'
    show timePickerHourColumnKey, timePickerHourRowKey;
import 'package:widgets_extended/widgets_extended.dart';

import '../../scheduling/zones.dart';
import '../recording_errors.dart';
import '../view_doubles.dart';

final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);

/// A theme whose motion is 400 ms on a linear curve.
final CalendarThemeData motionTheme = CalendarThemeData(
  motionDuration: const Duration(milliseconds: 400),
  motionCurve: Curves.linear,
);

/// [picker] under a MaterialApp, at the top of a 400-pixel-wide column, in
/// [theme] where given.
Widget app(Widget picker, {CalendarThemeData? theme}) {
  Widget body = Align(
    alignment: Alignment.topCenter,
    child: SizedBox(width: 400.0, child: picker),
  );
  if (theme != null) {
    body = CalendarTheme(data: theme, child: body);
  }
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: Scaffold(body: body),
  );
}

/// The day cell of [day], as a screen reader names a day with no badge.
Finder dayCell(DateTime day) {
  return find.bySemanticsLabel(
    const DefaultCalendarLocalizations().dayWithBadges(day, const <String?>[]),
  );
}

/// The [DayCell] of [day], found by its widget, so that whether it takes a
/// pointer is checked apart from what a screen reader hears of it.
Finder dayTarget(DateTime day) {
  return find.byWidgetPredicate((widget) {
    return widget is DayCell &&
        widget.day.year == day.year &&
        widget.day.month == day.month &&
        widget.day.day == day.day;
  });
}

/// The labels of the segments of the shown view's control.
final Finder dateSegment = find.byKey(dateTimePickerDateSegmentKey);
final Finder timeSegment = find.byKey(dateTimePickerTimeSegmentKey);

final Finder timeView = find.byKey(dateTimePickerTimeKey);

final Finder dayPicker = find.byType(CalendarDayPicker<String>);

/// The header row of the view [view] finds.
Finder headerRowOf(Finder view) {
  return find
      .descendant(of: view, matching: find.byType(CalendarHeaderRow))
      .first;
}

/// The tap target of the segment whose label [label] finds.
Finder segmentOf(Finder label) {
  return find.ancestor(of: label, matching: find.byType(InkWell)).first;
}

/// The track of the shown view's control.
Finder control() {
  return find
      .ancestor(
        of: dateSegment,
        matching: find.byWidgetPredicate((widget) {
          return widget is DecoratedBox &&
              widget.decoration is ShapeDecoration &&
              (widget.decoration as ShapeDecoration).shape is StadiumBorder;
        }),
      )
      .first;
}

/// The pill under the shown view's segment.
Finder pill() {
  return find.descendant(
    of: control(),
    matching: find.byType(FractionallySizedBox),
  );
}

/// The fill of the box [box] finds.
Color? fillOf(WidgetTester tester, Finder box) {
  return (tester.widget<DecoratedBox>(box).decoration as ShapeDecoration).color;
}

/// The fill of the pill.
Color? pillFill(WidgetTester tester) {
  return fillOf(
    tester,
    find.descendant(of: pill(), matching: find.byType(DecoratedBox)),
  );
}

/// The colour of the label [label] finds.
Color? inkOf(WidgetTester tester, Finder label) {
  return tester.widget<Text>(label).style!.color;
}

/// The opacity of the view that holds what [finder] finds.
double viewOpacity(WidgetTester tester, Finder finder) {
  return tester
      .widget<FadeTransition>(
        find.ancestor(of: finder, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;
}

double pickerHeight(WidgetTester tester) {
  return tester.getSize(find.byType(CalendarDateTimePicker<String>)).height;
}

/// The theme the picker draws in.
CalendarThemeData pickerTheme(WidgetTester tester) {
  return CalendarTheme.of(tester.element(dayPicker));
}

/// Whether the row keyed [key] of the time picker takes a tap.
bool rowTakesTap(WidgetTester tester, Key key) {
  return tester.widget<GestureDetector>(find.byKey(key)).onTap != null;
}

/// Whether the focus lies on the segment whose label [label] finds.
bool focusedOn(Finder label) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) {
    return false;
  }
  // The segment's own node, under its InkWell: a scope above the picker
  // holds the focus of no segment, though it is an ancestor of each.
  return find
      .descendant(
        of: segmentOf(label),
        matching: find.byElementPredicate((element) {
          return element == focused;
        }),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  setUpAll(ensureZones);

  testWidgets("DT1 the barrel shows CalendarDateTimePicker, which opens on "
      "its date view: the day picker on the day and no time picker; at the "
      "end of the day picker's header, centred on its row, the view control, "
      "a stadium track in the theme's background whose Date and Time "
      "segments share its width, a pill in the primary tint under the Date "
      "segment, whose label is in the primary colour and the Time segment's "
      "in the secondary text colour, which a screen reader hears as buttons "
      "in a mutually exclusive group, Date selected", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          today: tuesday,
          onChanged: (day, minute) {},
        ),
      ),
    );
    expect(
      tester.widget<CalendarDayPicker<String>>(dayPicker).value,
      wednesday,
    );
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(timeView, findsNothing);
    final header = tester.getRect(headerRowOf(dayPicker));
    final track = tester.getRect(control());
    expect(track.right, header.right);
    expect(track.center.dy, moreOrLessEquals(header.center.dy));
    final date = tester.getRect(segmentOf(dateSegment));
    final time = tester.getRect(segmentOf(timeSegment));
    expect(date.width, moreOrLessEquals(time.width));
    expect(date.left, track.left);
    expect(time.right, track.right);
    expect(tester.getRect(pill()), date);
    final theme = pickerTheme(tester);
    expect(fillOf(tester, control()), theme.background);
    expect(pillFill(tester), theme.primaryTint);
    expect(inkOf(tester, dateSegment), theme.primary);
    expect(inkOf(tester, timeSegment), theme.textSecondary);
    expect(
      tester.getSemantics(dateSegment),
      isSemantics(
        label: "Date",
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(timeSegment),
      isSemantics(
        label: "Time",
        isButton: true,
        isSelected: false,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        isFocusable: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets("DT2 a tap on the Time segment turns to the time view over the "
      "theme's motion: the picker's height moves from the date view's to "
      "the time view's, the time view lying at full opacity under the date "
      "view, which fades out and takes no pointer and no screen reader's "
      "attention, as the pill slides to "
      "the Time segment and the labels turn between their colours; the time "
      "view's header names the day against today, the control where it lay, "
      "over the time picker on the minute; it reports true and no value; a "
      "tap on the Date segment turns back the reverse way and reports "
      "false", (tester) async {
    final semantics = tester.ensureSemantics();
    final shows = <bool>[];
    final picks = <(DateTime, int?)>[];
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          today: tuesday,
          onChanged: (day, minute) {
            picks.add((day, minute));
          },
          onShowsTimeChanged: shows.add,
        ),
        theme: motionTheme,
      ),
    );
    final theme = pickerTheme(tester);
    final dateHeight = pickerHeight(tester);
    final track = tester.getRect(control());
    final dateSegmentRect = tester.getRect(segmentOf(dateSegment));
    // Setup sanity: Thursday takes a tap.
    expect(dayTarget(thursday).hitTestable(), findsOne);
    final heard = find.semantics.byLabel(
      const DefaultCalendarLocalizations().dayWithBadges(
        thursday,
        const <String?>[],
      ),
    );
    // Setup sanity: a screen reader hears Thursday.
    expect(heard, findsOne);

    await tester.tap(segmentOf(timeSegment));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final timeHeight = tester.getSize(timeView).height;
    // Setup sanity: the views differ in height.
    expect((timeHeight - dateHeight).abs(), greaterThan(50.0));
    expect(
      pickerHeight(tester),
      moreOrLessEquals((dateHeight + timeHeight) / 2.0),
    );
    expect(viewOpacity(tester, timeView), 1.0);
    expect(viewOpacity(tester, dayPicker), moreOrLessEquals(0.5));
    expect(dayTarget(thursday).hitTestable(), findsNothing);
    expect(heard, findsNothing);
    // The date view fades over the time view: its layer is the last of
    // the switch's, after the time view's.
    final fading = tester.layers.whereType<OpacityLayer>().where((layer) {
      return layer.alpha == 128;
    }).toList();
    expect(fading, hasLength(1));
    expect(fading.single.nextSibling, isNull);
    final under = fading.single.previousSibling;
    expect(under, isA<OpacityLayer>());
    expect((under! as OpacityLayer).alpha, 255);
    expect(
      tester.getRect(pill()).left,
      moreOrLessEquals(dateSegmentRect.left + dateSegmentRect.width * 0.5),
    );
    final half = Color.lerp(theme.textSecondary, theme.primary, 0.5);
    expect(inkOf(tester, dateSegment), half);
    expect(inkOf(tester, timeSegment), half);

    await tester.pumpAndSettle();
    expect(pickerHeight(tester), moreOrLessEquals(timeHeight));
    expect(viewOpacity(tester, dayPicker), 0.0);
    expect(
      tester.widget<CalendarTimePicker>(find.byType(CalendarTimePicker)).value,
      600,
    );
    expect(
      find.descendant(of: timeView, matching: find.text("Tomorrow, April 22")),
      findsOne,
    );
    expect(tester.getRect(control()), track);
    expect(tester.getRect(pill()), tester.getRect(segmentOf(timeSegment)));
    expect(inkOf(tester, timeSegment), theme.primary);
    expect(inkOf(tester, dateSegment), theme.textSecondary);
    expect(
      tester.getSemantics(timeSegment),
      isSemantics(
        label: "Time",
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        isFocusable: true,
      ),
    );
    expect(find.byKey(timePickerHourRowKey(11)).hitTestable(), findsOne);
    expect(shows, <bool>[true]);

    await tester.tap(segmentOf(dateSegment));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      pickerHeight(tester),
      moreOrLessEquals(timeHeight + (dateHeight - timeHeight) * 0.25),
    );
    expect(viewOpacity(tester, timeView), moreOrLessEquals(0.75));
    expect(viewOpacity(tester, dayPicker), 1.0);
    expect(find.byKey(timePickerHourRowKey(11)).hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(timeView, findsNothing);
    expect(pickerHeight(tester), moreOrLessEquals(dateHeight));
    expect(dayTarget(thursday).hitTestable(), findsOne);
    expect(shows, <bool>[true, false]);
    expect(picks, isEmpty);
    semantics.dispose();
  });

  testWidgets("DT3 with initialShowsTime the picker opens on its time view, "
      "and a later build's leaves the view; where the platform asks for no "
      "animations a tap switches in its frame", (tester) async {
    Widget picker({required bool showsTime}) {
      return app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          today: tuesday,
          onChanged: (day, minute) {},
          initialShowsTime: showsTime,
        ),
        theme: motionTheme,
      );
    }

    await tester.pumpWidget(picker(showsTime: true));
    expect(viewOpacity(tester, timeView), 1.0);
    expect(viewOpacity(tester, dayPicker), 0.0);
    expect(inkOf(tester, timeSegment), pickerTheme(tester).primary);
    await tester.pumpWidget(picker(showsTime: false));
    await tester.pumpAndSettle();
    expect(timeView, findsOne);
    expect(viewOpacity(tester, timeView), 1.0);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.tap(segmentOf(dateSegment));
    await tester.pump();
    expect(timeView, findsNothing);
    expect(viewOpacity(tester, dayPicker), 1.0);
    await tester.tap(segmentOf(timeSegment));
    await tester.pump();
    expect(viewOpacity(tester, timeView), 1.0);
    expect(viewOpacity(tester, dayPicker), 0.0);
  });

  testWidgets("DT18 a tap on a day reports it and keeps the date view, "
      "reporting no switch, and so do a tap on the value's day and a screen "
      "reader's activation of a day", (tester) async {
    final semantics = tester.ensureSemantics();
    final shows = <bool>[];
    final picks = <(DateTime, int?)>[];
    var built = 0;
    Widget picker() {
      built++;
      return app(
        CalendarDateTimePicker<String>(
          key: ValueKey<int>(built),
          day: wednesday,
          minute: 600,
          today: tuesday,
          onChanged: (day, minute) {
            picks.add((day, minute));
          },
          onShowsTimeChanged: shows.add,
        ),
      );
    }

    Future<void> expectKept(String step) async {
      await tester.pumpAndSettle();
      expect(shows, isEmpty, reason: step);
      expect(timeView, findsNothing, reason: step);
      expect(dayTarget(thursday).hitTestable(), findsOne, reason: step);
    }

    await tester.pumpWidget(picker());
    await tester.tap(dayCell(thursday));
    expect(picks, <(DateTime, int?)>[(thursday, 600)]);
    await expectKept("a tap");

    picks.clear();
    await tester.pumpWidget(picker());
    await tester.tap(dayCell(wednesday));
    expect(picks, <(DateTime, int?)>[(wednesday, 600)]);
    await expectKept("the value's day");

    picks.clear();
    await tester.pumpWidget(picker());
    tester.semantics.tap(
      find.semantics.byLabel(
        const DefaultCalendarLocalizations().dayWithBadges(
          thursday,
          const <String?>[],
        ),
      ),
    );
    expect(picks, <(DateTime, int?)>[(thursday, 600)]);
    await expectKept("a screen reader");
    semantics.dispose();
  });

  testWidgets("DT19 the control lies at the same place in the date view and "
      "the time view, at the end of each header's row and centred on it, "
      "the rows as tall, on a padded and a shrink-wrapped tap target, at "
      "text scale 1 and 2, and with daysToEdges", (tester) async {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      for (final scale in <double>[1.0, 2.0]) {
        for (final edges in <bool>[false, true]) {
          final step = "$platform x$scale edges $edges";
          debugDefaultTargetPlatformOverride = platform;
          Widget picker(bool showsTime) {
            return app(
              Builder(
                builder: (context) {
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: CalendarDateTimePicker<String>(
                      key: ValueKey<bool>(showsTime),
                      day: wednesday,
                      minute: 600,
                      today: tuesday,
                      daysToEdges: edges,
                      initialShowsTime: showsTime,
                      onChanged: (day, minute) {},
                    ),
                  );
                },
              ),
            );
          }

          await tester.pumpWidget(picker(false));
          final inDate = tester.getRect(control());
          final dateHeader = tester.getRect(headerRowOf(dayPicker));
          await tester.pumpWidget(picker(true));
          final inTime = tester.getRect(control());
          final timeHeader = tester.getRect(headerRowOf(timeView));
          debugDefaultTargetPlatformOverride = null;
          expect(inTime, inDate, reason: step);
          expect(timeHeader, dateHeader, reason: step);
          expect(inTime.right, timeHeader.right, reason: step);
          expect(
            inTime.center.dy,
            moreOrLessEquals(timeHeader.center.dy),
            reason: step,
          );
        }
      }
    }
  });

  testWidgets("DT20 the date view keeps its state while the time view "
      "shows, unfolded and browsed to another month, taking no pointer and "
      "no screen reader's attention and running no animation; it shows "
      "that month again on the turn back", (tester) async {
    final semantics = tester.ensureSemantics();
    final may15 = DateTime(2026, 5, 15);
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          today: tuesday,
          initialView: const CalendarDayPickerView(folded: false),
          onChanged: (day, minute) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: the month shows May.
    expect(dayCell(may15).hitTestable(), findsOne);
    final heard = find.semantics.byLabel(
      const DefaultCalendarLocalizations().dayWithBadges(
        may15,
        const <String?>[],
      ),
    );
    // Setup sanity: a screen reader hears May 15.
    expect(heard, findsOne);
    await tester.tap(segmentOf(timeSegment));
    await tester.pumpAndSettle();
    expect(heard, findsNothing);
    expect(find.byType(DayCell).hitTestable(), findsNothing);
    expect(TickerMode.valuesOf(tester.element(dayPicker)).enabled, isFalse);
    await tester.tap(segmentOf(dateSegment));
    await tester.pumpAndSettle();
    expect(dayCell(may15).hitTestable(), findsOne);
    expect(TickerMode.valuesOf(tester.element(dayPicker)).enabled, isTrue);
    semantics.dispose();
  });

  testWidgets("DT21 the control's segments share its width whatever their "
      "labels, each as wide as the wider label takes; a control whose labels "
      "would take more than half its header row scales down to half of it, "
      "in both views, and nothing overflows", (tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            return Localizations.override(
              context: context,
              delegates: const <LocalizationsDelegate<Object?>>[
                _LongTimeDelegate(),
              ],
              child: CalendarDateTimePicker<String>(
                day: wednesday,
                minute: 600,
                today: tuesday,
                onChanged: (day, minute) {},
              ),
            );
          },
        ),
      ),
    );
    // Setup sanity: the Time label is the wider.
    expect(
      tester.getRect(timeSegment).width,
      greaterThan(tester.getRect(dateSegment).width + 20.0),
    );
    final track = tester.getRect(control());
    expect(
      tester.getRect(segmentOf(dateSegment)).width,
      moreOrLessEquals(track.width / 2.0),
    );
    expect(
      tester.getRect(segmentOf(timeSegment)).width,
      moreOrLessEquals(track.width / 2.0),
    );
    final header = tester.getRect(headerRowOf(dayPicker));
    // Setup sanity: the labels, unscaled, take more than half the row.
    expect(tester.getSize(control()).width, greaterThan(header.width / 2.0));
    expect(track.width, moreOrLessEquals(header.width / 2.0));
    expect(track.right, header.right);

    await tester.tap(segmentOf(timeSegment));
    await tester.pumpAndSettle();
    expect(tester.getRect(control()), track);
  });

  testWidgets("DT22 as an AlertDialog's content, which the dialog lays out "
      "under an IntrinsicWidth, the picker lays out in both views with no "
      "error, its control unscaled, and answers the height it lays out at "
      "as its intrinsic height", (tester) async {
    for (final showsTime in <bool>[false, true]) {
      final step = showsTime ? "time view" : "date view";
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: AlertDialog(
              content: CalendarDateTimePicker<String>(
                key: ValueKey<bool>(showsTime),
                day: wednesday,
                minute: 600,
                today: tuesday,
                initialShowsTime: showsTime,
                onChanged: (day, minute) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: step);
      // Setup sanity: the view asked for shows.
      expect(timeView, showsTime ? findsOne : findsNothing, reason: step);
      expect(
        tester.getRect(dateSegment).width,
        moreOrLessEquals(tester.getSize(dateSegment).width),
        reason: step,
      );
      final box = tester.renderObject<RenderBox>(
        find.byType(CalendarDateTimePicker<String>),
      );
      expect(
        box.getMinIntrinsicHeight(box.size.width),
        moreOrLessEquals(box.size.height),
        reason: step,
      );
      expect(
        box.getMaxIntrinsicHeight(box.size.width),
        moreOrLessEquals(box.size.height),
        reason: step,
      );
    }
  });

  testWidgets("DT23 under an unbounded width the picker lays out with no "
      "error at its intrinsic width, at which each view's header row shows "
      "its title and the control unscaled, whether the title or the "
      "control's half of the row sets the row's width", (tester) async {
    for (final long in <bool>[false, true]) {
      final labels = long ? "long labels" : "short labels";
      final picker = CalendarDateTimePicker<String>(
        key: ValueKey<bool>(long),
        day: wednesday,
        minute: 600,
        today: tuesday,
        onChanged: (day, minute) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (long)
                    Builder(
                      builder: (context) {
                        return Localizations.override(
                          context: context,
                          delegates: const <LocalizationsDelegate<Object?>>[
                            _LongTimeDelegate(),
                          ],
                          child: picker,
                        );
                      },
                    )
                  else
                    picker,
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: labels);
      final box = tester.renderObject<RenderBox>(
        find.byType(CalendarDateTimePicker<String>),
      );
      for (final (view, title) in <(Finder, Finder)>[
        (dayPicker, find.text("Apr 2026")),
        (timeView, find.text("Tomorrow, April 22")),
      ]) {
        final step = "$labels, ${view == timeView ? "time" : "date"} view";
        if (view == timeView) {
          await tester.tap(segmentOf(timeSegment));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: step);
        }
        expect(
          box.size.width,
          moreOrLessEquals(box.getMaxIntrinsicWidth(double.infinity)),
          reason: step,
        );
        for (final label in <Finder>[dateSegment, timeSegment, title]) {
          expect(
            tester.getRect(label).width,
            moreOrLessEquals(tester.getSize(label).width),
            reason: "$step: $label",
          );
        }
        // Setup sanity: the control's half of the row sets the row's width
        // with the long labels, and the title with the short ones.
        final half = tester.getRect(headerRowOf(view)).width / 2.0;
        expect(
          tester.getRect(control()).width,
          long ? moreOrLessEquals(half) : lessThan(half - 1.0),
          reason: step,
        );
      }
    }
  });

  testWidgets("DT4 a tap on a day reports it with the time where the day "
      "offers it, and where it does not, as isTimeEnabled refuses it or it "
      "lies outside timeBoundsOf's bounds there, with the offered time of "
      "that day nearest it on the step, the later of two as near; and with "
      "the time unchanged where the day offers none", (tester) async {
    final thursday = DateTime(2026, 4, 23);
    final friday = DateTime(2026, 4, 24);
    final saturday = DateTime(2026, 4, 25);
    final sunday = DateTime(2026, 4, 26);
    final refused = <int, Set<int>>{
      CalendarDates.dayNumber(thursday): <int>{585, 600, 615},
      CalendarDates.dayNumber(saturday): <int>{600, 615},
    };
    final picks = <(DateTime, int?)>[];
    for (final (day, kept) in <(DateTime, int)>[
      (friday, 600),
      // 570 and 630 lie as near.
      (thursday, 630),
      // 585 lies nearer than 630.
      (saturday, 585),
      (sunday, 660),
      (tuesday, 600),
    ]) {
      // A tap turns to the time view, so each day's tap is a new picker's.
      await tester.pumpWidget(
        app(
          CalendarDateTimePicker<String>(
            key: ValueKey<DateTime>(day),
            day: wednesday,
            minute: 600,
            today: wednesday,
            onChanged: (day, minute) {
              picks.add((day, minute));
            },
            timeBoundsOf: (day) {
              return CalendarDates.dayNumber(day) ==
                      CalendarDates.dayNumber(sunday)
                  ? (min: 660, max: 1439)
                  : (min: 0, max: 1439);
            },
            isTimeEnabled: (day, minute) {
              if (CalendarDates.dayNumber(day) ==
                  CalendarDates.dayNumber(tuesday)) {
                return false;
              }
              final number = CalendarDates.dayNumber(day);
              return !(refused[number]?.contains(minute) ?? false);
            },
          ),
        ),
      );
      picks.clear();
      await tester.tap(dayCell(day));
      await tester.pump();
      expect(picks, hasLength(1), reason: "$day");
      expect(
        CalendarDates.dayNumber(picks.single.$1),
        CalendarDates.dayNumber(day),
        reason: "$day",
      );
      expect(picks.single.$2, kept, reason: "$day");
    }
  });

  testWidgets("DT5 on the clock of the store's zone, a time it skips draws "
      "disabled on its day, and a tap on that day moves a time it would "
      "skip to the first time the clock reads", (tester) async {
    // America/Havana's clock skips 00:00 to 01:00 on Sunday 2026-03-08.
    final havana = tz.getLocation("America/Havana");
    final store = MemoryCalendarStore<String>(zone: havana);
    addTearDown(store.dispose);
    final saturday = DateTime(2026, 3, 7);
    final sunday = DateTime(2026, 3, 8);
    final picks = <(DateTime, int?)>[];
    Widget picker(DateTime day, int minute) {
      return app(
        CalendarDateTimePicker<String>(
          day: day,
          minute: minute,
          store: store,
          today: saturday,
          initialShowsTime: true,
          onChanged: (day, minute) {
            picks.add((day, minute));
          },
        ),
      );
    }

    await tester.pumpWidget(picker(saturday, 30));
    await tester.pumpAndSettle();
    // Setup sanity: Saturday's clock reads 00:30.
    expect(rowTakesTap(tester, timePickerHourRowKey(0)), isTrue);
    await tester.tap(segmentOf(dateSegment));
    await tester.pumpAndSettle();
    await tester.tap(dayCell(sunday));
    await tester.pump();
    expect(
      CalendarDates.dayNumber(picks.single.$1),
      CalendarDates.dayNumber(sunday),
    );
    expect(picks.single.$2, 60);

    await tester.pumpWidget(picker(sunday, 60));
    await tester.tap(segmentOf(timeSegment));
    await tester.pumpAndSettle();
    expect(rowTakesTap(tester, timePickerHourRowKey(0)), isFalse);
    expect(rowTakesTap(tester, timePickerHourRowKey(1)), isTrue);
  });

  testWidgets("DT6 a pick of a time reports it with the day", (tester) async {
    final picks = <(DateTime, int?)>[];
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          today: tuesday,
          initialShowsTime: true,
          onChanged: (day, minute) {
            picks.add((day, minute));
          },
        ),
      ),
    );
    await tester.tap(find.byKey(timePickerHourRowKey(11)));
    await tester.pumpAndSettle();
    expect(picks, <(DateTime, int?)>[(wednesday, 660)]);
  });

  testWidgets("DT16 a pick of a time reports its day as the start of its "
      "date on the clock of the store's zone, and of the device with no "
      "store, whatever time of it day holds", (tester) async {
    final havana = tz.getLocation("America/Havana");
    final store = MemoryCalendarStore<String>(zone: havana);
    addTearDown(store.dispose);
    Future<List<(DateTime, int?)>> pickEleven(
      CalendarStore<String>? store,
    ) async {
      final picks = <(DateTime, int?)>[];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(
          CalendarDateTimePicker<String>(
            day: DateTime(2026, 4, 22, 9, 30),
            minute: 600,
            today: tuesday,
            store: store,
            initialShowsTime: true,
            onChanged: (day, minute) {
              picks.add((day, minute));
            },
          ),
        ),
      );
      await tester.tap(find.byKey(timePickerHourRowKey(11)));
      await tester.pumpAndSettle();
      return picks;
    }

    expect(await pickEleven(store), <(DateTime, int?)>[
      (tz.TZDateTime(havana, 2026, 4, 22), 660),
    ]);
    expect(await pickEleven(null), <(DateTime, int?)>[(wednesday, 660)]);
  });

  testWidgets("DT7 with a null minute the picker shows its date view with no "
      "control, and a tap on a day reports it with null; a minute that "
      "turns null in the time view turns to the date view, the time view "
      "still showing its last time as it fades, and fades the control out "
      "over the theme's motion; one that turns from null shows the time "
      "view again, as the control last turned to", (tester) async {
    final semantics = tester.ensureSemantics();
    final picks = <(DateTime, int?)>[];
    final shows = <bool>[];
    Widget picker(int? minute, {Key? key, bool showsTime = true}) {
      return app(
        CalendarDateTimePicker<String>(
          key: key,
          day: wednesday,
          minute: minute,
          today: tuesday,
          initialShowsTime: showsTime,
          onChanged: (day, minute) {
            picks.add((day, minute));
          },
          onShowsTimeChanged: shows.add,
        ),
        theme: motionTheme,
      );
    }

    await tester.pumpWidget(picker(null, key: const ValueKey<int>(1)));
    expect(dateSegment, findsNothing);
    expect(timeSegment, findsNothing);
    expect(timeView, findsNothing);
    expect(viewOpacity(tester, dayPicker), 1.0);
    await tester.tap(dayCell(thursday));
    await tester.pumpAndSettle();
    expect(picks.single.$2, isNull);
    expect(timeView, findsNothing);

    await tester.pumpWidget(picker(600, key: const ValueKey<int>(2)));
    final timeHeight = tester.getSize(timeView).height;
    await tester.pumpWidget(picker(null, key: const ValueKey<int>(2)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(viewOpacity(tester, timeView), moreOrLessEquals(0.5));
    expect(viewOpacity(tester, dayPicker), 1.0);
    expect(pickerHeight(tester), lessThan(timeHeight));
    expect(
      tester.widget<CalendarTimePicker>(find.byType(CalendarTimePicker)).value,
      600,
    );
    expect(
      tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: dateSegment,
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value,
      moreOrLessEquals(0.5),
    );
    expect(find.semantics.byLabel("Time"), findsNothing);
    expect(find.semantics.byLabel("Date"), findsNothing);
    await tester.pumpAndSettle();
    expect(dateSegment, findsNothing);
    expect(timeView, findsNothing);

    await tester.pumpWidget(picker(600, key: const ValueKey<int>(2)));
    await tester.pumpAndSettle();
    expect(timeView, findsOne);
    expect(viewOpacity(tester, timeView), 1.0);
    expect(viewOpacity(tester, dayPicker), 0.0);
    expect(dateSegment, findsOne);
    expect(shows, isEmpty);

    // A minute that turns null and back while the control shows the date
    // view leaves the date view shown.
    const third = ValueKey<int>(3);
    await tester.pumpWidget(picker(600, key: third, showsTime: false));
    await tester.pumpWidget(picker(null, key: third, showsTime: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(picker(600, key: third, showsTime: false));
    await tester.pumpAndSettle();
    // Setup sanity: the control came back.
    expect(dateSegment, findsOne);
    expect(timeView, findsNothing);
    expect(shows, isEmpty);
    semantics.dispose();
  });

  testWidgets("DT14 as a minute that turns null turns to the date view, the "
      "time picker keeps the bounds and the times it offered, and the "
      "picker asks timeBoundsOf and isTimeEnabled nothing more", (
    tester,
  ) async {
    final asks = <String>[];
    Widget picker(int? minute) {
      // New callbacks at each build, as a host's whose schedule changes,
      // whose bounds turn with its minute.
      return app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: minute,
          today: tuesday,
          initialShowsTime: true,
          onChanged: (day, minute) {},
          timeBoundsOf: (day) {
            asks.add("bounds");
            return minute == null ? (min: 0, max: 1439) : (min: 480, max: 1080);
          },
          isTimeEnabled: (day, time) {
            asks.add("time $time");
            return time != 615;
          },
        ),
        theme: motionTheme,
      );
    }

    await tester.pumpWidget(picker(600));
    final shown = tester.widget<CalendarTimePicker>(
      find.byType(CalendarTimePicker),
    );
    // Setup sanity: the time picker asked as it built.
    expect(asks, containsAll(<String>["bounds", "time 600"]));
    asks.clear();
    await tester.pumpWidget(picker(null));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(picker(null));
    await tester.pump(const Duration(milliseconds: 100));
    final hiding = tester.widget<CalendarTimePicker>(
      find.byType(CalendarTimePicker),
    );
    expect((hiding.min, hiding.max), (480, 1080));
    expect(identical(hiding.isEnabled, shown.isEnabled), isTrue);
    await tester.pumpAndSettle();
    expect(asks, isEmpty);
  });

  testWidgets("DT15 isTimeEnabled is asked of each time of the day at most "
      "once across builds while the day and the predicate stay, and anew "
      "for a new day or a new predicate", (tester) async {
    final asks = <(int, int)>[];
    bool first(DateTime day, int minute) {
      asks.add((CalendarDates.dayNumber(day), minute));
      return true;
    }

    bool second(DateTime day, int minute) {
      return first(day, minute);
    }

    Widget picker(
      DateTime day,
      int minute,
      bool Function(DateTime, int) isTimeEnabled,
    ) {
      return app(
        CalendarDateTimePicker<String>(
          day: day,
          minute: minute,
          today: tuesday,
          initialShowsTime: true,
          onChanged: (day, minute) {},
          isTimeEnabled: isTimeEnabled,
        ),
      );
    }

    final wednesdayNumber = CalendarDates.dayNumber(wednesday);
    await tester.pumpWidget(picker(wednesday, 600, first));
    await tester.pumpWidget(picker(wednesday, 615, first));
    await tester.pumpWidget(picker(wednesday, 600, first));
    await tester.pumpAndSettle();
    // Setup sanity: the time picker asked of the times it shows.
    expect(asks, contains((wednesdayNumber, 600)));
    expect(asks.length, asks.toSet().length);

    asks.clear();
    await tester.pumpWidget(picker(wednesday, 600, second));
    await tester.pumpAndSettle();
    expect(asks, contains((wednesdayNumber, 600)));

    asks.clear();
    await tester.pumpWidget(picker(thursday, 600, second));
    await tester.pumpAndSettle();
    expect(asks, contains((CalendarDates.dayNumber(thursday), 600)));
  });

  testWidgets("DT9 a column held as the view turns to the date view picks "
      "nothing", (tester) async {
    final picks = <(DateTime, int?)>[];
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          today: tuesday,
          initialShowsTime: true,
          onChanged: (day, minute) {
            picks.add((day, minute));
          },
        ),
        theme: motionTheme,
      ),
    );
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(timePickerHourColumnKey)),
    );
    await hold.moveBy(const Offset(0.0, -20.0));
    await tester.pump(const Duration(milliseconds: 50));
    await hold.moveBy(const Offset(0.0, -40.0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(segmentOf(dateSegment));
    await tester.pump();
    await hold.up();
    await tester.pumpAndSettle();
    expect(picks, isEmpty);
  });

  testWidgets("DT10 where a switch leaves the focus in the view it hides, "
      "the focus moves to the segment that names the shown view in the "
      "shown view's control, whether a tap or a key turned it; a switch "
      "with the focus elsewhere moves no focus", (tester) async {
    final hours = FocusNode(debugLabel: "hours");
    addTearDown(hours.dispose);
    final outside = FocusNode(debugLabel: "outside");
    addTearDown(outside.dispose);
    await tester.pumpWidget(
      app(
        Column(
          children: <Widget>[
            Focus(focusNode: outside, child: const SizedBox(height: 10.0)),
            CalendarDateTimePicker<String>(
              day: wednesday,
              minute: 600,
              today: tuesday,
              initialShowsTime: true,
              initialView: const CalendarDayPickerView(folded: false),
              timeFocusNode: hours,
              onChanged: (day, minute) {},
            ),
          ],
        ),
      ),
    );
    hours.requestFocus();
    await tester.pump();
    // Setup sanity: the Hour column has the focus.
    expect(hours.hasFocus, isTrue);
    await tester.tap(segmentOf(dateSegment));
    await tester.pumpAndSettle();
    expect(focusedOn(dateSegment), isTrue);

    // The Date segment has the focus; Tab moves it to the Time segment,
    // whose Enter turns to the time view.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // Setup sanity: Tab reached the Time segment of the date view.
    expect(focusedOn(timeSegment), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(viewOpacity(tester, timeView), 1.0);
    expect(focusedOn(timeSegment), isTrue);

    outside.requestFocus();
    await tester.pump();
    await tester.tap(segmentOf(dateSegment));
    await tester.pumpAndSettle();
    expect(outside.hasPrimaryFocus, isTrue);
  });

  testWidgets("DT11 the picker hands its day parameters to its day picker "
      "and its time parameters to its time picker, the bounds the day's", (
    tester,
  ) async {
    // Tall enough for the month and the time picker.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 1200.0);
    addTearDown(tester.view.reset);
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final hours = FocusNode();
    addTearDown(hours.dispose);
    final badges = CalendarDayBadges<String>(
      kinds: const <CalendarBadgeKind>[],
      kindOf: (entry) {
        return null;
      },
    );
    bool isDayEnabled(DateTime day) {
      return true;
    }

    void onViewChanged(CalendarDayPickerView view) {}

    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          store: store,
          today: wednesday,
          firstDay: tuesday,
          lastDay: DateTime(2026, 5, 1),
          isDayEnabled: isDayEnabled,
          firstColumn: 6,
          dayBadges: badges,
          daysToEdges: true,
          browsesBeforeFirstDay: false,
          initialView: const CalendarDayPickerView(folded: false),
          onViewChanged: onViewChanged,
          hourLabelFormat: CalendarHourLabelFormat.twelveHour,
          minuteStep: 30,
          timeBoundsOf: (day) {
            return (min: CalendarDates.dayNumber(day) % 100, max: 1200);
          },
          timeFocusNode: hours,
          hapticFeedback: true,
          subject: "start",
          initialShowsTime: true,
          onChanged: (day, minute) {},
        ),
      ),
    );
    final dayPickerWidget = tester.widget<CalendarDayPicker<String>>(dayPicker);
    expect(dayPickerWidget.store, same(store));
    expect(dayPickerWidget.today, wednesday);
    expect(dayPickerWidget.firstDay, tuesday);
    expect(dayPickerWidget.lastDay, DateTime(2026, 5, 1));
    expect(dayPickerWidget.isEnabled == isDayEnabled, isTrue);
    expect(dayPickerWidget.firstColumn, 6);
    expect(dayPickerWidget.dayBadges, same(badges));
    expect(dayPickerWidget.daysToEdges, isTrue);
    expect(dayPickerWidget.browsesBeforeFirstDay, isFalse);
    expect(
      dayPickerWidget.initialView,
      const CalendarDayPickerView(folded: false),
    );
    expect(dayPickerWidget.onViewChanged == onViewChanged, isTrue);
    final timePicker = tester.widget<CalendarTimePicker>(
      find.byType(CalendarTimePicker),
    );
    expect(timePicker.hourLabelFormat, CalendarHourLabelFormat.twelveHour);
    expect(timePicker.minuteStep, 30);
    expect(timePicker.min, CalendarDates.dayNumber(wednesday) % 100);
    expect(timePicker.max, 1200);
    expect(timePicker.focusNode, same(hours));
    expect(timePicker.hapticFeedback, isTrue);
    expect(timePicker.subject, "start");
  });

  testWidgets("DT12 with no CalendarTheme above it the picker draws in the "
      "theme its Material theme's colour scheme gives", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: Scaffold(
          body: CalendarDateTimePicker<String>(
            day: wednesday,
            minute: 600,
            today: tuesday,
            onChanged: (day, minute) {},
          ),
        ),
      ),
    );
    final scheme = Theme.of(tester.element(dayPicker)).colorScheme;
    final derived = CalendarThemeExtension.fromColorScheme(scheme).data;
    expect(pillFill(tester), derived.primaryTint);
  });

  test("DT13 the constructor names the first value it does not take", () {
    void ok(DateTime day, int? minute) {}
    for (final minute in <int>[-1, 1441]) {
      expect(() {
        return CalendarDateTimePicker<String>(
          day: wednesday,
          minute: minute,
          onChanged: ok,
          minuteStep: 7,
        );
      }, throwsA(isArgumentError.having((e) => e.name, "name", "minute")));
    }
    for (final step in <int>[7, 0]) {
      expect(() {
        return CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          onChanged: ok,
          minuteStep: step,
          firstColumn: 7,
        );
      }, throwsA(isArgumentError.having((e) => e.name, "name", "minuteStep")));
    }
    expect(() {
      return CalendarDateTimePicker<String>(
        day: wednesday,
        minute: 1440,
        onChanged: ok,
        firstColumn: 7,
      );
    }, throwsA(isArgumentError.having((e) => e.name, "name", "firstColumn")));
  });

  testWidgets("DT17 folded at text scale 2, the picker's days lay each label "
      "out whole on one line in its day, and nothing overflows", (
    tester,
  ) async {
    await recordingErrors((errors) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2.0)),
                child: CalendarDateTimePicker<String>(
                  day: wednesday,
                  minute: 600,
                  today: tuesday,
                  onChanged: (day, minute) {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
      final cut = <String>[];
      final outside = <String>[];
      for (final cell in find.byType(DayCell).evaluate()) {
        final box = cell.renderObject! as RenderBox;
        final cellRect = box.localToGlobal(Offset.zero) & box.size;
        for (final label
            in find
                .descendant(
                  of: find.byElementPredicate((element) {
                    return element == cell;
                  }),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final paragraph = label.renderObject! as RenderParagraph;
          final text = paragraph.text.toPlainText();
          if (paragraph.size.width <
                  paragraph.getMaxIntrinsicWidth(double.infinity) - 0.01 ||
              paragraph.size.height <
                  paragraph.getMinIntrinsicHeight(double.infinity) - 0.01) {
            cut.add(text);
          }
          final painted = Rect.fromPoints(
            paragraph.localToGlobal(Offset.zero),
            paragraph.localToGlobal(paragraph.size.bottomRight(Offset.zero)),
          );
          if (painted.left < cellRect.left - 0.01 ||
              painted.top < cellRect.top - 0.01 ||
              painted.right > cellRect.right + 0.01 ||
              painted.bottom > cellRect.bottom + 0.01) {
            outside.add(text);
          }
        }
      }
      // Setup sanity: the picker is folded, each of its days at a full
      // collapse.
      final days = tester.widgetList<DayCell>(find.byType(DayCell)).toList();
      expect(days, hasLength(greaterThanOrEqualTo(7)));
      expect(
        days.where((day) {
          return day.collapse.value != 1.0;
        }),
        isEmpty,
      );
      expect(cut, isEmpty);
      expect(outside, isEmpty);
    });
  });
  testWidgets("DT35 a reader that is no store, given as the store, badges "
      "the days of the entries it keeps alone", (tester) async {
    final semantics = tester.ensureSemantics();
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        for (final (id, day) in <(String, DateTime)>[
          ("a", tuesday),
          ("b", wednesday),
        ])
          CalendarEntry<String>(
            id: id,
            start: DateTime(day.year, day.month, day.day, 9),
            end: DateTime(day.year, day.month, day.day, 10),
            title: id,
            color: const Color(0xFF3366CC),
            payload: id,
          ),
      ],
    );
    addTearDown(store.dispose);
    final reader = ForwardingReader<String>(
      store,
      keep: (entry) {
        return entry.id == "a";
      },
    );
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: tuesday,
          minute: 600,
          today: thursday,
          onChanged: (day, minute) {},
          store: reader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        const DefaultCalendarLocalizations().dayWithBadges(
          tuesday,
          const <String?>[null],
        ),
      ),
      findsOneWidget,
    );
    expect(dayCell(wednesday), findsOneWidget);
    semantics.dispose();
  });
}

/// The default localizations with a Time label longer than the Date one.
final class _LongTime extends DefaultCalendarLocalizations {
  const _LongTime();

  @override
  String get dateTimePickerTimeLabel {
    return "Time of day";
  }
}

class _LongTimeDelegate extends LocalizationsDelegate<CalendarLocalizations> {
  const _LongTimeDelegate();

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<CalendarLocalizations> load(Locale locale) {
    return SynchronousFuture<CalendarLocalizations>(const _LongTime());
  }

  @override
  bool shouldReload(_LongTimeDelegate old) {
    return false;
  }
}
