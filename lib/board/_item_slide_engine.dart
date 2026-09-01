/// Internal: the itemSlide animation source, which also carries dropSettle
/// glides through the same records.
///
/// TRANSIENT paint-only deltas: each record runs from a displaced position
/// TOWARD the item's structural position, so purging one lands the item
/// where it belongs. A repeat install COMPOSES from the record's current
/// interpolated delta rather than replacing it.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';

import 'board_animation_style.dart';

class _SlideRecord {
  _SlideRecord({
    required this.start,
    required this.family,
    required this.explicitDuration,
    required this.explicitCurve,
  });

  /// The delta at clock 0. The painted delta decays from this to zero.
  Offset start;

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
  /// zero-installs-per-reflow contract, which the painted rects cannot:
  /// a resize moving every following item looks identical to one slide
  /// per item.
  int debugInstallCount = 0;

  bool get hasActive {
    return _records.isNotEmpty;
  }

  /// The ids holding records, for the composed per-id bound.
  Iterable<int> get activeIds {
    return _records.keys;
  }

  /// The painted delta for [id]: its start delta decayed by the eased
  /// clock, zero for an id with no record.
  Offset deltaOf(int id) {
    final record = _records[id];
    if (record == null) {
      return Offset.zero;
    }
    final curve =
        record.explicitCurve ?? _styleOf().specFor(record.family).curve;
    final eased = curve.transform(record.t.clamp(0.0, 1.0));
    return record.start * (1.0 - eased);
  }

  /// Installs a slide whose painted position starts displaced by [delta]
  /// and decays to zero, or COMPOSES onto an active record: the new start
  /// is the record's current interpolated delta plus [delta], the clock
  /// resets, and the spec is re-read. Returns false for a REFUSED
  /// install: a zero family, or a zero resolved duration, leaves the item
  /// at its structural position, which for a transient delta is where it
  /// belongs.
  bool animateSlideFrom(
    int id,
    Offset delta, {
    required BoardAnimationFamily family,
    Duration? duration,
    Curve? curve,
  }) {
    final spec = _styleOf().specFor(family);
    if (spec.duration == Duration.zero ||
        (duration ?? spec.duration) == Duration.zero) {
      return false;
    }
    debugInstallCount += 1;
    final composedStart = deltaOf(id) + delta;
    _records[id] = _SlideRecord(
      start: composedStart,
      family: family,
      explicitDuration: duration,
      explicitCurve: curve,
    );
    _ensureTicking();
    return true;
  }

  /// PER-AXIS magnitudes over the active set, independently.
  ({double dx, double dy}) get bound {
    var dx = 0.0;
    var dy = 0.0;
    for (final id in _records.keys) {
      final delta = deltaOf(id);
      if (delta.dx.abs() > dx) {
        dx = delta.dx.abs();
      }
      if (delta.dy.abs() > dy) {
        dy = delta.dy.abs();
      }
    }
    return (dx: dx, dy: dy);
  }

  /// Drops every record, landing every item at its structural position.
  /// The restyle-to-zero transition; the caller notifies afterwards so
  /// items painted mid-delta repaint snapped.
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
