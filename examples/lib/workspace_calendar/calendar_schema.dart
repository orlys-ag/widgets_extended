/// The calendar's item types, the one schema registry that describes each
/// type's payload, the one validator of an item's JSON, and the one
/// overlap rule. The mock API and the form both read these.
///
/// An item is a JSON envelope: `id`, `type`, `title`, `day` (an ISO
/// date), `startMinute` and `endMinute` (minutes after midnight),
/// `dayCount` (consecutive days carrying the same hours) and `fields`,
/// the type's payload.
library;

import 'calendar_data.dart';

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
  final TypeSchema schema;
  switch (type) {
    case CalendarItemType.task:
      schema = _taskSchema;
    case CalendarItemType.meeting:
      schema = _meetingSchema;
    case CalendarItemType.outOfOffice:
      schema = _outOfOfficeSchema;
    case CalendarItemType.deadline:
      schema = _deadlineSchema;
  }
  // Here rather than in the constructor: a const constructor's assert
  // cannot read a list's length.
  assert(schema.summaryKeys.length <= 2, "A card shows two summaries at most.");
  return schema;
}

/// The length of one slot, and the step every item time is a multiple of.
const int minutesPerSlot = 15;

const int minutesPerDay = 1440;

/// The most days one item may cover.
const int maxDayCount = 366;

/// Whether an item may cover [dayCount] days: 1 to [maxDayCount]. The one
/// test of that range, which [validateItemJson] and the week grid's drop
/// check both read.
bool isAllowedDayCount(int dayCount) {
  return dayCount >= 1 && dayCount <= maxDayCount;
}

/// The error key [validateItemJson] reports for the payload field [key].
String fieldErrorKey(String key) {
  return "fields.$key";
}

const Set<String> _envelopeKeys = <String>{
  "id",
  "type",
  "title",
  "day",
  "startMinute",
  "endMinute",
  "dayCount",
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
  final day = json["day"];
  if (day is! String || parseIsoDate(day) == null) {
    errors["day"] = "Enter a date as YYYY-MM-DD.";
  }
  final start = json["startMinute"];
  final startValid =
      start is int &&
      start % minutesPerSlot == 0 &&
      start >= 0 &&
      start <= minutesPerDay - minutesPerSlot;
  if (!startValid) {
    errors["startMinute"] =
        "The start is a multiple of $minutesPerSlot minutes, 00:00 to "
        "${clockLabel(minutesPerDay - minutesPerSlot)}.";
  }
  final end = json["endMinute"];
  if (end is! int || end % minutesPerSlot != 0 || end > minutesPerDay) {
    errors["endMinute"] =
        "The end is a multiple of $minutesPerSlot minutes, at most "
        "${clockLabel(minutesPerDay)}.";
  } else if (start is int && end <= start) {
    errors["endMinute"] = "The end must be after the start.";
  }
  final dayCount = json["dayCount"];
  if (dayCount is! int || !isAllowedDayCount(dayCount)) {
    errors["dayCount"] = "The item covers 1 to $maxDayCount days.";
  }
  final fields = json["fields"];
  if (fields is! Map<String, Object?>) {
    errors["fields"] = "The fields are a map.";
  } else if (type != null) {
    _validateFields(schemaOf(type), fields, errors);
  }
  return errors;
}

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

/// What the overlap rule reads of an item. [firstDay] is a [dayNumber];
/// [start] and [end] are minutes after midnight on each of its days.
typedef ItemShape = ({
  CalendarItemType type,
  int firstDay,
  int dayCount,
  int start,
  int end,
});

/// Whether [a] and [b] may not share time: their days meet, their
/// half-open minute ranges `[start, end)` meet, and at least one of them
/// is Out of office or covers more than one day. Two single-day items of
/// any other type may share, which the board shows as lanes.
bool itemsConflict(ItemShape a, ItemShape b) {
  final exclusive =
      a.type == CalendarItemType.outOfOffice ||
      b.type == CalendarItemType.outOfOffice ||
      a.dayCount > 1 ||
      b.dayCount > 1;
  if (!exclusive) {
    return false;
  }
  final daysMeet =
      a.firstDay < b.firstDay + b.dayCount &&
      b.firstDay < a.firstDay + a.dayCount;
  final minutesMeet = a.start < b.end && b.start < a.end;
  return daysMeet && minutesMeet;
}
