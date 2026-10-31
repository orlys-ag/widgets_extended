/// Every text the calendar shows and every label, value, hint and tooltip a
/// screen reader hears comes from the [CalendarLocalizations] above it, and
/// follows a change of them: each view, built in English, switches to
/// localizations that bracket every string they write, and then each line,
/// its bracketed spans taken out, holds nothing but the commas and spaces
/// that joined them, entry content and bare numbers, in the views, the
/// header, the calendar card, the month picker and the default builders.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/composition/calendar_card.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/presentation/calendar_day_badges.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/month_picker.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

/// [text] between the brackets [_Marked] puts around each string it
/// writes.
String bracketed(String text) {
  return "[$text]";
}

/// English, with every string [bracketed], so a string the calendar
/// writes some other way, or a word it adds to one, reads outside the
/// brackets.
final class _Marked extends DefaultCalendarLocalizations {
  const _Marked();

  @override
  String monthName(int month) {
    return bracketed(super.monthName(month));
  }

  @override
  String weekdayAbbreviation(int weekday) {
    return bracketed(super.weekdayAbbreviation(weekday));
  }

  @override
  String weekdayShortName(int weekday) {
    return bracketed(super.weekdayShortName(weekday));
  }

  @override
  String weekdayLetter(int weekday) {
    return bracketed(super.weekdayLetter(weekday));
  }

  @override
  String dayLabel(DateTime day) {
    return bracketed(super.dayLabel(day));
  }

  @override
  String dayTitle(DateTime day, DateTime today) {
    return bracketed(super.dayTitle(day, today));
  }

  @override
  String monthYear(DateTime month) {
    return bracketed(super.monthYear(month));
  }

  @override
  String shortMonthYear(DateTime month) {
    return bracketed(super.shortMonthYear(month));
  }

  @override
  String formatTime(int minute, CalendarHourLabelFormat format) {
    return bracketed(super.formatTime(minute, format));
  }

  @override
  String formatTimeRange(int start, int end, CalendarHourLabelFormat format) {
    return bracketed(super.formatTimeRange(start, end, format));
  }

  @override
  String entryTimes(
    DateTime start,
    DateTime end,
    CalendarHourLabelFormat format,
  ) {
    return bracketed(super.entryTimes(start, end, format));
  }

  @override
  String get allDay {
    return bracketed(super.allDay);
  }

  @override
  String duration(int minutes) {
    return bracketed(super.duration(minutes));
  }

  @override
  String moreEntries(int count) {
    return bracketed(super.moreEntries(count));
  }

  @override
  String moreEntriesBefore(int count, String time) {
    return bracketed(super.moreEntriesBefore(count, time));
  }

  @override
  String moreEntriesAfter(int count, String time) {
    return bracketed(super.moreEntriesAfter(count, time));
  }

  @override
  String entryCount(int count) {
    return bracketed(super.entryCount(count));
  }

  @override
  String hiddenRow(
    DateTime day,
    int count,
    String time, {
    required bool above,
  }) {
    return bracketed(super.hiddenRow(day, count, time, above: above));
  }

  @override
  String hiddenEntries(int count) {
    return bracketed(super.hiddenEntries(count));
  }

  @override
  String moreCount(int count) {
    return bracketed(super.moreCount(count));
  }

  @override
  String earlierCount(int count) {
    return bracketed(super.earlierCount(count));
  }

  @override
  String laterCount(int count) {
    return bracketed(super.laterCount(count));
  }

  @override
  String allDayMore(int count) {
    return bracketed(super.allDayMore(count));
  }

  @override
  String get allDayLess {
    return bracketed(super.allDayLess);
  }

  @override
  String get showLess {
    return bracketed(super.showLess);
  }

  @override
  String get noLanding {
    return bracketed(super.noLanding);
  }

  @override
  String landing(
    DateTime start,
    DateTime end,
    DateTime today,
    CalendarHourLabelFormat format,
  ) {
    return bracketed(super.landing(start, end, today, format));
  }

  @override
  String entryLabel({
    required String title,
    required String? kind,
    required DateTime start,
    required DateTime end,
    required CalendarHourLabelFormat format,
    required bool pending,
  }) {
    final label = super.entryLabel(
      title: title,
      kind: kind,
      start: start,
      end: end,
      format: format,
      pending: pending,
    );
    return bracketed(label);
  }

  @override
  String get today {
    return bracketed(super.today);
  }

  @override
  String get openDayHint {
    return bracketed(super.openDayHint);
  }

  @override
  String get createEntryHint {
    return bracketed(super.createEntryHint);
  }

  @override
  String dayWithBadges(DateTime day, List<String?> kinds) {
    return bracketed(super.dayWithBadges(day, kinds));
  }

  @override
  String addEntryAt(String time) {
    return bracketed(super.addEntryAt(time));
  }

  @override
  String get readFailed {
    return bracketed(super.readFailed);
  }

  @override
  String get retry {
    return bracketed(super.retry);
  }

  @override
  String startsAt(String time) {
    return bracketed(super.startsAt(time));
  }

  @override
  String endsAt(String time) {
    return bracketed(super.endsAt(time));
  }

  @override
  String get agendaView {
    return bracketed(super.agendaView);
  }

  @override
  String get dayView {
    return bracketed(super.dayView);
  }

  @override
  String get weekView {
    return bracketed(super.weekView);
  }

  @override
  String get monthView {
    return bracketed(super.monthView);
  }

  @override
  String get previousDayTooltip {
    return bracketed(super.previousDayTooltip);
  }

  @override
  String get previousWeekTooltip {
    return bracketed(super.previousWeekTooltip);
  }

  @override
  String get previousMonthTooltip {
    return bracketed(super.previousMonthTooltip);
  }

  @override
  String get previousYearTooltip {
    return bracketed(super.previousYearTooltip);
  }

  @override
  String get nextDayTooltip {
    return bracketed(super.nextDayTooltip);
  }

  @override
  String get nextWeekTooltip {
    return bracketed(super.nextWeekTooltip);
  }

  @override
  String get nextMonthTooltip {
    return bracketed(super.nextMonthTooltip);
  }

  @override
  String get nextYearTooltip {
    return bracketed(super.nextYearTooltip);
  }

  @override
  String get pickMonthTooltip {
    return bracketed(super.pickMonthTooltip);
  }

  @override
  String get closeMonthsTooltip {
    return bracketed(super.closeMonthsTooltip);
  }

  @override
  String get viewMenuTooltip {
    return bracketed(super.viewMenuTooltip);
  }

  @override
  String get showMonthLabel {
    return bracketed(super.showMonthLabel);
  }

  @override
  String get showWeekLabel {
    return bracketed(super.showWeekLabel);
  }
}

class _MarkedDelegate extends LocalizationsDelegate<CalendarLocalizations> {
  const _MarkedDelegate();

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<CalendarLocalizations> load(Locale locale) {
    return SynchronousFuture<CalendarLocalizations>(const _Marked());
  }

  @override
  bool shouldReload(_MarkedDelegate old) {
    return false;
  }
}

const CalendarLocalizations marked = _Marked();

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime friday = DateTime(2026, 4, 24);
final DateTime saturday = DateTime(2026, 4, 25);

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// The calendar's hours, 08:00 to 18:00.
const CalendarDayHours office = CalendarDayHours(8 * 60, 18 * 60);

/// [hour]:[minute] on [day].
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// An entry titled [id] from [start] to [end].
CalendarEntry<String> entryOf(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// The week of Tuesday April 21 2026, each entry there for a text it
/// brings: an entry inside the hours, two wholly before or after them, one
/// that starts before them and one that ends after them, one over two
/// days, all-day entries enough to fold Week's strip, and one on a
/// Saturday, a weekday the calendar hides.
List<CalendarEntry<String>> weekEntries() {
  return <CalendarEntry<String>>[
    entryOf("Standup", at(tuesday, 9), at(tuesday, 9, 30)),
    entryOf("Early", at(tuesday, 6), at(tuesday, 7)),
    entryOf("Late", at(tuesday, 19), at(tuesday, 20)),
    entryOf("Straddle", at(tuesday, 7, 30), at(tuesday, 10)),
    entryOf("Overnight", at(wednesday, 17), at(thursday, 10)),
    entryOf("Trip", thursday, saturday),
    for (var i = 1; i <= 4; i++) entryOf("Errand $i", thursday, friday),
    entryOf("Review", at(friday, 16), at(friday, 19)),
    entryOf("Weekend", at(saturday, 10), at(saturday, 11)),
  ];
}

/// The kind of the entries titled Standup, the one badge kind.
const CalendarBadgeKind work = CalendarBadgeKind(
  color: Color(0xFFAA3355),
  label: "Work",
);

/// The texts the host wrote: the entries' titles and the badge kind's
/// label.
final Set<String> content = <String>{
  for (final entry in weekEntries()) entry.title,
  work.label,
};

/// [home] under a MaterialApp whose calendar localizations are [_Marked]
/// where [marked] is true and English otherwise.
Widget app(Widget home, {required bool marked}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    localizationsDelegates: <LocalizationsDelegate<Object?>>[
      marked ? const _MarkedDelegate() : DefaultCalendarLocalizations.delegate,
    ],
    home: home,
  );
}

/// Pumps an editable calendar on [store] and [controller], Monday to
/// Friday, under [app], and settles it.
Future<void> pumpCalendar(
  WidgetTester tester, {
  required CalendarStore<String> store,
  required CalendarController controller,
  required bool marked,
}) async {
  await tester.pumpWidget(
    app(
      CalendarView<String>(
        store: store,
        controller: controller,
        editable: true,
        weekdays: CalendarWeekdaySet.workweek,
        clock: fixedClock,
        entryKindOf: (entry) {
          return entry.title == "Standup" ? work.label : null;
        },
        dayBadges: CalendarDayBadges<String>(
          kinds: const <CalendarBadgeKind>[work],
          kindOf: (entry) {
            return entry.title == "Standup" ? work : null;
          },
        ),
      ),
      marked: marked,
    ),
  );
  await tester.pumpAndSettle();
}

/// Lays the test out in a view [width] wide and [height] tall.
void useView(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// The plain text of every [RichText] on stage, but an [Icon]'s glyph.
List<String> shownTexts(WidgetTester tester) {
  final icons = find
      .descendant(of: find.byType(Icon), matching: find.byType(RichText))
      .evaluate()
      .toSet();
  return <String>[
    for (final element in find.byType(RichText).evaluate())
      if (!icons.contains(element))
        (element.widget as RichText).text.toPlainText(),
  ];
}

/// The label, value, hint, tooltip and hint overrides of every node of the
/// semantics tree.
List<String> heardTexts(WidgetTester tester) {
  final texts = <String>[];
  bool visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    texts.addAll(<String>[data.label, data.value, data.hint, data.tooltip]);
    final overrides = node.hintOverrides;
    if (overrides != null) {
      texts.addAll(<String>[
        overrides.onTapHint ?? "",
        overrides.onLongPressHint ?? "",
      ]);
    }
    node.visitChildren(visit);
    return true;
  }

  var root = tester.getSemantics(find.byType(CalendarView<String>));
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return texts;
}

final RegExp _bareNumber = RegExp(r"^\+?\d+$");

/// A [bracketed] span with no bracket inside it.
final RegExp _innermost = RegExp(r"\[[^\[\]]*\]");

/// Nothing but the commas and spaces that join a label's parts.
final RegExp _joins = RegExp(r"^[\s,]*$");

/// [line] with its [bracketed] spans taken out, innermost first, until
/// none is left.
String unbracketed(String line) {
  var rest = line;
  while (true) {
    final next = rest.replaceAll(_innermost, "");
    if (next == rest) {
      return rest;
    }
    rest = next;
  }
}

/// The lines of [texts] that, [unbracketed], hold more than the commas
/// and spaces of [_joins] and are neither [content] nor a bare number,
/// such as a day's or a year's, or a "+N" count.
List<String> unmarked(Iterable<String> texts) {
  return <String>[
    for (final text in texts)
      for (final line in text.split("\n"))
        if (unbracketed(line) case final rest
            when !_joins.hasMatch(rest) &&
                !content.contains(rest.trim()) &&
                !_bareNumber.hasMatch(rest.trim()))
          line,
  ];
}

/// Expects no line on stage or in the semantics tree to be [unmarked]; a
/// line that is is named with where it was found.
void expectMarked(WidgetTester tester, String where) {
  expect(
    <String>[
      for (final line in unmarked(shownTexts(tester))) "shown: $line",
      for (final line in unmarked(heardTexts(tester))) "heard: $line",
    ],
    isEmpty,
    reason: where,
  );
}

/// A data source whose every read fails.
class FailingSource implements CalendarDataSource<String> {
  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    return Future<List<CalendarEntry<String>>>.error(
      StateError("The read failed."),
    );
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets("LZ1 Agenda, its header, calendar card and view menu, and the "
      "default card and add button builders switch to the localizations "
      "above them", (tester) async {
    useView(tester, 800.0, 2000.0);
    final semantics = tester.ensureSemantics();
    final store = MemoryCalendarStore<String>(
      entries: weekEntries(),
      hours: office,
    );
    final controller = CalendarController(
      view: CalendarViewKind.agenda,
      selectedDay: tuesday,
    );
    addTearDown(controller.dispose);
    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: false,
    );
    expect(unmarked(shownTexts(tester)), isNotEmpty);

    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: true,
    );
    expect(find.byKey(dayListHiddenKey(tuesday, above: true)), findsOneWidget);
    expect(find.byKey(dayListHiddenKey(tuesday, above: false)), findsOneWidget);
    expect(
      find.text(
        marked.startsAt(
          marked.formatTime(
            7 * 60 + 30,
            CalendarHourLabelFormat.twentyFourHour,
          ),
        ),
      ),
      findsOneWidget,
    );
    expectMarked(tester, "Agenda");

    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    expectMarked(tester, "Agenda's card folded");

    await tester.tap(find.byTooltip(marked.viewMenuTooltip));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<CalendarViewKind>), findsNWidgets(4));
    expectMarked(tester, "the view menu");
    semantics.dispose();
  });

  testWidgets("LZ2 Day's grid, its gutter and notices, and the default block "
      "and chip builders switch to the localizations above them, the hour "
      "labels the grid paints included", (tester) async {
    useView(tester, 800.0, 2000.0);
    final semantics = tester.ensureSemantics();
    final store = MemoryCalendarStore<String>(
      entries: weekEntries(),
      hours: office,
    );
    final controller = CalendarController(
      view: CalendarViewKind.day,
      selectedDay: tuesday,
    );
    addTearDown(controller.dispose);
    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: false,
    );
    expect(unmarked(shownTexts(tester)), isNotEmpty);
    final english = tester.allRenderObjects
        .whereType<RenderBoardViewport<GridKey>>()
        .single
        .foreground!;

    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: true,
    );
    expect(find.byKey(hiddenAboveKey(tuesday)), findsOneWidget);
    expect(find.byKey(hiddenBelowKey(tuesday)), findsOneWidget);
    expectMarked(tester, "Day");
    final foreground = tester.allRenderObjects
        .whereType<RenderBoardViewport<GridKey>>()
        .single
        .foreground!;
    expect(foreground.shouldRepaint(english), isTrue);
    semantics.dispose();
  });

  testWidgets("LZ3 Week's grid, its hidden-day pill, its all-day strip "
      "folded and unfolded, and the landing label of a move switch to the "
      "localizations above them", (tester) async {
    useView(tester, 800.0, 2000.0);
    final semantics = tester.ensureSemantics();
    final store = MemoryCalendarStore<String>(
      entries: weekEntries(),
      hours: office,
    );
    final controller = CalendarController(
      view: CalendarViewKind.week,
      selectedDay: tuesday,
    );
    addTearDown(controller.dispose);
    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: false,
    );
    expect(unmarked(shownTexts(tester)), isNotEmpty);

    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: true,
    );
    expect(find.byKey(hiddenCountKey), findsOneWidget);
    expect(find.byKey(allDayMoreKey(thursday)), findsOneWidget);
    expectMarked(tester, "Week");

    await tester.tap(find.byKey(allDayMoreKey(thursday)));
    await tester.pumpAndSettle();
    expect(find.byKey(allDayLessKey), findsOneWidget);
    expectMarked(tester, "Week's strip unfolded");

    final block = tester.getCenter(find.byKey(blockKey("Standup", tuesday)));
    final gesture = await tester.startGesture(block);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveBy(const Offset(0.0, 60.0));
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 60.0));
    await tester.pump();
    expect(find.byKey(landingLabelKey), findsOneWidget);
    expectMarked(tester, "a move's landing");

    await gesture.moveTo(Offset(4.0, block.dy + 120.0));
    await tester.pump();
    expectMarked(tester, "a move with nowhere to land");
    expect(find.text(marked.noLanding), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets("LZ4 Month's board, its banners and chips, and the month "
      "picker switch to the localizations above them", (tester) async {
    useView(tester, 800.0, 900.0);
    final semantics = tester.ensureSemantics();
    final store = MemoryCalendarStore<String>(
      entries: weekEntries(),
      hours: office,
    );
    final controller = CalendarController(
      view: CalendarViewKind.month,
      selectedDay: tuesday,
    );
    addTearDown(controller.dispose);
    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: false,
    );
    expect(unmarked(shownTexts(tester)), isNotEmpty);

    await pumpCalendar(
      tester,
      store: store,
      controller: controller,
      marked: true,
    );
    expect(find.byKey(monthEarlierKey(tuesday)), findsOneWidget);
    expect(find.byKey(monthLaterKey(tuesday)), findsOneWidget);
    expect(find.byKey(monthMoreKey(thursday)), findsOneWidget);
    expectMarked(tester, "Month");

    await tester.tap(find.byTooltip(marked.pickMonthTooltip));
    await tester.pumpAndSettle();
    expect(find.byKey(monthPickerMonthKey(DateTime(2026, 4))), findsOneWidget);
    expectMarked(tester, "the month picker");
    semantics.dispose();
  });

  testWidgets("LZ5 the default failure builder, in Agenda's day rows and over "
      "Week's grid, switches to the localizations above it", (tester) async {
    useView(tester, 800.0, 2000.0);
    final semantics = tester.ensureSemantics();
    for (final view in <CalendarViewKind>[
      CalendarViewKind.agenda,
      CalendarViewKind.week,
    ]) {
      final store = CachingCalendarStore<String>(
        dataSource: FailingSource(),
        hours: office,
      );
      final controller = CalendarController(view: view, selectedDay: tuesday);
      await pumpCalendar(
        tester,
        store: store,
        controller: controller,
        marked: false,
      );
      expect(
        find.text(const DefaultCalendarLocalizations().retry),
        findsWidgets,
      );

      await pumpCalendar(
        tester,
        store: store,
        controller: controller,
        marked: true,
      );
      expect(find.text(marked.retry), findsWidgets);
      expectMarked(tester, "$view failed");
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      store.dispose();
    }
    semantics.dispose();
  });
}
