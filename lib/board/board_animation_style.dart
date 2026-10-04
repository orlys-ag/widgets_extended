/// Value types configuring animation timing and easing for the board module.
///
/// [BoardAnimationSpec] is one (duration, curve) pair. [BoardAnimationStyle]
/// carries one spec per animation family, five of them over two roots:
///
/// - [BoardAnimationStyle.trackResize]: a content-sized track's extent
///   changing. A ROOT family.
/// - [BoardAnimationStyle.itemEnterExit]: item insert and remove. Inherits
///   [BoardAnimationStyle.trackResize] when unset, because both animate an
///   EXTENT and because adding an item can grow its own track.
/// - [BoardAnimationStyle.itemSlide]: RECT FLIP for span changes, meaning
///   move, resize, and the re-lane a mutation causes. A ROOT family.
/// - [BoardAnimationStyle.makeRoom]: the drag make-room preview, meaning gap
///   open, re-target and release. Inherits [BoardAnimationStyle.itemSlide]
///   when unset.
/// - [BoardAnimationStyle.dropSettle]: the drop proxy glide and the cancel
///   return. Inherits [BoardAnimationStyle.itemSlide] when unset.
///
/// The unset-to-root mapping above is the whole of it, and the error it
/// exists to prevent is reading [BoardAnimationStyle.itemEnterExit] as
/// falling back to [BoardAnimationStyle.itemSlide]: enter/exit scales an
/// item's whole extent as it arrives or leaves, where a slide moves a
/// rectangle that already exists, so that reading routes an item's
/// enter/exit through the wrong half of every rule below. (A slide's LEAD
/// is paint-only; its EXTENT is layout-driving, as enter/exit is.)
///
/// Inheritance is by UNSET-NESS and is resolved at READ time. Leaving one of
/// the three fallback families null keeps it tracking later restyles of its
/// root, and [BoardAnimationStyle.copyWith] preserves that unset-ness. No
/// install site may copy a resolved spec and hold it: it calls
/// [BoardAnimationStyle.specFor], or the matching `effective` getter, at
/// install and again on every tick.
///
/// A family whose RESOLVED spec has a [Duration.zero] duration is OFF, and
/// that kill switch DOMINATES an explicit per-call duration. There is no
/// master switch: every family gates on its own resolved zero, so an
/// explicitly configured [BoardAnimationStyle.dropSettle] glide still runs
/// when [BoardAnimationStyle.itemSlide] is zeroed, and
/// [BoardAnimationStyle.disabled] is zeros on both ROOTS rather than a flag.
///
/// What a resolved zero MEANS is decided at each install site, not here
/// (refuse the install, snap to target, or complete synchronously,
/// depending on what the family's offset represents); this file only
/// guarantees that the resolution reads above answer per family. A REFUSED
/// install creates no motion and destroys none: its change lands at once,
/// and motion already in flight, of any family, keeps running from the new
/// geometry. Restyling a family to zero at RUNTIME is a separate
/// transition the controller's `animationStyle` setter owns: it stops, at
/// once, the motion of every family the new style resolves to zero, and
/// of no other.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// The animation families a [BoardAnimationStyle] carries. Declared at the
/// site that installs an animation and never re-derived downstream.
enum BoardAnimationFamily {
  /// A content-sized track's extent changing. A root family.
  trackResize,

  /// Item insert and remove. Inherits [trackResize] when unset.
  itemEnterExit,

  /// RECT FLIP for span changes: move, resize, and the re-lane a
  /// mutation causes. A root family.
  itemSlide,

  /// The drag make-room preview: gap open, re-target and release. Inherits
  /// [itemSlide] when unset.
  makeRoom,

  /// The drop proxy glide and the cancel return. Inherits [itemSlide] when
  /// unset.
  dropSettle,
}

/// A (duration, curve) pair for one animation family.
@immutable
class BoardAnimationSpec {
  /// Creates a spec. A [Duration.zero] duration means the family is off;
  /// see the library doc for what "off" resolves to per family kind.
  const BoardAnimationSpec({required this.duration, required this.curve});

  /// Total animation duration. [Duration.zero] means the family snaps
  /// rather than animating. See the library doc for the kill-switch rule.
  final Duration duration;

  /// Easing curve applied over the animation's progress.
  final Curve curve;

  @override
  String toString() {
    return "BoardAnimationSpec(${duration.inMilliseconds}ms, $curve)";
  }
}

/// Timing and easing for every animation family in the board module.
///
/// Immutable value type: pass it to `BoardController(animationStyle: ...)`
/// and restyle at runtime by assigning a new instance. The three fallback
/// families ([itemEnterExit], [makeRoom], [dropSettle]) INHERIT when left
/// unset, meaning they track later changes to the root they fall back to,
/// and [copyWith] preserves that unset-ness.
@immutable
class BoardAnimationStyle {
  /// Builds a style from per-family specs. Leaving [itemEnterExit],
  /// [makeRoom] or [dropSettle] null is NOT the same as passing a copy of
  /// the root it falls back to: null keeps it inheriting, so a later
  /// restyle of that root carries through to it.
  const BoardAnimationStyle({
    this.trackResize = defaultSpec,
    BoardAnimationSpec? itemEnterExit,
    this.itemSlide = defaultSpec,
    BoardAnimationSpec? makeRoom,
    BoardAnimationSpec? dropSettle,
  }) : _itemEnterExit = itemEnterExit,
       _makeRoom = makeRoom,
       _dropSettle = dropSettle;

  /// One spec for all five families: sets both ROOTS to [spec] and leaves
  /// the other three inheriting them, so a later [copyWith] of either root
  /// still carries through.
  const BoardAnimationStyle.uniform(BoardAnimationSpec spec)
    : trackResize = spec,
      itemSlide = spec,
      _itemEnterExit = null,
      _makeRoom = null,
      _dropSettle = null;

  /// The ONE uniform default spec backing every family: 300ms, linear.
  /// A single shared const: there is deliberately no per-family default
  /// literal anywhere else in the module.
  static const BoardAnimationSpec defaultSpec = BoardAnimationSpec(
    duration: Duration(milliseconds: 300),
    curve: Curves.linear,
  );

  /// Every family off: a total animation disable, and the configuration
  /// tests use when they need mutations to settle synchronously. Zeros on
  /// both ROOTS, which the three fallback families inherit; it is not a
  /// master switch, because there is none.
  static const BoardAnimationStyle disabled = BoardAnimationStyle(
    trackResize: BoardAnimationSpec(
      duration: Duration.zero,
      curve: Curves.linear,
    ),
    itemSlide: BoardAnimationSpec(
      duration: Duration.zero,
      curve: Curves.linear,
    ),
  );

  /// Content-sized track resize timing. A root family.
  final BoardAnimationSpec trackResize;

  /// RECT FLIP timing for span changes: an item's corner and extent
  /// decay together from its old rectangle to its new one, and so does
  /// the rectangle of every neighbour the change re-lanes. A root
  /// family, and what a null `duration` or `curve` argument to
  /// `moveItem` or `resizeItem` resolves against.
  final BoardAnimationSpec itemSlide;

  final BoardAnimationSpec? _itemEnterExit;

  final BoardAnimationSpec? _makeRoom;

  final BoardAnimationSpec? _dropSettle;

  /// Item enter/exit timing as configured, or null when inheriting
  /// [trackResize]. Consumers read [effectiveItemEnterExit].
  BoardAnimationSpec? get itemEnterExit {
    return _itemEnterExit;
  }

  /// Make-room preview timing as configured, or null when inheriting
  /// [itemSlide]. Consumers read [effectiveMakeRoom].
  BoardAnimationSpec? get makeRoom {
    return _makeRoom;
  }

  /// Drop-settle glide timing as configured, or null when inheriting
  /// [itemSlide]. Consumers read [effectiveDropSettle].
  BoardAnimationSpec? get dropSettle {
    return _dropSettle;
  }

  /// [itemEnterExit] resolved through its fallback to [trackResize].
  ///
  /// The fallback is [trackResize] and NOT [itemSlide]. Both families
  /// animate an extent, and under the contributor rule adding an item can
  /// grow its own track, so an insert often IS a track resize.
  BoardAnimationSpec get effectiveItemEnterExit {
    return _itemEnterExit ?? trackResize;
  }

  /// [makeRoom] resolved through its fallback to [itemSlide].
  BoardAnimationSpec get effectiveMakeRoom {
    return _makeRoom ?? itemSlide;
  }

  /// [dropSettle] resolved through its fallback to [itemSlide].
  BoardAnimationSpec get effectiveDropSettle {
    return _dropSettle ?? itemSlide;
  }

  /// Resolves [family] to its effective spec, applying the inheritance
  /// chain. The ONE mapping from a declared family to its timing.
  BoardAnimationSpec specFor(BoardAnimationFamily family) {
    switch (family) {
      case BoardAnimationFamily.trackResize:
        return trackResize;
      case BoardAnimationFamily.itemEnterExit:
        return effectiveItemEnterExit;
      case BoardAnimationFamily.itemSlide:
        return itemSlide;
      case BoardAnimationFamily.makeRoom:
        return effectiveMakeRoom;
      case BoardAnimationFamily.dropSettle:
        return effectiveDropSettle;
    }
  }

  /// Debug validation at the injection boundary, meaning
  /// `BoardController`'s constructor and its `animationStyle` setter: every
  /// CONFIGURED duration must be non-negative. A negative duration has no
  /// meaning and would STRAND its animations, because progress can never
  /// reach 1, which for a state-owning family leaves an item exiting
  /// forever. Lives here rather than in the const constructor because Dart
  /// forbids non-const expressions in a const constructor's asserts.
  /// Returns true so it can sit inside an `assert`.
  bool debugValidate() {
    assert(
      !trackResize.duration.isNegative &&
          !(_itemEnterExit?.duration.isNegative ?? false) &&
          !itemSlide.duration.isNegative &&
          !(_makeRoom?.duration.isNegative ?? false) &&
          !(_dropSettle?.duration.isNegative ?? false),
      "BoardAnimationStyle durations must be non-negative: a negative "
      "duration strands its animations, since progress can never complete.",
    );
    return true;
  }

  /// Copies with the given fields replaced. An omitted field keeps its
  /// stored value, INCLUDING a stored "unset" for the three fallback
  /// families, which therefore keep inheriting. Un-setting a fallback
  /// family that was previously set is not expressible; construct a fresh
  /// style.
  BoardAnimationStyle copyWith({
    BoardAnimationSpec? trackResize,
    BoardAnimationSpec? itemEnterExit,
    BoardAnimationSpec? itemSlide,
    BoardAnimationSpec? makeRoom,
    BoardAnimationSpec? dropSettle,
  }) {
    return BoardAnimationStyle(
      trackResize: trackResize ?? this.trackResize,
      itemEnterExit: itemEnterExit ?? _itemEnterExit,
      itemSlide: itemSlide ?? this.itemSlide,
      makeRoom: makeRoom ?? _makeRoom,
      dropSettle: dropSettle ?? _dropSettle,
    );
  }

  @override
  String toString() {
    return "BoardAnimationStyle(trackResize: $trackResize, "
        "itemEnterExit: ${_itemEnterExit ?? "inherit"}, "
        "itemSlide: $itemSlide, "
        "makeRoom: ${_makeRoom ?? "inherit"}, "
        "dropSettle: ${_dropSettle ?? "inherit"})";
  }
}
