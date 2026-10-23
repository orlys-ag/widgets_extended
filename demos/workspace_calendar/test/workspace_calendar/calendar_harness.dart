/// Helpers the calendar's widget tests share: the fixed day, the host the
/// calendar is pumped in, the settings sheet, the calendar bar and its edit
/// mode switch and Today, the timed grid's viewport, a block's selection and move, a read
/// of the mock, and a canvas that records what a painter draws.
library;

import 'dart:ui' as ui;

import 'package:workspace_calendar/workspace_calendar/calendar_bar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/item_builders.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/month_strip.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// A Tuesday. April 2026 starts on a Wednesday and has 30 days, so its
/// Monday-first grid runs from March 30 to May 3 in five weeks.
final DateTime today = DateTime(2026, 4, 21);

/// The latency of the mock [pumpCalendar] builds when given none.
const Duration harnessLatency = Duration(milliseconds: 100);

// The ids of the seed around [today]: `defaultCalendarSeed` lists the kept
// tasks first, then the week's meetings and deadlines, then "Day off" and
// "Conference trip", and the mock numbers them in that order.
const String uxFlowId = "item-5";
const String brainstormId = "item-6";
const String standupId = "item-7";
const String reviewId = "item-8";
const String retroPrepId = "item-17";
const String clientPresentationId = "item-18";
const String teamOffsiteId = "item-20";
const String releasePlanningId = "item-21";
const String designSystemSyncId = "item-22";
const String designCritiqueId = "item-25";
const String dayOffId = "item-28";

/// The Monday of [today]'s week.
final DateTime monday = DateTime(2026, 4, 20);

/// Week's timed grid row of [minute], over the whole day's hours: row 0 is
/// the day header and row 1 the room above the first slot.
int rowOf(int minute) {
  return 2 + minute ~/ 15;
}

/// Day's timed grid row of [minute], over the whole day's hours: the grid
/// has no day header, so row 0 is the room above the first slot.
int dayRowOf(int minute) {
  return 1 + minute ~/ 15;
}

/// The timed grid's gutter cell that a screen reader hears as [label],
/// the clock time an hour label there names. Needs semantics on.
Finder gutterLabelFinder(String label) {
  return find.bySemanticsLabel(label);
}

/// The room the timed grid keeps above its first slot and below its last:
/// half an hour label, as the foreground lays the labels out, and 2 px.
double labelRoom(WidgetTester tester) {
  return paintGridForeground(tester).paragraphs.first.paragraph.height / 2 +
      2.0;
}

/// The first day the timed grid shows, which in Day mode is its one day.
DateTime gridDay(WidgetTester tester) {
  return tester
      .widget<TimedGrid<ItemPayload>>(find.byType(TimedGrid<ItemPayload>))
      .firstDay;
}

/// [minute] minutes after [day]'s midnight.
DateTime atMinute(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, 0, minute);
}

/// The minutes after midnight of [item]'s start, and of its end on the
/// last day it has a part in, 1440 for an end at a day's start.
(int, int) minutesOf(CalendarItem item) {
  return (minuteOfDay(item.start), endMinuteOfDay(item.end));
}

/// The day of [item]'s start.
DateTime firstDayOf(CalendarItem item) {
  return dateOfDayNumber(dayNumber(item.start));
}

/// The days [item] has a part in, from its start's day to its last.
int daysOf(CalendarItem item) {
  return lastDayNumberOf(item.start, item.end) - dayNumber(item.start) + 1;
}

/// The week grid's column of the day [weekday] days after [monday]:
/// column 0 is the hour gutter.
int colOf(int weekday) {
  return 1 + weekday;
}

/// The block of the item [id]'s piece on [day], or with no [day] the one
/// block of [id].
Finder blockFinder(String id, [DateTime? day]) {
  if (day != null) {
    return find.byKey(blockKey(id, day));
  }
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("block-$id@");
  });
}

/// The global rect of the timed grid's cell at [row] and [col].
Rect cellRect(WidgetTester tester, int row, int col) {
  final viewport = gridViewport(tester);
  final rect = viewport.rectOfCell(row, col)!;
  return viewport.localToGlobal(rect.topLeft) & rect.size;
}

/// The item form's date field labelled [label], "Start date" or "End
/// date".
Finder formDateFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(InputDecorator),
  );
}

/// The item form's date field labelled [label] showing [date], as
/// [isoDate] writes it.
Finder formDateShows(String label, String date) {
  return find.descendant(of: formDateFinder(label), matching: find.text(date));
}

/// Expects the item form's Start date to name [day] and its End date the
/// day [days] - 1 days after it, both as [isoDate] writes them.
void expectFormDays(String day, int days) {
  expect(formDateShows("Start date", day), findsOneWidget);
  expect(
    formDateShows("End date", isoDate(addDays(parseIsoDate(day)!, days - 1))),
    findsOneWidget,
  );
}

/// Opens the calendar's mode menu and picks [mode], "Agenda", "Day", "Week"
/// or "Month".
Future<void> pickMode(WidgetTester tester, String mode) async {
  await tester.tap(find.byTooltip("Calendar view"));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  await tester.pumpAndSettle();
}

/// Stores [item] through [api] before the calendar is pumped, and pumps
/// the latency it answers after.
Future<void> createBeforePump(
  WidgetTester tester,
  MockCalendarApi api,
  Map<String, Object?> item,
) async {
  api.create(item);
  await tester.pump(api.latency);
}

/// A Task envelope with status to do, from [start] minutes after [day]'s
/// midnight to [end] minutes after the midnight of the day [dayCount] - 1
/// days on.
Map<String, Object?> taskJson(
  String title,
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
}) {
  return <String, Object?>{
    "type": "task",
    "title": title,
    "start": isoDateTime(atMinute(day, start)),
    "end": isoDateTime(atMinute(addDays(day, dayCount - 1), end)),
    "fields": <String, Object?>{"status": "toDo"},
  };
}

/// The start of the stored envelope [item], read as the envelope writes
/// it.
DateTime startOfJson(Map<String, Object?> item) {
  return parseIsoDateTime(item["start"]! as String)!;
}

/// The end of the stored envelope [item], read as the envelope writes it.
DateTime endOfJson(Map<String, Object?> item) {
  return parseIsoDateTime(item["end"]! as String)!;
}

/// The app [pumpCalendar] pumps: the calendar over [api], given [today]
/// and [clock], opening in edit mode when [editing], its views drawing
/// with [builders].
Widget calendarApp({
  required MockCalendarApi api,
  DateTime? today,
  DateTime Function()? clock,
  bool editing = false,
  ItemBuilders builders = harborItemBuilders,
}) {
  return MaterialApp(
    // The M3 ink sparkle shader cannot load under the test binding.
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    // Out of edit mode the calendar is given no edit mode, so it opens on
    // its own default.
    home: editing
        ? WorkspaceCalendarExample(
            today: today,
            api: api,
            clock: clock,
            editing: true,
            builders: builders,
          )
        : WorkspaceCalendarExample(
            today: today,
            api: api,
            clock: clock,
            builders: builders,
          ),
  );
}

/// Pumps the calendar on [today] over [api], by default a mock seeded
/// around [today] at [harnessLatency] with no failure policy, at [size],
/// reading the time from [clock], by default the real clock, and lets its
/// first read complete. Returns the mock. With [pinsToday] false the
/// calendar is given no day, so it opens on the day [clock] reads and
/// marks that day as today. With [editing] it opens in edit mode. Its
/// views draw with [builders].
Future<MockCalendarApi> pumpCalendar(
  WidgetTester tester, {
  MockCalendarApi? api,
  Size size = const Size(390.0, 844.0),
  DateTime Function()? clock,
  bool pinsToday = true,
  bool editing = false,
  ItemBuilders builders = harborItemBuilders,
}) async {
  final mock = api ?? MockCalendarApi.seeded(today, latency: harnessLatency);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    calendarApp(
      api: mock,
      today: pinsToday ? today : null,
      clock: clock,
      editing: editing,
      builders: builders,
    ),
  );
  await tester.pump(mock.latency);
  await tester.pumpAndSettle();
  return mock;
}

/// Opens the settings sheet from the app bar's More menu.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip("More"));
  await tester.pumpAndSettle();
  await tester.tap(find.text("Calendar settings"));
  await tester.pumpAndSettle();
}

/// Opens the calendar bar with the app bar's chevron where it is closed.
Future<void> openBar(WidgetTester tester) async {
  if (find.byKey(calendarBarKey).evaluate().isEmpty) {
    await tester.tap(find.byTooltip("Calendar settings bar"));
    await tester.pumpAndSettle();
  }
}

/// Closes the open calendar bar with the app bar's chevron.
Future<void> closeBar(WidgetTester tester) async {
  await tester.tap(find.byTooltip("Calendar settings bar"));
  await tester.pumpAndSettle();
}

/// Opens the calendar bar where it is closed, flips its edit mode switch,
/// and closes the bar.
Future<void> toggleEditMode(WidgetTester tester) async {
  await openBar(tester);
  await tester.tap(find.byKey(editModeKey));
  await tester.pumpAndSettle();
  await closeBar(tester);
}

/// The calendar bar's Today.
Finder todayButtonFinder() {
  return find.widgetWithText(TextButton, "Today");
}

/// Taps Today in the calendar bar, opening the bar first where it is
/// closed, and pumps nothing after the tap.
Future<void> tapToday(WidgetTester tester) async {
  await openBar(tester);
  await tester.tap(todayButtonFinder());
}

/// Selects in Agenda the day a month after the selected one, keeping its
/// day of the month where the next month has it: "Next month" slides the
/// unfolded calendar card on, selecting nothing, and a tap on that day of
/// the month it shows selects it. Pumps through the slide, over the
/// motion of the [CalendarTheme] above the card, and nothing after the
/// tap.
Future<void> selectNextMonth(WidgetTester tester) async {
  final motion = CalendarTheme.of(
    tester.element(find.byType(MonthStrip<ItemPayload>)),
  ).motionDuration;
  final selected = tester.widgetList<DayCell>(find.byType(DayCell)).singleWhere(
    (cell) {
      return cell.isSelected;
    },
  ).day;
  await tester.tap(find.byTooltip("Next month"));
  // The frame that starts the slide after the build, the frame its
  // motion's clock starts on, its motion, and a frame past it: the slide
  // ends, and its scroll view takes pointers again, only once more than
  // its duration has passed.
  await tester.pump();
  await tester.pump();
  await tester.pump(motion);
  await tester.pump(const Duration(milliseconds: 16));
  await tester.tap(find.byKey(dayCellKey(addMonths(selected, 1))));
}

/// The one board's viewport: in Week and Day the timed grid's, keyed by
/// [GridKey]s, and in Month the month board's, keyed by strings.
RenderBoardViewport<Object> gridViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<Object>>()
      .single;
}

/// Long-presses the block of the item [id] and lets go where it lifted,
/// which selects it, so its resize handles show, and moves nothing.
Future<void> selectBlock(WidgetTester tester, String id) async {
  final gesture = await tester.startGesture(tester.getCenter(blockFinder(id)));
  await tester.pump(kLongPressTimeout + kPressTimeout);
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The style the timed grid animates with: [timedGridAnimationStyleOf]
/// the theme above it.
BoardAnimationStyle gridAnimationStyle(WidgetTester tester) {
  return timedGridAnimationStyleOf(
    CalendarTheme.of(tester.element(find.byType(TimedGrid<ItemPayload>))),
  );
}

/// Long-presses [block] and drops it so its top-left corner lands on
/// [target], then pumps the frame that starts the drop-settle glide and
/// the glide itself, which ends before any mock answer a test sets at
/// 1 s or more.
Future<void> moveBlock(WidgetTester tester, Finder block, Offset target) async {
  final rect = tester.getRect(block);
  final gesture = await tester.startGesture(rect.center);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  await gesture.moveBy(target - rect.topLeft);
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump(gridAnimationStyle(tester).effectiveDropSettle.duration);
}

/// What [api]'s `list` returns for [first] to [last], pumped through its
/// latency.
Future<List<Map<String, Object?>>> listAll(
  WidgetTester tester,
  MockCalendarApi api,
  DateTime first,
  DateTime last,
) async {
  List<Map<String, Object?>>? items;
  api.list(first, last).then((result) {
    items = result;
  });
  await tester.pump(api.latency);
  return items!;
}

/// One draw call a [RecordingCanvas] received: a rect, or a line from
/// [from] to [to], and the paint it was drawn with.
class CanvasRecord {
  CanvasRecord.rect(Rect this.rect, this.paint) : from = null, to = null;

  CanvasRecord.line(Offset this.from, Offset this.to, this.paint) : rect = null;

  final Rect? rect;
  final Offset? from;
  final Offset? to;
  final Paint paint;

  bool get isLine {
    return from != null;
  }

  Color get color {
    return paint.color;
  }

  /// Whether the record was drawn in [other]. Compared as 32-bit ARGB: a
  /// [Paint] hands its colour back from its own storage, which need not
  /// compare equal to the [Color] it was given.
  bool isIn(Color other) {
    return paint.color.toARGB32() == other.toARGB32();
  }

  bool get isFill {
    return paint.style == PaintingStyle.fill;
  }
}

/// A canvas that records the rects and lines drawn on it, each with its
/// paint, in the coordinates they were drawn in, the paragraphs drawn and
/// the rects it is clipped to. Every other call is ignored.
class RecordingCanvas implements Canvas {
  final List<CanvasRecord> records = <CanvasRecord>[];

  /// The rects passed to [clipRect], in the order they were passed.
  final List<Rect> clips = <Rect>[];

  /// The paragraphs drawn, each with the offset of its top left, in the
  /// order they were drawn.
  final List<({ui.Paragraph paragraph, Offset offset})> paragraphs =
      <({ui.Paragraph paragraph, Offset offset})>[];

  /// The filled rects drawn in [color].
  Iterable<Rect> fillsOf(Color color) {
    return <Rect>[
      for (final record in records)
        if (!record.isLine && record.isFill && record.isIn(color)) record.rect!,
    ];
  }

  Iterable<CanvasRecord> get lines {
    return records.where((record) {
      return record.isLine;
    });
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    records.add(CanvasRecord.rect(rect, paint));
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    records.add(CanvasRecord.line(p1, p2, paint));
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    paragraphs.add((paragraph: paragraph, offset: offset));
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    clips.add(rect);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

/// Paints the timed grid's background onto a new [RecordingCanvas], with
/// the viewport as the geometry.
RecordingCanvas paintGridBackground(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = RecordingCanvas();
  viewport.background!.paint(canvas, viewport);
  return canvas;
}

/// Paints the timed grid's foreground, the line marking the current time,
/// onto a new [RecordingCanvas], which stays empty where the grid has no
/// foreground.
RecordingCanvas paintGridForeground(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = RecordingCanvas();
  viewport.foreground?.paint(canvas, viewport);
  return canvas;
}

/// Shows Saturday and Sunday where the open calendar bar hides them and
/// hides them where it shows them, both in one change, through its days
/// shown buttons' own callback. Pumps nothing.
void flipWeekends(WidgetTester tester) {
  final days = tester.widget<SegmentedButton<int>>(find.byKey(shownDaysKey));
  days.onSelectionChanged!(
    days.selected
        .difference(const <int>{5, 6})
        .union(const <int>{5, 6}.difference(days.selected)),
  );
}
