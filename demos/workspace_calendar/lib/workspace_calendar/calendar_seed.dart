/// The items the demo's mock API starts with, laid out around the day the
/// calendar opens on.
library;

import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_schema.dart';

/// [minute] minutes after [day]'s midnight.
DateTime _at(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, 0, minute);
}

/// A task kept from the original demo: [day] counts whole days from today,
/// [start] and [end] are minutes after midnight, and [status] is a Task
/// status value.
typedef _KeptTask = ({
  int day,
  int start,
  int end,
  String title,
  String status,
});

/// Today carries two tasks, and today + 6 enough to scroll the list. Only
/// the offsets -5, -2, 0, 1, 3 and 6 can fall in today's week, which is
/// what leaves [defaultCalendarSeed] a day of that week for "Day off".
const List<_KeptTask> _keptTasks = <_KeptTask>[
  (
    day: -35,
    start: 11 * 60,
    end: 12 * 60,
    title: "Kickoff: mobile app",
    status: "done",
  ),
  (
    day: -9,
    start: 14 * 60,
    end: 15 * 60,
    title: "Quarterly review",
    status: "done",
  ),
  (
    day: -5,
    start: 9 * 60,
    end: 12 * 60,
    title: "Workshop: journey mapping",
    status: "done",
  ),
  (
    day: -2,
    start: 15 * 60,
    end: 16 * 60,
    title: "Stakeholder check-in",
    status: "done",
  ),
  (
    day: 0,
    start: 10 * 60,
    end: 13 * 60,
    title: "Design new UX flow for Michael",
    status: "inProgress",
  ),
  (
    day: 0,
    start: 14 * 60,
    end: 15 * 60,
    title: "Brainstorm with the team",
    status: "done",
  ),
  (
    day: 1,
    start: 9 * 60 + 30,
    end: 10 * 60,
    title: "Daily standup",
    status: "toDo",
  ),
  (
    day: 1,
    start: 11 * 60,
    end: 12 * 60,
    title: "Review onboarding copy",
    status: "toDo",
  ),
  (
    day: 3,
    start: 13 * 60,
    end: 14 * 60 + 30,
    title: "Interview: product designer",
    status: "toDo",
  ),
  (
    day: 6,
    start: 8 * 60 + 30,
    end: 9 * 60,
    title: "Plan the sprint goals",
    status: "toDo",
  ),
  (
    day: 6,
    start: 9 * 60,
    end: 10 * 60,
    title: "Sprint planning",
    status: "toDo",
  ),
  (
    day: 6,
    start: 10 * 60 + 30,
    end: 11 * 60 + 30,
    title: "Accessibility audit",
    status: "inProgress",
  ),
  (
    day: 6,
    start: 11 * 60 + 30,
    end: 12 * 60,
    title: "Sync with marketing",
    status: "toDo",
  ),
  (
    day: 6,
    start: 13 * 60,
    end: 14 * 60,
    title: "Prototype review",
    status: "toDo",
  ),
  (
    day: 6,
    start: 14 * 60,
    end: 15 * 60 + 30,
    title: "Usability test session",
    status: "toDo",
  ),
  (
    day: 6,
    start: 16 * 60,
    end: 16 * 60 + 30,
    title: "Update the roadmap",
    status: "toDo",
  ),
  (day: 6, start: 17 * 60, end: 18 * 60, title: "Retro prep", status: "toDo"),
  (
    day: 7,
    start: 10 * 60,
    end: 11 * 60,
    title: "Client presentation",
    status: "toDo",
  ),
  (
    day: 12,
    start: 10 * 60,
    end: 10 * 60 + 30,
    title: "Vendor call",
    status: "toDo",
  ),
  (
    day: 18,
    start: 13 * 60,
    end: 17 * 60,
    title: "Team offsite",
    status: "toDo",
  ),
  (
    day: 30,
    start: 9 * 60,
    end: 10 * 60,
    title: "Release planning",
    status: "toDo",
  ),
  (
    day: 44,
    start: 15 * 60,
    end: 16 * 60,
    title: "Design system sync",
    status: "toDo",
  ),
];

/// An item of today's week: [weekday] counts from Monday, 0.
typedef _WeekEntry = ({
  int weekday,
  CalendarItemType type,
  String title,
  int start,
  int end,
  Map<String, Object?> fields,
});

/// On Monday to Wednesday these lie outside 09:00 to 17:00, the hours of
/// "Day off", which falls on one of those days. Each also misses the hours
/// of every kept task that can fall on its day, whichever day today is.
const List<_WeekEntry> _weekEntries = <_WeekEntry>[
  (
    weekday: 0,
    type: CalendarItemType.meeting,
    title: "Weekly planning",
    start: 8 * 60,
    end: 9 * 60,
    fields: <String, Object?>{
      "location": "Room 4B",
      "attendees": <String>["Ana", "Ben", "Chen"],
    },
  ),
  (
    weekday: 2,
    type: CalendarItemType.deadline,
    title: "Roadmap draft due",
    start: 17 * 60,
    end: 17 * 60 + 30,
    fields: <String, Object?>{"project": "Roadmap", "met": false},
  ),
  (
    weekday: 3,
    type: CalendarItemType.meeting,
    title: "Design critique",
    start: 16 * 60,
    end: 17 * 60,
    fields: <String, Object?>{
      "location": "Studio",
      "attendees": <String>["Lu", "Michael"],
      "videoLink": "https://meet.example.com/critique",
    },
  ),
  (
    weekday: 4,
    type: CalendarItemType.meeting,
    title: "Client demo",
    start: 16 * 60 + 30,
    end: 17 * 60 + 30,
    fields: <String, Object?>{
      "attendees": <String>["Ana", "Michael", "Sam"],
      "videoLink": "https://meet.example.com/demo",
    },
  ),
  (
    weekday: 4,
    type: CalendarItemType.deadline,
    title: "Release notes due",
    start: 16 * 60,
    end: 16 * 60 + 30,
    fields: <String, Object?>{"project": "Mobile app", "met": false},
  ),
];

/// The seed of the demo's mock API around [today], as item envelopes
/// without ids, in this order: the kept tasks at their offsets from
/// [today]; the meetings and deadlines of the Monday-to-Sunday week
/// holding [today]; "Day off", an Out of office from 09:00 to 17:00 on the
/// first day of that week, Monday first, that holds no kept task; and
/// "Conference trip", an all-day Out of office over the five days from
/// the first Monday at least 19 days after [today], from that Monday's
/// start to the start of the day five days on.
List<Map<String, Object?>> defaultCalendarSeed(DateTime today) {
  final day = CalendarDates.dateOnly(today);
  final weekStart = WeekdaySet.all.weekStartOf(day);
  final seed = <Map<String, Object?>>[];
  final keptDays = <DateTime>{};
  for (final task in _keptTasks) {
    final taskDay = CalendarDates.addDays(day, task.day);
    keptDays.add(taskDay);
    seed.add(
      _envelope(
        type: CalendarItemType.task,
        title: task.title,
        start: _at(taskDay, task.start),
        end: _at(taskDay, task.end),
        fields: <String, Object?>{"status": task.status},
      ),
    );
  }
  for (final entry in _weekEntries) {
    seed.add(
      _envelope(
        type: entry.type,
        title: entry.title,
        start: _at(
          CalendarDates.addDays(weekStart, entry.weekday),
          entry.start,
        ),
        end: _at(CalendarDates.addDays(weekStart, entry.weekday), entry.end),
        fields: entry.fields,
      ),
    );
  }
  DateTime? dayOff;
  for (var weekday = 0; weekday < 7 && dayOff == null; weekday++) {
    final candidate = CalendarDates.addDays(weekStart, weekday);
    if (!keptDays.contains(candidate)) {
      dayOff = candidate;
    }
  }
  if (dayOff == null) {
    throw StateError("Every day of the week of $weekStart holds a kept task.");
  }
  seed.add(
    _envelope(
      type: CalendarItemType.outOfOffice,
      title: "Day off",
      start: _at(dayOff, 9 * 60),
      end: _at(dayOff, 17 * 60),
      fields: const <String, Object?>{"reason": "vacation"},
    ),
  );
  final earliest = CalendarDates.addDays(day, 19);
  final tripStart = CalendarDates.addDays(
    earliest,
    (7 - CalendarDates.weekdayColumn(earliest)) % 7,
  );
  seed.add(
    _envelope(
      type: CalendarItemType.outOfOffice,
      title: "Conference trip",
      start: tripStart,
      end: CalendarDates.addDays(tripStart, 5),
      fields: const <String, Object?>{"reason": "travel"},
    ),
  );
  return seed;
}

Map<String, Object?> _envelope({
  required CalendarItemType type,
  required String title,
  required DateTime start,
  required DateTime end,
  required Map<String, Object?> fields,
}) {
  return <String, Object?>{
    "type": type.id,
    "title": title,
    "start": isoDateTime(start),
    "end": isoDateTime(end),
    "fields": <String, Object?>{
      for (final entry in fields.entries)
        entry.key: entry.value is List
            ? List<Object?>.of(entry.value! as List)
            : entry.value,
    },
  };
}
