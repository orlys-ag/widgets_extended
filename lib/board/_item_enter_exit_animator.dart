/// Internal: the itemEnterExit animation source.
///
/// One record per animating id, holding the 0-to-1 animation clock and
/// the ramp value the record STARTED from. The direction is not stored
/// here: it is the store's exiting bit against its entering bit, whose
/// single writer is the coordinator, and this animator asks through a
/// callback.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/scheduler.dart';

import 'board_animation_style.dart';

class _EnterExitRecord {
  _EnterExitRecord({required this.from, required this.family});

  /// The reported ramp value at clock 0: 0 for an enter, and for an exit
  /// the value the ramp held when the exit was installed, which is 1
  /// except for a mid-enter removal. An enter that REVERSES an exit
  /// starts from the value that exit had reached.
  final double from;

  /// Resolved through `specFor` on every tick, so a restyle carries
  /// through (and a restyle to zero drives the clock past 1).
  final BoardAnimationFamily family;

  /// The 0-to-1 animation clock, advanced by tick deltas.
  double t = 0.0;
}

/// Owns the per-id enter/exit records and their one ticker.
class ItemEnterExitAnimator {
  ItemEnterExitAnimator({
    required TickerProvider vsync,
    required BoardAnimationStyle Function() styleOf,
    required bool Function(int id) isExitingOf,
    required void Function(int id) onSettle,
    required void Function() onTick,
  }) : _styleOf = styleOf,
       _isExitingOf = isExitingOf,
       _onSettle = onSettle,
       _onTick = onTick {
    _ticker = vsync.createTicker(_tick);
  }

  final BoardAnimationStyle Function() _styleOf;
  final bool Function(int id) _isExitingOf;
  final void Function(int id) _onSettle;
  final void Function() _onTick;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final Map<int, _EnterExitRecord> _records = <int, _EnterExitRecord>{};

  bool get hasActive {
    return _records.isNotEmpty;
  }

  /// The ids holding a record, a live view: the coordinator walks it once
  /// per tick to mark those ids' presences.
  Iterable<int> get activeIds {
    return _records.keys;
  }

  /// The ramp: `from` eased up to 1 while entering, `from` eased down to
  /// 0 while exiting, and exactly 1 for an id with no record, which is
  /// the settled-live-item arm every consumer multiplies by
  /// unconditionally.
  ///
  /// CLAMPED TO `[0, 1]` HERE, at the producer: an overshooting curve
  /// (`Curves.easeInBack` dips below 0, `Curves.easeOutBack` rises above
  /// 1) would otherwise hand the lane-axis geometry a negative extent,
  /// which reaches layout as a negative tight constraint. The `from` an
  /// interrupted enter hands an exit is read through this same method,
  /// so it is bounded too.
  double progressOf(int id) {
    final record = _records[id];
    if (record == null) {
      return 1.0;
    }
    final curve = _styleOf().specFor(record.family).curve;
    final eased = curve.transform(record.t.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    if (_isExitingOf(id)) {
      return (record.from * (1.0 - eased)).clamp(0.0, 1.0);
    }
    return (record.from + (1.0 - record.from) * eased).clamp(0.0, 1.0);
  }

  /// Installs an enter ramp for [id], from [from] up to 1 over
  /// `1 - from` times the family's resolved duration, the mirror of an
  /// exit's scaling, so an item growing back from part way grows at the
  /// pixels per second a full enter gives. The caller has already set the
  /// entering bit; a fresh item starts at 0, and an exit being reversed
  /// at the value it had reached.
  void animateEnter(
    int id, {
    required BoardAnimationFamily family,
    double from = 0.0,
  }) {
    _records[id] = _EnterExitRecord(from: from, family: family);
    _ensureTicking();
  }

  /// Installs an exit ramp for [id], running from [from] down to 0 over
  /// `from` times the family's resolved duration, so a part-entered item
  /// leaves at the same pixels per second a full exit gives.
  void animateExit(
    int id, {
    required BoardAnimationFamily family,
    required double from,
  }) {
    _records[id] = _EnterExitRecord(from: from, family: family);
    _ensureTicking();
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
    List<int>? settled;
    _records.forEach((id, record) {
      final spec = style.specFor(record.family);
      // The scaled denominators: an exit's clock runs over
      // `from * duration`, an enter's over `(1 - from) * duration`. A zero
      // product, which a zero FAMILY produces, and an enter reversing an
      // exit that had not begun, maps to an INFINITE delta rather than a
      // division, driving the record past 1 and through the normal settle
      // on this very tick.
      final baseUs = spec.duration.inMicroseconds;
      final durationUs = _isExitingOf(id)
          ? (baseUs * record.from).round()
          : (baseUs * (1.0 - record.from)).round();
      record.t += durationUs == 0
          ? double.infinity
          : dt.inMicroseconds / durationUs;
      if (record.t >= 1.0) {
        (settled ??= <int>[]).add(id);
      }
    });
    if (settled != null) {
      for (final id in settled!) {
        // An earlier handler's delivered notification can reach an app
        // listener that retires this id (and, under LIFO recycling,
        // re-issues it to a fresh incarnation whose record is new), or
        // re-adds the key of this exiting id, which reverses the exit on
        // the same id with an enter's record, so a collected id is only
        // settled if ITS record is still the one that reached 1.
        final record = _records[id];
        if (record == null || record.t < 1.0) {
          continue;
        }
        // The settle handler drops the record (directly on an enter,
        // through clearForId on an exit) and owns everything after.
        _onSettle(id);
      }
    }
    _stopIfIdle();
    // Coalesced dispatch, after the settle handlers: every level the
    // deferred callback reads is already idle, which is what the render
    // object's prior-tick latch exists for.
    _onTick();
  }

  void dispose() {
    _ticker.dispose();
  }
}
