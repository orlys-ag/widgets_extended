/// The calendar's create flow, its item form, which also shows an item
/// read-only, and the delete confirmation.
///
/// The form is generated from the item type's schema and checks its input
/// with the same validator the API runs, and against the history lock,
/// whose refusals [lockErrorsOf] keys as the form's fields, before it sends
/// anything; the store holds its times to the calendar's hours, and the
/// time fields offer the slot boundaries inside them.
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
import 'harbor_theme.dart';

/// Asks for a type, then opens the form for a new item of it over the
/// range [range] picked, with All day on for an all-day range, whose Save
/// the history [lock] that holds then checks; its times step by
/// [slotMinutes]. Completes when the flow closes, whether or not an item
/// was created.
Future<void> showCreateFlow(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CreateRange range,
  required ValueGetter<HistoryLock> lock,
  int slotMinutes = defaultSlotMinutes,
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
    start: range.start,
    end: range.end,
    fields: withFieldDefaults(type, const <String, Object?>{}),
  );
  await _showForm(
    context,
    store: store,
    item: draft,
    lock: lock,
    slotMinutes: slotMinutes,
  );
}

/// Opens the form for the stored item [id], whose Save the history [lock]
/// that holds then checks, and whose times step by [slotMinutes]; of an
/// item the lock has [EntryHold.started] the start date, the start time
/// and All day take no input, and it has no Delete. Does nothing when the
/// store does not hold it.
Future<void> showEditForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required String id,
  required ValueGetter<HistoryLock> lock,
  int slotMinutes = defaultSlotMinutes,
}) async {
  final item = store.storedEntry(id);
  if (item == null) {
    return;
  }
  await _showForm(
    context,
    store: store,
    item: item,
    lock: lock,
    slotMinutes: slotMinutes,
  );
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

/// The item form's errors for [to], a change of the stored [from] or,
/// where [from] is null, a new item, which [lock] refuses, keyed as
/// `validateItemJson` keys them; empty where [lock] admits it.
Map<String, String> lockErrorsOf(
  HistoryLock lock,
  ({DateTime start, DateTime end})? from,
  ({DateTime start, DateTime end}) to,
) {
  final boundary = lock.boundary;
  if (boundary == null ||
      (from != null && lock.admits(from.start, from.end, to.start, to.end))) {
    return const <String, String>{};
  }
  if (from == null || lock.holdOf(from.start, from.end) == EntryHold.free) {
    if (!to.start.isBefore(boundary)) {
      return const <String, String>{};
    }
    if (dayNumber(to.start) < dayNumber(boundary)) {
      return const <String, String>{"start": "Past days are locked."};
    }
    return const <String, String>{"start": "The start can't be in the past."};
  }
  if (lock.holdOf(from.start, from.end) == EntryHold.locked) {
    return const <String, String>{"start": "Past items are locked."};
  }
  return <String, String>{
    if (to.start != from.start) "start": "An item in progress keeps its start.",
    if (!to.end.isAfter(boundary)) "end": "The end can't be in the past.",
  };
}

Future<void> _showForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CalendarItem item,
  bool readOnly = false,
  ValueGetter<HistoryLock>? lock,
  int slotMinutes = defaultSlotMinutes,
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
        slotMinutes: slotMinutes,
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
    required this.slotMinutes,
  });

  final CalendarStore<ItemPayload> store;
  final CalendarItem item;

  /// The step of the time fields' slot boundaries.
  final int slotMinutes;

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

  /// The day of the item's start.
  late DateTime _startDate = dateOfDayNumber(dayNumber(widget.item.start));

  /// The start's minute of [_startDate].
  late int _startMinute = minuteOfDay(widget.item.start);

  /// The last day the item has a part in.
  late DateTime _endDate = dateOfDayNumber(
    lastDayNumberOf(widget.item.start, widget.item.end),
  );

  /// The end's minute of [_endDate], 1440 for an end at the start of the
  /// day after it.
  late int _endMinute = endMinuteOfDay(widget.item.end);

  /// Whether the item covers whole days, from [_startDate]'s start to the
  /// start of the day after [_endDate], and the time fields hide.
  late bool _allDay = widget.item.isAllDay;

  /// How the history lock held the stored item when the form opened, free
  /// for a draft. Of a started one the start date, the start time and All
  /// day take no input.
  late final EntryHold _hold = widget.item.id == null
      ? EntryHold.free
      : widget.lock().holdOf(widget.item.start, widget.item.end);

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
    for (final controller in _texts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The item the form holds, as an envelope: with All day on, from the
  /// start of [_startDate] to the start of the day after [_endDate], and
  /// otherwise from [_startMinute] of [_startDate] to [_endMinute] of
  /// [_endDate].
  Map<String, Object?> _envelope() {
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
      "start": _allDay
          ? isoDateTime(_startDate)
          : _timeText(_startDate, _startMinute),
      "end": _allDay
          ? isoDateTime(addDays(_endDate, 1))
          : _timeText(_endDate, _endMinute),
      "fields": fields,
    };
  }

  /// [minute] of [day] as the envelope writes it: the time
  /// [timeAtWallMinute] gives, the earlier of a time the clock repeats, so
  /// 24:00 is the next day's start; and a time the clock skips as its own
  /// text, which the validator then reports.
  static String _timeText(DateTime day, int minute) {
    final time = timeAtWallMinute(dayNumber(day) * minutesPerDay + minute);
    if (time == null) {
      return "${isoDate(day)}T${clockLabel(minute)}";
    }
    return isoDateTime(time);
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
      final to = itemFromJson(json);
      errors = lockErrorsOf(
        widget.lock(),
        _isDraft ? null : (start: widget.item.start, end: widget.item.end),
        (start: to.start, end: to.end),
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

  /// Picks a day from [initial], and hands it to [onPicked].
  Future<void> _pickDate(
    DateTime initial,
    ValueChanged<DateTime> onPicked,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        onPicked(dateOnly(picked));
      });
    }
  }

  /// A field naming [date] that opens a date picker, showing the error
  /// [validateItemJson] keys [errorKey] where it is not null; a [fixed]
  /// one takes no input.
  Widget _dateField({
    required String label,
    required String? errorKey,
    required DateTime date,
    required ValueChanged<DateTime> onPicked,
    bool fixed = false,
  }) {
    return InkWell(
      onTap: _locked || fixed
          ? null
          : () {
              _pickDate(date, onPicked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorKey == null ? null : _errors[errorKey],
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(isoDate(date)),
      ),
    );
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
      for (var minute = first; minute <= last; minute += widget.slotMinutes)
        minute,
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
    final started = _hold == EntryHold.started;
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
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _dateField(
              label: "Start date",
              errorKey: _allDay ? "start" : null,
              date: _startDate,
              onPicked: (date) {
                _startDate = date;
              },
              fixed: started,
            ),
          ),
          if (!_allDay) ...<Widget>[
            const SizedBox(width: 12.0),
            Expanded(
              child: _minuteField(
                label: "Start time",
                errorKey: "start",
                value: _startMinute,
                first: hours.start,
                last: hours.end - widget.slotMinutes,
                onChanged: (minute) {
                  _startMinute = minute;
                },
                fixed: started,
              ),
            ),
          ],
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _dateField(
              label: "End date",
              errorKey: _allDay ? "end" : null,
              date: _endDate,
              onPicked: (date) {
                _endDate = date;
              },
            ),
          ),
          if (!_allDay) ...<Widget>[
            const SizedBox(width: 12.0),
            Expanded(
              child: _minuteField(
                label: "End time",
                errorKey: "end",
                value: _endMinute,
                first: hours.start + widget.slotMinutes,
                last: hours.end,
                onChanged: (minute) {
                  _endMinute = minute;
                },
              ),
            ),
          ],
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text("All day"),
        value: _allDay,
        onChanged: _locked || started
            ? null
            : (on) {
                setState(() {
                  _allDay = on;
                });
              },
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
                    if (!_isDraft &&
                        !widget.readOnly &&
                        _hold == EntryHold.free)
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
