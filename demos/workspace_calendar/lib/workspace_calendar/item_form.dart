/// The calendar's create flow, its item form, which also shows an item
/// read-only, and the delete confirmation.
///
/// The form opens in a modal bottom sheet: a heading ([ScheduleHeading]),
/// which writes the schedule's length after the form's title and its zone at
/// the sheet's top right, over a scrolling page of the schedule section,
/// which every item type shares and which edits a [CalendarSchedule], the
/// overlap notice ([ScheduleOverlapNotice]) while the schedule overlaps
/// other entries, and the item's own fields, generated from the item type's
/// schema. The page's parts lie on the sheet with no card around them, at
/// the page's margins, and nothing on it stays in place as it scrolls. Once
/// the page has scrolled the Start row wholly out of its view, a
/// summary of the schedule's days and times ([ScheduleSummary]) grows in
/// under the heading, the page's view then starting under it and what the
/// page shows staying where it lies, and it shrinks out as soon as any of
/// the row comes back; while the page scrolls itself, as to a message, the
/// summary waits for that scroll's end. The
/// heading and the notice show what the schedule's [CalendarScheduleCheck]
/// answers. The check is made again
/// at each edit, at each change of the store that moves the entries over
/// the schedule's days, the store's zone or its hours, and at the start of
/// each minute. The start's and the end's messages ([scheduleErrorsOf])
/// follow the check from the form's opening; an overlap the rules refuse
/// shows in the notice, not as a message. Save sends nothing while the
/// check names a problem or the validator the API runs refuses the item;
/// after a failed Save the title's and the type fields' messages show too,
/// following the edits, and the page scrolls the first field with a
/// message, or the notice of a refused overlap, into view, which takes the
/// focus where it takes text.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show clampDouble, listEquals;
import 'package:flutter/gestures.dart'
    show GestureRecognizer, VerticalDragGestureRecognizer;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollDirection;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_api.dart';
import 'calendar_api_source.dart';
import 'calendar_item.dart';
import 'calendar_settings.dart';
import 'calendar_schema.dart';
import 'harbor_theme.dart';
import 'schedule_section.dart';

/// The key of the form's scheduling part, which holds the
/// [ScheduleSection], with no card around it.
const ValueKey<String> formSchedulingCardKey = ValueKey<String>(
  "form-scheduling-card",
);

/// The key of the form's item part, which holds the item's type, title and
/// type fields, with no card around them.
const ValueKey<String> formItemCardKey = ValueKey<String>("form-item-card");

/// Opens the form for a new item over the range [range] picked, with All
/// day on for an all-day range, its type chosen in the form, Task first;
/// its Save [policy] checks at the time [now] reads then, its times step
/// by [slotMinutes], and it writes them on [hourLabelFormat]'s clock. Its
/// rows' day pickers badge the days with entries of [store] as
/// [dayBadges] marks them, or with one primary dot where it is null, and
/// start their weeks on the weekday column [firstColumn], 0 for Monday to
/// 6 for Sunday. Completes when the form closes, whether or not an item
/// was created.
Future<void> showCreateFlow(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CalendarCreateRange range,
  required CalendarEditPolicy<ItemPayload> policy,
  required ValueGetter<CalendarNow> now,
  required CalendarHourLabelFormat hourLabelFormat,
  int slotMinutes = CalendarDates.defaultSlotMinutes,
  CalendarDayBadges<ItemPayload>? dayBadges,
  int firstColumn = 0,
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
    dayBadges: dayBadges,
    firstColumn: firstColumn,
  );
}

/// Opens the form for the stored item [id], whose Save [policy] checks at
/// the time [now] reads then, whose times step by [slotMinutes], and which
/// writes them on [hourLabelFormat]'s clock. Of an item [policy], when the
/// form opens, lets neither move nor resize its start, the Start row and
/// All day take no input; and the form offers Delete only where [policy]
/// then lets the item be deleted. Its rows' day pickers badge the days as
/// [dayBadges] marks them and start their weeks
/// on [firstColumn], as [showCreateFlow]'s do. Does nothing when the store
/// does not hold it.
Future<void> showEditForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required String id,
  required CalendarEditPolicy<ItemPayload> policy,
  required ValueGetter<CalendarNow> now,
  required CalendarHourLabelFormat hourLabelFormat,
  int slotMinutes = CalendarDates.defaultSlotMinutes,
  CalendarDayBadges<ItemPayload>? dayBadges,
  int firstColumn = 0,
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
    dayBadges: dayBadges,
    firstColumn: firstColumn,
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

/// Asks whether to delete an item, in a dialog that comes in and leaves
/// as [HarborMotion.dialog]. True when Delete was pressed.
Future<bool> confirmDelete(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    animationStyle: HarborMotion.of(context, HarborMotion.dialog),
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
/// first problem of each key giving its message. A refused overlap
/// ([CalendarScheduleOverlapRefused]) gives none: the overlap notice
/// ([ScheduleOverlapNotice]) states it.
Map<String, String> scheduleErrorsOf(
  Iterable<CalendarScheduleProblem> problems,
) {
  final errors = <String, String>{};
  for (final problem in problems) {
    if (problem is CalendarScheduleOverlapRefused) {
      continue;
    }
    errors.putIfAbsent(problem.atEnd ? "end" : "start", () {
      return scheduleProblemMessage(problem);
    });
  }
  return errors;
}

/// Opens the form for [item] in a sheet that comes in and leaves as a
/// surface ([HarborMotion.surface]).
Future<void> _showForm(
  BuildContext context, {
  required CalendarStore<ItemPayload> store,
  required CalendarItem item,
  required CalendarHourLabelFormat hourLabelFormat,
  bool readOnly = false,
  CalendarEditPolicy<ItemPayload>? policy,
  ValueGetter<CalendarNow>? now,
  int slotMinutes = CalendarDates.defaultSlotMinutes,
  CalendarDayBadges<ItemPayload>? dayBadges,
  int firstColumn = 0,
}) {
  // The barrier does not close the sheet. Cancel, Save, Delete, a drag down
  // and the back gesture do, the last through the form's PopScope; a drag
  // closes it through the sheet's onClosing, which no PopScope stops, so
  // the form claims vertical drags while a save is in flight.
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    sheetAnimationStyle: HarborMotion.of(context, HarborMotion.surface),
    builder: (context) {
      return _ItemForm(
        store: store,
        item: item,
        readOnly: readOnly,
        policy: policy ?? const UnrestrictedEditPolicy<ItemPayload>(),
        now: now ?? _clockNow,
        hourLabelFormat: hourLabelFormat,
        slotMinutes: slotMinutes,
        dayBadges: dayBadges,
        firstColumn: firstColumn,
      );
    },
  );
}

/// The length of the times an all-day item takes when All day is turned
/// off: an hour.
const int _timedLengthMinutes = 60;

/// The room the form's text fields keep around their caret as they scroll
/// it into view on taking the focus ([TextField.scrollPadding]), which
/// [_ItemFormState._revealFirstError] keeps around the field it reveals, so
/// that reveal of the caret, made as the field then takes the focus, has
/// nothing to scroll; where selection handles show, it may scroll on to
/// make room under them.
const EdgeInsets _revealPadding = EdgeInsets.all(20.0);

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
    required this.dayBadges,
    required this.firstColumn,
  });

  final CalendarStore<ItemPayload> store;
  final CalendarItem item;

  /// The kinds of entry the day pickers' badges mark; null for one primary
  /// dot on a day with entries.
  final CalendarDayBadges<ItemPayload>? dayBadges;

  /// The weekday column the day pickers' weeks start on.
  final int firstColumn;

  /// The step of the time pickers' times.
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

  /// The focus nodes of the fields of [_texts], by key.
  final Map<String, FocusNode> _textFocus = <String, FocusNode>{};

  /// The keys of the schema's fields, by key, which [_revealFirstError]
  /// scrolls into view; new for each type.
  final Map<String, GlobalKey> _fieldKeys = <String, GlobalKey>{};

  final GlobalKey<ScheduleSectionState> _sectionKey =
      GlobalKey<ScheduleSectionState>();

  /// Whether the schedule's summary shows under the heading: once the
  /// Start row has scrolled wholly out of the page's view.
  bool _summaryShown = false;

  /// Whether a [_placeSummary] waits for the end of a frame.
  bool _summaryQueued = false;

  /// The controller of the page's scroll view, whose offset the summary
  /// moves as it comes and goes.
  final ScrollController _page = ScrollController();
  final GlobalKey _noticeKey = GlobalKey(debugLabel: "Overlap notice");
  final GlobalKey _titleKey = GlobalKey(debugLabel: "Title");
  final FocusNode _titleFocus = FocusNode(debugLabel: "Title");

  /// The values of the schema's choice and bool fields, by key.
  final Map<String, Object?> _values = <String, Object?>{};

  /// The schedule's check, which the summary and the section read: made in
  /// [initState] and again by [_recheck] only.
  late CalendarScheduleCheck<ItemPayload> _scheduleCheck;

  /// What [_checkNow] read of the store for [_scheduleCheck], the last check
  /// it made: the entries it gave the check as its others, and the store's
  /// zone and hours, which the form's build reads.
  List<CalendarEntry<ItemPayload>> _checkedOthers =
      const <CalendarEntry<ItemPayload>>[];
  Location? _checkedZone;
  CalendarDayHours? _checkedHours;

  /// The errors [_errorsOf] finds of [_scheduleCheck] and the form's item,
  /// made at the first read after each [_recheck].
  Map<String, String>? _liveErrors;

  /// Whether a Save failed, by a failed validation or a refused send, so
  /// that the title's and the type fields' messages show, following the
  /// edits.
  bool _saveFailed = false;

  /// A refused send's messages of the title, the start, the end and the
  /// type's fields, keyed as the validator keys them, each shown until an
  /// edit changes what it reads. Replaced, never changed in place.
  Map<String, String> _refusal = const <String, String>{};

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
    _dropRefusalOnEdit(_title, "title");
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
    for (final node in _textFocus.values) {
      node.dispose();
    }
    _texts.clear();
    _textFocus.clear();
    _values.clear();
    _fieldKeys.clear();
    final values = withFieldDefaults(_type, fields);
    for (final field in _schema.fields) {
      _fieldKeys[field.key] = GlobalKey(debugLabel: field.label);
      final value = values[field.key];
      switch (field.kind) {
        case FieldKind.choice:
        case FieldKind.boolean:
          _values[field.key] = value;
        case FieldKind.text:
        case FieldKind.longText:
        case FieldKind.url:
          _addText(field, value is String ? value : "");
        case FieldKind.textList:
          _addText(field, value is List ? value.join(", ") : "");
      }
    }
  }

  /// [field]'s text controller, holding [text], and its focus node.
  void _addText(FieldSpec field, String text) {
    final controller = TextEditingController(text: text);
    _dropRefusalOnEdit(controller, fieldErrorKey(field.key));
    _texts[field.key] = controller;
    _textFocus[field.key] = FocusNode(debugLabel: field.label);
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    widget.store.removeListener(_storeChanged);
    _title.dispose();
    _titleFocus.dispose();
    for (final controller in _texts.values) {
      controller.dispose();
    }
    for (final node in _textFocus.values) {
      node.dispose();
    }
    _page.dispose();
    super.dispose();
  }

  /// Checks the schedule again where the change moves what the check or
  /// the build reads of the store: the entries from the schedule's first
  /// day to the day after its last, compared by `==`, or the store's zone
  /// or hours. So an item another write puts over or off the item's days
  /// shows while the form is open, and a read of other days, as a day
  /// picker browses, checks nothing. Not while a send is in flight, whose
  /// own write notifies before it completes, and which a draft's check
  /// would count as an overlap of its own.
  void _storeChanged() {
    if (_saving) {
      return;
    }
    final store = widget.store;
    if (store.zone == _checkedZone &&
        store.hours == _checkedHours &&
        listEquals(_othersNow(), _checkedOthers)) {
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
  /// their Now and the start's and the end's messages answer as Save's own
  /// check does; but not while a send is in flight, which [_storeChanged]
  /// skips too.
  void _minuteTurned() {
    if (!_saving) {
      setState(_recheck);
    }
    _scheduleMinute();
  }

  /// Has [controller] drop the refusal's message keyed [errorKey] at each
  /// change of its text, and not at a change of its selection alone; the
  /// field's [ListenableBuilder] shows it, rebuilding nothing else.
  void _dropRefusalOnEdit(TextEditingController controller, String errorKey) {
    var text = controller.text;
    controller.addListener(() {
      if (controller.text == text) {
        return;
      }
      text = controller.text;
      if (_refusal.containsKey(errorKey)) {
        _refusal = _without(_refusal, <String>[errorKey]);
      }
    });
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

  /// The entries the store shows from the schedule's first day to the day
  /// after its last, so that the checks the schedule section makes of its
  /// pickers' times, an end moved onto the next day among them, see that
  /// day's entries too.
  List<CalendarEntry<ItemPayload>> _othersNow() {
    return widget.store
        .entriesBetween(
          _schedule.startDay,
          CalendarDates.addDays(_schedule.endDay, 1),
        )
        .map((shown) {
          return shown.entry;
        })
        .toList();
  }

  /// The check of the schedule now, against [_othersNow]; keeps what it
  /// read of the store as [_checkedOthers], [_checkedZone] and
  /// [_checkedHours]. Each check it makes becomes [_scheduleCheck].
  CalendarScheduleCheck<ItemPayload> _checkNow() {
    final store = widget.store;
    final others = _othersNow();
    _checkedOthers = others;
    _checkedZone = store.zone;
    _checkedHours = store.hours;
    return CalendarScheduleCheck<ItemPayload>(
      schedule: _schedule,
      rules: _rules,
      now: widget.now(),
      others: others,
      entry: _isDraft ? null : widget.item,
      options: scheduleOptionsOf(_type),
    );
  }

  /// The item the form holds, as an envelope: its schedule's times on the
  /// store's clock, as [itemTimeText] writes them; a time the clock skips
  /// as its own local text, which the validator then reports.
  Map<String, Object?> _envelope() {
    final fields = <String, Object?>{
      for (final field in _schema.fields) field.key: ?_fieldValue(field),
    };
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

  /// The value of [field] in the form, as the envelope holds it: null where
  /// the envelope leaves it out, as it does an empty text or list.
  Object? _fieldValue(FieldSpec field) {
    switch (field.kind) {
      case FieldKind.choice:
      case FieldKind.boolean:
        return _values[field.key];
      case FieldKind.text:
      case FieldKind.longText:
      case FieldKind.url:
        final text = _texts[field.key]!.text;
        return text.isEmpty ? null : text;
      case FieldKind.textList:
        final entries = <String>[
          for (final part in _texts[field.key]!.text.split(","))
            if (part.trim().isNotEmpty) part.trim(),
        ];
        return entries.isEmpty ? null : entries;
    }
  }

  /// The errors of [json], the form's item as an envelope, under [check],
  /// keyed as the validator keys them: the validator's, the check's
  /// ([scheduleErrorsOf]), and where the hours refuse the times, their own
  /// words, as the store's refusal of them reads. Save's errors, and the
  /// live start and end messages.
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
  /// closes on success. A failed validation or a send refused with field
  /// errors reveals the first field with a message.
  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final json = _envelope();
    final check = _checkNow();
    final errors = _errorsOf(check, json);
    // A refused overlap has no field's message, so the check's own answer
    // stops the send too.
    if (errors.isNotEmpty || !check.admitted) {
      setState(() {
        _scheduleCheck = check;
        _liveErrors = null;
        _saveFailed = true;
        _refusal = const <String, String>{};
        _message = null;
      });
      _revealFirstErrorAfterFrame();
      return;
    }
    setState(() {
      _scheduleCheck = check;
      _liveErrors = null;
      _saving = true;
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
            _refusal = <String, String>{
              for (final key in <String>[
                "title",
                "start",
                "end",
                for (final field in _schema.fields) fieldErrorKey(field.key),
              ])
                key: ?fieldErrors[key],
            };
          } else {
            _message = writeFailureMessage(error);
          }
          // The store may have changed while the send was in flight.
          _recheck();
        });
        if (fieldErrors != null) {
          _revealFirstErrorAfterFrame();
        }
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Asks first; a confirmed delete closes the form and then deletes,
  /// and the messenger the form showed under says why where it fails, in
  /// a snack bar that comes in and leaves as a surface
  /// ([HarborMotion.surface]).
  Future<void> _delete() async {
    final confirmed = await confirmDelete(context);
    if (!confirmed || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final snackBarMotion = HarborMotion.of(context, HarborMotion.surface);
    Navigator.of(context).pop();
    try {
      await widget.store.requestDelete(widget.item.id!);
    } on Object catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(writeFailureMessage(error))),
          snackBarAnimationStyle: snackBarMotion,
        );
    }
  }

  /// A new item's type: the details reset to [type]'s defaults, with no
  /// message of the refusal, the title and the schedule kept.
  void _selectType(CalendarItemType type) {
    if (type == _type) {
      return;
    }
    setState(() {
      _refusal = _without(_refusal, <String>[
        for (final field in _schema.fields) fieldErrorKey(field.key),
      ]);
      _type = type;
      _initFields(const <String, Object?>{});
      _recheck();
    });
  }

  /// The title's message: the refusal's, or after a failed Save the title
  /// rule's of the text now ([titleErrorOf]).
  String? _titleError() {
    return _refusal["title"] ??
        (_saveFailed ? titleErrorOf(_title.text) : null);
  }

  /// The start's and the end's messages, each the refusal's, or that of
  /// [_errorsOf] of the check and the item now.
  Map<String, String> _scheduleErrors() {
    final errors = <String, String>{};
    for (final key in const <String>["start", "end"]) {
      final message =
          _refusal[key] ??
          (_liveErrors ??= _errorsOf(_scheduleCheck, _envelope()))[key];
      if (message != null) {
        errors[key] = message;
      }
    }
    return errors;
  }

  /// [field]'s message: the refusal's, or after a failed Save that of its
  /// value now ([fieldErrorOf]).
  String? _fieldError(FieldSpec field) {
    return _refusal[fieldErrorKey(field.key)] ??
        (_saveFailed ? fieldErrorOf(field, _fieldValue(field)) : null);
  }

  /// Sets [field]'s value to [value], dropping the refusal's message of it.
  void _setValue(FieldSpec field, Object? value) {
    setState(() {
      _values[field.key] = value;
      _refusal = _without(_refusal, <String>[fieldErrorKey(field.key)]);
    });
  }

  /// The control for one schema field, by its kind, under its key in
  /// [_fieldKeys]. A text field's message follows each keystroke, which
  /// rebuilds that field alone.
  Widget _fieldFor(FieldSpec field) {
    final Widget control;
    switch (field.kind) {
      case FieldKind.choice:
        final value = _values[field.key];
        control = DropdownButtonFormField<String>(
          key: ValueKey<String>("${_type.id}.${field.key}"),
          initialValue: value is String ? value : null,
          decoration: InputDecoration(
            labelText: field.label,
            errorText: _fieldError(field),
          ),
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
                  _setValue(field, choice);
                },
        );
      case FieldKind.text:
      case FieldKind.url:
      case FieldKind.textList:
      case FieldKind.longText:
        final controller = _texts[field.key]!;
        final long = field.kind == FieldKind.longText;
        control = ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            return TextField(
              controller: controller,
              focusNode: _textFocus[field.key],
              scrollPadding: _revealPadding,
              enabled: !_locked,
              minLines: long ? 2 : null,
              maxLines: long ? 4 : 1,
              keyboardType: field.kind == FieldKind.url
                  ? TextInputType.url
                  : null,
              decoration: InputDecoration(
                labelText: field.label,
                helperText: field.kind == FieldKind.textList
                    ? "Separate names with commas"
                    : null,
                errorText: _fieldError(field),
              ),
            );
          },
        );
      case FieldKind.boolean:
        final value = _values[field.key];
        final error = _fieldError(field);
        control = SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          subtitle: error == null
              ? null
              : Text(error, style: const TextStyle(color: HarborColors.error)),
          value: value == true,
          onChanged: _locked
              ? null
              : (on) {
                  _setValue(field, on);
                },
        );
    }
    return KeyedSubtree(key: _fieldKeys[field.key], child: control);
  }

  /// Places the schedule's summary after a frame in which the page
  /// scrolled or its extent or view changed; a scroll inside the page, as
  /// of a picker's strip, moves nothing the summary reads.
  bool _pageNotified(Notification notification) {
    if (notification is ViewportNotificationMixin &&
        notification.depth == 0 &&
        (notification is ScrollNotification ||
            notification is ScrollMetricsNotification) &&
        !_summaryQueued) {
      _summaryQueued = true;
      SchedulerBinding.instance
        ..addPostFrameCallback((timeStamp) {
          _summaryQueued = false;
          _placeSummary();
        })
        ..ensureVisualUpdate();
    }
    return false;
  }

  /// Shows the schedule's summary where the Start row lies wholly above
  /// the page's view, and hides it where any of the row shows;
  /// while the page scrolls by no drag, as a reveal animates it, places
  /// nothing until that scroll ends, as an animated scroll would undo the
  /// summary's move of the offset ([ScheduleSummary]).
  void _placeSummary() {
    if (!mounted) {
      return;
    }
    if (_page.hasClients) {
      final position = _page.position;
      if (position.isScrollingNotifier.value &&
          position.userScrollDirection == ScrollDirection.idle) {
        return;
      }
    }
    final field = _sectionKey.currentState?.startRowContext?.findRenderObject();
    if (field is! RenderBox || !field.attached || !field.hasSize) {
      return;
    }
    final view = RenderAbstractViewport.maybeOf(field);
    if (view == null) {
      return;
    }
    final bottom = field
        .localToGlobal(Offset(0.0, field.size.height), ancestor: view)
        .dy;
    final shown = bottom <= 0.0;
    if (shown != _summaryShown) {
      setState(() {
        _summaryShown = shown;
      });
    }
  }

  /// The field the first message shows on, in the page's order, the start's
  /// or the end's field, the overlap notice where it names an overlap the
  /// rules refuse, the title, then the type's fields, and the node that
  /// takes the focus there, where it takes text; null where none shows or
  /// its field is not built.
  ({BuildContext field, FocusNode? focus})? _firstError() {
    final scheduleErrors = _scheduleErrors();
    for (final key in const <String>["start", "end"]) {
      if (scheduleErrors.containsKey(key)) {
        final field = _sectionKey.currentState?.errorFieldOf(key);
        return field == null ? null : (field: field, focus: null);
      }
    }
    if (_scheduleCheck.problems.any((problem) {
      return problem is CalendarScheduleOverlapRefused;
    })) {
      final notice = _noticeKey.currentContext;
      return notice == null ? null : (field: notice, focus: null);
    }
    if (_titleError() != null) {
      final field = _titleKey.currentContext;
      return field == null ? null : (field: field, focus: _titleFocus);
    }
    for (final spec in _schema.fields) {
      if (_fieldError(spec) != null) {
        final field = _fieldKeys[spec.key]!.currentContext;
        return field == null
            ? null
            : (field: field, focus: _textFocus[spec.key]);
      }
    }
    return null;
  }

  /// Runs [_revealFirstError] after the frame, once the messages that the
  /// frame shows have their room.
  void _revealFirstErrorAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _revealFirstError();
      }
    });
  }

  /// Scrolls the page the least that shows the field of [_firstError],
  /// with [_revealPadding] around it, or its leading edge where the view
  /// cannot hold it, over the [CalendarTheme]'s motion, or at once where the
  /// platform asks for no animations; and then gives the field the focus
  /// where it takes text.
  Future<void> _revealFirstError() async {
    final first = _firstError();
    final box = first?.field.findRenderObject();
    if (first == null || box == null) {
      return;
    }
    final position = Scrollable.of(first.field).position;
    final viewport = RenderAbstractViewport.of(box);
    final rect = _revealPadding.inflateRect(box.paintBounds);
    final leading = viewport.getOffsetToReveal(box, 0.0, rect: rect).offset;
    final trailing = viewport.getOffsetToReveal(box, 1.0, rect: rect).offset;
    final pixels = position.pixels;
    var target = pixels;
    if (pixels > leading || trailing > leading) {
      target = leading;
    } else if (pixels < trailing) {
      target = trailing;
    }
    target = clampDouble(
      target,
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != pixels) {
      if (MediaQuery.disableAnimationsOf(context)) {
        position.jumpTo(target);
      } else {
        final theme = CalendarTheme.of(context);
        await position.animateTo(
          target,
          duration: theme.motionDuration,
          curve: theme.motionCurve,
        );
      }
    }
    if (first.field.mounted) {
      first.focus?.requestFocus();
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
    final itemFields = <Widget>[
      if (_isDraft && !widget.readOnly) _typeSelector() else _typeRow(),
      // A keystroke rebuilds the title alone, whose message follows it.
      ListenableBuilder(
        listenable: _title,
        builder: (context, child) {
          return TextField(
            key: _titleKey,
            controller: _title,
            focusNode: _titleFocus,
            scrollPadding: _revealPadding,
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
    final schedulingCard = KeyedSubtree(
      key: formSchedulingCardKey,
      child: ScheduleSection(
        key: _sectionKey,
        check: _scheduleCheck,
        hours: widget.store.hours,
        slotMinutes: widget.slotMinutes,
        hourLabelFormat: widget.hourLabelFormat,
        now: widget.now,
        store: widget.store,
        dayBadges: widget.dayBadges,
        firstColumn: widget.firstColumn,
        locked: _locked,
        errors: _scheduleErrors(),
        onChanged: _scheduleChanged,
      ),
    );
    final itemCard = KeyedSubtree(
      key: formItemCardKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < itemFields.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 12.0),
            itemFields[index],
          ],
        ],
      ),
    );
    return PopScope(
      canPop: !_saving,
      // While a save is in flight the form claims each vertical drag on it,
      // so the sheet's own drag, which would close the sheet and drop the
      // save's outcome, never starts. Its recognizer is of the sheet's kind,
      // with the same default slop, and lies deeper, so it hears each move
      // first and wins the gesture arena.
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
          if (_saving)
            VerticalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  VerticalDragGestureRecognizer
                >(
                  () {
                    return VerticalDragGestureRecognizer(debugOwner: this);
                  },
                  (VerticalDragGestureRecognizer recognizer) {
                    recognizer.onStart = (details) {};
                  },
                ),
        },
        child: _KeyboardInset(
          child: Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ScheduleHeading(
                    title: heading,
                    check: _scheduleCheck,
                    zone: widget.store.zone,
                  ),
                ),
                // The page's padding lies inside its scroll view, so a drag
                // anywhere across the sheet's width scrolls it. The view is
                // no taller than its page, so the sheet is no taller than
                // its contents.
                Flexible(
                  child: ScheduleSummary(
                    check: _scheduleCheck,
                    hourLabelFormat: widget.hourLabelFormat,
                    shown: _summaryShown,
                    controller: _page,
                    child: NotificationListener<Notification>(
                      onNotification: _pageNotified,
                      child: SingleChildScrollView(
                        controller: _page,
                        padding: const EdgeInsets.fromLTRB(
                          24.0,
                          12.0,
                          24.0,
                          12.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            schedulingCard,
                            ScheduleOverlapNotice(
                              key: _noticeKey,
                              check: _scheduleCheck,
                              hourLabelFormat: widget.hourLabelFormat,
                              zone: widget.store.zone,
                              locked: _locked,
                              padding: const EdgeInsets.only(top: 12.0),
                              onChanged: _scheduleChanged,
                            ),
                            const SizedBox(height: 12.0),
                            itemCard,
                          ],
                        ),
                      ),
                    ),
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
                // Delete lies at the row's start, the other actions at its
                // end. Where a narrow screen cannot fit them in a row, Delete
                // stacks above Cancel and Save, which stack in turn where
                // they alone do not fit.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: OverflowBar(
                    alignment: _deletable
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.end,
                    spacing: 8.0,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: <Widget>[
                      if (_deletable)
                        TextButton(
                          onPressed: _saving ? null : _delete,
                          child: const Text("Delete"),
                        ),
                      if (widget.readOnly)
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text("Close"),
                        )
                      else
                        OverflowBar(
                          spacing: 8.0,
                          overflowAlignment: OverflowBarAlignment.end,
                          children: <Widget>[
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
                                  ? const CalendarActivityIndicator(
                                      size: 16.0,
                                      strokeWidth: 2.0,
                                    )
                                  : const Text("Save"),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
