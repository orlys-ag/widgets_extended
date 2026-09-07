/// Internal: cell-targeted scrolling over the two axes.
///
/// Owns the target derivation, one in-flight leg per AXIS with
/// supersession, the one-frame wait for a port that has not laid out,
/// and the post-frame settle snap that re-derives a landing after a
/// driven scroll overwrote the correction loop's writes with absolute
/// values.
///
/// Not exported from the module barrel.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '_board_axis.dart';
import 'board_render_port.dart';

class _AxisLeg {
  _AxisLeg();

  final Completer<bool> completer = Completer<bool>();
}

/// The scroll session and target arithmetic behind `animateScrollToCell`,
/// `jumpToCell` and `frozenInsetOf`.
class BoardScrollOrchestrator<TKey> {
  BoardScrollOrchestrator({
    required BoardRenderPort<TKey>? Function() portOf,
    required BoardAxisConfig Function() rowsOf,
    required BoardAxisConfig Function() columnsOf,
  }) : _portOf = portOf,
       _rowsOf = rowsOf,
       _columnsOf = columnsOf;

  final BoardRenderPort<TKey>? Function() _portOf;
  final BoardAxisConfig Function() _rowsOf;
  final BoardAxisConfig Function() _columnsOf;

  _AxisLeg? _verticalLeg;
  _AxisLeg? _horizontalLeg;

  /// Bumped by every new scroll intent (either public entry) and by
  /// cancellation. A pending settle snap carries the generation it was
  /// scheduled under and no-ops when a newer intent has since taken the
  /// position; the post-wait re-check of the unlaid-port arm reads it
  /// for the same reason.
  int _intentGeneration = 0;

  /// The one settle-snap slot: newest wins, never rescheduled from
  /// inside itself.
  ({int row, int col, double rowAlignment, double colAlignment, bool avoid})?
  _pendingSnap;
  bool _snapScheduled = false;

  /// The intent generation of the NEWEST landing that wrote
  /// [_pendingSnap]. Newest wins here as it does for the slot: a second
  /// landing in the frame an earlier one already scheduled the callback
  /// for overwrites both, so the callback compares the generation of the
  /// snap it is about to apply rather than the one it was scheduled under.
  int _snapGeneration = 0;

  /// The one deferred-jump slot for a not-yet-laid-out `jumpToCell`.
  ({int row, int col, bool avoid})? _pendingJump;
  bool _jumpScheduled = false;

  bool _disposed = false;

  /// The extent of the LEADING frozen band on [axis]. 0.0 with no port
  /// AND before the port's first layout, which a caller cannot tell from
  /// a board with no frozen tracks and does not need to.
  double frozenInsetOf(Axis axis) {
    final port = _portOf();
    if (port == null || !port.isLaidOut) {
      return 0.0;
    }
    return port.frozenInsetOf(axis);
  }

  /// The TRAILING band's extent, derived from the configs and the axis
  /// directly: the port's inset read is leading-only by contract.
  double _trailingInsetOf(Axis axis) {
    final config = axis == Axis.vertical ? _rowsOf() : _columnsOf();
    if (config.frozenEnd <= 0) {
      return 0.0;
    }
    final boardAxis = config.axis;
    // Clamped like every other frozen-band consumer: an over-large
    // frozenEnd freezes everything rather than leaving the axis's
    // domain.
    final start = boardAxis.trackCount - config.frozenEnd;
    if (start <= 0) {
      return boardAxis.totalExtent;
    }
    return boardAxis.totalExtent - boardAxis.offsetOf(start);
  }

  /// The scroll offset that lands [track]'s leading edge at the aligned
  /// painted position: the leading inset when [alignment] is 0, sliding
  /// toward the trailing band's start as it approaches 1.
  double _targetFor(
    Axis axis,
    int track,
    double alignment,
    bool avoid,
    ScrollPosition position,
  ) {
    final config = axis == Axis.vertical ? _rowsOf() : _columnsOf();
    final leading = avoid ? frozenInsetOf(axis) : 0.0;
    final trailing = avoid ? _trailingInsetOf(axis) : 0.0;
    final viewport = position.viewportDimension;
    final paintedTarget =
        leading + alignment * (viewport - leading - trailing);
    final raw = config.axis.offsetOf(track) - paintedTarget;
    return raw.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Scrolls both axes so cell `(row, col)` lands aligned. Completes true
  /// only when BOTH legs landed; false when either was superseded by a
  /// later call on its axis, when no port is registered (after the one
  /// frame a registered-but-unlaid-out port is allowed), or when the
  /// port went away mid-scroll.
  Future<bool> animateScrollToCell(
    int row,
    int col, {
    required Duration duration,
    required Curve curve,
    required double rowAlignment,
    required double colAlignment,
    required bool avoidFrozenTracks,
  }) async {
    var port = _portOf();
    if (port == null || _disposed) {
      return false;
    }
    if (row < 0 ||
        row >= _rowsOf().axis.trackCount ||
        col < 0 ||
        col >= _columnsOf().axis.trackCount) {
      // Out of the lattice: defined degradation rather than the axis's
      // domain assert.
      return false;
    }
    final generation = ++_intentGeneration;
    if (!port.isLaidOut) {
      // Exactly one wait, never a loop: registration happens in attach,
      // one line after the markNeedsLayout that schedules the first
      // layout, so a mounted board is laid out one frame later and a
      // port still unlaid after the wait never mounted.
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
      port = _portOf();
      if (port == null || _disposed || !port.isLaidOut) {
        return false;
      }
      if (generation != _intentGeneration) {
        // A newer intent arrived while this call waited; superseding it
        // now would invert the supersession order.
        return false;
      }
    }
    final vertical = port.verticalPosition;
    final horizontal = port.horizontalPosition;
    if (vertical == null || horizontal == null) {
      return false;
    }
    final rowTarget = _targetFor(
      Axis.vertical,
      row,
      rowAlignment,
      avoidFrozenTracks,
      vertical,
    );
    final colTarget = _targetFor(
      Axis.horizontal,
      col,
      colAlignment,
      avoidFrozenTracks,
      horizontal,
    );
    final legs = await Future.wait(<Future<bool>>[
      _driveLeg(Axis.vertical, vertical, rowTarget, duration, curve),
      _driveLeg(Axis.horizontal, horizontal, colTarget, duration, curve),
    ]);
    final landed = legs[0] && legs[1];
    if (landed && !_disposed && generation == _intentGeneration) {
      // The driven activity overwrote every correction with absolute
      // values; one post-frame snap re-derives the landing against the
      // settled geometry. Guarded by the generation: an interrupted
      // flight can report landed through the activity-dispose path (a
      // documented residual), and its stale snap must not take the
      // position from whatever interrupted it.
      _pendingSnap = (
        row: row,
        col: col,
        rowAlignment: rowAlignment,
        colAlignment: colAlignment,
        avoid: avoidFrozenTracks,
      );
      _scheduleSnap(generation);
    }
    return landed;
  }

  Future<bool> _driveLeg(
    Axis axis,
    ScrollPosition position,
    double target,
    Duration duration,
    Curve curve,
  ) {
    final superseded = axis == Axis.vertical ? _verticalLeg : _horizontalLeg;
    if (superseded != null && !superseded.completer.isCompleted) {
      superseded.completer.complete(false);
    }
    final leg = _AxisLeg();
    if (axis == Axis.vertical) {
      _verticalLeg = leg;
    } else {
      _horizontalLeg = leg;
    }
    if (duration <= Duration.zero) {
      position.jumpTo(target);
      if (!leg.completer.isCompleted) {
        leg.completer.complete(true);
      }
      return leg.completer.future;
    }
    position.animateTo(target, duration: duration, curve: curve).whenComplete(
      () {
        // Landed only if this leg is still the axis's current one and
        // nothing cancelled it while the activity ran.
        if (!leg.completer.isCompleted) {
          leg.completer.complete(true);
        }
      },
    );
    return leg.completer.future;
  }

  void _scheduleSnap(int generation) {
    _snapGeneration = generation;
    if (_snapScheduled) {
      return;
    }
    _snapScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      final snap = _pendingSnap;
      _pendingSnap = null;
      if (snap == null || _disposed || _snapGeneration != _intentGeneration) {
        return;
      }
      final port = _portOf();
      if (port == null || !port.isLaidOut) {
        return;
      }
      final vertical = port.verticalPosition;
      final horizontal = port.horizontalPosition;
      if (vertical == null || horizontal == null) {
        return;
      }
      if (_userIsScrolling(vertical) || _userIsScrolling(horizontal)) {
        // The user took the position; a jump here would run goIdle
        // first, killing the drag activity under the finger.
        return;
      }
      final rowTarget = _targetFor(
        Axis.vertical,
        snap.row,
        snap.rowAlignment,
        snap.avoid,
        vertical,
      );
      final colTarget = _targetFor(
        Axis.horizontal,
        snap.col,
        snap.colAlignment,
        snap.avoid,
        horizontal,
      );
      if ((vertical.pixels - rowTarget).abs() > precisionErrorTolerance) {
        vertical.jumpTo(rowTarget);
      }
      if ((horizontal.pixels - colTarget).abs() > precisionErrorTolerance) {
        horizontal.jumpTo(colTarget);
      }
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  static bool _userIsScrolling(ScrollPosition position) {
    return position is ScrollPositionWithSingleContext &&
        position.userScrollDirection != ScrollDirection.idle;
  }

  /// Jumps both axes. A registered-but-unlaid-out port gets one deferred
  /// post-frame jump, one slot, newest wins; no port is a no-op, and so
  /// is a target outside the lattice.
  void jumpToCell(int row, int col, {required bool avoidFrozenTracks}) {
    final port = _portOf();
    if (port == null || _disposed) {
      return;
    }
    if (row < 0 ||
        row >= _rowsOf().axis.trackCount ||
        col < 0 ||
        col >= _columnsOf().axis.trackCount) {
      return;
    }
    _intentGeneration += 1;
    if (!port.isLaidOut) {
      _pendingJump = (row: row, col: col, avoid: avoidFrozenTracks);
      if (_jumpScheduled) {
        return;
      }
      _jumpScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _jumpScheduled = false;
        final jump = _pendingJump;
        _pendingJump = null;
        if (jump == null || _disposed) {
          return;
        }
        final late = _portOf();
        if (late == null || !late.isLaidOut) {
          return;
        }
        jumpToCell(jump.row, jump.col, avoidFrozenTracks: jump.avoid);
      });
      SchedulerBinding.instance.scheduleFrame();
      return;
    }
    final vertical = port.verticalPosition;
    final horizontal = port.horizontalPosition;
    if (vertical == null || horizontal == null) {
      return;
    }
    vertical.jumpTo(
      _targetFor(Axis.vertical, row, 0.0, avoidFrozenTracks, vertical),
    );
    horizontal.jumpTo(
      _targetFor(Axis.horizontal, col, 0.0, avoidFrozenTracks, horizontal),
    );
  }

  /// Completes every in-flight leg false and drops the pending slots.
  /// Run by `detachRenderPort` and by [dispose], so a `Future` never
  /// waits on a `ScrollPosition` that left the tree.
  void cancelInFlight() {
    _intentGeneration += 1;
    final vertical = _verticalLeg;
    if (vertical != null && !vertical.completer.isCompleted) {
      vertical.completer.complete(false);
    }
    _verticalLeg = null;
    final horizontal = _horizontalLeg;
    if (horizontal != null && !horizontal.completer.isCompleted) {
      horizontal.completer.complete(false);
    }
    _horizontalLeg = null;
    _pendingSnap = null;
    _pendingJump = null;
  }

  void dispose() {
    _disposed = true;
    cancelInFlight();
  }
}
