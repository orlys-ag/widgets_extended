/// The month picker on its own: the text scale its names draw at where the
/// theme's two name styles differ, what a new selected month measures
/// again, the height of its rows, and the intrinsic height it answers.
library;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/month_picker.dart';

/// The months of 2026.
final List<DateTime> months = <DateTime>[
  for (var month = 1; month <= 12; month++) DateTime(2026, month),
];

/// Pumps a picker of 2026 [width] px wide with April selected and current,
/// its unmarked names in [name] px and its marked ones in [marked] px, or
/// with [selected] selected where it is given, and settles.
Future<void> pumpPicker(
  WidgetTester tester, {
  required double name,
  required double marked,
  double width = 240.0,
  DateTime? selected,
}) async {
  tester.view.physicalSize = Size(width, 400.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  const theme = CalendarThemeData.builtIn;
  await tester.pumpWidget(
    MaterialApp(
      home: CalendarTheme(
        data: theme.copyWith(
          monthNameStyle: TextStyle(fontSize: name),
          monthNameMarkedStyle: TextStyle(fontSize: marked),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: MonthPicker(
            year: 2026,
            selectedMonth: selected ?? DateTime(2026, 4),
            currentMonth: DateTime(2026, 4),
            onSelectMonth: (month) {},
            onBrowse: (year) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The [Text] of [month]'s name.
Finder nameOf(DateTime month) {
  return find.descendant(
    of: find.byKey(monthPickerMonthKey(month)),
    matching: find.byType(Text),
  );
}

void main() {
  // September's is the longest name: unmarked in the first case, and
  // selected in the second.
  for (final (name, marked, selected) in <(double, double, int)>[
    (22.0, 15.0, 4),
    (15.0, 22.0, 9),
  ]) {
    testWidgets("MP1 in a picker 240 px wide whose unmarked names are "
        "$name px and marked ones $marked px, with month $selected selected, "
        "every name draws whole at one text scale", (tester) async {
      await pumpPicker(
        tester,
        name: name,
        marked: marked,
        selected: DateTime(2026, selected),
      );
      final scalers = <TextScaler>{
        for (final month in months)
          tester.widget<Text>(nameOf(month)).textScaler!,
      };
      expect(scalers, hasLength(1));
      // Setup sanity: the widest name does not fit its cell at the text
      // size, so the names draw at a smaller one.
      expect(scalers.single.scale(10.0), lessThan(10.0));
      for (final month in months) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: nameOf(month), matching: find.byType(RichText)),
        );
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(
            paragraph.getMaxIntrinsicWidth(double.infinity) - 0.01,
          ),
          reason: "${month.month} cut off",
        );
      }
    });
  }

  testWidgets("MP2 a new selected month lays out no name again", (
    tester,
  ) async {
    await pumpPicker(tester, name: 22.0, marked: 15.0);
    final before = debugLabelSizeMeasures;
    await pumpPicker(
      tester,
      name: 22.0,
      marked: 15.0,
      selected: DateTime(2026, 9),
    );
    // Setup sanity: September is the selected month.
    final september = tester.widget<Text>(nameOf(DateTime(2026, 9)));
    expect(september.style?.fontSize, 15.0);
    expect(debugLabelSizeMeasures, before);
  });

  testWidgets("MP3 every row of a picker is as tall as a cell whose name is "
      "the tallest in either style, whichever months are marked, and the "
      "picker answers the height it lays out at as its intrinsic height, at "
      "its width and at one that scales its names otherwise, at rest and as "
      "it slides a year", (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    RenderBox picker() {
      return tester.renderObject<RenderBox>(find.byType(MonthPicker));
    }

    double cellHeight(DateTime month) {
      return tester.getSize(find.byKey(monthPickerMonthKey(month))).height;
    }

    await pumpPicker(tester, name: 15.0, marked: 30.0, width: 2400.0);
    final wide = picker().size.height;
    await pumpPicker(tester, name: 15.0, marked: 30.0, width: 1200.0);
    final box = picker();
    final marked = tester.getSize(nameOf(DateTime(2026, 4))).height;
    // Setup sanity: April's marked name is taller than an unmarked one and
    // than a day's circle, and the wider picker's names scale otherwise.
    expect(
      marked,
      greaterThan(tester.getSize(nameOf(DateTime(2026, 1))).height),
    );
    expect(marked, greaterThan(dayCircleSize));
    expect(wide, isNot(moreOrLessEquals(box.size.height)));

    final row = MonthCell.pillMargin.vertical + marked;
    for (final month in months) {
      expect(cellHeight(month), moreOrLessEquals(row), reason: "${month.month}");
    }
    expect(box.size.height, moreOrLessEquals(4 * row));
    for (final (width, height) in <(double, double)>[
      (1200.0, box.size.height),
      (2400.0, wide),
    ]) {
      expect(
        box.getMinIntrinsicHeight(width),
        moreOrLessEquals(height),
        reason: "at $width",
      );
      expect(
        box.getMaxIntrinsicHeight(width),
        moreOrLessEquals(height),
        reason: "at $width",
      );
    }

    // The first move goes to the touch slop.
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(MonthPicker)),
    );
    for (var move = 0; move < 3; move++) {
      await drag.moveBy(const Offset(-100.0, 0.0));
      await tester.pump();
    }
    // Setup sanity: 2027's months, none of them marked, come in.
    expect(find.text("January"), findsNWidgets(2));
    expect(
      box.getMaxIntrinsicHeight(1200.0),
      moreOrLessEquals(box.size.height),
    );
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets("MP4 under an IntrinsicHeight of a fixed width a picker lays "
      "out at the height it takes without one, and does again once a new "
      "text size gives its rows another height", (tester) async {
    tester.view.physicalSize = const Size(1200.0, 600.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Widget app({required bool intrinsic}) {
      final picker = MonthPicker(
        year: 2026,
        selectedMonth: DateTime(2026, 4),
        currentMonth: DateTime(2026, 4),
        onSelectMonth: (month) {},
        onBrowse: (year) {},
      );
      return MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1200.0,
            child: intrinsic ? IntrinsicHeight(child: picker) : picker,
          ),
        ),
      );
    }

    // From a larger text size to a smaller, so an answer kept from the
    // larger shows as a picker too tall rather than as an overflow.
    final heights = <bool, List<double>>{};
    for (final intrinsic in <bool>[false, true]) {
      final steps = heights[intrinsic] = <double>[];
      tester.platformDispatcher.textScaleFactorTestValue = 3.0;
      await tester.pumpWidget(app(intrinsic: intrinsic));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: "$intrinsic");
      steps.add(tester.getSize(find.byType(MonthPicker)).height);
      tester.platformDispatcher.textScaleFactorTestValue = 1.0;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: "$intrinsic");
      steps.add(tester.getSize(find.byType(MonthPicker)).height);
    }
    // Setup sanity: the larger text makes the rows taller.
    expect(heights[false]![0], greaterThan(heights[false]![1]));
    expect(heights[true]![0], moreOrLessEquals(heights[false]![0]));
    expect(heights[true]![1], moreOrLessEquals(heights[false]![1]));
  });
}
