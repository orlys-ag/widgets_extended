/// The calendar's data source over its API, and the sentences and field
/// errors the calendar shows for the store's and the API's refusals.
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
      day: day,
      startMinute: 600,
      endMinute: 660,
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
        "The start is 08:00 to 17:45, inside the calendar's hours.";
    const endError = "The end is 08:15 to 18:00, inside the calendar's hours.";
    const early = CalendarHoursException(
      hours: hours,
      startMinute: 450,
      endMinute: 510,
    );
    expect(writeFieldErrors(early), <String, String>{
      "startMinute": startError,
    });
    expect(writeFailureMessage(early), "The item is not valid: $startError");

    const late = CalendarHoursException(
      hours: hours,
      startMinute: 1050,
      endMinute: 1110,
    );
    expect(writeFieldErrors(late), <String, String>{"endMinute": endError});

    const past = CalendarHoursException(
      hours: hours,
      startMinute: 1080,
      endMinute: 1095,
    );
    expect(writeFieldErrors(past), <String, String>{
      "startMinute": startError,
      "endMinute": endError,
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
}
