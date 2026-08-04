/// Unit tests for [TreeAnimationSpec] / [TreeAnimationStyle]: fallback
/// chain, copyWith unset-ness preservation, value semantics, and the
/// `disabled` / `uniform` conveniences.
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  const specA = TreeAnimationSpec(
    duration: Duration(milliseconds: 111),
    curve: Curves.bounceIn,
  );
  const specB = TreeAnimationSpec(
    duration: Duration(milliseconds: 222),
    curve: Curves.decelerate,
  );

  group("TreeAnimationSpec", () {
    test("value equality and hashCode", () {
      const same = TreeAnimationSpec(
        duration: Duration(milliseconds: 111),
        curve: Curves.bounceIn,
      );
      expect(specA, equals(same));
      expect(specA.hashCode, equals(same.hashCode));
      expect(specA, isNot(equals(specB)));
      expect(
        specA,
        isNot(
          equals(
            const TreeAnimationSpec(
              duration: Duration(milliseconds: 111),
              curve: Curves.decelerate,
            ),
          ),
        ),
      );
    });

    test("copyWith replaces only the given fields", () {
      final retimed = specA.copyWith(
        duration: const Duration(milliseconds: 999),
      );
      expect(retimed.duration, const Duration(milliseconds: 999));
      expect(retimed.curve, Curves.bounceIn);
      final recurved = specA.copyWith(curve: Curves.elasticOut);
      expect(recurved.duration, const Duration(milliseconds: 111));
      expect(recurved.curve, Curves.elasticOut);
    });
  });

  group("TreeAnimationStyle fallback chain", () {
    test("a default-constructed style is uniform: 300ms / linear for "
        "every effective family", () {
      const style = TreeAnimationStyle();
      const expected = TreeAnimationSpec(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      );
      expect(TreeAnimationStyle.defaultSpec, expected);
      expect(style.expandCollapse, expected);
      expect(style.effectiveEnterExit, expected);
      expect(style.reorderSlide, expected);
      expect(style.effectiveMakeRoom, expected);
      expect(style.effectiveDropSettle, expected);
    });

    test("unset fallback families inherit", () {
      const style = TreeAnimationStyle(
        expandCollapse: specA,
        reorderSlide: specB,
      );
      expect(style.enterExit, isNull);
      expect(style.makeRoom, isNull);
      expect(style.dropSettle, isNull);
      expect(style.effectiveEnterExit, specA);
      expect(style.effectiveMakeRoom, specB);
      expect(style.effectiveDropSettle, specB);
    });

    test("set fallback families win over inheritance", () {
      const style = TreeAnimationStyle(
        expandCollapse: specA,
        enterExit: specB,
        reorderSlide: specA,
        makeRoom: specB,
        dropSettle: specB,
      );
      expect(style.effectiveEnterExit, specB);
      expect(style.effectiveMakeRoom, specB);
      expect(style.effectiveDropSettle, specB);
    });
  });

  group("TreeAnimationStyle copyWith", () {
    test("preserves unset-ness of fallback families", () {
      const style = TreeAnimationStyle();
      final restyled = style.copyWith(expandCollapse: specA);
      expect(restyled.enterExit, isNull);
      // Still inheriting: tracks the NEW expandCollapse.
      expect(restyled.effectiveEnterExit, specA);
    });

    test("preserves explicitly set families", () {
      const style = TreeAnimationStyle(enterExit: specB);
      final restyled = style.copyWith(expandCollapse: specA);
      expect(restyled.enterExit, specB);
      expect(restyled.effectiveEnterExit, specB);
    });

    test("replaces only the given fields", () {
      const style = TreeAnimationStyle(
        expandCollapse: specA,
        reorderSlide: specA,
        makeRoom: specA,
      );
      final restyled = style.copyWith(reorderSlide: specB);
      expect(restyled.expandCollapse, specA);
      expect(restyled.reorderSlide, specB);
      expect(restyled.makeRoom, specA);
      expect(restyled.dropSettle, isNull);
    });
  });

  group("TreeAnimationStyle value semantics", () {
    test("equal configurations are equal", () {
      const a = TreeAnimationStyle(expandCollapse: specA, makeRoom: specB);
      const b = TreeAnimationStyle(expandCollapse: specA, makeRoom: specB);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test("an explicitly set family is distinct from an inherited one, "
        "even at equal resolved values", () {
      // Raw-field equality: explicit-set does NOT track later
      // expandCollapse changes, so the two configurations genuinely
      // differ.
      const inherited = TreeAnimationStyle(expandCollapse: specA);
      const explicit = TreeAnimationStyle(
        expandCollapse: specA,
        enterExit: specA,
      );
      expect(inherited.effectiveEnterExit, explicit.effectiveEnterExit);
      expect(inherited, isNot(equals(explicit)));
    });
  });

  group("debugValidate", () {
    test("accepts zero and positive durations", () {
      expect(const TreeAnimationStyle().debugValidate(), isTrue);
      expect(TreeAnimationStyle.disabled.debugValidate(), isTrue);
    });

    test("rejects a negative duration in any family", () {
      const negative = TreeAnimationSpec(
        duration: Duration(milliseconds: -100),
        curve: Curves.linear,
      );
      expect(
        () => const TreeAnimationStyle(expandCollapse: negative)
            .debugValidate(),
        throwsAssertionError,
        reason: "a negative duration strands animations — it must be "
            "rejected at the injection boundary, the one configuration "
            "that is genuinely invalid rather than merely unusual",
      );
      expect(
        () => const TreeAnimationStyle(dropSettle: negative).debugValidate(),
        throwsAssertionError,
      );
    });
  });

  group("disabled and uniform", () {
    test("disabled zeroes every effective family", () {
      const style = TreeAnimationStyle.disabled;
      expect(style.expandCollapse.duration, Duration.zero);
      expect(style.effectiveEnterExit.duration, Duration.zero);
      expect(style.reorderSlide.duration, Duration.zero);
      expect(style.effectiveMakeRoom.duration, Duration.zero);
      expect(style.effectiveDropSettle.duration, Duration.zero);
    });

    test("uniform sets every effective family to the one spec", () {
      final style = TreeAnimationStyle.uniform(
        duration: const Duration(milliseconds: 111),
        curve: Curves.bounceIn,
      );
      expect(style.expandCollapse, specA);
      expect(style.effectiveEnterExit, specA);
      expect(style.reorderSlide, specA);
      expect(style.effectiveMakeRoom, specA);
      expect(style.effectiveDropSettle, specA);
    });
  });
}
