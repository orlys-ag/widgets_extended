/// Internal: the board's spatial item index.
///
/// One-dimensional, keyed on the PRIMARY axis, with each bucket kept
/// sorted on the SPAN axis so a viewport query is a binary search plus a
/// bounded backward walk rather than a full scan. Not exported from the
/// module barrel.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '_board_store.dart';

/// A sparse map from PRIMARY-axis track to the ids whose span touches it.
///
/// The PRIMARY axis is the CONTENT-SIZED axis when one exists and the ROW
/// axis otherwise, so it is never null; the SPAN axis is its complement.
/// Neither is the LANE axis in general, and the lane resolver keys its own
/// partition on a different axis on purpose.
class SpanIndex {
  /// Creates an index over [store]'s items, bucketed on [primaryAxis].
  SpanIndex({
    required BoardStore<Object?, Object?> store,
    required Axis primaryAxis,
  }) : _store = store,
       _primaryAxis = primaryAxis;

  final BoardStore<Object?, Object?> _store;

  Axis _primaryAxis;

  /// Item ids per PRIMARY-axis track. An item is listed in EVERY bucket
  /// its span touches, so a query over a track range visits that many
  /// buckets and de-duplicates through [_seen]. A sparse map rather than a
  /// dense list because the track count is unbounded while the occupied
  /// set is not.
  final Map<int, List<int>> _buckets = <int, List<int>>{};

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
  /// the backward walk, and each element a sorted insert shifts. It is the
  /// only thing that distinguishes the sorted bucket from a full linear
  /// scan, which return identical sets. A field on an unexported class, so
  /// it adds nothing to the public surface.
  int debugProbeCount = 0;

  /// The bucket key axis.
  Axis get primaryAxis {
    return _primaryAxis;
  }

  /// Re-keys the index. Every bucket is dropped, because the key changed;
  /// the owner re-registers every item. A full invalidation, which is what
  /// an axis swap is.
  set primaryAxis(Axis value) {
    if (value == _primaryAxis) {
      return;
    }
    _primaryAxis = value;
    _ordinalRanks.clear();
    _ordinalDirty.clear();
    clear();
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

  /// Registers [id] in every PRIMARY-axis bucket its span touches.
  ///
  /// With [bulk] false this is a SORTED insert per bucket, O(span times k)
  /// for buckets of k items, which is the right trade per mutation. With
  /// [bulk] true it APPENDS and marks the bucket pending, which the caller
  /// resolves with one [flushPendingSorts] at the call's exit; N sorted
  /// inserts into one bucket would otherwise be O(N squared) shifts on
  /// exactly the input a bulk call carries.
  void register(int id, {bool bulk = false}) {
    final firstTrack = _store.startTrackOf(id, _primaryAxis).floor();
    final lastTrack = _store.endTrackOf(id, _primaryAxis).ceil() - 1;
    assert(
      lastTrack >= firstTrack,
      "a span asserts a positive extent, so its bucket range is never "
      "empty",
    );
    final extent = _spanAxisExtentOf(id);
    _ordinalDirty.add(firstTrack);
    for (var track = firstTrack; track <= lastTrack; track++) {
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
  }

  /// Removes [id] from every bucket its span touches.
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
    final firstTrack = _store.startTrackOf(id, _primaryAxis).floor();
    final lastTrack = _store.endTrackOf(id, _primaryAxis).ceil() - 1;
    _ordinalDirty.add(firstTrack);
    for (var track = firstTrack; track <= lastTrack; track++) {
      final bucket = _buckets[track];
      if (bucket == null) {
        continue;
      }
      bucket.remove(id);
      if (bucket.isEmpty) {
        _buckets.remove(track);
        _maxSpanAxisExtent.remove(track);
        _pendingSortBuckets.remove(track);
      }
    }
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
    _maxSpanAxisExtent.clear();
    _pendingSortBuckets.clear();
    _seen.clear();
    _ordinalRanks.clear();
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
    for (var track = primaryStart; track < primaryEnd; track++) {
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
        if (start < rangeEnd && _endOf(id) > rangeStart) {
          if (!includeExiting && _store.isExiting(id)) {
            continue;
          }
          if (_seen.add(id)) {
            into.add(id);
          }
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

  /// The item's rank among the items whose primary START track equals its
  /// own. The item vicinity's xIndex component.
  int ordinalOf(int id) {
    final track = _store.startTrackOf(id, _primaryAxis).floor();
    final ranks = _ranksFor(track);
    final at = ranks.indexOf(id);
    assert(
      at >= 0,
      "ordinalOf($id) on a track whose rank list does not hold it; the "
      "item was mutated without deregister-register",
    );
    return at;
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
        if (_store.startTrackOf(id, _primaryAxis).floor() == track) {
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
