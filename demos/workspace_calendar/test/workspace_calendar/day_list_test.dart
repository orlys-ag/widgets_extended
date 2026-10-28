/// The day list: deleting from a card's menu, the animations of the writes
/// the list can see, and a failed delete.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_bar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/item_builders.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_harness.dart';

const Duration oneFrame = Duration(milliseconds: 16);

Finder cardFinder(String id) {
  return find.byKey(entryCardKey(id));
}

/// Opens the calendar bar, sets the hours to [start] to [end] o'clock and
/// closes it.
Future<void> pickHours(WidgetTester tester, int start, int end) async {
  await openBar(tester);
  tester.widget<RangeSlider>(find.byKey(hoursSliderKey)).onChanged!(
    RangeValues(start.toDouble(), end.toDouble()),
  );
  await tester.pumpAndSettle();
  await closeBar(tester);
}

/// Opens the calendar bar, flips its AM/PM switch and closes it.
Future<void> flipHourFormat(WidgetTester tester) async {
  await openBar(tester);
  await tester.tap(find.byKey(hourLabelFormatKey));
  await tester.pumpAndSettle();
  await closeBar(tester);
}

Finder dayFinder(DateTime day) {
  return find.byKey(dayCellKey(day));
}

/// The day the calendar shows selected: the one selected [DayCell], in
/// the month grid or in the strip it folds into.
DateTime selectedDay(WidgetTester tester) {
  return tester.widgetList<DayCell>(find.byType(DayCell)).singleWhere((cell) {
    return cell.isSelected;
  }).day;
}

/// The top of [day]'s header less the list's top.
double headerTop(WidgetTester tester, DateTime day) {
  return tester.getRect(find.byKey(dayListHeaderKey(day))).top -
      tester.getRect(find.byType(DayList<ItemPayload>)).top;
}

/// Opens [id]'s card menu and picks [action], "Edit" or "Delete".
Future<void> cardAction(WidgetTester tester, String id, String action) async {
  await tester.tap(
    find.descendant(
      of: cardFinder(id),
      matching: find.bySemanticsLabel("Item actions"),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
}

/// How far the fade that brings [card] in or takes it out has gone: the
/// opacity of the nearest [FadeTransition] above it.
double fadingOf(WidgetTester tester, Finder card) {
  return tester
      .widget<FadeTransition>(
        find.ancestor(of: card, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;
}

/// The opacity the pending fade gives [finder]'s content: the first
/// [Opacity] under it, or 1.0 when there is none.
double fadeOf(WidgetTester tester, Finder finder) {
  final fades = tester.widgetList<Opacity>(
    find.descendant(of: finder, matching: find.byType(Opacity)),
  );
  return fades.isEmpty ? 1.0 : fades.first.opacity;
}

/// Picks [option] in the dropdown labelled [label], scrolling its menu by
/// [delta] until the option shows.
Future<void> chooseOption(
  WidgetTester tester,
  String label,
  String option, {
  double delta = 100.0,
}) async {
  await tester.tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) {
        return widget is DropdownButtonFormField;
      }),
    ),
  );
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

void main() {
  testWidgets("L1 delete from the card menu", (tester) async {
    const latency = Duration(seconds: 1);
    final api = await pumpCalendar(
      tester,
      editing: true,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    final requests = api.requests.length;

    await cardAction(tester, brainstormId, "Delete");
    expect(find.text("Delete item?"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();
    expect(cardFinder(brainstormId), findsOneWidget);
    expect(api.requests, hasLength(requests));

    await cardAction(tester, brainstormId, "Delete");
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    // Not settled: the pending card's indicator would keep it pumping
    // through the delete's latency.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fadeOf(tester, cardFinder(brainstormId)), 0.5);
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(cardFinder(brainstormId), findsNothing);
    await pickMode(tester, "Week");
    expect(blockFinder(brainstormId), findsNothing);
    await pickMode(tester, "Agenda");

    // The last item of a day takes its marker with it, and the change
    // rebuilds no other cell.
    await tester.tap(dayFinder(DateTime(2026, 4, 23)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DayCell>(dayFinder(DateTime(2026, 4, 23))).hasEntries,
      isTrue,
    );
    await cardAction(tester, designCritiqueId, "Delete");
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final neighbour = tester.widget(dayFinder(DateTime(2026, 4, 22)));
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DayCell>(dayFinder(DateTime(2026, 4, 23))).hasEntries,
      isFalse,
    );
    expect(
      identical(tester.widget(dayFinder(DateTime(2026, 4, 22))), neighbour),
      isTrue,
    );
  });

  for (final edit in <bool>[false, true]) {
    testWidgets(
      edit
          ? "L2b a confirmed edit that moves an item past the next one fades "
                "its card out where it was and in where it goes"
          : "L2 a confirmed delete animates the card out",
      (tester) async {
        final api = await pumpCalendar(tester, editing: true);
        await tester.tap(dayFinder(DateTime(2026, 4, 22)));
        await tester.pumpAndSettle();
        final standupTop = tester.getRect(cardFinder(standupId)).top;
        final reviewTop = tester.getRect(cardFinder(reviewId)).top;
        expect(reviewTop, greaterThan(standupTop));
        expect(
          find.byType(SyncedSliverTree<String, DayListRow>),
          findsOneWidget,
        );
        if (!edit) {
          // A confirmed delete animates the card out: one frame after the
          // answer it is still there, and the card below is on its way up.
          await cardAction(tester, standupId, "Delete");
          await tester.tap(find.widgetWithText(TextButton, "Delete"));
          await tester.pump();
          await tester.pump(api.latency);
          // The list shows no motion in the first frame after the answer;
          // the check is made in the frame after that.
          await tester.pump(oneFrame);
          await tester.pump(oneFrame);
          expect(cardFinder(standupId), findsOneWidget);
          final moving = tester.getRect(cardFinder(reviewId)).top;
          expect(moving, lessThan(reviewTop));
          expect(moving, greaterThan(standupTop));
        } else {
          // A confirmed edit that moves the item past the next one fades its
          // card out where it was and in where it goes, and the card it
          // passes moves up as the old place shrinks.
          await cardAction(tester, standupId, "Edit");
          await chooseOption(tester, "Start time", "12:00");
          await chooseOption(tester, "End time", "12:30");
          await tester.tap(find.byType(FilledButton));
          await tester.pump();
          await tester.pump(api.latency);
          await tester.pump(oneFrame);
          await tester.pump(oneFrame);
          final copies = cardFinder(standupId);
          expect(copies, findsNWidgets(2));
          final leaving = fadingOf(tester, copies.first);
          final coming = fadingOf(tester, copies.last);
          expect(leaving, inExclusiveRange(0.0, 1.0));
          expect(coming, inExclusiveRange(0.0, 1.0));
          final reviewMid = tester.getRect(cardFinder(reviewId)).top;
          expect(reviewMid, lessThan(reviewTop));
          await tester.pumpAndSettle();
          // The copy that left is gone: the card measures as one.
          final reviewEnd = tester.getRect(cardFinder(reviewId)).top;
          expect(
            tester.getRect(cardFinder(standupId)).top,
            greaterThan(reviewEnd),
          );
          expect(reviewMid, greaterThan(reviewEnd));
        }
        expect(
          find.byType(SyncedSliverTree<String, DayListRow>),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets("L3 a tap on a day scrolls the list, animating, until that "
      "day's header is at the list's top, and the days before it stay in "
      "the list", (tester) async {
    await pumpCalendar(tester);
    final list = tester.getRect(find.byType(DayList<ItemPayload>));
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(DayList<ItemPayload>),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final start = position.pixels;
    await tester.tap(dayFinder(DateTime(2026, 4, 24)));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(oneFrame);
    }
    final mid = position.pixels;
    await tester.pumpAndSettle();
    expect(mid, greaterThan(start));
    expect(mid, lessThan(position.pixels));
    expect(
      tester.getRect(find.byKey(dayListHeaderKey(DateTime(2026, 4, 24)))).top,
      list.top,
    );
    // Pulled back past the day the list opened on, the day before that
    // shows.
    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, 1400.0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(dayListHeaderKey(DateTime(2026, 4, 20))), findsOneWidget);
  });

  testWidgets("L4 a failed delete returns the card", (tester) async {
    final api = await pumpCalendar(tester, editing: true);
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.delete
          ? "Deleting failed."
          : null;
    };
    await cardAction(tester, brainstormId, "Delete");
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(cardFinder(brainstormId), findsOneWidget);
    expect(fadeOf(tester, cardFinder(brainstormId)), 1.0);
    expect(find.text("Deleting failed."), findsOneWidget);
  });

  testWidgets("L5 the list animates every family over 300 ms on "
      "fastOutSlowIn", (tester) async {
    await pumpCalendar(tester);

    final list = tester.widget<SyncedSliverTree<String, DayListRow>>(
      find.byType(SyncedSliverTree<String, DayListRow>),
    );
    for (final family in TreeAnimationFamily.values) {
      final spec = list.animationStyle.specFor(family);
      expect(
        spec.duration,
        const Duration(milliseconds: 300),
        reason: "$family",
      );
      expect(spec.curve, Curves.fastOutSlowIn, reason: "$family");
    }
  });

  testWidgets("L7 a card sits right of its start time over a chip of its "
      "length behind an hourglass, and shows no time itself, and a gap "
      "between the items is a dashed row at its start, all in the hour label "
      "format", (tester) async {
    await pumpCalendar(tester, editing: true);
    await tester.tap(dayFinder(DateTime(2026, 4, 22)));
    await tester.pumpAndSettle();
    final time = find.byKey(dayListTimeKey(standupId));
    final card = cardFinder(standupId);
    final chip = find.byKey(dayListDurationKey(standupId));
    final gap = find.byKey(dayListGapKey(DateTime(2026, 4, 22), 10 * 60));
    Finder inside(Finder of, String text) {
      return find.descendant(of: of, matching: find.text(text));
    }

    final start = tester.getRect(inside(time, "09:30"));
    // No end time, and no "to" before one.
    expect(inside(time, "to"), findsNothing);
    expect(inside(time, "10:00"), findsNothing);
    expect(tester.getRect(chip).top, greaterThan(start.bottom));
    expect(inside(chip, "30m"), findsOneWidget);
    final hourglass = find.descendant(
      of: chip,
      matching: find.byIcon(Icons.hourglass_empty),
    );
    expect(hourglass, findsOneWidget);
    expect(
      tester.getRect(hourglass).right,
      lessThanOrEqualTo(tester.getRect(inside(chip, "30m")).left),
    );
    expect(
      tester.getRect(time).right,
      lessThanOrEqualTo(tester.getRect(card).left),
    );
    expect(
      find.descendant(of: card, matching: find.textContaining(":")),
      findsNothing,
    );
    expect(inside(gap, "10:00"), findsOneWidget);
    // The dashed line, before the add button's paint.
    expect(
      tester.renderObject(
        find.descendant(of: gap, matching: find.byType(CustomPaint)).first,
      ),
      paints
        ..line(color: HarborColors.outline)
        ..line(color: HarborColors.outline),
    );

    await openBar(tester);
    await tester.tap(find.byKey(hourLabelFormatKey));
    await tester.pumpAndSettle();
    await closeBar(tester);
    expect(inside(time, "9:30 AM"), findsOneWidget);
    expect(inside(gap, "10 AM"), findsOneWidget);
  });

  testWidgets("L8 the header of the day at the list's top sticks there while "
      "its block scrolls under it, and a drag that brings the next day's "
      "header to the top selects that day", (tester) async {
    await pumpCalendar(tester);
    // Today's block is taller than this drag.
    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, -100.0),
    );
    await tester.pumpAndSettle();
    expect(headerTop(tester, today), 0.0);
    expect(selectedDay(tester), today);

    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, -400.0),
    );
    await tester.pumpAndSettle();
    expect(selectedDay(tester), DateTime(2026, 4, 22));
  });

  testWidgets("L9 a read that lands on the days above the list's top moves "
      "nothing the list shows", (tester) async {
    final api = MockCalendarApi.seeded(
      today,
      latency: const Duration(seconds: 1),
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 844.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(calendarApp(api: api, today: today));
    for (var i = 0; i < 4; i++) {
      await tester.pump(oneFrame);
    }
    final yesterday = DateTime(2026, 4, 20);
    bool yesterdayRead() {
      return tester.widget<DayCell>(dayFinder(yesterday)).hasEntries;
    }

    expect(headerTop(tester, today), 0.0);
    // Sanity: yesterday, above the top, is read with the answer, which
    // gives its block two cards.
    expect(headerTop(tester, yesterday), lessThan(0.0));
    expect(yesterdayRead(), isFalse);

    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(yesterdayRead(), isTrue);
    expect(headerTop(tester, today), 0.0);
  });

  testWidgets("L10 a day selected beyond the days the list holds brings the "
      "list to it, centred on it", (tester) async {
    await pumpCalendar(tester);
    // November 21 lies 214 days on, past the 180 the list held.
    for (var i = 0; i < 7; i++) {
      await selectNextMonth(tester);
      await tester.pumpAndSettle();
    }
    final november = DateTime(2026, 11, 21);
    expect(selectedDay(tester), november);
    expect(headerTop(tester, november), 0.0);
  });

  testWidgets("L11 the list adds days as its top nears the last day it "
      "holds", (tester) async {
    await pumpCalendar(tester);
    final past = addDays(today, dayListWindowDays + 10);
    for (var i = 0; i < 40 && selectedDay(tester).isBefore(past); i++) {
      await tester.fling(
        find.byType(DayList<ItemPayload>),
        const Offset(0.0, -2000.0),
        8000.0,
      );
      await tester.pumpAndSettle();
    }
    expect(selectedDay(tester).isBefore(past), isFalse);
  });

  testWidgets("L12 a list first built outside a frame, as runApp builds it, "
      "lands on the selected day once a frame lays it out", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 844.0);
    addTearDown(tester.view.reset);
    // As runApp's first attach does, the tree is built outside a frame,
    // and the first frame runs as the warm-up frame does: its start runs
    // the frame callbacks that build scheduled, before its draw lays
    // anything out.
    tester.binding.attachRootWidget(
      tester.binding.wrapWithDefaultView(calendarApp(api: api, today: today)),
    );
    tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
    tester.binding.handleBeginFrame(Duration.zero);
    tester.binding.handleDrawFrame();
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(headerTop(tester, today), 0.0);
  });

  testWidgets("L13 a gap's add button opens the create flow on the gap's "
      "first slot, and an empty day's on the hours' first slot", (
    tester,
  ) async {
    final day = DateTime(2026, 4, 22);
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("First", day, 9 * 60, 10 * 60),
        taskJson("Second", day, 10 * 60 + 30, 11 * 60 + 15),
      ],
      latency: harnessLatency,
    );
    await pumpCalendar(tester, editing: true, api: api);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    Finder shows(String label, String text) {
      return find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) {
            return widget is DropdownButtonFormField;
          }),
        ),
        matching: find.text(text),
      );
    }

    Future<void> addFrom(Finder row) async {
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.add)),
      );
      await tester.pumpAndSettle();
      expect(find.text("New item"), findsOneWidget);
      await tester.tap(find.text("Task").last);
      await tester.pumpAndSettle();
    }

    await addFrom(find.byKey(dayListGapKey(day, 10 * 60)));
    expectFormDays("2026-04-22", 1);
    expect(shows("Start time", "10:00"), findsOneWidget);
    expect(shows("End time", "10:15"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();

    // The gap after the last item, to the end of the day.
    await addFrom(find.byKey(dayListGapKey(day, 11 * 60 + 15)));
    expect(shows("Start time", "11:15"), findsOneWidget);
    expect(shows("End time", "11:30"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();

    // A day without items: one gap across the hours.
    await addFrom(find.byKey(dayListGapKey(DateTime(2026, 4, 23), 0)));
    expectFormDays("2026-04-23", 1);
    expect(shows("Start time", "00:00"), findsOneWidget);
    expect(shows("End time", "00:15"), findsOneWidget);
  });

  testWidgets("L14 the gap rows follow the calendar's hours as the "
      "settings change them", (tester) async {
    final day = DateTime(2026, 4, 22);
    await pumpCalendar(tester, editing: true);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    expect(find.byKey(dayListGapKey(day, 0)), findsOneWidget);
    expect(find.byKey(dayListGapKey(day, 8 * 60)), findsNothing);

    await openBar(tester);
    tester.widget<RangeSlider>(find.byKey(hoursSliderKey)).onChanged!(
      const RangeValues(8.0, 18.0),
    );
    await tester.pumpAndSettle();
    await closeBar(tester);
    expect(find.byKey(dayListGapKey(day, 0)), findsNothing);
    expect(find.byKey(dayListGapKey(day, 8 * 60)), findsOneWidget);
  });

  testWidgets("L15 out of edit mode the list has no dashed rows and the "
      "cards no menu, so a day without items shows its header alone, and "
      "edit mode turned on adds them, the cards keeping their height", (
    tester,
  ) async {
    final day = DateTime(2026, 4, 22);
    final empty = DateTime(2026, 4, 25);
    await pumpCalendar(tester);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    final card = cardFinder(standupId);
    final menu = find.descendant(
      of: card,
      matching: find.bySemanticsLabel("Item actions"),
    );
    final height = tester.getSize(card).height;
    expect(find.byKey(dayListGapKey(day, 10 * 60)), findsNothing);
    expect(menu, findsNothing);

    await tester.tap(dayFinder(empty));
    await tester.pumpAndSettle();
    // Setup sanity: the day shows.
    expect(find.byKey(dayListHeaderKey(empty)), findsOneWidget);
    expect(find.byKey(dayListGapKey(empty, 0)), findsNothing);

    await toggleEditMode(tester);
    expect(find.byKey(dayListGapKey(empty, 0)), findsOneWidget);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    expect(menu, findsOneWidget);
    expect(tester.getSize(card).height, height);
  });

  testWidgets("L16 the time column ends the start time, the chip and a gap "
      "row's label a gap short of the card and the dashed line", (
    tester,
  ) async {
    // Half-size text, so the test font's wide glyphs leave the times room
    // in their column to align by.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final day = DateTime(2026, 4, 22);
    await pumpCalendar(tester, editing: true);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    final time = find.byKey(dayListTimeKey(standupId));
    final card = tester.getRect(cardFinder(standupId));
    final end = card.left - dayListTimeGap;
    expect(
      tester
          .getRect(find.descendant(of: time, matching: find.text("09:30")))
          .right,
      moreOrLessEquals(end),
    );
    expect(
      tester.getRect(find.byKey(dayListDurationKey(standupId))).right,
      moreOrLessEquals(end),
    );

    final gap = find.byKey(dayListGapKey(day, 10 * 60));
    final line = tester.getRect(
      find.descendant(of: gap, matching: find.byType(CustomPaint)).first,
    );
    expect(
      tester
          .getRect(find.descendant(of: gap, matching: find.text("10:00")))
          .right,
      moreOrLessEquals(line.left - dayListTimeGap),
    );
  });

  testWidgets("L17 a day without items names itself and its No items in "
      "smaller, muted type, in a header as tall as a busy day's", (
    tester,
  ) async {
    final busy = DateTime(2026, 4, 22);
    final empty = DateTime(2026, 4, 25);
    await pumpCalendar(tester);

    /// The header of [day], and the styles of its title and its count.
    ({double height, TextStyle title, TextStyle count}) header(DateTime day) {
      final finder = find.byKey(dayListHeaderKey(day));
      final texts = find
          .descendant(of: finder, matching: find.byType(RichText))
          .evaluate()
          .map((element) {
            return (element.renderObject! as RenderParagraph).text.style!;
          })
          .toList();
      return (
        height: tester.getSize(finder).height,
        title: texts.first,
        count: texts.last,
      );
    }

    await tester.tap(dayFinder(busy));
    await tester.pumpAndSettle();
    final full = header(busy);
    expect(full.title.fontSize, 16.0);

    await tester.tap(dayFinder(empty));
    await tester.pumpAndSettle();
    final bare = header(empty);
    expect(bare.title.fontSize, 13.0);
    expect(bare.title.color, HarborColors.textMuted);
    expect(bare.count.fontSize, 12.0);
    expect(bare.count.color, HarborColors.textMuted);
    expect(bare.height, full.height);
  });

  testWidgets("L19 an item wholly outside the hours leaves the list for a "
      "soft yellow banner across the row's width, 16 px in from either "
      "side, that counts it, above "
      "the cards for those before the hours and below them for those "
      "after, in the hour format and heard with its day, while the header "
      "counts every item", (tester) async {
    final semantics = tester.ensureSemantics();
    final day = DateTime(2026, 4, 22);
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("Early", day, 6 * 60, 7 * 60),
        taskJson("Mid", day, 10 * 60, 11 * 60),
        taskJson("Late", day, 19 * 60, 20 * 60),
        taskJson("Later", day, 21 * 60, 22 * 60),
      ],
      latency: harnessLatency,
    );
    await pumpCalendar(tester, api: api);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    final above = find.byKey(dayListHiddenKey(day, above: true));
    final below = find.byKey(dayListHiddenKey(day, above: false));
    Finder inside(Finder banner, Finder finder) {
      return find.descendant(of: banner, matching: finder);
    }

    // Setup sanity: every item shows inside the whole day's hours.
    expect(cardFinder("item-1"), findsOneWidget);

    await openBar(tester);
    tester.widget<RangeSlider>(find.byKey(hoursSliderKey)).onChanged!(
      const RangeValues(8.0, 18.0),
    );
    await tester.pump();
    await tester.pump(oneFrame);
    // Leaving, Early shows its own start, with no strip.
    expect(
      find.descendant(
        of: find.byKey(dayListTimeKey("item-1")),
        matching: find.text("06:00"),
      ),
      findsOneWidget,
    );
    expect(find.byKey(itemCardStartsAtKey("item-1")), findsNothing);
    await tester.pumpAndSettle();
    await closeBar(tester);
    expect(cardFinder("item-1"), findsNothing);
    expect(cardFinder("item-3"), findsNothing);
    expect(cardFinder("item-4"), findsNothing);
    final mid = tester.getRect(cardFinder("item-2"));
    expect(
      inside(above, find.text("1 more item before 08:00")),
      findsOneWidget,
    );
    expect(
      inside(below, find.text("2 more items after 18:00")),
      findsOneWidget,
    );
    expect(inside(above, find.byIcon(Icons.keyboard_arrow_up)), findsOneWidget);
    expect(
      inside(below, find.byIcon(Icons.keyboard_arrow_down)),
      findsOneWidget,
    );
    final box = inside(above, find.byType(DecoratedBox)).first;
    final decoration =
        tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
    expect(decoration.color, HarborColors.notice);
    final list = tester.getRect(find.byType(DayList<ItemPayload>));
    expect(tester.getRect(box).left, list.left + dayListGutter);
    expect(tester.getRect(box).right, list.right - dayListGutter);
    expect(tester.getRect(above).bottom, lessThan(mid.top));
    expect(tester.getRect(below).top, greaterThan(mid.bottom));
    expect(
      find.descendant(
        of: find.byKey(dayListHeaderKey(day)),
        matching: find.text("4 items"),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel("Wednesday, April 22, 1 more item before 08:00"),
      findsOneWidget,
    );

    await flipHourFormat(tester);
    expect(inside(above, find.text("1 more item before 8 AM")), findsOneWidget);

    await pickHours(tester, 0, 24);
    expect(cardFinder("item-1"), findsOneWidget);
    expect(above, findsNothing);
    expect(below, findsNothing);
    semantics.dispose();
  });

  testWidgets("L20 in edit mode a day without items shows one gap row "
      "across the hours, named by their start in the hour format, and only "
      "its header says it has no items", (tester) async {
    final empty = DateTime(2026, 4, 25);
    await pumpCalendar(tester, editing: true);
    await tester.tap(dayFinder(empty));
    await tester.pumpAndSettle();
    Finder labelOf(int start, String label) {
      return find.descendant(
        of: find.byKey(dayListGapKey(empty, start)),
        matching: find.text(label),
      );
    }

    expect(labelOf(0, "00:00"), findsOneWidget);
    expect(labelOf(0, "No items"), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(dayListHeaderKey(empty)),
        matching: find.text("No items"),
      ),
      findsOneWidget,
    );

    await pickHours(tester, 8, 18);
    expect(labelOf(8 * 60, "08:00"), findsOneWidget);
    await flipHourFormat(tester);
    expect(labelOf(8 * 60, "8 AM"), findsOneWidget);
  });

  testWidgets("L21 a red line marks the clock's time over its day's rows, "
      "from the cards to the list's right edge: across a running item's "
      "card as far as the item has run, in the gap under the last row "
      "started by then otherwise, and above the first row before any, the "
      "time in a pill hugging it 8 px in from the list's left edge, the line "
      "starting at the pill's end, in the hour format; "
      "never outside the hours, nor on another day", (tester) async {
    final day = DateTime(2026, 4, 22);
    var now = DateTime(2026, 4, 22, 10, 15);
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("First", day, 10 * 60, 11 * 60),
        taskJson("Second", day, 13 * 60, 14 * 60),
        taskJson("Third", DateTime(2026, 4, 23), 9 * 60, 10 * 60),
      ],
      latency: harnessLatency,
    );
    await pumpCalendar(
      tester,
      api: api,
      pinsToday: false,
      clock: () {
        return now;
      },
    );
    final line = find.byKey(dayListNowKey);
    double lineY() {
      return tester.getRect(line).center.dy;
    }

    Rect card(String id) {
      return tester.getRect(cardFinder(id));
    }

    Future<void> setNow(int hour, int minute) async {
      now = DateTime(2026, 4, 22, hour, minute);
      await tester.pump(const Duration(minutes: 1));
    }

    // A quarter of the way through First.
    expect(line, findsOneWidget);
    expect(
      lineY(),
      moreOrLessEquals(card("item-1").top + card("item-1").height / 4.0),
    );
    expect(
      find.descendant(of: line, matching: find.text("10:15")),
      findsOneWidget,
    );
    final list = tester.getRect(find.byType(DayList<ItemPayload>));
    expect(tester.getRect(line).left, list.left);
    expect(tester.getRect(line).right, list.right);
    final label = find.descendant(of: line, matching: find.text("10:15"));
    final pill = tester.getRect(
      find.ancestor(of: label, matching: find.byType(DecoratedBox)),
    );
    expect(pill.left, list.left + 8.0);
    final text = tester.renderObject<RenderParagraph>(label);
    expect(
      pill.width,
      moreOrLessEquals(text.getMaxIntrinsicWidth(double.infinity) + 12.0),
    );
    expect(
      tester
          .getRect(
            find.descendant(of: line, matching: find.byType(CustomPaint)),
          )
          .left,
      pill.right,
    );

    await setNow(12, 0);
    expect(lineY(), moreOrLessEquals(card("item-1").bottom + 6.0));

    await setNow(9, 0);
    expect(lineY(), moreOrLessEquals(card("item-1").top - 6.0));

    // Second ends at 14:00, so the line passes under it.
    await setNow(14, 0);
    expect(lineY(), moreOrLessEquals(card("item-2").bottom + 6.0));
    await flipHourFormat(tester);
    expect(
      find.descendant(of: line, matching: find.text("2 PM")),
      findsOneWidget,
    );

    await pickHours(tester, 8, 18);
    await setNow(18, 1);
    expect(line, findsNothing);
    await setNow(7, 59);
    expect(line, findsNothing);
    await setNow(8, 0);
    expect(line, findsOneWidget);

    // The clock's next day: the line moves to that day's block alone.
    now = DateTime(2026, 4, 23, 8, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(line, findsOneWidget);
    expect(lineY(), moreOrLessEquals(card("item-3").top - 6.0));
  });

  testWidgets("L22 a card keeps 8 px left of its icon and right of its menu, "
      "2 px above its title row and 8 px under its summaries, the title in "
      "14 px type on a row as tall as its compact menu button, 40 px", (
    tester,
  ) async {
    await pumpCalendar(tester, editing: true);
    await tester.tap(dayFinder(DateTime(2026, 4, 22)));
    await tester.pumpAndSettle();
    final card = cardFinder(standupId);
    final title = find.descendant(
      of: card,
      matching: find.text("Daily standup"),
    );
    final padding = tester.widget<Padding>(
      find.descendant(of: card, matching: find.byType(Padding)).first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 8.0));
    expect(
      tester.renderObject<RenderParagraph>(title).text.style!.fontSize,
      14.0,
    );
    expect(
      tester
          .getSize(find.ancestor(of: title, matching: find.byType(Row)).first)
          .height,
      40.0,
    );
  });

  testWidgets("L23 a header's background spans the list's width, its title "
      "16 px in, and a row's time column starts and its card ends 16 px in "
      "from the list's sides", (tester) async {
    final day = DateTime(2026, 4, 22);
    await pumpCalendar(tester);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(DayList<ItemPayload>));
    final header = tester.getRect(find.byKey(dayListHeaderKey(day)));
    expect(header.left, list.left);
    expect(header.right, list.right);
    expect(
      tester.getRect(find.text("Tomorrow, April 22")).left,
      list.left + dayListGutter,
    );
    expect(
      tester.getRect(find.byKey(dayListTimeKey(standupId))).left,
      list.left + dayListGutter,
    );
    expect(
      tester.getRect(cardFinder(standupId)).right,
      list.right - dayListGutter,
    );
  });

  testWidgets("L24 an item reaching past the hours shows in its time column "
      "the later of its start and theirs and its whole length, and "
      "states its own start in a yellow strip across its card's top where "
      "it starts before them, and its end in one across the card's bottom "
      "where it ends after them, in the hour format", (tester) async {
    final day = DateTime(2026, 4, 22);
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("Early", day, 7 * 60 + 30, 9 * 60),
        taskJson("Late", day, 17 * 60, 19 * 60 + 30),
        taskJson("Long", DateTime(2026, 4, 23), 6 * 60, 20 * 60),
      ],
      latency: harnessLatency,
    );
    await pumpCalendar(tester, api: api);
    await tester.tap(dayFinder(day));
    await tester.pumpAndSettle();
    Finder time(String id, String text) {
      return find.descendant(
        of: find.byKey(dayListTimeKey(id)),
        matching: find.text(text),
      );
    }

    Finder length(String id, String text) {
      return find.descendant(
        of: find.byKey(dayListDurationKey(id)),
        matching: find.text(text),
      );
    }

    Finder onCard(String id, String text) {
      return find.descendant(of: cardFinder(id), matching: find.text(text));
    }

    // Setup sanity: inside the whole day's hours nothing is cut.
    expect(time("item-1", "07:30"), findsOneWidget);

    await pickHours(tester, 8, 18);
    expect(time("item-1", "08:00"), findsOneWidget);
    expect(length("item-1", "1h 30m"), findsOneWidget);
    expect(onCard("item-1", "Starts at 07:30"), findsOneWidget);
    expect(find.byKey(itemCardEndsAtKey("item-1")), findsNothing);
    expect(time("item-2", "17:00"), findsOneWidget);
    expect(length("item-2", "2h 30m"), findsOneWidget);
    expect(onCard("item-2", "Ends at 19:30"), findsOneWidget);
    expect(find.byKey(itemCardStartsAtKey("item-2")), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(dayListTimeKey("item-1")),
        matching: find.byIcon(Icons.keyboard_arrow_up),
      ),
      findsNothing,
    );

    // Long is cut at both ends.
    final card = tester.getRect(cardFinder("item-3"));
    const strip = ItemCard.stripHeight;
    expect(
      tester.getRect(find.byKey(itemCardStartsAtKey("item-3"))),
      rectMoreOrLessEquals(
        Rect.fromLTWH(card.left, card.top, card.width, strip),
      ),
    );
    expect(
      tester.getRect(find.byKey(itemCardEndsAtKey("item-3"))),
      rectMoreOrLessEquals(
        Rect.fromLTWH(card.left, card.bottom - strip, card.width, strip),
      ),
    );
    for (final key in <Key>[
      itemCardStartsAtKey("item-3"),
      itemCardEndsAtKey("item-3"),
    ]) {
      final box = tester.widget<DecoratedBox>(find.byKey(key));
      expect((box.decoration as BoxDecoration).color, HarborColors.notice);
    }

    await flipHourFormat(tester);
    expect(time("item-1", "8 AM"), findsOneWidget);
    expect(onCard("item-1", "Starts at 7:30 AM"), findsOneWidget);
    expect(onCard("item-2", "Ends at 7:30 PM"), findsOneWidget);
  });

  testWidgets("L25 across a card the hours cut, the red line marks the "
      "item's minutes inside them between the card's strips, and stays on "
      "the card at the hours' end while the item runs past it", (tester) async {
    final day = DateTime(2026, 4, 22);
    var now = DateTime(2026, 4, 22, 8, 30);
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("Early", day, 7 * 60, 9 * 60),
        taskJson("Late", day, 17 * 60, 19 * 60),
      ],
      latency: harnessLatency,
    );
    await pumpCalendar(
      tester,
      api: api,
      pinsToday: false,
      clock: () {
        return now;
      },
    );
    await pickHours(tester, 8, 18);
    final line = find.byKey(dayListNowKey);
    double lineY() {
      return tester.getRect(line).center.dy;
    }

    Future<void> setNow(int hour, int minute) async {
      now = DateTime(2026, 4, 22, hour, minute);
      await tester.pump(const Duration(minutes: 1));
    }

    const strip = ItemCard.stripHeight;
    // Early's hour inside the hours is 8:00 to 9:00, under its top strip.
    final early = tester.getRect(cardFinder("item-1"));
    expect(
      lineY(),
      moreOrLessEquals(early.top + strip + (early.height - strip) / 2.0),
    );

    // Late's is 17:00 to 18:00, over its bottom strip.
    await setNow(17, 30);
    final late = tester.getRect(cardFinder("item-2"));
    expect(lineY(), moreOrLessEquals(late.top + (late.height - strip) / 2.0));
    await setNow(18, 0);
    expect(lineY(), moreOrLessEquals(late.bottom - strip));
  });

  testWidgets("L26 a pending card's progress indicator stays 8 px down its "
      "title row under a strip stating its start", (tester) async {
    final item = itemFromJson(<String, Object?>{
      ...taskJson("Early", DateTime(2026, 4, 22), 7 * 60, 9 * 60),
      "id": "early",
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300.0,
            child: CalendarTheme(
              data: harborCalendarTheme,
              child: ItemCard(
                entry: ShownItem(item, pending: true),
                onEdit: null,
                onDelete: null,
                startsAt: "07:00",
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byType(CircularProgressIndicator)).top,
      tester.getRect(find.byKey(itemCardStartsAtKey("early"))).bottom + 8.0,
    );
  });

  testWidgets("L27 a card's strip keeps its height at twice the text size", (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final item = itemFromJson(<String, Object?>{
      ...taskJson("Early", DateTime(2026, 4, 22), 7 * 60, 9 * 60),
      "id": "early",
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300.0,
            child: CalendarTheme(
              data: harborCalendarTheme,
              child: ItemCard(
                entry: ShownItem(item, pending: false),
                onEdit: null,
                onDelete: null,
                startsAt: "07:00",
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(itemCardStartsAtKey("early"))).height,
      ItemCard.stripHeight,
    );
  });

  testWidgets("L28 a delete from the card menu the mock API fails keeps the "
      "card, under a snackbar naming the failure", (tester) async {
    const latency = Duration(seconds: 1);
    final api = await pumpCalendar(
      tester,
      editing: true,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.delete
          ? "Deleting failed."
          : null;
    };
    await cardAction(tester, brainstormId, "Delete");
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SnackBar, "Deleting failed."), findsOneWidget);
    expect(cardFinder(brainstormId), findsOneWidget);
  });
}
