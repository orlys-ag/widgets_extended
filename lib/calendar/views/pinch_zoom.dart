/// A two-finger pinch on one of the calendar's grids, read from the raw
/// pointer events, the limits of the sizes it zooms to, and the scroll
/// offset that keeps the point between the fingers in its place as the
/// board's tracks grow or shrink under it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../board/board.dart';

/// The least day width a pinch zooms to, and a timed grid's and a month
/// board's default least day width.
const double minDayWidthLow = 44.0;

/// The most day width a pinch zooms to.
const double minDayWidthHigh = 240.0;

/// The least slot height a pinch zooms a timed grid to.
const double minSlotHeightLow = 8.0;

/// The most slot height a pinch zooms a timed grid to.
const double minSlotHeightHigh = 48.0;

/// A timed grid's default least slot height.
const double defaultMinSlotHeight = 16.0;

/// The most week scale a pinch zooms a month board to: the most slot
/// height a pinch zooms a timed grid to over its default.
const double maxMonthWeekScale = minSlotHeightHigh / defaultMinSlotHeight;

/// The axis a pinch zooms.
enum PinchAxis { vertical, horizontal }

/// A pinch's progress: the axis it zooms, the fingers' distance over
/// their distance when it started, and the point midway between them, in
/// global coordinates.
typedef PinchUpdate = ({PinchAxis axis, double scale, Offset focal});

/// Follows the touches on a grid and reports a pinch of the first two.
///
/// The grid's [Listener] hands it every pointer event it receives, which
/// reach it however the arena resolves, so a pinch is seen even where a
/// scroll already took the first finger. Once the spread of the two
/// fingers has changed by more than [kTouchSlop] along an axis, [onStart]
/// is called with that axis, the one it changed more along, which the
/// pinch then zooms; [onUpdate] follows each move after it, and [onEnd]
/// the lift or cancel of either finger. [onStart] may refuse the pinch by
/// returning false, and the two fingers then pinch nothing until one of
/// them lifts. Touches past the first two, and pointers of other kinds,
/// are ignored.
class PinchTracker {
  PinchTracker({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final bool Function(PinchAxis axis, Offset focal) onStart;
  final ValueChanged<PinchUpdate> onUpdate;
  final VoidCallback onEnd;

  /// Whether two touches are down, pinching or not: while they are, the
  /// grid holds its scrolling, so a second finger never scrolls it.
  final ValueNotifier<bool> holding = ValueNotifier<bool>(false);

  /// Whether a pinch has started among the touches down: true from
  /// [onStart] until the last of them has lifted and that lift's event has
  /// reached every handler, so a tap it ends still sees it while the next
  /// touch's down, which reaches the grid's descendants before the grid,
  /// does not. A grid acts on no tap, long press or drag of those touches.
  final ValueNotifier<bool> pinched = ValueNotifier<bool>(false);

  /// Whether a pinch runs: from [onStart] to [onEnd].
  bool get active {
    return _axis != null;
  }

  /// The tracked touches' positions, the first to land first.
  final Map<int, Offset> _touches = <int, Offset>{};

  /// The spread of the two touches when the second landed.
  Offset _startSpread = Offset.zero;

  /// The distance between the two touches when the pinch started.
  double _startDistance = 0.0;

  PinchAxis? _axis;
  bool _refused = false;

  void handleEvent(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    if (event is PointerDownEvent) {
      if (_touches.length < 2) {
        _touches[event.pointer] = event.position;
        if (_touches.length == 2) {
          _startSpread = _spread();
          holding.value = true;
        }
      }
    } else if (event is PointerMoveEvent) {
      if (!_touches.containsKey(event.pointer)) {
        return;
      }
      _touches[event.pointer] = event.position;
      if (_touches.length == 2) {
        _move();
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_touches.remove(event.pointer) == null) {
        return;
      }
      _refused = false;
      holding.value = false;
      if (_axis != null) {
        _axis = null;
        onEnd();
      }
      if (_touches.isEmpty && pinched.value) {
        scheduleMicrotask(() {
          if (_touches.isEmpty) {
            pinched.value = false;
          }
        });
      }
    }
  }

  void dispose() {
    holding.dispose();
    pinched.dispose();
  }

  /// The second touch less the first.
  Offset _spread() {
    final positions = _touches.values;
    return positions.last - positions.first;
  }

  Offset _focal() {
    final positions = _touches.values;
    return (positions.first + positions.last) / 2.0;
  }

  void _move() {
    final spread = _spread();
    final axis = _axis;
    if (axis != null) {
      onUpdate((
        axis: axis,
        scale: math.max(spread.distance, 1.0) / _startDistance,
        focal: _focal(),
      ));
      return;
    }
    if (_refused) {
      return;
    }
    final across = (spread.dx.abs() - _startSpread.dx.abs()).abs();
    final down = (spread.dy.abs() - _startSpread.dy.abs()).abs();
    if (math.max(across, down) <= kTouchSlop) {
      return;
    }
    final picked = down >= across ? PinchAxis.vertical : PinchAxis.horizontal;
    if (!onStart(picked, _focal())) {
      _refused = true;
      return;
    }
    _axis = picked;
    pinched.value = true;
    // From the spread the pinch starts at, so the slop it crossed to start
    // makes no jump.
    _startDistance = math.max(spread.distance, 1.0);
  }
}

/// Keeps scroll positions still from [hold] to [release]: [hold] stops
/// each one's drag or fling where it is with [ScrollPosition.hold], and
/// holds it again whenever it starts scrolling after, so no finger moves
/// it. A drag a position's scrollable started ends there, its scrollable
/// dropping it as the hold replaces its activity, so the moves of its
/// pointers reach nothing.
class ScrollHolder {
  final Map<ScrollPosition, VoidCallback> _listeners =
      <ScrollPosition, VoidCallback>{};
  final Map<ScrollPosition, ScrollHoldController> _holds =
      <ScrollPosition, ScrollHoldController>{};

  void hold(Iterable<ScrollPosition?> positions) {
    for (final position in positions) {
      if (position == null || _listeners.containsKey(position)) {
        continue;
      }
      void listener() {
        if (position.isScrollingNotifier.value) {
          // Not from inside the activity change that notified, whose
          // caller still holds the activity it began.
          scheduleMicrotask(() {
            if (_listeners.containsKey(position)) {
              _holds[position] = position.hold(_ignore);
            }
          });
        }
      }

      _listeners[position] = listener;
      position.isScrollingNotifier.addListener(listener);
      _holds[position] = position.hold(_ignore);
    }
  }

  void release() {
    for (final MapEntry(key: position, value: listener) in _listeners.entries) {
      position.isScrollingNotifier.removeListener(listener);
    }
    _listeners.clear();
    final holds = _holds.values.toList();
    _holds.clear();
    for (final hold in holds) {
      hold.cancel();
    }
  }

  static void _ignore() {}
}

/// The fractional track at [offset] on [axis], in content space: the
/// track there and how far into it, from 0 to 1.
double trackFractionAt(BoardAxis axis, double offset) {
  final track = axis.trackAt(offset);
  final extent = axis.extentOf(track);
  final into = extent > 0.0
      ? ((offset - axis.offsetOf(track)) / extent).clamp(0.0, 1.0)
      : 0.0;
  return track + into;
}

/// Sets [position]'s offset for the board's next layout, which lays out
/// [next] in place of [old], so that the lattice point [focal] from the
/// viewport's leading edge, under the [band] its frozen leading tracks
/// take, keeps that place.
///
/// The board's zoom anchor, at the head of a layout that finds a new axis
/// instance, puts the lattice point at the scrolled region's leading edge
/// under [old], read at the offset it finds, back at that edge under
/// [next]. The offset set here is the one whose leading edge under [old]
/// holds the point that edge must hold under [next] for [focal] to stay,
/// clamped as the board clamps into the new scroll range. Both axes have
/// [band] for their leading band, which a point over it is moved off.
void holdFocalAcrossAxisSwap(
  ScrollPosition position, {
  required BoardAxis old,
  required BoardAxis next,
  required double band,
  required double focal,
}) {
  if (!position.hasPixels ||
      !position.hasViewportDimension ||
      old.trackCount == 0 ||
      next.trackCount == 0) {
    return;
  }
  final at = math.max(focal, band);
  final point = trackFractionAt(old, position.pixels + at);
  final maxTarget = math.max(
    0.0,
    next.totalExtent - position.viewportDimension,
  );
  final target = (next.offsetOfFraction(point) - at).clamp(0.0, maxTarget);
  final lead = trackFractionAt(
    next,
    target + band,
  ).clamp(0.0, old.trackCount.toDouble());
  position.correctPixels(old.offsetOfFraction(lead) - band);
}
