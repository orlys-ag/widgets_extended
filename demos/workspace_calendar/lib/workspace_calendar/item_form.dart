/// The calendar's create flow, its item form, which also shows an item
/// read-only, and the delete confirmation.
///
/// The form opens in a modal bottom sheet. Its schedule section, which
/// every item type shares, edits a [CalendarSchedule] and shows what its
/// [CalendarScheduleCheck] answers; its details are generated from the item
/// type's schema. Save sends nothing while the check names a problem
/// ([scheduleErrorsOf]) or the validator the API runs refuses the item.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_api.dart';
import 'calendar_api_source.dart';
import 'calendar_item.dart';
import 'calendar_settings.dart';
import 'calendar_schema.dart';
import 'harbor_theme.dart';
import 'schedule_section.dart';

/// Opens the form for a new item over the range [range] picked, with All
/// day on for an all-day range, its type chosen in the form, Task first;
/// its Save [policy] checks at the time [now] reads then, and its times
/// step by [slotMinutes]. Completes when the form closes, whether or not
/// an item was created.
Future<void> showCreateFlow(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CalendarCreateRange range,
  required CalendarEditPolicy<ItemPayload> policy,
  required ValueGetter<CalendarNow> now,
  int slotMinutes = CalendarDates.defaultSlotMinutes,
}) {
  const type = CalendarItemType.task;
  final draft = calendarItem(
    type: type,
    title: "",
    start: range.start,
    end: range.end,
    fields: withFieldDefaults(type, const <String, Object?>{}),
    isAllDay: range.isAllDay,
  );
  return _showForm(
    context,
    store: store,
    item: draft,
    policy: policy,
    now: now,
    slotMinutes: slotMinutes,
  );
}

/// Opens the form for the stored item [id], whose Save [policy] checks at
/// the time [now] reads then, and whose times step by [slotMinutes]. Of an
/// item [policy], when the form opens, lets neither move nor resize its
/// start, the start date, the start time and All day take no input; and
/// the form offers Delete only where [policy] then lets the item be
/// deleted. Does nothing when the store does not hold it.
Future<void> showEditForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required String id,
  required CalendarEditPolicy<ItemPayload> policy,
  required ValueGetter<CalendarNow> now,
  int slotMinutes = CalendarDates.defaultSlotMinutes,
}) async {
  final item = store.storedEntry(id);
  if (item == null) {
    return;
  }
  await _showForm(
    context,
    store: store,
    item: item,
    policy: policy,
    now: now,
    slotMinutes: slotMinutes,
  );
}

/// Opens the form for the stored item [id] read-only: it shows the item's
/// schedule and fields, takes no input and has Close for its one action.
/// Does nothing when the store does not hold it.
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

/// The form's message for [problem].
String scheduleProblemMessage(CalendarScheduleProblem problem) {
  switch (problem) {
    case CalendarScheduleEndNotAfterStart():
      return "The end must be after the start.";
    case CalendarScheduleTooManyDays():
      return "The item covers 1 to $maxDayCount days.";
    case CalendarScheduleSpansDays():
      return "This item ends on the day it starts.";
    case CalendarScheduleAllDayNotAllowed():
      return "This item can't be all day.";
    case CalendarScheduleStartSkipped():
    case CalendarScheduleEndSkipped():
      return "The clock skips this time on that day.";
    case CalendarScheduleOutsideHours():
      return "Outside the calendar's hours.";
    case CalendarSchedulePastDay():
      return "Past days are locked.";
    case CalendarScheduleBeforeEarliest():
      return "The start can't be in the past.";
    case CalendarScheduleLocked():
      return "Past items are locked.";
    case CalendarScheduleStartKept():
      return "An item in progress keeps its start.";
    case CalendarScheduleKindKept():
      return "An item in progress keeps its All day setting.";
    case CalendarScheduleEndInPast():
      return "The end can't be in the past.";
    case CalendarScheduleOverlapRefused<ItemPayload>(:final other):
      return "Overlaps ${other.title}.";
    case CalendarScheduleRefused():
      return "The calendar's rules refuse this time.";
    default:
      return "This time isn't allowed.";
  }
}

/// The form's errors for [problems], keyed `start` or `end` as the form's
/// fields and the envelope key them ([CalendarScheduleProblem.atEnd]), the
/// first problem of each key giving its message.
Map<String, String> scheduleErrorsOf(
  Iterable<CalendarScheduleProblem> problems,
) {
  final errors = <String, String>{};
  for (final problem in problems) {
    errors.putIfAbsent(problem.atEnd ? "end" : "start", () {
      return scheduleProblemMessage(problem);
    });
  }
  return errors;
}

Future<void> _showForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CalendarItem item,
  bool readOnly = false,
  CalendarEditPolicy<ItemPayload>? policy,
  ValueGetter<CalendarNow>? now,
  int slotMinutes = CalendarDates.defaultSlotMinutes,
}) {
  // Neither a drag nor the barrier closes the sheet: a drag would close it
  // through the sheet's onClosing, which no PopScope stops, so a save in
  // flight would lose its outcome. Cancel, Save, Delete and the back
  // gesture close it, the last through the form's PopScope.
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) {
      return _ItemForm(
        store: store,
        item: item,
        readOnly: readOnly,
        policy: policy ?? const UnrestrictedEditPolicy<ItemPayload>(),
        now: now ?? _clockNow,
        slotMinutes: slotMinutes,
      );
    },
  );
}

/// The length of the times an all-day item takes when All day is turned
/// off: an hour.
const int _timedLengthMinutes = 60;

CalendarNow _clockNow() {
  final time = DateTime.now();
  return CalendarNow(time: time, today: time);
}

/// The form for [item]: a draft when its id is null, which Save creates,
/// and a stored item otherwise, which Save updates and Delete deletes, or
/// which it only shows when [readOnly].
class _ItemForm extends StatefulWidget {
  const _ItemForm({
    required this.store,
    required this.item,
    required this.readOnly,
    required this.policy,
    required this.now,
    required this.slotMinutes,
  });

  final CalendarStore<ItemPayload> store;
  final CalendarItem item;

  /// The step of the time fields' slot boundaries.
  final int slotMinutes;

  /// Whether every control is disabled and Close is the one action.
  final bool readOnly;

  /// The edit policy the schedule's check asks, and which decides whether
  /// the form offers Delete.
  final CalendarEditPolicy<ItemPayload> policy;

  /// The time the policy is asked at, read at each ask.
  final ValueGetter<CalendarNow> now;

  @override
  State<_ItemForm> createState() {
    return _ItemFormState();
  }
}

class _ItemFormState extends State<_ItemForm> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item.title,
  );

  late CalendarItemType _type = widget.item.type;

  late CalendarSchedule _schedule = _openingSchedule();

  /// The item's schedule. An all-day item has no times of its own for
  /// [CalendarSchedule.withAllDay] off to restore, so it keeps, as its
  /// timed ones, the first hour of the store's hours on its start day that
  /// no shown item shares, or the first hour where each is shared, as
  /// [CalendarEditRules.firstSlot] finds them; and its first day's 00:00 to
  /// its last day's 24:00 where the start day leaves no hour.
  CalendarSchedule _openingSchedule() {
    final item = widget.item;
    final schedule = CalendarSchedule.of(
      item.start,
      item.end,
      isAllDay: item.isAllDay,
    );
    if (!item.isAllDay) {
      return schedule;
    }
    final day = schedule.startDay;
    final start = _rules.earliestStartOn(day, widget.now());
    final shown = widget.store.entriesOn(day).map((shown) {
      return shown.entry;
    });
    final slot =
        _rules.firstSlot(
          start,
          clearOf: shown,
          lengthMinutes: _timedLengthMinutes,
        ) ??
        _rules.firstSlot(start, lengthMinutes: _timedLengthMinutes);
    if (slot == null) {
      return schedule;
    }
    return CalendarSchedule.of(
      slot.start,
      slot.end,
      isAllDay: false,
    ).withEndDay(schedule.endDay).withAllDay(true);
  }

  /// The rules the schedule is checked under: the policy, the store's
  /// hours when the form opened, and the slot length.
  late final CalendarEditRules<ItemPayload> _rules =
      CalendarEditRules<ItemPayload>(
        policy: widget.policy,
        hours: widget.store.hours,
        slotMinutes: widget.slotMinutes,
      );

  /// Whether the form offers Delete: of a stored item the policy, when the
  /// form opened, let be deleted, where the form is not read-only.
  late final bool _deletable =
      !_isDraft &&
      !widget.readOnly &&
      widget.policy.mayDelete(widget.item, widget.now());

  /// The text controllers of the schema's text, URL, long-text and text
  /// list fields, by key.
  final Map<String, TextEditingController> _texts =
      <String, TextEditingController>{};

  /// The values of the schema's choice and bool fields, by key.
  final Map<String, Object?> _values = <String, Object?>{};

  /// The errors the last Save found, keyed as the validator keys them.
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
    return schemaOf(_type);
  }

  @override
  void initState() {
    super.initState();
    _initFields(widget.item.fields);
  }

  /// The details' controls for [_type], at [fields] with the type's
  /// defaults for those it lacks.
  void _initFields(Map<String, Object?> fields) {
    for (final controller in _texts.values) {
      controller.dispose();
    }
    _texts.clear();
    _values.clear();
    final values = withFieldDefaults(_type, fields);
    for (final field in _schema.fields) {
      final value = values[field.key];
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

  /// The check of the schedule now, against the entries the store shows
  /// over its days.
  CalendarScheduleCheck<ItemPayload> _check() {
    return CalendarScheduleCheck<ItemPayload>(
      schedule: _schedule,
      rules: _rules,
      now: widget.now(),
      others: widget.store
          .entriesBetween(_schedule.startDay, _schedule.endDay)
          .map((shown) {
            return shown.entry;
          }),
      entry: _isDraft ? null : widget.item,
      options: scheduleOptionsOf(_type),
    );
  }

  /// The item the form holds, as an envelope: its schedule's times on the
  /// store's clock, as [itemTimeText] writes them; a time the clock skips
  /// as its own local text, which the validator then reports.
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
    final schedule = _schedule;
    final times = schedule.timesOn(widget.store.zone);
    final allDay = schedule.isAllDay;
    String textOf(DateTime? time, DateTime day, int minute) {
      if (time != null) {
        return itemTimeText(time, allDay: allDay);
      }
      return "${isoDate(day)}T${isoTime(minute)}";
    }

    return <String, Object?>{
      if (widget.item.id != null) "id": widget.item.id,
      "type": _type.id,
      "title": _title.text,
      "start": textOf(times?.start, schedule.startDay, schedule.startMinute),
      "end": textOf(times?.end, schedule.endDay, schedule.endMinute),
      "fields": fields,
    };
  }

  /// Validates and sends. Nothing is sent while the schedule's check names
  /// a problem or a field breaks a rule; the form stays open, with every
  /// control disabled, until the API answers, and closes on success.
  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final json = _envelope();
    final problems = _check().problems;
    final times = _schedule.timesOn(widget.store.zone);
    final errors = <String, String>{
      ...validateItemJson(json),
      ...scheduleErrorsOf(problems),
      // The hours' own words, as the store's refusal of them reads.
      if (times != null &&
          problems.any((problem) {
            return problem is CalendarScheduleOutsideHours;
          }))
        ...hoursErrorsOf(times.start, times.end, widget.store.hours),
    };
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

  /// Asks first; a confirmed delete closes the form and then deletes,
  /// and the messenger the form showed under says why where it fails.
  Future<void> _delete() async {
    final confirmed = await confirmDelete(context);
    if (!confirmed || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await widget.store.requestDelete(widget.item.id!);
    } on Object catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(writeFailureMessage(error))));
    }
  }

  /// A new item's type: the details reset to [type]'s defaults, the title
  /// and the schedule kept.
  void _selectType(CalendarItemType type) {
    if (type == _type) {
      return;
    }
    setState(() {
      _type = type;
      _initFields(const <String, Object?>{});
      _errors = const <String, String>{};
    });
  }

  /// The control for one schema field, by its kind.
  Widget _fieldFor(FieldSpec field) {
    final error = _errors[fieldErrorKey(field.key)];
    switch (field.kind) {
      case FieldKind.choice:
        final value = _values[field.key];
        return DropdownButtonFormField<String>(
          key: ValueKey<String>("${_type.id}.${field.key}"),
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

  Widget _typeSelector() {
    return SegmentedButton<CalendarItemType>(
      showSelectedIcon: false,
      segments: <ButtonSegment<CalendarItemType>>[
        for (final type in CalendarItemType.values)
          ButtonSegment<CalendarItemType>(
            value: type,
            icon: Icon(harborTypeStyleOf(type).icon),
            label: Text(type.label),
          ),
      ],
      selected: <CalendarItemType>{_type},
      onSelectionChanged: _locked
          ? null
          : (selected) {
              _selectType(selected.single);
            },
    );
  }

  Widget _typeRow() {
    final style = harborTypeStyleOf(_type);
    return Row(
      children: <Widget>[
        Icon(style.icon, color: style.edge),
        const SizedBox(width: 8.0),
        Text(
          _type.label,
          style: const TextStyle(fontSize: 15.0, color: HarborColors.text),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final String heading;
    if (widget.readOnly) {
      heading = _type.label;
    } else if (_isDraft) {
      heading = "New item";
    } else {
      heading = "Edit ${_type.label}";
    }
    final fields = <Widget>[
      if (_isDraft && !widget.readOnly) _typeSelector() else _typeRow(),
      TextField(
        controller: _title,
        enabled: !_locked,
        decoration: InputDecoration(
          labelText: "Title",
          errorText: _errors["title"],
        ),
      ),
      // The store's notifications check the schedule again, so an item
      // another write puts over its time shows while the form is open.
      ListenableBuilder(
        listenable: widget.store,
        builder: (context, child) {
          return ScheduleSection(
            check: _check(),
            hours: widget.store.hours,
            slotMinutes: widget.slotMinutes,
            zone: widget.store.zone,
            locked: _locked,
            errors: _errors,
            onChanged: (schedule) {
              setState(() {
                _schedule = schedule;
              });
            },
          );
        },
      ),
      for (final field in _schema.fields) _fieldFor(field),
    ];
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                heading,
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
                  if (_deletable)
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
    );
  }
}
