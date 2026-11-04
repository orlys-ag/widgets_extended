/// The package barrel: what a host reaches through
/// `package:widgets_extended/widgets_extended.dart` alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("PB1 a host builds a calendar of its entries through the "
      "package barrel alone", (tester) async {
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        CalendarEntry<String>(
          id: "standup",
          start: DateTime(2026, 4, 21, 9),
          end: DateTime(2026, 4, 21, 10),
          title: "Standup",
          color: const Color(0xFF3366CC),
          payload: "team",
        ),
      ],
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: CalendarView<String>(
          store: store,
          clock: () {
            return DateTime(2026, 4, 21, 8);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Standup"), findsOneWidget);
  });

  testWidgets("PB2 a host reads a create's details, and takes them in "
      "onCreateRange, through the package barrel alone", (tester) async {
    final range = CalendarCreateRange(
      start: DateTime(2026, 4, 21, 10),
      end: DateTime(2026, 4, 21, 12, 15),
    );
    const rect = Rect.fromLTWH(10.0, 20.0, 30.0, 40.0);
    final details = CalendarCreateDetails(
      range: range,
      globalRect: rect,
      userChoseLength: true,
    );
    expect(details.range, range);
    expect(details.globalRect, rect);
    expect(details.userChoseLength, isTrue);

    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final reported = <CalendarCreateDetails>[];
    Future<void> onCreate(CalendarCreateDetails details) async {
      reported.add(details);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: CalendarView<String>(
          store: store,
          views: const <CalendarViewKind>[CalendarViewKind.month],
          clock: () {
            return DateTime(2026, 4, 21, 8);
          },
          editable: true,
          onCreateRange: onCreate,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text("23"));
    await tester.pumpAndSettle();
    // Month's long press reports the day's first slot, a length the
    // calendar chose.
    expect(reported, hasLength(1));
    expect(
      reported.single.range,
      CalendarCreateRange(
        start: DateTime(2026, 4, 23),
        end: DateTime(2026, 4, 23, 0, 15),
      ),
    );
    expect(reported.single.userChoseLength, isFalse);
  });
}
