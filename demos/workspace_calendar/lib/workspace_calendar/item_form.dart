/// The calendar's create flow, its item form, which also shows an item
/// read-only, and the delete confirmation.
///
/// The form opens in a modal bottom sheet, a scrolling page of three
/// cards: the schedule section, which every item type shares and which
/// edits a [CalendarSchedule]; the schedule's summary, which shows what its
/// [CalendarScheduleCheck] answers; and the item's own fields, generated
/// from the item type's schema. Once the schedule section has scrolled
/// away, the summary stays at the page's top while the item's fields scroll
/// under it, where it takes at most half of the page
/// ([FittingPinnedHeaderSliver]). The check is made again
/// at each edit, at each change of the store and at the start of each
/// minute. Save sends nothing while the check names a problem
/// ([scheduleErrorsOf]) or the validator the API runs refuses the item;
/// after a failed Save the title's and the times' messages follow the
/// edits.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_api.dart';
import 'calendar_api_source.dart';
import 'calendar_item.dart';
import 'calendar_settings.dart';
import 'calendar_schema.dart';
import 'fitting_pinned_header.dart';
import 'harbor_theme.dart';
import 'schedule_section.dart';

/// The key of the form's summary card, which holds the [ScheduleSummary].
const ValueKey<String> formSummaryCardKey = ValueKey<String>(
  "form-summary-card",
);

/// The key of the form's scheduling card, which holds the
/// [ScheduleSection].
const ValueKey<String> formSchedulingCardKey = ValueKey<String>(
  "form-scheduling-card",
);

/// The key of the form's item card, which holds the item's type, title and
/// type fields.
const ValueKey<String> formItemCardKey = ValueKey<String>("form-item-card");

/// Opens the form for a new item over the range [range] picked, with All
/// day on for an all-day range, its type chosen in the form, Task first;
/// its Save [policy] checks at the time [now] reads then, its times step
/// by [slotMinutes], and it writes them on [hourLabelFormat]'s clock.
/// Completes when the form closes, whether or not an item was created.
Future<void> showCreateFlow(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CalendarCreateRange range,
  required CalendarEditPolicy<ItemPayload> policy,
  required ValueGetter<CalendarNow> now,
  required CalendarHourLabelFormat hourLabelFormat,
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
    hourLabelFormat: hourLabelFormat,
    slotMinutes: slotMinutes,
  );
}

/// Opens the form for the stored item [id], whose Save [policy] checks at
/// the time [now] reads then, whose times step by [slotMinutes], and which
/// writes them on [hourLabelFormat]'s clock. Of an item [policy], when the
/// form opens, lets neither move nor resize its start, the start date, the
/// start time and All day take no input; and the form offers Delete only
/// where [policy] then lets the item be deleted. Does nothing when the
/// store does not hold it.
Future<void> showEditForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required String id,
  required CalendarEditPolicy<ItemPayload> policy,
  required ValueGetter<CalendarNow> now,
  required CalendarHourLabelFormat hourLabelFormat,
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
    hourLabelFormat: hourLabelFormat,
    slotMinutes: slotMinutes,
  );
}

/// Opens the form for the stored item [id] read-only: it shows the item's
/// schedule, its times on [hourLabelFormat]'s clock, and its fields, takes
/// no input and has Close for its one action. Does nothing when the store
/// does not hold it.
Future<void> showItemDetails(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required String id,
  required CalendarHourLabelFormat hourLabelFormat,
}) async {
  final item = store.storedEntry(id);
  if (item == null) {
    return;
  }
  await _showForm(
    context,
    store: store,
    item: item,
    readOnly: true,
    hourLabelFormat: hourLabelFormat,
  );
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
  required CalendarHourLabelFormat hourLabelFormat,
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
        hourLabelFormat: hourLabelFormat,
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
    required this.hourLabelFormat,
    required this.slotMinutes,
  });

  final CalendarStore<ItemPayload> store;
  final CalendarItem item;

  /// The step of the time fields' slot boundaries.
  final int slotMinutes;

  /// The clock the schedule's summary and section write times on.
  final CalendarHourLabelFormat hourLabelFormat;

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

  /// The schedule's check, which the summary and the section read: made in
  /// [initState] and again by [_recheck] only.
  late CalendarScheduleCheck<ItemPayload> _scheduleCheck;

  /// The errors [_errorsOf] finds of [_scheduleCheck] and the form's item,
  /// made at the first read after each [_recheck].
  Map<String, String>? _liveErrors;

  /// Whether a Save failed, by a failed validation or a refused send, so
  /// that the title's and the times' messages show, following the edits.
  bool _saveFailed = false;

  /// The errors the last failed validation found, or a refused send's field
  /// errors, keyed as the validator keys them; the type fields show theirs
  /// until the next Save or a type change. Replaced, never changed in
  /// place.
  Map<String, String> _saveErrors = const <String, String>{};

  /// A refused send's messages of the title, the start and the end, each
  /// shown until an edit changes what it reads. Replaced, never changed in
  /// place.
  Map<String, String> _refusal = const <String, String>{};

  /// The title's text as [_titleChanged] last saw it.
  late String _titleText;

  /// A failure that names no field: an overlap, the network, a lock.
  String? _message;

  bool _saving = false;

  /// Fires at the start of the next minute, for [_minuteTurned].
  Timer? _minuteTimer;

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
    _scheduleCheck = _checkNow();
    _scheduleMinute();
    _titleText = _title.text;
    _title.addListener(_titleChanged);
    widget.store.addListener(_storeChanged);
  }

  @override
  void didUpdateWidget(_ItemForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_storeChanged);
      widget.store.addListener(_storeChanged);
    }
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
    _minuteTimer?.cancel();
    widget.store.removeListener(_storeChanged);
    _title.removeListener(_titleChanged);
    _title.dispose();
    for (final controller in _texts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Checks the schedule again, so an item another write puts over its time
  /// shows while the form is open; but not while a send is in flight, whose
  /// own write notifies before it completes, and which a draft's check
  /// would count as an overlap of its own.
  void _storeChanged() {
    if (_saving) {
      return;
    }
    setState(_recheck);
  }

  /// Sets [_minuteTimer] for the start of the minute after the time now.
  void _scheduleMinute() {
    final time = widget.now().time;
    final intoMinute = Duration(
      seconds: time.second,
      milliseconds: time.millisecond,
      microseconds: time.microsecond,
    );
    _minuteTimer = Timer(const Duration(minutes: 1) - intoMinute, () {
      _minuteTurned();
    });
  }

  /// Checks the schedule again as a minute starts, since the check's
  /// answers move with the minute now
  /// ([CalendarEarliestStart.firstWallMinute]), so the summary, the pickers,
  /// their Now and the messages after a failed Save answer as Save's own
  /// check does; but not while a send is in flight, which [_storeChanged]
  /// skips too.
  void _minuteTurned() {
    if (!_saving) {
      setState(_recheck);
    }
    _scheduleMinute();
  }

  /// Drops the refusal's title message at a change of the title's text;
  /// the title's [ListenableBuilder] shows it, rebuilding nothing else.
  void _titleChanged() {
    final text = _title.text;
    if (text == _titleText) {
      return;
    }
    _titleText = text;
    if (_refusal.containsKey("title")) {
      _refusal = _without(_refusal, const <String>["title"]);
    }
  }

  /// [map] without [keys], as a new map.
  static Map<String, String> _without(
    Map<String, String> map,
    List<String> keys,
  ) {
    return <String, String>{
      for (final entry in map.entries)
        if (!keys.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Makes [_scheduleCheck] anew at the time now, and drops the live errors
  /// of the last one.
  void _recheck() {
    _scheduleCheck = _checkNow();
    _liveErrors = null;
  }

  /// Takes [schedule], the section's edit: drops the refusal's start
  /// message where it moves the start, and its end message where it moves
  /// either time, and checks again.
  void _scheduleChanged(CalendarSchedule schedule) {
    final old = _schedule;
    final startMoved =
        schedule.startDay != old.startDay ||
        schedule.startMinute != old.startMinute ||
        schedule.isAllDay != old.isAllDay;
    final endMoved =
        startMoved ||
        schedule.endDay != old.endDay ||
        schedule.endMinute != old.endMinute;
    setState(() {
      _schedule = schedule;
      if (endMoved) {
        _refusal = _without(_refusal, <String>[if (startMoved) "start", "end"]);
      }
      _recheck();
    });
  }

  /// The check of the schedule now, against the entries the store shows
  /// from its first day to the day after its last, so that the checks the
  /// schedule section makes of its pickers' times, an end moved onto the
  /// next day among them, see that day's entries too.
  CalendarScheduleCheck<ItemPayload> _checkNow() {
    return CalendarScheduleCheck<ItemPayload>(
      schedule: _schedule,
      rules: _rules,
      now: widget.now(),
      others: widget.store
          .entriesBetween(
            _schedule.startDay,
            CalendarDates.addDays(_schedule.endDay, 1),
          )
          .map((shown) {
            return shown.entry;
          })
          .toList(),
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

  /// The errors of [json], the form's item as an envelope, under [check],
  /// keyed as the validator keys them: the validator's, the check's
  /// ([scheduleErrorsOf]), and where the hours refuse the times, their own
  /// words, as the store's refusal of them reads. Save's errors, and the
  /// live start and end messages after a failed Save.
  Map<String, String> _errorsOf(
    CalendarScheduleCheck<ItemPayload> check,
    Map<String, Object?> json,
  ) {
    final problems = check.problems;
    final times = check.schedule.timesOn(widget.store.zone);
    return <String, String>{
      ...validateItemJson(json),
      ...scheduleErrorsOf(problems),
      if (times != null &&
          problems.any((problem) {
            return problem is CalendarScheduleOutsideHours;
          }))
        ...hoursErrorsOf(times.start, times.end, widget.store.hours),
    };
  }

  /// Checks at the time now, validates and sends. Nothing is sent while the
  /// schedule's check names a problem or a field breaks a rule; the form
  /// stays open, with every control disabled, until the API answers, and
  /// closes on success.
  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final json = _envelope();
    final check = _checkNow();
    final errors = _errorsOf(check, json);
    if (errors.isNotEmpty) {
      setState(() {
        _scheduleCheck = check;
        _liveErrors = null;
        _saveFailed = true;
        _saveErrors = errors;
        _refusal = const <String, String>{};
        _message = null;
      });
      return;
    }
    setState(() {
      _scheduleCheck = check;
      _liveErrors = null;
      _saving = true;
      _saveErrors = const <String, String>{};
      _refusal = const <String, String>{};
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
          _saveFailed = true;
          if (fieldErrors != null) {
            _saveErrors = fieldErrors;
            _refusal = <String, String>{
              for (final key in const <String>["title", "start", "end"])
                key: ?fieldErrors[key],
            };
          } else {
            _message = writeFailureMessage(error);
          }
          // The store may have changed while the send was in flight.
          _recheck();
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
      _saveErrors = const <String, String>{};
      _recheck();
    });
  }

  /// The title's message: the refusal's, or after a failed Save the title
  /// rule's of the text now ([titleErrorOf]).
  String? _titleError() {
    return _refusal["title"] ??
        (_saveFailed ? titleErrorOf(_title.text) : null);
  }

  /// The start's and the end's messages, each the refusal's, or after a
  /// failed Save that of [_errorsOf] of the check and the item now.
  Map<String, String> _scheduleErrors() {
    final errors = <String, String>{};
    for (final key in const <String>["start", "end"]) {
      final message =
          _refusal[key] ??
          (_saveFailed
              ? (_liveErrors ??= _errorsOf(_scheduleCheck, _envelope()))[key]
              : null);
      if (message != null) {
        errors[key] = message;
      }
    }
    return errors;
  }

  /// The control for one schema field, by its kind.
  Widget _fieldFor(FieldSpec field) {
    final error = _saveErrors[fieldErrorKey(field.key)];
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

  /// An outlined card keyed [key], with no heading, holding [child] inside
  /// [padding].
  Widget _card(
    Key key,
    Widget child, {
    EdgeInsetsGeometry padding = const EdgeInsets.all(16.0),
  }) {
    return Card.outlined(
      key: key,
      margin: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );
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
    final itemFields = <Widget>[
      if (_isDraft && !widget.readOnly) _typeSelector() else _typeRow(),
      // A keystroke rebuilds the title alone, whose message follows it.
      ListenableBuilder(
        listenable: _title,
        builder: (context, child) {
          return TextField(
            controller: _title,
            enabled: !_locked,
            decoration: InputDecoration(
              labelText: "Title",
              errorText: _titleError(),
            ),
          );
        },
      ),
      for (final field in _schema.fields) _fieldFor(field),
    ];
    // The section pads itself to the card's edges, so that its controls'
    // touch targets can reach into the padding.
    final schedulingCard = _card(
      formSchedulingCardKey,
      padding: EdgeInsets.zero,
      ScheduleSection(
        check: _scheduleCheck,
        hours: widget.store.hours,
        slotMinutes: widget.slotMinutes,
        hourLabelFormat: widget.hourLabelFormat,
        now: widget.now,
        zone: widget.store.zone,
        locked: _locked,
        errors: _scheduleErrors(),
        onChanged: _scheduleChanged,
      ),
    );
    final summaryCard = _card(
      formSummaryCardKey,
      ScheduleSummary(
        check: _scheduleCheck,
        hourLabelFormat: widget.hourLabelFormat,
        zone: widget.store.zone,
        locked: _locked,
        onChanged: _scheduleChanged,
      ),
    );
    final itemCard = _card(
      formItemCardKey,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < itemFields.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 12.0),
            itemFields[index],
          ],
        ],
      ),
    );
    // The sheet's own colour, which the summary's strip paints so that the
    // item card scrolls out of sight under it.
    final sheetColor =
        Material.of(context).color ??
        Theme.of(context).colorScheme.surfaceContainerLow;
    return PopScope(
      canPop: !_saving,
      child: _KeyboardInset(
        child: Padding(
          padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  heading,
                  style: const TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.w600,
                    color: HarborColors.text,
                  ),
                ),
              ),
              // The page's padding lies inside its scroll view, so a drag
              // anywhere across the sheet's width scrolls it. The view
              // shrink-wraps, so the sheet is no taller than its page. The
              // summary's strip holds the 12-pixel gaps above and below its
              // card, and pins at the page's top while it takes at most
              // half of the page.
              Flexible(
                child: CustomScrollView(
                  shrinkWrap: true,
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          24.0,
                          12.0,
                          24.0,
                          0.0,
                        ),
                        child: schedulingCard,
                      ),
                    ),
                    FittingPinnedHeaderSliver(
                      child: ColoredBox(
                        color: sheetColor,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 12.0,
                          ),
                          child: summaryCard,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          24.0,
                          0.0,
                          24.0,
                          12.0,
                        ),
                        child: itemCard,
                      ),
                    ),
                  ],
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 8.0),
                  child: Text(
                    message,
                    style: const TextStyle(color: HarborColors.error),
                  ),
                ),
              // Stacks the actions where a narrow screen cannot fit them in
              // a row.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: OverflowBar(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [child] padded by the keyboard's bottom inset. It alone reads the inset,
/// so a keyboard that slides in or out rebuilds it and not the form, whose
/// open time picker asks its `isEnabled` of every time again as it is
/// rebuilt.
class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}
