/// A model of a data source that other clients also change, for a
/// differential fuzz of a [CalendarStore] over it: announcements, reads and
/// writes in flight answered in random orders, failures, retries, zone
/// changes and disposal, each run checked against what the source holds.
/// Every microtask runs in a zone [FuzzRun] drains by hand, so a run is
/// deterministic for its seed.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart'
    show zonedEntryOf;
import 'package:widgets_extended/scheduling/scheduling.dart';

import '../zones.dart';

typedef StoreFactory =
    CalendarStore<String> Function(
      CalendarDataSource<String> source,
      Stream<CalendarSourceChange<String>> changes,
      Location? zone,
      int readAhead,
    );

class SourceFailure implements Exception {
  SourceFailure(this.n);

  final int n;

  @override
  String toString() {
    return "SourceFailure($n)";
  }
}

class PendingRead {
  PendingRead(this.first, this.last, this.snapshot, this.epoch);

  final int first;
  final int last;
  List<CalendarEntry<String>> snapshot;
  final int epoch;
  final Completer<List<CalendarEntry<String>>> completer =
      Completer<List<CalendarEntry<String>>>();
}

enum WriteKind { create, replace, delete }

class PendingWrite {
  PendingWrite(this.kind, {this.entry, this.id});

  final WriteKind kind;
  final CalendarEntry<String>? entry;
  final String? id;
  bool applied = false;
  CalendarEntry<String>? result;
  Object? applyFailure;
  final Completer<CalendarEntry<String>> entryCompleter =
      Completer<CalendarEntry<String>>();
  final Completer<void> voidCompleter = Completer<void>();
  WriteRecord? record;
}

class WriteRecord {
  WriteRecord(this.kind, this.id, this.step);

  final String kind;
  final String? id;
  final int step;
  bool done = false;
  Object? value;
  Object? error;
  bool expectRefusal = false;
  bool expectDisposed = false;
  bool answered = false;
  bool expectAnswerSet = false;
  CalendarEntry<String>? expectedValue;
  Object? expectedError;
}

class Queued {
  Queued.change(this.change) : error = false;
  Queued.error() : change = null, error = true;

  final CalendarSourceChange<String>? change;
  final bool error;
}

class Problem {
  Problem(this.kind, this.detail);

  final String kind;
  final String detail;

  @override
  String toString() {
    return "$kind: $detail";
  }
}

const Color _color = Color(0xFF3060C0);
const List<String> _titles = <String>["A", "B"];

bool coversDays(CalendarEntry<String> entry, int first, int last) {
  return CalendarDates.dayNumber(entry.start) <= last &&
      CalendarDates.lastDayNumberOf(entry.start, entry.end) >= first;
}

class FuzzSource implements CalendarDataSource<String> {
  FuzzSource(this.run);

  final FuzzRun run;
  final Map<String, CalendarEntry<String>> stored =
      <String, CalendarEntry<String>>{};
  final List<PendingRead> reads = <PendingRead>[];
  final List<PendingWrite> writes = <PendingWrite>[];
  final Queue<Queued> announcements = Queue<Queued>();
  int nextId = 1;
  int readCalls = 0;
  int writeCalls = 0;

  /// Each read call in order: its read in flight, or null where it answered
  /// within the call.
  final List<PendingRead?> readLog = <PendingRead?>[];

  /// Whether a write call of the store is under way, within which an own
  /// write's announcement may be delivered ([FuzzOptions.announceWithin]).
  bool inCall = false;

  /// Whether no read answers within its call, as while the quiesce probes.
  bool noSync = false;

  /// The entries the source holds on [a] to [b] now.
  List<CalendarEntry<String>> snapshotOf(int a, int b) {
    return <CalendarEntry<String>>[
      for (final entry in stored.values)
        if (coversDays(entry, a, b)) entry,
    ];
  }

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final a = CalendarDates.dayNumber(first);
    final b = CalendarDates.dayNumber(last);
    final snapshot = <CalendarEntry<String>>[
      for (final entry in stored.values)
        if (coversDays(entry, a, b)) entry,
    ];
    readCalls++;
    if (run.options.syncAnswers && run.rng.nextDouble() < 0.25 && !noSync) {
      run.log("  source.read($a..$b) answers within the call");
      run.count("path:read-answered-within");
      readLog.add(null);
      return SynchronousFuture<List<CalendarEntry<String>>>(snapshot);
    }
    final read = PendingRead(a, b, snapshot, run.epoch);
    reads.add(read);
    readLog.add(read);
    run.log("  source.read($a..$b) epoch ${run.epoch}");
    return read.completer.future;
  }

  /// Whether the last write answered within its call.
  bool lastWriteSync = false;

  /// The answer of the last write answered within its call.
  CalendarEntry<String>? lastSyncResult;

  PendingWrite _add(PendingWrite write) {
    writeCalls++;
    lastWriteSync = false;
    if (run.options.syncAnswers && run.rng.nextDouble() < 0.25) {
      apply(write);
      if (write.applyFailure == null) {
        lastWriteSync = true;
        lastSyncResult = write.result;
        run.log("  ... answered within the call: ${write.result}");
        run.count("path:write-answered-within");
        return write;
      }
    }
    writes.add(write);
    if (run.rng.nextDouble() < 0.15) {
      apply(write);
    }
    return write;
  }

  Future<CalendarEntry<String>> _entryFuture(PendingWrite write) {
    if (lastWriteSync) {
      return SynchronousFuture<CalendarEntry<String>>(write.result!);
    }
    return write.entryCompleter.future;
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    run.log("  source.create(${draft.title})");
    inCall = true;
    try {
      return _entryFuture(_add(PendingWrite(WriteKind.create, entry: draft)));
    } finally {
      inCall = false;
    }
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    run.log("  source.replace($entry)");
    inCall = true;
    try {
      return _entryFuture(
        _add(PendingWrite(WriteKind.replace, entry: entry, id: entry.id)),
      );
    } finally {
      inCall = false;
    }
  }

  @override
  Future<void> delete(String id) {
    run.log("  source.delete($id)");
    inCall = true;
    try {
      final write = _add(PendingWrite(WriteKind.delete, id: id));
      if (lastWriteSync) {
        return SynchronousFuture<void>(null);
      }
      return write.voidCompleter.future;
    } finally {
      inCall = false;
    }
  }

  CalendarEntry<String> _normalized(CalendarEntry<String> entry) {
    if (run.rng.nextDouble() < 0.2) {
      return entry.copyWith(title: entry.title == "A" ? "B" : "A");
    }
    return entry;
  }

  void apply(PendingWrite write) {
    if (write.applied) {
      return;
    }
    write.applied = true;
    switch (write.kind) {
      case WriteKind.create:
        final id = "s${nextId++}";
        final entry = _normalized(write.entry!.copyWith(id: id));
        stored[id] = entry;
        write.result = entry;
        run.log("  source applies create -> $entry");
        announce(null, entry, own: true);
      case WriteKind.replace:
        final id = write.id!;
        final old = stored[id];
        if (old == null) {
          write.applyFailure = SourceFailure(-1);
          run.log("  source applies replace $id: gone");
          return;
        }
        final entry = _normalized(write.entry!);
        stored[id] = entry;
        write.result = entry;
        run.log("  source applies replace -> $entry");
        announce(old, entry, own: true);
      case WriteKind.delete:
        final old = stored.remove(write.id!);
        run.log("  source applies delete ${write.id}");
        if (old != null) {
          announce(old, null, own: true);
        }
    }
  }

  void announce(
    CalendarEntry<String>? old,
    CalendarEntry<String>? entry, {
    bool own = false,
  }) {
    if (run.dropAnnouncements ||
        run.streamMode == 2 ||
        (own && run.streamMode == 3)) {
      return;
    }
    var r = run.rng.nextDouble();
    final within =
        own &&
        inCall &&
        run.options.announceWithin &&
        announcements.isEmpty &&
        run.rng.nextDouble() < 0.6;
    final queuedBefore = announcements.length;
    if (run.streamMode == 1 || run.streamMode == 3) {
      // Mostly changes of days: a change of all marks every day changed,
      // which would hide a stale day from the end-of-run check.
      r = r < 0.92 ? 0.70 : (r < 0.96 ? 0.90 : 0.99);
    }
    if (r < 0.70) {
      announcements.add(
        Queued.change(
          entry == null
              ? CalendarEntryRemoved<String>(old!.id!)
              : CalendarEntryPut<String>(entry),
        ),
      );
    } else if (r < 0.86) {
      var first = 1 << 30;
      var last = -(1 << 30);
      for (final e in <CalendarEntry<String>?>[old, entry]) {
        if (e != null) {
          first = min(first, CalendarDates.dayNumber(e.start));
          last = max(last, CalendarDates.lastDayNumberOf(e.start, e.end));
        }
      }
      announcements.add(
        Queued.change(
          CalendarDaysChanged<String>(
            CalendarDates.dateOfDayNumber(first),
            CalendarDates.dateOfDayNumber(last),
          ),
        ),
      );
    } else if (r < 0.94) {
      announcements.add(Queued.change(const CalendarAllChanged<String>()));
    } else {
      announcements.add(Queued.error());
    }
    if (within && announcements.length == queuedBefore + 1) {
      final queued = announcements.removeLast();
      run.log("  announced within the write call");
      run.count("path:announced-within");
      if (queued.error) {
        run.changes.addError(SourceFailure(0));
      } else {
        run.changes.add(queued.change!);
      }
    }
  }
}

class MicrotaskQueue {
  final Queue<void Function()> queue = Queue<void Function()>();
  final List<Object> uncaught = <Object>[];
  late final Zone zone;

  void drain() {
    var n = 0;
    while (queue.isNotEmpty) {
      if (++n > 1000000) {
        throw StateError("microtask storm");
      }
      queue.removeFirst()();
    }
  }
}

class StoreSnapshot {
  StoreSnapshot(
    this.entries,
    this.status,
    this.error,
    this.read,
    this.failed,
    this.marker,
  );

  final List<CalendarShownEntry<String>> entries;
  final CalendarLoadStatus status;
  final Object? error;
  final List<bool> read;
  final List<bool> failed;
  final List<bool> marker;

  bool sameAs(StoreSnapshot other) {
    return listEquals(entries, other.entries) &&
        status == other.status &&
        identical(error, other.error) &&
        listEquals(read, other.read) &&
        listEquals(failed, other.failed) &&
        listEquals(marker, other.marker);
  }
}

class FuzzOptions {
  const FuzzOptions({
    this.dropAnnouncements = false,
    this.otherClients = true,
    this.allowDispose = true,
    this.allowZones = true,
    this.readFailures = true,
    this.writeFailures = true,
    this.steps = 90,
    this.streamMode,
    this.focus = false,
    this.syncAnswers = false,
    this.lateServe = false,
    this.announceWithin = false,
    this.zoneFocus = false,
  });

  /// Whether a read may be served, its snapshot taken, at any moment
  /// between its send and its answer, not only at its send.
  final bool lateServe;

  /// Whether an own write's announcement may arrive within the store's
  /// write call, before the source answers.
  final bool announceWithin;

  /// Whether every run changes zones, more often, from any first zone.
  final bool zoneFocus;

  /// Whether the source answers some reads and writes within the call.
  final bool syncAnswers;

  /// Weights that favour writes racing reads sent since.
  final bool focus;

  final int? streamMode;

  final bool dropAnnouncements;
  final bool otherClients;
  final bool allowDispose;
  final bool allowZones;
  final bool readFailures;
  final bool writeFailures;
  final int steps;
}

final List<DateTime> _bases = <DateTime>[
  DateTime(2026, 3, 4),
  DateTime(2026, 3, 31),
  DateTime(2026, 10, 28),
  DateTime(2026, 6, 10),
];

List<Location?> fuzzZones() {
  ensureZones();
  return <Location?>[
    null,
    tz.getLocation("America/Havana"),
    tz.getLocation("America/Santiago"),
    tz.getLocation("Asia/Tokyo"),
    tz.getLocation("Pacific/Kiritimati"),
  ];
}

class FuzzRun {
  FuzzRun(this.seed, this.factory, this.options)
    : rng = Random(seed),
      dropAnnouncements = options.dropAnnouncements;

  final int seed;
  final StoreFactory factory;
  final FuzzOptions options;
  final Random rng;
  final bool dropAnnouncements;

  /// 0: every source change announced, mostly as puts and removals; 1: every
  /// change announced as a change of days, of all, or a stream error; 2: a
  /// single writer, this store, and no announcement; 3: as 1 for other
  /// clients' changes, and none for this store's own writes.
  int streamMode = 0;
  final List<String> trace = <String>[];
  final List<Problem> problems = <Problem>[];
  final Map<String, int> counts = <String, int>{};

  late final FuzzSource source = FuzzSource(this);
  late final CalendarStore<String> store;
  final StreamController<CalendarSourceChange<String>> changes =
      StreamController<CalendarSourceChange<String>>.broadcast(sync: true);
  final MicrotaskQueue micro = MicrotaskQueue();
  int epoch = 0;
  Location? zone;
  late List<Location?> zones;
  int readAhead = 0;
  bool zoneChanges = false;
  bool disposed = false;
  int notifications = 0;
  bool anyReadFailed = false;
  int? shownFirst;
  int? shownLast;
  late int u0;
  int uCount = 10;
  bool tight = false;
  final Map<String, ({String kind, CalendarEntry<String>? requested})>
  inFlight = <String, ({String kind, CalendarEntry<String>? requested})>{};
  final List<WriteRecord> records = <WriteRecord>[];
  final List<(Future<void>, List<bool>)> refreshes =
      <(Future<void>, List<bool>)>[];
  final Set<String> knownIds = <String>{};
  int step = 0;

  /// The reads whose failure fails a refresh: a refresh's own, and the read
  /// of the shown range a zone change sends while one waits.
  final Set<PendingRead> refreshReads = <PendingRead>{};

  /// The days a failed read of [refreshReads] covered, since which no read
  /// of this zone has answered and no other read of this zone over them has
  /// failed: a changed day among them is left unmarked, its failure told
  /// to the refresh, until a read answers and the store reads it again.
  final Set<int> refreshFailedDays = <int>{};

  int get vFirst {
    return u0 - 3;
  }

  int get vLast {
    return u0 + uCount + 2;
  }

  void log(String line) {
    trace.add(line);
  }

  void problem(String kind, String detail) {
    problems.add(Problem(kind, "step $step: $detail"));
  }

  void count(String key) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  DateTime date(int day) {
    return CalendarDates.dateOfDayNumber(day);
  }

  void runAll() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      problem("reported", "${details.exception}");
    };
    micro.zone = Zone.current.fork(
      specification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, f) {
          micro.queue.add(() {
            zone.runGuarded(f);
          });
        },
        handleUncaughtError: (self, parent, zone, error, stack) {
          micro.uncaught.add(error);
          problem("uncaught", "$error\n$stack");
        },
      ),
    );
    try {
      micro.zone.run(_body);
    } finally {
      FlutterError.onError = previousOnError;
    }
  }

  void _body() {
    zones = fuzzZones();
    final mode = rng.nextDouble();
    if (options.zoneFocus) {
      zone = zones[rng.nextInt(zones.length)];
      zoneChanges = true;
    } else if (!options.allowZones || mode < 0.4) {
      zone = null;
    } else {
      zone = zones[1 + rng.nextInt(zones.length - 1)];
      zoneChanges = mode > 0.7;
    }
    readAhead = rng.nextInt(3);
    final m = rng.nextDouble();
    streamMode =
        options.streamMode ??
        (m < 0.2 ? 0 : (m < 0.45 ? 1 : (m < 0.65 ? 2 : 3)));
    u0 = CalendarDates.dayNumber(_bases[rng.nextInt(_bases.length)]);
    tight = rng.nextBool();
    if (tight) {
      uCount = 4;
    }
    final initial = tight ? 1 + rng.nextInt(3) : 2 + rng.nextInt(6);
    for (var i = 0; i < initial; i++) {
      final id = "s${source.nextId++}";
      source.stored[id] = randomEntry(id);
    }
    store = factory(source, changes.stream, zone, readAhead);
    store.addListener(() {
      notifications++;
    });
    log(
      "seed $seed zone ${zone?.name} readAhead $readAhead u0 $u0 "
      "zoneChanges $zoneChanges streamMode $streamMode",
    );
    for (step = 0; step < options.steps; step++) {
      _randomStep();
      if (problems.length > 20) {
        return;
      }
      if (!disposed && rng.nextDouble() < 0.06) {
        _quiesceAndCheck(isFinal: false);
      }
    }
    if (!disposed) {
      _quiesceAndCheck(isFinal: true);
    } else {
      _settleAll();
    }
    _checkFuturesDone();
    if (!disposed) {
      store.dispose();
      disposed = true;
    }
    micro.drain();
  }

  CalendarEntry<String> randomEntry(String? id) {
    final day = u0 + rng.nextInt(uCount);
    final d = date(day);
    final title = _titles[rng.nextInt(_titles.length)];
    if (rng.nextDouble() < 0.25) {
      final k = 1 + rng.nextInt(3);
      return CalendarEntry<String>(
        id: id,
        start: d,
        end: date(day + k),
        title: title,
        color: _color,
        payload: "p",
        isAllDay: true,
      );
    }
    final minute = 60 * rng.nextInt(24);
    final start = DateTime(d.year, d.month, d.day, 0, minute);
    const lengths = <int>[60, 120, 600, 1440, 1500, 2880];
    final end = start.add(Duration(minutes: lengths[rng.nextInt(6)]));
    return CalendarEntry<String>(
      id: id,
      start: start,
      end: end,
      title: title,
      color: _color,
      payload: "p",
    );
  }

  ({int first, int last}) randomRange({int maxLength = 7}) {
    final length = 1 + rng.nextInt(min(maxLength, uCount));
    final first = u0 + rng.nextInt(uCount - length + 1);
    return (first: first, last: first + length - 1);
  }

  StoreSnapshot snap() {
    return StoreSnapshot(
      store.entriesBetween(date(vFirst), date(vLast)),
      store.status,
      store.loadError,
      <bool>[for (var d = vFirst; d <= vLast; d++) store.isRead(date(d))],
      <bool>[for (var d = vFirst; d <= vLast; d++) store.readFailed(date(d))],
      <bool>[
        for (var d = vFirst; d <= vLast; d++) store.dayHasShownEntries(date(d)),
      ],
    );
  }

  /// Runs [action] as one call into the store and checks the notification
  /// promises and the invariants after it.
  void _call(String name, void Function() action) {
    log("[$step] $name");
    final before = disposed ? null : snap();
    notifications = 0;
    action();
    micro.drain();
    if (disposed || before == null) {
      if (notifications != 0) {
        problem("notify-after-dispose", name);
      }
      return;
    }
    final after = snap();
    if (notifications > 1) {
      problem("notify-many", "$name notified $notifications times");
    }
    if (!after.sameAs(before) && notifications == 0) {
      problem("notify-missing", "$name changed state without notifying");
    }
    if (after.sameAs(before) && notifications > 0) {
      count("notify-extra:${name.split(RegExp(r"[ (]")).first}");
    }
    _checkInvariants();
  }

  void _checkInvariants() {
    final first = shownFirst;
    final last = shownLast;
    final status = store.status;
    // A mark may stand on a read day, one the store takes to have changed;
    // the quiesce checks that each marked read day is one.
    if (first == null || last == null) {
      if (status != CalendarLoadStatus.loading) {
        problem("status", "no shown range, status $status");
      }
    } else {
      var unread = false;
      var marked = false;
      for (var d = first; d <= last; d++) {
        if (!store.isRead(date(d))) {
          unread = true;
        }
        if (store.readFailed(date(d))) {
          marked = true;
        }
      }
      final expected = marked
          ? CalendarLoadStatus.failed
          : unread
          ? CalendarLoadStatus.loading
          : CalendarLoadStatus.ready;
      if (status != expected) {
        problem("status", "status $status, expected $expected");
      }
      if ((store.loadError != null) != (status == CalendarLoadStatus.failed)) {
        problem("load-error", "loadError ${store.loadError} status $status");
      }
    }
    final shown = store.entriesBetween(date(vFirst), date(vLast));
    for (final entry in shown) {
      if (entry.pending && !inFlight.containsKey(entry.id)) {
        problem("pending-shown", "${entry.id} shown pending with no write");
      }
    }
    for (final id in knownIds) {
      final pending = store.isPending(id);
      final expected = inFlight.containsKey(id);
      if (pending != expected) {
        problem("is-pending", "$id isPending $pending, expected $expected");
      }
    }
    for (final MapEntry(key: id, value: write) in inFlight.entries) {
      final withId = <CalendarShownEntry<String>>[
        for (final entry in shown)
          if (entry.id == id) entry,
      ];
      CalendarEntry<String>? expected;
      if (write.kind == "move") {
        expected = zonedEntryOf(write.requested!, zone);
      } else {
        expected = store.storedEntry(id);
      }
      if (expected == null) {
        if (withId.isNotEmpty) {
          problem("pending-entry", "$id shows $withId, expected none");
        }
      } else if (withId.length != 1 ||
          !withId.single.pending ||
          withId.single.entry != expected) {
        problem(
          "pending-entry",
          "$id (${write.kind}) shows $withId, expected $expected pending",
        );
      }
    }
  }

  void _randomStep() {
    final f = this.options.focus;
    final options = <(double, void Function())>[
      (f ? 3 : 8, _show),
      (f ? 8 : 4, _prefetch),
      (f ? 1 : 3, _retry),
      (f ? 8 : 3, _invalidate),
      (f ? 1 : 2, _refresh),
      (f ? 2 : 4, _create),
      (
        f ? 6 : 4,
        () {
          _replace(move: false);
        },
      ),
      (
        f ? 6 : 4,
        () {
          _replace(move: true);
        },
      ),
      (f ? 4 : 3, _delete),
      if (this.options.otherClients && streamMode != 2) (8, _otherClient),
      if (source.announcements.isNotEmpty) (10, _deliver),
      if (source.reads.isNotEmpty)
        (
          14,
          () {
            _answerRead(mayFail: true);
          },
        ),
      if (source.writes.any((write) {
        return !write.applied;
      }))
        (5, _applyWrite),
      if (source.writes.isNotEmpty)
        (
          8,
          () {
            _answerWrite(mayFail: true);
          },
        ),
      if (zoneChanges) (this.options.zoneFocus ? 6 : 2, _changeZone),
      if (this.options.lateServe && source.reads.isNotEmpty) (6, _serveRead),
      if (this.options.allowDispose && !disposed) (0.15, _dispose),
    ];
    var total = 0.0;
    for (final option in options) {
      total += option.$1;
    }
    var r = rng.nextDouble() * total;
    for (final option in options) {
      r -= option.$1;
      if (r <= 0) {
        option.$2();
        return;
      }
    }
    options.last.$2();
  }

  void _show() {
    final range = randomRange();
    final same = range.first == shownFirst && range.last == shownLast;
    _call("show(${range.first}..${range.last})", () {
      store.show(date(range.first), date(range.last));
      if (!disposed) {
        shownFirst = range.first;
        shownLast = range.last;
      }
    });
    if (disposed) {
      return;
    }
    if (!same) {
      _checkRequested(range.first - readAhead, range.last + readAhead, "show");
    }
  }

  /// After a show, a retry or a refresh: no day of [first] to [last] is
  /// marked, and every unread shown day is under a read in flight.
  void _checkRequested(int first, int last, String name) {
    for (var d = first; d <= last; d++) {
      if (store.readFailed(date(d))) {
        problem("mark-after-request", "$name left day $d marked");
      }
    }
    final sf = shownFirst;
    final sl = shownLast;
    if (sf == null || sl == null) {
      return;
    }
    for (var d = max(first, sf); d <= min(last, sl); d++) {
      if (store.isRead(date(d))) {
        continue;
      }
      final covered = source.reads.any((read) {
        return read.epoch == epoch && read.first <= d && d <= read.last;
      });
      if (!covered) {
        problem("unread-uncovered", "$name left unread day $d with no read");
      }
    }
  }

  void _prefetch() {
    final range = randomRange(maxLength: 10);
    _call("prefetch(${range.first}..${range.last})", () {
      store.prefetch(date(range.first), date(range.last));
    });
  }

  void _retry() {
    if (rng.nextBool()) {
      _call("retry()", () {
        store.retry();
      });
      final sf = shownFirst;
      final sl = shownLast;
      if (!disposed && sf != null && sl != null) {
        _checkRequested(sf - readAhead, sl + readAhead, "retry");
      }
    } else {
      final range = randomRange();
      _call("retry(${range.first}..${range.last})", () {
        store.retry(date(range.first), date(range.last));
      });
      final sf = shownFirst;
      final sl = shownLast;
      if (!disposed) {
        if (sf != null && sl != null) {
          _checkRequested(sf - readAhead, sl + readAhead, "retry");
        }
        _checkRequested(range.first, range.last, "retry(given)");
      }
    }
  }

  void _invalidate() {
    final range = randomRange();
    _call("invalidate(${range.first}..${range.last})", () {
      store.invalidate(date(range.first), date(range.last));
    });
  }

  void _refresh() {
    late Future<void> future;
    final done = <bool>[false];
    final logged = source.readLog.length;
    _call("refresh()", () {
      future = store.refresh();
      future.then(
        (_) {
          done[0] = true;
        },
        onError: (Object error) {
          done[0] = true;
        },
      );
    });
    refreshes.add((future, done));
    if (source.readLog.length > logged) {
      final read = source.readLog[logged];
      if (read != null) {
        refreshReads.add(read);
      }
    }
    final sf = shownFirst;
    final sl = shownLast;
    if (!disposed && sf != null && sl != null) {
      _checkRequested(sf, sl, "refresh");
    }
  }

  WriteRecord _record(String kind, String? id, Future<Object?> future) {
    final record = WriteRecord(kind, id, step);
    records.add(record);
    future.then(
      (value) {
        if (record.done) {
          problem("completed-twice", "$kind $id");
        }
        record.done = true;
        record.value = value;
      },
      onError: (Object error) {
        if (record.done) {
          problem("completed-twice", "$kind $id");
        }
        record.done = true;
        record.error = error;
      },
    );
    return record;
  }

  void _create() {
    final draft = randomEntry(null);
    final calls = source.writeCalls;
    late WriteRecord record;
    _call("create(${draft.title})", () {
      record = _record("create", null, store.create(draft));
    });
    if (source.writeCalls > calls) {
      if (source.lastWriteSync) {
        _checkSyncWrite(record);
      } else {
        source.writes.last.record = record;
      }
    }
    _afterWriteCall(record, calls);
  }

  void _afterWriteCall(WriteRecord record, int calls) {
    if (disposed) {
      record.expectDisposed = true;
      if (source.writeCalls != calls) {
        problem("write-after-dispose-sent", record.kind);
      }
      if (!record.done || record.error is! StateError) {
        problem(
          "write-after-dispose",
          "${record.kind} done ${record.done} error ${record.error}",
        );
      }
    }
  }

  String? _targetId({bool allowPending = true}) {
    if (disposed && rng.nextBool()) {
      return knownIds.isEmpty ? "s1" : knownIds.first;
    }
    final held = <String>{
      for (final entry in store.entriesBetween(date(vFirst), date(vLast)))
        entry.id,
    };
    knownIds.addAll(held);
    knownIds.addAll(source.stored.keys);
    final r = rng.nextDouble();
    if (allowPending && r < 0.1 && inFlight.isNotEmpty) {
      return inFlight.keys.elementAt(rng.nextInt(inFlight.length));
    }
    if (r < 0.15 && source.stored.isNotEmpty) {
      return source.stored.keys.elementAt(rng.nextInt(source.stored.length));
    }
    if (held.isEmpty) {
      return null;
    }
    return held.elementAt(rng.nextInt(held.length));
  }

  void _replace({required bool move}) {
    final id = _targetId();
    if (id == null) {
      return;
    }
    knownIds.add(id);
    final entry = randomEntry(id);
    final kind = move ? "move" : "update";
    final calls = source.writeCalls;
    final refused = inFlight.containsKey(id);
    late WriteRecord record;
    _call("$kind($entry)", () {
      record = _record(
        kind,
        id,
        move ? store.requestMove(entry) : store.update(entry),
      );
      if (!disposed && !refused && !source.lastWriteSync) {
        inFlight[id] = (kind: kind, requested: move ? entry : null);
      }
    });
    _afterLockCall(record, calls, refused, id);
  }

  void _afterLockCall(WriteRecord record, int calls, bool refused, String id) {
    if (disposed) {
      _afterWriteCall(record, calls);
      return;
    }
    if (refused) {
      record.expectRefusal = true;
      if (source.writeCalls != calls) {
        problem("refused-write-sent", "${record.kind} $id");
      }
      final error = record.error;
      if (!record.done ||
          error is! CalendarWritePendingException ||
          error.id != id) {
        problem("refusal", "${record.kind} $id: ${record.error}");
      }
      return;
    }
    if (source.writeCalls != calls + 1) {
      problem("write-not-sent", "${record.kind} $id");
      inFlight.remove(id);
      return;
    }
    if (source.lastWriteSync) {
      _checkSyncWrite(record);
      return;
    }
    source.writes.last.record = record;
  }

  void _checkSyncWrite(WriteRecord record) {
    if (!record.done) {
      problem("sync-write-not-completed", "${record.kind} ${record.id}");
      return;
    }
    if (record.kind == "delete") {
      if (record.error != null) {
        problem("write-error", "sync delete failed with ${record.error}");
      }
      return;
    }
    final expected = zonedEntryOf(source.lastSyncResult!, zone);
    if (record.value != expected) {
      problem(
        "write-value",
        "sync ${record.kind} completed with ${record.value ?? record.error}, "
            "expected $expected",
      );
    }
  }

  void _delete() {
    final id = _targetId();
    if (id == null) {
      return;
    }
    knownIds.add(id);
    final calls = source.writeCalls;
    final refused = inFlight.containsKey(id);
    late WriteRecord record;
    _call("delete($id)", () {
      record = _record("delete", id, store.requestDelete(id));
      if (!disposed && !refused && !source.lastWriteSync) {
        inFlight[id] = (kind: "delete", requested: null);
      }
    });
    _afterLockCall(record, calls, refused, id);
  }

  void _otherClient() {
    final r = rng.nextDouble();
    if (r < 0.35 || source.stored.isEmpty) {
      final id = "s${source.nextId++}";
      final entry = randomEntry(id);
      log("[$step] other client puts new $entry");
      source.stored[id] = entry;
      source.announce(null, entry);
    } else if (r < 0.8) {
      final targets = <String>[
        for (final id in inFlight.keys)
          if (source.stored.containsKey(id)) id,
      ];
      final id = targets.isNotEmpty && rng.nextBool()
          ? targets[rng.nextInt(targets.length)]
          : source.stored.keys.elementAt(rng.nextInt(source.stored.length));
      final old = source.stored[id]!;
      final entry = rng.nextBool()
          ? randomEntry(id)
          : old.copyWith(title: old.title == "A" ? "B" : "A");
      log("[$step] other client puts $entry");
      source.stored[id] = entry;
      source.announce(old, entry);
    } else {
      final id = source.stored.keys.elementAt(
        rng.nextInt(source.stored.length),
      );
      final old = source.stored.remove(id)!;
      log("[$step] other client removes $id");
      source.announce(old, null);
    }
  }

  void _deliver() {
    final queued = source.announcements.removeFirst();
    final change = queued.change;
    final name = queued.error
        ? "announce error"
        : switch (change!) {
            CalendarEntryPut<String>(:final entry) => "announce put $entry",
            CalendarEntryRemoved<String>(:final id) => "announce removed $id",
            CalendarDaysChanged<String>(:final first, :final last) =>
              "announce days "
                  "${CalendarDates.dayNumber(first)}.."
                  "${CalendarDates.dayNumber(last)}",
            CalendarAllChanged<String>() => "announce all",
            _ => "announce $change",
          };
    _call(name, () {
      if (queued.error) {
        changes.addError(SourceFailure(0));
      } else {
        changes.add(change!);
      }
    });
  }

  /// Serves a read in flight now: its answer becomes what the source holds
  /// on its days at this moment.
  void _serveRead() {
    final read = source.reads[rng.nextInt(source.reads.length)];
    final served = source.snapshotOf(read.first, read.last);
    if (!listEquals(served, read.snapshot)) {
      count("path:late-serve-changed");
    }
    read.snapshot = served;
    log("[$step] source serves read ${read.first}..${read.last} now");
  }

  void _answerRead({required bool mayFail}) {
    final index = rng.nextInt(source.reads.length);
    final read = source.reads.removeAt(index);
    if (options.lateServe && rng.nextBool()) {
      final served = source.snapshotOf(read.first, read.last);
      if (!listEquals(served, read.snapshot)) {
        count("path:late-serve-changed");
      }
      read.snapshot = served;
      log("[$step] source serves read ${read.first}..${read.last} at answer");
    }
    final fail = mayFail && options.readFailures && rng.nextDouble() < 0.2;
    final stale = read.epoch != epoch;
    final othersInFlight = source.reads.any((other) {
      return other.epoch == epoch;
    });
    if (fail) {
      anyReadFailed = anyReadFailed || !stale;
      final failure = SourceFailure(step);
      _call("read ${read.first}..${read.last} fails", () {
        read.completer.completeError(failure);
      });
      if (!stale) {
        final days = <int>[for (var d = read.first; d <= read.last; d++) d];
        if (refreshReads.contains(read)) {
          refreshFailedDays.addAll(days);
        } else {
          refreshFailedDays.removeAll(days);
        }
      }
      if (!disposed && !stale && zone == null && !othersInFlight) {
        for (var d = read.first; d <= read.last; d++) {
          if (!store.isRead(date(d)) && !store.readFailed(date(d))) {
            problem("failure-unmarked", "day $d of a failed read not marked");
          }
        }
      }
    } else {
      final unreadBefore = <int>{
        if (!disposed)
          for (var d = read.first; d <= read.last; d++)
            if (!store.isRead(date(d))) d,
      };
      _call("read ${read.first}..${read.last} answers "
          "${read.snapshot.length}", () {
        read.completer.complete(List<CalendarEntry<String>>.of(read.snapshot));
      });
      if (!stale) {
        refreshFailedDays.clear();
      }
      if (!disposed && !stale && zone == null) {
        for (var d = read.first; d <= read.last; d++) {
          // A read day this read does not fill, as one a later read filled,
          // keeps its mark; an unread one it fills ends it.
          if (!store.isRead(date(d)) ||
              (unreadBefore.contains(d) && store.readFailed(date(d)))) {
            problem("answer-unfilled", "day $d of an answered read unread");
          }
        }
      }
    }
  }

  void _applyWrite() {
    final unapplied = <PendingWrite>[
      for (final write in source.writes)
        if (!write.applied) write,
    ];
    final write = unapplied[rng.nextInt(unapplied.length)];
    log("[$step] source applies a ${write.kind.name}");
    source.apply(write);
  }

  void _answerWrite({required bool mayFail}) {
    final write = source.writes.removeAt(rng.nextInt(source.writes.length));
    final fail =
        mayFail &&
        options.writeFailures &&
        !write.applied &&
        rng.nextDouble() < 0.15;
    final record = write.record;
    Object? error;
    if (fail) {
      error = SourceFailure(step);
    } else {
      source.apply(write);
      error = write.applyFailure;
    }
    final lockId = write.kind == WriteKind.create ? null : write.id;
    _call("${write.kind.name} ${write.id} answers "
        "${error ?? write.result}", () {
      if (error != null) {
        if (write.kind == WriteKind.delete) {
          write.voidCompleter.completeError(error);
        } else {
          write.entryCompleter.completeError(error);
        }
      } else if (write.kind == WriteKind.delete) {
        write.voidCompleter.complete();
      } else {
        write.entryCompleter.complete(write.result!);
      }
      if (lockId != null) {
        inFlight.remove(lockId);
      }
    });
    if (record == null) {
      problem("harness", "write with no record");
      return;
    }
    record.answered = true;
    if (!record.done) {
      problem("write-not-completed", "${record.kind} ${record.id}");
      return;
    }
    if (error != null) {
      if (!identical(record.error, error)) {
        problem(
          "write-error",
          "${record.kind} ${record.id} failed with ${record.error}, "
              "expected $error",
        );
      }
    } else if (write.kind == WriteKind.delete) {
      if (record.error != null) {
        problem("write-error", "delete failed with ${record.error}");
      }
    } else {
      final expected = zonedEntryOf(write.result!, zone);
      if (record.value != expected) {
        problem(
          "write-value",
          "${record.kind} completed with ${record.value ?? record.error}, "
              "expected $expected",
        );
      }
    }
  }

  void _changeZone() {
    final next = zones[rng.nextInt(zones.length)];
    if (next == zone) {
      return;
    }
    // A refresh waiting on a read of this zone passes its wait to the read
    // of the shown range the change sends first.
    final waiting = source.reads.any((read) {
      return read.epoch == epoch && refreshReads.contains(read);
    });
    epoch++;
    final previous = zone;
    zone = next;
    if (inFlight.isNotEmpty || source.writes.isNotEmpty) {
      count("path:zone-change-with-writes");
    }
    final logged = source.readLog.length;
    _call("zone ${previous?.name} -> ${next?.name}", () {
      store.zone = next;
    });
    refreshFailedDays.clear();
    if (waiting && !disposed && source.readLog.length > logged) {
      final read = source.readLog[logged];
      if (read != null) {
        refreshReads.add(read);
      }
    }
  }

  void _dispose() {
    log("[$step] dispose");
    store.dispose();
    disposed = true;
    inFlight.clear();
  }

  /// Answers everything in flight, successfully, until nothing is.
  void _settleAll() {
    for (var i = 0; ; i++) {
      if (i > 4000) {
        problem("endless", "still in flight after $i answers");
        return;
      }
      final choices = <void Function()>[
        if (source.announcements.isNotEmpty) _deliver,
        if (source.reads.isNotEmpty)
          () {
            _answerRead(mayFail: false);
          },
        if (source.writes.isNotEmpty)
          () {
            _answerWrite(mayFail: false);
          },
      ];
      if (choices.isEmpty) {
        return;
      }
      choices[rng.nextInt(choices.length)]();
    }
  }

  List<CalendarEntry<String>> expectedOn(int day) {
    final expected = <CalendarEntry<String>>[
      for (final entry in source.stored.values)
        if (coversDays(zonedEntryOf(entry, zone), day, day))
          zonedEntryOf(entry, zone),
    ];
    expected.sort(compareCalendarEntries);
    return expected;
  }

  List<CalendarEntry<String>> heldOn(int day) {
    return <CalendarEntry<String>>[
      for (final entry in store.entriesOn(date(day))) entry.entry,
    ];
  }

  void _quiesceAndCheck({required bool isFinal}) {
    log("[$step] quiesce${isFinal ? " (final)" : ""}");
    _settleAll();
    if (disposed) {
      return;
    }
    final sf = shownFirst;
    final sl = shownLast;
    if (sf != null &&
        sl != null &&
        store.status == CalendarLoadStatus.loading) {
      problem("stuck-loading", "status loading with nothing in flight");
    }
    // A read day whose entries differ from the source's, or marked
    // readFailed, is probed: a prefetch sends a read of it only where the
    // store takes it to have changed.
    final probed = <({int day, bool stale, bool marked})>[];
    for (var d = vFirst; d <= vLast; d++) {
      if (!store.isRead(date(d))) {
        continue;
      }
      final stale = !listEquals(heldOn(d), expectedOn(d));
      final marked = store.readFailed(date(d));
      if (stale || marked) {
        probed.add((day: d, stale: stale, marked: marked));
      }
    }
    for (final (:day, :stale, :marked) in probed) {
      final d = day;
      final detail = "day $d holds ${heldOn(d)}, source ${expectedOn(d)}";
      final before = source.readCalls;
      // No probe's read answers within its call, so no answer applies and
      // sets off a read of a later probed day.
      source.noSync = true;
      store.prefetch(date(d), date(d));
      source.noSync = false;
      micro.drain();
      final sent = source.readCalls > before;
      final inShown = sf != null && sl != null && d >= sf && d <= sl;
      // With nothing in flight, a stale day the store does not take to have
      // changed is always a divergence. One it takes to have changed may
      // wait outside the shown range until a show or a prefetch covers it,
      // or while a mark stands on it, or after the read a refresh waited on
      // failed over it; a shown one with none of these is read at once, so
      // it is a divergence too.
      if (!sent) {
        if (stale) {
          problem(inShown ? "stale-shown-fresh" : "stale-fresh", detail);
        }
        if (marked) {
          problem("mark-on-fresh-day", "day $d is read, unchanged, marked");
        }
      } else if (!stale) {
        count("marked-changed-current");
      } else if (!inShown) {
        count("stale-outside-changed");
      } else if (marked) {
        count("stale-shown-marked");
      } else if (refreshFailedDays.contains(d)) {
        count("stale-shown-after-refresh-failed");
      } else {
        problem("stale-shown-changed", detail);
      }
    }
    if (!isFinal) {
      return;
    }
    _settleAll();
    _call("final retry", () {
      store.retry();
    });
    _call("final prefetch", () {
      store.prefetch(date(vFirst), date(vLast));
    });
    _settleAll();
    for (var d = vFirst; d <= vLast; d++) {
      if (!store.isRead(date(d))) {
        continue;
      }
      if (!listEquals(heldOn(d), expectedOn(d))) {
        problem(
          "stale-after-reread",
          "day $d holds ${heldOn(d)}, source ${expectedOn(d)}",
        );
      }
    }
  }

  void _checkFuturesDone() {
    for (final record in records) {
      if (!record.done) {
        problem(
          "write-never-completed",
          "${record.kind} ${record.id} "
              "of step ${record.step}",
        );
      }
    }
    for (final (_, done) in refreshes) {
      if (!done[0]) {
        problem("refresh-never-completed", "");
      }
    }
  }
}

class FuzzSummary {
  int runs = 0;
  final Map<String, List<int>> problemSeeds = <String, List<int>>{};
  final Map<String, int> counts = <String, int>{};
  final Map<int, FuzzRun> divergent = <int, FuzzRun>{};

  @override
  String toString() {
    final buffer = StringBuffer("runs $runs\n");
    for (final MapEntry(key: kind, value: seeds) in problemSeeds.entries) {
      buffer.writeln(
        "  $kind: ${seeds.length} runs, seeds ${seeds.take(12).join(", ")}",
      );
    }
    final keys = counts.keys.toList()..sort();
    for (final key in keys) {
      buffer.writeln("  count $key: ${counts[key]}");
    }
    return buffer.toString();
  }
}

FuzzSummary runFuzz(
  StoreFactory factory, {
  required int firstSeed,
  required int runs,
  FuzzOptions options = const FuzzOptions(),
  bool keepRuns = false,
}) {
  final summary = FuzzSummary();
  for (var seed = firstSeed; seed < firstSeed + runs; seed++) {
    final run = FuzzRun(seed, factory, options);
    try {
      run.runAll();
    } on Object catch (error, stack) {
      run.problems.add(Problem("harness-throw", "$error\n$stack"));
    }
    summary.runs++;
    final kinds = <String>{for (final p in run.problems) p.kind};
    for (final kind in kinds) {
      (summary.problemSeeds[kind] ??= <int>[]).add(seed);
    }
    for (final MapEntry(key: key, value: value) in run.counts.entries) {
      summary.counts[key] = (summary.counts[key] ?? 0) + value;
    }
    if (kinds.isNotEmpty && keepRuns && summary.divergent.length < 50) {
      summary.divergent[seed] = run;
    }
  }
  return summary;
}

/// The run of [seed], with its trace and problems, for a replay.
FuzzRun replay(
  StoreFactory factory,
  int seed, {
  FuzzOptions options = const FuzzOptions(),
}) {
  final run = FuzzRun(seed, factory, options);
  run.runAll();
  return run;
}
