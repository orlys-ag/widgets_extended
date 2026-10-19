/// The calendar's English strings: the names and labels of its dates, times
/// and counts, and the sentences and labels its default builders show.
library;

import 'calendar_dates.dart';

const List<String> monthNames = <String>[
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

/// The first three letters of each of [monthNames].
const List<String> monthShortNames = <String>[
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

/// Indexed by [weekdayColumn], so Monday first.
const List<String> weekdayNames = <String>[
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

/// Indexed by [weekdayColumn].
const List<String> weekdayShortNames = <String>[
  "Mo",
  "Tu",
  "We",
  "Th",
  "Fr",
  "Sa",
  "Su",
];

/// Indexed by [weekdayColumn].
const List<String> weekdayAbbreviations = <String>[
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
  "Sun",
];

/// Indexed by [weekdayColumn].
const List<String> weekdayLetters = <String>["M", "T", "W", "T", "F", "S", "S"];

/// "09:30" for [minute] minutes after midnight; 1440 reads "24:00".
String clockLabel(int minute) {
  final hours = (minute ~/ 60).toString().padLeft(2, "0");
  final minutes = (minute % 60).toString().padLeft(2, "0");
  return "$hours:$minutes";
}

/// "09:00-10:00": the [clockLabel]s of [start] and [end], minutes after
/// midnight.
String clockRangeLabel(int start, int end) {
  return "${clockLabel(start)}-${clockLabel(end)}";
}

/// The sentence the default failure builder shows for a read that failed.
const String readFailedLabel = "The entries could not be read.";

/// The label of the default failure builder's action, which reads the
/// failed days again.
const String retryLabel = "Retry";

/// "Starts at 07:30": the strip across the top of a card whose entry starts
/// at [time], before the hours its list shows.
String startsAtLabel(String time) {
  return "Starts at $time";
}

/// "Ends at 19:30": the strip across the bottom of a card whose entry ends
/// at [time], after the hours its list shows.
String endsAtLabel(String time) {
  return "Ends at $time";
}

/// "45m", "1h" or "1h 30m": [minutes] as the day list writes an item's
/// length.
String durationLabel(int minutes) {
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

/// "Today, April 21", "Monday, April 27", or with the year appended when
/// [day] is not in [today]'s year.
String dayTitle(DateTime day, DateTime today) {
  var date = "${monthNames[day.month - 1]} ${day.day}";
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
    name = weekdayNames[weekdayColumn(day)];
  }
  return "$name, $date";
}

/// "1 more item" or "N more items".
String moreItemsLabel(int count) {
  return count == 1 ? "1 more item" : "$count more items";
}

/// "No items", "1 item" or "N items".
String itemCountLabel(int count) {
  if (count == 0) {
    return "No items";
  }
  if (count == 1) {
    return "1 item";
  }
  return "$count items";
}
