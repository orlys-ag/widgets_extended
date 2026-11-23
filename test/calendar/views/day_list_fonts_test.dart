/// Agenda's time column in Roboto, from the Flutter SDK's cache, at larger
/// text sizes: an item's start, an all-day item's label and a gap row's
/// time. Loaded for this file alone, so the other files keep the test font.
library;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
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

/// Pumps Agenda on [tuesday], [width] wide, in Roboto at the text [scale],
/// on [format]'s clock, holding an item from 10:45 to 11:15 and an all-day
/// item, with the hours 09:00 to 17:00, in edit mode, so the day shows a gap
/// row from 09:00 and one from 11:15.
Future<void> pumpAgenda(
  WidgetTester tester, {
  required double scale,
  required CalendarHourLabelFormat format,
  double width = 400.0,
}) async {
  tester.view.physicalSize = Size(width, 800.0);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = MemoryCalendarStore<String>(
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
  addTearDown(store.dispose);
  final now = ValueNotifier<CalendarNow>(
    CalendarNow(time: DateTime(2026, 4, 25, 9), today: DateTime(2026, 4, 25)),
  );
  addTearDown(now.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: "Roboto"),
      home: Material(
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: DayList<String>(
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
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The [Text] showing [text] inside the widget [of] finds.
Finder textIn(Finder of, String text) {
  final label = find.descendant(of: of, matching: find.text(text));
  expect(label, findsOneWidget, reason: text);
  return label;
}

/// Expects [label], a one-line [Text], to lie whole and at its full size
/// in [box]: not cut off at its end or to the box's height, not scaled
/// down, and within the box's top and bottom.
void expectWhole(WidgetTester tester, Finder label, Finder box, String what) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  // Setup sanity: the label is laid out in Roboto.
  expect(paragraph.text.style?.fontFamily, "Roboto", reason: what);
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
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(drawnScaleOf(tester, label), lessThan(1.0));
    expect(tester.getRect(talk).width, lessThanOrEqualTo((220.0 - 32.0) / 2));
    expect(tester.takeException(), isNull);
  });
}
