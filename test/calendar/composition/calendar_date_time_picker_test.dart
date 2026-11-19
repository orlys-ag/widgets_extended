/// The date-time picker through the package barrel: its day picker over
/// its divider and time picker, its Time toggle's look, what a screen
/// reader hears of it and what a tap on it does over the theme's motion,
/// the view it opens on, what a tap on a day and a pick of a time report,
/// a picked time's day as a day start on the store's clock,
/// the time a tap on a day keeps or moves to, the times the clock of the
/// store's zone skips, Now on today alone, a minute that turns null, a
/// column held as the time hides, the focus the toggle takes, the
/// parameters it hands its pickers, the theme it draws in and the values
/// its constructor refuses.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/composition/calendar_date_time_picker.dart'
    show
        dateTimePickerDividerKey,
        dateTimePickerTimeKey,
        dateTimePickerToggleKey;
import 'package:widgets_extended/calendar/views/time_picker.dart'
    show timePickerHourColumnKey, timePickerHourRowKey, timePickerNowKey;
import 'package:widgets_extended/widgets_extended.dart';

import '../../scheduling/zones.dart';

final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);

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

final Finder toggle = find.byKey(dateTimePickerToggleKey);

final Finder timePart = find.byKey(dateTimePickerTimeKey);

/// The fill of the toggle's pill.
Color? toggleFill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.ancestor(of: toggle, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as ShapeDecoration).color;
}

/// The colour of the toggle's label.
Color? toggleInk(WidgetTester tester) {
  return tester
      .widget<Text>(find.descendant(of: toggle, matching: find.byType(Text)))
      .style!
      .color;
}

/// The opacity the time part's [FadeTransition] draws at.
double timeOpacity(WidgetTester tester) {
  return tester
      .widget<FadeTransition>(
        find.descendant(of: timePart, matching: find.byType(FadeTransition)),
      )
      .opacity
      .value;
}

/// The theme the picker draws in.
CalendarThemeData pickerTheme(WidgetTester tester) {
  return CalendarTheme.of(tester.element(toggle));
}

/// Whether the row keyed [key] of the time picker takes a tap.
bool rowTakesTap(WidgetTester tester, Key key) {
  return tester.widget<GestureDetector>(find.byKey(key)).onTap != null;
}

void main() {
  setUpAll(ensureZones);

  testWidgets("DT1 the barrel shows CalendarDateTimePicker: a day picker on "
      "the day, over a divider 1 high in the theme's outline across the "
      "picker, over a time picker on the minute; at the end of the day "
      "picker's header a pill reading Time, on, filled with the primary "
      "tint, its label in the primary colour, which a screen reader hears "
      "as a toggled button", (tester) async {
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
    final picker = tester.getRect(find.byType(CalendarDateTimePicker<String>));
    final dayPicker = find.byType(CalendarDayPicker<String>);
    expect(
      tester.widget<CalendarDayPicker<String>>(dayPicker).value,
      wednesday,
    );
    final timePicker = find.byType(CalendarTimePicker);
    expect(tester.widget<CalendarTimePicker>(timePicker).value, 600);
    final divider = find.byKey(dateTimePickerDividerKey);
    final line = tester.getRect(divider);
    expect(line.height, 1.0);
    expect(line.left, picker.left);
    expect(line.right, picker.right);
    expect(line.top, greaterThanOrEqualTo(tester.getRect(dayPicker).bottom));
    expect(tester.getRect(timePicker).top, line.bottom);
    final theme = pickerTheme(tester);
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(of: divider, matching: find.byType(ColoredBox)),
          )
          .color,
      theme.outline,
    );
    final header = tester.getRect(
      find.descendant(of: dayPicker, matching: find.byType(Row)).first,
    );
    final pill = tester.getRect(toggle);
    expect(pill.right, header.right);
    expect(pill.center.dy, moreOrLessEquals(header.center.dy));
    expect(find.descendant(of: toggle, matching: find.text("Time")), findsOne);
    expect(toggleFill(tester), theme.primaryTint);
    expect(toggleInk(tester), theme.primary);
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        label: "Time",
        isButton: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets("DT2 a tap on the toggle hides the time over the theme's "
      "motion, the part under the day picker shrinking to no height, its "
      "divider and time picker fading out over the motion's first half and "
      "taking no pointer, as the toggle turns off between its colours; it "
      "reports false and no value; a second tap shows the time the reverse "
      "way and reports true", (tester) async {
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
    final full = tester.getSize(timePart).height;
    // Setup sanity: the part holds the divider and the time picker.
    expect(full, greaterThan(200.0));
    final hour = find.byKey(timePickerHourRowKey(11));
    expect(hour.hitTestable(), findsOne);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(timeOpacity(tester), moreOrLessEquals(0.5));
    expect(hour.hitTestable(), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(timePart).height, moreOrLessEquals(full * 0.5));
    expect(
      toggleFill(tester),
      Color.lerp(theme.background, theme.primaryTint, 0.5),
    );
    expect(
      toggleInk(tester),
      Color.lerp(theme.textSecondary, theme.primary, 0.5),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        label: "Time",
        isButton: true,
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );
    expect(shows, <bool>[false]);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(timePart).height, moreOrLessEquals(full * 0.25));
    expect(timeOpacity(tester), 0.0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(timeOpacity(tester), moreOrLessEquals(0.5));
    await tester.pumpAndSettle();
    expect(shows, <bool>[false, true]);
    expect(picks, isEmpty);
    semantics.dispose();
  });

  testWidgets("DT3 with initialShowsTime false the picker opens with the "
      "time hidden and the toggle off, and a later build's leaves it; where "
      "the platform asks for no animations a tap shows and hides the time "
      "in its frame", (tester) async {
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

    await tester.pumpWidget(picker(showsTime: false));
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(toggleFill(tester), pickerTheme(tester).background);
    expect(toggleInk(tester), pickerTheme(tester).textSecondary);
    await tester.pumpWidget(picker(showsTime: true));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarTimePicker), findsNothing);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    expect(timeOpacity(tester), 1.0);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(timePart, findsNothing);
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
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
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
    for (final (day, kept) in <(DateTime, int)>[
      (friday, 600),
      // 570 and 630 lie as near.
      (thursday, 630),
      // 585 lies nearer than 630.
      (saturday, 585),
      (sunday, 660),
      (tuesday, 600),
    ]) {
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
    await tester.tap(dayCell(sunday));
    await tester.pump();
    expect(
      CalendarDates.dayNumber(picks.single.$1),
      CalendarDates.dayNumber(sunday),
    );
    expect(picks.single.$2, 60);

    await tester.pumpWidget(picker(sunday, 60));
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

  testWidgets("DT7 with a null minute the picker shows no toggle and no "
      "time, and a tap on a day reports it with null; a minute that turns "
      "null hides the time, still showing its last, and fades the toggle "
      "out over the theme's motion; one that turns from null shows both", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final picks = <(DateTime, int?)>[];
    Widget picker(int? minute) {
      return app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: minute,
          today: tuesday,
          onChanged: (day, minute) {
            picks.add((day, minute));
          },
        ),
        theme: motionTheme,
      );
    }

    await tester.pumpWidget(picker(null));
    expect(toggle, findsNothing);
    expect(find.byType(CalendarTimePicker), findsNothing);
    await tester.tap(dayCell(DateTime(2026, 4, 23)));
    await tester.pump();
    expect(picks.single.$2, isNull);

    await tester.pumpWidget(picker(600));
    await tester.pumpAndSettle();
    expect(toggle, findsOne);
    final full = tester.getSize(timePart).height;
    await tester.pumpWidget(picker(null));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(timePart).height, moreOrLessEquals(full * 0.5));
    expect(
      tester.widget<CalendarTimePicker>(find.byType(CalendarTimePicker)).value,
      600,
    );
    expect(
      tester
          .widget<FadeTransition>(
            find
                .ancestor(of: toggle, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value,
      moreOrLessEquals(0.5),
    );
    expect(find.semantics.byLabel("Time"), findsNothing);
    await tester.pumpAndSettle();
    expect(toggle, findsNothing);
    expect(timePart, findsNothing);
    semantics.dispose();
  });

  testWidgets("DT14 as a minute that turns null hides the time, the time "
      "picker keeps the bounds and the times it offered, and the picker "
      "asks timeBoundsOf and isTimeEnabled nothing more", (tester) async {
    final asks = <String>[];
    Widget picker(int? minute) {
      // New callbacks at each build, as a host's whose schedule changes,
      // whose bounds turn with its minute.
      return app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: minute,
          today: tuesday,
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
    await tester.pumpWidget(picker(DateTime(2026, 4, 23), 600, second));
    await tester.pumpAndSettle();
    expect(
      asks,
      contains((CalendarDates.dayNumber(DateTime(2026, 4, 23)), 600)),
    );
  });

  testWidgets("DT8 the time picker shows Now on today's day alone", (
    tester,
  ) async {
    Widget picker(DateTime day) {
      return app(
        CalendarDateTimePicker<String>(
          day: day,
          minute: 600,
          today: wednesday,
          now: () {
            return 615;
          },
          onChanged: (day, minute) {},
        ),
      );
    }

    await tester.pumpWidget(picker(wednesday));
    expect(find.byKey(timePickerNowKey), findsOne);
    await tester.pumpWidget(picker(DateTime(2026, 4, 23)));
    expect(find.byKey(timePickerNowKey), findsNothing);
  });

  testWidgets("DT9 a column held as the toggle hides the time picks "
      "nothing", (tester) async {
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
    await tester.tap(toggle);
    await tester.pump();
    await hold.up();
    await tester.pumpAndSettle();
    expect(picks, isEmpty);
  });

  testWidgets("DT10 where the toggle hides the time with the focus in the "
      "time picker, the focus moves to the toggle", (tester) async {
    final hours = FocusNode(debugLabel: "hours");
    addTearDown(hours.dispose);
    await tester.pumpWidget(
      app(
        CalendarDateTimePicker<String>(
          day: wednesday,
          minute: 600,
          today: tuesday,
          timeFocusNode: hours,
          onChanged: (day, minute) {},
        ),
      ),
    );
    hours.requestFocus();
    await tester.pump();
    // Setup sanity: the Hour column has the focus.
    expect(hours.hasFocus, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!.context!;
    var underToggle = false;
    focused.visitAncestorElements((element) {
      underToggle = element.widget.key == dateTimePickerToggleKey;
      return !underToggle;
    });
    expect(
      underToggle || focused.widget.key == dateTimePickerToggleKey,
      isTrue,
    );
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
    int now() {
      return 0;
    }

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
          now: now,
          nowPicksLater: true,
          timeFocusNode: hours,
          hapticFeedback: true,
          subject: "start",
          onChanged: (day, minute) {},
        ),
      ),
    );
    final dayPicker = tester.widget<CalendarDayPicker<String>>(
      find.byType(CalendarDayPicker<String>),
    );
    expect(dayPicker.store, same(store));
    expect(dayPicker.today, wednesday);
    expect(dayPicker.firstDay, tuesday);
    expect(dayPicker.lastDay, DateTime(2026, 5, 1));
    expect(dayPicker.isEnabled == isDayEnabled, isTrue);
    expect(dayPicker.firstColumn, 6);
    expect(dayPicker.dayBadges, same(badges));
    expect(dayPicker.daysToEdges, isTrue);
    expect(dayPicker.browsesBeforeFirstDay, isFalse);
    expect(dayPicker.initialView, const CalendarDayPickerView(folded: false));
    expect(dayPicker.onViewChanged == onViewChanged, isTrue);
    final timePicker = tester.widget<CalendarTimePicker>(
      find.byType(CalendarTimePicker),
    );
    expect(timePicker.hourLabelFormat, CalendarHourLabelFormat.twelveHour);
    expect(timePicker.minuteStep, 30);
    expect(timePicker.min, CalendarDates.dayNumber(wednesday) % 100);
    expect(timePicker.max, 1200);
    expect(timePicker.now == now, isTrue);
    expect(timePicker.nowPicksLater, isTrue);
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
    final scheme = Theme.of(tester.element(toggle)).colorScheme;
    final derived = CalendarThemeExtension.fromColorScheme(scheme).data;
    expect(toggleFill(tester), derived.primaryTint);
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
}
