/// The calendar's API boundary: JSON-compatible maps in and out, and the
/// errors a call can complete with.
library;

import 'package:flutter/foundation.dart';

/// The store the calendar reads and writes. Every map is a JSON envelope
/// (see `calendar_schema.dart`); a map passed in or returned is the
/// caller's own, never one the store keeps.
abstract interface class CalendarApi {
  /// Every item covering any day from [first] to [last], both inclusive,
  /// each once.
  Future<List<Map<String, Object?>>> list(DateTime first, DateTime last);

  /// The item [id]. Fails with [CalendarNotFoundException] when there is
  /// none.
  Future<Map<String, Object?>> get(String id);

  /// Stores [item] under a new id and completes with the stored item.
  Future<Map<String, Object?>> create(Map<String, Object?> item);

  /// Replaces the item [id] with [item] and completes with the stored
  /// item. The type cannot change.
  Future<Map<String, Object?>> update(String id, Map<String, Object?> item);

  /// Removes the item [id].
  Future<void> delete(String id);
}

enum CalendarMethod { list, get, create, update, delete }

/// One call as the API received it.
@immutable
class CalendarRequest {
  const CalendarRequest({
    required this.method,
    this.id,
    this.first,
    this.last,
    this.body,
  });

  final CalendarMethod method;

  /// The item a `get`, `update` or `delete` names.
  final String? id;

  /// The first day a `list` covers.
  final DateTime? first;

  /// The last day a `list` covers.
  final DateTime? last;

  /// What a `create` or `update` sent.
  final Map<String, Object?>? body;

  @override
  String toString() {
    final parts = <String>[
      method.name,
      if (id != null) "id: $id",
      if (first != null) "first: $first",
      if (last != null) "last: $last",
      if (body != null) "body: $body",
    ];
    return "CalendarRequest(${parts.join(", ")})";
  }
}

/// Asked once per call: a message fails the call with
/// [CalendarFailureException], null lets it run.
typedef CalendarFailurePolicy = String? Function(CalendarRequest request);

/// The errors a [CalendarApi] call completes with.
sealed class CalendarApiException implements Exception {
  const CalendarApiException();

  /// A sentence a person can read.
  String get message;

  @override
  String toString() {
    return message;
  }
}

/// The item breaks a rule of its envelope or its type's schema.
final class CalendarValidationException extends CalendarApiException {
  const CalendarValidationException(this.fieldErrors);

  /// Every rule broken, keyed as `validateItemJson` keys them.
  final Map<String, String> fieldErrors;

  @override
  String get message {
    return "The item is not valid: ${fieldErrors.values.join(" ")}";
  }
}

/// The item would share time with other items, which the overlap rule
/// forbids.
final class CalendarOverlapException extends CalendarApiException {
  const CalendarOverlapException(this.conflictingIds);

  final List<String> conflictingIds;

  @override
  String get message {
    return "The item overlaps another item.";
  }
}

final class CalendarNotFoundException extends CalendarApiException {
  const CalendarNotFoundException(this.id);

  final String id;

  @override
  String get message {
    return "No item $id.";
  }
}

/// The call failed for a reason outside the item: the network, the
/// server.
final class CalendarFailureException extends CalendarApiException {
  const CalendarFailureException(this.message);

  @override
  final String message;
}
