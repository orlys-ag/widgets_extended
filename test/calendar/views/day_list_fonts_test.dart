/// Agenda's time column in Roboto, from the Flutter SDK's cache, at larger
/// text sizes: an item's start, an all-day item's label and a gap row's
/// time; what measures them again; and a font loaded while the list is up.
/// Loaded for this file alone, so the other files keep the test font.
library;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import 'date_labels_fonts_test.dart' show drawnScaleOf, materialFont;

final DateTime tuesday = DateTime(2026, 4, 21);

/// [tuesday] at [hour] and [minute].
DateTime at(int hour, [int minute = 0]) {
  return DateTime(tuesday.year, tuesday.month, tuesday.day, hour, minute);
}

CalendarEntry<String> entryOf(
  String id,
  DateTime start,
  DateTime end, {
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: isAllDay,
  );
}

/// Agenda on [tuesday], holding an item from 10:45 to 11:15 and an
/// all-day item, with the hours 09:00 to 17:00, in edit mode, so the day
/// shows a gap row from 09:00 and one from 11:15. [pump] builds it again
/// with what it is given, the list keeping its state.
class Agenda {
  Agenda(this.tester);

  final WidgetTester tester;

  late final MemoryCalendarStore<String> store = MemoryCalendarStore<String>(
    entries: <CalendarEntry<String>>[
      entryOf("talk", at(10, 45), at(11, 15)),
      entryOf(
        "trip",
        tuesday,
        CalendarDates.addDays(tuesday, 1),
        isAllDay: true,
      ),
    ],
    hours: CalendarDayHours(9 * 60, 17 * 60),
  );

  late final ValueNotifier<CalendarNow> now = ValueNotifier<CalendarNow>(
    CalendarNow(time: DateTime(2026, 4, 25, 9), today: DateTime(2026, 4, 25)),
  );

  /// Pumps the list [width] wide in [fontFamily] at the text [scale], on
  /// [format]'s clock, under [theme] where it is given, and settles.
  Future<void> pump({
    required double scale,
    required CalendarHourLabelFormat format,
    double width = 400.0,
    String fontFamily = "Roboto",
    CalendarThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 800.0);
    tester.view.devicePixelRatio = 1.0;
    Widget list = DayList<String>(
      store: store,
      weekdays: CalendarWeekdaySet.all,
      format: format,
      hours: store.hours,
      editable: true,
      selectedDay: tuesday,
      now: now,
      onTopDay: (day) {},
      onCreateRange: (details) async {},
      onEdit: (id) {},
      onDelete: (id) {},
    );
    if (theme != null) {
      list = CalendarTheme(data: theme, child: list);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: fontFamily),
        home: Material(
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: list,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Pumps an [Agenda] [width] wide in Roboto at the text [scale], on
/// [format]'s clock.
Future<Agenda> pumpAgenda(
  WidgetTester tester, {
  required double scale,
  required CalendarHourLabelFormat format,
  double width = 400.0,
}) async {
  addTearDown(tester.view.reset);
  final agenda = Agenda(tester);
  addTearDown(agenda.store.dispose);
  addTearDown(agenda.now.dispose);
  await agenda.pump(scale: scale, format: format, width: width);
  return agenda;
}

/// The [Text] showing [text] inside the widget [of] finds.
Finder textIn(Finder of, String text) {
  final label = find.descendant(of: of, matching: find.text(text));
  expect(label, findsOneWidget, reason: text);
  return label;
}

/// The paragraph [label], a [Text], lays out.
RenderParagraph paragraphOf(WidgetTester tester, Finder label) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
}

/// How wide the test font lays out what [paragraph] lays out.
double testFontWidthOf(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: TextSpan(
      text: paragraph.text.toPlainText(),
      style: paragraph.text.style!.copyWith(fontFamily: "FlutterTest"),
    ),
    textScaler: paragraph.textScaler,
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Expects [label], a one-line [Text], to lie whole and at its full size
/// in [box]: not cut off at its end or to the box's height, not scaled
/// down, and within the box's top and bottom.
void expectWhole(WidgetTester tester, Finder label, Finder box, String what) {
  final paragraph = paragraphOf(tester, label);
  // Setup sanity: the label is laid out in Roboto, whose glyphs are
  // narrower than the test font's em squares.
  expect(
    paragraph.size.width,
    lessThan(0.8 * testFontWidthOf(paragraph)),
    reason: "$what in Roboto",
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: "$what cut off");
  expect(
    paragraph.size.height,
    moreOrLessEquals(paragraph.getMaxIntrinsicHeight(double.infinity)),
    reason: "$what cut to its box's height",
  );
  expect(drawnScaleOf(tester, label), moreOrLessEquals(1.0), reason: what);
  final rect = tester.getRect(label);
  final outer = tester.getRect(box);
  expect(
    rect.top >= outer.top - 0.01 && rect.bottom <= outer.bottom + 0.01,
    isTrue,
    reason: "$what at $rect overflows its row $outer",
  );
}

/// The gap row from [start] on [tuesday].
Finder gapRow(int start) {
  return find.byKey(dayListGapKey(tuesday, start));
}

void main() {
  setUpAll(() async {
    final roboto = FontLoader("Roboto")
      ..addFont(Future<ByteData>.value(materialFont("roboto-regular.ttf")))
      ..addFont(Future<ByteData>.value(materialFont("roboto-medium.ttf")))
      ..addFont(Future<ByteData>.value(materialFont("roboto-bold.ttf")));
    await roboto.load();
  });

  for (final (scale, format) in <(double, CalendarHourLabelFormat)>[
    (1.0, CalendarHourLabelFormat.twelveHour),
    (1.3, CalendarHourLabelFormat.twelveHour),
    (2.0, CalendarHourLabelFormat.twelveHour),
    (2.0, CalendarHourLabelFormat.twentyFourHour),
    (3.0, CalendarHourLabelFormat.twelveHour),
  ]) {
    testWidgets("AF1 in Roboto at text scale $scale on the ${format.name} "
        "clock, Agenda's time column shows an item's start, the all-day "
        "label and a gap row's time whole, and its column lines the cards "
        "up with the gap rows' lines", (tester) async {
      await pumpAgenda(tester, scale: scale, format: format);
      const strings = DefaultCalendarLocalizations();
      final start = strings.formatTime(10 * 60 + 45, format);
      final gap = strings.formatTime(11 * 60 + 15, format);
      final talk = find.byKey(dayListTimeKey("talk"));
      expectWhole(tester, textIn(talk, start), talk, "the start $start");
      final trip = find.byKey(dayListTimeKey("trip"));
      expectWhole(tester, textIn(trip, strings.allDay), trip, "all day");
      final row = gapRow(11 * 60 + 15);
      expectWhole(tester, textIn(row, gap), row, "the gap's $gap");
      expect(
        tester.getRect(talk).right,
        moreOrLessEquals(tester.getRect(textIn(row, gap)).right + 8.0),
        reason: "the item's column and the gap's end alike",
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("AF2 in Roboto at text scale 3 in a list 220 px wide, the "
      "time column takes no more than half the row, draws its times whole "
      "though scaled down, and overflows nothing", (tester) async {
    await pumpAgenda(
      tester,
      scale: 3.0,
      format: CalendarHourLabelFormat.twelveHour,
      width: 220.0,
    );
    const strings = DefaultCalendarLocalizations();
    final start = strings.formatTime(
      10 * 60 + 45,
      CalendarHourLabelFormat.twelveHour,
    );
    final talk = find.byKey(dayListTimeKey("talk"));
    final label = textIn(talk, start);
    expect(paragraphOf(tester, label).didExceedMaxLines, isFalse);
    expect(drawnScaleOf(tester, label), lessThan(1.0));
    expect(tester.getRect(talk).width, lessThanOrEqualTo((220.0 - 32.0) / 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets("AF3 a theme that changes only colours lays out no time label "
      "again, as each frame of a colour transition gives one, while a new "
      "text size measures them again", (tester) async {
    const format = CalendarHourLabelFormat.twelveHour;
    final agenda = await pumpAgenda(tester, scale: 1.0, format: format);
    const theme = CalendarThemeData.builtIn;
    await agenda.pump(scale: 1.0, format: format, theme: theme);
    final before = debugLabelSizeMeasures;
    final recoloured = theme.copyWith(
      textSecondary: const Color(0xFF00AA00),
      textMuted: const Color(0xFF0000AA),
      primary: const Color(0xFFAA0000),
    );
    await agenda.pump(scale: 1.0, format: format, theme: recoloured);
    final talk = find.byKey(dayListTimeKey("talk"));
    const strings = DefaultCalendarLocalizations();
    final start = textIn(talk, strings.formatTime(10 * 60 + 45, format));
    // Setup sanity: the new colours reach the time column.
    expect(
      paragraphOf(tester, start).text.style?.color,
      const Color(0xFF00AA00),
    );
    expect(debugLabelSizeMeasures, before);
    await agenda.pump(scale: 1.5, format: format, theme: recoloured);
    expect(debugLabelSizeMeasures, greaterThan(before));
  });

  testWidgets("AF4 a font loaded while Agenda is up measures its times "
      "again: the column narrows to the loaded font's widest time", (
    tester,
  ) async {
    const format = CalendarHourLabelFormat.twelveHour;
    addTearDown(tester.view.reset);
    final agenda = Agenda(tester);
    addTearDown(agenda.store.dispose);
    addTearDown(agenda.now.dispose);
    await agenda.pump(scale: 2.0, format: format, fontFamily: "LateRoboto");
    final talk = find.byKey(dayListTimeKey("talk"));
    final before = tester.getRect(talk).width;
    await tester.runAsync(() async {
      final late = FontLoader("LateRoboto")
        ..addFont(Future<ByteData>.value(materialFont("roboto-medium.ttf")));
      await late.load();
    });
    await tester.pumpAndSettle();
    const strings = DefaultCalendarLocalizations();
    final start = textIn(talk, strings.formatTime(10 * 60 + 45, format));
    final paragraph = paragraphOf(tester, start);
    // Setup sanity: the label now lays out in the loaded font, narrower
    // than the test font it laid out in before.
    expect(paragraph.size.width, lessThan(0.8 * testFontWidthOf(paragraph)));
    expect(before, greaterThan(paragraph.size.width + 8.0 + 20.0));
    expect(tester.getRect(talk).width, lessThan(before - 20.0));
    expect(drawnScaleOf(tester, start), moreOrLessEquals(1.0));
  });
}
