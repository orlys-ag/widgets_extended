/// The calendar's text: [CalendarLocalizations], its English default
/// [DefaultCalendarLocalizations], and [HourLabelFormat].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../dates/calendar_dates.dart';

/// How the calendar names a time of day ([CalendarLocalizations.formatTime]).
enum HourLabelFormat {
  /// The 24-hour clock: "13:00" in English.
  twentyFourHour,

  /// The 12-hour clock: "1 PM" in English.
  twelveHour,
}

/// Every text the calendar shows or a screen reader hears: the names of the
/// months and weekdays, the times and dates, and the views', the header's
/// and the default builders' labels, sentences and hints.
///
/// [CalendarLocalizations.of] reads the instance the nearest [Localizations]
/// loaded, and [DefaultCalendarLocalizations] where it loaded none. To
/// translate the calendar, a host extends this class, or
/// [DefaultCalendarLocalizations] to change some of its words, in a class
/// it declares `final` or `base`, and adds a [LocalizationsDelegate] of it
/// to its app's localization delegates.
///
/// Each member returns a whole label, sentence or hint, so a translation
/// orders its words and forms its plurals as its language needs. A member
/// that takes a `time` takes it as [formatTime] wrote it. A weekday is a
/// [DateTime.weekday], [DateTime.monday] 1 to [DateTime.sunday] 7, and a
/// month a [DateTime.month], 1 to 12. A minute is a minute after midnight,
/// 0 to 1440, where 1440 is the midnight that ends the day.
abstract base class CalendarLocalizations {
  /// Lets a subclass have a const constructor.
  const CalendarLocalizations();

  /// The localizations of the nearest [Localizations] that loaded them, and
  /// [DefaultCalendarLocalizations] where none did. Makes [context] depend
  /// on that [Localizations], so it rebuilds when they change.
  static CalendarLocalizations of(BuildContext context) {
    return Localizations.of<CalendarLocalizations>(
          context,
          CalendarLocalizations,
        ) ??
        const DefaultCalendarLocalizations();
  }

  /// The name of [month], as Month's picker shows it.
  String monthName(int month);

  /// The abbreviation of [weekday], as the calendar card's weekday row and
  /// its week strip's days show it.
  String weekdayAbbreviation(int weekday);

  /// The short name of [weekday], as Week's day headers show it.
  String weekdayShortName(int weekday);

  /// The letter of [weekday], as Month's weekday row shows it.
  String weekdayLetter(int weekday);

  /// [day] named by its weekday, month and day, as a screen reader hears
  /// a day.
  String dayLabel(DateTime day);

  /// [day] as Agenda's day headers and the landing label name it against
  /// [today]: today, tomorrow and yesterday by those words, any other day
  /// by its weekday, with its month and day, and its year where it is not
  /// [today]'s.
  String dayTitle(DateTime day, DateTime today);

  /// The month of [month] and its year, as a screen reader hears a month
  /// of Month's picker.
  String monthYear(DateTime month);

  /// The short name of the month of [month] and its year, as the header's
  /// title shows it.
  String shortMonthYear(DateTime month);

  /// [minute] in [format].
  String formatTime(int minute, HourLabelFormat format);

  /// The times from [start] to [end], minutes after midnight, in [format].
  String formatTimeRange(int start, int end, HourLabelFormat format);

  /// The times of an entry from [start] to [end], as the default block and
  /// chip builders show them: [allDay] for a range from a day's start to a
  /// day's start, and otherwise the times of day of [start] and [end] in
  /// [format], where an end at the start of the day after [start]'s is
  /// the midnight that ends that day.
  String entryTimes(DateTime start, DateTime end, HourLabelFormat format);

  /// The times of an all-day entry.
  String get allDay;

  /// [minutes] as Agenda writes an entry's length.
  String duration(int minutes);

  /// [count] entries more than are shown.
  String moreEntries(int count);

  /// [count] entries before [time], which the hours a view shows leave out.
  String moreEntriesBefore(int count, String time);

  /// [count] entries after [time], which the hours a view shows leave out.
  String moreEntriesAfter(int count, String time);

  /// [count] entries on a day, as Agenda's day headers count them.
  String entryCount(int count);

  /// What a screen reader hears for a count of [count] of [day]'s entries
  /// before [time], or after it where [above] is false: the timed grid's
  /// rows and Agenda's banners outside the hours.
  String hiddenRow(DateTime day, int count, String time, {required bool above});

  /// What a screen reader hears for the timed grid's pill counting [count]
  /// entries on days it has no column for.
  String hiddenEntries(int count);

  /// The visible count of [count] entries more than fit: the timed grid's
  /// rows outside the hours, and Month's days.
  String moreCount(int count);

  /// The visible count of [count] entries a Month day leaves out before
  /// its hours.
  String earlierCount(int count);

  /// The visible count of [count] entries a Month day leaves out after its
  /// hours.
  String laterCount(int count);

  /// What a screen reader hears for the pill counting [count] all-day
  /// entries the collapsed all-day strip hides on a day.
  String allDayMore(int count);

  /// What a screen reader hears for the pill that collapses the expanded
  /// all-day strip.
  String get allDayLess;

  /// The text of the pill that collapses the expanded all-day strip.
  String get showLess;

  /// The landing label while a move has nowhere to land.
  String get noLanding;

  /// The landing label for a drag that would give an entry the times
  /// [start] to [end]: its days as [dayTitle] names them against [today],
  /// and its times in [format], or for an all-day range that it is all
  /// day.
  String landing(
    DateTime start,
    DateTime end,
    DateTime today,
    HourLabelFormat format,
  );

  /// What a screen reader hears for a Month chip: the entry's [title], its
  /// [kind] where it has one, its days and its times from [start] to [end]
  /// in [format], and whether it is [pending].
  String entryLabel({
    required String title,
    required String? kind,
    required DateTime start,
    required DateTime end,
    required HourLabelFormat format,
    required bool pending,
  });

  /// What a screen reader hears for the day that is today, after its
  /// [dayLabel].
  String get today;

  /// The hint of a Month day's tap, which opens the day.
  String get openDayHint;

  /// The hint of a Month day's long press, which creates an entry.
  String get createEntryHint;

  /// What a screen reader hears for a day of the calendar card: its
  /// [dayLabel], and the kinds of entry its dots mark, each a host's label,
  /// or null for the dot of entries of no kind.
  String dayWithBadges(DateTime day, List<String?> kinds);

  /// What a screen reader hears for Agenda's gap that adds an entry at
  /// [time].
  String addEntryAt(String time);

  /// The sentence of the default failure builder.
  String get readFailed;

  /// The label of the default failure builder's action, which reads the
  /// failed days again.
  String get retry;

  /// The strip across the top of an Agenda card whose entry starts at
  /// [time], before the hours its list shows.
  String startsAt(String time);

  /// The strip across the bottom of an Agenda card whose entry ends at
  /// [time], after the hours its list shows.
  String endsAt(String time);

  /// The header view menu's name of Agenda.
  String get agendaView;

  /// The header view menu's name of Day.
  String get dayView;

  /// The header view menu's name of Week.
  String get weekView;

  /// The header view menu's name of Month.
  String get monthView;

  /// The tooltip of the header's chevron to the previous day.
  String get previousDayTooltip;

  /// The tooltip of the header's chevron to the previous week.
  String get previousWeekTooltip;

  /// The tooltip of the header's chevron to the previous month.
  String get previousMonthTooltip;

  /// The tooltip of the header's chevron to the previous year.
  String get previousYearTooltip;

  /// The tooltip of the header's chevron to the next day.
  String get nextDayTooltip;

  /// The tooltip of the header's chevron to the next week.
  String get nextWeekTooltip;

  /// The tooltip of the header's chevron to the next month.
  String get nextMonthTooltip;

  /// The tooltip of the header's chevron to the next year.
  String get nextYearTooltip;

  /// The tooltip of the header's title while it opens the month picker.
  String get pickMonthTooltip;

  /// The tooltip of the header's title while it closes the month picker.
  String get closeMonthsTooltip;

  /// The tooltip of the header's view menu.
  String get viewMenuTooltip;

  /// What a screen reader hears for the calendar card's pull tab while the
  /// card shows a week.
  String get showMonthLabel;

  /// What a screen reader hears for the calendar card's pull tab while the
  /// card shows a month.
  String get showWeekLabel;
}

/// [CalendarLocalizations] in US English.
base class DefaultCalendarLocalizations extends CalendarLocalizations {
  /// The US English text.
  const DefaultCalendarLocalizations();

  /// A [LocalizationsDelegate] that loads [DefaultCalendarLocalizations]
  /// for English. [CalendarLocalizations.of] finds the English default
  /// without it; listed among an app's localization delegates, it makes a
  /// debug build report an app locale that no delegate of
  /// [CalendarLocalizations] supports.
  static const LocalizationsDelegate<CalendarLocalizations> delegate =
      _DefaultCalendarLocalizationsDelegate();

  static const List<String> _monthNames = <String>[
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  static const List<String> _weekdayNames = <String>[
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ];

  static const List<String> _weekdayShortNames = <String>[
    "Mo",
    "Tu",
    "We",
    "Th",
    "Fr",
    "Sa",
    "Su",
  ];

  static const List<String> _weekdayLetters = <String>[
    "M",
    "T",
    "W",
    "T",
    "F",
    "S",
    "S",
  ];

  @override
  String monthName(int month) {
    return _monthNames[month - 1];
  }

  /// The first three letters of the weekday's name.
  @override
  String weekdayAbbreviation(int weekday) {
    return _weekdayNames[weekday - 1].substring(0, 3);
  }

  @override
  String weekdayShortName(int weekday) {
    return _weekdayShortNames[weekday - 1];
  }

  @override
  String weekdayLetter(int weekday) {
    return _weekdayLetters[weekday - 1];
  }

  /// "Tuesday, April 21".
  @override
  String dayLabel(DateTime day) {
    return "${_weekdayNames[day.weekday - 1]}, ${monthName(day.month)} "
        "${day.day}";
  }

  /// "Today, April 21", "Monday, April 27", or with the year appended
  /// where [day] is not in [today]'s year.
  @override
  String dayTitle(DateTime day, DateTime today) {
    var date = "${monthName(day.month)} ${day.day}";
    if (day.year != today.year) {
      date = "$date, ${day.year}";
    }
    final offset = daysBetween(today, day);
    final String name;
    if (offset == 0) {
      name = "Today";
    } else if (offset == 1) {
      name = "Tomorrow";
    } else if (offset == -1) {
      name = "Yesterday";
    } else {
      name = _weekdayNames[day.weekday - 1];
    }
    return "$name, $date";
  }

  /// "April 2026".
  @override
  String monthYear(DateTime month) {
    return "${monthName(month.month)} ${month.year}";
  }

  /// "Apr 2026": the first three letters of the month's name, and the
  /// year.
  @override
  String shortMonthYear(DateTime month) {
    return "${_monthNames[month.month - 1].substring(0, 3)} ${month.year}";
  }

  /// "09:30" on the 24-hour clock, where 1440 reads "24:00"; on the
  /// 12-hour clock the hour, its minutes where it has some, and the half
  /// of the day, as "1 PM" or "8:15 AM", where midnight, 1440 included,
  /// reads "12 AM" and noon "12 PM".
  @override
  String formatTime(int minute, HourLabelFormat format) {
    if (format == HourLabelFormat.twentyFourHour) {
      final hours = (minute ~/ 60).toString().padLeft(2, "0");
      final minutes = (minute % 60).toString().padLeft(2, "0");
      return "$hours:$minutes";
    }
    final ofDay = minute % minutesPerDay;
    final hour = ofDay ~/ 60;
    final half = hour < 12 ? "AM" : "PM";
    final shown = hour % 12 == 0 ? 12 : hour % 12;
    final minutes = ofDay % 60;
    if (minutes == 0) {
      return "$shown $half";
    }
    return "$shown:${minutes.toString().padLeft(2, "0")} $half";
  }

  /// "09:00-10:00".
  @override
  String formatTimeRange(int start, int end, HourLabelFormat format) {
    return "${formatTime(start, format)}-${formatTime(end, format)}";
  }

  /// "09:10-09:50", "9:10 AM-9:50 AM" on the 12-hour clock, or "All
  /// day".
  @override
  String entryTimes(DateTime start, DateTime end, HourLabelFormat format) {
    if (isDayStart(start) && isDayStart(end)) {
      return allDay;
    }
    final last = isDayStart(end) && dayNumber(end) == dayNumber(start) + 1
        ? minutesPerDay
        : minuteOfDay(end);
    return formatTimeRange(minuteOfDay(start), last, format);
  }

  @override
  String get allDay {
    return "All day";
  }

  /// "45m", "1h" or "1h 30m".
  @override
  String duration(int minutes) {
    assert(minutes >= 0);
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) {
      return "${rest}m";
    }
    if (rest == 0) {
      return "${hours}h";
    }
    return "${hours}h ${rest}m";
  }

  /// "1 more item" or "N more items".
  @override
  String moreEntries(int count) {
    return count == 1 ? "1 more item" : "$count more items";
  }

  /// "3 more items before 09:00".
  @override
  String moreEntriesBefore(int count, String time) {
    return "${moreEntries(count)} before $time";
  }

  /// "3 more items after 18:00".
  @override
  String moreEntriesAfter(int count, String time) {
    return "${moreEntries(count)} after $time";
  }

  /// "No items", "1 item" or "N items".
  @override
  String entryCount(int count) {
    if (count == 0) {
      return "No items";
    }
    if (count == 1) {
      return "1 item";
    }
    return "$count items";
  }

  /// "Monday, April 20, 3 more items before 09:00".
  @override
  String hiddenRow(
    DateTime day,
    int count,
    String time, {
    required bool above,
  }) {
    final more = above
        ? moreEntriesBefore(count, time)
        : moreEntriesAfter(count, time);
    return "${dayLabel(day)}, $more";
  }

  /// "1 item is on a day not shown" or "N items are on days not shown".
  @override
  String hiddenEntries(int count) {
    if (count == 1) {
      return "1 item is on a day not shown";
    }
    return "$count items are on days not shown";
  }

  /// "+3 more".
  @override
  String moreCount(int count) {
    return "+$count more";
  }

  /// "+3 earlier".
  @override
  String earlierCount(int count) {
    return "+$count earlier";
  }

  /// "+3 later".
  @override
  String laterCount(int count) {
    return "+$count later";
  }

  /// "1 more all-day entry" or "N more all-day entries".
  @override
  String allDayMore(int count) {
    return count == 1 ? "1 more all-day entry" : "$count more all-day entries";
  }

  @override
  String get allDayLess {
    return "Show fewer all-day entries";
  }

  @override
  String get showLess {
    return "Less";
  }

  @override
  String get noLanding {
    return "No free time near here";
  }

  /// "Today, April 21, 14:00-15:00"; for a range over more than one day
  /// "Monday, April 20, 22:00 to Tuesday, April 21, 02:00"; and for an
  /// all-day range "Monday, April 20, all day" or "Monday, April 20 to
  /// Wednesday, April 22, all day"; the times as [formatTime] writes them
  /// in [format].
  @override
  String landing(
    DateTime start,
    DateTime end,
    DateTime today,
    HourLabelFormat format,
  ) {
    final first = dayNumber(start);
    final last = lastDayNumberOf(start, end);
    final from = dayTitle(dateOfDayNumber(first), today);
    final to = dayTitle(dateOfDayNumber(last), today);
    if (isDayStart(start) && isDayStart(end)) {
      return first == last ? "$from, all day" : "$from to $to, all day";
    }
    if (first == last) {
      return "$from, ${entryTimes(start, end, format)}";
    }
    final startTime = formatTime(minuteOfDay(start), format);
    final endTime = formatTime(endMinuteOfDay(end), format);
    return "$from, $startTime to $to, $endTime";
  }

  /// "Title, Monday, April 20, all day", "Title, Kind, Monday, April 20 to
  /// Wednesday, April 22, all day", "Title, Monday, April 20, 09:10 to
  /// 09:50", or for a timed entry over days "Title, Monday, April 20,
  /// 22:00 to Tuesday, April 21, 02:00", each with ", pending" while it is
  /// [pending]; the times as [formatTime] writes them in [format].
  @override
  String entryLabel({
    required String title,
    required String? kind,
    required DateTime start,
    required DateTime end,
    required HourLabelFormat format,
    required bool pending,
  }) {
    final first = dateOfDayNumber(dayNumber(start));
    final last = dateOfDayNumber(lastDayNumberOf(start, end));
    final startTime = formatTime(minuteOfDay(start), format);
    final endTime = formatTime(endMinuteOfDay(end), format);
    final String when;
    if (isDayStart(start) && isDayStart(end)) {
      when = first == last
          ? "${dayLabel(first)}, all day"
          : "${dayLabel(first)} to ${dayLabel(last)}, all day";
    } else if (first == last) {
      when = "${dayLabel(first)}, $startTime to $endTime";
    } else {
      when = "${dayLabel(first)}, $startTime to ${dayLabel(last)}, $endTime";
    }
    final label = kind == null ? "$title, $when" : "$title, $kind, $when";
    return pending ? "$label, pending" : label;
  }

  @override
  String get today {
    return "today";
  }

  @override
  String get openDayHint {
    return "Opens the day";
  }

  @override
  String get createEntryHint {
    return "create an item";
  }

  /// "Tuesday, April 21", or with its kinds "Tuesday, April 21, has
  /// Meetings, other items", where the dot of entries of no kind reads
  /// "items" alone and "other items" beside kinds.
  @override
  String dayWithBadges(DateTime day, List<String?> kinds) {
    if (kinds.isEmpty) {
      return dayLabel(day);
    }
    final named = <String>[
      for (final kind in kinds)
        kind ?? (kinds.length == 1 ? "items" : "other items"),
    ];
    return "${dayLabel(day)}, has ${named.join(", ")}";
  }

  /// "Add an item at 09:00".
  @override
  String addEntryAt(String time) {
    return "Add an item at $time";
  }

  @override
  String get readFailed {
    return "The entries could not be read.";
  }

  @override
  String get retry {
    return "Retry";
  }

  /// "Starts at 07:30".
  @override
  String startsAt(String time) {
    return "Starts at $time";
  }

  /// "Ends at 19:30".
  @override
  String endsAt(String time) {
    return "Ends at $time";
  }

  @override
  String get agendaView {
    return "Agenda";
  }

  @override
  String get dayView {
    return "Day";
  }

  @override
  String get weekView {
    return "Week";
  }

  @override
  String get monthView {
    return "Month";
  }

  @override
  String get previousDayTooltip {
    return "Previous day";
  }

  @override
  String get previousWeekTooltip {
    return "Previous week";
  }

  @override
  String get previousMonthTooltip {
    return "Previous month";
  }

  @override
  String get previousYearTooltip {
    return "Previous year";
  }

  @override
  String get nextDayTooltip {
    return "Next day";
  }

  @override
  String get nextWeekTooltip {
    return "Next week";
  }

  @override
  String get nextMonthTooltip {
    return "Next month";
  }

  @override
  String get nextYearTooltip {
    return "Next year";
  }

  @override
  String get pickMonthTooltip {
    return "Pick a month";
  }

  @override
  String get closeMonthsTooltip {
    return "Close the months";
  }

  @override
  String get viewMenuTooltip {
    return "Calendar view";
  }

  @override
  String get showMonthLabel {
    return "Show the month";
  }

  @override
  String get showWeekLabel {
    return "Show the week";
  }
}

class _DefaultCalendarLocalizationsDelegate
    extends LocalizationsDelegate<CalendarLocalizations> {
  const _DefaultCalendarLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == "en";
  }

  @override
  Future<CalendarLocalizations> load(Locale locale) {
    return SynchronousFuture<CalendarLocalizations>(
      const DefaultCalendarLocalizations(),
    );
  }

  @override
  bool shouldReload(_DefaultCalendarLocalizationsDelegate old) {
    return false;
  }

  @override
  String toString() {
    return "DefaultCalendarLocalizations.delegate(en)";
  }
}
