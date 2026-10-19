/// The calendar's English labels: lengths, clock times, day titles, counts
/// and the names of months and weekdays.
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
}
