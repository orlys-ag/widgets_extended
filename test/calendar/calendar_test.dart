/// The names the module barrel shows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

void main() {
  test("B1 the barrel shows the module's public names", () {
    // Compile-time only: a name the barrel stops showing stops this file
    // compiling.
    <Object>[
      DayHours,
      WeekdaySet,
      dayNumber,
      dateOfDayNumber,
      CalendarEntry,
      CalendarEntryTime,
      CalendarDataSource,
      CalendarStore,
      CachingCalendarStore,
      MemoryCalendarStore,
      CalendarShownEntry,
      CalendarLoadStatus,
      CalendarWriteFailure,
      CalendarWriteFailed,
      CalendarEntryChanged,
      CalendarStoreException,
      CalendarHoursException,
      CalendarEntryOverlapException,
      CalendarWritePendingException,
      CalendarTheme,
      CalendarThemeData,
      CalendarBlockBuilder,
      CalendarChipBuilder,
      CalendarCardBuilder,
      CalendarAddButtonBuilder,
      CalendarLoadingBuilder,
      CalendarFailureBuilder,
      CalendarBlockDetails,
      CalendarChipDetails,
      CalendarCardDetails,
      CalendarAddButtonDetails,
      CalendarLoadingState,
      CalendarFailureState,
      CalendarStateSite,
      calendarCardStripExtent,
      defaultCalendarBlockBuilder,
      defaultCalendarChipBuilder,
      defaultCalendarCardBuilder,
      defaultCalendarAddButtonBuilder,
      defaultCalendarLoadingBuilder,
      defaultCalendarFailureBuilder,
      CalendarActivityIndicator,
    ];
  });
}
