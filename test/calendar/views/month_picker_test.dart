/// The month picker on its own: the text scale its names draw at where the
/// theme's two name styles differ, and what a new selected month measures
/// again.
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
}
