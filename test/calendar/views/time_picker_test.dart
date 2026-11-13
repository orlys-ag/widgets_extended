/// [CalendarTimePicker]: its rows and their limits, the 1440 that ends a
/// day, its motions and the one report each gesture makes, the host's
/// value, its keys, focus, semantics, theme, footer and checks, and the
/// cost of a frame of its motion.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/views/time_picker.dart'
    show
        timePickerAmKey,
        timePickerBandKey,
        timePickerClearKey,
        timePickerFooterKey,
        timePickerHourColumnKey,
        timePickerHourRowKey,
        timePickerMinuteColumnKey,
        timePickerMinuteRowKey,
        timePickerNowKey,
        timePickerPmKey,
        timePickerToggleKey;
import 'package:widgets_extended/widgets_extended.dart';

/// A theme whose motion no built-in value matches: 200 ms on an ease-in
/// curve.
final CalendarThemeData steady = CalendarThemeData(
  motionDuration: const Duration(milliseconds: 200),
  motionCurve: Curves.easeIn,
);

/// [picker] under a MediaQuery of [textScaler], a Directionality of
/// [direction] and a CalendarTheme of [theme], [width] wide at the top
/// left.
Widget host(
  Widget picker, {
  CalendarThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  double width = 320.0,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: textScaler),
    child: Directionality(
      textDirection: direction,
      child: CalendarTheme(
        data: theme ?? steady,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: picker),
        ),
      ),
    ),
  );
}

Finder hourRow(int number) {
  return find.byKey(timePickerHourRowKey(number));
}

Finder minuteRow(int minute) {
  return find.byKey(timePickerMinuteRowKey(minute));
}

Finder hourColumn() {
  return find.byKey(timePickerHourColumnKey);
}

Finder minuteColumn() {
  return find.byKey(timePickerMinuteColumnKey);
}

/// The y of the band's centre, the middle of a column's five rows, in
/// global logical pixels.
double bandY(WidgetTester tester) {
  return tester.getCenter(hourColumn()).dy;
}

/// A column's row extent: a fifth of its height.
double extentOf(WidgetTester tester) {
  return tester.getSize(hourColumn()).height / 5.0;
}

/// Whether [row]'s centre lies within 0.5 px of the band's.
bool onBand(WidgetTester tester, Finder row) {
  return (tester.getCenter(row).dy - bandY(tester)).abs() < 0.5;
}

/// Expects the hour row [hour] and the minute row [minute] on the band.
void expectOnBand(WidgetTester tester, int hour, int minute) {
  expect(onBand(tester, hourRow(hour)), isTrue, reason: "hour $hour");
  expect(onBand(tester, minuteRow(minute)), isTrue, reason: "minute $minute");
}

/// The numbers of the rows of the column whose row keys [keyOf] makes,
/// among 0 to 59.
List<int> rowNumbers(ValueKey<String> Function(int number) keyOf) {
  return <int>[
    for (var number = 0; number < 60; number++)
      if (find.byKey(keyOf(number)).evaluate().isNotEmpty) number,
  ];
}

/// The style the [RichText] of [row] paints in.
TextStyle rowStyle(WidgetTester tester, Finder row) {
  return tester
      .widget<RichText>(find.descendant(of: row, matching: find.byType(RichText)))
      .text
      .style!;
}

SemanticsData semanticsOf(WidgetTester tester, Finder finder) {
  return tester.getSemantics(finder).getSemanticsData();
}

void performAction(WidgetTester tester, Finder finder, SemanticsAction action) {
  final node = tester.getSemantics(finder);
  node.owner!.performAction(node.id, action);
}

/// Pumps frames of [interval] until none is scheduled, calling [onFrame]
/// after each; returns the frames pumped.
Future<int> pumpFrames(
  WidgetTester tester, {
  Duration interval = const Duration(milliseconds: 16),
  void Function(int frame)? onFrame,
}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame) {
    await tester.pump(interval);
    frames++;
    onFrame?.call(frames);
    expect(frames, lessThan(1000));
  }
  return frames;
}

/// Moves [gesture] by [dy] in steps of at most 8 px, 50 ms apart, so its
/// release has no velocity.
Future<void> slowMove(WidgetTester tester, TestGesture gesture, double dy) async {
  var left = dy;
  while (left.abs() > 0.0) {
    final step = left.abs() > 8.0 ? 8.0 * left.sign : left;
    await gesture.moveBy(Offset(0.0, step));
    await tester.pump(const Duration(milliseconds: 50));
    left -= step;
  }
  await tester.pump(const Duration(milliseconds: 200));
}

/// Holds a drag on [row], moved past the drag slop and then so that [row]
/// lies [rows] row extents below the band, and returns the gesture.
Future<TestGesture> holdOn(
  WidgetTester tester,
  Finder row, {
  double rows = 0.0,
}) async {
  final gesture = await tester.startGesture(tester.getCenter(row));
  await gesture.moveBy(const Offset(0.0, -20.0));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveBy(const Offset(0.0, 20.0));
  await tester.pump(const Duration(milliseconds: 50));
  final to = bandY(tester) + rows * extentOf(tester);
  await slowMove(tester, gesture, to - tester.getCenter(row).dy);
  return gesture;
}

/// Whether [ancestor] is [element] or lies above it.
bool isAtOrAbove(Element ancestor, Element element) {
  var found = identical(ancestor, element);
  element.visitAncestorElements((above) {
    found = found || identical(above, ancestor);
    return !found;
  });
  return found;
}

/// Runs [body] and returns the elements at or under [picker] that rebuilt
/// meanwhile, as [debugOnRebuildDirtyWidget] reports them.
Future<List<Element>> rebuildsUnder(
  Element picker,
  Future<void> Function() body,
) async {
  final rebuilt = <Element>[];
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    if (isAtOrAbove(picker, element)) {
      rebuilt.add(element);
    }
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

/// Whether the primary focus belongs to the control [finder] finds: its
/// node's widget lies at, above or under it, with no other control
/// between them.
bool focusedUnder(Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context is! Element) {
    return false;
  }
  return finder.evaluate().any((element) {
    if (isAtOrAbove(element, context)) {
      return true;
    }
    // A control's key may lie under its Focus: the nearest Focus above the
    // keyed element is then the focused one.
    return isAtOrAbove(context, element) &&
        identical(Focus.of(element), FocusManager.instance.primaryFocus);
  });
}

/// Throws an [ArgumentError] whose name is [name].
Matcher throwsArgumentNamed(String name) {
  return throwsA(isArgumentError.having((error) => error.name, "name", name));
}

void main() {
  testWidgets("PK1 a picker builds through the package barrel's "
      "CalendarTimePicker and shows its Hour header", (tester) async {
    await tester.pumpWidget(
      host(CalendarTimePicker(value: 570, onChanged: (value) {})),
    );
    expect(find.byType(CalendarTimePicker), findsOneWidget);
    expect(find.text("Hour"), findsOneWidget);
    expect(find.text("Minute"), findsOneWidget);
  });

  testWidgets("PK2 the 24-hour clock lists 00 to 23 and the step's minutes, "
      "the value's on the band and no toggle; the 12-hour clock lists 12 and "
      "01 to 11 in the value's half, the toggle on it", (tester) async {
    await tester.pumpWidget(
      host(CalendarTimePicker(value: 570, onChanged: (value) {})),
    );
    expect(rowNumbers(timePickerHourRowKey), <int>[
      for (var hour = 0; hour < 24; hour++) hour,
    ]);
    expect(hourRow(24), findsNothing);
    expect(rowNumbers(timePickerMinuteRowKey), <int>[0, 15, 30, 45]);
    expect(find.text("09"), findsOneWidget);
    expectOnBand(tester, 9, 30);
    expect(onBand(tester, hourRow(10)), isFalse);
    expect(find.byKey(timePickerToggleKey), findsNothing);
    expect(find.byKey(timePickerBandKey), findsOneWidget);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 870,
          hourLabelFormat: CalendarHourLabelFormat.twelveHour,
          onChanged: (value) {},
        ),
      ),
    );
    expect(rowNumbers(timePickerHourRowKey), <int>[
      for (var hour = 12; hour < 24; hour++) hour,
    ]);
    for (final label in <String>["12", "01", "02", "06", "11"]) {
      expect(
        find.descendant(of: hourColumn(), matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text("13"), findsNothing);
    expectOnBand(tester, 14, 30);
    expect(find.byKey(timePickerToggleKey), findsOneWidget);
    expect(
      semanticsOf(tester, find.byKey(timePickerPmKey)).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      semanticsOf(tester, find.byKey(timePickerAmKey)).flagsCollection.isSelected,
      Tristate.isFalse,
    );
  });

  testWidgets("PK3 a max of 1440 adds the hour 24, whose one minute reports "
      "1440; on the 12-hour clock 12 AM 00 is 1440 in an end's range, and "
      "in a range holding both while the value is 1440", (tester) async {
    final calls = <int?>[];
    Widget picker(
      int value, {
      int min = 0,
      CalendarHourLabelFormat format = CalendarHourLabelFormat.twentyFourHour,
    }) {
      return host(
        CalendarTimePicker(
          value: value,
          min: min,
          max: 1440,
          hourLabelFormat: format,
          onChanged: calls.add,
        ),
      );
    }

    await tester.pumpWidget(picker(22 * 60));
    expect(rowNumbers(timePickerHourRowKey).last, 24);
    await tester.tap(hourRow(24));
    await tester.pumpAndSettle();
    expect(calls, <int?>[1440]);
    expect(rowNumbers(timePickerMinuteRowKey), <int>[0]);
    expectOnBand(tester, 24, 0);

    calls.clear();
    const twelve = CalendarHourLabelFormat.twelveHour;
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(15, min: 1, format: twelve));
    expectOnBand(tester, 0, 15);
    expect(
      semanticsOf(tester, find.byKey(timePickerAmKey)).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    await tester.tap(minuteRow(0));
    await tester.pumpAndSettle();
    expect(calls, <int?>[1440]);
    await tester.pumpWidget(picker(1440, min: 1, format: twelve));
    await tester.pumpAndSettle();
    expectOnBand(tester, 0, 0);
    await tester.tap(minuteRow(15));
    await tester.pumpAndSettle();
    expect(calls, <int?>[1440, 15]);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(1440, format: twelve));
    expectOnBand(tester, 0, 0);
    await tester.tap(minuteRow(0));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(0, format: twelve));
    await tester.tap(minuteRow(0));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets("PK4 a refused row takes no tap, the keys skip refused rows, "
      "and a half with no time to pick takes no tap", (tester) async {
    final calls = <int?>[];
    final hour = FocusNode();
    addTearDown(hour.dispose);
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 555,
          focusNode: hour,
          isEnabled: (minute) {
            return minute != 570 && minute ~/ 60 != 10;
          },
          onChanged: calls.add,
        ),
      ),
    );
    await tester.tap(minuteRow(30), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(hourRow(10), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expectOnBand(tester, 9, 15);

    hour.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(calls, <int?>[675]);
    expectOnBand(tester, 11, 15);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(calls, <int?>[675, 555]);
    expectOnBand(tester, 9, 15);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(calls.last, 585);
    expectOnBand(tester, 9, 45);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(calls.last, 555);
    expectOnBand(tester, 9, 15);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 540,
          hourLabelFormat: CalendarHourLabelFormat.twelveHour,
          isEnabled: (minute) {
            return minute < 720;
          },
          onChanged: calls.add,
        ),
      ),
    );
    await tester.tap(find.byKey(timePickerPmKey));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(
      semanticsOf(tester, find.byKey(timePickerPmKey)).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
  });

  testWidgets("PK5 a value off the step shows its own minute row, and a "
      "refused value shows selected with no report", (tester) async {
    final calls = <int?>[];
    await tester.pumpWidget(
      host(CalendarTimePicker(value: 550, onChanged: calls.add)),
    );
    expect(rowNumbers(timePickerMinuteRowKey), <int>[0, 10, 15, 30, 45]);
    expectOnBand(tester, 9, 10);

    bool refuses(int minute) {
      return minute != 570;
    }

    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 570,
          isEnabled: (minute) {
            return refuses(minute);
          },
          onChanged: calls.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectOnBand(tester, 9, 30);
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 570,
          isEnabled: (minute) {
            return refuses(minute);
          },
          onChanged: calls.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectOnBand(tester, 9, 30);
    expect(calls, isEmpty);
  });

  testWidgets("PK6 a new hour or half keeps the minute where it may be "
      "picked, and otherwise takes the nearest, the earlier on a tie", (
    tester,
  ) async {
    final calls = <int?>[];
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 615,
          isEnabled: (minute) {
            return minute != 675;
          },
          onChanged: calls.add,
        ),
      ),
    );
    await tester.tap(hourRow(11));
    await tester.pumpAndSettle();
    expect(calls, <int?>[660]);
    expectOnBand(tester, 11, 0);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 615,
          hourLabelFormat: CalendarHourLabelFormat.twelveHour,
          isEnabled: (minute) {
            return minute != 1320 && minute != 1335;
          },
          onChanged: calls.add,
        ),
      ),
    );
    await tester.tap(find.byKey(timePickerPmKey));
    await tester.pumpAndSettle();
    expect(calls, <int?>[1350]);
    expectOnBand(tester, 22, 30);
  });

  testWidgets("PK7 a fling reports once, after the column settles, the row "
      "it settled on, a tap on a row once, and a pick in the other column "
      "while the fling lands joins that one report", (tester) async {
    final calls = <int?>[];
    await tester.pumpWidget(
      host(CalendarTimePicker(value: 570, onChanged: calls.add)),
    );
    await tester.fling(hourColumn(), const Offset(0.0, -120.0), 600.0);
    expect(calls, isEmpty);
    var frames = 0;
    while (calls.isEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      expect(frames, lessThan(500));
    }
    expect(frames, greaterThan(1));
    expect(calls, hasLength(1));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    final picked = calls.single!;
    expect(picked % 60, 30);
    expect(picked ~/ 60, greaterThan(10));
    expectOnBand(tester, picked ~/ 60, 30);

    calls.clear();
    await tester.tap(minuteRow(45));
    await tester.pumpAndSettle();
    expect(calls, <int?>[picked ~/ 60 * 60 + 45]);

    calls.clear();
    final hour = picked ~/ 60;
    await tester.fling(hourColumn(), const Offset(0.0, 120.0), 600.0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(calls, isEmpty);
    await tester.tap(minuteRow(15));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The minute settled while the hour still lands.
    expect(calls, isEmpty);
    while (calls.isEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      expect(frames, lessThan(1000));
    }
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single! % 60, 15);
    expect(calls.single! ~/ 60, lessThan(hour));
    expectOnBand(tester, calls.single! ~/ 60, 15);
  });

  testWidgets("PK8 a drag's pointer moves and the frames of its landing "
      "build nothing, lay out nothing and ask isEnabled nothing; a host "
      "value's motion paints a row once a frame", (tester) async {
    final calls = <int?>[];
    var asked = 0;
    Widget picker(int value) {
      return host(
        CalendarTimePicker(
          value: value,
          isEnabled: (minute) {
            asked++;
            return true;
          },
          onChanged: calls.add,
        ),
      );
    }

    await tester.pumpWidget(picker(570));
    final asks = asked;
    expect(asks, greaterThan(0));
    final pickerElement = tester.element(find.byType(CalendarTimePicker));
    final rebuilt = <Element>[];
    final logged = <String>[];
    final print = debugPrint;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      var under = identical(element, pickerElement);
      element.visitAncestorElements((ancestor) {
        under = under || identical(ancestor, pickerElement);
        return !under;
      });
      if (under) {
        rebuilt.add(element);
      }
    };
    debugPrint = (String? message, {int? wrapWidth}) {
      logged.add(message ?? "");
    };
    debugPrintLayouts = true;
    try {
      final gesture = await tester.startGesture(tester.getCenter(hourColumn()));
      for (var move = 0; move < 10; move++) {
        await gesture.moveBy(const Offset(0.0, -12.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      while (calls.isEmpty) {
        expect(asked, asks);
        expect(rebuilt, isEmpty);
        expect(
          logged.where((line) {
            return line.contains("Laying out");
          }),
          isEmpty,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
      debugPrint = print;
      debugPrintLayouts = false;
    }
    // Setup sanity: the rebuild hook saw the settle's rebuild.
    expect(rebuilt, isNotEmpty);
    expect(calls, hasLength(1));
    await tester.pumpAndSettle();

    await tester.pumpWidget(picker(570));
    await tester.pumpAndSettle();
    final row = tester.renderObject(hourRow(9));
    var paints = 0;
    debugOnProfilePaint = (renderObject) {
      if (identical(renderObject, row)) {
        paints++;
      }
    };
    final counts = <int>[];
    try {
      await tester.pumpWidget(picker(630));
      await pumpFrames(
        tester,
        onFrame: (frame) {
          counts.add(paints);
          paints = 0;
        },
      );
    } finally {
      debugOnProfilePaint = null;
    }
    expect(counts.length, greaterThan(5));
    expect(counts, everyElement(1));
  });

  testWidgets("PK9 the keys move over the enabled rows without wrapping, two "
      "digits pick a row, Right moves to Minute, and A and P pick the "
      "half", (tester) async {
    final calls = <int?>[];
    final hour = FocusNode();
    addTearDown(hour.dispose);
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 570,
          focusNode: hour,
          isEnabled: (minute) {
            return minute ~/ 60 != 10;
          },
          onChanged: calls.add,
        ),
      ),
    );
    hour.requestFocus();
    await tester.pump();
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.arrowDown);
    expect(calls.last, 11 * 60 + 30);
    await press(LogicalKeyboardKey.arrowUp);
    expect(calls.last, 9 * 60 + 30);
    await press(LogicalKeyboardKey.home);
    expect(calls.last, 30);
    await press(LogicalKeyboardKey.end);
    expect(calls.last, 23 * 60 + 30);
    final count = calls.length;
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.pageDown);
    expect(calls, hasLength(count));
    expectOnBand(tester, 23, 30);
    await press(LogicalKeyboardKey.pageUp);
    expect(calls.last, 18 * 60 + 30);
    await press(LogicalKeyboardKey.arrowUp);
    expect(calls.last, 17 * 60 + 30);
    await press(LogicalKeyboardKey.pageDown);
    expect(calls.last, 22 * 60 + 30);
    await press(LogicalKeyboardKey.pageDown);
    expect(calls.last, 23 * 60 + 30);
    await press(LogicalKeyboardKey.home);
    expect(calls.last, 30);
    await press(LogicalKeyboardKey.pageDown);
    expect(calls.last, 5 * 60 + 30);
    await press(LogicalKeyboardKey.pageUp);
    expect(calls.last, 30);
    final atStart = calls.length;
    await press(LogicalKeyboardKey.arrowUp);
    await press(LogicalKeyboardKey.pageUp);
    expect(calls, hasLength(atStart));
    expectOnBand(tester, 0, 30);
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowDown);
    expect(calls.last, 2 * 60 + 30);
    await press(LogicalKeyboardKey.pageUp);
    expect(calls.last, 30);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pumpAndSettle();
    expect(calls.last, 14 * 60 + 30);
    expectOnBand(tester, 14, 30);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.pumpAndSettle();
    expect(calls.last, 7 * 60 + 30);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(calls.last, 60 + 30);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(hour.hasFocus, isFalse);
    expect(focusedUnder(minuteColumn()), isTrue);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 570,
          focusNode: hour,
          hourLabelFormat: CalendarHourLabelFormat.twelveHour,
          onChanged: calls.add,
        ),
      ),
    );
    hour.requestFocus();
    await tester.pump();
    await press(LogicalKeyboardKey.keyP);
    expect(calls, <int?>[21 * 60 + 30]);
    await press(LogicalKeyboardKey.keyA);
    expect(calls, <int?>[21 * 60 + 30, 9 * 60 + 30]);
  });

  testWidgets("PK10 each column is one adjustable node, named by its "
      "header, whose increase reports the next enabled row", (tester) async {
    final semantics = tester.ensureSemantics();
    final calls = <int?>[];
    Widget picker(int value) {
      return host(
        CalendarTimePicker(
          value: value,
          isEnabled: (minute) {
            return minute ~/ 60 != 10;
          },
          onChanged: calls.add,
        ),
      );
    }

    await tester.pumpWidget(picker(570));
    final data = semanticsOf(tester, hourColumn());
    expect(data.label, "Hour");
    expect(data.value, "09");
    expect(data.increasedValue, "11");
    expect(data.decreasedValue, "08");
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    expect(semanticsOf(tester, minuteColumn()).label, "Minute");
    expect(semanticsOf(tester, minuteColumn()).value, "30");
    performAction(tester, hourColumn(), SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(calls, <int?>[690]);

    await tester.pumpWidget(picker(1410));
    await tester.pumpAndSettle();
    final last = semanticsOf(tester, hourColumn());
    expect(last.value, "23");
    expect(last.hasAction(SemanticsAction.increase), isFalse);
    expect(last.increasedValue, "");
    expect(last.hasAction(SemanticsAction.decrease), isTrue);
    semantics.dispose();
  });

  testWidgets("PK11 Now picks the current minute rounded down to the step, "
      "disabled where that is refused; Clear reports null; with neither no "
      "footer; each ends a running fling with its own one report", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final calls = <int?>[];
    var now = 853;
    Widget picker({
      int? value = 570,
      bool Function(int minute)? isEnabled,
      bool withNow = true,
      bool clearable = false,
      int min = 0,
      CalendarHourLabelFormat format = CalendarHourLabelFormat.twentyFourHour,
      CalendarThemeData? theme,
    }) {
      return host(
        CalendarTimePicker(
          value: value,
          min: min,
          hourLabelFormat: format,
          isEnabled: isEnabled,
          now: withNow
              ? () {
                  return now;
                }
              : null,
          clearable: clearable,
          onChanged: calls.add,
        ),
        theme: theme,
      );
    }

    await tester.pumpWidget(picker());
    await tester.tap(find.byKey(timePickerNowKey));
    await tester.pumpAndSettle();
    expect(calls, <int?>[840]);
    expectOnBand(tester, 14, 0);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      picker(
        isEnabled: (minute) {
          return minute != 840;
        },
      ),
    );
    expect(
      semanticsOf(tester, find.byKey(timePickerNowKey)).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
    await tester.tap(find.byKey(timePickerNowKey));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(withNow: false, clearable: true));
    expect(find.byKey(timePickerNowKey), findsNothing);
    await tester.tap(find.byKey(timePickerClearKey));
    await tester.pumpAndSettle();
    expect(calls, <int?>[null]);
    expect(find.byKey(timePickerBandKey), findsNothing);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(withNow: false));
    expect(find.byKey(timePickerFooterKey), findsNothing);

    // Now across the halves, onto an hour whose minute rows differ.
    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      picker(value: 540, format: CalendarHourLabelFormat.twelveHour),
    );
    await tester.tap(find.byKey(timePickerNowKey));
    await tester.pumpAndSettle();
    expect(calls, <int?>[840]);
    expect(
      semanticsOf(tester, find.byKey(timePickerPmKey)).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expectOnBand(tester, 14, 0);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(value: 510, min: 495));
    expect(rowNumbers(timePickerMinuteRowKey), <int>[15, 30, 45]);
    await tester.tap(find.byKey(timePickerNowKey));
    await tester.pumpAndSettle();
    expect(calls, <int?>[840]);
    expectOnBand(tester, 14, 0);

    final slow = CalendarThemeData(
      motionDuration: const Duration(seconds: 1),
      motionCurve: Curves.easeIn,
    );
    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(clearable: true, theme: slow));
    await tester.fling(hourColumn(), const Offset(0.0, -60.0), 800.0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(calls, isEmpty);
    await tester.tap(find.byKey(timePickerNowKey));
    await tester.pumpAndSettle();
    expect(calls, <int?>[840]);
    expectOnBand(tester, 14, 0);

    calls.clear();
    await tester.fling(hourColumn(), const Offset(0.0, -60.0), 800.0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(calls, isEmpty);
    await tester.tap(find.byKey(timePickerClearKey));
    await tester.pumpAndSettle();
    expect(calls, <int?>[null]);
    expect(find.byKey(timePickerBandKey), findsNothing);
    semantics.dispose();
  });

  testWidgets("PK12 with a null onChanged no tap, fling, key or semantics "
      "action reports, the focused Hour keeps the focus, and Tab passes "
      "the picker by; with one, Tab visits Hour, Minute, the toggle, Now "
      "and Clear in that order", (tester) async {
    final semantics = tester.ensureSemantics();
    final calls = <int?>[];
    final hour = FocusNode();
    final before = FocusNode();
    final after = FocusNode();
    addTearDown(hour.dispose);
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    Widget harness(ValueChanged<int?>? onChanged, {bool twelve = false}) {
      return Shortcuts(
        shortcuts: WidgetsApp.defaultShortcuts,
        child: Actions(
          actions: WidgetsApp.defaultActions,
          child: host(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Focus(focusNode: before, child: const SizedBox(height: 10.0)),
                CalendarTimePicker(
                  value: 570,
                  focusNode: hour,
                  hourLabelFormat: twelve
                      ? CalendarHourLabelFormat.twelveHour
                      : CalendarHourLabelFormat.twentyFourHour,
                  now: () {
                    return 853;
                  },
                  clearable: true,
                  onChanged: onChanged,
                ),
                Focus(focusNode: after, child: const SizedBox(height: 10.0)),
              ],
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(harness(null));
    await tester.tap(hourRow(11), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.fling(hourColumn(), const Offset(0.0, -120.0), 800.0);
    await tester.pumpAndSettle();
    final data = semanticsOf(tester, hourColumn());
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    expect(data.hasAction(SemanticsAction.decrease), isFalse);
    expect(
      semanticsOf(tester, minuteColumn()).hasAction(SemanticsAction.increase),
      isFalse,
    );
    performAction(tester, hourColumn(), SemanticsAction.increase);
    await tester.pumpAndSettle();
    hour.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(hour.hasPrimaryFocus, isTrue);
    expect(calls, isEmpty);
    expectOnBand(tester, 9, 30);

    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(after.hasPrimaryFocus, isTrue);

    await tester.pumpWidget(harness(calls.add, twelve: true));
    before.requestFocus();
    await tester.pump();
    final visited = <String>[];
    for (var press = 0; press < 6; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      if (focused == hour) {
        visited.add("Hour");
      } else if (focused == after) {
        visited.add("after");
      } else if (focusedUnder(minuteColumn())) {
        visited.add("Minute");
      } else if (focusedUnder(find.byKey(timePickerToggleKey))) {
        visited.add("toggle");
      } else if (focusedUnder(find.byKey(timePickerNowKey))) {
        visited.add("Now");
      } else if (focusedUnder(find.byKey(timePickerClearKey))) {
        visited.add("Clear");
      } else {
        visited.add("other");
      }
    }
    expect(visited, <String>["Hour", "Minute", "toggle", "Now", "Clear", "after"]);
    semantics.dispose();
  });

  testWidgets("PK13 the picker draws its panel, band, rows and headers in "
      "the theme above it", (tester) async {
    final theme = CalendarThemeData(
      surface: const Color(0xFF101820),
      outline: const Color(0xFF203040),
      primaryTint: const Color(0xFF304050),
      text: const Color(0xFF405060),
      textSecondary: const Color(0xFF506070),
      disabledOpacity: 0.25,
      timePickerRowStyle: const TextStyle(
        fontSize: 18.0,
        fontWeight: FontWeight.w300,
      ),
      timePickerHeaderStyle: const TextStyle(
        fontSize: 11.0,
        fontWeight: FontWeight.w800,
      ),
    );
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 570,
          isEnabled: (minute) {
            return minute ~/ 60 != 10;
          },
          onChanged: (value) {},
        ),
        theme: theme,
      ),
    );
    final band = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(timePickerBandKey),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((band.decoration as BoxDecoration).color, theme.primaryTint);
    final enabled = rowStyle(tester, hourRow(9));
    expect(enabled.fontSize, 18.0);
    expect(enabled.fontWeight, FontWeight.w300);
    expect(enabled.color, theme.text);
    final disabled = rowStyle(tester, hourRow(10));
    expect(disabled.fontSize, 18.0);
    expect(disabled.color!.a, moreOrLessEquals(theme.text.a * 0.25));
    expect(disabled.color!.r, theme.text.r);
    final header = tester
        .widget<RichText>(
          find.descendant(of: find.text("Hour"), matching: find.byType(RichText)),
        )
        .text
        .style!;
    expect(header.fontSize, 11.0);
    expect(header.fontWeight, FontWeight.w800);
    expect(header.color, theme.textSecondary);
    final panel = tester
        .widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(CalendarTimePicker),
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .decoration as BoxDecoration;
    expect(panel.color, theme.surface);
    expect(panel.border, Border.all(color: theme.outline));
  });

  test("PK15 the constructor names the first value it does not take", () {
    void ok(int? value) {}
    for (final step in <int>[7, 0, -5]) {
      expect(() {
        return CalendarTimePicker(value: 0, minuteStep: step, onChanged: ok);
      }, throwsArgumentNamed("minuteStep"));
    }
    for (final min in <int>[-1, 1441]) {
      expect(() {
        return CalendarTimePicker(value: 0, min: min, max: 1440, onChanged: ok);
      }, throwsArgumentNamed("min"));
    }
    expect(() {
      return CalendarTimePicker(value: 0, max: 1441, onChanged: ok);
    }, throwsArgumentNamed("max"));
    expect(() {
      return CalendarTimePicker(value: 0, min: 200, max: 100, onChanged: ok);
    }, throwsArgumentNamed("max"));
    expect(() {
      return CalendarTimePicker(value: 1441, max: 1440, onChanged: ok);
    }, throwsArgumentNamed("value"));
    expect(() {
      return CalendarTimePicker(value: null, max: 1440, onChanged: ok);
    }, returnsNormally);
  });

  testWidgets("PK20 the bounds leave rows only for the hours and minutes "
      "inside them, and the value's own row besides", (tester) async {
    Widget picker(int value) {
      return host(
        CalendarTimePicker(
          value: value,
          min: 510,
          max: 1080,
          onChanged: (value) {},
        ),
      );
    }

    await tester.pumpWidget(picker(510));
    expect(rowNumbers(timePickerHourRowKey), <int>[
      for (var hour = 8; hour <= 18; hour++) hour,
    ]);
    expect(rowNumbers(timePickerMinuteRowKey), <int>[30, 45]);
    await tester.pumpWidget(picker(1080));
    await tester.pumpAndSettle();
    expect(rowNumbers(timePickerMinuteRowKey), <int>[0]);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(420));
    expect(rowNumbers(timePickerHourRowKey), <int>[
      for (var hour = 7; hour <= 18; hour++) hour,
    ]);
    expect(rowNumbers(timePickerMinuteRowKey), <int>[0]);
    expectOnBand(tester, 7, 0);
  });

  testWidgets("PK21 a host value moves the columns over the theme's motion "
      "on its curve, at once under a zero duration, and reports "
      "nothing", (tester) async {
    final calls = <int?>[];
    final linear = CalendarThemeData(
      motionDuration: const Duration(seconds: 1),
      motionCurve: Curves.linear,
    );
    Widget picker(int value, CalendarThemeData theme) {
      return host(
        CalendarTimePicker(value: value, onChanged: calls.add),
        theme: theme,
      );
    }

    await tester.pumpWidget(picker(570, linear));
    await tester.pumpWidget(picker(870, linear));
    await tester.pump(const Duration(milliseconds: 500));
    final extent = extentOf(tester);
    expect(
      tester.getCenter(hourRow(9)).dy - bandY(tester),
      moreOrLessEquals(-2.5 * extent, epsilon: 0.5),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expectOnBand(tester, 14, 30);

    final off = CalendarThemeData(motionDuration: Duration.zero);
    await tester.pumpWidget(picker(870, off));
    await tester.pumpWidget(picker(1230, off));
    expectOnBand(tester, 20, 30);
    await tester.pump();
    expectOnBand(tester, 20, 30);
    expect(calls, isEmpty);
  });

  testWidgets("PK22 a host value waits while a column is held, and moves the "
      "columns once the drag ends", (tester) async {
    final calls = <int?>[];
    Widget picker(int value) {
      return host(CalendarTimePicker(value: value, onChanged: calls.add));
    }

    await tester.pumpWidget(picker(570));
    final gesture = await tester.startGesture(tester.getCenter(hourColumn()));
    for (var move = 0; move < 6; move++) {
      await gesture.moveBy(const Offset(0.0, -10.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final held = tester.getCenter(hourRow(9));
    await tester.pumpWidget(picker(870));
    expect(tester.getCenter(hourRow(9)), held);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(hourRow(9)), held);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getCenter(hourRow(9)), held);
    await gesture.up();
    await tester.pumpAndSettle();
    expectOnBand(tester, 14, 30);
    expect(calls, isEmpty);
  });

  testWidgets("PK23 each fade shows where rows lie past its edge, sliding in "
      "over the row before", (tester) async {
    Widget picker(int value) {
      return host(CalendarTimePicker(value: value, onChanged: (value) {}));
    }

    await tester.pumpWidget(picker(0));
    final column = tester.renderObject<RenderBox>(hourRow(0)).parent!;
    final extent = extentOf(tester);
    final width = (column as RenderBox).size.width;
    final top = Rect.fromLTWH(0.0, 0.0, width, extent);
    final bottom = Rect.fromLTWH(0.0, 4 * extent, width, extent);
    expect(column, isNot(paints..rect(rect: top)));
    expect(
      column,
      paints
        ..save()
        ..translate(x: 0.0, y: 0.0)
        ..rect(rect: bottom)
        ..restore(),
    );

    await tester.pumpWidget(picker(720));
    await tester.pumpAndSettle();
    expect(
      column,
      paints
        ..save()
        ..translate(x: 0.0, y: 0.0)
        ..rect(rect: top)
        ..restore()
        ..save()
        ..translate(x: 0.0, y: 0.0)
        ..rect(rect: bottom)
        ..restore(),
    );

    await tester.pumpWidget(picker(0));
    await tester.pumpAndSettle();
    final gesture = await holdOn(tester, hourRow(0), rows: -2.5);
    expect(
      tester.getCenter(hourRow(0)).dy - bandY(tester),
      moreOrLessEquals(-2.5 * extent),
    );
    expect(
      column,
      paints
        ..save()
        ..translate(x: 0.0, y: -0.5 * extent)
        ..rect(rect: top)
        ..restore(),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("PK24 a wheel event moves a column one row and reports once "
      "it settles", (tester) async {
    final calls = <int?>[];
    await tester.pumpWidget(
      host(CalendarTimePicker(value: 570, onChanged: calls.add)),
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(hourColumn())));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0.0, 20.0)));
    expect(calls, isEmpty);
    await tester.pumpAndSettle();
    expect(calls, <int?>[630]);
    expectOnBand(tester, 10, 30);
  });

  testWidgets("PK25 right to left, Hour still lies left of Minute and Right "
      "moves from Hour to Minute", (tester) async {
    final hour = FocusNode();
    addTearDown(hour.dispose);
    await tester.pumpWidget(
      host(
        CalendarTimePicker(value: 570, focusNode: hour, onChanged: (value) {}),
        direction: TextDirection.rtl,
      ),
    );
    expect(
      tester.getCenter(hourColumn()).dx,
      lessThan(tester.getCenter(minuteColumn()).dx),
    );
    hour.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(hour.hasFocus, isFalse);
    expect(focusedUnder(minuteColumn()), isTrue);
  });

  testWidgets("PK26 with a null value no band and no semantics value, a tap "
      "reports once, a touch on a disabled row reports nothing, a range "
      "with no row takes a drag and a release, and the 12-hour half is the "
      "first time's", (tester) async {
    final semantics = tester.ensureSemantics();
    final calls = <int?>[];
    Widget picker({
      int min = 0,
      int max = 1439,
      CalendarHourLabelFormat format = CalendarHourLabelFormat.twentyFourHour,
      bool Function(int minute)? isEnabled,
    }) {
      return host(
        CalendarTimePicker(
          value: null,
          min: min,
          max: max,
          hourLabelFormat: format,
          isEnabled: isEnabled,
          onChanged: calls.add,
        ),
      );
    }

    await tester.pumpWidget(picker(isEnabled: (minute) => minute != 30));
    expect(find.byKey(timePickerBandKey), findsNothing);
    expect(semanticsOf(tester, hourColumn()).value, "");
    expect(semanticsOf(tester, minuteColumn()).value, "");
    final touch = await tester.startGesture(tester.getCenter(minuteRow(30)));
    await tester.pump(const Duration(milliseconds: 100));
    await touch.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(minuteRow(15));
    await tester.pumpAndSettle();
    expect(calls, <int?>[15]);
    expect(find.byKey(timePickerBandKey), findsOneWidget);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(min: 5, max: 10));
    expect(rowNumbers(timePickerHourRowKey), isEmpty);
    expect(rowNumbers(timePickerMinuteRowKey), isEmpty);
    await tester.drag(hourColumn(), const Offset(0.0, -80.0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls, isEmpty);

    // A held column released onto a range that left it no rows.
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker());
    final held = await tester.startGesture(tester.getCenter(hourColumn()));
    await held.moveBy(const Offset(0.0, -30.0));
    await tester.pump(const Duration(milliseconds: 16));
    await held.moveBy(const Offset(0.0, -30.0));
    await tester.pump(const Duration(milliseconds: 16));
    // Setup sanity: the drag moved the column off its row.
    expect(onBand(tester, hourRow(0)), isFalse);
    await tester.pumpWidget(picker(min: 5, max: 10));
    await held.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls, isEmpty);
    expect(rowNumbers(timePickerHourRowKey), isEmpty);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      picker(min: 780, max: 1080, format: CalendarHourLabelFormat.twelveHour),
    );
    expect(
      semanticsOf(tester, find.byKey(timePickerPmKey)).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(rowNumbers(timePickerHourRowKey), <int>[13, 14, 15, 16, 17, 18]);
    semantics.dispose();
  });

  testWidgets("PK27 a new text scaler sizes the rows anew: a column at rest "
      "stays exactly on its row, and a motion under way lands and reports "
      "once", (tester) async {
    final calls = <int?>[];
    Widget picker(int? value, double scale, {bool Function(int)? isEnabled}) {
      return host(
        CalendarTimePicker(
          value: value,
          isEnabled: isEnabled,
          onChanged: calls.add,
        ),
        textScaler: TextScaler.linear(scale),
      );
    }

    await tester.pumpWidget(picker(570, 1.0));
    expect(extentOf(tester), 40.0);
    await tester.pumpWidget(picker(570, 2.0));
    expect(extentOf(tester), 44.0);
    expectOnBand(tester, 9, 30);
    expect(tester.getCenter(hourRow(9)).dy, bandY(tester));
    await tester.pumpAndSettle();

    await tester.pumpWidget(picker(570, 1.0));
    await tester.pumpWidget(picker(870, 2.0));
    await tester.pumpAndSettle();
    expectOnBand(tester, 14, 30);
    expect(calls, isEmpty);

    // A tap's motion across a new scaler.
    await tester.pumpWidget(picker(570, 1.0));
    await tester.pumpAndSettle();
    await tester.tap(hourRow(10));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(picker(570, 2.0));
    await tester.pumpAndSettle();
    expect(calls, <int?>[630]);
    expectOnBand(tester, 10, 30);
    await tester.tap(hourRow(11));
    await tester.pumpAndSettle();
    expect(calls, <int?>[630, 690]);

    // A null value at rest on row 9, whose offset a scaled one would miss
    // by a rounding error: a touch that neither moves nor stops it reports
    // nothing.
    calls.clear();
    bool fromNine(int minute) {
      return minute >= 540;
    }

    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(null, 1.0, isEnabled: fromNine));
    await tester.pumpWidget(picker(null, 2.0, isEnabled: fromNine));
    await tester.pumpAndSettle();
    expect(onBand(tester, hourRow(9)), isTrue);
    final touch = await tester.startGesture(tester.getCenter(hourRow(8)));
    await tester.pump(const Duration(milliseconds: 100));
    await touch.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets("PK28 rows that change under a motion keep it one motion, a "
      "refused target moving to the nearest resting row", (tester) async {
    final calls = <int?>[];
    Widget picker(int min, {bool Function(int)? isEnabled}) {
      return host(
        CalendarTimePicker(
          value: 540,
          min: min,
          isEnabled: isEnabled,
          onChanged: calls.add,
        ),
      );
    }

    bool notEleven(int minute) {
      return minute ~/ 60 != 11;
    }

    await tester.pumpWidget(picker(540));
    await tester.tap(hourRow(11));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(picker(480));
    expect(hourRow(8), findsOneWidget);
    await tester.pumpAndSettle();
    expect(calls, <int?>[660]);
    expectOnBand(tester, 11, 0);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(540));
    await tester.tap(hourRow(11));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(picker(540, isEnabled: notEleven));
    await tester.pumpAndSettle();
    expect(calls, <int?>[600]);
    expectOnBand(tester, 10, 0);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker(540));
    final gesture = await holdOn(tester, hourRow(11));
    expect(tester.getCenter(hourRow(11)).dy, moreOrLessEquals(bandY(tester)));
    await tester.pumpWidget(picker(540, isEnabled: notEleven));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, <int?>[600]);
    expectOnBand(tester, 10, 0);
  });

  testWidgets("PK29 under a zero motion a fling, a tap and Down each land "
      "on their row by the next frame and report once", (tester) async {
    final calls = <int?>[];
    final hour = FocusNode();
    addTearDown(hour.dispose);
    await tester.pumpWidget(
      host(
        CalendarTimePicker(value: 570, focusNode: hour, onChanged: calls.add),
        theme: CalendarThemeData(motionDuration: Duration.zero),
      ),
    );
    await tester.fling(hourColumn(), const Offset(0.0, -120.0), 800.0);
    await tester.pump();
    expect(calls, hasLength(1));
    expect(onBand(tester, hourRow(calls.single! ~/ 60)), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);

    final flung = calls.single! ~/ 60;

    calls.clear();
    await tester.tap(minuteRow(45));
    await tester.pump();
    expect(calls, <int?>[flung * 60 + 45]);
    expect(onBand(tester, minuteRow(45)), isTrue);

    calls.clear();
    hour.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(calls, <int?>[(flung + 1) * 60 + 45]);
    expect(onBand(tester, hourRow(flung + 1)), isTrue);
  });

  testWidgets("PK30 while a column flings, a tap on an enabled row picks "
      "it, and a touch on a disabled row or one that slides sideways lands "
      "it, each with one report", (tester) async {
    final calls = <int?>[];
    final slow = CalendarThemeData(
      motionDuration: const Duration(seconds: 1),
      motionCurve: Curves.easeIn,
    );
    Widget picker() {
      return host(
        CalendarTimePicker(
          value: 570,
          isEnabled: (minute) {
            return minute ~/ 60 % 2 == 1 || minute ~/ 60 == 0;
          },
          onChanged: calls.add,
        ),
        theme: slow,
      );
    }

    /// Flings Hour up until row 9 lies more than two rows off the band,
    /// and returns a row [want] takes that lies within 1.5 rows of it.
    Future<int> flingAndFind(bool Function(int hour) want) async {
      await tester.fling(hourColumn(), const Offset(0.0, -150.0), 1500.0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, isEmpty);
      final extent = extentOf(tester);
      expect(
        (tester.getCenter(hourRow(9)).dy - bandY(tester)).abs(),
        greaterThan(2 * extent),
      );
      expect(tester.binding.hasScheduledFrame, isTrue);
      final shown = <int>[
        for (var hour = 0; hour < 24; hour++)
          if (want(hour) &&
              (tester.getCenter(hourRow(hour)).dy - bandY(tester)).abs() <
                  1.5 * extent)
            hour,
      ];
      expect(shown, isNotEmpty);
      return shown.first;
    }

    await tester.pumpWidget(picker());
    final odd = await flingAndFind((hour) => hour.isOdd);
    await tester.tap(hourRow(odd));
    await tester.pumpAndSettle();
    expect(calls, <int?>[odd * 60 + 30]);
    expectOnBand(tester, odd, 30);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker());
    final even = await flingAndFind((hour) => hour.isEven);
    final touch = await tester.startGesture(tester.getCenter(hourRow(even)));
    await tester.pump(const Duration(milliseconds: 50));
    await touch.up();
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect((calls.single! ~/ 60).isOdd, isTrue);
    expectOnBand(tester, calls.single! ~/ 60, 30);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(picker());
    final other = await flingAndFind((hour) => hour.isOdd);
    final slide = await tester.startGesture(tester.getCenter(hourRow(other)));
    await slide.moveBy(const Offset(30.0, 0.0));
    await tester.pump(const Duration(milliseconds: 50));
    await slide.up();
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect((calls.single! ~/ 60).isOdd, isTrue);
    expectOnBand(tester, calls.single! ~/ 60, 30);
  });

  testWidgets("PK31 onChanged turning null ends a fling and a held drag "
      "without a report, the value's rows on the band, and a tap after it "
      "returns reports once", (tester) async {
    final calls = <int?>[];
    Widget picker(bool takes) {
      return host(
        CalendarTimePicker(value: 570, onChanged: takes ? calls.add : null),
      );
    }

    await tester.pumpWidget(picker(true));
    await tester.fling(hourColumn(), const Offset(0.0, -120.0), 800.0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(picker(false));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expectOnBand(tester, 9, 30);
    await tester.pumpWidget(picker(true));
    await tester.tap(hourRow(10));
    await tester.pumpAndSettle();
    expect(calls, <int?>[630]);

    calls.clear();
    final gesture = await tester.startGesture(tester.getCenter(hourColumn()));
    await gesture.moveBy(const Offset(0.0, -30.0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0.0, -30.0));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(picker(false));
    await gesture.moveBy(const Offset(0.0, -30.0));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(picker(true));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expectOnBand(tester, 9, 30);
    await tester.tap(hourRow(11));
    await tester.pumpAndSettle();
    expect(calls, <int?>[690]);
  });

  testWidgets("PK32 a column held without moving while the other column, "
      "the toggle or Now picks: the other column's pick and the toggle's "
      "wait for its release, Now reports at once, and the release picks "
      "from where it lies", (tester) async {
    final calls = <int?>[];
    Widget picker({
      CalendarHourLabelFormat format = CalendarHourLabelFormat.twentyFourHour,
    }) {
      return host(
        CalendarTimePicker(
          value: 570,
          hourLabelFormat: format,
          now: () {
            return 853;
          },
          // Row 8 takes no tap, so a touch on it holds the column alone.
          isEnabled: (minute) {
            return minute ~/ 60 != 8;
          },
          onChanged: calls.add,
        ),
      );
    }

    Future<TestGesture> holdHour(int pointer) async {
      final gesture = await tester.startGesture(
        tester.getCenter(hourRow(8)),
        pointer: pointer,
      );
      await tester.pump(const Duration(milliseconds: 100));
      return gesture;
    }

    await tester.pumpWidget(picker());
    final hold = await holdHour(7);
    await tester.tap(minuteRow(45), pointer: 8);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expectOnBand(tester, 9, 45);
    await hold.up();
    await tester.pumpAndSettle();
    expect(calls, <int?>[585]);
    expectOnBand(tester, 9, 45);

    calls.clear();
    final again = await holdHour(9);
    await tester.tap(find.byKey(timePickerNowKey), pointer: 10);
    await tester.pumpAndSettle();
    expect(calls, <int?>[840]);
    await again.up();
    await tester.pumpAndSettle();
    expect(calls, <int?>[840, 540]);
    expectOnBand(tester, 9, 0);

    calls.clear();
    await tester.pumpWidget(Container());
    await tester.pumpWidget(
      picker(format: CalendarHourLabelFormat.twelveHour),
    );
    final half = await holdHour(11);
    await tester.tap(find.byKey(timePickerPmKey), pointer: 12);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await half.up();
    await tester.pumpAndSettle();
    expect(calls, <int?>[21 * 60 + 30]);
    expectOnBand(tester, 21, 30);
  });

  testWidgets("PK33 under a parent that asks its intrinsic sizes the picker "
      "lays out at its natural size, and a new width lays it out again "
      "building nothing", (tester) async {
    Widget under(Widget child) {
      return MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: CalendarTheme(
            data: steady,
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      );
    }

    final picker = CalendarTimePicker(value: 570, onChanged: (value) {});
    await tester.pumpWidget(under(IntrinsicWidth(child: picker)));
    expect(tester.takeException(), isNull);
    // Two columns of 72 and the panel's padding of 8 each side.
    expect(tester.getSize(find.byType(CalendarTimePicker)).width, 160.0);

    Widget sized(double width) {
      return under(
        SizedBox(width: width, child: IntrinsicHeight(child: picker)),
      );
    }

    await tester.pumpWidget(sized(300.0));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(hourColumn()).height, 200.0);
    final wide = tester.getSize(hourColumn()).width;
    final rebuilt = await rebuildsUnder(
      tester.element(find.byType(CalendarTimePicker)),
      () {
        return tester.pumpWidget(sized(260.0));
      },
    );
    expect(tester.takeException(), isNull);
    expect(rebuilt, isEmpty);
    // Setup sanity: the new width reached the columns.
    expect(tester.getSize(hourColumn()).width, isNot(wide));
  }, skip: true);

  testWidgets("PK34 a new width lays the columns out again and builds no "
      "element under the picker", (tester) async {
    final picker = CalendarTimePicker(value: 570, onChanged: (value) {});
    await tester.pumpWidget(host(picker));
    final wide = tester.getSize(hourRow(9)).width;
    var narrow = wide;
    final rebuilt = await rebuildsUnder(
      tester.element(find.byType(CalendarTimePicker)),
      () async {
        await tester.pumpWidget(host(picker, width: 260.0));
        narrow = tester.getSize(hourRow(9)).width;
        await tester.pumpWidget(host(picker, width: 360.0));
      },
    );
    expect(rebuilt, isEmpty);
    // Setup sanity: the new width reached the rows.
    expect(narrow, isNot(wide));
  }, skip: true);

  testWidgets("PK35 Now and Clear end a finger's hold on a column: its lift "
      "neither picks from where it lies nor taps its row, and a pointer "
      "down after the pick taps as before", (tester) async {
    final calls = <int?>[];
    await tester.pumpWidget(
      host(
        CalendarTimePicker(
          value: 570,
          now: () {
            return 853;
          },
          clearable: true,
          onChanged: calls.add,
        ),
      ),
    );
    final now = await tester.startGesture(
      tester.getCenter(hourRow(9)),
      pointer: 9,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(timePickerNowKey), pointer: 10);
    await tester.pumpAndSettle();
    expect(calls, <int?>[840]);
    await now.up();
    await tester.pumpAndSettle();
    expect(calls, <int?>[840]);
    expectOnBand(tester, 14, 0);

    calls.clear();
    final clear = await tester.startGesture(
      tester.getCenter(hourRow(14)),
      pointer: 11,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(timePickerClearKey), pointer: 12);
    await tester.pumpAndSettle();
    expect(calls, <int?>[null]);
    await clear.up();
    await tester.pumpAndSettle();
    expect(calls, <int?>[null]);

    await tester.tap(hourRow(1));
    await tester.pumpAndSettle();
    expect(calls, <int?>[null, 60]);
  }, skip: true);
}
