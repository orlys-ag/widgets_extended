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
  /// so a restyle carries through. The family's zero KILL SWITCH
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
  }) : _styleOf = styleOf,
       _notifyNow = notifyNow {
    _ticker = vsync.createTicker(_tick);
  }

  final BoardAnimationStyle Function() _styleOf;

  /// The UNCOALESCED dispatch: this engine's settle notify carries a
  /// synchronous ordering contract (deltas observed at 0 while the record
  /// still exists), which a deferred dispatch would land after.
  final void Function() _notifyNow;

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
  /// the spec is re-read. Returns false for a REFUSED install: a zero
  /// family, or a zero resolved duration, leaves the item at its
  /// structural rectangle, which for a transient delta is where it
  /// belongs. The refusal drops BOTH deltas, never one without the
  /// other.
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
    final spec = _styleOf().specFor(family);
    if (spec.duration == Duration.zero ||
        (duration ?? spec.duration) == Duration.zero) {
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

  /// Drops every record, landing every item at its structural
  /// RECTANGLE. The restyle-to-zero transition; the caller notifies
  /// afterwards, and re-dirties layout when a record stood, because a
  /// purge before a record's first tick leaves the render where the
  /// install frame left it.
  void purgeActive() {
    _records.clear();
    _stopIfIdle();
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
      final spec = style.specFor(record.family);
      // The family's zero dominates the record's explicit duration: a
      // restyle to zero between two ticks drives every record past 1
      // here rather than dividing by zero.
      final effective = spec.duration == Duration.zero
          ? Duration.zero
          : (record.explicitDuration ?? spec.duration);
      final durationUs = effective.inMicroseconds;
      record.t += durationUs == 0
          ? double.infinity
          : dt.inMicroseconds / durationUs;
      if (record.t >= 1.0) {
        anyCompleted = true;
      }
    });
    // The settle protocol: listeners first observe the completed records
    // with their deltas at 0 while the engine still reports active, then
    // the records are cleared, then one more dispatch shows the
    // active-to-idle transition.
    _notifyNow();
    if (anyCompleted) {
      _records.removeWhere((id, record) {
        return record.t >= 1.0;
      });
      _stopIfIdle();
      _notifyNow();
    }
  }

  void dispose() {
    _ticker.dispose();
  }
}
