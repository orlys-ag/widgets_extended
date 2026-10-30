/// The calendar's text: what [DefaultCalendarLocalizations] writes for each
/// name, time, date, count, sentence and label, and how
/// [CalendarLocalizations.of] finds the localizations.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';

const DefaultCalendarLocalizations english = DefaultCalendarLocalizations();

/// English, but for the months, which it names "M1" to "M12", so a lookup
/// shows which localizations it found.
final class _Numbered extends DefaultCalendarLocalizations {
  const _Numbered();

  @override
  String monthName(int month) {
    return "M$month";
  }
}

class _NumberedDelegate extends LocalizationsDelegate<CalendarLocalizations> {
  const _NumberedDelegate();

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<CalendarLocalizations> load(Locale locale) {
    return SynchronousFuture<CalendarLocalizations>(const _Numbered());
  }

  @override
  bool shouldReload(_NumberedDelegate old) {
    return false;
  }
}

/// [child] under a [Localizations] of English that loads [delegate].
Widget localized(
  LocalizationsDelegate<CalendarLocalizations> delegate,
  Widget child,
) {
  return Localizations(
    locale: const Locale("en"),
    delegates: <LocalizationsDelegate<Object?>>[
      DefaultWidgetsLocalizations.delegate,
      delegate,
    ],
    child: child,
  );
}

void main() {
  group("D3 duration", () {
    test("writes minutes, whole hours, and hours with minutes", () {
      expect(english.duration(45), "45m");
      expect(english.duration(60), "1h");
      expect(english.duration(90), "1h 30m");
    });
  });

  group("L1 the labels", () {
    test("formatTime writes hours and minutes on the 24-hour clock, 1440 as "
        "24:00", () {
      expect(english.formatTime(570, HourLabelFormat.twentyFourHour), "09:30");
      expect(english.formatTime(1440, HourLabelFormat.twentyFourHour), "24:00");
    });

    test("LB2 moreEntries and entryCount count in words", () {
      expect(english.moreEntries(1), "1 more item");
      expect(english.moreEntries(3), "3 more items");
      expect(english.entryCount(0), "No items");
      expect(english.entryCount(1), "1 item");
      expect(english.entryCount(2), "2 items");
    });

    test("dayTitle names today, tomorrow, yesterday and other weekdays, "
        "with the year of another year", () {
      final today = DateTime(2026, 4, 21);
      expect(english.dayTitle(DateTime(2026, 4, 21), today), "Today, April 21");
      expect(
        english.dayTitle(DateTime(2026, 4, 22), today),
        "Tomorrow, April 22",
      );
      expect(
        english.dayTitle(DateTime(2026, 4, 20), today),
        "Yesterday, April 20",
      );
      expect(
        english.dayTitle(DateTime(2026, 4, 27), today),
        "Monday, April 27",
      );
      expect(
        english.dayTitle(DateTime(2027, 1, 4), today),
        "Monday, January 4, 2027",
      );
    });

    test("names the months and the weekdays", () {
      expect(english.monthName(4), "April");
      expect(english.weekdayShortName(DateTime.monday), "Mo");
      expect(english.weekdayLetter(DateTime.sunday), "S");
    });
  });

  test("L2 the default builders' sentences and labels", () {
    expect(english.readFailed, "The entries could not be read.");
    expect(english.retry, "Retry");
    expect(english.startsAt("07:30"), "Starts at 07:30");
    expect(english.endsAt("19:30"), "Ends at 19:30");
    expect(
      english.formatTimeRange(540, 600, HourLabelFormat.twentyFourHour),
      "09:00-10:00",
    );
  });

  test("LB1 entryTimes writes a range's clock times, 24:00 for an end at the "
      "next day's start, and All day from a day start to one", () {
    expect(
      english.entryTimes(
        DateTime(2026, 4, 21, 9, 10),
        DateTime(2026, 4, 21, 9, 50),
        HourLabelFormat.twentyFourHour,
      ),
      "09:10-09:50",
    );
    expect(
      english.entryTimes(
        DateTime(2026, 4, 20, 22),
        DateTime(2026, 4, 21, 2),
        HourLabelFormat.twentyFourHour,
      ),
      "22:00-02:00",
    );
    expect(
      english.entryTimes(
        DateTime(2026, 4, 20, 22),
        DateTime(2026, 4, 21),
        HourLabelFormat.twentyFourHour,
      ),
      "22:00-24:00",
    );
    expect(
      english.entryTimes(
        DateTime(2026, 4, 20),
        DateTime(2026, 4, 21),
        HourLabelFormat.twentyFourHour,
      ),
      "All day",
    );
    expect(
      english.entryTimes(
        DateTime(2026, 4, 20),
        DateTime(2026, 4, 23),
        HourLabelFormat.twentyFourHour,
      ),
      "All day",
    );
    expect(english.allDay, "All day");
  });

  test("HF1 entryTimes, landing and entryLabel write their times in the "
      "format they take", () {
    const twelve = HourLabelFormat.twelveHour;
    final today = DateTime(2026, 4, 15);
    expect(
      english.entryTimes(
        DateTime(2026, 4, 21, 9, 10),
        DateTime(2026, 4, 21, 9, 50),
        twelve,
      ),
      "9:10 AM-9:50 AM",
    );
    expect(
      english.landing(
        DateTime(2026, 4, 15, 14),
        DateTime(2026, 4, 15, 15),
        today,
        twelve,
      ),
      "Today, April 15, 2 PM-3 PM",
    );
    expect(
      english.landing(
        DateTime(2026, 4, 20, 22),
        DateTime(2026, 4, 21, 2),
        today,
        twelve,
      ),
      "Monday, April 20, 10 PM to Tuesday, April 21, 2 AM",
    );
    expect(
      english.entryLabel(
        title: "Gym",
        kind: null,
        start: DateTime(2026, 4, 20, 9, 10),
        end: DateTime(2026, 4, 20, 9, 50),
        format: twelve,
        pending: false,
      ),
      "Gym, Monday, April 20, 9:10 AM to 9:50 AM",
    );
  });

  group("C7 formatTime", () {
    test("names a minute as hours and minutes on the 24-hour clock", () {
      const format = HourLabelFormat.twentyFourHour;
      expect(english.formatTime(0, format), "00:00");
      expect(english.formatTime(13 * 60, format), "13:00");
      expect(english.formatTime(8 * 60 + 15, format), "08:15");
      expect(english.formatTime(24 * 60, format), "24:00");
    });

    test("names the hour and the half of the day on the 12-hour clock, with "
        "minutes where there are some", () {
      const format = HourLabelFormat.twelveHour;
      expect(english.formatTime(0, format), "12 AM");
      expect(english.formatTime(60, format), "1 AM");
      expect(english.formatTime(9 * 60, format), "9 AM");
      expect(english.formatTime(11 * 60, format), "11 AM");
      expect(english.formatTime(12 * 60, format), "12 PM");
      expect(english.formatTime(13 * 60, format), "1 PM");
      expect(english.formatTime(22 * 60, format), "10 PM");
      expect(english.formatTime(24 * 60, format), "12 AM");
      expect(english.formatTime(8 * 60 + 15, format), "8:15 AM");
      expect(english.formatTime(12 * 60 + 5, format), "12:05 PM");
    });
  });

  group("LC1 the English default", () {
    test("names months, and weekdays short, abbreviated and by "
        "letter", () {
      expect(english.monthName(1), "January");
      expect(english.weekdayAbbreviation(DateTime.wednesday), "Wed");
      expect(english.weekdayShortName(DateTime.thursday), "Th");
      expect(english.weekdayLetter(DateTime.saturday), "S");
    });

    test("names a day, a month and a short month", () {
      expect(english.dayLabel(DateTime(2026, 4, 21)), "Tuesday, April 21");
      expect(english.monthYear(DateTime(2026, 4)), "April 2026");
      expect(english.shortMonthYear(DateTime(2026, 4, 21)), "Apr 2026");
      expect(
        english.formatTimeRange(540, 600, HourLabelFormat.twelveHour),
        "9 AM-10 AM",
      );
    });

    test("counts entries left out, hidden, more, earlier and later", () {
      expect(
        english.moreEntriesBefore(3, "09:00"),
        "3 more items before 09:00",
      );
      expect(english.moreEntriesAfter(1, "18:00"), "1 more item after 18:00");
      expect(
        english.hiddenRow(DateTime(2026, 4, 20), 3, "09:00", above: true),
        "Monday, April 20, 3 more items before 09:00",
      );
      expect(
        english.hiddenRow(DateTime(2026, 4, 20), 1, "18:00", above: false),
        "Monday, April 20, 1 more item after 18:00",
      );
      expect(english.hiddenEntries(1), "1 item is on a day not shown");
      expect(english.hiddenEntries(2), "2 items are on days not shown");
      expect(english.moreCount(3), "+3 more");
      expect(english.earlierCount(2), "+2 earlier");
      expect(english.laterCount(4), "+4 later");
      expect(english.allDayMore(1), "1 more all-day entry");
      expect(english.allDayMore(2), "2 more all-day entries");
      expect(english.allDayLess, "Show fewer all-day entries");
      expect(english.showLess, "Less");
    });

    test("names where a drag lands, against today, and that it lands "
        "nowhere", () {
      final today = DateTime(2026, 4, 15);
      expect(english.noLanding, "No free time near here");
      expect(
        english.landing(
          DateTime(2026, 4, 15, 14),
          DateTime(2026, 4, 15, 15),
          today,
          HourLabelFormat.twentyFourHour,
        ),
        "Today, April 15, 14:00-15:00",
      );
      expect(
        english.landing(
          DateTime(2026, 4, 20, 22),
          DateTime(2026, 4, 21, 2),
          today,
          HourLabelFormat.twentyFourHour,
        ),
        "Monday, April 20, 22:00 to Tuesday, April 21, 02:00",
      );
      expect(
        english.landing(
          DateTime(2026, 4, 20),
          DateTime(2026, 4, 21),
          today,
          HourLabelFormat.twentyFourHour,
        ),
        "Monday, April 20, all day",
      );
      expect(
        english.landing(
          DateTime(2026, 4, 20),
          DateTime(2026, 4, 23),
          today,
          HourLabelFormat.twentyFourHour,
        ),
        "Monday, April 20 to Wednesday, April 22, all day",
      );
    });

    test("names a Month chip by its title, kind, days, times and pending "
        "write", () {
      expect(
        english.entryLabel(
          title: "Gym",
          kind: "Health",
          start: DateTime(2026, 4, 20),
          end: DateTime(2026, 4, 21),
          format: HourLabelFormat.twentyFourHour,
          pending: true,
        ),
        "Gym, Health, Monday, April 20, all day, pending",
      );
      expect(
        english.entryLabel(
          title: "Gym",
          kind: null,
          start: DateTime(2026, 4, 20),
          end: DateTime(2026, 4, 23),
          format: HourLabelFormat.twentyFourHour,
          pending: false,
        ),
        "Gym, Monday, April 20 to Wednesday, April 22, all day",
      );
      expect(
        english.entryLabel(
          title: "Gym",
          kind: null,
          start: DateTime(2026, 4, 20, 9, 10),
          end: DateTime(2026, 4, 20, 9, 50),
          format: HourLabelFormat.twentyFourHour,
          pending: false,
        ),
        "Gym, Monday, April 20, 09:10 to 09:50",
      );
      expect(
        english.entryLabel(
          title: "Gym",
          kind: null,
          start: DateTime(2026, 4, 20, 22),
          end: DateTime(2026, 4, 21),
          format: HourLabelFormat.twentyFourHour,
          pending: false,
        ),
        "Gym, Monday, April 20, 22:00 to 24:00",
      );
      expect(
        english.entryLabel(
          title: "Gym",
          kind: null,
          start: DateTime(2026, 4, 20, 22),
          end: DateTime(2026, 4, 21, 2),
          format: HourLabelFormat.twentyFourHour,
          pending: false,
        ),
        "Gym, Monday, April 20, 22:00 to Tuesday, April 21, 02:00",
      );
    });

    test("names a day's state, hints and badges, and Agenda's add", () {
      expect(english.today, "today");
      expect(english.openDayHint, "Opens the day");
      expect(english.createEntryHint, "create an item");
      expect(
        english.dayWithBadges(DateTime(2026, 4, 21), const <String?>[]),
        "Tuesday, April 21",
      );
      expect(
        english.dayWithBadges(DateTime(2026, 4, 21), const <String?>[null]),
        "Tuesday, April 21, has items",
      );
      expect(
        english.dayWithBadges(DateTime(2026, 4, 21), const <String?>[
          "Work",
          null,
        ]),
        "Tuesday, April 21, has Work, other items",
      );
      expect(english.addEntryAt("09:00"), "Add an item at 09:00");
    });

    test("names the header's views, chevrons, title and menu, and the "
        "card's pull tab", () {
      expect(english.agendaView, "Agenda");
      expect(english.dayView, "Day");
      expect(english.weekView, "Week");
      expect(english.monthView, "Month");
      expect(english.previousDayTooltip, "Previous day");
      expect(english.previousWeekTooltip, "Previous week");
      expect(english.previousMonthTooltip, "Previous month");
      expect(english.previousYearTooltip, "Previous year");
      expect(english.nextDayTooltip, "Next day");
      expect(english.nextWeekTooltip, "Next week");
      expect(english.nextMonthTooltip, "Next month");
      expect(english.nextYearTooltip, "Next year");
      expect(english.pickMonthTooltip, "Pick a month");
      expect(english.closeMonthsTooltip, "Close the months");
      expect(english.viewMenuTooltip, "Calendar view");
      expect(english.showMonthLabel, "Show the month");
      expect(english.showWeekLabel, "Show the week");
    });
  });

  group("LC2 the lookup", () {
    testWidgets("finds the English default with no Localizations above, and "
        "the localizations a Localizations above loaded, rebuilding a "
        "reader when they change", (tester) async {
      final read = <String>[];
      final reader = Builder(
        builder: (context) {
          read.add(CalendarLocalizations.of(context).monthName(4));
          return const SizedBox.shrink();
        },
      );
      await tester.pumpWidget(reader);
      expect(read, <String>["April"]);
      await tester.pumpWidget(
        localized(DefaultCalendarLocalizations.delegate, reader),
      );
      expect(read.last, "April");
      final count = read.length;
      await tester.pumpWidget(localized(const _NumberedDelegate(), reader));
      expect(read.length, greaterThan(count));
      expect(read.last, "M4");
    });

    test("DefaultCalendarLocalizations.delegate takes English alone and loads "
        "the English default at once", () {
      const delegate = DefaultCalendarLocalizations.delegate;
      expect(delegate.isSupported(const Locale("en")), isTrue);
      expect(delegate.isSupported(const Locale("en", "GB")), isTrue);
      expect(delegate.isSupported(const Locale("fr")), isFalse);
      final loaded = delegate.load(const Locale("en"));
      expect(loaded, isA<SynchronousFuture<CalendarLocalizations>>());
      CalendarLocalizations? value;
      loaded.then((localizations) {
        value = localizations;
      });
      expect(value, isA<DefaultCalendarLocalizations>());
    });
  });
}
