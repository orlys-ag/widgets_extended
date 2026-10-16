/// The calendar's Month mode: the month board's weeks, chips and days, its
/// taps, keys and chevrons, its load overlay, and its syncs with the
/// model.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board_controller.dart'
    show BoardControllerInternals;
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';

import 'calendar_harness.dart';

/// Layout rounds track offsets, so geometry is compared to half a pixel.
Matcher near(double value) {
  return moreOrLessEquals(value, epsilon: 0.5);
}

const Duration oneFrame = Duration(milliseconds: 16);

/// The height of a day's number strip and of one chip lane.
const double strip = 28.0;
const double lane = 18.0;

DateTime april(int day) {
  return DateTime(2026, 4, day);
}

DateTime may(int day) {
  return DateTime(2026, 5, day);
}

/// The month board, as the calendar keys it.
Finder monthBoardFinder() {
  return find.byKey(const ValueKey<String>("month-board"));
}

/// The chip of the item [id] in the calendar week starting on [monday].
Finder chipFinder(String id, DateTime monday) {
  return find.byKey(ValueKey<String>("month-chip-$id@${isoDate(monday)}"));
}

Finder dayFinder(DateTime day) {
  return find.byKey(ValueKey<String>("month-day-${isoDate(day)}"));
}

Finder stripFinder(DateTime day) {
  return find.byKey(ValueKey<String>("month-strip-${isoDate(day)}"));
}

/// The month board's viewport: in Month mode the one board keyed by
/// strings.
RenderBoardViewport<String> monthViewport(WidgetTester tester) {
  return gridViewport(tester);
}

/// Pumps the calendar over a mock holding [seed] at [latency] and picks
/// Month.
Future<MockCalendarApi> pumpMonth(
  WidgetTester tester, {
  List<Map<String, Object?>> seed = const <Map<String, Object?>>[],
  Duration latency = harnessLatency,
}) async {
  final api = MockCalendarApi(seed: seed, latency: latency);
  await pumpCalendar(tester, api: api);
  await pickMode(tester, "Month");
  return api;
}

/// Pumps the calendar over the default seed and picks Month.
Future<MockCalendarApi> pumpSeededMonth(WidgetTester tester) async {
  final api = await pumpCalendar(tester);
  await pickMode(tester, "Month");
  return api;
}

/// Taps [day]'s empty part: its cell's centre column, 4 px above the
/// upper of its cell's bottom edge and the month board's.
Future<void> tapEmptyPart(WidgetTester tester, DateTime day) async {
  final cell = tester.getRect(dayFinder(day));
  final board = tester.getRect(monthBoardFinder());
  final bottom = math.min(cell.bottom, board.bottom);
  await tester.tapAt(Offset(cell.center.dx, bottom - 4.0));
  await tester.pumpAndSettle();
}

/// Dismisses the create flow's type picker with a tap on its barrier.
Future<void> dismissPicker(WidgetTester tester) async {
  expect(find.text("New item"), findsOneWidget);
  await tester.tapAt(const Offset(10.0, 10.0));
  await tester.pumpAndSettle();
  expect(find.text("New item"), findsNothing);
}

/// Picks Task in the create flow's type picker.
Future<void> pickTask(WidgetTester tester) async {
  expect(find.text("New item"), findsOneWidget);
  await tester.tap(find.text("Task").last);
  await tester.pumpAndSettle();
}

Finder fieldFinder(String label) {
  return find.widgetWithText(TextField, label);
}

String fieldText(WidgetTester tester, String label) {
  return tester.widget<TextField>(fieldFinder(label)).controller!.text;
}

Finder dropdownFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) {
      return widget is DropdownButtonFormField;
    }),
  );
}

/// The time the form's [label] dropdown shows.
Finder dropdownShows(String label, String time) {
  return find.descendant(of: dropdownFinder(label), matching: find.text(time));
}

Finder formButton(String label) {
  return find.widgetWithText(TextButton, label);
}

Finder saveFinder() {
  return find.byType(FilledButton);
}

/// Picks [option] in the dropdown labelled [label], scrolling its menu by
/// [delta], forward for a positive one, until the option shows.
Future<void> chooseOption(
  WidgetTester tester,
  String label,
  String option, {
  double delta = 100.0,
}) async {
  await tester.tap(dropdownFinder(label));
  await tester.pumpAndSettle();
  final menu = find.byType(Scrollable).last;
  final item = find.descendant(of: menu, matching: find.text(option));
  await tester.scrollUntilVisible(item, delta, scrollable: menu);
  // Centred, as an item scrolled to the menu's edge can sit under it.
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// The days whose number sits on the selection's pill, in its colour.
List<DateTime> pilledDays(WidgetTester tester) {
  final days = <DateTime>[];
  final strips = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("month-strip-");
  });
  for (final element in strips.evaluate()) {
    final key = (element.widget.key! as ValueKey<String>).value;
    final day = parseIsoDate(key.substring("month-strip-".length))!;
    final number = find.descendant(
      of: stripFinder(day),
      matching: find.text("${day.day}"),
    );
    final color = tester
        .renderObject<RenderParagraph>(number)
        .text
        .style!
        .color!;
    if (color.toARGB32() == HarborColors.onPrimary.toARGB32()) {
      days.add(day);
    }
  }
  return days;
}

/// The task [title] on [day] from [start] to [end] o'clock.
Map<String, Object?> taskAt(String title, DateTime day, int start, int end) {
  return taskJson(title, day, start * 60, end * 60);
}

/// [count] one-hour tasks on [day] from [start] o'clock on.
List<Map<String, Object?>> hourlyTasks(DateTime day, int count, int start) {
  return <Map<String, Object?>>[
    for (var hour = start; hour < start + count; hour++)
      taskAt("Task at $hour", day, hour, hour + 1),
  ];
}

int listCount(MockCalendarApi api) {
  return api.requests.where((request) {
    return request.method == CalendarMethod.list;
  }).length;
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip("Calendar settings"));
  await tester.pumpAndSettle();
}

/// Closes the sheet with a tap on the barrier above it.
Future<void> closeSettings(WidgetTester tester) async {
  await tester.tapAt(const Offset(195.0, 20.0));
  await tester.pumpAndSettle();
}

/// Opens the calendar settings, flips the weekends switch and closes them.
Future<void> toggleWeekends(WidgetTester tester) async {
  await openSettings(tester);
  await tester.tap(find.byKey(weekendsSwitchKey));
  await tester.pumpAndSettle();
  await closeSettings(tester);
}

/// Whether [context] lies inside the month board.
bool insideMonthBoard(BuildContext? context) {
  if (context == null) {
    return false;
  }
  var inside = false;
  context.visitAncestorElements((element) {
    if (element.widget.key == const ValueKey<String>("month-board")) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// Whether [day]'s cell lies wholly inside the month board.
bool whollyInsideBoard(WidgetTester tester, DateTime day) {
  final cell = tester.getRect(dayFinder(day));
  final board = tester.getRect(monthBoardFinder());
  return cell.top >= board.top - 0.5 && cell.bottom <= board.bottom + 0.5;
}

void main() {
  testWidgets(
    "M1 the menu lists Agenda, Month, Week and Day and the calendar opens "
    "in Agenda",
    (tester) async {
      await pumpCalendar(tester);
      expect(find.text("Agenda"), findsOneWidget);
      expect(find.byType(DayList), findsOneWidget);
      expect(find.byType(DayCell), findsNWidgets(35));

      await tester.tap(find.byTooltip("Calendar view"));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((widget) {
          return widget is PopupMenuItem;
        }),
        findsNWidgets(4),
      );
      final tops = <double>[
        for (final label in <String>["Agenda", "Month", "Week", "Day"])
          tester.getRect(find.text(label).last).top,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]));
      }
    },
  );

  testWidgets(
    "M2 every item of the month has a chip in each week and on each shown "
    "day it covers",
    (tester) async {
      final api = await pumpSeededMonth(tester);
      final grid = MonthGrid.of(today);
      final listed = await listAll(tester, api, grid.firstDay, grid.lastDay);
      // Sanity: the seed holds items across the month.
      expect(listed.length, greaterThan(10));
      for (final json in listed) {
        final item = CalendarItem.fromJson(json);
        final itemLast = addDays(item.day, item.dayCount - 1);
        for (var row = 0; row < grid.weekCount; row++) {
          final monday = grid.dateAt(row, 0);
          final sunday = addDays(monday, 6);
          final first = item.day.isAfter(monday) ? item.day : monday;
          final last = itemLast.isBefore(sunday) ? itemLast : sunday;
          if (first.isAfter(last)) {
            continue;
          }
          final chip = chipFinder(item.id!, monday);
          expect(chip, findsOneWidget, reason: "${item.title} in $monday");
          final rect = tester.getRect(chip);
          final firstCell = tester.getRect(dayFinder(first));
          final lastCell = tester.getRect(dayFinder(last));
          expect(rect.left, near(firstCell.left));
          expect(rect.right, near(lastCell.right));
          expect(rect.top, greaterThanOrEqualTo(firstCell.top + strip - 0.5));
        }
      }
      expect(find.byType(DayList), findsNothing);
    },
  );

  testWidgets(
    "M3 weeks that fit fill the board and the board does not scroll",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[
          taskAt("Ninth", april(9), 10, 11),
          taskAt("Sixteenth", april(16), 10, 11),
          taskAt("Twenty-first", april(21), 10, 11),
        ],
      );
      final board = tester.getRect(monthBoardFinder());
      for (var row = 0; row < 5; row++) {
        final day = addDays(DateTime(2026, 3, 30), 7 * row);
        expect(tester.getSize(dayFinder(day)).height, near(board.height / 5));
      }
      expect(
        monthViewport(tester).verticalPosition!.maxScrollExtent,
        near(0.0),
      );
    },
  );

  testWidgets(
    "M4 a week needing more lanes grows to the strip plus its lanes",
    (tester) async {
      await pumpMonth(tester, seed: hourlyTasks(april(22), 7, 8));
      final board = tester.getRect(monthBoardFinder());
      final fitted = board.height / 5;
      final grown = tester.getSize(dayFinder(april(22))).height;
      expect(grown, near(strip + 7 * lane));
      expect(grown, greaterThan(fitted + 0.5));
      for (final day in <DateTime>[
        DateTime(2026, 3, 30),
        april(6),
        april(13),
        april(27),
      ]) {
        expect(tester.getSize(dayFinder(day)).height, near(fitted));
      }
      expect(
        monthViewport(tester).verticalPosition!.maxScrollExtent,
        greaterThan(0.0),
      );
    },
  );

  testWidgets(
    "M5 a bar per week, clipped to the shown columns, rounded only where "
    "the item ends",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[
          taskJson("X", april(24), 10 * 60, 11 * 60, dayCount: 5),
          taskJson("W", april(25), 11 * 60, 12 * 60, dayCount: 2),
        ],
      );
      const x = "item-1";
      const w = "item-2";
      void expectOn(Finder chip, DateTime first, DateTime last) {
        final rect = tester.getRect(chip);
        expect(rect.left, near(tester.getRect(dayFinder(first)).left));
        expect(rect.right, near(tester.getRect(dayFinder(last)).right));
      }

      BorderRadiusGeometry? radiusOf(Finder chip) {
        return tester
            .widget<ClipRRect>(
              find.descendant(of: chip, matching: find.byType(ClipRRect)),
            )
            .borderRadius;
      }

      final xFirst = chipFinder(x, april(20));
      final xSecond = chipFinder(x, april(27));
      expectOn(xFirst, april(24), april(26));
      expectOn(xSecond, april(27), april(28));
      expect(
        radiusOf(xFirst),
        const BorderRadius.horizontal(left: Radius.circular(4.0)),
      );
      expect(
        radiusOf(xSecond),
        const BorderRadius.horizontal(right: Radius.circular(4.0)),
      );
      expectOn(chipFinder(w, april(20)), april(25), april(26));

      await toggleWeekends(tester);
      expectOn(xFirst, april(24), april(24));
      expectOn(xSecond, april(27), april(28));
      expect(chipFinder(w, april(20)), findsNothing);
    },
  );

  testWidgets(
    "M6 an earlier item created later stacks above, and a multi-day item "
    "starting that day above both",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[
          taskAt("T", april(21), 14, 15),
          taskJson("M", april(21), 18 * 60, 19 * 60, dayCount: 2),
        ],
      );
      await tapEmptyPart(tester, april(21));
      await pickTask(tester);
      await chooseOption(tester, "Start", "08:00");
      await chooseOption(tester, "End", "09:00");
      await tester.enterText(fieldFinder("Title"), "Early");
      await tester.tap(saveFinder());
      await tester.pump(harnessLatency);
      await tester.pumpAndSettle();
      expect(find.text("New Task"), findsNothing);

      final monday = april(20);
      final m = tester.getRect(chipFinder("item-2", monday)).top;
      final early = tester.getRect(chipFinder("item-3", monday)).top;
      final t = tester.getRect(chipFinder("item-1", monday)).top;
      expect(m, lessThan(early));
      expect(early, lessThan(t));
    },
  );

  testWidgets("M6b a bar continuing from the week before stacks above a chip "
      "starting that day", (tester) async {
    await pumpMonth(
      tester,
      seed: <Map<String, Object?>>[
        taskJson("P", april(19), 18 * 60, 19 * 60, dayCount: 2),
        taskAt("Q", april(20), 9, 10),
      ],
    );
    final p = tester.getRect(chipFinder("item-1", april(20)));
    final q = tester.getRect(chipFinder("item-2", april(20)));
    // Sanity: the week clips P's bar to the columns Q's chip holds.
    expect(p.left, near(q.left));
    expect(p.right, near(q.right));
    expect(p.top, lessThan(q.top));
  });

  testWidgets(
    "M7 a widened chip paints one lane, and a tap below it creates on its "
    "day",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[
          taskJson("A", april(20), 9 * 60, 10 * 60, dayCount: 3),
          taskAt("B", april(20), 10, 11),
          taskAt("C", april(20), 11, 12),
          taskAt("D", april(22), 12, 13),
        ],
      );
      final chip = chipFinder("item-4", april(20));
      final box = tester.getRect(chip);
      expect(box.height, near(lane));
      final band = tester.getRect(
        find.ancestor(of: chip, matching: find.byType(Align)).first,
      );
      expect(band.height, near(2 * lane));
      final below = Offset(box.center.dx, box.bottom + 9.0);
      expect(band.contains(below), isTrue);

      await tester.tapAt(below);
      await tester.pumpAndSettle();
      await pickTask(tester);
      expect(find.text("2026-04-22"), findsOneWidget);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "M8 a chip shows its title in its type's colours without a time, and a "
    "pending one is dimmed and inert",
    (tester) async {
      const latency = Duration(seconds: 1);
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[taskAt("Plan sprint", april(23), 10, 11)],
        latency: latency,
      );
      final chip = chipFinder("item-1", april(20));
      final title = find.descendant(
        of: chip,
        matching: find.text("Plan sprint"),
      );
      expect(title, findsOneWidget);
      final text = tester.widget<Text>(title);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final style = harborTypeStyleOf(CalendarItemType.task);
      Finder coloredBox(Color color) {
        return find.descendant(
          of: chip,
          matching: find.byWidgetPredicate((widget) {
            return widget is ColoredBox &&
                widget.color.toARGB32() == color.toARGB32();
          }),
        );
      }

      expect(coloredBox(style.tint), findsWidgets);
      expect(coloredBox(style.edge), findsOneWidget);
      expect(tester.getSize(coloredBox(style.edge)).width, near(4.0));
      expect(
        find.descendant(
          of: chip,
          matching: find.textContaining(RegExp(r"\d\d:\d\d")),
        ),
        findsNothing,
      );

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text("Edit Task"), findsOneWidget);
      await tester.tap(formButton("Delete"));
      await tester.pumpAndSettle();
      await tester.tap(formButton("Delete").last);
      await tester.pumpAndSettle();
      expect(find.text("Edit Task"), findsNothing);
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: chip, matching: find.byType(Opacity)),
            )
            .opacity,
        0.5,
      );

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text("Edit Task"), findsNothing);
      expect(find.text("New item"), findsNothing);
      expect(pilledDays(tester), <DateTime>[april(21)]);

      await tester.pump(latency);
      await tester.pumpAndSettle();
    },
  );

  testWidgets("M9 a tap on a chip opens its edit form", (tester) async {
    await pumpSeededMonth(tester);
    await tester.tap(chipFinder(uxFlowId, april(20)));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);
    expect(fieldText(tester, "Title"), "Design new UX flow for Michael");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();
  });

  testWidgets(
    "M10 a tap on a day's number strip selects it and shows Day mode",
    (tester) async {
      await pumpSeededMonth(tester);
      await tester.tap(stripFinder(april(22)));
      await tester.pumpAndSettle();
      expect(find.text("Day"), findsOneWidget);
      expect(find.byKey(dayHeaderKey(april(22))), findsOneWidget);
    },
  );

  testWidgets(
    "M11a a tap on a day's empty part selects it and creates at the first "
    "free hour",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[taskAt("Night", april(22), 0, 1)],
      );
      await tapEmptyPart(tester, april(22));
      await pickTask(tester);
      expect(find.text("2026-04-22"), findsOneWidget);
      expect(dropdownShows("Start", "01:00"), findsOneWidget);
      expect(dropdownShows("End", "02:00"), findsOneWidget);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
      expect(pilledDays(tester), <DateTime>[april(22)]);
    },
  );

  testWidgets(
    "M11b a day free only before the hours' end creates 30 minutes to the "
    "end",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[
          taskJson("Long", april(22), 0, 23 * 60 + 30),
        ],
      );
      await tapEmptyPart(tester, april(22));
      await pickTask(tester);
      expect(dropdownShows("Start", "23:30"), findsOneWidget);
      expect(dropdownShows("End", "24:00"), findsOneWidget);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "M11c a day with no free start creates at the hours' first hour",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[taskAt("All day", april(22), 0, 24)],
      );
      await tapEmptyPart(tester, april(22));
      await pickTask(tester);
      expect(dropdownShows("Start", "00:00"), findsOneWidget);
      expect(dropdownShows("End", "01:00"), findsOneWidget);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "M12 a tap on a muted day's empty part creates there and keeps the "
    "selection and the month",
    (tester) async {
      await pumpMonth(tester);
      await tapEmptyPart(tester, DateTime(2026, 3, 31));
      await pickTask(tester);
      expect(find.text("2026-03-31"), findsOneWidget);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
      expect(find.text("April 2026"), findsOneWidget);
      expect(pilledDays(tester), <DateTime>[april(21)]);
    },
  );

  testWidgets(
    "M13 Month's Add creates on the selected day with no floating button; "
    "Agenda's opens Week",
    (tester) async {
      await pumpSeededMonth(tester);
      await tester.tap(find.byTooltip("Add"));
      await tester.pumpAndSettle();
      await pickTask(tester);
      expect(find.text("2026-04-21"), findsOneWidget);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
      expect(find.byTooltip("Add item"), findsNothing);

      await pickMode(tester, "Agenda");
      await tester.tap(find.byTooltip("Add"));
      await tester.pumpAndSettle();
      expect(find.text("Week"), findsOneWidget);
    },
  );

  testWidgets(
    "M14 the chevrons step a month and a key onto next month's muted day "
    "re-dates the grid",
    (tester) async {
      await pumpMonth(tester);
      expect(find.byTooltip("Previous month"), findsOneWidget);
      expect(find.byTooltip("Next month"), findsOneWidget);

      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      await tester.pump(harnessLatency);
      await tester.pumpAndSettle();
      expect(find.text("May 2026"), findsOneWidget);
      expect(pilledDays(tester), <DateTime>[may(21)]);

      await tester.tap(find.byTooltip("Previous month"));
      await tester.pumpAndSettle();
      expect(find.text("April 2026"), findsOneWidget);
      expect(pilledDays(tester), <DateTime>[april(21)]);

      await tapEmptyPart(tester, april(30));
      await dismissPicker(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(pilledDays(tester), <DateTime>[april(30)]);
      expect(find.text("April 2026"), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text("May 2026"), findsOneWidget);
      expect(pilledDays(tester), <DateTime>[may(1)]);
      expect(dayFinder(may(31)), findsOneWidget);
      expect(dayFinder(DateTime(2026, 3, 30)), findsNothing);
    },
  );

  testWidgets(
    "M14b a key from a six-week month into a five-week month re-dates the "
    "grid",
    (tester) async {
      await pumpMonth(tester);
      await tester.tap(find.byTooltip("Previous month"));
      await tester.pump();
      await tester.pump(harnessLatency);
      await tester.pumpAndSettle();
      await tapEmptyPart(tester, DateTime(2026, 3, 31));
      await dismissPicker(tester);
      expect(monthViewport(tester).controller.rows.axis.trackCount, 6);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text("April 2026"), findsOneWidget);
      expect(pilledDays(tester), <DateTime>[april(1)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets("M14c two keys before a frame each move the selected day", (
    tester,
  ) async {
    await pumpMonth(tester);
    await tapEmptyPart(tester, april(21));
    await dismissPicker(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(pilledDays(tester), <DateTime>[april(21)]);
    expect(find.text("April 2026"), findsOneWidget);

    await tapEmptyPart(tester, april(30));
    await dismissPicker(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(pilledDays(tester), <DateTime>[april(30)]);
    expect(find.text("April 2026"), findsOneWidget);
  });

  testWidgets(
    "M15 Month shows the load overlay while it loads, and the error and a "
    "Retry that reads again",
    (tester) async {
      final api = await pumpSeededMonth(tester);
      api.failurePolicy = (request) {
        return request.method == CalendarMethod.list ? "Reading failed." : null;
      };
      Finder underBoard(Finder finder) {
        return find.descendant(of: monthBoardFinder(), matching: finder);
      }

      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      expect(
        underBoard(find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );

      await tester.pump(harnessLatency);
      expect(underBoard(find.text("Reading failed.")), findsOneWidget);
      expect(underBoard(find.text("Retry")), findsOneWidget);

      api.failurePolicy = null;
      final reads = listCount(api);
      await tester.tap(underBoard(find.text("Retry")));
      await tester.pump();
      expect(listCount(api), reads + 1);
      await tester.pump(harnessLatency);
      await tester.pump();
      expect(underBoard(find.byType(CircularProgressIndicator)), findsNothing);
      expect(underBoard(find.text("Retry")), findsNothing);
    },
  );

  testWidgets(
    "M16 a model change that alters one item builds that item's chips only",
    (tester) async {
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[
          taskAt("X", april(21), 14, 15),
          taskAt("Y", april(21), 15, 16),
          taskJson("Z", april(23), 9 * 60, 10 * 60, dayCount: 5),
          taskAt("Eighth", april(8), 10, 11),
          taskAt("Fifteenth", april(15), 10, 11),
        ],
      );
      final monday = april(20);
      final x = chipFinder("item-1", monday);
      final yKey = "month-chip-item-2@${isoDate(monday)}";
      final xTop = tester.getRect(x).top;

      await tester.tap(chipFinder("item-2", monday));
      await tester.pumpAndSettle();
      expect(find.text("Edit Task"), findsOneWidget);
      await chooseOption(tester, "Start", "08:00", delta: -100.0);
      await chooseOption(tester, "End", "09:00", delta: -100.0);

      final reported = <String>{};
      addTearDown(() {
        debugOnRebuildDirtyWidget = null;
      });
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final key = element.widget.key;
        if (key is ValueKey<String> &&
            (key.value.startsWith("month-chip-") ||
                key.value.startsWith("month-day-"))) {
          reported.add(key.value);
        }
      };
      await tester.tap(saveFinder());
      await tester.pump(harnessLatency);
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      expect(find.text("Edit Task"), findsNothing);
      expect(reported, contains(yKey));
      expect(reported, <String>{yKey});
      expect(
        reported.where((key) {
          return key.startsWith("month-day-");
        }),
        isEmpty,
      );
      expect(tester.getRect(x).top, greaterThan(xTop + 0.5));
    },
  );

  testWidgets("M17 a month change and a weekday change each sync once with no "
      "animation", (tester) async {
    await pumpSeededMonth(tester);
    final controller = monthViewport(tester).controller;
    var structural = 0;
    var ticks = 0;
    void onStructural(Set<String>? keys) {
      structural++;
    }

    void onTick() {
      ticks++;
    }

    controller.addStructuralListener(onStructural);
    controller.addAnimationListener(onTick);

    await tester.tap(find.byTooltip("Next month"));
    await tester.pump();
    expect(structural, 1);
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(structural, 2);
    expect(ticks, 0);

    structural = 0;
    final slides = controller.debugSlideInstallCount;
    await tester.tap(find.byTooltip("Previous month"));
    await tester.pump();
    expect(structural, 1);
    await tester.pumpAndSettle();
    expect(structural, 1);
    expect(ticks, 0);
    expect(controller.debugSlideInstallCount, slides);

    structural = 0;
    await toggleWeekends(tester);
    expect(structural, 1);
    expect(ticks, 0);

    controller.removeStructuralListener(onStructural);
    controller.removeAnimationListener(onTick);
  });

  testWidgets(
    "M17b an exit in flight at a month change is retired with the sync and "
    "paints nothing in the next grid",
    (tester) async {
      const latency = Duration(seconds: 1);
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[
          taskAt("G", april(22), 10, 11),
          ...hourlyTasks(may(20), 8, 8),
        ],
        latency: latency,
      );
      expect(monthBoardFinder(), findsOneWidget);
      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      await tester.pump(latency);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Previous month"));
      await tester.pumpAndSettle();

      final g = chipFinder("item-1", april(20));
      await tester.tap(g);
      await tester.pumpAndSettle();
      await tester.tap(formButton("Delete"));
      await tester.pumpAndSettle();
      await tester.tap(formButton("Delete").last);
      await tester.pump(latency);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final exiting = tester.getSize(g).height;
      expect(exiting, greaterThan(0.0));
      expect(exiting, lessThan(lane));

      // May's grid holds May 20 in the week row G's exit held, on G's
      // column.
      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      expect(g, findsNothing);
      expect(tester.getSize(dayFinder(may(20))).height, near(strip + 8 * lane));
      final controller = monthViewport(tester).controller;
      var ticks = 0;
      void onTick() {
        ticks++;
      }

      controller.addAnimationListener(onTick);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.getSize(dayFinder(may(20))).height,
          near(strip + 8 * lane),
        );
      }
      expect(ticks, 0);
      controller.removeAnimationListener(onTick);
      await tester.pumpAndSettle();
    },
    skip: true,
  );

  testWidgets(
    "M17c an exit in flight at a weekday change is retired with the sync and "
    "paints nothing",
    (tester) async {
      const latency = Duration(seconds: 1);
      await pumpMonth(
        tester,
        seed: hourlyTasks(april(21), 8, 8),
        latency: latency,
      );
      expect(monthBoardFinder(), findsOneWidget);
      final first = chipFinder("item-1", april(20));
      await tester.tap(first);
      await tester.pumpAndSettle();
      await tester.tap(formButton("Delete"));
      await tester.pumpAndSettle();
      await tester.tap(formButton("Delete").last);
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tester.pump(latency);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final exiting = tester.getSize(first).height;
      expect(exiting, greaterThan(0.0));
      expect(exiting, lessThan(lane));

      await tester.tap(find.byKey(weekendsSwitchKey));
      await tester.pump();
      expect(first, findsNothing);
      expect(
        tester.getSize(dayFinder(april(21))).height,
        near(strip + 7 * lane),
      );
      final controller = monthViewport(tester).controller;
      var ticks = 0;
      void onTick() {
        ticks++;
      }

      controller.addAnimationListener(onTick);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.getSize(dayFinder(april(21))).height,
          near(strip + 7 * lane),
        );
      }
      expect(ticks, 0);
      controller.removeAnimationListener(onTick);
      await closeSettings(tester);
    },
    skip: true,
  );

  testWidgets(
    "M17d an enter in flight at a month change is settled with the sync",
    (tester) async {
      const latency = Duration(seconds: 1);
      await pumpMonth(
        tester,
        seed: hourlyTasks(april(28), 8, 8),
        latency: latency,
      );
      expect(monthBoardFinder(), findsOneWidget);
      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      await tester.pump(latency);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Previous month"));
      await tester.pumpAndSettle();
      await tapEmptyPart(tester, april(21));
      await dismissPicker(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(pilledDays(tester), <DateTime>[april(28)]);

      await tester.tap(find.byTooltip("Add"));
      await tester.pumpAndSettle();
      await pickTask(tester);
      await chooseOption(tester, "Start", "16:00");
      await chooseOption(tester, "End", "17:00");
      await tester.enterText(fieldFinder("Title"), "Late");
      await tester.tap(saveFinder());
      await tester.pump(latency);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final created = chipFinder("item-9", april(27));
      final entering = tester.getSize(created).height;
      expect(entering, greaterThan(0.0));
      expect(entering, lessThan(lane));

      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      expect(tester.getSize(created).height, near(lane));
      expect(
        tester.getSize(dayFinder(april(28))).height,
        near(strip + 9 * lane),
      );
      final controller = monthViewport(tester).controller;
      var ticks = 0;
      void onTick() {
        ticks++;
      }

      controller.addAnimationListener(onTick);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.getSize(dayFinder(april(28))).height,
          near(strip + 9 * lane),
        );
      }
      expect(ticks, 0);
      controller.removeAnimationListener(onTick);
      await tester.pumpAndSettle();
    },
    skip: true,
  );

  testWidgets(
    "M17e a write whose sync lays out in the frame after a month change "
    "animates",
    (tester) async {
      const latency = Duration(seconds: 1);
      await pumpMonth(
        tester,
        seed: <Map<String, Object?>>[taskAt("T", april(28), 10, 11)],
        latency: latency,
      );
      expect(monthBoardFinder(), findsOneWidget);
      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      await tester.pump(latency);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Previous month"));
      await tester.pumpAndSettle();

      final t = chipFinder("item-1", april(27));
      await tester.tap(t);
      await tester.pumpAndSettle();
      await tester.tap(formButton("Delete"));
      await tester.pumpAndSettle();
      // The delete goes out at this tap and is answered [latency] later.
      await tester.tap(formButton("Delete").last);
      await tester.pump(latency - const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: t, matching: find.byType(Opacity)),
            )
            .opacity,
        0.5,
      );

      // May's grid holds T's week as its first row.
      await tester.tap(find.byTooltip("Next month"));
      await tester.pump();
      // A pump elapses its duration, which delivers the answer, before it
      // runs its frame.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(oneFrame);
      await tester.pump(oneFrame);
      final leaving = tester.getSize(t).height;
      expect(leaving, greaterThan(0.0));
      expect(leaving, lessThan(lane));
      await tester.pumpAndSettle();
    },
    skip: true,
  );

  testWidgets("M19 a tap on a day's empty part gives the board the keys", (
    tester,
  ) async {
    await pumpMonth(tester);
    await tapEmptyPart(tester, april(22));
    await dismissPicker(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(pilledDays(tester), <DateTime>[april(23)]);
  });

  testWidgets(
    "M19b Tab gives the board the keys, which move from the selected day",
    (tester) async {
      await pumpMonth(tester);
      var presses = 0;
      while (!insideMonthBoard(FocusManager.instance.primaryFocus?.context) &&
          presses < 20) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        presses++;
      }
      expect(
        insideMonthBoard(FocusManager.instance.primaryFocus?.context),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(pilledDays(tester), <DateTime>[april(22)]);
      expect(find.text("April 2026"), findsOneWidget);
    },
  );

  testWidgets("M20a after a month change by a chevron the selected day shows", (
    tester,
  ) async {
    await pumpMonth(
      tester,
      seed: <Map<String, Object?>>[
        ...hourlyTasks(april(23), 9, 8),
        ...hourlyTasks(may(6), 9, 8),
        ...hourlyTasks(may(13), 9, 8),
        ...hourlyTasks(may(20), 9, 8),
      ],
    );
    await tapEmptyPart(tester, april(30));
    await dismissPicker(tester);
    final vertical = monthViewport(tester).verticalPosition!;
    expect(vertical.maxScrollExtent, greaterThan(0.0));

    await tester.tap(find.byTooltip("Next month"));
    await tester.pump();
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);
    expect(
      monthViewport(tester).verticalPosition!.maxScrollExtent,
      greaterThan(0.0),
    );
    expect(whollyInsideBoard(tester, may(30)), isTrue);
  });

  testWidgets("M20b after a month change by a key the selected day shows", (
    tester,
  ) async {
    await pumpMonth(
      tester,
      seed: <Map<String, Object?>>[
        ...hourlyTasks(april(6), 9, 8),
        ...hourlyTasks(april(13), 9, 8),
        ...hourlyTasks(april(20), 9, 8),
      ],
    );
    await tester.tap(find.byTooltip("Next month"));
    await tester.pump();
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    await tapEmptyPart(tester, may(1));
    await dismissPicker(tester);
    expect(monthViewport(tester).verticalPosition!.pixels, 0.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(monthViewport(tester).verticalPosition!.pixels, greaterThan(0.0));
    expect(find.text("April 2026"), findsOneWidget);
    expect(pilledDays(tester), <DateTime>[april(30)]);
    expect(whollyInsideBoard(tester, april(30)), isTrue);
  });

  testWidgets("M21 a confirmed create grows its chip in", (tester) async {
    await pumpMonth(tester);
    await tapEmptyPart(tester, april(22));
    await pickTask(tester);
    await tester.enterText(fieldFinder("Title"), "New");
    await tester.tap(saveFinder());
    await tester.pump(harnessLatency);
    await tester.pump(oneFrame);
    await tester.pump(oneFrame);
    final chip = chipFinder("item-1", april(20));
    final growing = tester.getSize(chip).height;
    expect(growing, greaterThan(0.0));
    expect(growing, lessThan(lane));
    await tester.pumpAndSettle();
    expect(tester.getSize(chip).height, near(lane));
  });

  testWidgets("M22 a form's keyboard leaves Month's weeks as they are", (
    tester,
  ) async {
    await pumpMonth(tester);
    final board = tester.getRect(monthBoardFinder());
    await tapEmptyPart(tester, april(22));
    await pickTask(tester);
    final controller = monthViewport(tester).controller;
    var structural = 0;
    void onStructural(Set<String>? keys) {
      structural++;
    }

    controller.addStructuralListener(onStructural);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300.0);
    await tester.pump();
    expect(structural, 0);
    expect(tester.getRect(monthBoardFinder()), board);
    // Sanity: the form's dialog moves above the keyboard once its inset
    // padding has animated; its surface is the Material it builds.
    await tester.pumpAndSettle();
    expect(structural, 0);
    expect(tester.getRect(monthBoardFinder()), board);
    expect(
      tester
          .getRect(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .bottom,
      lessThanOrEqualTo(844.0 - 300.0),
    );
    controller.removeStructuralListener(onStructural);
  });
}
