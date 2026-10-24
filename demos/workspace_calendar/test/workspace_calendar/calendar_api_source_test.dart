/// The calendar's data source over its API, the sentences and field errors
/// the calendar shows for the store's and the API's refusals, and the
/// sentences it shows for a failed read.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api_source.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

void main() {
  test("AS1 the source reads and writes items through the API", () async {
    final api = MockCalendarApi(latency: Duration.zero);
    final source = CalendarApiSource(api);
    final day = DateTime(2026, 4, 21);
    final draft = calendarItem(
      type: CalendarItemType.task,
      title: "Write",
      start: DateTime(2026, 4, 21, 10),
      end: DateTime(2026, 4, 21, 11),
      fields: const <String, Object?>{"status": "toDo"},
    );

    final created = await source.create(draft);
    expect(created.id, "item-1");
    expect(created.title, "Write");
    expect(created.fields["priority"], "medium");
    expect(created.color, harborTypeStyleOf(CalendarItemType.task).edge);
    expect(await source.read(day, day), <CalendarItem>[created]);

    final renamed = await source.replace(created.copyWith(title: "Rewrite"));
    expect(renamed.id, "item-1");
    expect(renamed.title, "Rewrite");

    await source.delete("item-1");
    expect(await source.read(day, day), isEmpty);

    api.failurePolicy = (request) {
      return "Offline.";
    };
    await expectLater(
      source.read(day, day),
      throwsA(
        isA<CalendarFailureException>().having(
          (error) => error.message,
          "message",
          "Offline.",
        ),
      ),
    );
  });

  test("AS2 an hours refusal reads as the API's validation words it", () {
    const hours = DayHours(480, 1080);
    const startError =
        "The start is from 08:00 to before 18:00, inside the calendar's "
        "hours.";
    const endError =
        "The end is from after 08:00 to 18:00, inside the calendar's hours.";
    final early = CalendarHoursException(
      hours: hours,
      start: DateTime(2026, 4, 21, 7, 30),
      end: DateTime(2026, 4, 21, 8, 30),
    );
    expect(writeFieldErrors(early), <String, String>{"start": startError});
    expect(writeFailureMessage(early), "The item is not valid: $startError");

    final late = CalendarHoursException(
      hours: hours,
      start: DateTime(2026, 4, 21, 17, 30),
      end: DateTime(2026, 4, 21, 18, 30),
    );
    expect(writeFieldErrors(late), <String, String>{"end": endError});

    final past = CalendarHoursException(
      hours: hours,
      start: DateTime(2026, 4, 21, 18),
      end: DateTime(2026, 4, 21, 18, 15),
    );
    expect(writeFieldErrors(past), <String, String>{
      "start": startError,
      "end": endError,
    });
  });

  test("AS3 the store's other refusals and the API's errors read as their "
      "sentences", () {
    expect(
      writeFailureMessage(const CalendarWritePendingException("item-1")),
      "This item has a change in progress.",
    );
    expect(
      writeFailureMessage(
        const CalendarEntryOverlapException(<String>["item-2"]),
      ),
      "The item overlaps another item.",
    );
    expect(
      writeFailureMessage(const CalendarFailureException("Offline.")),
      "Offline.",
    );
    expect(writeFailureMessage(StateError("x")), "Bad state: x");

    const invalid = CalendarValidationException(<String, String>{
      "title": "Enter a title.",
    });
    expect(writeFieldErrors(invalid), invalid.fieldErrors);
    expect(
      writeFieldErrors(const CalendarWritePendingException("item-1")),
      isNull,
    );
    expect(
      writeFieldErrors(const CalendarEntryOverlapException(<String>["x"])),
      isNull,
    );
    expect(
      writeFieldErrors(const CalendarFailureException("Offline.")),
      isNull,
    );
    expect(writeFieldErrors(StateError("x")), isNull);
  });

  test("AS4 a failed read reads as the API's sentence, the error itself, or "
      "the unread day's sentence where there is no error", () {
    expect(
      readFailureMessage(const CalendarFailureException("Offline.")),
      "Offline.",
    );
    expect(readFailureMessage(StateError("x")), "Bad state: x");
    expect(readFailureMessage(null), "This day could not be read.");
    expect(unreadDayMessage, "This day could not be read.");
  });
}
