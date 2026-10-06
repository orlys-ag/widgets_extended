/// Internal: the itemSlide animation source, which also carries dropSettle
/// glides through the same records.
///
/// TRANSIENT deltas: each record runs from a displaced RECTANGLE toward
/// the item's structural one, so purging one lands the item where it
/// belongs. A repeat install COMPOSES from the record's current
/// interpolated deltas rather than replacing them.
///
/// A record carries two deltas and one mark. The LEAD is paint-only, a
/// shift the render composes at paint. The EXTENT is LAYOUT-DRIVING: the
/// geometry rule adds it to the item's extent, so the child is laid out
/// at the animated size and the coordinator's layout-driving union
/// counts a record that holds one. The RELANE mark says every lead
/// composed into the record was an INTRA-TRACK shift on the lane axis,
/// which is what lets the track-sizing term read that lead as a term of
/// its own track; the install site decides it, and a compose that mixes
/// the two kinds drops it.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';

import 'board_animation_style.dart';

class _SlideRecord {
  _SlideRecord({
    required this.start,
    required this.startExtent,
    required this.relane,
    required this.family,
    required this.explicitDuration,
    required this.explicitCurve,
  });

  /// The LEAD delta at clock 0. The painted delta decays from this to
  /// zero.
  Offset start;

  /// The EXTENT delta at clock 0, `dx` the width and `dy` the height,
  /// both content-space LENGTHS the painted extent adds to the
  /// structural one. Decays on the same clock as [start].
  Offset startExtent;

  /// Whether every lead composed into this record was an intra-track
  /// shift on the lane axis. See the library doc.
  final bool relane;

  final BoardAnimationFamily family;

  /// Per-call overrides; null falls back to the family spec at tick time,
  /// so a restyle carries through. An off family, the KILL SWITCH,
  /// dominates an explicit duration either way.
  final Duration? explicitDuration;
  final Curve? explicitCurve;

  /// The 0-to-1 animation clock, advanced by tick deltas.
  double t = 0.0;
}

/// Owns the per-id slide records and their one ticker.
class ItemSlideEngine {
  ItemSlideEngine({
    required TickerProvider vsync,
    required BoardAnimationStyle Function() styleOf,
    required void Function() notifyNow,
    required void Function() notifyCoalesced,
  }) : _styleOf = styleOf,
       _notifyNow = notifyNow,
       _notifyCoalesced = notifyCoalesced {
    _ticker = vsync.createTicker(_tick);
  }

  final BoardAnimationStyle Function() _styleOf;

  /// The UNCOALESCED dispatch, for the SETTLE only: that notify carries a
  /// synchronous ordering contract (deltas observed at 0 while the record
  /// still exists), which a deferred dispatch would land after.
  final void Function() _notifyNow;

  /// The ordinary per-tick dispatch, coalesced with every other source
  /// ticking in the same frame. A tick that completed no record carries
  /// no ordering contract: it moved some deltas, and one dispatch per
  /// frame is what the listeners want. The microtask it defers to runs
  /// before the frame's build and layout phase, so a listener that marks
  /// layout dirty still lays out in the same frame.
  final void Function() _notifyCoalesced;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final Map<int, _SlideRecord> _records = <int, _SlideRecord>{};

  /// Debug-only: successful (non-refused) installs. Pins the
  /// zero-installs-per-TRACK-RESIZE-reflow contract, which the painted
  /// rects cannot: a track resize moving every following item looks
  /// identical to one slide per item.
  int debugInstallCount = 0;

  bool get hasActive {
    return _records.isNotEmpty;
  }

  /// The ids holding records, for the composed per-id bound.
  Iterable<int> get activeIds {
    return _records.keys;
  }

  /// Whether any record holds a non-zero EXTENT delta. Read once per
  /// tick by the coordinator's layout-driving union, so a SCAN rather
  /// than a counter: a counter is a derived aggregate with four
  /// maintenance sites, and one drift upward would make every tick of
  /// every source a layout for the board's life.
  bool get hasExtentActive {
    for (final record in _records.values) {
      if (record.startExtent != Offset.zero) {
        return true;
      }
    }
    return false;
  }

  /// Whether any RELANE record stands. Same scan rule as
  /// [hasExtentActive]; the render composes it with its content-sized
  /// lane axis predicate.
  bool get hasRelaneActive {
    for (final record in _records.values) {
      if (record.relane) {
        return true;
      }
    }
    return false;
  }

  /// The painted delta for [id]: its start delta decayed by the eased
  /// clock, zero for an id with no record.
  Offset deltaOf(int id) {
    final record = _records[id];
    if (record == null) {
      return Offset.zero;
    }
    return record.start * (1.0 - _easedOf(record));
  }

  /// The in-flight EXTENT delta for [id], zero for an id with no record.
  /// The geometry rule adds it to the item's structural extent.
  Offset extentDeltaOf(int id) {
    final record = _records[id];
    if (record == null) {
      return Offset.zero;
    }
    return record.startExtent * (1.0 - _easedOf(record));
  }

  /// [deltaOf] for a RELANE record and zero for every other, which is
  /// what the track-sizing term reads: a lead it may add to its own
  /// track's extent.
  Offset relaneDeltaOf(int id) {
    final record = _records[id];
    if (record == null || !record.relane) {
      return Offset.zero;
    }
    return record.start * (1.0 - _easedOf(record));
  }

  double _easedOf(_SlideRecord record) {
    final curve =
        record.explicitCurve ?? _styleOf().specFor(record.family).curve;
    return curve.transform(record.t.clamp(0.0, 1.0));
  }

  /// Installs a slide whose painted RECTANGLE starts displaced by
  /// [delta] and [extentDelta] and decays to the structural one, or
  /// COMPOSES onto an active record: each new start is the record's
  /// current interpolated value plus the argument, the clock resets, and
  /// the spec is re-read.
  ///
  /// Returns false for a REFUSED install: the family or [duration] is
  /// off, which [BoardAnimationTiming.isOff] decides, a duration that is
  /// not positive being off. A refusal creates no motion: the change the
  /// call describes lands this frame, both deltas of it, never one
  /// without the other. And it destroys none: a record already standing
  /// for [id] is left as it is, its deltas measured from whatever
  /// structural rectangle the item now has, and it finishes on its own
  /// clock. Stopping motion is the restyle transition's job
  /// ([purgeWhere]), never a side effect of another install.
  ///
  /// [relane] declares that [delta] is an intra-track shift on the lane
  /// axis (see the library doc). The composed record keeps the mark only
  /// when both the record and this install carry it, so a compose that
  /// mixes an intra-track lead with a cross-track one drops it and the
  /// track-sizing term stops reading a lead that is no longer one.
  bool animateSlideFrom(
    int id,
    Offset delta, {
    required BoardAnimationFamily family,
    Duration? duration,
    Curve? curve,
    Offset extentDelta = Offset.zero,
    bool relane = false,
  }) {
    if (_styleOf().isOff(family, explicit: duration)) {
      return false;
    }
    debugInstallCount += 1;
    final existing = _records[id];
    final composedStart = deltaOf(id) + delta;
    final composedExtent = extentDeltaOf(id) + extentDelta;
    _records[id] = _SlideRecord(
      start: composedStart,
      startExtent: composedExtent,
      relane: existing == null ? relane : (relane && existing.relane),
      family: family,
      explicitDuration: duration,
      explicitCurve: curve,
    );
    _ensureTicking();
    return true;
  }

  /// Drops every record whose family [off] answers true for, landing its
  /// item at its structural RECTANGLE, and returns whether any went. The
  /// restyle transition: the controller passes the families the NEW style
  /// turns off, so a family restyled off stops its own motion and no
  /// other's. The caller notifies afterwards, and re-dirties
  /// layout when a record went, because a purge before a record's first
  /// tick leaves the render where the install frame left it.
  bool purgeWhere(bool Function(BoardAnimationFamily family) off) {
    var removed = false;
    _records.removeWhere((id, record) {
      if (off(record.family)) {
        removed = true;
        return true;
      }
      return false;
    });
    _stopIfIdle();
    return removed;
  }

  void clearForId(int id) {
    _records.remove(id);
    _stopIfIdle();
  }

  void _ensureTicking() {
    if (!_ticker.isActive && _records.isNotEmpty) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _stopIfIdle() {
    if (_ticker.isActive && _records.isEmpty) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final style = _styleOf();
    var anyCompleted = false;
    _records.forEach((id, record) {
      // An off family dominates the record's explicit duration, and
      // either one off answers zero. The restyle to off purges a
      // family's records in the setter, so this is the guard against a
      // division by zero or a clock running backwards rather than the
      // mechanism: an off duration drives a record past 1 here.
      final durationUs = style
          .durationFor(record.family, explicit: record.explicitDuration)
          .inMicroseconds;
      record.t += durationUs == 0
          ? double.infinity
          : dt.inMicroseconds / durationUs;
      if (record.t >= 1.0) {
        anyCompleted = true;
      }
    });
    if (!anyCompleted) {
      // An ordinary tick: nothing settled, so nothing depends on when
      // within the frame this lands. Coalesced with every other source.
      _notifyCoalesced();
      return;
    }
    // The settle protocol: listeners first observe the completed records
    // with their deltas at 0 while the engine still reports active, then
    // the records are cleared, then one more dispatch shows the
    // active-to-idle transition. BOTH are synchronous, because both are
    // about what is observable at a particular instant.
    _notifyNow();
    _records.removeWhere((id, record) {
      return record.t >= 1.0;
    });
    _stopIfIdle();
    _notifyNow();
  }

  void dispose() {
    _ticker.dispose();
  }
}
