/// The item form's times: its start and end dates and times, and its All
/// day switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/policy/history_lock.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';

final DateTime wednesday = DateTime(2026, 4, 22);

/// A Task titled "Write" from [start] to [end], stored as "item-1".
CalendarItem task(DateTime start, DateTime end) {
  return calendarItem(
    id: "item-1",
    type: CalendarItemType.task,
    title: "Write",
    start: start,
    end: end,
    fields: const <String, Object?>{"status": "toDo"},
  );
}

/// Pumps a host over [store] whose one button opens the form of the item
/// "item-1", and opens it.
Future<void> openForm(
  WidgetTester tester,
  CalendarStore<ItemPayload> store,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showEditForm(
                  context,
                  store: store,
                  id: "item-1",
                  lock: () {
                    return HistoryLock.none;
                  },
                );
              },
              child: const Text("Open"),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text("Open"));
  await tester.pumpAndSettle();
}

/// The form's time field labelled [label].
Finder timeField(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(DropdownButtonFormField<int>),
  );
}

void main() {
  testWidgets("IF1 the form shows Start date, Start time, End date, End "
      "time and All day, and All day hides the times and saves day starts", (
    tester,
  ) async {
    final writes = <CalendarItem?>[];
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9), DateTime(2026, 4, 23, 10)),
      ],
      onChanged: (old, entry) {
        writes.add(entry);
      },
    );
    await openForm(tester, store);
    for (final label in <String>[
      "Start date",
      "Start time",
      "End date",
      "End time",
      "All day",
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text("2026-04-22"), findsOneWidget);
    expect(find.text("2026-04-23"), findsOneWidget);

    await tester.tap(find.text("All day"));
    await tester.pumpAndSettle();
    expect(timeField("Start time"), findsNothing);
    expect(timeField("End time"), findsNothing);
    expect(find.text("Start date"), findsOneWidget);
    expect(find.text("End date"), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    final saved = writes.single!;
    expect(saved.start, wednesday);
    expect(saved.end, DateTime(2026, 4, 24));
    expect(saved.isAllDay, isTrue);
    store.dispose();
  });

  testWidgets("IF3 an entry at 09:10 shows 09:10, and a save that changes "
      "nothing writes 09:10", (tester) async {
    final writes = <CalendarItem?>[];
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[
        task(DateTime(2026, 4, 22, 9, 10), DateTime(2026, 4, 22, 9, 50)),
      ],
      onChanged: (old, entry) {
        writes.add(entry);
      },
    );
    await openForm(tester, store);
    expect(
      find.descendant(
        of: timeField("Start time"),
        matching: find.text("09:10"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: timeField("End time"), matching: find.text("09:50")),
      findsOneWidget,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single!.start, DateTime(2026, 4, 22, 9, 10));
    expect(writes.single!.end, DateTime(2026, 4, 22, 9, 50));
    store.dispose();
  });
}
