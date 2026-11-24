/// Week's and Day's all-day strip in Roboto, from the Flutter SDK's cache,
/// at larger text sizes: a bar's title, the count chip and the Less pill,
/// and a theme given at run time whose chip title outgrows a bar. Loaded
/// for this file alone, so the other files keep the test font.
library;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart'
    show debugLabelSizeMeasures;
import 'package:widgets_extended/calendar/views/pinch_zoom.dart'
    show defaultMinSlotHeight, minDayWidthHigh;
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';

import 'date_labels_fonts_test.dart' show drawnScaleOf, materialFont;
import 'timed_grid_strip_test.dart'
    show
        Harness,
        Shown,
        allDayOf,
        barFinder,
        firstSlotRect,
        monday,
        storeOf,
        stripRect,
        tuesday;

/// The text scales the tests run at: none, and the larger ones a phone's
/// settings offer.
const List<double> scales = <double>[1.0, 1.3, 1.5, 2.0, 3.0];

/// Whether the paragraph of the [Text] [text] finds lays its line out
/// whole in height: its box as tall as its line, and no line cut off.
bool wholeIn(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final line = paragraph.getDryLayout(const BoxConstraints());
  return (paragraph.size.height - line.height).abs() < 0.5 &&
      !paragraph.didExceedMaxLines;
}

/// Week from Monday in [size], its days [minDayWidthHigh] wide so no text a
/// test reads is scaled down for its width, holding a bar titled "Trip" on
/// Monday and six bars on Tuesday, which the collapsed strip counts.
Harness weekOf({Size size = const Size(800.0, 2000.0)}) {
  return Harness(
    storeOf(<CalendarEntry<String>>[
      allDayOf("b", monday, title: "Trip"),
      for (var i = 0; i < 6; i++) allDayOf("t$i", tuesday),
    ]),
    Shown.week(monday),
    minDayWidth: minDayWidthHigh,
    size: size,
  );
}

/// [harness]'s grid in Roboto at the text [scale], under [theme] where it
/// is given.
Widget weekApp(
  Harness harness, {
  required double scale,
  CalendarThemeData? theme,
}) {
  return MaterialApp(
    theme: ThemeData(fontFamily: "Roboto"),
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      );
    },
    home: Material(
      child: theme == null
          ? harness.grid()
          : CalendarTheme(data: theme, child: harness.grid()),
    ),
  );
}

/// Pumps [weekOf] in [size] at the text [scale] and settles.
Future<Harness> pumpWeek(
  WidgetTester tester, {
  required double scale,
  Size size = const Size(800.0, 2000.0),
}) async {
  final harness = weekOf(size: size);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = harness.size;
  addTearDown(tester.view.reset);
  addTearDown(harness.now.dispose);
  await tester.pumpWidget(weekApp(harness, scale: scale));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  setUpAll(() async {
    final roboto = FontLoader("Roboto")
      ..addFont(Future<ByteData>.value(materialFont("roboto-regular.ttf")))
      ..addFont(Future<ByteData>.value(materialFont("roboto-medium.ttf")))
      ..addFont(Future<ByteData>.value(materialFont("roboto-bold.ttf")));
    await roboto.load();
  });

  for (final scale in scales) {
    testWidgets("SF1 at text scale $scale a bar's title in the all-day strip "
        "shows its whole line, and the count chip draws its text at its own "
        "size, in rows 24 px tall at no text scaling", (tester) async {
      await pumpWeek(tester, scale: scale);
      final chip = find.byKey(allDayMoreKey(tuesday));
      // Setup sanity: collapsed, the strip counts Tuesday's bars.
      expect(chip, findsOne);
      expect(
        wholeIn(
          tester,
          find.descendant(of: barFinder("b"), matching: find.text("Trip")),
        ),
        isTrue,
      );
      final count = find.descendant(of: chip, matching: find.byType(Text));
      expect(drawnScaleOf(tester, count), moreOrLessEquals(1.0));
      if (scale == 1.0) {
        expect(stripRect(tester, Shown.week(monday), monday).height, 24.0);
      }
    });

    testWidgets("SF2 at text scale $scale the expanded strip's Less pill "
        "shows its word whole", (tester) async {
      await pumpWeek(tester, scale: scale);
      await tester.tap(find.byKey(allDayMoreKey(tuesday)));
      await tester.pumpAndSettle();
      final pill = find.byKey(allDayLessKey);
      // Setup sanity: expanded, the pill shows.
      expect(pill, findsOne);
      expect(
        wholeIn(tester, find.descendant(of: pill, matching: find.byType(Text))),
        isTrue,
      );
    });
  }

  testWidgets("SF3 a theme given while the grid is up that differs only in "
      "a chip title taller than a bar holds at no text scaling grows the "
      "strip's rows so a bar's title shows its whole line, also where the "
      "slots keep their least height", (tester) async {
    final harness = await pumpWeek(
      tester,
      scale: 1.0,
      size: const Size(800.0, 600.0),
    );
    final shown = Shown.week(monday);
    const builtIn = CalendarThemeData.builtIn;
    await tester.pumpWidget(weekApp(harness, scale: 1.0, theme: builtIn));
    await tester.pumpAndSettle();
    final row = stripRect(tester, shown, monday).height;
    final theme = builtIn.copyWith(
      chipTitleStyle: const TextStyle(fontSize: 24.0),
    );
    await tester.pumpWidget(weekApp(harness, scale: 1.0, theme: theme));
    await tester.pumpAndSettle();
    final title = find.descendant(
      of: barFinder("b"),
      matching: find.text("Trip"),
    );
    // Setup sanity: the slots keep their least height, so a taller strip
    // gives them no new height; and the new style reaches the bar, its line
    // taller than a bar of 20 px.
    expect(firstSlotRect(tester, shown, monday).height, defaultMinSlotHeight);
    expect(
      tester
          .renderObject<RenderParagraph>(title)
          .getDryLayout(const BoxConstraints())
          .height,
      greaterThan(20.0),
    );
    expect(wholeIn(tester, title), isTrue);
    expect(stripRect(tester, shown, monday).height, greaterThan(row));
  });

  testWidgets("SF4 a text scale raised to 2 while the grid is up grows the "
      "strip's rows so a bar's title shows its whole line, and one brought "
      "back to 1 lays them out 24 px tall again", (tester) async {
    final harness = await pumpWeek(tester, scale: 1.0);
    final shown = Shown.week(monday);
    final title = find.descendant(
      of: barFinder("b"),
      matching: find.text("Trip"),
    );
    await tester.pumpWidget(weekApp(harness, scale: 2.0));
    await tester.pumpAndSettle();
    expect(wholeIn(tester, title), isTrue);
    expect(stripRect(tester, shown, monday).height, greaterThan(24.0));
    await tester.pumpWidget(weekApp(harness, scale: 1.0));
    await tester.pumpAndSettle();
    expect(stripRect(tester, shown, monday).height, 24.0);
  });

  testWidgets("SF5 rebuilt at the device's own text scale of 1, which "
      "TextScaler.noScaling, its unscaled measure, does not take as equal to "
      "it, the grid lays out no label again", (tester) async {
    final harness = weekOf();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = harness.size;
    addTearDown(tester.view.reset);
    addTearDown(harness.now.dispose);
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: "Roboto"),
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return harness.grid();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scaler = MediaQuery.textScalerOf(
      tester.element(find.byType(TimedGrid<String>)),
    );
    expect(scaler == TextScaler.noScaling, isTrue);
    expect(TextScaler.noScaling == scaler, isFalse);
    final before = debugLabelSizeMeasures;
    for (var i = 0; i < 3; i++) {
      rebuild(() {});
      await tester.pump();
    }
    expect(debugLabelSizeMeasures, before);
  });
}
