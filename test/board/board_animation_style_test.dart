/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 3 (animation style value types). The cases
/// below are `testWidgets` because the Testing Plan's harness rule says
/// `testWidgets` starts at step 3, not because anything here needs a
/// `WidgetTester`: step 3 has no controller and no `vsync`.
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board_animation_style.dart';

void main() {
  // The configured-fallback-wins half of the resolution surface: every
  // other case reads styles whose fallback slots are UNSET, so an
  // implementation whose effective getters return the root
  // unconditionally, whose nullable getters return null unconditionally,
  // and whose copyWith drops its three fallback parameters passed the
  // whole file. This case is the witness for all three arms.
  testWidgets("a set fallback slot wins over its root and survives a root "
      "restyle", (tester) async {
    const slide = BoardAnimationSpec(
      duration: Duration(milliseconds: 149),
      curve: Curves.easeIn,
    );
    const room = BoardAnimationSpec(
      duration: Duration(milliseconds: 271),
      curve: Curves.easeOut,
    );
    const settle = BoardAnimationSpec(
      duration: Duration(milliseconds: 383),
      curve: Curves.easeInOut,
    );
    const enterExit = BoardAnimationSpec(
      duration: Duration(milliseconds: 461),
      curve: Curves.decelerate,
    );
    const slideAfter = BoardAnimationSpec(
      duration: Duration(milliseconds: 587),
      curve: Curves.bounceOut,
    );

    // Set through the CONSTRUCTOR.
    const style = BoardAnimationStyle(
      itemSlide: slide,
      makeRoom: room,
      dropSettle: settle,
      itemEnterExit: enterExit,
    );
    // The stored slots read back as themselves.
    expect(style.makeRoom, same(room));
    expect(style.dropSettle, same(settle));
    expect(style.itemEnterExit, same(enterExit));
    // A set slot beats its root, through the effective getters and
    // through specFor.
    expect(style.effectiveMakeRoom, same(room));
    expect(style.effectiveDropSettle, same(settle));
    expect(style.effectiveItemEnterExit, same(enterExit));
    expect(style.specFor(BoardAnimationFamily.makeRoom), same(room));
    expect(style.specFor(BoardAnimationFamily.dropSettle), same(settle));
    expect(style.specFor(BoardAnimationFamily.itemEnterExit), same(enterExit));

    // A ROOT restyle moves nothing that is set: the three slots keep
    // their own specs while an unset slot would have tracked the root.
    final restyled = style.copyWith(itemSlide: slideAfter);
    expect(restyled.effectiveMakeRoom, same(room));
    expect(restyled.effectiveDropSettle, same(settle));
    expect(restyled.effectiveItemEnterExit, same(enterExit));

    // Set through COPYWITH on a style whose slots are unset.
    final viaCopy = const BoardAnimationStyle().copyWith(makeRoom: room);
    expect(viaCopy.makeRoom, same(room));
    expect(viaCopy.effectiveMakeRoom, same(room));
  });

  // The one place a literal pin is the correct shape: the SUBJECT is the
  // default value. Every other case deliberately chooses specs unequal to
  // defaultSpec, so a typo'd default passes the rest of the file.
  testWidgets("the default-constructed style resolves every family to "
      "defaultSpec", (tester) async {
    const style = BoardAnimationStyle();
    expect(
      BoardAnimationStyle.defaultSpec.duration,
      const Duration(milliseconds: 300),
    );
    expect(BoardAnimationStyle.defaultSpec.curve, Curves.linear);
    for (final family in BoardAnimationFamily.values) {
      expect(
        style.specFor(family),
        same(BoardAnimationStyle.defaultSpec),
        reason: "$family resolves to the default",
      );
    }
  });
  // AC13 inheritance is live.
  // Asserts: effectiveDropSettle before and after assigning a style with a
  // distinctive itemSlide.
  // Falsification: resolving inheritance by copying at construction time
  // returns the old spec and fails.
  testWidgets(
    "leaving dropSettle unset makes it track a later itemSlide restyle",
    (tester) async {
      // Three distinctive specs, no two alike and none equal to
      // defaultSpec, so a fallback to the WRONG root is a visible
      // difference rather than an accidental match. Family FLOW is what is
      // pinned here; the literal numbers are arbitrary and nothing asserts
      // them.
      const trackResize = BoardAnimationSpec(
        duration: Duration(milliseconds: 911),
        curve: Curves.bounceIn,
      );
      const slideBefore = BoardAnimationSpec(
        duration: Duration(milliseconds: 137),
        curve: Curves.easeInCubic,
      );
      const slideAfter = BoardAnimationSpec(
        duration: Duration(milliseconds: 421),
        curve: Curves.easeOutQuart,
      );

      const style = BoardAnimationStyle(
        trackResize: trackResize,
        itemSlide: slideBefore,
      );

      // Identity, not value equality: `BoardAnimationSpec` declares no
      // `operator ==`, and identity is the stronger pin anyway, because it
      // also rejects an implementation that reconstructs an equal spec on
      // the way through.
      expect(
        style.dropSettle,
        isNull,
        reason: "dropSettle was never set, so it must read back UNSET",
      );
      expect(
        style.effectiveDropSettle,
        same(slideBefore),
        reason: "an unset dropSettle resolves through itemSlide",
      );

      // "Assigning a style with a distinctive itemSlide", at step 3's only
      // available door: there is no controller yet, so the restyle is a
      // copyWith that touches the ROOT and nothing else.
      final restyled = style.copyWith(itemSlide: slideAfter);

      expect(
        restyled.dropSettle,
        isNull,
        reason: "copyWith preserves unset-ness, so dropSettle keeps inheriting",
      );
      expect(
        restyled.effectiveDropSettle,
        same(slideAfter),
        reason: "the restyled root carries through to the inheriting family",
      );
      expect(
        restyled.specFor(BoardAnimationFamily.dropSettle),
        same(slideAfter),
        reason:
            "specFor is the ONE family-to-timing mapping and must agree with "
            "effectiveDropSettle, since install sites read it and not the "
            "getter",
      );
    },
  );

  // No AC. The unset-to-root mapping, which the Public Surface section's L2
  // block for this file marks BINDING and where it names
  // `itemEnterExit -> itemSlide` as the specific error to avoid: enter/exit
  // is layout-driving while slide is paint-only, so that reading routes an
  // item's enter/exit down the wrong half of the zero rule and of the
  // restyle transition. AC13 covers the dropSettle arm of inheritance and
  // touches neither root of this one.
  // Asserts: itemEnterExit reads back UNSET; it resolves through
  // trackResize at both doors, the effective getter and specFor; a later
  // itemSlide restyle does NOT move it; a later trackResize restyle does.
  // Falsification: `_itemEnterExit ?? itemSlide`.
  testWidgets(
    "an unset itemEnterExit resolves through trackResize and not itemSlide",
    (tester) async {
      // Four distinctive specs, no two alike and none equal to defaultSpec,
      // so a fallback to the WRONG root is a visible difference rather than
      // an accidental match. Family FLOW is what is pinned; the literal
      // numbers are arbitrary and nothing asserts them.
      const trackResizeBefore = BoardAnimationSpec(
        duration: Duration(milliseconds: 733),
        curve: Curves.decelerate,
      );
      const trackResizeAfter = BoardAnimationSpec(
        duration: Duration(milliseconds: 887),
        curve: Curves.elasticIn,
      );
      const slideBefore = BoardAnimationSpec(
        duration: Duration(milliseconds: 149),
        curve: Curves.easeInBack,
      );
      const slideAfter = BoardAnimationSpec(
        duration: Duration(milliseconds: 251),
        curve: Curves.easeOutBack,
      );

      const style = BoardAnimationStyle(
        trackResize: trackResizeBefore,
        itemSlide: slideBefore,
      );

      expect(
        style.itemEnterExit,
        isNull,
        reason: "itemEnterExit was never set, so it must read back UNSET",
      );
      // Identity, not value equality, for the same reason as the case
      // above: `BoardAnimationSpec` declares no `operator ==`.
      expect(
        style.effectiveItemEnterExit,
        same(trackResizeBefore),
        reason:
            "an unset itemEnterExit resolves through trackResize, which is "
            "the root it shares an EXTENT with, and not through itemSlide",
      );
      expect(
        style.specFor(BoardAnimationFamily.itemEnterExit),
        same(trackResizeBefore),
        reason:
            "specFor is the ONE family-to-timing mapping and must agree with "
            "effectiveItemEnterExit, since install sites read it and not the "
            "getter",
      );

      // The two restyle probes are what separate the roots: a mapping that
      // resolved the right spec once and inherited the wrong root still
      // fails one of them.
      final slideRestyled = style.copyWith(itemSlide: slideAfter);
      expect(
        slideRestyled.effectiveItemEnterExit,
        same(trackResizeBefore),
        reason:
            "restyling the itemSlide root must leave itemEnterExit where it "
            "was: it does not inherit that root",
      );

      final trackRestyled = style.copyWith(trackResize: trackResizeAfter);
      expect(
        trackRestyled.effectiveItemEnterExit,
        same(trackResizeAfter),
        reason:
            "itemEnterExit keeps INHERITING trackResize, so a later restyle "
            "of that root carries through to it",
      );
    },
  );

  // No AC. `BoardAnimationStyle.disabled` is the harness the Testing Plan
  // prescribes for controller tests from step 4 on, so a fallback rooted at
  // the wrong family still resolves to zero under it: the constant masks
  // the defect in every later case, and a break here would read as flake
  // rather than as a broken constant.
  // Asserts: all five families resolve to a zero duration through specFor;
  // the three fallback families stay UNSET, which is HOW disabled reaches
  // them; and a restyle off disabled therefore carries through.
  // Falsification: a disabled that zeroes only itemSlide leaves trackResize
  // and itemEnterExit at the default; one that spells the zeros into all
  // five fields resolves every family to zero and fails the unset
  // assertions and the restyle probe.
  testWidgets("BoardAnimationStyle.disabled resolves every family to zero", (
    tester,
  ) async {
    const disabled = BoardAnimationStyle.disabled;

    // Read through specFor, the door install sites use, one family at a
    // time so no family rides on a neighbour.
    expect(
      disabled.specFor(BoardAnimationFamily.trackResize).duration,
      Duration.zero,
      reason: "trackResize is a ROOT and disabled zeroes it directly",
    );
    expect(
      disabled.specFor(BoardAnimationFamily.itemEnterExit).duration,
      Duration.zero,
      reason:
          "itemEnterExit reaches zero only by INHERITING the zeroed "
          "trackResize; disabled sets no spec for it",
    );
    expect(
      disabled.specFor(BoardAnimationFamily.itemSlide).duration,
      Duration.zero,
      reason: "itemSlide is the other ROOT and disabled zeroes it directly",
    );
    expect(
      disabled.specFor(BoardAnimationFamily.makeRoom).duration,
      Duration.zero,
      reason:
          "makeRoom reaches zero only by INHERITING the zeroed itemSlide; "
          "disabled sets no spec for it",
    );
    expect(
      disabled.specFor(BoardAnimationFamily.dropSettle).duration,
      Duration.zero,
      reason:
          "dropSettle reaches zero only by INHERITING the zeroed itemSlide; "
          "disabled sets no spec for it",
    );

    // Zeros on the two ROOTS and not five spelled-out zeros. Spelling
    // them out resolves the same five values and kills inheritance, so
    // the unset-ness is what has to be asserted, not the resolved zeros.
    expect(
      disabled.itemEnterExit,
      isNull,
      reason: "disabled zeroes trackResize; itemEnterExit stays UNSET",
    );
    expect(
      disabled.makeRoom,
      isNull,
      reason: "disabled zeroes itemSlide; makeRoom stays UNSET",
    );
    expect(
      disabled.dropSettle,
      isNull,
      reason: "disabled zeroes itemSlide; dropSettle stays UNSET",
    );

    // And the consequence, which is what a test restyling off the harness
    // depends on.
    const revived = BoardAnimationSpec(
      duration: Duration(milliseconds: 617),
      curve: Curves.easeInOutCubic,
    );
    final restyled = disabled.copyWith(itemSlide: revived);
    expect(
      restyled.effectiveMakeRoom,
      same(revived),
      reason:
          "restyling one root off disabled revives the families that "
          "inherit it, which five spelled-out zeros could not do",
    );
  });

  // No AC. `debugValidate`, the non-negative duration check the Public
  // Surface section's L2 block declares for the injection boundary. A
  // negative duration is a configuration error, which a debug build
  // reports here and a release build resolves as zero, turning its family
  // off.
  // Asserts: a style whose five slots are all non-negative passes and
  // returns true; a negative duration in each of the five slots throws.
  // Falsification: dropping any single conjunct from the assert accepts a
  // negative duration in that one slot and passes the other five
  // assertions.
  testWidgets(
    "debugValidate rejects a negative duration in any of the five slots",
    (tester) async {
      const ok = BoardAnimationSpec(
        duration: Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      const negative = BoardAnimationSpec(
        duration: Duration(milliseconds: -1),
        curve: Curves.linear,
      );

      // Setup sanity, and falsifiable in both directions it claims: a
      // validator that rejected everything would make the five assertions
      // below hold vacuously, and one returning false would fire at every
      // `assert(style.debugValidate())` site.
      const valid = BoardAnimationStyle(
        trackResize: ok,
        itemEnterExit: ok,
        itemSlide: ok,
        makeRoom: ok,
        dropSettle: ok,
      );
      expect(
        valid.debugValidate(),
        isTrue,
        reason:
            "five non-negative slots pass, and the result is true so the "
            "call can sit inside an assert",
      );

      // One slot at a time, with the other four non-negative, so no slot's
      // rejection rides on a neighbour's.
      expect(
        () {
          const style = BoardAnimationStyle(trackResize: negative);
          return style.debugValidate();
        },
        throwsAssertionError,
        reason: "a negative trackResize is rejected",
      );
      expect(
        () {
          const style = BoardAnimationStyle(itemEnterExit: negative);
          return style.debugValidate();
        },
        throwsAssertionError,
        reason: "a negative itemEnterExit is rejected",
      );
      expect(
        () {
          const style = BoardAnimationStyle(itemSlide: negative);
          return style.debugValidate();
        },
        throwsAssertionError,
        reason: "a negative itemSlide is rejected",
      );
      expect(
        () {
          const style = BoardAnimationStyle(makeRoom: negative);
          return style.debugValidate();
        },
        throwsAssertionError,
        reason: "a negative makeRoom is rejected",
      );
      expect(
        () {
          const style = BoardAnimationStyle(dropSettle: negative);
          return style.debugValidate();
        },
        throwsAssertionError,
        reason: "a negative dropSettle is rejected",
      );
    },
  );

  // No AC. `BoardAnimationStyle.uniform`'s semantics, whose only normative
  // statement is at the Public Surface section: it sets both ROOTS and
  // leaves the other three families INHERITING them, matching the tree's
  // shape (`animation_style.dart:117`). The rejected reading spells the
  // spec into all five fields, and it resolves IDENTICALLY through every
  // `specFor` call, because under `uniform` both roots carry the same spec.
  // Only unset-ness and a restyle separate the two readings, so the value
  // half below cannot stand alone.
  // Asserts: both roots read back as the spec passed in; the three fallback
  // families read back UNSET; all five families resolve to that spec
  // through specFor; a later itemSlide restyle moves makeRoom and
  // dropSettle but NOT itemEnterExit; a later trackResize restyle moves
  // itemEnterExit.
  // Falsification: spelling the spec into all five fields passes every
  // value assertion and reddens the three unset ones and all four restyle
  // probes; setting only one root reddens that root's read-back.
  testWidgets("uniform sets both roots and leaves the other three inheriting", (
    tester,
  ) async {
    // Two distinctive specs, unequal to each other and to defaultSpec, so
    // a wrong root or a stale resolve is a visible difference rather than
    // an accidental match. Family FLOW is what is pinned here; the
    // literal numbers are arbitrary and nothing asserts them.
    const uniformSpec = BoardAnimationSpec(
      duration: Duration(milliseconds: 383),
      curve: Curves.easeInOutBack,
    );
    const restyledSpec = BoardAnimationSpec(
      duration: Duration(milliseconds: 557),
      curve: Curves.fastOutSlowIn,
    );

    // `const` here is load-bearing rather than idiomatic: taking the spec
    // POSITIONALLY is what lets the initializer list assign both roots
    // directly, so this constructor is const where the tree's `uniform`
    // is a `factory`. That property is pinned by COMPILATION and by
    // nothing below it: turning `uniform` into a factory stops this line
    // compiling. No `expect` can carry it, because its falsifier is a
    // compile error rather than a red assertion, and an assertion that
    // cannot go red is worse than none.
    const style = BoardAnimationStyle.uniform(uniformSpec);

    // Identity, not value equality, as in the cases above:
    // `BoardAnimationSpec` declares no `operator ==`, and identity also
    // rejects an implementation that reconstructs an equal spec on the
    // way through.
    expect(
      style.trackResize,
      same(uniformSpec),
      reason: "uniform sets the trackResize ROOT to the spec it is given",
    );
    expect(
      style.itemSlide,
      same(uniformSpec),
      reason: "uniform sets the itemSlide ROOT to the spec it is given",
    );

    // The three fallback families, and this is the half the rejected
    // reading fails: spelling the spec into all five fields resolves the
    // same five values below and ends inheritance.
    expect(
      style.itemEnterExit,
      isNull,
      reason: "uniform sets no spec for itemEnterExit, so it stays UNSET",
    );
    expect(
      style.makeRoom,
      isNull,
      reason: "uniform sets no spec for makeRoom, so it stays UNSET",
    );
    expect(
      style.dropSettle,
      isNull,
      reason: "uniform sets no spec for dropSettle, so it stays UNSET",
    );

    // "One spec for all five families", read through specFor, the door
    // install sites use, one family at a time so no family rides on a
    // neighbour.
    expect(
      style.specFor(BoardAnimationFamily.trackResize),
      same(uniformSpec),
      reason: "trackResize is a ROOT and uniform sets it directly",
    );
    expect(
      style.specFor(BoardAnimationFamily.itemEnterExit),
      same(uniformSpec),
      reason:
          "itemEnterExit reaches the spec only by INHERITING trackResize; "
          "uniform sets no spec for it",
    );
    expect(
      style.specFor(BoardAnimationFamily.itemSlide),
      same(uniformSpec),
      reason: "itemSlide is the other ROOT and uniform sets it directly",
    );
    expect(
      style.specFor(BoardAnimationFamily.makeRoom),
      same(uniformSpec),
      reason:
          "makeRoom reaches the spec only by INHERITING itemSlide; uniform "
          "sets no spec for it",
    );
    expect(
      style.specFor(BoardAnimationFamily.dropSettle),
      same(uniformSpec),
      reason:
          "dropSettle reaches the spec only by INHERITING itemSlide; "
          "uniform sets no spec for it",
    );

    // The restyle probes. Every assertion above holds under the rejected
    // reading and under a fallback rooted at the WRONG family, since both
    // roots carry one spec here; these are what tell those apart.
    final slideRestyled = style.copyWith(itemSlide: restyledSpec);
    expect(
      slideRestyled.effectiveMakeRoom,
      same(restyledSpec),
      reason:
          "makeRoom keeps INHERITING itemSlide, so a later restyle of that "
          "root carries through to it",
    );
    expect(
      slideRestyled.effectiveDropSettle,
      same(restyledSpec),
      reason:
          "dropSettle keeps INHERITING itemSlide, so a later restyle of "
          "that root carries through to it",
    );
    expect(
      slideRestyled.effectiveItemEnterExit,
      same(uniformSpec),
      reason:
          "itemEnterExit inherits trackResize, which the itemSlide restyle "
          "did not touch, so it must stay where uniform put it",
    );

    final trackRestyled = style.copyWith(trackResize: restyledSpec);
    expect(
      trackRestyled.effectiveItemEnterExit,
      same(restyledSpec),
      reason:
          "itemEnterExit keeps INHERITING trackResize, so a later restyle "
          "of that root carries through to it",
    );
  });
}
