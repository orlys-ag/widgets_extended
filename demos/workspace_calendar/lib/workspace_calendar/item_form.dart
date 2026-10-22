/// The calendar's create flow, its item form, which also shows an item
/// read-only, and the delete confirmation.
///
/// The form is generated from the item type's schema and checks its input
/// with the same validator the API runs, and against the history lock,
/// before it sends anything; the
/// store holds its days and minutes to the calendar's hours, and the time
/// fields offer the minutes inside them.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/policy/history_lock.dart';

import 'calendar_api.dart';
import 'calendar_api_source.dart';
import 'calendar_item.dart';
import 'calendar_schema.dart';
import 'calendar_settings.dart';
import 'harbor_theme.dart';
import 'timed_grid.dart';

/// Asks for a type, then opens the form for a new item of it over the
/// slots [range] picked, whose Save the history [lock] that holds then
/// checks. Completes when the flow closes, whether or not an item was
/// created.
Future<void> showCreateFlow(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CreateRange range,
  required ValueGetter<HistoryLock> lock,
}) async {
  final type = await showDialog<CalendarItemType>(
    context: context,
    builder: (context) {
      return SimpleDialog(
        title: const Text("New item"),
        children: <Widget>[
          for (final type in CalendarItemType.values)
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop(type);
              },
              child: Row(
                children: <Widget>[
                  Icon(
                    harborTypeStyleOf(type).icon,
                    color: harborTypeStyleOf(type).edge,
                  ),
                  const SizedBox(width: 12.0),
                  Text(type.label),
                ],
              ),
            ),
        ],
      );
    },
  );
  if (type == null || !context.mounted) {
    return;
  }
  final draft = calendarItem(
    type: type,
    title: "",
    day: range.day,
    startMinute: range.startMinute,
    endMinute: range.endMinute,
    dayCount: range.dayCount,
    fields: withFieldDefaults(type, const <String, Object?>{}),
  );
  await _showForm(context, store: store, item: draft, lock: lock);
}

/// Opens the form for the stored item [id], whose Save the history [lock]
/// that holds then checks; of an item the lock has [ItemHold.started] the
/// day and the start take no input, and it has no Delete. Does nothing
/// when the store does not hold it.
Future<void> showEditForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required String id,
  required ValueGetter<HistoryLock> lock,
}) async {
  final item = store.storedEntry(id);
  if (item == null) {
    return;
  }
  await _showForm(context, store: store, item: item, lock: lock);
}

/// Opens the form for the stored item [id] read-only: it shows the item's
/// fields, takes no input and has Close for its one action. Does nothing
/// when the store does not hold it.
Future<void> showItemDetails(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required String id,
}) async {
  final item = store.storedEntry(id);
  if (item == null) {
    return;
  }
  await _showForm(context, store: store, item: item, readOnly: true);
}

/// Asks whether to delete an item. True when Delete was pressed.
Future<bool> confirmDelete(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Delete item?"),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: const Text("Delete"),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

Future<void> _showForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CalendarItem item,
  bool readOnly = false,
  ValueGetter<HistoryLock>? lock,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return _ItemForm(
        store: store,
        item: item,
        readOnly: readOnly,
        lock: lock ?? _noLock,
      );
    },
  );
}

HistoryLock _noLock() {
  return HistoryLock.none;
}

/// The form for [item]: a draft when its id is null, which Save creates,
/// and a stored item otherwise, which Save updates and Delete deletes, or
/// which it only shows when [readOnly].
class _ItemForm extends StatefulWidget {
  const _ItemForm({
    required this.store,
    required this.item,
    required this.readOnly,
    required this.lock,
  });

  final CalendarStore<ItemPayload> store;
  final CalendarItem item;

  /// Whether every control is disabled and Close is the one action.
  final bool readOnly;

  /// The history lock at the moment it is read: when the form opens, for
  /// what it takes input in, and at Save, which it refuses to break.
  final ValueGetter<HistoryLock> lock;

  @override
  State<_ItemForm> createState() {
    return _ItemFormState();
  }
}

class _ItemFormState extends State<_ItemForm> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item.title,
  );
  late final TextEditingController _days = TextEditingController(
    text: "${widget.item.dayCount}",
  );
  late DateTime _day = widget.item.day;
  late int _start = widget.item.startMinute;
  late int _end = widget.item.endMinute;

  /// How the history lock held the stored item when the form opened, free
  /// for a draft. Of a started one the day and the start take no input.
  late final ItemHold _hold = widget.item.id == null
      ? ItemHold.free
      : widget.lock().holdOf(widget.item.time);

  /// The text controllers of the schema's text, URL, long-text and text
  /// list fields, by key.
  final Map<String, TextEditingController> _texts =
      <String, TextEditingController>{};

  /// The values of the schema's choice and bool fields, by key.
  final Map<String, Object?> _values = <String, Object?>{};

  /// The validator's errors, keyed as it keys them.
  Map<String, String> _errors = const <String, String>{};

  /// A failure that names no field: an overlap, the network, a lock.
  String? _message;

  bool _saving = false;

  /// Whether the controls take no input: while the form saves, and always
  /// when it is read-only.
  bool get _locked {
    return _saving || widget.readOnly;
  }

  bool get _isDraft {
    return widget.item.id == null;
  }

  TypeSchema get _schema {
    return schemaOf(widget.item.type);
  }

  @override
  void initState() {
    super.initState();
    final fields = withFieldDefaults(widget.item.type, widget.item.fields);
    for (final field in _schema.fields) {
      final value = fields[field.key];
      switch (field.kind) {
        case FieldKind.choice:
        case FieldKind.boolean:
          _values[field.key] = value;
        case FieldKind.text:
        case FieldKind.longText:
        case FieldKind.url:
          _texts[field.key] = TextEditingController(
            text: value is String ? value : "",
          );
        case FieldKind.textList:
          _texts[field.key] = TextEditingController(
            text: value is List ? value.join(", ") : "",
          );
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _days.dispose();
    for (final controller in _texts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The item the form holds, as an envelope. The Days text goes in as an
  /// int when it reads as one and as the text otherwise, so the validator
  /// reports it.
  Map<String, Object?> _envelope() {
    final daysText = _days.text.trim();
    final fields = <String, Object?>{};
    for (final field in _schema.fields) {
      switch (field.kind) {
        case FieldKind.choice:
        case FieldKind.boolean:
          final value = _values[field.key];
          if (value != null) {
            fields[field.key] = value;
          }
        case FieldKind.text:
        case FieldKind.longText:
        case FieldKind.url:
          final text = _texts[field.key]!.text;
          if (text.isNotEmpty) {
            fields[field.key] = text;
          }
        case FieldKind.textList:
          final entries = <String>[
            for (final part in _texts[field.key]!.text.split(","))
              if (part.trim().isNotEmpty) part.trim(),
          ];
          if (entries.isNotEmpty) {
            fields[field.key] = entries;
          }
      }
    }
    return <String, Object?>{
      if (widget.item.id != null) "id": widget.item.id,
      "type": widget.item.type.id,
      "title": _title.text,
      "day": isoDate(_day),
      "startMinute": _start,
      "endMinute": _end,
      "dayCount": int.tryParse(daysText) ?? daysText,
      "fields": fields,
    };
  }

  /// Validates and sends. Nothing is sent while a field breaks a rule, or
  /// the item breaks the history lock; the form stays open, with every
  /// control disabled, until the API answers, and closes on success.
  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final json = _envelope();
    var errors = validateItemJson(json);
    if (errors.isEmpty) {
      errors = lockErrorsOf(
        widget.lock(),
        _isDraft ? null : widget.item.time,
        itemFromJson(json).time,
      );
    }
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _message = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _errors = const <String, String>{};
      _message = null;
    });
    final item = itemFromJson(json);
    try {
      if (_isDraft) {
        await widget.store.create(item);
      } else {
        await widget.store.update(item);
      }
    } on Object catch (error) {
      final fieldErrors = writeFieldErrors(error);
      if (fieldErrors == null &&
          error is! CalendarStoreException &&
          error is! CalendarApiException) {
        rethrow;
      }
      if (mounted) {
        setState(() {
          _saving = false;
          if (fieldErrors != null) {
            _errors = fieldErrors;
          } else {
            _message = writeFailureMessage(error);
          }
        });
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Asks first; a confirmed delete closes the form and then deletes.
  Future<void> _delete() async {
    final confirmed = await confirmDelete(context);
    if (!confirmed || !mounted) {
      return;
    }
    Navigator.of(context).pop();
    widget.store.requestDelete(widget.item.id!);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_day.year - 5),
      lastDate: DateTime(_day.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        _day = dateOnly(picked);
      });
    }
  }

  /// A dropdown of every slot boundary from [first] to [last] minutes, and
  /// of [value] where it lies outside them, so an item that lay outside the
  /// calendar's hours when they changed shows its own time. A [fixed] one
  /// takes no input.
  Widget _minuteField({
    required String label,
    required String errorKey,
    required int value,
    required int first,
    required int last,
    required ValueChanged<int> onChanged,
    bool fixed = false,
  }) {
    final minutes = <int>{
      for (var minute = first; minute <= last; minute += minutesPerSlot) minute,
      value,
    }.toList()..sort();
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[errorKey],
      ),
      items: <DropdownMenuItem<int>>[
        for (final minute in minutes)
          DropdownMenuItem<int>(value: minute, child: Text(clockLabel(minute))),
      ],
      onChanged: _locked || fixed
          ? null
          : (minute) {
              if (minute != null) {
                setState(() {
                  onChanged(minute);
                });
              }
            },
    );
  }

  /// The control for one schema field, by its kind.
  Widget _fieldFor(FieldSpec field) {
    final error = _errors[fieldErrorKey(field.key)];
    switch (field.kind) {
      case FieldKind.choice:
        final value = _values[field.key];
        return DropdownButtonFormField<String>(
          initialValue: value is String ? value : null,
          decoration: InputDecoration(labelText: field.label, errorText: error),
          items: <DropdownMenuItem<String>>[
            for (final choice in field.choices)
              DropdownMenuItem<String>(
                value: choice.value,
                child: Text(choice.label),
              ),
          ],
          onChanged: _locked
              ? null
              : (choice) {
                  setState(() {
                    _values[field.key] = choice;
                  });
                },
        );
      case FieldKind.text:
      case FieldKind.url:
      case FieldKind.textList:
        return TextField(
          controller: _texts[field.key],
          enabled: !_locked,
          maxLines: 1,
          keyboardType: field.kind == FieldKind.url ? TextInputType.url : null,
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.kind == FieldKind.textList
                ? "Separate names with commas"
                : null,
            errorText: error,
          ),
        );
      case FieldKind.longText:
        return TextField(
          controller: _texts[field.key],
          enabled: !_locked,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: field.label, errorText: error),
        );
      case FieldKind.boolean:
        final value = _values[field.key];
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          subtitle: error == null
              ? null
              : Text(error, style: const TextStyle(color: HarborColors.error)),
          value: value == true,
          onChanged: _locked
              ? null
              : (on) {
                  setState(() {
                    _values[field.key] = on;
                  });
                },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.item.type;
    final style = harborTypeStyleOf(type);
    final message = _message;
    final hours = widget.store.hours;
    final started = _hold == ItemHold.started;
    final fields = <Widget>[
      Row(
        children: <Widget>[
          Icon(style.icon, color: style.edge),
          const SizedBox(width: 8.0),
          Text(
            type.label,
            style: const TextStyle(fontSize: 15.0, color: HarborColors.text),
          ),
        ],
      ),
      TextField(
        controller: _title,
        enabled: !_locked,
        decoration: InputDecoration(
          labelText: "Title",
          errorText: _errors["title"],
        ),
      ),
      InkWell(
        onTap: _locked || started ? null : _pickDay,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: "Day",
            errorText: _errors["day"],
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          child: Text(isoDate(_day)),
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _minuteField(
              label: "Start",
              errorKey: "startMinute",
              value: _start,
              first: hours.start,
              last: hours.end - minutesPerSlot,
              onChanged: (minute) {
                _start = minute;
              },
              fixed: started,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: _minuteField(
              label: "End",
              errorKey: "endMinute",
              value: _end,
              first: hours.start + minutesPerSlot,
              last: hours.end,
              onChanged: (minute) {
                _end = minute;
              },
            ),
          ),
        ],
      ),
      TextField(
        controller: _days,
        enabled: !_locked,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: "Days",
          errorText: _errors["dayCount"],
        ),
      ),
      for (final field in _schema.fields) _fieldFor(field),
    ];
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  widget.readOnly
                      ? type.label
                      : "${_isDraft ? "New" : "Edit"} ${type.label}",
                  style: const TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w600,
                    color: HarborColors.text,
                  ),
                ),
                const SizedBox(height: 12.0),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final field in fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: field,
                          ),
                      ],
                    ),
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      message,
                      style: const TextStyle(color: HarborColors.error),
                    ),
                  ),
                // Stacks the actions where a narrow screen cannot fit them in
                // a row.
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8.0,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: <Widget>[
                    if (widget.readOnly)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text("Close"),
                      ),
                    if (!_isDraft && !widget.readOnly && _hold == ItemHold.free)
                      TextButton(
                        onPressed: _saving ? null : _delete,
                        child: const Text("Delete"),
                      ),
                    if (!widget.readOnly) ...<Widget>[
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () {
                                Navigator.of(context).pop();
                              },
                        child: const Text("Cancel"),
                      ),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox.square(
                                dimension: 16.0,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                ),
                              )
                            : const Text("Save"),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
