/// The zone panel where no zone data is loaded, a file of its own so that no
/// other test has loaded the database.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:widgets_extended/calendar/composition/calendar_zone_panel.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';

void main() {
  testWidgets(
    "ZP4 with no zone data or an empty list view 2 shows the empty state, "
    "and view 1 the device row and the pill",
    (tester) async {
      // Setup sanity: no zone data is loaded.
      expect(CalendarDates.loadedZones(), isEmpty);
      const strings = DefaultCalendarLocalizations();
      final controller = CalendarZoneController();
      addTearDown(controller.dispose);
      for (final zones in <List<Location>?>[null, const <Location>[]]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CalendarZonePanel(
                value: null,
                onChanged: (zone) {},
                controller: controller,
                zones: zones,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: "$zones");
        expect(find.byKey(zonePanelRowKey("")), findsOneWidget);
        expect(find.text(strings.deviceZoneName), findsOneWidget);
        expect(find.text(strings.addZonesLabel), findsOneWidget);
        await tester.tap(find.text(strings.addZonesLabel));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: "$zones");
        expect(find.text(strings.noZonesMessage), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byType(CustomScrollView), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
