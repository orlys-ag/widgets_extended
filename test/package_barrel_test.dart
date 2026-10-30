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
}
