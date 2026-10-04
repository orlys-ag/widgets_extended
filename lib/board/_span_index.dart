/// Internal: the board's spatial item index.
///
/// One-dimensional, keyed on the PRIMARY axis, with each bucket kept
/// sorted on the SPAN axis so a viewport query is a binary search plus a
/// bounded backward walk rather than a full scan. Not exported from the
/// module barrel.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '_board_span.dart';
import '_board_store.dart';

/// A sparse map from PRIMARY-axis track to the ids filed under it: each
/// id under the tracks its span touches inside the lattice, and always
/// under its first track, with an overflow set for the ids whose span
/// reaches past the lattice's end.
///
/// The PRIMARY axis is the CONTENT-SIZED axis when one exists and the ROW
/// axis otherwise, so it is never null; the SPAN axis is its complement.
/// Neither is the LANE axis in general, and the lane resolver keys its own
/// partition on a different axis on purpose.
class SpanIndex {
  /// Creates an index over [store]'s items, bucketed on [primaryAxis] and
  /// filed against a lattice of [trackCount] primary tracks.
  SpanIndex({
    required BoardStore<Object?, Object?> store,
    required Axis primaryAxis,
    required int trackCount,
  }) : _store = store,
       _primaryAxis = primaryAxis,
       _trackCount = trackCount;

  final BoardStore<Object?, Object?> _store;

  Axis _primaryAxis;

  /// The primary axis's track count the ids are filed against. Changed
  /// only by [reconfigure], so the count [register] filed an id under is
  /// the one [deregister] reads.
  int _trackCount;

  /// Item ids per PRIMARY-axis track. An id is listed in every bucket its
  /// span touches below [_trackCount], and always in its first track's,
  /// so a query over a track range visits that many buckets and
  /// de-duplicates through [_seen]; the part of a span past the lattice is
  /// found through [_overflow]. A sparse map rather than a dense list
  /// because the occupied set is far smaller than the lattice.
  final Map<int, List<int>> _buckets = <int, List<int>>{};

  /// The ids whose span reaches track [_trackCount] or past it. No bucket
  /// at or past that track lists such an id beyond its first track's, so
  /// a query whose range passes the lattice's end scans this set.
  final Set<int> _overflow = <int>{};

  /// Per bucket, the maximum over its members of
  /// `endTrackOn(spanAxis) - startTrackOn(spanAxis)`. Raised in place by
  /// every registration, accepted monotone-HIGH on de-registration, and
  /// recomputed exactly by [flushPendingSorts]. Too LOW ends the backward
  /// walk early and silently drops items; too HIGH only degrades the walk.
  final Map<int, double> _maxSpanAxisExtent = <int, double>{};

  /// Buckets appended to by the BULK path and not yet sorted. Owned HERE
  /// and deliberately NOT shared with the lane resolver's dirty set, which
  /// every lane flush clears: one interleaved lane read between the
  /// appends and the batch exit would otherwise empty it, the sort would
  /// never run, and every later query would binary-search an unsorted
  /// bucket.
  final Set<int> _pendingSortBuckets = <int>{};

  /// The lane axis, when one exists; the ordinal sort's first key reads
  /// it and falls back to the span axis. The controller keeps it in sync
  /// with the resolver's on construction and on every axis swap; a change
  /// invalidates every cached rank.
  Axis? get laneAxis {
    return _laneAxis;
  }

  Axis? _laneAxis;

  set laneAxis(Axis? value) {
    if (value == _laneAxis) {
      return;
    }
    _laneAxis = value;
    _ordinalRanks.clear();
    _ordinalById.clear();
    _ordinalDirty.clear();
  }

  /// Rank order per primary START track: the ids whose primary start
  /// equals the track, sorted by
  /// (startTrackOn(laneAxis ?? spanAxis), startTrackOn(the other axis),
  /// id). The rank is the item vicinity's xIndex component; it ignores
  /// lanes entirely, which is what makes it injective where a lane-keyed
  /// vicinity is not (a lane is reused within a cluster by
  /// non-overlapping items, and non-laned items all carry lane 0).
  final Map<int, List<int>> _ordinalRanks = <int, List<int>>{};

  /// Id to its ordinal, the inverse of [_ordinalRanks]. Written only by
  /// [_ranksFor]'s rebuild, in the same loop that fills the rank list,
  /// removed by [deregister] beside its dirty mark so the map never holds
  /// an id that is not registered, and cleared wherever [_ordinalRanks]
  /// is.
  final Map<int, int> _ordinalById = <int, int>{};

  /// Primary start tracks whose rank list is stale. Registration and
  /// de-registration mark the item's own start track; ranks rebuild
  /// lazily at the first ordinal read.
  final Set<int> _ordinalDirty = <int>{};

  /// De-duplication set, reused across queries rather than allocated per
  /// call. Because it is reused, every query MATERIALIZES EAGERLY and
  /// returns before the next one starts; a lazy walk would be corrupted by
  /// the very next query.
  final Set<int> _seen = <int>{};

  /// Debug-only: bucket entries any operation on this index has touched
  /// since the last reset. Counts each binary-search probe, each step of
  /// the backward walk, each element a sorted insert shifts, each
  /// comparison [ordinalOf]'s rank search makes, each comparison
  /// [deregister]'s bucket search makes, each member a query's overflow
  /// scan reads, each id [reconfigure]'s band walk reads, and each id
  /// [hasIntraTrackItemOn] reads. It is the
  /// only thing that distinguishes the sorted bucket from a full linear
  /// scan, which return identical sets. A field on an unexported class, so
  /// it adds nothing to the public surface.
  int debugProbeCount = 0;

  /// The bucket key axis.
  Axis get primaryAxis {
    return _primaryAxis;
  }

  /// Re-files the index for a new primary axis or track count, and does
  /// nothing when neither changed. Both values are stored first, so every
  /// filing below reads the new ones. A primary-axis change drops every
  /// bucket, whose key changed, and re-files every id the store holds; a
  /// track-count change alone re-files only what lies between the two
  /// counts ([_grow], [_shrink]).
  void reconfigure({required Axis primaryAxis, required int trackCount}) {
    if (primaryAxis == _primaryAxis && trackCount == _trackCount) {
      return;
    }
    final oldCount = _trackCount;
    final axisChanged = primaryAxis != _primaryAxis;
    _primaryAxis = primaryAxis;
    _trackCount = trackCount;
    if (axisChanged) {
      clear();
      for (final id in _store.ids) {
        register(id, bulk: true);
      }
    } else if (trackCount > oldCount) {
      _grow(oldCount, trackCount);
    } else {
      _shrink(oldCount, trackCount);
    }
    flushPendingSorts();
  }

  /// The growth arm of [reconfigure]: each overflowing id gains the
  /// buckets its filing adds between the two counts, and leaves
  /// [_overflow] once its span no longer reaches past the lattice. An id
  /// starting at or past the new count gains nothing.
  void _grow(int oldCount, int newCount) {
    // A copy: the loop removes from the set.
    for (final id in List<int>.of(_overflow)) {
      debugProbeCount++;
      final before = _filingOf(id, oldCount);
      final after = _filingOf(id, newCount);
      if (after.hi > before.hi) {
        final extent = _spanAxisExtentOf(id);
        for (var track = before.hi + 1; track <= after.hi; track++) {
          _file(track, id, extent, bulk: true);
        }
      }
      if (!after.overflows) {
        _overflow.remove(id);
      }
    }
  }

  /// The shrink arm of [reconfigure]: one pass over each bucket between
  /// the two counts, keeping an entry only while its id's filing still
  /// reaches that track and adding each id met that now reaches past the
  /// lattice to [_overflow]. Those buckets are visited by whichever is
  /// smaller, the track range or the bucket map.
  void _shrink(int oldCount, int newCount) {
    void pass(int track) {
      final bucket = _buckets[track];
      if (bucket == null) {
        return;
      }
      var write = 0;
      for (var read = 0; read < bucket.length; read++) {
        final id = bucket[read];
        debugProbeCount++;
        final filing = _filingOf(id, newCount);
        if (filing.hi >= track) {
          bucket[write] = id;
          write++;
        }
        if (filing.overflows) {
          _overflow.add(id);
        }
      }
      bucket.length = write;
      if (bucket.isEmpty) {
        _dropBucket(track);
      }
    }

    if (oldCount - newCount <= _buckets.length) {
      for (var track = newCount; track < oldCount; track++) {
        pass(track);
      }
      return;
    }
    // A copy of the in-band keys: the pass removes the buckets it empties,
    // and a map must not change while its keys are iterated.
    final inBand = <int>[
      for (final track in _buckets.keys)
        if (track >= newCount && track < oldCount) track,
    ];
    for (final track in inBand) {
      pass(track);
    }
  }

  /// The axis a visited bucket is filtered against: the primary axis's
  /// complement.
  Axis get spanAxis {
    return _primaryAxis == Axis.vertical ? Axis.horizontal : Axis.vertical;
  }

  /// Number of occupied buckets.
  int get bucketCount {
    return _buckets.length;
  }

  /// The maximum span-axis extent recorded for [track], or 0 when the
  /// bucket is empty.
  double maxSpanAxisExtentOf(int track) {
    return _maxSpanAxisExtent[track] ?? 0.0;
  }

  /// Files [id] under the PRIMARY-axis buckets its span touches inside
  /// the lattice, and always under its first track's, and adds it to the
  /// overflow set when its span reaches past the lattice ([_filingOf]).
  ///
  /// With [bulk] false this is a SORTED insert per bucket, O(span times k)
  /// for buckets of k items, which is the right trade per mutation. With
  /// [bulk] true it APPENDS and marks the bucket pending, which the caller
  /// resolves with one [flushPendingSorts] at the call's exit; N sorted
  /// inserts into one bucket would otherwise be O(N squared) shifts on
  /// exactly the input a bulk call carries.
  void register(int id, {bool bulk = false}) {
    final filing = _filingOf(id, _trackCount);
    final extent = _spanAxisExtentOf(id);
    _ordinalDirty.add(filing.first);
    for (var track = filing.first; track <= filing.hi; track++) {
      _file(track, id, extent, bulk: bulk);
    }
    if (filing.overflows) {
      _overflow.add(id);
    }
  }

  /// Lists [id] in [track]'s bucket, appended and marked pending when
  /// [bulk] and sorted into place otherwise, and raises the bucket's
  /// aggregate to [extent].
  void _file(int track, int id, double extent, {required bool bulk}) {
    final bucket = _buckets.putIfAbsent(track, () {
      return <int>[];
    });
    if (bulk) {
      bucket.add(id);
      _pendingSortBuckets.add(track);
    } else {
      final at = _insertionIndex(bucket, id);
      debugProbeCount += bucket.length - at;
      bucket.insert(at, id);
    }
    if (extent > (_maxSpanAxisExtent[track] ?? 0.0)) {
      _maxSpanAxisExtent[track] = extent;
    }
  }

  /// [id]'s filing under a lattice of [count] primary tracks: the buckets
  /// `first` to `hi`, its span's tracks below [count] and always its first
  /// track's, and whether its span reaches track [count] or past it. The
  /// one computation of both, read by [register] and [deregister] at the
  /// stored count and by [reconfigure]'s band walk at both counts.
  ({int first, int hi, bool overflows}) _filingOf(int id, int count) {
    final first = _store.startIndexOf(id, _primaryAxis);
    final last = _lastTrackOf(id, first);
    return (
      first: first,
      hi: math.max(first, math.min(last, count - 1)),
      overflows: last >= count,
    );
  }

  /// Removes [id] from every bucket it is filed under and from the
  /// overflow set.
  ///
  /// The bucket range is computed from the store's CURRENT span, so a
  /// caller changing an item's span de-registers BEFORE writing the new
  /// one and re-registers after.
  ///
  /// The aggregate is left monotone-HIGH rather than rescanned: rescanning
  /// to lower one number would make a single removal cost a second pass,
  /// and a stale-high value is correct-but-slower, never wrong. Only
  /// [flushPendingSorts] ever lowers it.
  void deregister(int id) {
    final filing = _filingOf(id, _trackCount);
    _ordinalDirty.add(filing.first);
    _ordinalById.remove(id);
    _overflow.remove(id);
    for (var track = filing.first; track <= filing.hi; track++) {
      final bucket = _buckets[track];
      if (bucket == null) {
        continue;
      }
      final int at;
      if (_pendingSortBuckets.contains(track)) {
        // Appended by the bulk path and not yet sorted: no order to
        // search, so this is the one arm that walks.
        at = _linearIndex(bucket, id);
      } else {
        at = _removalIndex(bucket, id);
      }
      if (at >= 0) {
        bucket.removeAt(at);
      }
      if (bucket.isEmpty) {
        _dropBucket(track);
      }
    }
  }

  /// Removes [track]'s emptied bucket with its aggregate and pending mark.
  void _dropBucket(int track) {
    _buckets.remove(track);
    _maxSpanAxisExtent.remove(track);
    _pendingSortBuckets.remove(track);
  }

  /// The padded last PRIMARY-axis track of [id]'s span, given its first,
  /// uncut by the lattice.
  ///
  /// `endTrackOf` is a double sum, so a span whose parts add to a whole
  /// track can land an ulp above it (`0.78 + 2 + 0.22` is
  /// `3.0000000000000004`); an unpadded `ceil() - 1` would bucket that
  /// item into a track it does not occupy, and [_query] would then admit
  /// it for a range starting there. Padded by the tolerance, and floored
  /// at [firstTrack] so a span thinner than the tolerance still owns its
  /// own bucket.
  int _lastTrackOf(int id, int firstTrack) {
    final end = _store.endTrackOf(id, _primaryAxis);
    return math.max(firstTrack, trackEndIndexOf(end) - 1);
  }

  /// Sorts every bucket the BULK path appended to and recomputes its
  /// aggregate in the same walk.
  ///
  /// The ONE flush site. Called from the entry of both query forms, which
  /// is what makes a mid-batch query safe, AND from the bulk path's exit,
  /// which is what keeps the cost one sort per bucket rather than one per
  /// interleaved read. Idempotent, and one set-empty check when there is
  /// nothing pending, so the two arms do not fight.
  void flushPendingSorts() {
    if (_pendingSortBuckets.isEmpty) {
      return;
    }
    for (final track in _pendingSortBuckets) {
      final bucket = _buckets[track];
      if (bucket == null) {
        continue;
      }
      bucket.sort(_compare);
      var maxExtent = 0.0;
      for (final id in bucket) {
        final extent = _spanAxisExtentOf(id);
        if (extent > maxExtent) {
          maxExtent = extent;
        }
      }
      _maxSpanAxisExtent[track] = maxExtent;
    }
    _pendingSortBuckets.clear();
  }

  /// Ids intersecting the track rect, EXCLUDING ids whose exiting bit is
  /// set. Backs the caller-facing reads, which map ids to keys, and the
  /// render port's spatial query. Materializes a fresh list per call.
  ///
  /// All four bounds are half-open track ranges: an item ending exactly at
  /// a range start does not intersect it.
  List<int> itemsInRect(int rowStart, int rowEnd, int colStart, int colEnd) {
    return _query(
      rowStart,
      rowEnd,
      colStart,
      colEnd,
      <int>[],
      includeExiting: false,
    );
  }

  /// Ids intersecting the track rect, INCLUDING ids whose exiting bit is
  /// set. Backs layout's obtain set, lane resolution and intrinsic track
  /// sizing, all of which must keep an exiting item until it settles.
  ///
  /// APPENDS into [into] and returns it, so the per-layout path allocates
  /// nothing; the caller owns [into] and clears it.
  List<int> itemsInRectIncludingExiting(
    int rowStart,
    int rowEnd,
    int colStart,
    int colEnd,
    List<int> into,
  ) {
    return _query(
      rowStart,
      rowEnd,
      colStart,
      colEnd,
      into,
      includeExiting: true,
    );
  }

  /// Drops every bucket.
  void clear() {
    _buckets.clear();
    _overflow.clear();
    _maxSpanAxisExtent.clear();
    _pendingSortBuckets.clear();
    _seen.clear();
    _ordinalRanks.clear();
    _ordinalById.clear();
    _ordinalDirty.clear();
  }

  List<int> _query(
    int rowStart,
    int rowEnd,
    int colStart,
    int colEnd,
    List<int> into, {
    required bool includeExiting,
  }) {
    flushPendingSorts();
    _seen.clear();
    final primaryIsRow = _primaryAxis == Axis.vertical;
    final primaryStart = primaryIsRow ? rowStart : colStart;
    final primaryEnd = primaryIsRow ? rowEnd : colEnd;
    final rangeStart = (primaryIsRow ? colStart : rowStart).toDouble();
    final rangeEnd = (primaryIsRow ? colEnd : rowEnd).toDouble();
    final walkEnd = math.min(primaryEnd, _trackCount);
    for (var track = primaryStart; track < walkEnd; track++) {
      final bucket = _buckets[track];
      if (bucket == null) {
        continue;
      }
      final maxExtent = _maxSpanAxisExtent[track] ?? 0.0;
      // First index whose span-axis start is at or past the range end.
      // Everything at or after it starts too late to intersect.
      var low = 0;
      var high = bucket.length;
      while (low < high) {
        final mid = (low + high) >> 1;
        debugProbeCount++;
        if (_startOf(bucket[mid]) >= rangeEnd) {
          high = mid;
        } else {
          low = mid + 1;
        }
      }
      for (var i = low - 1; i >= 0; i--) {
        debugProbeCount++;
        final id = bucket[i];
        final start = _startOf(id);
        // Padded by the tolerance: `fl(start + fl(end - start))` can
        // undershoot `end` by an ulp across an integer, so an unpadded
        // break drops an item the admit test below would accept. Costs a
        // few extra probes; the admit test still reads the true endpoint.
        if (start + maxExtent <= rangeStart - precisionErrorTolerance) {
          break;
        }
        // No primary-axis re-test: membership in a visited bucket already
        // implies intersection with the query's integer primary range.
        // Padded on both ends: an endpoint an ulp past a range bound is
        // ON the bound, and a half-open range does not intersect there.
        if (_admits(start, _endOf(id), rangeStart, rangeEnd)) {
          if (!includeExiting && _store.isExiting(id)) {
            continue;
          }
          if (_seen.add(id)) {
            into.add(id);
          }
        }
      }
    }
    // The part of the range past the lattice: no bucket there lists an id
    // beyond its first track's, so the overflow set is read instead.
    final pastStart = math.max(primaryStart, _trackCount);
    if (pastStart < primaryEnd) {
      for (final id in _overflow) {
        debugProbeCount++;
        final first = _store.startIndexOf(id, _primaryAxis);
        if (first >= primaryEnd || _lastTrackOf(id, first) < pastStart) {
          continue;
        }
        if (!_admits(_startOf(id), _endOf(id), rangeStart, rangeEnd)) {
          continue;
        }
        if (!includeExiting && _store.isExiting(id)) {
          continue;
        }
        if (_seen.add(id)) {
          into.add(id);
        }
      }
    }
    return into;
  }

  double _startOf(int id) {
    return _store.startTrackOf(id, spanAxis);
  }

  double _endOf(int id) {
    return _store.endTrackOf(id, spanAxis);
  }

  /// The admit test on the span axis: whether `[start, end)` intersects
  /// the half-open `[rangeStart, rangeEnd)`, padded on both ends because
  /// an endpoint an ulp past a range bound is ON the bound. The ONE site
  /// of the rule; [_query] and [coversCell] both call it.
  bool _admits(double start, double end, double rangeStart, double rangeEnd) {
    return start < rangeEnd - precisionErrorTolerance &&
        end > rangeStart + precisionErrorTolerance;
  }

  /// Whether [id]'s span covers cell `(row, col)` by the SAME two rules
  /// [itemsInRect] lists it by: the cell's primary track lies inside the
  /// id's padded primary range, uncut by the lattice as [itemsInRect]'s
  /// overflow scan reads it, and the cell's
  /// unit range on the span axis passes the padded admit test [_query]
  /// applies. Both rules are CALLED, not restated, so a change to either
  /// reaches this predicate for free. Reads no exiting bit; the caller
  /// decides that.
  bool coversCell(int id, int row, int col) {
    final primaryIsRow = _primaryAxis == Axis.vertical;
    final primaryTrack = primaryIsRow ? row : col;
    final firstTrack = _store.startIndexOf(id, _primaryAxis);
    if (primaryTrack < firstTrack ||
        primaryTrack > _lastTrackOf(id, firstTrack)) {
      return false;
    }
    final spanTrack = (primaryIsRow ? col : row).toDouble();
    return _admits(_startOf(id), _endOf(id), spanTrack, spanTrack + 1.0);
  }

  /// Whether an id's padded primary range is the one track [track]: its
  /// first track by the start rule is [track], and so is its padded last
  /// track. Reads [track]'s bucket only, which lists every such id, and
  /// stops at the first; exiting ids count.
  bool hasIntraTrackItemOn(int track) {
    final bucket = _buckets[track];
    if (bucket == null) {
      return false;
    }
    for (final id in bucket) {
      debugProbeCount++;
      final first = _store.startIndexOf(id, _primaryAxis);
      if (first == track && _lastTrackOf(id, first) == track) {
        return true;
      }
    }
    return false;
  }

  /// The item's rank among the items whose primary START track equals its
  /// own. The item vicinity's xIndex component.
  int ordinalOf(int id) {
    final track = _store.startIndexOf(id, _primaryAxis);
    // The rebuild call is what makes a dirty track rebuild FIRST: either
    // the track is dirty and the rebuild overwrites the id's entry before
    // the read, or it is clean and nothing registered on it since the
    // entry was written. One map read, counted as one probe.
    _ranksFor(track);
    debugProbeCount++;
    final at = _ordinalById[id];
    assert(
      at != null,
      "ordinalOf($id) on a track whose rank list does not hold it; the "
      "item was mutated without deregister-register",
    );
    return at ?? -1;
  }

  /// The id at [ordinal] on primary start track [track], or noId when the
  /// slot is empty. The widget's builder resolves an item vicinity back
  /// to its item through this.
  int idAtOrdinal(int track, int ordinal) {
    final ranks = _ranksFor(track);
    if (ordinal < 0 || ordinal >= ranks.length) {
      return BoardStore.noId;
    }
    return ranks[ordinal];
  }

  /// The number of rank slots on primary start track [track].
  int ordinalCountOf(int track) {
    return _ranksFor(track).length;
  }

  List<int> _ranksFor(int track) {
    var ranks = _ordinalRanks[track];
    if (ranks != null && !_ordinalDirty.contains(track)) {
      return ranks;
    }
    final bucket = _buckets[track];
    ranks = <int>[];
    if (bucket != null) {
      for (final id in bucket) {
        if (_store.startIndexOf(id, _primaryAxis) == track) {
          ranks.add(id);
        }
      }
      final keyAxis = _laneAxis ?? spanAxis;
      final otherAxis = keyAxis == Axis.vertical
          ? Axis.horizontal
          : Axis.vertical;
      ranks.sort((a, b) {
        final first = _store
            .startTrackOf(a, keyAxis)
            .compareTo(_store.startTrackOf(b, keyAxis));
        if (first != 0) {
          return first;
        }
        final second = _store
            .startTrackOf(a, otherAxis)
            .compareTo(_store.startTrackOf(b, otherAxis));
        if (second != 0) {
          return second;
        }
        return a.compareTo(b);
      });
    }
    for (var i = 0; i < ranks.length; i++) {
      _ordinalById[ranks[i]] = i;
    }
    _ordinalRanks[track] = ranks;
    _ordinalDirty.remove(track);
    return ranks;
  }

  double _spanAxisExtentOf(int id) {
    final axis = spanAxis;
    return _store.endTrackOf(id, axis) - _store.startTrackOf(id, axis);
  }

  /// Bucket order: span-axis start ascending, then span-axis end
  /// DESCENDING, then id ascending. The id tie-break is load-bearing:
  /// `List.sort` is not stable, so without a final key two resolves over
  /// unchanged state can swap two identical intervals.
  int _compare(int a, int b) {
    final startA = _startOf(a);
    final startB = _startOf(b);
    if (startA != startB) {
      return startA < startB ? -1 : 1;
    }
    final endA = _endOf(a);
    final endB = _endOf(b);
    if (endA != endB) {
      return endA > endB ? -1 : 1;
    }
    return a.compareTo(b);
  }

  /// The index of [id] in a SORTED bucket, or -1: the lower bound under
  /// [_compare], the mirror of [_insertionIndex]'s upper bound, followed
  /// by a walk over the equal-key run until the id. That run has length
  /// one, since [_compare] ends on the id and no two distinct ids compare
  /// equal, so the walk exists only so a missing id degrades to -1 rather
  /// than removing a neighbour. Each probe is counted.
  ///
  /// Reads the keys the store holds NOW, which are the keys the item was
  /// inserted under because every span mutator de-registers before
  /// writing (see [deregister]).
  int _removalIndex(List<int> bucket, int id) {
    var low = 0;
    var high = bucket.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      debugProbeCount++;
      if (_compare(bucket[mid], id) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < bucket.length; i++) {
      debugProbeCount++;
      if (bucket[i] == id) {
        return i;
      }
      if (_compare(bucket[i], id) > 0) {
        break;
      }
    }
    return -1;
  }

  /// The index of [id] in an UNSORTED bucket, or -1, counting each probe.
  int _linearIndex(List<int> bucket, int id) {
    for (var i = 0; i < bucket.length; i++) {
      debugProbeCount++;
      if (bucket[i] == id) {
        return i;
      }
    }
    return -1;
  }

  /// Upper bound for [id] under [_compare], counting each probe.
  int _insertionIndex(List<int> bucket, int id) {
    var low = 0;
    var high = bucket.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      debugProbeCount++;
      if (_compare(bucket[mid], id) <= 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
