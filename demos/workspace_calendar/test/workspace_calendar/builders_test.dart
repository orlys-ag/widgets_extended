/// The views draw their entries and their loading and failure states only
/// through the builders the composition hands them, the module's defaults
/// where it hands none, and call each builder no more often than the base
/// built the widget it replaces.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_bar.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar/history_lock.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/item_builders.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/month_board.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';

import 'calendar_harness.dart';

const Duration second = Duration(seconds: 1);
const Duration oneFrame = Duration(milliseconds: 16);

/// 09:00 on [today].
DateTime nineOClock() {
  return DateTime(2026, 4, 21, 9);
}

/// The Sunday of [today]'s week.
final DateTime sunday = DateTime(2026, 4, 26);

/// The key of the mark a marking builder draws for [form] and [name], an
/// entry's id or a state's site.
ValueKey<String> markKey(String form, String name) {
  return ValueKey<String>("mark-$form-$name");
}

/// Every mark of [form] in the tree.
Finder marksOf(String form) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("mark-$form-");
  });
}

/// One call of a block builder.
typedef BlockCall = ({ShownItem entry, CalendarBlockDetails details});

/// One call of a chip builder.
typedef ChipCall = ({ShownItem entry, CalendarChipDetails details});

/// One call of a card builder.
typedef CardCall = ({ShownItem entry, CalendarCardDetails details});

/// The name an add button's mark and count go by: its day and minute.
String addNameOf(CalendarAddButtonDetails details) {
  return "${isoDate(details.day)}@${details.startMinute}";
}

/// Builders that mark what they draw: each returns a [ColoredBox] keyed by
/// [markKey], kept in [marks], and records its arguments.
class MarkingBuilders {
  final List<BlockCall> blocks = <BlockCall>[];
  final List<ChipCall> chips = <ChipCall>[];
  final List<CardCall> cards = <CardCall>[];
  final List<CalendarAddButtonDetails> adds = <CalendarAddButtonDetails>[];
  final List<CalendarLoadingState> loadings = <CalendarLoadingState>[];
  final List<CalendarFailureState> failures = <CalendarFailureState>[];

  /// Every mark these builders returned, by identity.
  final Set<Widget> marks = Set<Widget>.identity();

  late final ItemBuilders builders = ItemBuilders(
    block: block,
    chip: chip,
    card: card,
    addButton: addButton,
    loading: loading,
    failure: failure,
  );

  Widget _mark(String form, String name) {
    final mark = ColoredBox(
      key: markKey(form, name),
      color: Color(0xFF00C853 + marks.length % 2),
    );
    marks.add(mark);
    return mark;
  }

  Widget block(
    BuildContext context,
    ShownItem entry,
    CalendarBlockDetails details,
  ) {
    blocks.add((entry: entry, details: details));
    return _mark("block", entry.id);
  }

  Widget chip(
    BuildContext context,
    ShownItem entry,
    CalendarChipDetails details,
  ) {
    chips.add((entry: entry, details: details));
    return _mark("chip", entry.id);
  }

  Widget card(
    BuildContext context,
    ShownItem entry,
    CalendarCardDetails details,
  ) {
    cards.add((entry: entry, details: details));
    return _mark("card", entry.id);
  }

  Widget addButton(BuildContext context, CalendarAddButtonDetails details) {
    adds.add(details);
    return _mark("add", addNameOf(details));
  }

  Widget loading(BuildContext context, CalendarLoadingState state) {
    loadings.add(state);
    return _mark("loading", state.site.name);
  }

  Widget failure(BuildContext context, CalendarFailureState state) {
    failures.add(state);
    return _mark("failure", state.site.name);
  }

  /// The last block call for the entry [id].
  BlockCall lastBlock(String id) {
    return blocks.lastWhere((call) {
      return call.entry.id == id;
    });
  }

  /// The last chip call for the entry [id].
  ChipCall lastChip(String id) {
    return chips.lastWhere((call) {
      return call.entry.id == id;
    });
  }

  /// The last card call for the entry [id].
  CardCall lastCard(String id) {
    return cards.lastWhere((call) {
      return call.entry.id == id;
    });
  }

  /// Whether the mark under [slot] is one of these builders'.
  bool marked(WidgetTester tester, Finder slot, String form, String id) {
    final mark = find.descendant(
      of: slot,
      matching: find.byKey(markKey(form, id)),
    );
    if (mark.evaluate().length != 1) {
      return false;
    }
    return marks.contains(tester.widget(mark));
  }
}

/// Builders that count their calls, by entry id, and return Harbor's
/// builders' output.
class CountingBuilders {
  final Map<String, int> blockCalls = <String, int>{};
  final Map<String, int> chipCalls = <String, int>{};
  final Map<String, int> cardCalls = <String, int>{};
  final Map<String, int> addCalls = <String, int>{};

  late final ItemBuilders builders = ItemBuilders(
    block: block,
    chip: chip,
    card: card,
    cardExtent: ItemCard.extentOf,
    addButton: addButton,
    loading: harborLoadingBuilder,
    failure: harborFailureBuilder,
  );

  Widget card(
    BuildContext context,
    ShownItem entry,
    CalendarCardDetails details,
  ) {
    cardCalls.update(entry.id, (count) => count + 1, ifAbsent: () => 1);
    return harborCardBuilder(context, entry, details);
  }

  Widget addButton(BuildContext context, CalendarAddButtonDetails details) {
    addCalls.update(
      addNameOf(details),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return harborAddButtonBuilder(context, details);
  }

  int get cards {
    return cardCalls.values.fold(0, (sum, count) => sum + count);
  }

  int get adds {
    return addCalls.values.fold(0, (sum, count) => sum + count);
  }

  Widget chip(
    BuildContext context,
    ShownItem entry,
    CalendarChipDetails details,
  ) {
    chipCalls.update(entry.id, (count) => count + 1, ifAbsent: () => 1);
    return harborChipBuilder(context, entry, details);
  }

  int get chips {
    return chipCalls.values.fold(0, (sum, count) => sum + count);
  }

  Widget block(
    BuildContext context,
    ShownItem entry,
    CalendarBlockDetails details,
  ) {
    blockCalls.update(entry.id, (count) => count + 1, ifAbsent: () => 1);
    return harborBlockBuilder(context, entry, details);
  }

  int get blocks {
    return blockCalls.values.fold(0, (sum, count) => sum + count);
  }

  void clear() {
    blockCalls.clear();
    chipCalls.clear();
    cardCalls.clear();
    addCalls.clear();
  }
}

/// The ids of the items [api] lists for [today]'s week.
Future<List<String>> weekIds(WidgetTester tester, MockCalendarApi api) async {
  return <String>[
    for (final json in await listAll(tester, api, monday, sunday))
      json["id"]! as String,
  ];
}

/// The block slots the grid shows of [ids], each expected to hold its own
/// mark of [marks]; returns how many there are.
int expectBlockMarks(
  WidgetTester tester,
  MarkingBuilders marks,
  List<String> ids,
) {
  var slots = 0;
  for (final id in ids) {
    final slot = blockFinder(id);
    if (slot.evaluate().isEmpty) {
      continue;
    }
    slots++;
    expect(marks.marked(tester, slot, "block", id), isTrue, reason: id);
  }
  return slots;
}

/// Sets the open calendar bar's hours to [start] to [end] o'clock through
/// its slider's own callback, as a drag of it does, and closes the bar.
Future<void> pickHours(WidgetTester tester, int start, int end) async {
  await openBar(tester);
  tester.widget<RangeSlider>(find.byKey(hoursSliderKey)).onChanged!(
    RangeValues(start.toDouble(), end.toDouble()),
  );
  await tester.pumpAndSettle();
  await closeBar(tester);
}

/// Shows or hides the weekends through the calendar bar.
Future<void> toggleWeekends(WidgetTester tester) async {
  await openBar(tester);
  flipWeekends(tester);
  await tester.pumpAndSettle();
  await closeBar(tester);
}

/// Two touches [spread] apart up and down around [focal], each moved
/// [step] further from the other on each of [steps] frames, lifted, then
/// settled.
Future<void> pinch(
  WidgetTester tester,
  Offset focal, {
  double spread = 60.0,
  double step = 6.0,
  int steps = 6,
}) async {
  const unit = Offset(0.0, 1.0);
  final first = await tester.startGesture(focal - unit * (spread / 2.0));
  final second = await tester.startGesture(focal + unit * (spread / 2.0));
  await tester.pump();
  for (var i = 0; i < steps; i++) {
    await first.moveBy(-unit * step);
    await second.moveBy(unit * step);
    await tester.pump();
  }
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

/// The calendar over [api] with [builders] and [theme], editing, at 09:00
/// on [today]: [calendarApp]'s app with a theme of its own.
Widget themedApp(
  MockCalendarApi api,
  ItemBuilders builders,
  CalendarThemeData theme,
) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: WorkspaceCalendarExample(
      today: today,
      api: api,
      clock: nineOClock,
      editing: true,
      calendarTheme: theme,
      builders: builders,
    ),
  );
}

/// Pumps the frames of [duration] in 16 ms steps, for a view whose
/// activity indicator never settles.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final frames = duration.inMilliseconds ~/ oneFrame.inMilliseconds + 1;
  for (var i = 0; i < frames; i++) {
    await tester.pump(oneFrame);
  }
}

/// Whether [node] lies below [ancestor] in the render tree.
bool isBelow(RenderObject node, RenderObject ancestor) {
  var current = node.parent;
  while (current != null) {
    if (identical(current, ancestor)) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

/// The grid.
final Finder grid = find.byType(TimedGrid<ItemPayload>);

/// The month board.
final Finder month = find.byType(MonthBoard<ItemPayload>);

/// Agenda's day list.
final Finder agenda = find.byType(DayList<ItemPayload>);

/// Every widget keyed with a [ValueKey] of a string starting [prefix], by
/// that string.
Map<String, Finder> keyedSlots(String prefix) {
  return <String, Finder>{
    for (final element in find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith(prefix);
    }).evaluate())
      (element.widget.key! as ValueKey<String>).value: find.byKey(
        element.widget.key!,
      ),
  };
}

/// How far Agenda's list has scrolled.
double listOffset(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(of: agenda, matching: find.byType(Scrollable)),
      )
      .position
      .pixels;
}

/// The label nodes of the add buttons under [of].
Finder addLabelsUnder(Finder of) {
  return find.descendant(
    of: of,
    matching: find.bySemanticsLabel(RegExp("^Add an item at ")),
  );
}

/// The list requests [api] has had.
int listCalls(MockCalendarApi api) {
  return api.requests.where((request) {
    return request.method == CalendarMethod.list;
  }).length;
}

/// The text of the form's field labelled [label].
String fieldText(WidgetTester tester, String label) {
  return tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .controller!
      .text;
}

/// 11:07 on [today]: after [endedId] ends, while [runningId] runs and
/// before [laterId] starts.
DateTime midMorning() {
  return DateTime(2026, 4, 21, 11, 7);
}

const String endedId = "item-2";
const String runningId = "item-3";
const String laterId = "item-4";

/// A day before [today]'s, then today's ended, running and later items.
final List<Map<String, Object?>> lockSeed = <Map<String, Object?>>[
  taskJson("Past", monday, 9 * 60, 10 * 60),
  taskJson("Ended", today, 8 * 60, 9 * 60),
  taskJson("Running", today, 10 * 60, 12 * 60),
  taskJson("Later", today, 14 * 60, 15 * 60),
];

/// The calendar over [lockSeed] with [builders], in edit mode when
/// [editing], its clock reading [clock], and where [editing] the history
/// lock on to now through the settings sheet.
Future<MockCalendarApi> pumpLocked(
  WidgetTester tester,
  ItemBuilders builders, {
  DateTime Function() clock = midMorning,
  bool editing = true,
}) async {
  final api = MockCalendarApi(seed: lockSeed, latency: harnessLatency);
  await pumpCalendar(
    tester,
    api: api,
    size: const Size(390.0, 1400.0),
    editing: editing,
    clock: clock,
    builders: builders,
  );
  if (editing) {
    await openSettings(tester);
    await tester.tap(find.byKey(lockPastKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(lockEarlierTodayKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195.0, 20.0));
    await tester.pumpAndSettle();
  }
  return api;
}

/// Pumps the calendar over a mock seeded around [today] at a 1 s latency
/// with [builders] at [size], and steps it to the next month, pumping into
/// the read of its unread days.
Future<MockCalendarApi> stepToUnread(
  WidgetTester tester,
  ItemBuilders builders, {
  Size size = const Size(390.0, 844.0),
}) async {
  final api = await pumpCalendar(
    tester,
    editing: true,
    clock: nineOClock,
    size: size,
    api: MockCalendarApi.seeded(today, latency: second),
    builders: builders,
  );
  await tester.tap(find.byTooltip("Next month"));
  await pumpFor(tester, const Duration(milliseconds: 500));
  return api;
}

/// Lets [api]'s reads fail and steps to the month after, pumping through
/// the failed read.
Future<void> stepToFailed(WidgetTester tester, MockCalendarApi api) async {
  await pumpFor(tester, second);
  api.failurePolicy = (request) {
    return request.method == CalendarMethod.list ? "Reading failed." : null;
  };
  await tester.tap(find.byTooltip("Next month"));
  await pumpFor(tester, const Duration(milliseconds: 1500));
}

/// Every bar slot of the month board, by the key [monthChipKey] gives it.
Map<String, Finder> barSlots(WidgetTester tester) {
  return <String, Finder>{
    for (final element in find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith("month-chip-");
    }).evaluate())
      (element.widget.key! as ValueKey<String>).value: find.byKey(
        element.widget.key!,
      ),
  };
}

/// The id of the item whose bar the slot keyed [slotKey] holds.
String barIdOf(String slotKey) {
  final segment = slotKey.substring("month-chip-".length);
  return segment.substring(0, segment.indexOf("@"));
}

/// The tint the module's defaults draw a Task entry on under Harbor's
/// theme.
Color taskTint() {
  return Color.alphaBlend(
    harborTypeStyleOf(
      CalendarItemType.task,
    ).edge.withValues(alpha: harborCalendarTheme.entryTintOpacity),
    harborCalendarTheme.surface,
  );
}

/// Expects the block slot of the Task [id] to hold the module's default
/// block: its first coloured box the Task tint, with a 4 px left edge of
/// the Task colour.
void expectDefaultTaskBlock(WidgetTester tester, String id) {
  final task = harborTypeStyleOf(CalendarItemType.task).edge;
  final boxes = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: blockFinder(id),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) {
        return box.decoration;
      })
      .whereType<BoxDecoration>()
      .where((decoration) {
        return decoration.color != null;
      });
  final first = boxes.first;
  expect(first.color, taskTint(), reason: id);
  expect(
    first.border,
    Border(left: BorderSide(color: task, width: 4.0)),
    reason: id,
  );
}

/// Expects [bar], the slot of a Task's bar, to hold the module's default
/// bar: one box of the Task tint and one 4 px wide box of the Task colour.
void expectDefaultTaskBar(WidgetTester tester, Finder bar) {
  final task = harborTypeStyleOf(CalendarItemType.task).edge;
  final boxes = tester
      .widgetList<ColoredBox>(
        find.descendant(of: bar, matching: find.byType(ColoredBox)),
      )
      .toList();
  expect(
    boxes.where((box) {
      return box.color == taskTint();
    }),
    hasLength(1),
  );
  final edges = boxes.where((box) {
    return box.color == task;
  }).toList();
  expect(edges, hasLength(1));
  expect(tester.getSize(find.byWidget(edges.single)).width, 4.0);
}

/// The last day [api] has been asked to list: the end of the days the store
/// has read, or [today] before any read.
DateTime lastDayListed(MockCalendarApi api) {
  var last = today;
  for (final request in api.requests) {
    final end = request.last;
    if (request.method == CalendarMethod.list &&
        end != null &&
        end.isAfter(last)) {
      last = end;
    }
  }
  return last;
}

/// Steps Day forward with its chevron, settling after each step, until its
/// grid would show [day], every weekday shown.
Future<void> stepDayTo(WidgetTester tester, DateTime day) async {
  for (var i = daysBetween(gridDay(tester), day); i > 0; i--) {
    await tester.tap(find.byTooltip("Next day"));
    await tester.pumpAndSettle();
  }
}

/// Taps [tooltip]'s chevron, settling, until [shown] finds something, at
/// most three times; reads fail meanwhile while [api]'s policy says so.
Future<void> stepUntil(
  WidgetTester tester,
  MockCalendarApi api,
  String tooltip,
  Finder shown,
) async {
  for (var i = 0; i < 3 && shown.evaluate().isEmpty; i++) {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets("BW1 Week draws each block through its builder, its pending "
      "state and its cut ends included", (tester) async {
    final marks = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: marks.builders,
    );
    await pickMode(tester, "Week");
    final ids = await weekIds(tester, api);
    final slots = expectBlockMarks(tester, marks, ids);
    expect(slots, greaterThan(4));
    expect(marksOf("block"), findsNWidgets(slots));

    final brainstorm = blockFinder(brainstormId);
    await moveBlock(
      tester,
      brainstorm,
      cellRect(tester, rowOf(14 * 60), colOf(5)).topLeft,
    );
    expect(marks.lastBlock(brainstormId).entry.pending, isTrue);
    for (final type in <Type>[Opacity, Icon, CircularProgressIndicator]) {
      expect(
        find.descendant(of: brainstorm, matching: find.byType(type)),
        findsNothing,
        reason: "$type",
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(marks.lastBlock(brainstormId).entry.pending, isTrue);
    await tester.pump(second);
    await tester.pumpAndSettle();
    expect(marks.lastBlock(brainstormId).entry.pending, isFalse);

    // A block the hours cut at both ends: on Saturday, which holds no other
    // item, so the mock stores it, in a calendar of its own.
    await tester.pumpWidget(const SizedBox());
    final cut = MarkingBuilders();
    final cutApi = MockCalendarApi.seeded(today, latency: harnessLatency);
    await createBeforePump(
      tester,
      cutApi,
      taskJson("Long day", DateTime(2026, 4, 25), 7 * 60, 19 * 60),
    );
    final longDay =
        (await listAll(
              tester,
              cutApi,
              DateTime(2026, 4, 25),
              DateTime(2026, 4, 25),
            )).single["id"]!
            as String;
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: cutApi,
      builders: cut.builders,
    );
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    final details = cut.lastBlock(longDay).details;
    expect(details.cutAtStart, isTrue);
    expect(details.cutAtEnd, isTrue);
    expect(
      find.descendant(of: blockFinder(longDay), matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets("BW2 Day draws each block of its one day through its builder, "
      "detailed, its pending state included, and its cover through the "
      "loading and failure builders for its day", (tester) async {
    final marks = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: marks.builders,
    );
    await pickMode(tester, "Day");
    final ids = <String>[
      for (final json in await listAll(tester, api, today, today))
        json["id"]! as String,
    ];
    final slots = expectBlockMarks(tester, marks, ids);
    expect(slots, greaterThanOrEqualTo(2));
    expect(marksOf("block"), findsNWidgets(slots));
    expect(marks.blocks, isNotEmpty);
    for (final call in marks.blocks) {
      expect(call.details.detailed, isTrue, reason: call.entry.id);
    }

    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, dayRowOf(16 * 60), 1).topLeft,
    );
    expect(marks.lastBlock(brainstormId).entry.pending, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(marks.lastBlock(brainstormId).entry.pending, isTrue);
    await tester.pump(second);
    await tester.pumpAndSettle();
    expect(marks.lastBlock(brainstormId).entry.pending, isFalse);

    // A step to the first day past those read, whose week the store reads
    // then.
    final readTo = lastDayListed(api);
    await stepDayTo(tester, readTo);
    expect(gridDay(tester), readTo);
    final unread = addDays(readTo, 1);
    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(
      find.descendant(of: grid, matching: marksOf("loading")),
      findsOneWidget,
    );
    final loading = marks.loadings.last;
    expect(loading.site, CalendarStateSite.cover);
    expect(loading.first, unread);
    expect(loading.last, unread);
    await tester.pump(second);
    await tester.pumpAndSettle();

    // A step past that week, whose read fails.
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    final weekEnd = lastDayListed(api);
    await stepDayTo(tester, weekEnd);
    final failedDay = addDays(weekEnd, 1);
    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    await tester.pump(second);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: grid, matching: marksOf("failure")),
      findsOneWidget,
    );
    final failure = marks.failures.last;
    expect(failure.site, CalendarStateSite.cover);
    expect(failure.first, failedDay);
    expect(failure.last, failedDay);
    expect(
      failure.error,
      isA<CalendarFailureException>().having(
        (error) => error.message,
        "message",
        "Reading failed.",
      ),
    );
    final lists = listCalls(api);
    failure.retry();
    expect(listCalls(api), lists + 1);
    api.failurePolicy = null;
    await tester.pump(second);
    await tester.pumpAndSettle();
  });

  testWidgets("BW3 the cover draws the loading and failure builders' "
      "content for the grid's days, the failure with the store's error and "
      "its retry", (tester) async {
    final marks = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: marks.builders,
    );
    await pickMode(tester, "Week");
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(
      find.descendant(
        of: grid,
        matching: find.byKey(markKey("loading", "cover")),
      ),
      findsOneWidget,
    );
    final loading = marks.loadings.last;
    expect(loading.site, CalendarStateSite.cover);
    expect(loading.first, DateTime(2026, 5, 4));
    expect(loading.last, DateTime(2026, 5, 10));
    await tester.pump(second);
    await tester.pumpAndSettle();

    api.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(second);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: grid,
        matching: find.byKey(markKey("failure", "cover")),
      ),
      findsOneWidget,
    );
    final failure = marks.failures.last;
    expect(failure.site, CalendarStateSite.cover);
    expect(failure.first, DateTime(2026, 5, 18));
    expect(failure.last, DateTime(2026, 5, 24));
    expect(
      failure.error,
      isA<CalendarFailureException>().having(
        (error) => error.message,
        "message",
        "Reading failed.",
      ),
    );
    final lists = api.requests.where((request) {
      return request.method == CalendarMethod.list;
    }).length;
    failure.retry();
    expect(
      api.requests.where((request) {
        return request.method == CalendarMethod.list;
      }),
      hasLength(lists + 1),
    );
    api.failurePolicy = null;
    await tester.pump(second);
    await tester.pumpAndSettle();
  });

  testWidgets("BW4 given no builders the grid draws the module's defaults, "
      "in Week and in Day", (tester) async {
    final api = await pumpCalendar(
      tester,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: const ItemBuilders(),
    );
    await pickMode(tester, "Week");
    expect(find.byType(HarborBlock), findsNothing);
    expectDefaultTaskBlock(tester, brainstormId);

    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(
      find.descendant(
        of: grid,
        matching: find.byType(CalendarActivityIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: grid,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    await pumpFor(tester, second);

    api.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    await tester.tap(find.byTooltip("Next week"));
    await pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip("Next week"));
    await pumpFor(tester, const Duration(milliseconds: 1400));
    expect(
      find.descendant(of: grid, matching: find.text(readFailedLabel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: grid, matching: find.text(retryLabel)),
      findsOneWidget,
    );
    expect(find.text("Reading failed."), findsNothing);
    api.failurePolicy = null;
    await tester.tap(find.text(retryLabel));
    await pumpFor(tester, const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    // Day, in a calendar of its own: the detailed default block, then the
    // cover on the first day past those read and on the first day past the
    // week that read added, whose read fails.
    await tester.pumpWidget(const SizedBox());
    final dayApi = await pumpCalendar(
      tester,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: const ItemBuilders(),
    );
    await pickMode(tester, "Day");
    expect(find.byType(HarborBlock), findsNothing);
    expectDefaultTaskBlock(tester, brainstormId);
    expect(
      find.descendant(
        of: blockFinder(brainstormId),
        matching: find.text(clockRangeLabel(14 * 60, 15 * 60)),
      ),
      findsOneWidget,
    );

    final readTo = lastDayListed(dayApi);
    await stepDayTo(tester, readTo);
    expect(gridDay(tester), readTo);
    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(
      find.descendant(
        of: grid,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: grid,
        matching: find.byType(CalendarActivityIndicator),
      ),
      findsOneWidget,
    );
    await pumpFor(tester, second);

    dayApi.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    await stepDayTo(tester, lastDayListed(dayApi));
    await tester.tap(find.byTooltip("Next day"));
    await pumpFor(tester, const Duration(milliseconds: 1400));
    expect(find.text("Reading failed."), findsNothing);
    expect(
      find.descendant(of: grid, matching: find.text(readFailedLabel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: grid, matching: find.text(retryLabel)),
      findsOneWidget,
    );
    dayApi.failurePolicy = null;
    await tester.tap(find.text(retryLabel));
    await pumpFor(tester, const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
  });

  testWidgets("BW5 the hidden-count pill's tooltip is the grid node's label, "
      "with no tooltip under the grid", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await createBeforePump(
      tester,
      api,
      taskJson("Weekend", DateTime(2026, 4, 25), 10 * 60, 11 * 60),
    );
    await pumpCalendar(tester, api: api, clock: nineOClock);
    await pickMode(tester, "Week");
    await toggleWeekends(tester);
    expect(find.bySemanticsLabel("${hiddenItemsLabel(1)}\n+1"), findsOneWidget);
    expect(find.byTooltip(hiddenItemsLabel(1)), findsNothing);
    expect(
      find.descendant(of: grid, matching: find.byType(Tooltip)),
      findsNothing,
    );
    expect(
      find.descendant(of: grid, matching: find.byType(RawTooltip)),
      findsNothing,
    );
  });

  testWidgets("BW6 a drag, a scroll and a pinch call the block builder no "
      "more often than the base built blocks, and the pinch calls none for "
      "a block it keeps", (tester) async {
    final counts = CountingBuilders();
    final api = await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: counts.builders,
    );
    await pickMode(tester, "Week");
    expect(counts.blocks, greaterThan(4));
    counts.clear();

    // The drag of a block, with its settle slide and the API's answer.
    final requests = api.requests.length;
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, rowOf(14 * 60), colOf(5)).topLeft,
    );
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(requests + 1));
    expect(counts.blocks, greaterThan(0));
    expect(counts.blocks, lessThanOrEqualTo(23));
    expect(counts.blockCalls.keys, <String>[brainstormId]);
    expect(counts.chips, 0);
    expect(counts.cards, 0);
    expect(counts.adds, 0);
    counts.clear();

    // A scroll of the grid.
    final vertical = gridViewport(tester).verticalPosition!;
    final before = vertical.pixels;
    await tester.drag(grid, const Offset(0.0, -300.0));
    await tester.pumpAndSettle();
    expect(vertical.pixels - before, greaterThan(200.0));
    expect(counts.blocks, 0);
    expect(counts.chips, 0);
    expect(counts.cards, 0);
    expect(counts.adds, 0);
    counts.clear();

    // A pinch up and down the slots.
    final cell = cellRect(tester, rowOf(12 * 60), colOf(2));
    final kept = <String, Element>{
      for (final element in find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith("block-");
      }).evaluate())
        (element.widget.key! as ValueKey<String>).value: element,
    };
    await pinch(tester, cell.center);
    expect(
      cellRect(tester, rowOf(12 * 60), colOf(2)).height,
      greaterThan(cell.height),
    );
    expect(counts.blocks, lessThanOrEqualTo(42));
    expect(counts.chips, 0);
    expect(counts.cards, 0);
    expect(counts.adds, 0);
    var stayed = 0;
    for (final entry in kept.entries) {
      final id = entry.key.substring("block-".length);
      final now = find.byKey(blockKey(id));
      if (now.evaluate().length == 1 &&
          identical(now.evaluate().single, entry.value)) {
        stayed++;
        expect(counts.blockCalls[id] ?? 0, 0, reason: id);
      }
    }
    expect(stayed, greaterThan(4));
    for (final entry in counts.blockCalls.entries) {
      expect(entry.value, lessThanOrEqualTo(1), reason: entry.key);
    }
  });

  testWidgets("BW7 new builders draw every block, a block exiting and a "
      "drag held included, the proxy keeping the builder of its lift", (
    tester,
  ) async {
    final a = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: a.builders,
    );
    await pickMode(tester, "Week");
    final ids = await weekIds(tester, api);
    expect(expectBlockMarks(tester, a, ids), greaterThan(4));

    final b = MarkingBuilders();
    await tester.pumpWidget(
      calendarApp(
        api: api,
        today: today,
        clock: nineOClock,
        editing: true,
        builders: b.builders,
      ),
    );
    await tester.pumpAndSettle();
    expect(expectBlockMarks(tester, b, ids), greaterThan(4));
    for (final id in ids) {
      final slot = blockFinder(id);
      if (slot.evaluate().isNotEmpty) {
        expect(a.marked(tester, slot, "block", id), isFalse, reason: id);
      }
    }

    // A swap while a deleted block exits.
    final c = MarkingBuilders();
    final standup = blockFinder(standupId);
    // The exit ramp scales a block across its day, the grid's lane axis.
    final width = tester.getSize(standup).width;
    await tester.tap(standup);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(harnessLatency);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(standup).width, lessThan(width));
    await tester.pumpWidget(
      calendarApp(
        api: api,
        today: today,
        clock: nineOClock,
        editing: true,
        builders: c.builders,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(c.marked(tester, standup, "block", standupId), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(standup, findsNothing);

    // A swap while a drag is held.
    final d = MarkingBuilders();
    final brainstorm = blockFinder(brainstormId);
    final rect = tester.getRect(brainstorm);
    final requests = api.requests.length;
    final gesture = await tester.startGesture(rect.center);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveBy(const Offset(0.0, 40.0));
    await tester.pump();
    final proxy = find.descendant(
      of: find.byKey(liftedBlockKey),
      matching: find.byKey(markKey("block", brainstormId)),
    );
    expect(proxy, findsOneWidget);
    expect(c.marks.contains(tester.widget(proxy)), isTrue);
    await tester.pumpWidget(
      calendarApp(
        api: api,
        today: today,
        clock: nineOClock,
        editing: true,
        builders: d.builders,
      ),
    );
    await gesture.moveBy(const Offset(0.0, 40.0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(c.marks.contains(tester.widget(proxy)), isTrue);
    final inPlace = find.descendant(
      of: brainstorm,
      matching: find.byKey(markKey("block", brainstormId)),
    );
    expect(tester.widgetList(inPlace).where(d.marks.contains), hasLength(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(api.requests, hasLength(requests + 1));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
  });

  testWidgets("BW8 a block takes its tap and long press anywhere in its "
      "box, whatever its builder paints", (tester) async {
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: ItemBuilders(
        block: (context, entry, details) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(entry.entry.title),
          );
        },
      ),
    );
    await pickMode(tester, "Week");
    final point =
        tester.getRect(blockFinder(brainstormId)).bottomLeft +
        const Offset(2.0, -2.0);
    final path = tester.hitTestOnBinding(point).path;
    expect(
      path.map((entry) {
        return entry.target;
      }).whereType<RenderParagraph>(),
      isEmpty,
    );
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsNothing);

    final gesture = await tester.startGesture(point);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await tester.pump();
    expect(find.text("Brainstorm with the team"), findsNWidgets(2));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("BW9 a block builder that throws loses its own output alone: "
      "the block still opens on a tap", (tester) async {
    final marks = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: marks.builders,
    );
    await pickMode(tester, "Week");
    final thrown = StateError("A builder that fails for Brainstorm.");
    await tester.pumpWidget(
      calendarApp(
        api: api,
        today: today,
        clock: nineOClock,
        editing: true,
        builders: ItemBuilders(
          block: (context, entry, details) {
            if (entry.id == brainstormId) {
              throw thrown;
            }
            return marks.block(context, entry, details);
          },
        ),
      ),
    );
    expect(tester.takeException(), same(thrown));
    expect(
      find.descendant(
        of: blockFinder(brainstormId),
        matching: find.byType(ErrorWidget),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: blockFinder(standupId),
        matching: find.byKey(markKey("block", standupId)),
      ),
      findsOneWidget,
    );
    await tester.tap(blockFinder(brainstormId));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Edit Task"), findsOneWidget);
    expect(find.text("Brainstorm with the team"), findsOneWidget);
  });

  testWidgets("BW10 a pending default block's indicator repaints its own "
      "layer alone, and nothing under the grid builds", (tester) async {
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: const ItemBuilders(),
    );
    await pickMode(tester, "Week");
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, rowOf(14 * 60), colOf(5)).topLeft,
    );
    await tester.pump(oneFrame);
    final indicator = find.descendant(
      of: blockFinder(brainstormId),
      matching: find.byType(CalendarActivityIndicator),
    );
    expect(indicator, findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(of: indicator, matching: find.byType(RepaintBoundary)),
    );
    final arc = tester.renderObject<RenderCustomPaint>(
      find.descendant(of: indicator, matching: find.byType(CustomPaint)),
    );
    final top = tester.element(grid);
    final rebuilt = <Element>[];
    final painted = <RenderObject>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      var under = identical(element, top);
      element.visitAncestorElements((ancestor) {
        under = under || identical(ancestor, top);
        return !under;
      });
      if (under) {
        rebuilt.add(element);
      }
    };
    debugOnProfilePaint = painted.add;
    try {
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(oneFrame);
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
      debugOnProfilePaint = null;
    }
    expect(rebuilt, isEmpty);
    expect(painted, contains(arc));
    for (final object in painted) {
      expect(isBelow(object, boundary), isTrue, reason: "$object");
    }
    await pumpFor(tester, second);
    await tester.pumpAndSettle();
  });

  testWidgets("BW11 a block builder runs again when an inherited widget it "
      "read notifies, and on a hot reload", (tester) async {
    final calls = <String, int>{};
    final builders = ItemBuilders(
      block: (context, entry, details) {
        CalendarTheme.of(context);
        calls.update(entry.id, (count) => count + 1, ifAbsent: () => 1);
        return harborBlockBuilder(context, entry, details);
      },
    );
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 844.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(themedApp(api, builders, harborCalendarTheme));
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    await pickMode(tester, "Week");
    expect(calls[brainstormId], greaterThan(0));

    calls.clear();
    await tester.pumpWidget(themedApp(api, builders, harborCalendarTheme));
    await tester.pumpAndSettle();
    expect(calls[brainstormId], isNull);

    await tester.pumpWidget(
      themedApp(
        api,
        builders,
        harborCalendarTheme.copyWith(text: const Color(0xFF202020)),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls[brainstormId], 1);

    calls.clear();
    final reassembled = tester.binding.reassembleApplication();
    await tester.pump();
    await reassembled;
    await tester.pumpAndSettle();
    expect(calls[brainstormId], 1);
  });

  testWidgets("BW12 a write that changes only an entry's payload runs its "
      "block builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      day: day,
      startMinute: 10 * 60,
      endMinute: 11 * 60,
      title: "Note",
      color: const Color(0xFF336699),
      payload: "first",
    );
    // The in-memory store applies a write within the call, so the payload
    // changes with no pending state between.
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[note],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TimedGrid<String>(
          store: store,
          settings: const CalendarSettings(),
          firstDay: day,
          dayCount: 1,
          selectedDay: day,
          today: day,
          now: now,
          onSelectDay: (day) {},
          onOpenItem: (id) {},
          onCreate: (range) async {},
          blockBuilder: (context, entry, details) {
            calls.add(entry);
            return Text(entry.entry.payload);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final block = blockFinder("note-1");
    expect(
      find.descendant(of: block, matching: find.text("first")),
      findsOneWidget,
    );
    final before = calls.length;
    expect(calls.last.pending, isFalse);

    await store.update(note.copyWith(payload: "second"));
    await tester.pumpAndSettle();
    expect(calls.length, before + 1);
    expect(calls.last.pending, isFalse);
    expect(calls.last.entry.payload, "second");
    expect(
      find.descendant(of: block, matching: find.text("second")),
      findsOneWidget,
    );
  });

  testWidgets("BM1 Month draws each chip through its builder, its pending "
      "state included", (tester) async {
    final marks = MarkingBuilders();
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: marks.builders,
    );
    await pickMode(tester, "Month");
    final slots = barSlots(tester);
    expect(slots.length, greaterThan(4));
    for (final slot in slots.entries) {
      final id = barIdOf(slot.key);
      expect(marks.marked(tester, slot.value, "chip", id), isTrue, reason: id);
    }
    expect(marks.chips, isNotEmpty);
    for (final call in marks.chips) {
      expect(call.details.card, isFalse, reason: call.entry.id);
    }

    final slot = slots.entries.firstWhere((slot) {
      return barIdOf(slot.key) == brainstormId;
    }).value;
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(marks.lastChip(brainstormId).entry.pending, isTrue);
    await tester.pump(second);
    await tester.pumpAndSettle();
    expect(slot, findsNothing);
  });

  testWidgets("BM2 days large enough for cards draw each bar through the "
      "chip builder's card form, its pending state included", (tester) async {
    final marks = MarkingBuilders();
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      size: const Size(1200.0, 1600.0),
      api: MockCalendarApi.seeded(today, latency: second),
      builders: marks.builders,
    );
    await pickMode(tester, "Month");
    final cell = gridViewport(tester).rectOfCell(0, 0)!;
    expect(monthShowsCards(cell.width, cell.height), isTrue);
    final slots = barSlots(tester);
    expect(slots.length, greaterThan(4));
    for (final slot in slots.entries) {
      final id = barIdOf(slot.key);
      expect(marks.marked(tester, slot.value, "chip", id), isTrue, reason: id);
      expect(marks.lastChip(id).details.card, isTrue, reason: id);
    }

    final slot = find.byKey(
      monthChipKey(monthSegmentKey(brainstormId, monday)),
    );
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final pending = marks.lastChip(brainstormId);
    expect(pending.entry.pending, isTrue);
    expect(pending.details.card, isTrue);
    expect(marks.marked(tester, slot, "chip", brainstormId), isTrue);
    await tester.pump(second);
    await tester.pumpAndSettle();
  });

  testWidgets("BM3 the month board's cover draws the loading and failure "
      "builders' content for the grid's days", (tester) async {
    final marks = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: marks.builders,
    );
    await pickMode(tester, "Month");
    await tester.tap(find.byTooltip("Next month"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(
      find.descendant(
        of: month,
        matching: find.byKey(markKey("loading", "cover")),
      ),
      findsOneWidget,
    );
    final loading = marks.loadings.last;
    expect(loading.site, CalendarStateSite.cover);
    expect(loading.first, DateTime(2026, 4, 27));
    expect(loading.last, DateTime(2026, 5, 31));
    await tester.pump(second);
    await tester.pumpAndSettle();

    api.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    final failed = find.descendant(
      of: month,
      matching: find.byKey(markKey("failure", "cover")),
    );
    await stepUntil(tester, api, "Next month", failed);
    expect(failed, findsOneWidget);
    final failure = marks.failures.last;
    expect(failure.site, CalendarStateSite.cover);
    expect(
      failure.error,
      isA<CalendarFailureException>().having(
        (error) => error.message,
        "message",
        "Reading failed.",
      ),
    );
    int lists() {
      return api.requests.where((request) {
        return request.method == CalendarMethod.list;
      }).length;
    }

    final before = lists();
    failure.retry();
    expect(lists(), before + 1);
    api.failurePolicy = null;
    await tester.pump(second);
    await tester.pumpAndSettle();
  });

  testWidgets("BM4 given no builders the month board draws the module's "
      "defaults, in the chip and the card form", (tester) async {
    final api = await pumpCalendar(
      tester,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: const ItemBuilders(),
    );
    await pickMode(tester, "Month");
    expect(find.byType(HarborChip), findsNothing);
    final bar = find.byKey(monthChipKey(monthSegmentKey(brainstormId, monday)));
    expect(bar, findsOneWidget);
    expectDefaultTaskBar(tester, bar);

    await tester.tap(find.byTooltip("Next month"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(
      find.descendant(
        of: month,
        matching: find.byType(CalendarActivityIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: month,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    await pumpFor(tester, second);

    api.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    final failed = find.descendant(of: month, matching: find.text(retryLabel));
    for (var i = 0; i < 3 && failed.evaluate().isEmpty; i++) {
      await tester.tap(find.byTooltip("Next month"));
      await pumpFor(tester, const Duration(milliseconds: 1400));
    }
    expect(
      find.descendant(of: month, matching: find.text(readFailedLabel)),
      findsOneWidget,
    );
    expect(failed, findsOneWidget);
    expect(find.text("Reading failed."), findsNothing);
    api.failurePolicy = null;
    await tester.tap(failed);
    await pumpFor(tester, const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    // Days large enough for cards, in a calendar of its own: the default
    // bar in its card form, the times under the title.
    await tester.pumpWidget(const SizedBox());
    await pumpCalendar(
      tester,
      clock: nineOClock,
      size: const Size(1200.0, 1600.0),
      builders: const ItemBuilders(),
    );
    await pickMode(tester, "Month");
    final cell = gridViewport(tester).rectOfCell(0, 0)!;
    expect(monthShowsCards(cell.width, cell.height), isTrue);
    expect(find.byType(HarborChip), findsNothing);
    expect(bar, findsOneWidget);
    expectDefaultTaskBar(tester, bar);
    expect(
      find.descendant(
        of: bar,
        matching: find.text(clockRangeLabel(14 * 60, 15 * 60)),
      ),
      findsOneWidget,
    );
  });

  testWidgets("BM5 a pinch and a scroll call the chip builder no more often "
      "than the base built chips, and call no block builder", (tester) async {
    final counts = CountingBuilders();
    await pumpCalendar(tester, clock: nineOClock, builders: counts.builders);
    await pickMode(tester, "Month");
    expect(counts.chips, greaterThan(4));
    counts.clear();

    final first = gridViewport(tester).rectOfCell(0, 0)!;
    await pinch(tester, tester.getCenter(month));
    expect(
      gridViewport(tester).rectOfCell(0, 0)!.height,
      greaterThan(first.height),
    );
    expect(counts.chips, lessThanOrEqualTo(3));
    expect(counts.blocks, 0);
    expect(counts.cards, 0);
    expect(counts.adds, 0);
    counts.clear();

    final vertical = gridViewport(tester).verticalPosition!;
    final before = vertical.pixels;
    await tester.drag(month, const Offset(0.0, -300.0));
    await tester.pumpAndSettle();
    expect(vertical.pixels - before, greaterThan(100.0));
    expect(counts.chips, 0);
    expect(counts.blocks, 0);
    expect(counts.cards, 0);
    expect(counts.adds, 0);
  });

  testWidgets("BM6 new builders reach a chip while it exits", (tester) async {
    final a = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: a.builders,
    );
    await pickMode(tester, "Month");
    final slot = find.byKey(
      monthChipKey(monthSegmentKey(brainstormId, monday)),
    );
    expect(slot, findsOneWidget);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(slot).height, lessThan(monthLaneExtent));

    final b = MarkingBuilders();
    await tester.pumpWidget(
      calendarApp(
        api: api,
        today: today,
        clock: nineOClock,
        editing: true,
        builders: b.builders,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(b.marked(tester, slot, "chip", brainstormId), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(slot, findsNothing);
  });

  testWidgets("BM7 a sync that leaves a bar as it was calls no chip builder "
      "for it", (tester) async {
    final counts = CountingBuilders();
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: counts.builders,
    );
    await pickMode(tester, "Month");
    final kept = barSlots(tester).keys.where((key) {
      return barIdOf(key) != brainstormId;
    }).toList();
    expect(kept.length, greaterThan(4));
    counts.clear();

    final store = tester.widget<MonthBoard<ItemPayload>>(month).store;
    store.requestDelete(brainstormId);
    await tester.pump();
    expect(counts.chipCalls[brainstormId], greaterThan(0));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    var stayed = 0;
    for (final key in kept) {
      if (find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty) {
        stayed++;
        expect(counts.chipCalls[barIdOf(key)] ?? 0, 0, reason: key);
      }
    }
    expect(stayed, greaterThan(4));
  });

  testWidgets("BA1 Agenda draws each card and add button through its "
      "builder, the pending state and the strips included", (tester) async {
    final marks = MarkingBuilders();
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: marks.builders,
    );
    final cards = keyedSlots("card-");
    expect(cards.length, greaterThan(4));
    for (final card in cards.entries) {
      final id = card.key.substring("card-".length);
      expect(marks.marked(tester, card.value, "card", id), isTrue, reason: id);
    }
    var gapsWithButton = 0;
    for (final gap in keyedSlots("day-list-gap-").values) {
      final adds = find.descendant(
        of: gap,
        matching: find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith("mark-add-") &&
              marks.marks.contains(widget);
        }),
      );
      if (addLabelsUnder(gap).evaluate().isEmpty) {
        expect(adds, findsNothing);
      } else {
        gapsWithButton++;
        expect(adds, findsOneWidget);
      }
    }
    expect(gapsWithButton, greaterThan(2));

    marks.lastCard(brainstormId).details.onDelete!();
    await tester.pumpAndSettle();
    expect(find.text("Delete item?"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(marks.lastCard(brainstormId).entry.pending, isTrue);
    await tester.pump(second);
    await tester.pumpAndSettle();
    expect(find.byKey(itemCardKey(brainstormId)), findsNothing);

    // A card whose item the hours cut at both ends, on Saturday, which
    // holds no other item, in a calendar of its own.
    await tester.pumpWidget(const SizedBox());
    final cut = MarkingBuilders();
    final cutApi = MockCalendarApi.seeded(today, latency: harnessLatency);
    final saturday = DateTime(2026, 4, 25);
    await createBeforePump(
      tester,
      cutApi,
      taskJson("Long day", saturday, 7 * 60, 19 * 60),
    );
    final longDay =
        (await listAll(tester, cutApi, saturday, saturday)).single["id"]!
            as String;
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: cutApi,
      builders: cut.builders,
    );
    await pickHours(tester, 8, 18);
    await tester.tap(find.byKey(dayCellKey(saturday)));
    await tester.pumpAndSettle();
    final details = cut.lastCard(longDay).details;
    expect(details.startsAt, isNotNull);
    expect(details.endsAt, isNotNull);
    final slot = find.byKey(itemCardKey(longDay));
    expect(slot, findsOneWidget);
    for (final strip in <Finder>[
      find.byKey(itemCardStartsAtKey(longDay)),
      find.byKey(itemCardEndsAtKey(longDay)),
      find.byType(Text),
    ]) {
      expect(find.descendant(of: slot, matching: strip), findsNothing);
    }
  });

  testWidgets("BA2 a day row draws the loading and failure builders' "
      "content for its day, the failure with the store's error or none", (
    tester,
  ) async {
    final marks = MarkingBuilders();
    final api = await stepToUnread(tester, marks.builders);
    final loadings = keyedSlots("day-list-loading-");
    expect(loadings, isNotEmpty);
    for (final row in loadings.entries) {
      final day = DateTime.parse(row.key.substring("day-list-loading-".length));
      expect(
        find.descendant(
          of: row.value,
          matching: find.byKey(markKey("loading", "dayRow")),
        ),
        findsOneWidget,
        reason: row.key,
      );
      final state = marks.loadings.lastWhere((state) {
        return state.first == day;
      });
      expect(state.site, CalendarStateSite.dayRow);
      expect(state.last, day);
    }

    await stepToFailed(tester, api);
    final failed = keyedSlots("day-list-failed-");
    expect(failed, isNotEmpty);
    for (final row in failed.entries) {
      expect(
        find.descendant(
          of: row.value,
          matching: find.byKey(markKey("failure", "dayRow")),
        ),
        findsOneWidget,
        reason: row.key,
      );
    }
    final failure = marks.failures.last;
    expect(failure.site, CalendarStateSite.dayRow);
    expect(failure.first, failure.last);
    expect(
      failure.error,
      isA<CalendarFailureException>().having(
        (error) => error.message,
        "message",
        "Reading failed.",
      ),
    );
    final lists = listCalls(api);
    failure.retry();
    expect(listCalls(api), lists + 1);
    api.failurePolicy = null;
    await pumpFor(tester, const Duration(milliseconds: 1500));

    // A prefetch failure while the shown month is ready: May 4, the first
    // day past April's month grid, leaves no error.
    await tester.pumpWidget(const SizedBox());
    final prefetch = MarkingBuilders();
    final prefetchApi = await pumpCalendar(
      tester,
      clock: nineOClock,
      api: MockCalendarApi.seeded(today, latency: second),
      builders: prefetch.builders,
    );
    prefetchApi.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    final may4 = DateTime(2026, 5, 4);
    bool listedMay4() {
      return prefetchApi.requests.any((request) {
        return request.method == CalendarMethod.list && request.first == may4;
      });
    }

    for (var drag = 0; drag < 100 && !listedMay4(); drag++) {
      await tester.drag(agenda, const Offset(0.0, -80.0));
      await tester.pump();
    }
    expect(listedMay4(), isTrue);
    await tester.pump(second);
    await tester.pump();
    final unread = find.byKey(dayListFailedKey(may4));
    for (var drag = 0; drag < 100 && unread.evaluate().isEmpty; drag++) {
      await tester.drag(agenda, const Offset(0.0, -40.0));
      await tester.pump();
    }
    expect(unread, findsOneWidget);
    final none = prefetch.failures.lastWhere((state) {
      return state.first == may4;
    });
    expect(none.error, isNull);
    await tester.pump(second);
    await tester.pumpAndSettle();
  });

  testWidgets("BA3 given no builders Agenda draws the module's defaults", (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: const ItemBuilders(),
    );
    for (final card in keyedSlots("card-").values) {
      expect(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate((widget) {
            return widget is PopupMenuButton;
          }),
        ),
        findsNothing,
      );
    }
    expect(find.byType(ItemCard), findsNothing);
    final task = harborTypeStyleOf(CalendarItemType.task).edge;
    final decorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(itemCardKey(brainstormId)),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) {
          return box.decoration;
        })
        .whereType<BoxDecoration>()
        .toList();
    expect(
      decorations.where((decoration) {
        return decoration.color ==
                Color.alphaBlend(
                  task.withValues(alpha: harborCalendarTheme.entryTintOpacity),
                  harborCalendarTheme.surface,
                ) &&
            decoration.border ==
                Border(left: BorderSide(color: task, width: 4.0));
      }),
      hasLength(1),
    );
    var labels = 0;
    for (final gap in keyedSlots("day-list-gap-").values) {
      expect(
        find.descendant(of: gap, matching: find.byType(InkWell)),
        findsNothing,
      );
      for (final label in addLabelsUnder(gap).evaluate()) {
        labels++;
        final circles = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byWidget(label.widget),
                matching: find.byType(DecoratedBox),
              ),
            )
            .where((box) {
              final decoration = box.decoration;
              return decoration is BoxDecoration &&
                  decoration.shape == BoxShape.circle &&
                  decoration.color == harborCalendarTheme.primaryTint;
            })
            .toList();
        expect(circles, hasLength(1));
        expect(
          tester
              .widgetList<Icon>(
                find.descendant(
                  of: find.byWidget(circles.single),
                  matching: find.byType(Icon),
                ),
              )
              .single
              .icon,
          harborCalendarTheme.addEntryIcon,
        );
      }
    }
    expect(labels, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    final api = await stepToUnread(tester, const ItemBuilders());
    final loadings = keyedSlots("day-list-loading-");
    expect(loadings, isNotEmpty);
    for (final row in loadings.values) {
      expect(
        find.descendant(
          of: row,
          matching: find.byType(CalendarActivityIndicator),
        ),
        findsOneWidget,
      );
    }
    await stepToFailed(tester, api);
    final failed = keyedSlots("day-list-failed-");
    expect(failed, isNotEmpty);
    for (final row in failed.values) {
      expect(
        find.descendant(of: row, matching: find.text(readFailedLabel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(retryLabel)),
        findsOneWidget,
      );
    }
    api.failurePolicy = null;
    await pumpFor(tester, second);
  });

  testWidgets("BA4 a card is handed Edit and Delete as the history lock and "
      "edit mode allow, each requesting its action for its own entry", (
    tester,
  ) async {
    final marks = MarkingBuilders();
    final api = await pumpLocked(tester, marks.builders);
    final ended = marks.lastCard(endedId).details;
    expect(ended.onEdit, isNull);
    expect(ended.onDelete, isNull);
    final running = marks.lastCard(runningId).details;
    expect(running.onEdit, isNotNull);
    expect(running.onDelete, isNull);
    final later = marks.lastCard(laterId).details;
    expect(later.onEdit, isNotNull);
    expect(later.onDelete, isNotNull);

    for (final (details, title) in <(CalendarCardDetails, String)>[
      (running, "Running"),
      (later, "Later"),
    ]) {
      details.onEdit!();
      await tester.pumpAndSettle();
      expect(find.text("Edit Task"), findsOneWidget, reason: title);
      expect(fieldText(tester, "Title"), title);
      await tester.tap(find.widgetWithText(TextButton, "Cancel"));
      await tester.pumpAndSettle();
    }
    marks.lastCard(laterId).details.onDelete!();
    await tester.pumpAndSettle();
    expect(find.text("Delete item?"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    expect(
      api.requests.last,
      isA<CalendarRequest>()
          .having((request) => request.method, "method", CalendarMethod.delete)
          .having((request) => request.id, "id", laterId),
    );
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    final viewing = MarkingBuilders();
    await pumpLocked(tester, viewing.builders, editing: false);
    expect(viewing.cards.length, greaterThan(4));
    for (final call in viewing.cards) {
      expect(call.details.onEdit, isNull, reason: call.entry.id);
      expect(call.details.onDelete, isNull, reason: call.entry.id);
    }
  });

  testWidgets("BA5 the add button and the card menu are heard by their "
      "labels, with no tooltip under the list", (tester) async {
    await pumpLocked(
      tester,
      harborItemBuilders,
      clock: () {
        return DateTime(2026, 4, 21, 9, 37);
      },
    );
    final add = find.descendant(
      of: find.byKey(dayListGapKey(today, 9 * 60)),
      matching: find.bySemanticsLabel("Add an item at 09:45"),
    );
    expect(add, findsOneWidget);
    expect(tester.getSemantics(add), isSemantics(hasTapAction: true));
    final menu = find.descendant(
      of: find.byKey(itemCardKey(laterId)),
      matching: find.bySemanticsLabel(itemActionsLabel),
    );
    expect(menu, findsOneWidget);
    expect(
      tester.getSemantics(menu),
      isSemantics(isButton: true, hasTapAction: true),
    );
    expect(find.byTooltip("Add an item at 09:45"), findsNothing);
    expect(find.byTooltip(itemActionsLabel), findsNothing);
    expect(
      find.descendant(of: agenda, matching: find.byType(RawTooltip)),
      findsNothing,
    );
    final tooltips = tester
        .widgetList<Tooltip>(
          find.descendant(of: agenda, matching: find.byType(Tooltip)),
        )
        .toList();
    for (final tooltip in tooltips) {
      expect(tooltip.message, "");
    }
    for (final id in <String>[runningId, laterId]) {
      expect(
        find.descendant(
          of: find.byKey(itemCardKey(id)),
          matching: find.byType(Tooltip),
        ),
        findsOneWidget,
        reason: id,
      );
    }
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text("Edit"), findsOneWidget);
    expect(find.text("Delete"), findsOneWidget);
    await tester.tapAt(const Offset(10.0, 10.0));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      api: MockCalendarApi(latency: harnessLatency),
      builders: const ItemBuilders(),
    );
    final labels = addLabelsUnder(agenda);
    expect(labels.evaluate().length, greaterThan(0));
    for (final element in labels.evaluate()) {
      final node = tester.getSemantics(find.byWidget(element.widget));
      expect(node.label, startsWith("Add an item at "));
      expect(node.label.contains("\n"), isFalse, reason: node.label);
      expect(node, isSemantics(hasTapAction: true));
    }
    expect(
      find.descendant(of: agenda, matching: find.byType(Tooltip)),
      findsNothing,
    );
    expect(
      find.descendant(of: agenda, matching: find.byType(RawTooltip)),
      findsNothing,
    );
  });

  testWidgets("BA6 a scroll of Agenda calls the card and add button "
      "builders no more often than the base built cards and add buttons", (
    tester,
  ) async {
    final counts = CountingBuilders();
    await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: counts.builders,
    );
    expect(counts.cards, greaterThan(4));
    counts.clear();
    final before = listOffset(tester);
    await tester.drag(agenda, const Offset(0.0, -400.0));
    await tester.pumpAndSettle();
    expect(listOffset(tester) - before, greaterThan(300.0));
    expect(counts.cards, greaterThan(0));
    expect(counts.cards, lessThanOrEqualTo(18));
    expect(counts.adds, lessThanOrEqualTo(24));
    expect(counts.blocks, 0);
    expect(counts.chips, 0);
  });

  testWidgets("BA7 new builders draw every card, a card leaving included", (
    tester,
  ) async {
    final a = MarkingBuilders();
    final api = await pumpCalendar(
      tester,
      editing: true,
      clock: nineOClock,
      builders: a.builders,
    );
    final b = MarkingBuilders();
    await tester.pumpWidget(
      calendarApp(
        api: api,
        today: today,
        clock: nineOClock,
        editing: true,
        builders: b.builders,
      ),
    );
    await tester.pumpAndSettle();
    final cards = keyedSlots("card-");
    expect(cards.length, greaterThan(4));
    for (final card in cards.entries) {
      final id = card.key.substring("card-".length);
      expect(b.marked(tester, card.value, "card", id), isTrue, reason: id);
      expect(a.marked(tester, card.value, "card", id), isFalse, reason: id);
    }

    final slot = find.byKey(itemCardKey(brainstormId));
    final row = find.ancestor(of: slot, matching: find.byType(SizeTransition));
    final height = tester.getSize(row.first).height;
    b.lastCard(brainstormId).details.onDelete!();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(row.first).height, lessThan(height));
    final c = MarkingBuilders();
    await tester.pumpWidget(
      calendarApp(
        api: api,
        today: today,
        clock: nineOClock,
        editing: true,
        builders: c.builders,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(c.marked(tester, slot, "card", brainstormId), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(slot, findsNothing);
  });

  testWidgets("BA8 a reveal predicts the cards it passes by the card "
      "builder's extent", (tester) async {
    final offsets = <double>[];
    for (final extent in <double>[40.0, 400.0]) {
      await tester.pumpWidget(const SizedBox());
      await pumpCalendar(
        tester,
        clock: nineOClock,
        builders: ItemBuilders(
          block: harborBlockBuilder,
          chip: harborChipBuilder,
          card: harborCardBuilder,
          cardExtent: (entry) {
            return extent;
          },
          addButton: harborAddButtonBuilder,
          loading: harborLoadingBuilder,
          failure: harborFailureBuilder,
        ),
      );
      // The next month's day, a reveal past the cards of days the list
      // has not laid out, which it predicts.
      final may21 = DateTime(2026, 5, 21);
      expect(find.byKey(dayListHeaderKey(may21)), findsNothing);
      await tester.tap(find.byTooltip("Next month"));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(oneFrame);
      }
      offsets.add(listOffset(tester));
      await tester.pumpAndSettle();
    }
    expect(offsets.first, isNot(moreOrLessEquals(offsets.last)));
  });

  testWidgets("BA9 a day row's states take the heights the list predicts", (
    tester,
  ) async {
    for (final builders in <ItemBuilders>[
      const ItemBuilders(),
      harborItemBuilders,
    ]) {
      await tester.pumpWidget(const SizedBox());
      final api = await stepToUnread(
        tester,
        builders,
        size: const Size(1200.0, 844.0),
      );
      final loadings = keyedSlots("day-list-loading-");
      expect(loadings, isNotEmpty);
      for (final row in loadings.values) {
        expect(tester.getSize(row).height, 24.0);
      }
      await stepToFailed(tester, api);
      final failed = keyedSlots("day-list-failed-");
      expect(failed, isNotEmpty);
      for (final row in failed.values) {
        expect(tester.getSize(row).height, 48.0);
      }
      api.failurePolicy = null;
      await pumpFor(tester, second);
    }
  });

  testWidgets("BM8 a write that changes only an entry's payload runs its "
      "chip builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      day: day,
      startMinute: 10 * 60,
      endMinute: 11 * 60,
      title: "Note",
      color: const Color(0xFF336699),
      payload: "first",
    );
    // The in-memory store applies a write within the call, so the payload
    // changes with no pending state between.
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[note],
    );
    addTearDown(store.dispose);
    final todayNotifier = ValueNotifier<DateTime>(day);
    addTearDown(todayNotifier.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: MonthGrid.of(day),
          selectedDay: day,
          today: todayNotifier,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenItem: (id) {},
          chipBuilder: (context, entry, details) {
            calls.add(entry);
            return Text(entry.entry.payload);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byKey(monthChipKey(monthSegmentKey("note-1", monday)));
    expect(
      find.descendant(of: bar, matching: find.text("first")),
      findsOneWidget,
    );
    final before = calls.length;

    await store.update(note.copyWith(payload: "second"));
    await tester.pumpAndSettle();
    expect(calls.length, before + 1);
    expect(calls.last.pending, isFalse);
    expect(calls.last.entry.payload, "second");
    expect(
      find.descendant(of: bar, matching: find.text("second")),
      findsOneWidget,
    );
  });

  testWidgets("BA10 a write that changes only an entry's payload runs its "
      "card builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      day: day,
      startMinute: 10 * 60,
      endMinute: 11 * 60,
      title: "Note",
      color: const Color(0xFF336699),
      payload: "first",
    );
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[note],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DayList<String>(
          store: store,
          weekdays: WeekdaySet.all,
          format: HourLabelFormat.twentyFourHour,
          hours: DayHours.allDay,
          editable: false,
          lock: HistoryLock.none,
          selectedDay: day,
          today: day,
          now: now,
          onTopDay: (day) {},
          onCreateIn: (day, startMinute, endMinute) {},
          onEdit: (id) {},
          onDelete: (id) {},
          cardBuilder: (context, entry, details) {
            calls.add(entry);
            return Text(entry.entry.payload);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(itemCardKey("note-1"));
    expect(
      find.descendant(of: card, matching: find.text("first")),
      findsOneWidget,
    );
    final before = calls.length;

    await store.update(note.copyWith(payload: "second"));
    await tester.pumpAndSettle();
    expect(calls.length, greaterThan(before));
    expect(calls.last.pending, isFalse);
    expect(calls.last.entry.payload, "second");
    expect(
      find.descendant(of: card, matching: find.text("second")),
      findsOneWidget,
    );
  });
}
