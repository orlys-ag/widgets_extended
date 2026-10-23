/// The calendar's data source over its API, the sentences and field errors
/// the calendar shows for a write the store or the API refused, and the
/// sentences it shows for a failed read.
library;

import 'package:widgets_extended/calendar/calendar.dart';

import 'calendar_api.dart';
import 'calendar_item.dart';
import 'calendar_settings.dart';

/// The store's reads and writes through [api]: each entry goes out as its
/// envelope and comes back read from the envelope the API answers.
class CalendarApiSource implements CalendarDataSource<ItemPayload> {
  const CalendarApiSource(this.api);

  final CalendarApi api;

  @override
  Future<List<CalendarItem>> read(DateTime first, DateTime last) async {
    final items = await api.list(first, last);
    return <CalendarItem>[for (final json in items) itemFromJson(json)];
  }

  @override
  Future<CalendarItem> create(CalendarItem draft) async {
    return itemFromJson(await api.create(draft.toJson()));
  }

  @override
  Future<CalendarItem> replace(CalendarItem entry) async {
    return itemFromJson(await api.update(entry.id!, entry.toJson()));
  }

  @override
  Future<void> delete(String id) {
    return api.delete(id);
  }
}

/// What a write on an item with a write in flight reports.
const String lockedMessage = "This item has a change in progress.";

/// The sentence the calendar shows for [error], a write's failure: the
/// field errors of an hours refusal, as the API's validation words them,
/// the API's overlap sentence for an overlap refusal, [lockedMessage] for
/// a write in flight, an API error's own message, and the error itself
/// otherwise.
String writeFailureMessage(Object error) {
  if (error is CalendarHoursException) {
    return CalendarValidationException(
      hoursErrorsOf(error.start, error.end, error.hours),
    ).message;
  }
  if (error is CalendarEntryOverlapException) {
    return CalendarOverlapException(error.conflictingIds).message;
  }
  if (error is CalendarWritePendingException) {
    return lockedMessage;
  }
  if (error is CalendarApiException) {
    return error.message;
  }
  return "$error";
}

/// What a day row says for a day whose read failed while the range the
/// calendar shows is ready, which leaves it no error.
const String unreadDayMessage = "This day could not be read.";

/// The sentence the calendar shows for a failed read of [error], as the
/// store holds it: an API error's own message, [unreadDayMessage] for
/// none, and the error itself otherwise.
String readFailureMessage(Object? error) {
  if (error == null) {
    return unreadDayMessage;
  }
  if (error is CalendarApiException) {
    return error.message;
  }
  return "$error";
}

/// The item form's field errors for [error], keyed as `validateItemJson`
/// keys them: an hours refusal's, through [hoursErrorsOf], and the API's
/// validation errors; null for any other error.
Map<String, String>? writeFieldErrors(Object error) {
  if (error is CalendarHoursException) {
    return hoursErrorsOf(error.start, error.end, error.hours);
  }
  if (error is CalendarValidationException) {
    return error.fieldErrors;
  }
  return null;
}
