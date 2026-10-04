/// L0 axis geometry for the board module: the [BoardAxis] interface, its
/// four implementations, [BoardAxisConfig] and [TrackAlignment].
///
/// Every offset and extent below is BOARD CONTENT space: pixels along one
/// axis measured from that axis's leading edge. Track indices and the
/// `double track` argument of [BoardAxis.offsetOfFraction] are TRACK
/// space. Reversal is not applied here; the viewport applies it.
library;

import 'package:flutter/foundation.dart';

import '_fenwick.dart';

/// What a cell does with the surplus when the resolved track extent
/// exceeds what the cell asked for.
///
/// Consumed at exactly one site, the cell placement step of the board's
/// layout, and never applied to items: an item's position on the lane axis
/// is fully determined by its lane and on the span axis by its span, so
/// there is no residue for an alignment to place.
enum TrackAlignment {
  /// Lay the cell out tight at the resolved track extent, so there is no
  /// surplus to place. The default.
  stretch,

  /// Lay the cell out loose and leave it at the leading edge.
  start,

  /// Lay the cell out loose and centre it in the surplus.
  center,

  /// Lay the cell out loose and push it to the trailing edge.
  end,
}

/// Extent an axis with no tracks at all reports as its minimum, where
/// there is no track for it to bound. One logical pixel, the same value
/// [LazyContentAxis] defaults to.
const double _emptyAxisMinTrackExtent = 1.0;

/// The extent and offset model for one board axis.
///
/// The four implementations differ in where their extents come from and in
/// what they cost to build. Only [LazyContentAxis] returns
/// [acceptsMeasurements] true, and only it can report [isProvisional]
/// true.
abstract interface class BoardAxis {
  /// Number of tracks, indexed `[0, trackCount)`. Constant for the
  /// instance's life: a lattice of another size is a new axis, assigned
  /// through the config.
  int get trackCount;

  /// Extent of [track], in content space.
  double extentOf(int track);

  /// Content-space offset of [track]'s leading edge.
  double offsetOf(int track);

  /// Content-space offset of a FRACTIONAL track coordinate: linear
  /// interpolation inside the containing track,
  /// `offsetOf(t.floor()) + (t - t.floor()) * extentOf(t.floor())`.
  ///
  /// For an integral [track] this returns `offsetOf(track.toInt())`
  /// WITHOUT evaluating [extentOf], which is what makes
  /// `offsetOfFraction(trackCount.toDouble())` a legal call returning
  /// [totalExtent] rather than a range error.
  double offsetOfFraction(double track);

  /// The track containing the content-space [offset], clamped into
  /// `[0, trackCount - 1]`. Returns 0 on an axis with no tracks, which no
  /// caller may dereference.
  ///
  /// The interval is HALF-OPEN, so an offset exactly at a leading edge
  /// belongs to the HIGHER track and `trackAt(offsetOf(t))` is `t` for
  /// every track. That round-trip is a CONSTRAINT on the pair, not a
  /// consequence of either: an implementation whose search evaluates a
  /// different floating-point expression than its own [offsetOf] answers
  /// one track low at an exact edge, which is what
  /// [_correctToOffsetOf] exists to repair.
  int trackAt(double offset);

  /// Sum of every track's extent, in content space.
  double get totalExtent;

  /// The documented [totalExtent] ceiling, 1e12 logical pixels.
  ///
  /// Scroll positions work in doubles, and measured-delta arithmetic
  /// demonstrably random-walks near this scale (see the recovered-value
  /// note in `LazyContentAxis.extentOf`), so an axis REFUSES a larger
  /// total at construction instead of silently losing pixels at the far
  /// end.
  static const double maxTotalExtent = 1.0e12;

  /// Whether any track's extent is still an estimate.
  bool get isProvisional;

  /// Smallest extent this axis can ever report, strictly positive.
  ///
  /// The layout correction loop's termination is derived from it. Every
  /// implementation SOURCES this at construction and every path that could
  /// lower an extent below it floors there.
  double get minTrackExtent;

  /// Whether layout may feed measured extents back into this axis. True
  /// only for [LazyContentAxis].
  ///
  /// This is the predicate for CONTENT-SIZEDNESS. [isProvisional] cannot
  /// stand in for it: a [LazyContentAxis] whose tracks have all been
  /// measured reports [isProvisional] false while still accepting
  /// measurements.
  bool get acceptsMeasurements;

  /// Whether [track] already has a measured, non-estimated extent.
  bool isMeasured(int track);

  /// Records a measured extent, floored at [minTrackExtent]. Asserts
  /// [acceptsMeasurements].
  void recordMeasurement(int track, double extent);
}

/// Every track the same extent. Two scalars of storage, O(1) offsets and
/// O(1) [trackAt], and no prefix is ever built, so a swap costs this axis
/// nothing.
class UniformAxis implements BoardAxis {
  /// Creates an axis of [trackCount] tracks, each [extent] long.
  UniformAxis(this.trackCount, this.extent)
    : assert(trackCount >= 0),
      assert(
        extent > 0.0,
        "UniformAxis extent is its minTrackExtent and must be strictly "
        "positive",
      ),
      assert(
        trackCount * extent <= BoardAxis.maxTotalExtent,
        "UniformAxis total ${trackCount * extent} exceeds "
        "BoardAxis.maxTotalExtent",
      );

  @override
  final int trackCount;

  /// The one extent every track reports.
  final double extent;

  @override
  double extentOf(int track) {
    assert(track >= 0 && track < trackCount);
    return extent;
  }

  @override
  double offsetOf(int track) {
    assert(track >= 0 && track <= trackCount);
    return track * extent;
  }

  @override
  double offsetOfFraction(double track) {
    assert(track >= 0.0 && track <= trackCount);
    return track * extent;
  }

  @override
  int trackAt(double offset) {
    if (trackCount == 0) {
      return 0;
    }
    // The documented clamp for an offset the division cannot take: it
    // throws for a non-finite double. The answers are the ones the prefix
    // search gives the other three axes, NaN and negative infinity to the
    // first track and positive infinity to the last.
    if (!offset.isFinite) {
      return offset == double.infinity ? trackCount - 1 : 0;
    }
    // The division is an APPROXIMATION of the inverse of [offsetOf], not
    // the inverse: `offset ~/ extent` and `track * extent` are different
    // expressions in IEEE doubles and disagree by an ulp at a leading
    // edge, so the raw answer is corrected against offsetOf itself.
    return _correctToOffsetOf(this, offset ~/ extent, offset);
  }

  @override
  double get totalExtent {
    return trackCount * extent;
  }

  @override
  bool get isProvisional {
    return false;
  }

  @override
  double get minTrackExtent {
    return extent;
  }

  @override
  bool get acceptsMeasurements {
    return false;
  }

  @override
  bool isMeasured(int track) {
    return true;
  }

  @override
  void recordMeasurement(int track, double extent) {
    assert(
      acceptsMeasurements,
      "UniformAxis does not accept measurements; acceptsMeasurements is "
      "false",
    );
  }
}

/// One extent per track, supplied by the caller. Holds a COPY of that list
/// plus one prefix array, both built ONCE, eagerly, in the constructor.
class ExplicitAxis implements BoardAxis {
  /// Creates an axis over [extents], one entry per track. Every entry must
  /// be strictly positive.
  ///
  /// The list is COPIED. Holding the caller's reference while the prefix,
  /// the minimum and the track count are constructor snapshots lets a
  /// later mutation of that list make [extentOf] disagree with every other
  /// accessor, and lets a zero extent in past the assert below that
  /// [minTrackExtent] rests on. The copy is a [Float64List], so the read
  /// is a typed one.
  ExplicitAxis(List<double> extents)
    : _extents = Float64List(extents.length),
      _prefix = Float64List(extents.length + 1),
      _minTrackExtent = _emptyAxisMinTrackExtent {
    var running = 0.0;
    var smallest = double.infinity;
    for (var i = 0; i < extents.length; i++) {
      final extent = extents[i];
      assert(
        extent > 0.0,
        "ExplicitAxis extent at track $i must be strictly positive so "
        "minTrackExtent is",
      );
      _extents[i] = extent;
      running += extent;
      _prefix[i + 1] = running;
      if (extent < smallest) {
        smallest = extent;
      }
    }
    _minTrackExtent = _extents.isEmpty ? _emptyAxisMinTrackExtent : smallest;
    assert(
      running <= BoardAxis.maxTotalExtent,
      "ExplicitAxis total $running exceeds BoardAxis.maxTotalExtent",
    );
  }

  final Float64List _extents;
  final Float64List _prefix;
  double _minTrackExtent;

  @override
  int get trackCount {
    return _extents.length;
  }

  @override
  double extentOf(int track) {
    assert(track >= 0 && track < trackCount);
    return _extents[track];
  }

  @override
  double offsetOf(int track) {
    assert(track >= 0 && track <= trackCount);
    return _prefix[track];
  }

  @override
  double offsetOfFraction(double track) {
    return _interpolate(this, track);
  }

  @override
  int trackAt(double offset) {
    return _binarySearchPrefix(_prefix, trackCount, offset);
  }

  @override
  double get totalExtent {
    return _prefix[trackCount];
  }

  @override
  bool get isProvisional {
    return false;
  }

  @override
  double get minTrackExtent {
    return _minTrackExtent;
  }

  @override
  bool get acceptsMeasurements {
    return false;
  }

  @override
  bool isMeasured(int track) {
    return true;
  }

  @override
  void recordMeasurement(int track, double extent) {
    assert(
      acceptsMeasurements,
      "ExplicitAxis does not accept measurements; acceptsMeasurements is "
      "false",
    );
  }
}

/// Extents from a caller callback, invoked exactly [trackCount] times in
/// the constructor and never again.
///
/// [offsetOf] must not sum the callback per call: the callback is caller
/// code on the per-layout path and the track count is unbounded, so a
/// per-call sum would be O(trackCount) of caller code per row per frame.
class DerivedAxis implements BoardAxis {
  /// Creates an axis of [trackCount] tracks whose extents come from
  /// [extentOf], which is invoked exactly [trackCount] times here.
  DerivedAxis(this.trackCount, double Function(int track) extentOf)
    : assert(trackCount >= 0),
      _extents = Float64List(trackCount),
      _prefix = Float64List(trackCount + 1),
      _minTrackExtent = _emptyAxisMinTrackExtent {
    var running = 0.0;
    var smallest = double.infinity;
    for (var i = 0; i < trackCount; i++) {
      final extent = extentOf(i);
      assert(
        extent > 0.0,
        "DerivedAxis extent at track $i must be strictly positive so "
        "minTrackExtent is",
      );
      _extents[i] = extent;
      running += extent;
      _prefix[i + 1] = running;
      if (extent < smallest) {
        smallest = extent;
      }
    }
    _minTrackExtent = trackCount == 0 ? _emptyAxisMinTrackExtent : smallest;
    assert(
      running <= BoardAxis.maxTotalExtent,
      "DerivedAxis total $running exceeds BoardAxis.maxTotalExtent",
    );
  }

  @override
  final int trackCount;

  /// The callback's extents, kept as given, as `ExplicitAxis` keeps its
  /// own. A difference of two prefix sums rounds: it reported values
  /// below the one given, and below [minTrackExtent], which this axis
  /// promises never to report under.
  final Float64List _extents;
  final Float64List _prefix;
  double _minTrackExtent;

  @override
  double extentOf(int track) {
    assert(track >= 0 && track < trackCount);
    return _extents[track];
  }

  @override
  double offsetOf(int track) {
    assert(track >= 0 && track <= trackCount);
    return _prefix[track];
  }

  @override
  double offsetOfFraction(double track) {
    return _interpolate(this, track);
  }

  @override
  int trackAt(double offset) {
    return _binarySearchPrefix(_prefix, trackCount, offset);
  }

  @override
  double get totalExtent {
    return _prefix[trackCount];
  }

  @override
  bool get isProvisional {
    return false;
  }

  @override
  double get minTrackExtent {
    return _minTrackExtent;
  }

  @override
  bool get acceptsMeasurements {
    return false;
  }

  @override
  bool isMeasured(int track) {
    return true;
  }

  @override
  void recordMeasurement(int track, double extent) {
    assert(
      acceptsMeasurements,
      "DerivedAxis does not accept measurements; acceptsMeasurements is "
      "false",
    );
  }
}

/// The content-sized axis: every track starts at [estimate] and is
/// replaced by a measurement as layout supplies one.
///
/// Storage is one [Fenwick] of length [trackCount] holding
/// `extentOf(i) - estimate` at every measured `i`, so [offsetOf] is
/// `track * estimate + prefixSum(track)` and the prefix is built
/// incrementally, one [Fenwick.add] per measurement.
class LazyContentAxis implements BoardAxis {
  /// Creates a content-sized axis. [minTrackExtent] is the floor every
  /// recorded measurement is clamped to, and this is the only
  /// implementation that has to ask the caller for it, because its extents
  /// are not known at construction.
  LazyContentAxis(this.trackCount, this.estimate, {this.minTrackExtent = 1.0})
    : assert(trackCount >= 0),
      assert(estimate > 0.0, "LazyContentAxis estimate must be positive"),
      assert(
        minTrackExtent > 0.0,
        "LazyContentAxis minTrackExtent must be strictly positive",
      ),
      assert(
        estimate >= minTrackExtent,
        "LazyContentAxis estimate must not sit below minTrackExtent, or an "
        "unmeasured track would report less than the floor",
      ),
      assert(
        trackCount * estimate <= BoardAxis.maxTotalExtent,
        "LazyContentAxis estimated total ${trackCount * estimate} "
        "exceeds BoardAxis.maxTotalExtent",
      ),
      _deltas = Fenwick(trackCount),
      _measured = Uint8List(trackCount);

  @override
  final int trackCount;

  /// The extent an unmeasured track reports, in content space.
  final double estimate;

  @override
  final double minTrackExtent;

  /// `extentOf(i) - estimate` at every measured `i`, zero elsewhere.
  final Fenwick _deltas;

  /// One byte per track: 1 once [recordMeasurement] has run for it.
  final Uint8List _measured;

  int _measuredCount = 0;

  /// Debug-only: the backing tree, for the operation-count budget in the
  /// oracle fuzz. Both this class and [Fenwick] are unexported, so this
  /// adds nothing to the public surface.
  Fenwick get debugFenwick {
    return _deltas;
  }

  @override
  double extentOf(int track) {
    assert(track >= 0 && track < trackCount);
    // Floored at the READ and not only at the write. The extent is
    // recovered from the DIFFERENCE of two prefix sums, which are large
    // numbers whose difference drops low bits, and [recordMeasurement]
    // feeds that recovered value straight back in as `floored - current`,
    // so the stored delta random-walks: a 64-track axis re-measured 200
    // times around 1e12 reported 0.98828125 against a floor of 1.0. This
    // is what keeps [BoardAxis.minTrackExtent], "the smallest extent this
    // axis can ever report", an absolute rather than an approximation.
    final stored =
        estimate + _deltas.prefixSum(track + 1) - _deltas.prefixSum(track);
    return stored < minTrackExtent ? minTrackExtent : stored;
  }

  @override
  double offsetOf(int track) {
    assert(track >= 0 && track <= trackCount);
    return track * estimate + _deltas.prefixSum(track);
  }

  @override
  double offsetOfFraction(double track) {
    return _interpolate(this, track);
  }

  @override
  int trackAt(double offset) {
    if (trackCount == 0) {
      return 0;
    }
    // The descent accumulates one `power * estimate` term per level,
    // which is a different association than [offsetOf]'s
    // `track * estimate + prefixSum(track)`, so its answer is one low at
    // some exact leading edges. Corrected against offsetOf itself.
    final raw = _deltas.lowerBound(offset, perIndexBias: estimate);
    return _correctToOffsetOf(this, raw, offset);
  }

  @override
  double get totalExtent {
    return trackCount * estimate + _deltas.prefixSum(trackCount);
  }

  @override
  bool get isProvisional {
    return _measuredCount < trackCount;
  }

  @override
  bool get acceptsMeasurements {
    return true;
  }

  @override
  bool isMeasured(int track) {
    assert(track >= 0 && track < trackCount);
    return _measured[track] != 0;
  }

  /// Debug-only: how many measurements have been RECORDED, as opposed to
  /// offered and skipped. A re-record of an identical value is
  /// unobservable through any public read (the extent does not change by
  /// definition), so a consumer whose convergence test re-offers every
  /// frame can only be caught by counting; same justification as
  /// [debugFenwick].
  int debugRecordCount = 0;

  @override
  void recordMeasurement(int track, double extent) {
    debugRecordCount++;
    assert(acceptsMeasurements);
    assert(track >= 0 && track < trackCount);
    assert(extent.isFinite, "a measured extent must be finite");
    // A zero measurement is reachable from LEGAL input, not from caller
    // error: a content-sized track with no cell content, no items and a
    // lane padding of 0 resolves to 0. So this FLOORS instead of
    // asserting, which is what keeps the correction loop's termination
    // true by construction at the cost of one comparison per measurement.
    final floored = extent < minTrackExtent ? minTrackExtent : extent;
    final current = extentOf(track);
    _deltas.add(track, floored - current);
    if (_measured[track] == 0) {
      _measured[track] = 1;
      _measuredCount++;
    }
  }

  /// Drops every measurement, returning the axis to its all-estimate
  /// state.
  void resetMeasurements() {
    _deltas.clear();
    _measured.fillRange(0, _measured.length, 0);
    _measuredCount = 0;
  }
}

/// Shared body of [BoardAxis.offsetOfFraction]: linear interpolation
/// inside the containing track, short-circuiting at an integral argument
/// so the trackCount endpoint is callable.
double _interpolate(BoardAxis axis, double track) {
  assert(track >= 0.0 && track <= axis.trackCount);
  final floor = track.floorToDouble();
  if (floor == track) {
    return axis.offsetOf(track.toInt());
  }
  final containing = floor.toInt();
  return axis.offsetOf(containing) +
      (track - floor) * axis.extentOf(containing);
}

/// Corrects [raw], the result of an approximate track search, into the
/// track whose HALF-OPEN interval actually contains [offset] according to
/// the axis's own [BoardAxis.offsetOf].
///
/// [UniformAxis.trackAt] and [LazyContentAxis.trackAt] each answer from a
/// different floating-point expression than the [BoardAxis.offsetOf] they
/// have to invert, and the two disagree by an ulp at a leading edge: a
/// measured `UniformAxis(2000, 23.4)` resolved 1040 of its 2000 leading
/// edges to `track - 1`, and `UniformAxis(7, 360 / 7)`, the weekday axis
/// of a month calendar on a 360 pixel phone, resolved columns 3 and 6 one
/// low. Stepping against offsetOf makes trackAt invert the SAME
/// expression offsetOf evaluates, which is the round-trip constraint.
///
/// Both loops step at most a track or two, because the raw answer is off
/// by at most one boundary; the clamp before them is the one trackAt
/// already owed its callers. [ExplicitAxis] and [DerivedAxis] need no
/// correction: their search reads the same stored prefix their offsetOf
/// returns.
int _correctToOffsetOf(BoardAxis axis, int raw, double offset) {
  assert(axis.trackCount > 0);
  var track = raw.clamp(0, axis.trackCount - 1);
  while (track + 1 < axis.trackCount && axis.offsetOf(track + 1) <= offset) {
    track++;
  }
  while (track > 0 && axis.offsetOf(track) > offset) {
    track--;
  }
  return track;
}

/// Largest track whose leading offset does not exceed [offset], found by
/// binary search over an eagerly built prefix array.
int _binarySearchPrefix(Float64List prefix, int trackCount, double offset) {
  if (trackCount == 0) {
    return 0;
  }
  var low = 0;
  var high = trackCount;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (prefix[mid + 1] <= offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low.clamp(0, trackCount - 1);
}

/// Per-axis board configuration: the axis itself plus the frozen bands,
/// the cell alignment and the lane geometry that axis carries.
@immutable
class BoardAxisConfig {
  /// Creates a config. A non-null [laneExtent] makes this axis the LANE
  /// axis, and at most one of the two configs on a board may carry one.
  const BoardAxisConfig({
    required this.axis,
    this.frozenStart = 0,
    this.frozenEnd = 0,
    this.alignment = TrackAlignment.stretch,
    this.laneExtent,
    this.lanePadding = 0.0,
  }) : assert(frozenStart >= 0),
       assert(frozenEnd >= 0),
       assert(laneExtent == null || laneExtent > 0.0),
       assert(lanePadding >= 0.0);

  /// The extent model for this axis.
  final BoardAxis axis;

  /// Number of leading tracks pinned to the viewport's leading edge.
  ///
  /// The band's cells stay put while the lattice scrolls, and so does an
  /// ITEM whose span lies wholly inside the band on this axis (a laned
  /// item on the lane axis by its one track): a header row can carry
  /// items. A drag that moves an item along this axis (see
  /// `BoardDragConfig.snap` for when it does) lands it in the band when
  /// the drag proxy's centre is over the band and the item's span fits in
  /// it, unless landing there would move the item against the drag; on
  /// the lane axis a laned item lands in the band when the pointer is
  /// over it. A selection over the band selects the band's cells. An item
  /// that crosses the band's edge scrolls, and the band covers what
  /// scrolls beneath it.
  final int frozenStart;

  /// Number of trailing tracks pinned to the viewport's trailing edge,
  /// with the same rules for items as [frozenStart].
  final int frozenEnd;

  /// What a cell does with surplus track extent on this axis.
  final TrackAlignment alignment;

  /// Extent of ONE lane, in content space along this axis. Non-null makes
  /// this the lane axis.
  final double? laneExtent;

  /// Reserve at the track's LEADING edge, before lane 0, in content space
  /// along this axis. This is the space a month calendar day number
  /// occupies above its chips.
  final double lanePadding;
}

/// The frozen bands of a [BoardAxisConfig] as track bounds and extents:
/// the one site that clamps [BoardAxisConfig.frozenStart] and
/// [BoardAxisConfig.frozenEnd] against the axis. Internal, and not shown
/// by the barrel.
///
/// Where the two counts overlap on a short axis, the shared tracks belong
/// to the leading band, so the bands never overlap. Every read derives
/// from the axis as it is at the call, so a measurement recorded between
/// two reads shows in the second. The extents are SETTLED: no track
/// resize in flight is applied.
extension BoardAxisConfigBands on BoardAxisConfig {
  /// The exclusive end of the leading band: [frozenStart] clamped into
  /// `[0, trackCount]`, so 0 with no leading band.
  int get leadingBandEnd {
    return _leadingBandEndOf(axis.trackCount);
  }

  /// The first track of the trailing band, `trackCount` with no trailing
  /// band. Never below [leadingBandEnd].
  int get trailingBandStart {
    final count = axis.trackCount;
    return _trailingBandStartOf(count, _leadingBandEndOf(count));
  }

  /// Whether [track] lies in either band. Defined for
  /// `0 <= track < trackCount`.
  bool isFrozenTrack(int track) {
    final count = axis.trackCount;
    final lead = _leadingBandEndOf(count);
    return track < lead || track >= _trailingBandStartOf(count, lead);
  }

  /// The settled extent of the leading band, 0.0 with none.
  double get leadingBandExtent {
    final lead = leadingBandEnd;
    if (lead <= 0) {
      return 0.0;
    }
    return axis.offsetOfFraction(lead.toDouble());
  }

  /// The settled extent of the trailing band, 0.0 with none.
  double get trailingBandExtent {
    final start = trailingBandStart;
    // Not an equality: the non-negative checks on the counts are asserts,
    // so in a release build a negative `frozenEnd` puts the start past the
    // axis, where `offsetOfFraction` would read out of range.
    if (start >= axis.trackCount) {
      return 0.0;
    }
    return axis.totalExtent - axis.offsetOfFraction(start.toDouble());
  }

  /// The frozen tracks: the leading band ascending, then the trailing band
  /// ascending.
  Iterable<int> get frozenTracks sync* {
    final count = axis.trackCount;
    final lead = _leadingBandEndOf(count);
    for (var track = 0; track < lead; track++) {
      yield track;
    }
    for (
      var track = _trailingBandStartOf(count, lead);
      track < count;
      track++
    ) {
      yield track;
    }
  }

  int _leadingBandEndOf(int count) {
    final start = frozenStart;
    if (start <= 0) {
      return 0;
    }
    return start < count ? start : count;
  }

  int _trailingBandStartOf(int count, int lead) {
    final start = count - frozenEnd;
    return start > lead ? start : lead;
  }
}
