/// Internal: the scroll physics `Board` installs outermost around each
/// axis's physics, and the record it keeps of the simulations that physics
/// creates.
///
/// [BoardScrollPhysics] answers every member as the physics it wraps.
/// While its [BoardSpringRecord] wraps, it hands back each simulation its
/// parent creates wrapped in one that records where it started and every
/// value it yields, so a reader of the record can tell a move of the
/// scroll offset to a value that simulation yielded from a move anything
/// else made.
///
/// Not exported from the module barrel.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Whether a [BoardSpringRecord] on an axis wraps the simulations its
/// physics creates.
abstract interface class BoardSpringGate {
  /// Whether a record on [axis] wraps the simulations its physics creates.
  bool wrapsSpringsOn(Axis axis);
}

/// One axis's record of the simulations its [BoardScrollPhysics] wrapped.
///
/// The counters number events, never pixels: [simulation] counts the
/// simulations wrapped, the latest being the CURRENT one, and [serial]
/// counts every event, a wrap or a value the current simulation yielded.
/// [start] is where the current simulation started and [startSerial] the
/// serial of its wrap; [last] is the last value it yielded, or its start
/// before it yielded any, and [lastSerial] that event's serial. A reader
/// that names the simulation it read last in [watched] keeps that one's
/// last yield: when a wrap replaces the watched simulation, [last] and
/// [lastSerial] move to [watchedLast] and [watchedLastSerial] first.
class BoardSpringRecord {
  BoardSpringRecord(this.axis);

  /// The axis whose physics records here.
  final Axis axis;

  /// Answers whether this record wraps; with none it wraps nothing.
  BoardSpringGate? gate;

  int simulation = 0;
  int serial = 0;
  int watched = 0;
  int startSerial = 0;
  int lastSerial = 0;
  int watchedLastSerial = 0;

  /// [start], [last] and [watchedLast], in that order, so a recorded value
  /// is written into a typed slot rather than a field of its own.
  final Float64List _pixels = Float64List(3);

  double get start {
    return _pixels[0];
  }

  double get last {
    return _pixels[1];
  }

  double get watchedLast {
    return _pixels[2];
  }

  /// Whether the physics wraps the simulations it creates: while [gate] is
  /// set and answers true for [axis].
  bool get wraps {
    final gate = this.gate;
    return gate != null && gate.wrapsSpringsOn(axis);
  }

  /// [inner], started at [pixels], wrapped so that it records here as the
  /// current simulation.
  Simulation wrap(Simulation inner, double pixels) {
    if (simulation == watched) {
      _pixels[2] = _pixels[1];
      watchedLastSerial = lastSerial;
    }
    simulation += 1;
    serial += 1;
    startSerial = serial;
    lastSerial = serial;
    _pixels[0] = pixels;
    _pixels[1] = pixels;
    return _RecordedSimulation(inner, this, simulation);
  }
}

/// The scroll physics `Board` installs outermost around each axis's
/// physics for its life.
///
/// Every member answers as [parent] does. `ScrollPhysics` answers
/// [allowUserScrolling] and [allowImplicitScrolling] without its parent,
/// so this overrides both to ask it; every other member is inherited and
/// asks it already. [createBallisticSimulation] hands back the parent's
/// simulation, wrapped through [BoardSpringRecord.wrap] while [record]
/// wraps.
class BoardScrollPhysics extends ScrollPhysics {
  const BoardScrollPhysics({required this.record, super.parent});

  /// The record this physics' simulations record into.
  final BoardSpringRecord record;

  @override
  BoardScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return BoardScrollPhysics(record: record, parent: buildParent(ancestor));
  }

  @override
  bool get allowUserScrolling {
    return parent?.allowUserScrolling ?? true;
  }

  @override
  bool get allowImplicitScrolling {
    return parent?.allowImplicitScrolling ?? true;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final inner = parent?.createBallisticSimulation(position, velocity);
    if (inner == null || !record.wraps) {
      return inner;
    }
    return record.wrap(inner, position.pixels);
  }
}

/// [_inner], forwarded, recording each value [x] yields into [_record]
/// while it is the record's current simulation, numbered [_number].
class _RecordedSimulation extends Simulation {
  _RecordedSimulation(this._inner, this._record, this._number)
    : super(tolerance: _inner.tolerance);

  final Simulation _inner;
  final BoardSpringRecord _record;
  final int _number;

  @override
  double x(double time) {
    final value = _inner.x(time);
    final record = _record;
    if (record.simulation == _number) {
      record.serial += 1;
      record.lastSerial = record.serial;
      record._pixels[1] = value;
    }
    return value;
  }

  @override
  double dx(double time) {
    return _inner.dx(time);
  }

  @override
  bool isDone(double time) {
    return _inner.isDone(time);
  }
}
