/// A property sweep of the drop fit's SEARCH REGION,
/// [BoardDropFitter.searchRangeOn], against the real window functions,
/// the real step count and the real candidate scan.
///
/// A UNIT file: the region, the windows and the scan are pure functions,
/// so a grid of inputs covers far more cases than pumped boards could, at
/// a fraction of the cost.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_drop_fit.dart';
import 'package:widgets_extended/board/_board_drop_resolver.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_config.dart';

typedef _Range = ({int start, int end});

/// A window, what produced it, and the band bounds of that axis
/// configuration: [band] for a band's window, else the leading band's
/// end and the trailing band's start.
typedef _Window = ({
  BoardStartWindow window,
  String kind,
  ({int start, int end})? band,
  int lead,
  int trail,
});

/// The WIDENED BOX on one axis, the region with no window read: the box
/// widened by the radius on both sides, snapped out to whole tracks and
/// clamped to the lattice.
_Range _widened(double start, double end, double radius, int count) {
  final rangeStart = (start - radius).floor().clamp(0, count);
  final rangeEnd = (end + radius).ceil().clamp(0, count);
  return (start: rangeStart, end: rangeEnd);
}

/// One axis of a refused box, its policy radius and the window the
/// resolver placed it in.
class _AxisCase {
  _AxisCase({
    required this.count,
    required this.start,
    required this.extent,
    required this.radius,
    required this.wholeTrack,
    required this.window,
    required this.windowKind,
    this.reachable = true,
  });

  final int count;
  final double start;
  final double extent;
  final double radius;
  final bool wholeTrack;
  final BoardStartWindow window;
  final String windowKind;

  /// Whether a drag can present this box with this window: a box pinned
  /// in a band carries that band's window, and any other box, kept or
  /// moved, a scrolled or whole-lattice window.
  final bool reachable;

  int get windowRank {
    if (windowKind.startsWith("lattice")) {
      return 0;
    }
    if (windowKind.startsWith("band")) {
      return 1;
    }
    return 2;
  }

  String describe() {
    return "count $count, start $start, extent $extent, radius $radius, "
        "wholeTrack $wholeTrack, window [${window.min}, ${window.max}] "
        "($windowKind)${reachable ? "" : ", unreachable"}";
  }
}

/// The rule under test, called exactly as the drag controller calls it.
_Range _region(_AxisCase a, BoardSpan box, Axis axis, {required bool stepped}) {
  return BoardDropFitter.searchRangeOn(
    start: box.startTrackOn(axis),
    end: box.endTrackOn(axis),
    radius: a.radius,
    window: a.window,
    stepped: stepped,
    trackCount: a.count,
  );
}

BoardSpan _boxOf(_AxisCase row, _AxisCase col) {
  return BoardSpan(
    rowStart: row.start.floor(),
    rowFraction: row.start - row.start.floorToDouble(),
    rowSpan: row.extent.floor(),
    rowSpanFraction: row.extent - row.extent.floorToDouble(),
    colStart: col.start.floor(),
    colFraction: col.start - col.start.floorToDouble(),
    colSpan: col.extent.floor(),
    colSpanFraction: col.extent - col.extent.floorToDouble(),
  );
}

/// Failures of one property, with the first one met and the smallest by
/// track count, window kind, radius, extent and start.
class _Tally {
  _Tally(this.name);

  final String name;
  int checked = 0;
  int failed = 0;
  String? first;
  List<num>? _minimalKey;
  String? minimal;
  int reachableChecked = 0;
  int reachableFailed = 0;
  String? firstReachable;

  void count({required bool reachable}) {
    checked++;
    if (reachable) {
      reachableChecked++;
    }
  }

  void fail(
    List<num> key,
    String Function() describe, {
    required bool reachable,
  }) {
    failed++;
    if (reachable) {
      reachableFailed++;
      firstReachable ??= describe();
    }
    first ??= describe();
    final current = _minimalKey;
    if (current == null || _less(key, current)) {
      _minimalKey = key;
      minimal = describe();
    }
  }

  static bool _less(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return a[i] < b[i];
      }
    }
    return false;
  }

  String report() {
    return "$name: $checked checked ($reachableChecked reachable), "
        "$failed failed ($reachableFailed reachable)"
        "${failed == 0 ? "" : "\n  first: $first\n  minimal: $minimal"}"
        "${firstReachable == null ? "" : "\n  first reachable: $firstReachable"}";
  }
}

List<num> _keyOf(_AxisCase a) {
  return <num>[a.count, a.windowRank, a.radius, a.extent, a.start];
}

const List<double> _radii = <double>[
  0.0,
  0.25,
  0.3,
  0.5,
  0.6,
  0.7,
  1.0,
  1.1,
  1.25,
  2.0,
  4.5,
  9.0,
];
const List<double> _extents = <double>[0.25, 0.5, 1.0, 1.2, 2.0, 2.5];
const List<double> _laneExtents = <double>[0.25, 0.5, 1.0];
const List<int> _counts = <int>[6, 30];
const List<BoardSnap> _snaps = <BoardSnap>[
  BoardSnap.track(),
  BoardSnap.fraction(0.25),
  BoardSnap.fraction(0.35),
  BoardSnap.fraction(0.5),
  BoardSnap.fraction(2.0),
  BoardSnap.free(),
];

String _snapName(BoardSnap snap) {
  switch (snap.mode) {
    case BoardSnapMode.track:
      return "track";
    case BoardSnapMode.fraction:
      return "fraction(${snap.fraction})";
    case BoardSnapMode.free:
      return "free";
  }
}

/// Starts that keep a box of [extent] inside [count] tracks: a twentieth
/// grid, the snap's own grid as the snap produces it, and an offset grid
/// that lies on no grid at all, with the last start that fits.
List<double> _startsOf(int count, double extent, double quantum, int every) {
  final limit = count - extent;
  final starts = <double>{limit};
  for (var i = 0; i / 20.0 <= limit; i += every) {
    starts.add(i / 20.0);
    final offset = i / 20.0 + 0.0137;
    if (offset <= limit) {
      starts.add(offset);
    }
  }
  for (var k = 0; snapToTrackEdge(k * quantum) <= limit; k++) {
    starts.add(snapToTrackEdge(k * quantum));
  }
  return starts.toList()..sort();
}

BoardAxisSample _sample({
  required int count,
  required int leadingBandEnd,
  required int trailingBandStart,
  required double? visibleFrom,
  required double? visibleTo,
}) {
  return (
    painted: 0.0,
    paintedExtended: 0.0,
    scrolled: 0.0,
    scrollPixels: 0.0,
    band: null,
    visibleFrom: visibleFrom,
    visibleTo: visibleTo,
    trackCount: count,
    leadingBandEnd: leadingBandEnd,
    trailingBandStart: trailingBandStart,
  );
}

/// The bound values a synthesized sample takes: a grid across the
/// lattice, and a fine one around one interior track for thin regions.
List<double> _boundsOf(int count) {
  final values = <double>{};
  final step = count <= 6 ? 0.05 : 0.25;
  for (var i = 0; i * step <= count + 1e-9; i++) {
    values.add(i * step);
  }
  final thinAt = count <= 6 ? 3.0 : 21.0;
  for (var i = -20; i <= 20; i++) {
    final v = thinAt + i * 0.05;
    if (v >= 0.0 && v <= count) {
      values.add(v);
    }
  }
  values
    ..add(thinAt + 0.5)
    ..add(thinAt + 0.7);
  return values.toList()..sort();
}

/// Every distinct window a move axis can be placed in on [count] tracks,
/// for a span of [extent] on a grid of [quantum]: the lattice's, each band
/// of one to three tracks at either end that fits the span, and the
/// scrolled windows of synthesized samples with a leading bound alone, a
/// trailing bound alone, and both, the empty region included, where a
/// null scrolled window is the lattice's, as the path functions read it.
Map<String, _Window> _windowsOf(int count, double extent, double quantum) {
  final windows = <String, _Window>{};
  void add(
    BoardStartWindow window,
    String kind, {
    ({int start, int end})? band,
    int lead = 0,
    int? trail,
  }) {
    windows.putIfAbsent("${window.min}:${window.max}", () {
      return (
        window: window,
        kind: kind,
        band: band,
        lead: lead,
        trail: trail ?? count,
      );
    });
  }

  add(latticeWindowOf(count, extent), "lattice");
  for (var k = 1; k <= 3; k++) {
    final leading = bandWindowOf((start: 0, end: k), extent);
    if (leading != null) {
      add(leading, "band leading $k", band: (start: 0, end: k));
    }
    final trailing = bandWindowOf((start: count - k, end: count), extent);
    if (trailing != null) {
      add(trailing, "band trailing $k", band: (start: count - k, end: count));
    }
  }
  void addScrolled(BoardAxisSample sample) {
    final window = scrolledWindowOf(sample, extent, quantum);
    final kind =
        "scrolled from ${sample.visibleFrom} to ${sample.visibleTo}, "
        "bands ${sample.leadingBandEnd}/${sample.trailingBandStart}";
    if (window == null) {
      add(
        latticeWindowOf(count, extent),
        "lattice, no scrolled start: $kind",
        lead: sample.leadingBandEnd,
        trail: sample.trailingBandStart,
      );
    } else {
      add(
        window,
        kind,
        lead: sample.leadingBandEnd,
        trail: sample.trailingBandStart,
      );
    }
  }

  final bounds = _boundsOf(count);
  for (var k = 1; k <= 3; k++) {
    for (final from in bounds) {
      if (from >= k && from <= count) {
        addScrolled(
          _sample(
            count: count,
            leadingBandEnd: k,
            trailingBandStart: count,
            visibleFrom: from,
            visibleTo: null,
          ),
        );
      }
    }
    for (final to in bounds) {
      if (to >= 0 && to <= count - k) {
        addScrolled(
          _sample(
            count: count,
            leadingBandEnd: 0,
            trailingBandStart: count - k,
            visibleFrom: null,
            visibleTo: to,
          ),
        );
      }
    }
  }
  const pairs = <(int, int)>[(1, 1), (2, 1), (1, 3), (3, 3)];
  for (final (lead, trail) in pairs) {
    final lo = lead;
    final hi = count - trail;
    if (lo > hi) {
      continue;
    }
    for (final from in bounds) {
      if (from < lo || from > hi) {
        continue;
      }
      for (final to in bounds) {
        if (to < from || to > hi) {
          continue;
        }
        addScrolled(
          _sample(
            count: count,
            leadingBandEnd: lead,
            trailingBandStart: hi,
            visibleFrom: from,
            visibleTo: to,
          ),
        );
      }
    }
  }
  return windows;
}

final Map<String, List<_Window>> _cache = <String, List<_Window>>{};

/// The windows one axis case is checked against: every distinct window
/// when [limit] is null, else the lattice's, the bands', the twenty
/// narrowest scrolled windows and an even selection of the rest, about
/// [limit] in all.
List<_Window> _chosenWindows(
  int count,
  double extent,
  double quantum,
  int? limit,
) {
  final all = _cache.putIfAbsent("$count:$extent:$quantum", () {
    return _windowsOf(count, extent, quantum).values.toList();
  });
  if (limit == null || all.length <= limit) {
    return all;
  }
  final fixed = all.where((w) {
    return !w.kind.startsWith("scrolled");
  }).toList();
  final scrolled = all.where((w) {
    return w.kind.startsWith("scrolled");
  }).toList();
  final narrow = scrolled.toList()
    ..sort((a, b) {
      return (a.window.max - a.window.min).compareTo(
        b.window.max - b.window.min,
      );
    });
  final chosen = <_Window>[...fixed, ...narrow.take(20)];
  final stride = scrolled.length ~/ (limit - chosen.length) + 1;
  for (var i = 0; i < scrolled.length; i += stride) {
    chosen.add(scrolled[i]);
  }
  return chosen;
}

/// Whether a drag can present a box at [start] of [extent] with [w]: a
/// laned box lies inside one track, and is pinned by that whole track;
/// a box pinned in a band carries that band's window; any other box a
/// scrolled or whole-lattice window.
bool _reachable(
  double start,
  double extent,
  _Window w,
  int count, {
  required bool wholeTrack,
}) {
  var low = start;
  var high = start + extent;
  if (wholeTrack) {
    final track = trackIndexOf(start);
    if (high > track + 1 + precisionErrorTolerance) {
      return false;
    }
    low = track.toDouble();
    high = track + 1.0;
  }
  bool within(int lo, int hi) {
    return low >= lo - precisionErrorTolerance &&
        high <= hi + precisionErrorTolerance;
  }

  final band = w.band;
  if (band != null) {
    return within(band.start, band.end);
  }
  if (w.lead > 0 && within(0, w.lead)) {
    return false;
  }
  if (w.trail < count && within(w.trail, count)) {
    return false;
  }
  return true;
}

/// Every axis case for one track count, snap and whole-track choice, the
/// window's extent and grid being the ones the resolver places that axis
/// with: a whole track on the whole-track axis, the span's own extent and
/// the snap's grid elsewhere.
void _forEachAxisCase({
  required int count,
  required BoardSnap snap,
  required bool wholeTrack,
  required int? windowLimit,
  required int every,
  required void Function(_AxisCase a) visit,
}) {
  final quantum = wholeTrack ? 1.0 : BoardDropResolver.quantumOf(snap);
  for (final extent in wholeTrack ? _laneExtents : _extents) {
    final windowExtent = wholeTrack ? 1.0 : extent;
    final windows = _chosenWindows(count, windowExtent, quantum, windowLimit);
    final starts = _startsOf(count, extent, quantum, every);
    for (final radius in _radii) {
      for (final w in windows) {
        for (final start in starts) {
          visit(
            _AxisCase(
              count: count,
              start: start,
              extent: extent,
              radius: radius,
              wholeTrack: wholeTrack,
              window: w.window,
              windowKind: w.kind,
              reachable: _reachable(
                start,
                extent,
                w,
                count,
                wholeTrack: wholeTrack,
              ),
            ),
          );
        }
      }
    }
  }
}

_AxisCase _still(int count) {
  return _AxisCase(
    count: count,
    start: 0.0,
    extent: 1.0,
    radius: 0.0,
    wholeTrack: false,
    window: latticeWindowOf(count, 1.0),
    windowKind: "lattice",
  );
}

int _stepsOn(Axis axis, BoardSnap snap, Axis? wholeTrackAxis, double radius) {
  final steps = BoardDropFitter.stepsOf(
    policy: BoardDropFit(
      minFreeFraction: 0.0,
      rowRadius: axis == Axis.vertical ? radius : 0.0,
      colRadius: axis == Axis.horizontal ? radius : 0.0,
    ),
    snap: snap,
    wholeTrackAxis: wholeTrackAxis,
  );
  return axis == Axis.vertical ? steps.rows : steps.cols;
}

/// The pure properties on one axis: the region is the widened box on the
/// lattice's window (P1), holds the box's own tracks (P3), and is the
/// widened box on an axis the scan does not step whatever the window
/// (P4).
void _checkPure(
  _AxisCase a,
  Axis axis,
  BoardSnap snap,
  Axis? wholeTrackAxis,
  _Tally p1,
  _Tally p3,
  _Tally p4,
) {
  final still = _still(a.count);
  final box = axis == Axis.vertical ? _boxOf(a, still) : _boxOf(still, a);
  final start = box.startTrackOn(axis);
  final end = box.endTrackOn(axis);
  final steps = _stepsOn(axis, snap, wholeTrackAxis, a.radius);
  final region = _region(a, box, axis, stepped: steps > 0);
  final widened = _widened(start, end, a.radius, a.count);
  String describe() {
    return "${a.describe()}, snap ${_snapName(snap)}, steps $steps: "
        "region [${region.start}, ${region.end}), "
        "widened [${widened.start}, ${widened.end})";
  }

  if (a.windowKind.startsWith("lattice")) {
    p1.count(reachable: a.reachable);
    if (region != widened) {
      p1.fail(_keyOf(a), describe, reachable: a.reachable);
    }
  }
  p3.count(reachable: a.reachable);
  if (region.start > trackIndexOf(start) ||
      region.end < trackEndIndexOf(end).clamp(0, a.count)) {
    p3.fail(_keyOf(a), describe, reachable: a.reachable);
  }
  if (steps == 0) {
    p4.count(reachable: a.reachable);
    if (region != widened) {
      p4.fail(_keyOf(a), describe, reachable: a.reachable);
    }
  }
}

/// Every candidate the real scan proposes for the box of [row] and
/// [col]: no obstacle, and an [accepts] that records each and refuses
/// it, so the scan visits all of them.
List<BoardSpan> _candidatesOf(
  _AxisCase row,
  _AxisCase col,
  BoardSnap snap,
  Axis? wholeTrackAxis,
) {
  final candidates = <BoardSpan>[];
  BoardDropFitter.nearestFit(
    box: _boxOf(row, col),
    policy: BoardDropFit(
      minFreeFraction: 0.0,
      rowRadius: row.radius,
      colRadius: col.radius,
    ),
    snap: snap,
    rowAxis: UniformAxis(row.count, 10.0),
    colAxis: UniformAxis(col.count, 10.0),
    obstacles: const <BoardSpan>[],
    accepts: (candidate) {
      candidates.add(candidate);
      return false;
    },
    rowWindow: row.window,
    colWindow: col.window,
    wholeTrackAxis: wholeTrackAxis,
  );
  return candidates;
}

/// The first of [candidates] outside the region `rows` by `cols`, or
/// null; by the start rule's tolerance unless [strict], the tolerance
/// reading an end within it of a track edge as not reaching past it.
BoardSpan? _outside(
  List<BoardSpan> candidates,
  _Range rows,
  _Range cols, {
  required bool strict,
}) {
  for (final c in candidates) {
    final rs = c.startTrackOn(Axis.vertical);
    final re = c.endTrackOn(Axis.vertical);
    final cs = c.startTrackOn(Axis.horizontal);
    final ce = c.endTrackOn(Axis.horizontal);
    final out = strict
        ? rs < rows.start || re > rows.end || cs < cols.start || ce > cols.end
        : trackIndexOf(rs) < rows.start ||
              trackEndIndexOf(re) > rows.end ||
              trackIndexOf(cs) < cols.start ||
              trackEndIndexOf(ce) > cols.end;
    if (out) {
      return c;
    }
  }
  return null;
}

/// COVERAGE (P2): every candidate the real scan proposes for [row] and
/// [col] lies inside the region on both axes, strictly and by the start
/// rule.
void _checkCoverage(
  _AxisCase row,
  _AxisCase col,
  BoardSnap snap,
  Axis? wholeTrackAxis,
  _Tally strict,
  _Tally tolerant,
) {
  final box = _boxOf(row, col);
  final steps = BoardDropFitter.stepsOf(
    policy: BoardDropFit(
      minFreeFraction: 0.0,
      rowRadius: row.radius,
      colRadius: col.radius,
    ),
    snap: snap,
    wholeTrackAxis: wholeTrackAxis,
  );
  if (steps.rows == 0 && steps.cols == 0) {
    return;
  }
  final rows = _region(row, box, Axis.vertical, stepped: steps.rows > 0);
  final cols = _region(col, box, Axis.horizontal, stepped: steps.cols > 0);
  final candidates = _candidatesOf(row, col, snap, wholeTrackAxis);
  final reachable = row.reachable && col.reachable;
  strict.count(reachable: reachable);
  tolerant.count(reachable: reachable);
  final strictOut = _outside(candidates, rows, cols, strict: true);
  final tolerantOut = _outside(candidates, rows, cols, strict: false);
  String describe(BoardSpan? out) {
    return "row {${row.describe()}}, col {${col.describe()}}, "
        "snap ${_snapName(snap)}, wholeTrackAxis $wholeTrackAxis, "
        "steps $steps: rows [${rows.start}, ${rows.end}), "
        "cols [${cols.start}, ${cols.end}), candidate outside: $out "
        "(${candidates.length} candidates)";
  }

  final key = steps.rows > 0
      ? <num>[..._keyOf(row), ..._keyOf(col)]
      : <num>[..._keyOf(col), ..._keyOf(row)];
  if (strictOut != null) {
    strict.fail(key, () {
      return describe(strictOut);
    }, reachable: reachable);
  }
  if (tolerantOut != null) {
    tolerant.fail(key, () {
      return describe(tolerantOut);
    }, reachable: reachable);
  }
}

void main() {
  final totals = <String, _Tally>{};
  for (final snap in _snaps) {
    test("the search region's properties under ${_snapName(snap)}", () {
      final p1 = _Tally("P1 lattice window equals the widened box");
      final p2 = _Tally("P2 coverage, one axis stepped, start rule");
      final p2strict = _Tally("P2 coverage, one axis stepped, strict");
      final pairs = _Tally("P2 coverage, two-axis pairs, start rule");
      final pairsStrict = _Tally("P2 coverage, two-axis pairs, strict");
      final p3 = _Tally("P3 the box's own tracks");
      final p4 = _Tally("P4 unstepped axis equals the widened box");
      for (final count in _counts) {
        final still = _still(count);
        for (final wholeTrackAxis in <Axis?>[
          null,
          Axis.vertical,
          Axis.horizontal,
        ]) {
          for (final axis in <Axis>[Axis.vertical, Axis.horizontal]) {
            final wholeTrack = axis == wholeTrackAxis;
            _forEachAxisCase(
              count: count,
              snap: snap,
              wholeTrack: wholeTrack,
              windowLimit: count <= 6 ? null : 200,
              every: count <= 6 ? 1 : 4,
              visit: (a) {
                _checkPure(a, axis, snap, wholeTrackAxis, p1, p3, p4);
              },
            );
            _forEachAxisCase(
              count: count,
              snap: snap,
              wholeTrack: wholeTrack,
              windowLimit: 60,
              every: count <= 6 ? 2 : 4,
              visit: (a) {
                if (axis == Axis.vertical) {
                  _checkCoverage(a, still, snap, wholeTrackAxis, p2strict, p2);
                } else {
                  _checkCoverage(still, a, snap, wholeTrackAxis, p2strict, p2);
                }
              },
            );
          }
          final rowCases = <_AxisCase>[];
          final colCases = <_AxisCase>[];
          _forEachAxisCase(
            count: count,
            snap: snap,
            wholeTrack: wholeTrackAxis == Axis.vertical,
            windowLimit: 60,
            every: 8,
            visit: (a) {
              if (a.radius > 0.0) {
                rowCases.add(a);
              }
            },
          );
          _forEachAxisCase(
            count: count,
            snap: snap,
            wholeTrack: wholeTrackAxis == Axis.horizontal,
            windowLimit: 60,
            every: 8,
            visit: (a) {
              if (a.radius > 0.0) {
                colCases.add(a);
              }
            },
          );
          for (var i = 0; i < 60000; i++) {
            final row = rowCases[(i * 7919) % rowCases.length];
            final col = colCases[(i * 104729 + 13) % colCases.length];
            _checkCoverage(row, col, snap, wholeTrackAxis, pairsStrict, pairs);
          }
        }
      }
      final tallies = <_Tally>[p1, p2, p2strict, pairs, pairsStrict, p3, p4];
      for (final t in tallies) {
        debugPrint("${_snapName(snap)}: ${t.report()}");
        final total = totals.putIfAbsent(t.name, () {
          return _Tally(t.name);
        });
        total.checked += t.checked;
        total.reachableChecked += t.reachableChecked;
        total.failed += t.failed;
        total.reachableFailed += t.reachableFailed;
      }
      expect(p1.failed, 0, reason: p1.report());
      expect(p2.failed, 0, reason: p2.report());
      expect(pairs.failed, 0, reason: pairs.report());
      expect(p3.failed, 0, reason: p3.report());
      expect(p4.failed, 0, reason: p4.report());
    });
  }

  test(
    "a box running past the lattice's end: the region covers every "
    "candidate, and differs from the widened box only where that misses one",
    () {
      final covered = _Tally("P2 past the lattice's end, start rule");
      final differs = _Tally(
        "P1 past the lattice's end, region != widened box",
      );
      final widenedMisses = _Tally("the widened box misses a candidate");
      var differsWhereWidenedCovers = 0;
      String? differsWhereWidenedCoversExample;
      for (final snap in _snaps) {
        for (final count in _counts) {
          final still = _still(count);
          for (final extent in _extents) {
            final window = latticeWindowOf(count, extent);
            for (var i = 1; count - extent + i / 20.0 < count; i++) {
              final start = count - extent + i / 20.0;
              for (final radius in _radii) {
                final a = _AxisCase(
                  count: count,
                  start: start,
                  extent: extent,
                  radius: radius,
                  wholeTrack: false,
                  window: window,
                  windowKind: "lattice, box past the end",
                );
                final steps = _stepsOn(Axis.vertical, snap, null, radius);
                if (steps == 0) {
                  continue;
                }
                final box = _boxOf(a, still);
                final rows = _region(a, box, Axis.vertical, stepped: true);
                final cols = _region(
                  still,
                  box,
                  Axis.horizontal,
                  stepped: false,
                );
                final widened = _widened(
                  box.startTrackOn(Axis.vertical),
                  box.endTrackOn(Axis.vertical),
                  radius,
                  count,
                );
                final candidates = _candidatesOf(a, still, snap, null);
                String describe() {
                  return "${a.describe()}, snap ${_snapName(snap)}, "
                      "steps $steps: region [${rows.start}, ${rows.end}), "
                      "widened [${widened.start}, ${widened.end}), candidates "
                      "$candidates";
                }

                covered.count(reachable: true);
                if (_outside(candidates, rows, cols, strict: false) != null) {
                  covered.fail(_keyOf(a), describe, reachable: true);
                }
                widenedMisses.count(reachable: true);
                final missed =
                    _outside(candidates, widened, cols, strict: false) != null;
                if (missed) {
                  widenedMisses.fail(_keyOf(a), describe, reachable: true);
                }
                differs.count(reachable: true);
                if (rows != widened) {
                  differs.fail(_keyOf(a), describe, reachable: true);
                  if (!missed) {
                    differsWhereWidenedCovers++;
                    differsWhereWidenedCoversExample ??= describe();
                  }
                }
              }
            }
          }
        }
      }
      for (final t in <_Tally>[covered, differs, widenedMisses]) {
        debugPrint(t.report());
      }
      debugPrint(
        "region != widened box where that covers every candidate: "
        "$differsWhereWidenedCovers"
        "${differsWhereWidenedCoversExample == null ? "" : "\n  $differsWhereWidenedCoversExample"}",
      );
      expect(covered.failed, 0, reason: covered.report());
      expect(
        differsWhereWidenedCovers,
        0,
        reason: differsWhereWidenedCoversExample,
      );
    },
  );

  test("random spans, radii and windows", () {
    final random = math.Random(20260930);
    final p1 = _Tally("P1 random, lattice window equals the widened box");
    final p2 = _Tally("P2 random, start rule");
    final p2strict = _Tally("P2 random, strict");
    final p3 = _Tally("P3 random");
    final p4 = _Tally("P4 random");
    const wholeTrackAxes = <Axis?>[null, Axis.vertical, Axis.horizontal];
    for (var i = 0; i < 400000; i++) {
      final snap = _snaps[random.nextInt(_snaps.length)];
      final count = random.nextBool() ? 6 : 30;
      final wholeTrackAxis = wholeTrackAxes[random.nextInt(3)];
      final axis = random.nextBool() ? Axis.vertical : Axis.horizontal;
      final wholeTrack = axis == wholeTrackAxis;
      final extent = wholeTrack
          ? 1.0 - random.nextInt(20) / 20.0
          : random.nextInt(60) / 20.0 + 0.05 + random.nextDouble() / 20.0;
      final start = random.nextInt(4) == 0
          ? (random.nextInt(((count - extent) * 20).floor() + 1) / 20.0)
          : random.nextDouble() * (count - extent);
      final radius = random.nextInt(3) == 0
          ? _radii[random.nextInt(_radii.length)]
          : random.nextInt(60) / 20.0 + random.nextDouble() * 0.01;
      final quantum = wholeTrack ? 1.0 : BoardDropResolver.quantumOf(snap);
      final windowExtent = wholeTrack ? 1.0 : extent;
      _Window window = (
        window: latticeWindowOf(count, windowExtent),
        kind: "lattice",
        band: null,
        lead: 0,
        trail: count,
      );
      final kind = random.nextInt(3);
      if (kind == 1) {
        final k = 1 + random.nextInt(3);
        final band = random.nextBool()
            ? (start: 0, end: k)
            : (start: count - k, end: count);
        final w = bandWindowOf(band, windowExtent);
        if (w != null) {
          window = (
            window: w,
            kind: "band $band",
            band: band,
            lead: 0,
            trail: count,
          );
        }
      } else if (kind == 2) {
        final lead = random.nextInt(4);
        final trail = count - random.nextInt(4);
        final from = lead + random.nextDouble() * (trail - lead);
        final to = from + random.nextDouble() * (trail - from);
        final sample = _sample(
          count: count,
          leadingBandEnd: lead,
          trailingBandStart: trail,
          visibleFrom: lead > 0 ? from : null,
          visibleTo: trail < count ? to : null,
        );
        final w = scrolledWindowOf(sample, windowExtent, quantum);
        if (w != null) {
          window = (
            window: w,
            kind:
                "scrolled from ${sample.visibleFrom} to ${sample.visibleTo}, "
                "bands $lead/$trail",
            band: null,
            lead: lead,
            trail: trail,
          );
        }
      }
      final a = _AxisCase(
        count: count,
        start: start,
        extent: extent,
        radius: radius,
        wholeTrack: wholeTrack,
        window: window.window,
        windowKind: window.kind,
        reachable: _reachable(
          start,
          extent,
          window,
          count,
          wholeTrack: wholeTrack,
        ),
      );
      _checkPure(a, axis, snap, wholeTrackAxis, p1, p3, p4);
      final still = _still(count);
      if (axis == Axis.vertical) {
        _checkCoverage(a, still, snap, wholeTrackAxis, p2strict, p2);
      } else {
        _checkCoverage(still, a, snap, wholeTrackAxis, p2strict, p2);
      }
    }
    for (final t in <_Tally>[p1, p2, p2strict, p3, p4]) {
      debugPrint(t.report());
    }
    expect(p1.failed, 0, reason: p1.report());
    expect(p2.failed, 0, reason: p2.report());
    expect(p3.failed, 0, reason: p3.report());
    expect(p4.failed, 0, reason: p4.report());
  });

  tearDownAll(() {
    for (final t in totals.values) {
      debugPrint(
        "total: ${t.name}: ${t.checked} checked "
        "(${t.reachableChecked} reachable), ${t.failed} failed "
        "(${t.reachableFailed} reachable)",
      );
    }
  });
}
