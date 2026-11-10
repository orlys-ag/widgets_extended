/// The names the scheduling barrel shows: the same declarations through the
/// calendar's barrel and the package's, and every static helper on the
/// class that holds it.
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/calendar.dart' as calendar;
import 'package:widgets_extended/scheduling/scheduling.dart' as scheduling;
import 'package:widgets_extended/scheduling/scheduling.dart';
import 'package:widgets_extended/widgets_extended.dart' as widgets_extended;

void main() {
  test("SB1 the calendar barrel and the package barrel show each name the "
      "scheduling barrel shows as the same declaration", () {
    // Setup sanity: two different names read as two values.
    expect(scheduling.CalendarEntry, isNot(scheduling.CalendarStore));
    final names = <String, List<Object>>{
      "CalendarDates": <Object>[
        scheduling.CalendarDates,
        calendar.CalendarDates,
        widgets_extended.CalendarDates,
      ],
      "CalendarDayHours": <Object>[
        scheduling.CalendarDayHours,
        calendar.CalendarDayHours,
        widgets_extended.CalendarDayHours,
      ],
      "CalendarHourLabelFormat": <Object>[
        scheduling.CalendarHourLabelFormat,
        calendar.CalendarHourLabelFormat,
        widgets_extended.CalendarHourLabelFormat,
      ],
      "CalendarMonthGrid": <Object>[
        scheduling.CalendarMonthGrid,
        calendar.CalendarMonthGrid,
        widgets_extended.CalendarMonthGrid,
      ],
      "CalendarWeekdaySet": <Object>[
        scheduling.CalendarWeekdaySet,
        calendar.CalendarWeekdaySet,
        widgets_extended.CalendarWeekdaySet,
      ],
      "CalendarAllChanged": <Object>[
        scheduling.CalendarAllChanged,
        calendar.CalendarAllChanged,
        widgets_extended.CalendarAllChanged,
      ],
      "CalendarDataSource": <Object>[
        scheduling.CalendarDataSource,
        calendar.CalendarDataSource,
        widgets_extended.CalendarDataSource,
      ],
      "CalendarDaysChanged": <Object>[
        scheduling.CalendarDaysChanged,
        calendar.CalendarDaysChanged,
        widgets_extended.CalendarDaysChanged,
      ],
      "CalendarEntryPut": <Object>[
        scheduling.CalendarEntryPut,
        calendar.CalendarEntryPut,
        widgets_extended.CalendarEntryPut,
      ],
      "CalendarEntryRemoved": <Object>[
        scheduling.CalendarEntryRemoved,
        calendar.CalendarEntryRemoved,
        widgets_extended.CalendarEntryRemoved,
      ],
      "CalendarSourceChange": <Object>[
        scheduling.CalendarSourceChange,
        calendar.CalendarSourceChange,
        widgets_extended.CalendarSourceChange,
      ],
      "CalendarCreateRange": <Object>[
        scheduling.CalendarCreateRange,
        calendar.CalendarCreateRange,
        widgets_extended.CalendarCreateRange,
      ],
      "CalendarEntry": <Object>[
        scheduling.CalendarEntry,
        calendar.CalendarEntry,
        widgets_extended.CalendarEntry,
      ],
      "CalendarEditPolicy": <Object>[
        scheduling.CalendarEditPolicy,
        calendar.CalendarEditPolicy,
        widgets_extended.CalendarEditPolicy,
      ],
      "CalendarNow": <Object>[
        scheduling.CalendarNow,
        calendar.CalendarNow,
        widgets_extended.CalendarNow,
      ],
      "CalendarOverlapCandidate": <Object>[
        scheduling.CalendarOverlapCandidate,
        calendar.CalendarOverlapCandidate,
        widgets_extended.CalendarOverlapCandidate,
      ],
      "CalendarResizeEdges": <Object>[
        scheduling.CalendarResizeEdges,
        calendar.CalendarResizeEdges,
        widgets_extended.CalendarResizeEdges,
      ],
      "DayLimitPolicy": <Object>[
        scheduling.DayLimitPolicy,
        calendar.DayLimitPolicy,
        widgets_extended.DayLimitPolicy,
      ],
      "NoOverlapsPolicy": <Object>[
        scheduling.NoOverlapsPolicy,
        calendar.NoOverlapsPolicy,
        widgets_extended.NoOverlapsPolicy,
      ],
      "UnrestrictedEditPolicy": <Object>[
        scheduling.UnrestrictedEditPolicy,
        calendar.UnrestrictedEditPolicy,
        widgets_extended.UnrestrictedEditPolicy,
      ],
      "CalendarEarliestStart": <Object>[
        scheduling.CalendarEarliestStart,
        calendar.CalendarEarliestStart,
        widgets_extended.CalendarEarliestStart,
      ],
      "CalendarEditRules": <Object>[
        scheduling.CalendarEditRules,
        calendar.CalendarEditRules,
        widgets_extended.CalendarEditRules,
      ],
      "HistoryLockPolicy": <Object>[
        scheduling.HistoryLockPolicy,
        calendar.HistoryLockPolicy,
        widgets_extended.HistoryLockPolicy,
      ],
      "CachingCalendarStore": <Object>[
        scheduling.CachingCalendarStore,
        calendar.CachingCalendarStore,
        widgets_extended.CachingCalendarStore,
      ],
      "CalendarHoursException": <Object>[
        scheduling.CalendarHoursException,
        calendar.CalendarHoursException,
        widgets_extended.CalendarHoursException,
      ],
      "CalendarLoadStatus": <Object>[
        scheduling.CalendarLoadStatus,
        calendar.CalendarLoadStatus,
        widgets_extended.CalendarLoadStatus,
      ],
      "CalendarShownEntry": <Object>[
        scheduling.CalendarShownEntry,
        calendar.CalendarShownEntry,
        widgets_extended.CalendarShownEntry,
      ],
      "CalendarStore": <Object>[
        scheduling.CalendarStore,
        calendar.CalendarStore,
        widgets_extended.CalendarStore,
      ],
      "CalendarStoreException": <Object>[
        scheduling.CalendarStoreException,
        calendar.CalendarStoreException,
        widgets_extended.CalendarStoreException,
      ],
      "CalendarWritePendingException": <Object>[
        scheduling.CalendarWritePendingException,
        calendar.CalendarWritePendingException,
        widgets_extended.CalendarWritePendingException,
      ],
      "compareCalendarEntries": <Object>[
        scheduling.compareCalendarEntries,
        calendar.compareCalendarEntries,
        widgets_extended.compareCalendarEntries,
      ],
      "CalendarEntryChanged": <Object>[
        scheduling.CalendarEntryChanged,
        calendar.CalendarEntryChanged,
        widgets_extended.CalendarEntryChanged,
      ],
      "MemoryCalendarStore": <Object>[
        scheduling.MemoryCalendarStore,
        calendar.MemoryCalendarStore,
        widgets_extended.MemoryCalendarStore,
      ],
    };
    expect(names, hasLength(33));
    for (final MapEntry(key: name, value: values) in names.entries) {
      expect(values[1], values[0], reason: "calendar: $name");
      expect(values[2], values[0], reason: "package: $name");
    }
  });

  test("SB2 the scheduling barrel shows each CalendarDates static, the "
      "overlap rule's statics on NoOverlapsPolicy, and CalendarMonthGrid "
      "with its factories", () {
    // Compile-time only: a static that moves off its class, or a name the
    // barrel stops showing, stops this file compiling.
    <Object>[
      scheduling.CalendarDates.defaultSlotMinutes,
      scheduling.CalendarDates.slotMinuteChoices,
      scheduling.CalendarDates.minutesPerDay,
      scheduling.CalendarDates.dateOnly,
      scheduling.CalendarDates.addDays,
      scheduling.CalendarDates.addMonths,
      scheduling.CalendarDates.daysBetween,
      scheduling.CalendarDates.weekdayColumn,
      scheduling.CalendarDates.dayNumber,
      scheduling.CalendarDates.weekdayColumnOfDay,
      scheduling.CalendarDates.shownDayNear,
      scheduling.CalendarDates.nextShownDay,
      scheduling.CalendarDates.shownDaysOfWeek,
      scheduling.CalendarDates.dateOfDayNumber,
      scheduling.CalendarDates.isDayStart,
      scheduling.CalendarDates.minuteOfDay,
      scheduling.CalendarDates.endMinuteOfDay,
      scheduling.CalendarDates.wallMinuteOf,
      scheduling.CalendarDates.endWallMinuteOf,
      scheduling.CalendarDates.timeAtWallMinute,
      scheduling.CalendarDates.endAtWallMinute,
      scheduling.CalendarDates.rangeEndAtWallMinute,
      scheduling.CalendarDates.repeatedStretchOf,
      scheduling.CalendarDates.isLaterOccurrence,
      scheduling.CalendarDates.firstWallMinuteNotBefore,
      scheduling.CalendarDates.lastWallMinuteNotAfter,
      scheduling.CalendarDates.lastDayNumberOf,
      scheduling.CalendarDates.wallSpanOf,
      scheduling.CalendarDates.pieceOn,
      scheduling.CalendarDates.isoDate,
      scheduling.CalendarDates.isoTime,
      scheduling.NoOverlapsPolicy.entriesShareTime,
      scheduling.NoOverlapsPolicy.timesOverlap,
      scheduling.NoOverlapsPolicy.rangeSharesTime,
      scheduling.CalendarMonthGrid.new,
      scheduling.CalendarMonthGrid.of,
    ];
  });
  test("RS1 the README's zone sample runs and is verbatim", () async {
    // A checkout may hold either file with CRLF line ends.
    final readme = File(
      "README.md",
    ).readAsStringSync().replaceAll("\r\n", "\n");
    final own = File(
      "test/scheduling/scheduling_test.dart",
    ).readAsStringSync().replaceAll("\r\n", "\n");
    const startMark = "// README zone sample:";
    const endMark = "// End of the README zone sample.";
    final from = own.lastIndexOf(startMark) + startMark.length;
    final to = own.lastIndexOf(endMark);
    // The statements between the two marks are the README's sample, each
    // line less the indent of this test's body.
    final sample = own
        .substring(from, to)
        .split("\n")
        .map((line) {
          return line.startsWith("    ") ? line.substring(4) : line;
        })
        .join("\n")
        .trim();
    final at = readme.indexOf(sample);
    expect(at, isNot(-1), reason: "The README holds the sample verbatim.");
    final after = readme.substring(at + sample.length);
    expect(after, contains("tz.local"));
    expect(after, contains("latest_10y"));

    // README zone sample:
    tz.initializeTimeZones();
    final zone = tz.getLocation("America/Havana");
    final store = MemoryCalendarStore<String>(zone: zone);
    await store.create(
      CalendarEntry<String>(
        id: "standup",
        start: tz.TZDateTime(zone, 2026, 4, 21, 9),
        end: tz.TZDateTime(zone, 2026, 4, 21, 10),
        title: "Standup",
        color: const Color(0xFF3366CC),
        payload: "team",
      ),
    );
    // End of the README zone sample.

    addTearDown(store.dispose);
    final held = store.entriesOn(DateTime(2026, 4, 21)).single.entry;
    expect(held.start, isA<tz.TZDateTime>());
    expect((held.start as tz.TZDateTime).location, zone);
    expect(held.start.hour, 9);
  });
}
