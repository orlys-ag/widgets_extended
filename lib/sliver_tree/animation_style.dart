/// Value types configuring animation timing and easing for the sliver
/// tree stack.
///
/// [TreeAnimationSpec] is one (duration, curve) pair. [TreeAnimationStyle]
/// carries one spec per animation family:
///
/// - [TreeAnimationStyle.expandCollapse] — expand/collapse operation
///   groups, bulk expandAll/collapseAll, and the scroll orchestrator's
///   animated-concurrent mode gate.
/// - [TreeAnimationStyle.enterExit] — node enter/exit rows
///   (insert/remove); inherits `expandCollapse` when unset.
/// - [TreeAnimationStyle.reorderSlide] — FLIP reorder slides (`moveNode`,
///   `reorderRoots`/`reorderChildren`, `animateSlideFromOffsets`, the
///   drag-commit baseline).
/// - [TreeAnimationStyle.makeRoom] — the drag make-room preview
///   (gap open/re-target/release); inherits `reorderSlide` when unset.
/// - [TreeAnimationStyle.dropSettle] — the drag proxy settle glides
///   (commit handoff and cancel return); inherits `reorderSlide` when
///   unset.
///
/// A family whose resolved spec has [Duration.zero] duration is OFF: it
/// snaps instead of animating, and that kill switch dominates explicit
/// per-call durations. [TreeAnimationStyle.disabled] turns every family
/// off — the canonical synchronous-test configuration. Every family
/// gates on its OWN resolved zero: in particular, `dropSettle` glides
/// run even when `reorderSlide` is zeroed (the drop commits instantly
/// and the card settles into its new slot).
///
/// The zero rule splits two meanings cleanly: a zero family CREATES no
/// motion (installs are refused; other families' in-flight animations
/// are untouched and re-base seamlessly across concurrent structural
/// changes), while DISABLING — restyling `reorderSlide` to zero at
/// runtime — STOPS in-flight slide motion at the transition.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// A (duration, curve) pair for one animation family.
@immutable
class TreeAnimationSpec {
  const TreeAnimationSpec({required this.duration, required this.curve});

  /// Total animation duration. [Duration.zero] means the family snaps
  /// (no animation) — see the library docs for the kill-switch rule.
  final Duration duration;

  /// Easing curve applied over the animation's progress.
  final Curve curve;

  TreeAnimationSpec copyWith({Duration? duration, Curve? curve}) {
    return TreeAnimationSpec(
      duration: duration ?? this.duration,
      curve: curve ?? this.curve,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TreeAnimationSpec &&
        other.duration == duration &&
        other.curve == curve;
  }

  @override
  int get hashCode {
    return Object.hash(duration, curve);
  }

  @override
  String toString() {
    return "TreeAnimationSpec(${duration.inMilliseconds}ms, $curve)";
  }
}

/// Timing/easing for every animation family in the sliver tree stack.
///
/// Immutable value type: pass to `TreeController(animationStyle: ...)`
/// (or the declarative widgets) and restyle at runtime by assigning a
/// new instance. Unset fallback families ([enterExit], [makeRoom],
/// [dropSettle]) INHERIT — they track later changes to the family they
/// fall back to, and [copyWith] preserves that unset-ness.
@immutable
class TreeAnimationStyle {
  const TreeAnimationStyle({
    this.expandCollapse = defaultSpec,
    TreeAnimationSpec? enterExit,
    this.reorderSlide = defaultSpec,
    TreeAnimationSpec? makeRoom,
    TreeAnimationSpec? dropSettle,
  }) : _enterExit = enterExit,
       _makeRoom = makeRoom,
       _dropSettle = dropSettle;

  /// One spec for all five families.
  factory TreeAnimationStyle.uniform({
    required Duration duration,
    required Curve curve,
  }) {
    final spec = TreeAnimationSpec(duration: duration, curve: curve);
    return TreeAnimationStyle(expandCollapse: spec, reorderSlide: spec);
  }

  /// The ONE uniform default spec backing every family: 300ms, linear.
  /// A single shared const — there is deliberately no per-family default
  /// literal anywhere else in the package.
  static const TreeAnimationSpec defaultSpec = TreeAnimationSpec(
    duration: Duration(milliseconds: 300),
    curve: Curves.linear,
  );

  /// Every family off — total animation disable. The replacement for
  /// the old `animationDuration: Duration.zero` testing idiom.
  static const TreeAnimationStyle disabled = TreeAnimationStyle(
    expandCollapse: TreeAnimationSpec(
      duration: Duration.zero,
      curve: Curves.linear,
    ),
    reorderSlide: TreeAnimationSpec(
      duration: Duration.zero,
      curve: Curves.linear,
    ),
  );

  /// Expand/collapse timing: per-operation groups and bulk
  /// expandAll/collapseAll.
  final TreeAnimationSpec expandCollapse;

  final TreeAnimationSpec? _enterExit;

  final TreeAnimationSpec? _makeRoom;

  final TreeAnimationSpec? _dropSettle;

  /// FLIP reorder-slide timing: `moveNode`, `reorderRoots`/
  /// `reorderChildren`, `animateSlideFromOffsets`, drag-commit slides.
  final TreeAnimationSpec reorderSlide;

  /// Node enter/exit (insert/remove) timing as configured, or null when
  /// inheriting [expandCollapse]. Consumers read [effectiveEnterExit].
  TreeAnimationSpec? get enterExit {
    return _enterExit;
  }

  /// Make-room preview timing as configured, or null when inheriting
  /// [reorderSlide]. Consumers read [effectiveMakeRoom].
  TreeAnimationSpec? get makeRoom {
    return _makeRoom;
  }

  /// Drop-settle glide timing as configured, or null when inheriting
  /// [reorderSlide]. Consumers read [effectiveDropSettle].
  TreeAnimationSpec? get dropSettle {
    return _dropSettle;
  }

  /// [enterExit] resolved through its fallback to [expandCollapse].
  TreeAnimationSpec get effectiveEnterExit {
    return _enterExit ?? expandCollapse;
  }

  /// [makeRoom] resolved through its fallback to [reorderSlide].
  TreeAnimationSpec get effectiveMakeRoom {
    return _makeRoom ?? reorderSlide;
  }

  /// [dropSettle] resolved through its fallback to [reorderSlide].
  TreeAnimationSpec get effectiveDropSettle {
    return _dropSettle ?? reorderSlide;
  }

  /// Debug validation at the injection boundary ([TreeController]'s
  /// constructor and `animationStyle` setter): every configured
  /// duration must be non-negative. A negative duration has no meaning
  /// and would STRAND animations — progress can never reach 1, which
  /// blocks `hasActiveAnimations`-gated machinery (eviction deferral,
  /// sticky precomputation). Lives here rather than in the const
  /// constructor because Dart forbids non-const expressions in const
  /// ctor asserts. Returns true so it can sit inside an `assert`.
  bool debugValidate() {
    assert(
      !expandCollapse.duration.isNegative &&
          !(_enterExit?.duration.isNegative ?? false) &&
          !reorderSlide.duration.isNegative &&
          !(_makeRoom?.duration.isNegative ?? false) &&
          !(_dropSettle?.duration.isNegative ?? false),
      "TreeAnimationStyle durations must be non-negative — a negative "
      "duration strands its animations (progress can never complete).",
    );
    return true;
  }

  /// Copies with the given fields replaced. Omitted fields keep their
  /// stored value — including stored "unset" for the fallback families,
  /// which therefore keep inheriting. (Un-setting a previously set
  /// fallback family is not expressible; construct a fresh style.)
  TreeAnimationStyle copyWith({
    TreeAnimationSpec? expandCollapse,
    TreeAnimationSpec? enterExit,
    TreeAnimationSpec? reorderSlide,
    TreeAnimationSpec? makeRoom,
    TreeAnimationSpec? dropSettle,
  }) {
    return TreeAnimationStyle(
      expandCollapse: expandCollapse ?? this.expandCollapse,
      enterExit: enterExit ?? _enterExit,
      reorderSlide: reorderSlide ?? this.reorderSlide,
      makeRoom: makeRoom ?? _makeRoom,
      dropSettle: dropSettle ?? _dropSettle,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TreeAnimationStyle &&
        other.expandCollapse == expandCollapse &&
        other._enterExit == _enterExit &&
        other.reorderSlide == reorderSlide &&
        other._makeRoom == _makeRoom &&
        other._dropSettle == _dropSettle;
  }

  @override
  int get hashCode {
    return Object.hash(
      expandCollapse,
      _enterExit,
      reorderSlide,
      _makeRoom,
      _dropSettle,
    );
  }

  @override
  String toString() {
    return "TreeAnimationStyle(expandCollapse: $expandCollapse, "
        "enterExit: ${_enterExit ?? "inherit"}, "
        "reorderSlide: $reorderSlide, "
        "makeRoom: ${_makeRoom ?? "inherit"}, "
        "dropSettle: ${_dropSettle ?? "inherit"})";
  }
}
