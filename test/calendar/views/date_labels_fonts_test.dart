/// The day cells' and weekday headers' label boxes in Roboto, from the
/// Flutter SDK's cache: a proportional font, whose digits are narrower than
/// the test font's, and one loaded while a header is up. Loaded for this
/// file alone, so the other files keep the test font.
library;

import 'dart:io';

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

/// The bytes of [file] in the SDK's Material fonts.
ByteData materialFont(String file) {
  final root = Platform.environment["FLUTTER_ROOT"];
  if (root == null) {
    throw StateError("FLUTTER_ROOT is not set; run the tests with flutter.");
  }
  final bytes = File(
    "$root/bin/cache/artifacts/material_fonts/$file",
  ).readAsBytesSync();
  return ByteData.sublistView(bytes);
}

/// How many times larger [label], a [Text], draws than it lays out.
double drawnScaleOf(WidgetTester tester, Finder label) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  return tester.getRect(label).width / paragraph.size.width;
}

/// The least width of the box [label], a [Text] in a label box, lies in.
double boxWidthOf(WidgetTester tester, Finder label) {
  final box = tester.widget<ConstrainedBox>(
    find.ancestor(of: label, matching: find.byType(ConstrainedBox)).first,
  );
  return box.constraints.minWidth;
}

/// The width the widest of [labels] lays out at.
double widestOf(WidgetTester tester, Iterable<String> labels) {
  var widest = 0.0;
  for (final label in labels) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(label), matching: find.byType(RichText)),
    );
    if (paragraph.size.width > widest) {
      widest = paragraph.size.width;
    }
  }
  return widest;
}

void main() {
  setUpAll(() async {
    final roboto = FontLoader("Roboto")
      ..addFont(Future<ByteData>.value(materialFont("roboto-regular.ttf")))
      ..addFont(Future<ByteData>.value(materialFont("roboto-medium.ttf")))
      ..addFont(Future<ByteData>.value(materialFont("roboto-bold.ttf")));
    await roboto.load();
  });

  testWidgets("LF1 in Roboto at no text scaling, every day's number in the "
      "week strip draws at its full size", (tester) async {
    tester.view.physicalSize = const Size(360.0, 640.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final today = DateTime(2026, 4, 28);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: "Roboto"),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: WeekStrip<String>(
              store: store,
              selectedDay: today,
              today: today,
              weekdays: CalendarWeekdaySet.all,
              onSelectDay: (day) {},
              onBrowse: (day) {},
            ),
          ),
        ),
      ),
    );
    final numbers = <Finder>[
      for (var day = 27; day <= 30; day++) find.text("$day"),
      find.text("1"),
      find.text("2"),
      find.text("3"),
    ];
    // Setup sanity: Roboto's two digits lay out narrower than the test
    // font's two em.
    final number = tester.renderObject<RenderParagraph>(
      find.descendant(of: numbers.first, matching: find.byType(RichText)),
    );
    expect(number.size.width, lessThan(2.0 * 15.0 - 1.0));
    for (final number in numbers) {
      expect(number, findsOneWidget);
      expect(drawnScaleOf(tester, number), closeTo(1.0, 0.001));
    }
  });

  testWidgets("LF2 a weekday header measured before a font loads lays its "
      "names in a box of the loaded font's widest name", (tester) async {
    Widget header(int build) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: CalendarTheme(
          data: CalendarThemeData(
            weekdayHeaderStyle: const TextStyle(
              fontFamily: "Probe",
              fontSize: 12.0,
            ),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 700.0,
              child: WeekdayHeader(
                key: ValueKey<int>(build),
                weekdays: CalendarWeekdaySet.all,
                abbreviated: true,
              ),
            ),
          ),
        ),
      );
    }

    const names = <String>["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    await tester.pumpWidget(header(1));
    final before = boxWidthOf(tester, find.text("Wed"));
    // Setup sanity: before the font loads the box is the test font's
    // widest name, three em of 12 px.
    expect(before, closeTo(widestOf(tester, names), 0.01));
    expect(before, closeTo(36.0, 0.01));
    await tester.runAsync(() async {
      final probe = FontLoader("Probe")
        ..addFont(Future<ByteData>.value(materialFont("roboto-regular.ttf")));
      await probe.load();
    });
    await tester.pumpWidget(header(2));
    final after = boxWidthOf(tester, find.text("Wed"));
    // Setup sanity: the loaded font lays the names out narrower.
    expect(widestOf(tester, names), lessThan(before - 1.0));
    expect(after, closeTo(widestOf(tester, names), 0.01));
  });
}
