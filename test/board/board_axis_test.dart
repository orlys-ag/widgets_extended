/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 1 (L0 geometry). `BoardSpan`'s endpoint
/// arithmetic lands here too, and has no other home: it lands in the same
/// step as the axes, and a `board_span_test.dart` would be a file outside
/// the 24 stubs the plan counts.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';

void main() {
  // DERIVED name. No AC; board_axis_test.dart is listed under the tests not
  // tied to one criterion.
  // Asserts: the round-trip in each mode.
  // Falsification: not stated in the Testing Plan section.
  test("each mode's offsetOf, trackAt and offsetOfFraction round-trip", () {
    final lazy = LazyContentAxis(6, 30.0);
    // Measured unevenly, so the lazy axis is not secretly uniform and a
    // dropped Fenwick term cannot pass by accident.
    lazy.recordMeasurement(1, 55.0);
    lazy.recordMeasurement(4, 12.0);

    // The same shape on NON-DYADIC numbers. Every extent in the first four
    // entries below is a dyadic rational, which a double holds exactly, so
    // offsetOf and trackAt agree there however differently the two are
    // written. The non-dyadic entries are where a trackAt that inverts a
    // DIFFERENT expression than offsetOf returns track - 1 at a leading
    // edge.
    final lazyOdd = LazyContentAxis(8, 23.4);
    lazyOdd.recordMeasurement(1, 55.7);
    lazyOdd.recordMeasurement(4, 12.3);

    final axes = <String, BoardAxis>{
      "UniformAxis": UniformAxis(6, 40.0),
      "ExplicitAxis": ExplicitAxis(<double>[40, 12, 80, 25, 60, 33]),
      "DerivedAxis": DerivedAxis(6, (track) {
        return 10.0 + track * 7.0;
      }),
      "LazyContentAxis": lazy,
      // One non-dyadic extent per mode. 23.4 and 360/7 are measured
      // discriminators: UniformAxis(2000, 23.4) misresolved 200 of its
      // 2000 leading edges, first at track 3, and 360/7 is the weekday
      // axis of a month calendar on a 360 pixel phone, which misresolved
      // columns 3 and 6.
      "UniformAxis (23.4)": UniformAxis(16, 23.4),
      "UniformAxis (360/7)": UniformAxis(7, 360.0 / 7.0),
      "ExplicitAxis (non-dyadic)": ExplicitAxis(<double>[
        23.4,
        0.7,
        19.9,
        7.3,
        33.3,
        0.1,
      ]),
      "DerivedAxis (non-dyadic)": DerivedAxis(6, (track) {
        return 10.1 + track * 7.3;
      }),
      "LazyContentAxis (non-dyadic)": lazyOdd,
    };

    for (final entry in axes.entries) {
      final label = entry.key;
      final axis = entry.value;
      expect(axis.offsetOf(0), 0.0, reason: "$label offsetOf(0)");
      var running = 0.0;
      for (var track = 0; track < axis.trackCount; track++) {
        expect(
          axis.offsetOf(track),
          closeTo(running, 1e-9),
          reason: "$label offsetOf($track)",
        );
        // offsetOfFraction agrees with offsetOf at integers and
        // interpolates INSIDE the containing track, not across the total.
        expect(
          axis.offsetOfFraction(track.toDouble()),
          closeTo(running, 1e-9),
          reason: "$label offsetOfFraction($track)",
        );
        expect(
          axis.offsetOfFraction(track + 0.25),
          closeTo(running + 0.25 * axis.extentOf(track), 1e-9),
          reason: "$label offsetOfFraction($track + 0.25)",
        );
        // trackAt inverts both, at the leading edge and inside the track.
        // The leading edge probes the axis's OWN offsetOf rather than the
        // running sum: the constraint is that trackAt inverts offsetOf,
        // and on a Fenwick-backed axis the running sum accumulates in a
        // different association and can sit an ulp off the stored edge.
        expect(
          axis.trackAt(axis.offsetOf(track)),
          track,
          reason: "$label trackAt(offsetOf($track))",
        );
        expect(
          axis.trackAt(running + axis.extentOf(track) * 0.5),
          track,
          reason: "$label trackAt(mid of $track)",
        );
        running += axis.extentOf(track);
      }
      expect(
        axis.totalExtent,
        closeTo(running, 1e-9),
        reason: "$label totalExtent",
      );
      // The INTEGRAL endpoint at trackCount, which must return totalExtent
      // rather than range-error: it is what the drag layer's clamp calls,
      // and an implementation that evaluates extentOf(t.floor())
      // unconditionally throws here.
      expect(
        axis.offsetOfFraction(axis.trackCount.toDouble()),
        closeTo(axis.totalExtent, 1e-9),
        reason: "$label offsetOfFraction(trackCount)",
      );
    }
  });

  // DERIVED name. No AC.
  // Asserts: isProvisional per mode.
  // Falsification: not stated in the Testing Plan section.
  test("isProvisional reports per mode", () {
    expect(UniformAxis(4, 40.0).isProvisional, isFalse);
    expect(ExplicitAxis(<double>[40, 12, 80]).isProvisional, isFalse);
    expect(
      DerivedAxis(3, (track) {
        return 40.0;
      }).isProvisional,
      isFalse,
    );

    final lazy = LazyContentAxis(3, 30.0);
    expect(lazy.isProvisional, isTrue);
    expect(lazy.isMeasured(0), isFalse);
    lazy.recordMeasurement(0, 50.0);
    expect(lazy.isMeasured(0), isTrue);
    // Still provisional with tracks 1 and 2 unmeasured.
    expect(lazy.isProvisional, isTrue);
    lazy.recordMeasurement(1, 50.0);
    expect(lazy.isProvisional, isTrue);
    lazy.recordMeasurement(2, 50.0);
    // Fully measured, so NOT provisional, while acceptsMeasurements stays
    // true. That is why acceptsMeasurements and not isProvisional is the
    // predicate for content-sizedness.
    expect(lazy.isProvisional, isFalse);
    expect(lazy.acceptsMeasurements, isTrue);
    // A re-measurement of an already measured track does not reopen it.
    lazy.recordMeasurement(1, 90.0);
    expect(lazy.isProvisional, isFalse);
    // And it lands as a VALUE and not only as a flag. This is the arm the
    // render object takes on every track resize: the delta is added
    // against the extent already stored, so an implementation that added
    // the raw extent instead of the difference, or that skipped the
    // already-measured track, leaves every flag assertion above green.
    expect(lazy.extentOf(1), closeTo(90.0, 1e-9));
    // Exactly one track moved: the neighbours keep their own measurements.
    expect(lazy.extentOf(0), closeTo(50.0, 1e-9));
    expect(lazy.extentOf(2), closeTo(50.0, 1e-9));
    // The offsets after it, and the total, move by the DIFFERENCE of 40
    // and not by the new extent: adding the raw 90 reports 240 here.
    expect(lazy.offsetOf(1), closeTo(50.0, 1e-9));
    expect(lazy.offsetOf(2), closeTo(140.0, 1e-9));
    expect(lazy.totalExtent, closeTo(190.0, 1e-9));
  });

  // DERIVED name. No AC.
  // Asserts: minTrackExtent asserted strictly positive.
  // Falsification: not stated in the Testing Plan section.
  test("minTrackExtent is strictly positive", () {
    // All four report a strictly positive value on legal input.
    expect(UniformAxis(4, 40.0).minTrackExtent, greaterThan(0.0));
    expect(ExplicitAxis(<double>[40, 12, 80]).minTrackExtent, greaterThan(0.0));
    expect(
      DerivedAxis(3, (track) {
        return 40.0;
      }).minTrackExtent,
      greaterThan(0.0),
    );
    expect(LazyContentAxis(3, 30.0).minTrackExtent, greaterThan(0.0));

    // And all four REFUSE input that would make it zero or negative, at the
    // axis boundary rather than at the correction loop, whose termination
    // is derived from this value.
    expect(() {
      return UniformAxis(4, 0.0);
    }, throwsAssertionError);
    expect(() {
      return UniformAxis(4, -1.0);
    }, throwsAssertionError);
    expect(() {
      return ExplicitAxis(<double>[40, 0, 80]);
    }, throwsAssertionError);
    expect(() {
      return ExplicitAxis(<double>[40, -2, 80]);
    }, throwsAssertionError);
    expect(() {
      return DerivedAxis(3, (track) {
        return track == 1 ? 0.0 : 40.0;
      });
    }, throwsAssertionError);
    expect(() {
      return LazyContentAxis(3, 30.0, minTrackExtent: 0.0);
    }, throwsAssertionError);
    expect(() {
      return LazyContentAxis(3, 30.0, minTrackExtent: -1.0);
    }, throwsAssertionError);

    // LazyContentAxis carries two more asserts of the same kind, and they
    // are the ones nothing else constructs a violation of. An estimate of
    // 0 is not an extent, and an estimate BELOW the floor would make an
    // UNMEASURED track report less than the axis's own stated minimum,
    // before a single measurement lands.
    expect(() {
      return LazyContentAxis(3, 0.0);
    }, throwsAssertionError);
    expect(() {
      return LazyContentAxis(3, -1.0);
    }, throwsAssertionError);
    expect(() {
      return LazyContentAxis(3, 5.0, minTrackExtent: 10.0);
    }, throwsAssertionError);
    // The boundary itself is LEGAL: equal is not below, and an axis that
    // rejected it would refuse the ordinary "estimate is the floor" setup.
    expect(
      LazyContentAxis(3, 10.0, minTrackExtent: 10.0).extentOf(0),
      closeTo(10.0, 1e-9),
    );
  });

  // DERIVED name. No AC.
  // Asserts: recordMeasurement asserting on an axis whose
  // acceptsMeasurements is false.
  // Falsification: not stated in the Testing Plan section.
  test("recordMeasurement asserts on an axis whose acceptsMeasurements is "
      "false", () {
    final uniform = UniformAxis(4, 40.0);
    final explicit = ExplicitAxis(<double>[40, 12, 80]);
    final derived = DerivedAxis(3, (track) {
      return 40.0;
    });
    final lazy = LazyContentAxis(3, 30.0);

    // Setup sanity, and it can fail: an implementation that returned
    // acceptsMeasurements true everywhere would leave the three asserts
    // below unreachable.
    expect(uniform.acceptsMeasurements, isFalse);
    expect(explicit.acceptsMeasurements, isFalse);
    expect(derived.acceptsMeasurements, isFalse);
    expect(lazy.acceptsMeasurements, isTrue);

    expect(() {
      return uniform.recordMeasurement(0, 50.0);
    }, throwsAssertionError);
    expect(() {
      return explicit.recordMeasurement(0, 50.0);
    }, throwsAssertionError);
    expect(() {
      return derived.recordMeasurement(0, 50.0);
    }, throwsAssertionError);
    // The one axis that accepts them takes it without complaint.
    lazy.recordMeasurement(0, 50.0);
    expect(lazy.extentOf(0), closeTo(50.0, 1e-9));
  });

  // DERIVED name. No AC; the SOURCE of minTrackExtent, which nothing else
  // pins.
  // Asserts: UniformAxis(10, 40) reports 40, ExplicitAxis([40, 12, 80])
  // reports 12, DerivedAxis reports the minimum over its callback without
  // invoking it more than trackCount times (read through a counting
  // callback, not a new seam), and LazyContentAxis reports its named
  // argument.
  // Falsification: not stated in the Testing Plan section for this case.
  test("minTrackExtent comes from the axis in all four modes", () {
    // UniformAxis: the extent itself, a scalar it already holds.
    expect(UniformAxis(10, 40.0).minTrackExtent, closeTo(40.0, 1e-9));

    // ExplicitAxis: the minimum over the extents, taken in the constructor
    // pass that already builds the prefix.
    expect(
      ExplicitAxis(<double>[40, 12, 80]).minTrackExtent,
      closeTo(12.0, 1e-9),
    );

    // DerivedAxis: the minimum over the trackCount callback results the
    // constructor already takes, adding no invocations to that count.
    const extents = <double>[40, 12, 80, 25, 60];
    var calls = 0;
    final derived = DerivedAxis(extents.length, (track) {
      calls++;
      return extents[track];
    });
    expect(calls, extents.length);
    expect(derived.minTrackExtent, closeTo(12.0, 1e-9));
    // Reading the axis afterwards must not reach the callback again: it is
    // caller code on the per-layout path.
    derived.offsetOf(3);
    derived.extentOf(3);
    derived.trackAt(100.0);
    derived.minTrackExtent;
    derived.totalExtent;
    expect(calls, extents.length);

    // LazyContentAxis: the named constructor argument, because its extents
    // are not known at construction.
    expect(
      LazyContentAxis(10, 40.0, minTrackExtent: 7.0).minTrackExtent,
      closeTo(7.0, 1e-9),
    );
    expect(LazyContentAxis(10, 40.0).minTrackExtent, closeTo(1.0, 1e-9));

    // ExplicitAxis takes the minimum, the prefix and the track count in
    // the constructor, so it COPIES the list it was handed. Holding the
    // caller's reference lets a later mutation make extentOf disagree with
    // all three, and smuggles a zero extent past the constructor assert
    // that minTrackExtent rests on.
    final mutated = <double>[40, 12, 80];
    final copied = ExplicitAxis(mutated);
    mutated[1] = 0.0;
    mutated.add(99.0);
    expect(copied.extentOf(1), closeTo(12.0, 1e-9));
    expect(copied.minTrackExtent, closeTo(12.0, 1e-9));
    expect(copied.trackCount, 3);
    expect(copied.offsetOf(2), closeTo(52.0, 1e-9));
    expect(copied.totalExtent, closeTo(132.0, 1e-9));

    // The EMPTY axis, trackCount 0, which nothing else in the suite
    // constructs. minTrackExtent is unobservable through geometry there,
    // since there is no track for it to bound, so this is the only place
    // it can be read at all; what consumes it is the correction loop's
    // termination, which needs a positive number in hand on a
    // trackCount-0 board.
    expect(UniformAxis(0, 40.0).minTrackExtent, closeTo(40.0, 1e-9));
    expect(ExplicitAxis(<double>[]).minTrackExtent, closeTo(1.0, 1e-9));
    var emptyCalls = 0;
    final emptyDerived = DerivedAxis(0, (track) {
      emptyCalls++;
      return 40.0;
    });
    expect(emptyCalls, 0);
    expect(emptyDerived.minTrackExtent, closeTo(1.0, 1e-9));
    expect(
      LazyContentAxis(0, 30.0, minTrackExtent: 5.0).minTrackExtent,
      closeTo(5.0, 1e-9),
    );
    // The two OUTER modes source it from their own input and not from the
    // shared 1.0 the two middle ones fall back to, which is the
    // distinction one shared constant makes easy to lose.
    expect(UniformAxis(0, 40.0).minTrackExtent, isNot(closeTo(1.0, 1e-9)));
    expect(
      LazyContentAxis(0, 30.0, minTrackExtent: 5.0).minTrackExtent,
      isNot(closeTo(1.0, 1e-9)),
    );
    // And an empty axis stays callable: trackAt returns the placeholder 0
    // that no caller may dereference, totalExtent is 0, and
    // offsetOfFraction's domain has collapsed to the single point 0.0.
    expect(UniformAxis(0, 40.0).trackAt(37.0), 0);
    expect(ExplicitAxis(<double>[]).trackAt(37.0), 0);
    expect(emptyDerived.trackAt(37.0), 0);
    expect(LazyContentAxis(0, 30.0).trackAt(37.0), 0);
    expect(UniformAxis(0, 40.0).totalExtent, closeTo(0.0, 1e-9));
    expect(ExplicitAxis(<double>[]).totalExtent, closeTo(0.0, 1e-9));
    expect(emptyDerived.totalExtent, closeTo(0.0, 1e-9));
    expect(LazyContentAxis(0, 30.0).totalExtent, closeTo(0.0, 1e-9));
    expect(emptyDerived.offsetOfFraction(0.0), closeTo(0.0, 1e-9));
    expect(emptyCalls, 0);
  });

  // DERIVED name. No AC; the floor, which is the case R-8 is about.
  // Asserts: recordMeasurement(t, 0) on a LazyContentAxis leaves
  // extentOf(t) at minTrackExtent, and totalExtent grows by that and not by
  // zero.
  // Falsification: an implementation that stores the raw 0 passes every
  // other assertion in this file and fails these two.
  test(
    "recordMeasurement of 0 on a LazyContentAxis floors at minTrackExtent",
    () {
      const trackCount = 4;
      const estimate = 40.0;
      const floor = 3.0;
      final axis = LazyContentAxis(trackCount, estimate, minTrackExtent: floor);
      expect(axis.totalExtent, closeTo(trackCount * estimate, 1e-9));

      // A zero measurement is reachable from LEGAL input: an empty
      // content-sized track with no cell content, no items and no lane
      // padding resolves to 0. It floors rather than asserting.
      axis.recordMeasurement(1, 0.0);

      expect(axis.extentOf(1), closeTo(floor, 1e-9));
      expect(axis.isMeasured(1), isTrue);
      // The track contributes the floor and NOT zero, so the total is the
      // three unmeasured estimates plus the floor. An implementation storing
      // the raw 0 reports 120.
      expect(
        axis.totalExtent,
        closeTo((trackCount - 1) * estimate + floor, 1e-9),
      );
      // And the offsets after it move by the floor, not by zero.
      expect(axis.offsetOf(2), closeTo(estimate + floor, 1e-9));

      // A negative measurement floors the same way, which is the other side
      // of the same clamp.
      axis.recordMeasurement(2, -50.0);
      expect(axis.extentOf(2), closeTo(floor, 1e-9));

      // The floor survives RE-MEASUREMENT, which flooring only the write
      // does not give. extentOf recovers a track's extent as the
      // difference of two prefix sums, and recordMeasurement stores
      // `floored - current` against that recovered value, so the stored
      // delta random-walks and a floored track drifts BELOW the floor:
      // this script, deterministic on its seed, put three of its 64 tracks
      // under 1.0 when the read did not floor, the worst at 0.98828125.
      const drifted = 64;
      final walked = LazyContentAxis(drifted, 20.0, minTrackExtent: floor);
      final random = math.Random(20260901);
      for (var i = 0; i < 200; i++) {
        // Alternating an empty track with a large one is what moves the
        // shared Fenwick nodes between the two prefix reads.
        walked.recordMeasurement(
          random.nextInt(drifted),
          i.isEven ? 0.0 : random.nextDouble() * 1e12,
        );
      }
      var atTheFloor = 0;
      for (var track = 0; track < drifted; track++) {
        expect(
          walked.extentOf(track),
          greaterThanOrEqualTo(walked.minTrackExtent),
          reason: "extentOf($track) after re-measurement",
        );
        if (walked.extentOf(track) == walked.minTrackExtent) {
          atTheFloor++;
        }
      }
      // Setup sanity, and it can fail: a script that never floored a track
      // would leave every extent large, and the loop above would pass
      // without touching the clamp it is written against.
      expect(atTheFloor, greaterThan(0));
    },
  );

  // DERIVED name. No AC; BoardSpan's ENDPOINT arithmetic, which the Testing
  // Plan adds to this file because it lands in the same step and has no
  // other home.
  // Asserts: startTrackOn and endTrackOn on a span with both fractions
  // non-zero, endTrackOn on a span of 0 with a non-zero span fraction (the
  // sub-track item), and the assert pair rejecting a zero extent.
  // Falsification: an implementation that returns startOn + spanOn from
  // endTrackOn passes every integer case and fails the first.
  test("BoardSpan's endpoint arithmetic carries both fractions", () {
    // 09:15 to 10:45 on an hour axis: track 9 plus 0.25, extent 1 plus 0.5.
    const event = BoardSpan(
      rowStart: 9,
      colStart: 2,
      rowSpan: 1,
      colSpan: 3,
      rowFraction: 0.25,
      colFraction: 0.5,
      rowSpanFraction: 0.5,
      colSpanFraction: 0.25,
    );
    expect(event.startTrackOn(Axis.vertical), closeTo(9.25, 1e-9));
    expect(event.endTrackOn(Axis.vertical), closeTo(10.75, 1e-9));
    expect(event.startTrackOn(Axis.horizontal), closeTo(2.5, 1e-9));
    expect(event.endTrackOn(Axis.horizontal), closeTo(5.75, 1e-9));
    // The residual hazard, made visible: startOn plus spanOn is NEITHER
    // endpoint once a fraction is non-zero, which is why the two accessors
    // are the only sanctioned route.
    expect(event.startOn(Axis.vertical) + event.spanOn(Axis.vertical), 10);
    expect(event.endTrackOn(Axis.vertical), isNot(closeTo(10.0, 1e-9)));

    // An integer span still reads as the integer through both accessors.
    const plain = BoardSpan(rowStart: 3, colStart: 4, rowSpan: 2, colSpan: 1);
    expect(plain.startTrackOn(Axis.vertical), closeTo(3.0, 1e-9));
    expect(plain.endTrackOn(Axis.vertical), closeTo(5.0, 1e-9));
    expect(plain.startTrackOn(Axis.horizontal), closeTo(4.0, 1e-9));
    expect(plain.endTrackOn(Axis.horizontal), closeTo(5.0, 1e-9));

    // The SUB-TRACK item: a span of 0 with a non-zero span fraction is
    // LEGAL and is how a quarter-track item is represented.
    const quarter = BoardSpan(
      rowStart: 3,
      colStart: 1,
      rowSpan: 1,
      colSpan: 0,
      colSpanFraction: 0.25,
    );
    expect(quarter.startTrackOn(Axis.horizontal), closeTo(1.0, 1e-9));
    expect(quarter.endTrackOn(Axis.horizontal), closeTo(1.25, 1e-9));
    expect(quarter.spanOn(Axis.horizontal), 0);

    // The assert PAIR: the integer span may be 0, but the EXTENT may not.
    expect(() {
      return BoardSpan(rowStart: 0, colStart: 0, rowSpan: 0);
    }, throwsAssertionError);
    expect(() {
      return BoardSpan(rowStart: 0, colStart: 0, colSpan: 0);
    }, throwsAssertionError);
    // A fraction of 1.0 or more belongs in the integer part.
    expect(() {
      return BoardSpan(rowStart: 0, colStart: 0, rowFraction: 1.0);
    }, throwsAssertionError);
    expect(() {
      return BoardSpan(rowStart: 0, colStart: 0, rowSpanFraction: 1.0);
    }, throwsAssertionError);
    // Negative starts are not track coordinates.
    expect(() {
      return BoardSpan(rowStart: -1, colStart: 0);
    }, throwsAssertionError);

    // VALUE EQUALITY over all eight fields, in the same case. The drag
    // layer's re-target test compares the previous target with the new one
    // and notifies only on a difference, and it is the only other
    // consumer: it compares ONE previous target with ONE new one, so an
    // operator == that omits a field stays green there for as long as the
    // script never varies only that field.
    final same = event.copyWith();
    // Setup sanity, and it can fail: two CONST spans built from the same
    // eight arguments are canonicalized to one instance and operator ==
    // short-circuits on identical, which would leave the pair below inert.
    expect(identical(event, same), isFalse);
    // And the copy really did carry all eight across, so the pair differs
    // in nothing. Without these, a copyWith that dropped a field would red
    // the equality assertion and read as an operator == defect.
    expect(same.rowStart, event.rowStart);
    expect(same.colStart, event.colStart);
    expect(same.rowSpan, event.rowSpan);
    expect(same.colSpan, event.colSpan);
    expect(same.rowFraction, event.rowFraction);
    expect(same.colFraction, event.colFraction);
    expect(same.rowSpanFraction, event.rowSpanFraction);
    expect(same.colSpanFraction, event.colSpanFraction);
    expect(same == event, isTrue);
    // hashCode is asserted on the EQUAL pair only: unequal hashes are not
    // required of it.
    expect(same.hashCode, event.hashCode);

    // Eight spans, each differing from the baseline in exactly ONE of the
    // eight fields. One field at a time is the point: rowSpanFraction and
    // colSpanFraction are the two a drag script is least likely to vary
    // alone.
    final oneFieldApart = <String, BoardSpan>{
      "rowStart": event.copyWith(rowStart: 8),
      "colStart": event.copyWith(colStart: 3),
      "rowSpan": event.copyWith(rowSpan: 2),
      "colSpan": event.copyWith(colSpan: 4),
      "rowFraction": event.copyWith(rowFraction: 0.75),
      "colFraction": event.copyWith(colFraction: 0.75),
      "rowSpanFraction": event.copyWith(rowSpanFraction: 0.75),
      "colSpanFraction": event.copyWith(colSpanFraction: 0.75),
    };
    for (final entry in oneFieldApart.entries) {
      expect(
        entry.value == event,
        isFalse,
        reason: "a span differing only in ${entry.key} compared equal",
      );
    }

    // A fraction that VANISHES at the span's own magnitude must be
    // rejected at construction: 5.0 + 1e-17 == 5.0, so the span's
    // endpoints coincide, its extent is zero in track space, and its
    // bucket range is empty, which used to surface as the span INDEX's
    // assert instead of the constructor's.
    expect(() {
      BoardSpan(rowStart: 5, colStart: 0, rowSpan: 0, rowSpanFraction: 1e-17);
    }, throwsAssertionError);
    expect(() {
      BoardSpan(rowStart: 0, colStart: 7, colSpan: 0, colSpanFraction: 1e-17);
    }, throwsAssertionError);
  });

  // DERIVED name, and a NEW case: BoardAxisConfig's four asserts have no
  // coverage anywhere under test/board, and no case in this file is about
  // the config rather than the axis it carries.
  // Asserts: each of the four rejects the value that has no meaning, and
  // the legal boundaries are accepted.
  // Falsification: an implementation that dropped any one of the four
  // passes every other case in the suite.
  test("BoardAxisConfig refuses a value that has no meaning", () {
    // The defaults, which are also the legal BOUNDARIES: zero frozen
    // bands, no laneExtent at all, and a lanePadding of exactly 0.
    final plain = BoardAxisConfig(axis: UniformAxis(6, 40.0));
    expect(plain.frozenStart, 0);
    expect(plain.frozenEnd, 0);
    expect(plain.laneExtent, isNull);
    expect(plain.lanePadding, 0.0);
    expect(plain.alignment, TrackAlignment.stretch);

    // A fully populated config: a non-null laneExtent is what makes this
    // the LANE axis.
    final laned = BoardAxisConfig(
      axis: UniformAxis(6, 40.0),
      frozenStart: 1,
      frozenEnd: 2,
      alignment: TrackAlignment.center,
      laneExtent: 12.0,
      lanePadding: 4.0,
    );
    expect(laned.frozenStart, 1);
    expect(laned.frozenEnd, 2);
    expect(laned.alignment, TrackAlignment.center);
    expect(laned.laneExtent, closeTo(12.0, 1e-9));
    expect(laned.lanePadding, closeTo(4.0, 1e-9));

    // A negative frozen count would index a band backwards.
    expect(() {
      return BoardAxisConfig(axis: UniformAxis(6, 40.0), frozenStart: -1);
    }, throwsAssertionError);
    expect(() {
      return BoardAxisConfig(axis: UniformAxis(6, 40.0), frozenEnd: -1);
    }, throwsAssertionError);
    // A laneExtent of 0 leaves the axis named as the lane axis while
    // making the lane count stop mattering, so its lanes would have no
    // width at all.
    expect(() {
      return BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: 0.0);
    }, throwsAssertionError);
    expect(() {
      return BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: -12.0);
    }, throwsAssertionError);
    // A negative lanePadding moves lane 0 outside its own track.
    expect(() {
      return BoardAxisConfig(axis: UniformAxis(6, 40.0), lanePadding: -1.0);
    }, throwsAssertionError);
  });

  group("BoardAxisConfigBands", () {
    test("with no band, both bounds sit at the axis ends and no track is "
        "frozen", () {
      final config = BoardAxisConfig(axis: LazyContentAxis(4, 100.0));
      expect(config.leadingBandEnd, 0);
      expect(config.trailingBandStart, 4);
      expect(config.frozenTracks.toList(), isEmpty);
      for (var track = 0; track < 4; track++) {
        expect(config.isFrozenTrack(track), isFalse);
      }
    });

    test("with no band, both extents are zero and the trailing one reads "
        "no prefix sum", () {
      final axis = LazyContentAxis(4, 100.0);
      final config = BoardAxisConfig(axis: axis);
      expect(config.leadingBandExtent, 0.0);
      axis.debugFenwick.debugOpCount = 0;
      final trailing = config.trailingBandExtent;
      final operations = axis.debugFenwick.debugOpCount;
      expect(trailing, 0.0);
      // This axis answers `totalExtent` and `offsetOf` from prefix sums, so
      // only the no-band return keeps the count at zero.
      expect(operations, 0);
    });

    test("disjoint bands bound, list and measure their own tracks", () {
      // Distinct extents, so an extent derived from the first track's
      // alone is told from the axis's own offset.
      final axis = ExplicitAxis(<double>[
        10.0,
        20.0,
        30.0,
        40.0,
        50.0,
        60.0,
        70.0,
        80.0,
        90.0,
        100.0,
      ]);
      final config = BoardAxisConfig(axis: axis, frozenStart: 2, frozenEnd: 3);
      expect(config.leadingBandEnd, 2);
      expect(config.trailingBandStart, 7);
      expect(config.leadingBandExtent, axis.offsetOf(2));
      expect(config.trailingBandExtent, axis.totalExtent - axis.offsetOf(7));
      expect(config.frozenTracks.toList(), <int>[0, 1, 7, 8, 9]);
      expect(config.isFrozenTrack(1), isTrue);
      expect(config.isFrozenTrack(7), isTrue);
      expect(config.isFrozenTrack(2), isFalse);
      expect(config.isFrozenTrack(6), isFalse);
    });

    test("overlapping bands leave the shared tracks to the leading band", () {
      final axis = ExplicitAxis(<double>[10.0, 20.0, 30.0, 40.0, 50.0]);
      final config = BoardAxisConfig(axis: axis, frozenStart: 3, frozenEnd: 3);
      expect(config.trailingBandStart, 3);
      expect(config.trailingBandExtent, axis.totalExtent - axis.offsetOf(3));
    });

    test("a band extent reads the axis's current measurements", () {
      final axis = LazyContentAxis(4, 100.0);
      final config = BoardAxisConfig(axis: axis, frozenStart: 1);
      expect(config.leadingBandExtent, 100.0);
      axis.recordMeasurement(0, 40.0);
      expect(config.leadingBandExtent, 40.0);
    });
  });
}
