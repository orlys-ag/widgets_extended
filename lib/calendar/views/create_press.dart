/// The press that starts a create range on a timed grid's empty cells with
/// a mouse, a stylus or a trackpad: one held for the long-press timeout or
/// moved past a short slop, whichever comes first.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';

/// How far, in logical pixels, a [CreatePressGestureRecognizer] pointer
/// moves from its down before its press starts a drag; and how far a press
/// of such a pointer off a timed grid's blocks may move and still be a
/// click, which clears the grid's selection.
const double createPressSlop = 4.0;

/// Recognizes, per pointer, a press that starts a drag at the first of two
/// events: the pointer has stayed down for [delay], or it has moved more
/// than [slop] from where it went down. A pointer let go or cancelled
/// before either starts nothing.
///
/// The arena may give it a pointer before either event, as where it is
/// the only recognizer the pointer reached; the drag still waits for one
/// of them. Otherwise it claims the pointer at that event, ahead of a
/// recognizer that needs a longer move, such as a scrollable's pan.
class CreatePressGestureRecognizer extends MultiDragGestureRecognizer {
  CreatePressGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    this.delay = kLongPressTimeout,
    this.slop = createPressSlop,
  });

  /// How long a pointer stays down before its press starts a drag.
  final Duration delay;

  /// How far a pointer moves from its down before its press starts a drag.
  final double slop;

  /// Whether the drag [onStart] runs for started because its pointer
  /// stayed down for [delay], rather than because it moved past [slop];
  /// false outside [onStart].
  bool get startsHeld {
    return _startsHeld;
  }

  bool _startsHeld = false;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _CreatePressState(this, event.position, event.kind, gestureSettings);
  }

  /// Calls [starter], the arena's start of a pointer's drag, with
  /// [startsHeld] reading [held] for the [onStart] it runs.
  void _start(
    GestureMultiDragStartCallback starter,
    Offset position, {
    required bool held,
  }) {
    _startsHeld = held;
    try {
      starter(position);
    } finally {
      _startsHeld = false;
    }
  }

  @override
  String get debugDescription {
    return "create press";
  }
}

/// One pointer's press for a [CreatePressGestureRecognizer].
class _CreatePressState extends MultiDragPointerState {
  _CreatePressState(
    this._recognizer,
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  ) {
    _timer = Timer(_recognizer.delay, _delayPassed);
  }

  final CreatePressGestureRecognizer _recognizer;

  Timer? _timer;

  /// The arena's start of the drag, where the arena accepted the pointer
  /// before the press began; called once it begins.
  GestureMultiDragStartCallback? _starter;

  /// How the press began: null before it has, true where it was held for
  /// the delay, and false where it moved past the slop.
  bool? _held;

  void _delayPassed() {
    _timer = null;
    _begin(held: true);
  }

  @override
  void checkForResolutionAfterMove() {
    if (_held == null && pendingDelta!.distance > _recognizer.slop) {
      _stopTimer();
      _begin(held: false);
    }
  }

  /// Begins the press: starts its drag where the arena has accepted the
  /// pointer, and otherwise claims the pointer, whose acceptance
  /// ([accepted]) starts it.
  void _begin({required bool held}) {
    _held = held;
    final starter = _starter;
    if (starter == null) {
      resolve(GestureDisposition.accepted);
    } else {
      _starter = null;
      _recognizer._start(starter, initialPosition, held: held);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    final held = _held;
    if (held == null) {
      _starter = starter;
    } else {
      _recognizer._start(starter, initialPosition, held: held);
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
