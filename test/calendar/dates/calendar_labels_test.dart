/// The calendar's English labels: lengths, clock times, hour labels, day
/// titles, counts, the names of months and weekdays, and the sentences and
/// labels of the default builders.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';

void main() {
  group("D3 durationLabel", () {
    test("writes minutes, whole hours, and hours with minutes", () {
      expect(durationLabel(45), "45m");
      expect(durationLabel(60), "1h");
      expect(durationLabel(90), "1h 30m");
    });
  });

  group("L1 the labels", () {
    test("clockLabel writes hours and minutes, 1440 as 24:00", () {
      expect(clockLabel(570), "09:30");
      expect(clockLabel(1440), "24:00");
    });

    test("moreItemsLabel and itemCountLabel count in words", () {
      expect(moreItemsLabel(1), "1 more item");
      expect(moreItemsLabel(3), "3 more items");
      expect(itemCountLabel(0), "No items");
      expect(itemCountLabel(1), "1 item");
      expect(itemCountLabel(2), "2 items");
    });

    test("dayTitle names today, tomorrow, yesterday and other weekdays, "
        "with the year of another year", () {
      final today = DateTime(2026, 4, 21);
      expect(dayTitle(DateTime(2026, 4, 21), today), "Today, April 21");
      expect(dayTitle(DateTime(2026, 4, 22), today), "Tomorrow, April 22");
      expect(dayTitle(DateTime(2026, 4, 20), today), "Yesterday, April 20");
      expect(dayTitle(DateTime(2026, 4, 27), today), "Monday, April 27");
      expect(dayTitle(DateTime(2027, 1, 4), today), "Monday, January 4, 2027");
    });

    test("names the months and the weekdays from Monday", () {
      expect(monthNames[3], "April");
      expect(weekdayShortNames[0], "Mo");
      expect(weekdayLetters, hasLength(7));
    });
  });

  test("L2 the default builders' sentences and labels", () {
    expect(readFailedLabel, "The entries could not be read.");
    expect(retryLabel, "Retry");
    expect(startsAtLabel("07:30"), "Starts at 07:30");
    expect(endsAtLabel("19:30"), "Ends at 19:30");
    expect(clockRangeLabel(540, 600), "09:00-10:00");
  });

  group("C7 hourLabel", () {
    test("names a minute as clockLabel does in 24-hour", () {
      const format = HourLabelFormat.twentyFourHour;
      expect(hourLabel(0, format), "00:00");
      expect(hourLabel(13 * 60, format), "13:00");
      expect(hourLabel(8 * 60 + 15, format), "08:15");
      expect(hourLabel(24 * 60, format), "24:00");
    });

    test("names the hour and the half of the day in AM/PM, with minutes "
        "where there are some", () {
      const format = HourLabelFormat.twelveHour;
      expect(hourLabel(0, format), "12 AM");
      expect(hourLabel(60, format), "1 AM");
      expect(hourLabel(9 * 60, format), "9 AM");
      expect(hourLabel(11 * 60, format), "11 AM");
      expect(hourLabel(12 * 60, format), "12 PM");
      expect(hourLabel(13 * 60, format), "1 PM");
      expect(hourLabel(22 * 60, format), "10 PM");
      expect(hourLabel(24 * 60, format), "12 AM");
      expect(hourLabel(8 * 60 + 15, format), "8:15 AM");
      expect(hourLabel(12 * 60 + 5, format), "12:05 PM");
    });
  });
}
