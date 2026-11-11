/// A zone through the package barrel alone: a host names a `Location`,
/// zones a store with it and reads a time on its clock without importing
/// package:timezone, and the zone helpers list no zone it has not loaded.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  test("SB3 the package barrel shows Location, so a host zones a store and "
      "reads a time on its clock with no import of package:timezone, and "
      "loadedZones is empty while no zone data is loaded", () {
    // A zone of no offsets reads every instant at UTC's offset.
    final zone = Location("Test/Empty", const [], const [], const []);
    final store = MemoryCalendarStore<String>(zone: zone);
    addTearDown(store.dispose);
    expect(store.zone, same(zone));

    final instant = DateTime.utc(2026, 4, 21, 9, 30);
    final zoned = CalendarDates.inZone(instant, zone: zone);
    expect(zoned.isAtSameMomentAs(instant), isTrue);
    // A time of a zone other than UTC writes its offset, which neither a
    // plain local time nor a UTC one does.
    expect(zoned.toString(), "2026-04-21 09:30:00.000+0000");

    expect(CalendarDates.loadedZones(), isEmpty);

    final grep = Process.runSync("git", <String>[
      "grep",
      "-l",
      "package:timezone",
      "--",
      "lib",
    ]);
    expect(grep.exitCode, 0, reason: "${grep.stderr}");
    expect((grep.stdout as String).trim().split(RegExp(r"\r?\n")), <String>[
      "lib/scheduling/dates/calendar_dates.dart",
    ]);
  });
}
