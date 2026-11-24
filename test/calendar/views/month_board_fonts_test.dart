/// Month's bars in Roboto, from the Flutter SDK's cache, at larger text
/// sizes: a chip's title, a card's title and times, and a text size changed
/// while the board is up. Loaded for this file alone, so the other files
/// keep the test font.
library;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart'
    show debugLabelSizeMeasures;
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import 'date_labels_fonts_test.dart' show materialFont;

final DateTime tuesday = DateTime(2026, 4, 21);

/// The Monday of [tuesday]'s week, which keys its chips.
final DateTime monday = DateTime(2026, 4, 20);

/// The text scales the tests run at: none, and the larger ones a phone's
/// settings offer.
const List<double> scales = <double>[1.0, 1.3, 1.5, 2.0, 3.0];

/// A one-day all-day entry on [tuesday] with the id [id] and the title
/// "Trip".
CalendarEntry<String> tripOf(String id) {
  return CalendarEntry<String>(
    id: id,
    start: tuesday,
    end: CalendarDates.addDays(tuesday, 1),
    title: "Trip",
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: true,
  );
}

/// The paragraph of the [Text] [text] finds: its laid-out size and the size
/// its whole line takes.
({Size box, Size line}) paragraphOf(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  return (
    box: paragraph.size,
    line: paragraph.getDryLayout(const BoxConstraints()),
  );
}

/// April 2026's board in Roboto at the text [scale], [size] large, holding
/// [entries], under [layout].
Future<MemoryCalendarStore<String>> pumpMonth(
  WidgetTester tester, {
  required double scale,
  required Size size,
  required List<CalendarEntry<String>> entries,
  CalendarMonthLayout layout = CalendarMonthLayout.showAll,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final store = MemoryCalendarStore<String>(entries: entries);
  addTearDown(store.dispose);
  final now = ValueNotifier<CalendarNow>(
    CalendarNow(time: tuesday, today: tuesday),
  );
  addTearDown(now.dispose);
  await tester.pumpWidget(month(store, now, scale: scale, layout: layout));
  await tester.pumpAndSettle();
  return store;
}

/// The board [pumpMonth] pumps, at the text [scale].
Widget month(
  MemoryCalendarStore<String> store,
  ValueNotifier<CalendarNow> now, {
  required double scale,
  CalendarMonthLayout layout = CalendarMonthLayout.showAll,
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
      child: MonthBoard<String>(
        store: store,
        grid: CalendarMonthGrid.of(tuesday),
        layout: layout,
        selectedDay: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenDay: (day) {},
        onCreateOnDay: null,
        onOpenEntry: (id) {},
      ),
    ),
  );
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
    testWidgets("MF1 at text scale $scale a chip's title shows its whole "
        "line, in a chip 16 px tall at no text scaling", (tester) async {
      await pumpMonth(
        tester,
        scale: scale,
        size: const Size(800.0, 600.0),
        entries: <CalendarEntry<String>>[tripOf("trip")],
      );
      final chip = find.byKey(monthChipKey(monthSegmentKey("trip", monday)));
      final title = find.descendant(of: chip, matching: find.text("Trip"));
      // Setup sanity: the days show chips, not cards.
      expect(find.descendant(of: chip, matching: find.byType(Text)), findsOne);
      final paragraph = paragraphOf(tester, title);
      expect(
        paragraph.box.height,
        moreOrLessEquals(paragraph.line.height),
        reason: "line ${paragraph.line}, box ${paragraph.box}",
      );
      if (scale == 1.0) {
        expect(
          tester
              .getRect(
                find
                    .descendant(of: chip, matching: find.byType(ClipRRect))
                    .first,
              )
              .height,
          16.0,
        );
      }
    });

    testWidgets("MF2 at text scale $scale a card's title and times each "
        "lie whole inside the card, and nothing overflows", (tester) async {
      await pumpMonth(
        tester,
        scale: scale,
        size: const Size(1200.0, 2400.0),
        entries: <CalendarEntry<String>>[tripOf("trip")],
      );
      final card = find.byKey(monthChipKey(monthSegmentKey("trip", monday)));
      final lines = find.descendant(of: card, matching: find.byType(Text));
      // Setup sanity: the days show cards, a title over its times.
      expect(lines, findsNWidgets(2));
      final bar = tester.getRect(
        find.descendant(of: card, matching: find.byType(ClipRRect)).first,
      );
      for (final line in lines.evaluate()) {
        final rect = tester.getRect(find.byWidget(line.widget));
        expect(
          (rect.top >= bar.top - 0.5, rect.bottom <= bar.bottom + 0.5),
          (true, true),
          reason: "line $rect in $bar",
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("MF3 a text scale raised to 2 while the board is up builds "
      "every chip again at its taller lane, its title's line whole, and "
      "under fitScreen a week then holds fewer lanes, its +N more banner "
      "inside the day", (tester) async {
    final store = await pumpMonth(
      tester,
      scale: 1.0,
      size: const Size(800.0, 600.0),
      layout: CalendarMonthLayout.fitScreen,
      entries: <CalendarEntry<String>>[
        for (var i = 0; i < 8; i++) tripOf("trip$i"),
      ],
    );
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: tuesday, today: tuesday),
    );
    addTearDown(now.dispose);
    int shownChips() {
      var shown = 0;
      for (var i = 0; i < 8; i++) {
        if (find
            .byKey(monthChipKey(monthSegmentKey("trip$i", monday)))
            .evaluate()
            .isNotEmpty) {
          shown++;
        }
      }
      return shown;
    }

    final before = shownChips();
    // Setup sanity: the week hides some of Tuesday's chips at no scaling.
    expect(find.byKey(monthMoreKey(tuesday)), findsOne);
    await tester.pumpWidget(
      month(store, now, scale: 2.0, layout: CalendarMonthLayout.fitScreen),
    );
    await tester.pumpAndSettle();
    final after = shownChips();
    expect(after, lessThan(before));
    final title = find.descendant(
      of: find.byKey(monthChipKey(monthSegmentKey("trip0", monday))),
      matching: find.text("Trip"),
    );
    final paragraph = paragraphOf(tester, title);
    expect(
      paragraph.box.height,
      moreOrLessEquals(paragraph.line.height),
      reason: "line ${paragraph.line}, box ${paragraph.box}",
    );
    final day = tester.getRect(find.byKey(monthDayKey(tuesday)));
    expect(
      tester.getRect(find.byKey(monthMoreKey(tuesday))).bottom,
      lessThanOrEqualTo(day.bottom),
    );
  });

  testWidgets("MF4 rebuilt at the device's own text scale of 1, which "
      "TextScaler.noScaling, its unscaled measure, does not take as equal to "
      "it, the board lays out no label again", (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 600.0);
    addTearDown(tester.view.reset);
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[tripOf("a")],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: tuesday, today: tuesday),
    );
    addTearDown(now.dispose);
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: "Roboto"),
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MonthBoard<String>(
                store: store,
                grid: CalendarMonthGrid.of(tuesday),
                selectedDay: tuesday,
                now: now,
                onSelectDay: (day) {},
                onOpenDay: (day) {},
                onCreateOnDay: null,
                onOpenEntry: (id) {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scaler = MediaQuery.textScalerOf(
      tester.element(find.byType(MonthBoard<String>)),
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
