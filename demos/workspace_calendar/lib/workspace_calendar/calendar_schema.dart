/// The calendar's item types, the one schema registry that describes each
/// type's payload, and the one validator of an item's JSON. The mock API
/// and the form both read these.
///
/// An item is a JSON envelope: `id`, `type`, `title`, `start` and `end`,
/// local date-times with no offset in the form [isoDateTime] writes
/// (`YYYY-MM-DDTHH:MM`), the end exclusive, and `fields`, the type's
/// payload.
library;

import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

enum CalendarItemType {
  task("task", "Task"),
  meeting("meeting", "Meeting"),
  outOfOffice("outOfOffice", "Out of office"),
  deadline("deadline", "Deadline");

  const CalendarItemType(this.id, this.label);

  /// The value of the envelope's `type` key.
  final String id;

  final String label;

  /// The type whose [id] is [id], or null when none is.
  static CalendarItemType? fromId(String id) {
    for (final type in values) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }
}

enum FieldKind { choice, text, longText, textList, url, boolean }

class FieldChoice {
  const FieldChoice(this.value, this.label);

  /// The value stored in the payload.
  final String value;

  final String label;
}

/// One payload field of a type.
class FieldSpec {
  const FieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.choices = const <FieldChoice>[],
    this.defaultValue,
  });

  /// The key in the payload.
  final String key;

  final String label;
  final FieldKind kind;

  /// Whether the payload must hold a value that is not blank.
  final bool required;

  /// The values a [FieldKind.choice] field takes, in display order.
  final List<FieldChoice> choices;

  /// What [withFieldDefaults] adds when the payload lacks the field.
  final Object? defaultValue;

  /// The summary a card shows for [value]: a choice's label, a text,
  /// `"<label>: <count>"` for a list, `"<label>: Yes"` or `"<label>: No"`
  /// for a bool, or null when the value is absent or blank.
  String? summaryOf(Object? value) {
    if (_isBlank(value)) {
      return null;
    }
    switch (kind) {
      case FieldKind.choice:
        for (final choice in choices) {
          if (choice.value == value) {
            return choice.label;
          }
        }
        return null;
      case FieldKind.text:
      case FieldKind.longText:
      case FieldKind.url:
        return value is String ? value.trim() : null;
      case FieldKind.textList:
        return value is List ? "$label: ${value.length}" : null;
      case FieldKind.boolean:
        if (value is! bool) {
          return null;
        }
        return "$label: ${value ? "Yes" : "No"}";
    }
  }
}

/// The payload of one type.
class TypeSchema {
  const TypeSchema({
    required this.type,
    required this.fields,
    required this.summaryKeys,
  });

  final CalendarItemType type;

  /// The fields, in the order the form shows them.
  final List<FieldSpec> fields;

  /// The keys of the fields a card summarizes, in order, two at most; a
  /// grid block shows the first.
  final List<String> summaryKeys;

  /// The field whose key is [key], or null when the schema lists none.
  FieldSpec? fieldOf(String key) {
    for (final field in fields) {
      if (field.key == key) {
        return field;
      }
    }
    return null;
  }
}

const TypeSchema _taskSchema = TypeSchema(
  type: CalendarItemType.task,
  fields: <FieldSpec>[
    FieldSpec(
      key: "status",
      label: "Status",
      kind: FieldKind.choice,
      required: true,
      choices: <FieldChoice>[
        FieldChoice("toDo", "To do"),
        FieldChoice("inProgress", "In progress"),
        FieldChoice("done", "Done"),
      ],
      defaultValue: "toDo",
    ),
    FieldSpec(
      key: "priority",
      label: "Priority",
      kind: FieldKind.choice,
      choices: <FieldChoice>[
        FieldChoice("low", "Low"),
        FieldChoice("medium", "Medium"),
        FieldChoice("high", "High"),
      ],
      defaultValue: "medium",
    ),
    FieldSpec(key: "assignee", label: "Assignee", kind: FieldKind.text),
    FieldSpec(key: "notes", label: "Notes", kind: FieldKind.longText),
  ],
  summaryKeys: <String>["status", "priority"],
);

const TypeSchema _meetingSchema = TypeSchema(
  type: CalendarItemType.meeting,
  fields: <FieldSpec>[
    FieldSpec(key: "attendees", label: "Attendees", kind: FieldKind.textList),
    FieldSpec(key: "location", label: "Location", kind: FieldKind.text),
    FieldSpec(key: "videoLink", label: "Video link", kind: FieldKind.url),
    FieldSpec(key: "agenda", label: "Agenda", kind: FieldKind.longText),
  ],
  summaryKeys: <String>["location", "attendees"],
);

const TypeSchema _outOfOfficeSchema = TypeSchema(
  type: CalendarItemType.outOfOffice,
  fields: <FieldSpec>[
    FieldSpec(
      key: "reason",
      label: "Reason",
      kind: FieldKind.choice,
      required: true,
      choices: <FieldChoice>[
        FieldChoice("vacation", "Vacation"),
        FieldChoice("sick", "Sick"),
        FieldChoice("travel", "Travel"),
        FieldChoice("other", "Other"),
      ],
    ),
    FieldSpec(key: "note", label: "Note", kind: FieldKind.longText),
  ],
  summaryKeys: <String>["reason"],
);

const TypeSchema _deadlineSchema = TypeSchema(
  type: CalendarItemType.deadline,
  fields: <FieldSpec>[
    FieldSpec(
      key: "project",
      label: "Project",
      kind: FieldKind.text,
      required: true,
    ),
    FieldSpec(
      key: "met",
      label: "Met",
      kind: FieldKind.boolean,
      defaultValue: false,
    ),
  ],
  summaryKeys: <String>["project", "met"],
);

TypeSchema schemaOf(CalendarItemType type) {
  switch (type) {
    case CalendarItemType.task:
      return _taskSchema;
    case CalendarItemType.meeting:
      return _meetingSchema;
    case CalendarItemType.outOfOffice:
      return _outOfOfficeSchema;
    case CalendarItemType.deadline:
      return _deadlineSchema;
  }
}

/// The most days one item may cover.
const int maxDayCount = 366;

/// Whether an item may cover [dayCount] days, counting each day it has
/// any part of: 1 to [maxDayCount]. The one test of that range, which
/// [validateItemJson] reads; the example passes
/// [maxDayCount] to `CalendarView.maxDayCount`, which holds to it the
/// gestures its own doc names.
bool isAllowedDayCount(int dayCount) {
  return dayCount >= 1 && dayCount <= maxDayCount;
}

/// The error key [validateItemJson] reports for the payload field [key].
String fieldErrorKey(String key) {
  return "fields.$key";
}

/// [time]'s wall clock as the envelope writes it, "2026-04-21T09:10": its
/// year, month, day, hour and minute, with no seconds and no offset. Both
/// instants of a time a day's clock repeats write the same text.
String isoDateTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, "0");
  final minute = time.minute.toString().padLeft(2, "0");
  return "${isoDate(time)}T$hour:$minute";
}

final RegExp _isoDateTimePattern = RegExp(
  r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$",
);

/// The local time [text] names in the form [isoDateTime] writes, or null
/// when it is not in that form or names no time the clock reads: a day
/// that does not exist, or a time in an hour the clock skips, whose fields
/// a `DateTime` reads back moved. A time the clock repeats reads as its
/// earlier instant, the one `DateTime` gives.
DateTime? parseIsoDateTime(String text) {
  final match = _isoDateTimePattern.firstMatch(text);
  if (match == null) {
    return null;
  }
  final fields = <int>[
    for (var group = 1; group <= 5; group++) int.parse(match.group(group)!),
  ];
  final time = DateTime(fields[0], fields[1], fields[2], fields[3], fields[4]);
  if (time.year != fields[0] ||
      time.month != fields[1] ||
      time.day != fields[2] ||
      time.hour != fields[3] ||
      time.minute != fields[4]) {
    return null;
  }
  return time;
}

const Set<String> _envelopeKeys = <String>{
  "id",
  "type",
  "title",
  "start",
  "end",
  "fields",
};

/// Every rule [json] breaks, keyed by the envelope key or by
/// [fieldErrorKey] of the payload key it concerns. Empty when [json] is a
/// valid item. A payload is checked only when the type is known.
Map<String, String> validateItemJson(Map<String, Object?> json) {
  final errors = <String, String>{};
  for (final key in json.keys) {
    if (!_envelopeKeys.contains(key)) {
      errors[key] = "Unknown key.";
    }
  }
  final title = json["title"];
  if (title is! String || title.trim().isEmpty) {
    errors["title"] = "Enter a title.";
  }
  final typeId = json["type"];
  final type = typeId is String ? CalendarItemType.fromId(typeId) : null;
  if (type == null) {
    errors["type"] = "Unknown type.";
  }
  final startText = json["start"];
  final start = startText is String ? parseIsoDateTime(startText) : null;
  if (start == null) {
    errors["start"] = _timeError;
  }
  final endText = json["end"];
  final end = endText is String ? parseIsoDateTime(endText) : null;
  if (end == null) {
    errors["end"] = _timeError;
  } else if (start != null) {
    if (!end.isAfter(start)) {
      errors["end"] = "The end must be after the start.";
    } else if (!isAllowedDayCount(
      lastDayNumberOf(start, end) - dayNumber(start) + 1,
    )) {
      errors["end"] = "The item covers 1 to $maxDayCount days.";
    }
  }
  final fields = json["fields"];
  if (fields is! Map<String, Object?>) {
    errors["fields"] = "The fields are a map.";
  } else if (type != null) {
    _validateFields(schemaOf(type), fields, errors);
  }
  return errors;
}

/// What [validateItemJson] reports for a start or an end that
/// [parseIsoDateTime] does not read.
const String _timeError =
    "Enter a date and time as YYYY-MM-DDTHH:MM, at a time the clock reads.";

void _validateFields(
  TypeSchema schema,
  Map<String, Object?> fields,
  Map<String, String> errors,
) {
  for (final key in fields.keys) {
    if (schema.fieldOf(key) == null) {
      errors[fieldErrorKey(key)] = "Unknown field.";
    }
  }
  for (final field in schema.fields) {
    final value = fields[field.key];
    final errorKey = fieldErrorKey(field.key);
    if (_isBlank(value)) {
      if (field.required) {
        errors[errorKey] = "${field.label} is required.";
      } else if (value != null && !_hasKind(field, value)) {
        errors[errorKey] = _kindError(field);
      }
      continue;
    }
    if (!_hasKind(field, value)) {
      errors[errorKey] = _kindError(field);
    }
  }
}

/// Whether [value], present and not blank, is of [field]'s kind.
bool _hasKind(FieldSpec field, Object? value) {
  switch (field.kind) {
    case FieldKind.choice:
      return value is String &&
          field.choices.any((choice) {
            return choice.value == value;
          });
    case FieldKind.text:
    case FieldKind.longText:
      return value is String;
    case FieldKind.textList:
      return value is List &&
          value.every((entry) {
            return entry is String;
          });
    case FieldKind.url:
      return value is String && _isWebUrl(value);
    case FieldKind.boolean:
      return value is bool;
  }
}

String _kindError(FieldSpec field) {
  switch (field.kind) {
    case FieldKind.choice:
      final labels = field.choices.map((choice) {
        return choice.label;
      });
      return "Choose one of: ${labels.join(", ")}.";
    case FieldKind.text:
    case FieldKind.longText:
      return "${field.label} is text.";
    case FieldKind.textList:
      return "${field.label} is a list of names.";
    case FieldKind.url:
      return "Enter an http or https link.";
    case FieldKind.boolean:
      return "${field.label} is yes or no.";
  }
}

/// An empty string is a valid, absent URL; anything else needs the
/// `http` or `https` scheme and a host.
bool _isWebUrl(String text) {
  if (text.isEmpty) {
    return true;
  }
  final uri = Uri.tryParse(text);
  if (uri == null) {
    return false;
  }
  return (uri.scheme == "http" || uri.scheme == "https") && uri.host.isNotEmpty;
}

/// Absent, an all-whitespace string, or an empty list.
bool _isBlank(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is String) {
    return value.trim().isEmpty;
  }
  if (value is List) {
    return value.isEmpty;
  }
  return false;
}

/// [fields] with every absent field of [type]'s schema that has a default
/// added at its default. A new map; [fields] is not changed.
Map<String, Object?> withFieldDefaults(
  CalendarItemType type,
  Map<String, Object?> fields,
) {
  final result = Map<String, Object?>.of(fields);
  for (final field in schemaOf(type).fields) {
    final value = field.defaultValue;
    if (value != null && !result.containsKey(field.key)) {
      result[field.key] = value;
    }
  }
  return result;
}
