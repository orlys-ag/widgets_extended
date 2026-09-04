/// Internal: overlap lane assignment for board items.
///
/// Lanes are resolved PER LANE-AXIS TRACK, and the sweep runs along the
/// NON-LANE axis. That partition key is a declared departure from the
/// requirements' advisory per-primary-bucket wording, and the falsifiable
/// reason is the weekday time grid: its primary axis is the row axis and
/// its items span N rows each, so a primary partition would run N resolves
/// for one item into one lane slot and let the last one win.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '_board_store.dart';

/// Assigns each laned item a lane within its lane-axis track, and every
/// member of a cluster the same lane count.
class OverlapLaneResolver {
  /// Creates a resolver over [store]'s items. A null [laneAxis] means no
  /// axis carries a lane extent, which is the spreadsheet and gantt
  /// configuration: nothing is ever laned and this component costs
  /// nothing.
  OverlapLaneResolver({
    required BoardStore<Object?, Object?> store,
    required Axis? laneAxis,
  }) : _store = store,
       _laneAxis = laneAxis;

  final BoardStore<Object?, Object?> _store;

  Axis? _laneAxis;

  /// One entry per LANED item and never more, keyed by lane-axis track.
  /// Carries no sort order and no aggregate, unlike the span index's
  /// buckets: the sort is the resolve's own working list. EMPTY and never
  /// written when [laneAxis] is null.
  final Map<int, List<int>> _laneBuckets = <int, List<int>>{};

  /// Lane-axis buckets whose members changed since the last resolve.
  /// CLEARED by every flush, from either arm, which is exactly why the
  /// structural notification's key set rides [_laneChangedIds] instead.
  final Set<int> _dirtyBuckets = <int>{};

  /// Ids whose assigned lane or lane count differs from the one they held.
  /// THREE writers: a resolve's cluster close, [deregisterItem] through
  /// `_setUnlaned` (which is what puts a retiring id here for the drain's
  /// retired-key exclusion to exclude), and [clear] for every laned item.
  /// Cleared only by [drainLaneChangedIds]; no flush clears it.
  final Set<int> _laneChangedIds = <int>{};

  /// Debug-only: lane-axis buckets [ensureResolved] has actually
  /// processed, whichever arm called it. Rejects the seam of asserting the
  /// resolved lane values, which are identical under a correct incremental
  /// resolve and a correct full re-resolve on every layout while the
  /// second is O(all items log) per frame.
  int debugBucketResolveCount = 0;

  /// The axis items are laned ON, or null when neither config carries a
  /// lane extent. Governs LANE GEOMETRY and this partition, and nothing
  /// else; it is NOT the span index's bucket key.
  Axis? get laneAxis {
    return _laneAxis;
  }

  /// Re-keys the partition. Every bucket is dropped and every laned item
  /// is returned to lane 0 of 1; the owner re-registers. A full
  /// invalidation, which is what an axis swap is.
  set laneAxis(Axis? value) {
    if (value == _laneAxis) {
      return;
    }
    _laneAxis = value;
    clear();
  }

  /// The axis the sweep runs along: the lane axis's complement. Null
  /// exactly when [laneAxis] is.
  Axis? get sweepAxis {
    final axis = _laneAxis;
    if (axis == null) {
      return null;
    }
    return axis == Axis.vertical ? Axis.horizontal : Axis.vertical;
  }

  /// Number of occupied lane-axis buckets.
  int get bucketCount {
    return _laneBuckets.length;
  }

  /// Whether any bucket is waiting to be resolved.
  bool get hasDirtyBuckets {
    return _dirtyBuckets.isNotEmpty;
  }

  /// The largest resolved lane count among [track]'s laned members, or 0
  /// when the bucket is absent or empty, so a track with no cluster
  /// contributes NO term rather than one empty lane's worth. Callers
  /// flush first; this reads resolved state only.
  int maxLaneCountInBucket(int track) {
    final bucket = _laneBuckets[track];
    if (bucket == null || bucket.isEmpty) {
      return 0;
    }
    var max = 1;
    for (final id in bucket) {
      final count = _store.laneCountOf(id);
      if (count > max) {
        max = count;
      }
    }
    return max;
  }

  /// Whether [id] is laned: [laneAxis] is non-null AND the item's
  /// lane-axis interval lies inside ONE integer track.
  ///
  /// A lane is a SLICE OF a lane-axis track, so an item covering two of
  /// them has no single track to be sliced within, while an item covering
  /// ten PRIMARY tracks inside one lane-axis track has exactly one. The
  /// criterion is the LANE axis: neither the primary axis nor the content
  /// axis, whose own exclusion is a different test over a different axis
  /// selecting a different set.
  bool isLaned(int id) {
    final axis = _laneAxis;
    if (axis == null) {
      return false;
    }
    final start = _store.startTrackOf(id, axis);
    final end = _store.endTrackOf(id, axis);
    return end <= start.floorToDouble() + 1 + precisionErrorTolerance;
  }

  /// Adds [id]'s single lane-bucket entry and dirties that bucket, when
  /// [id] is laned. An unlaned item gets no entry and keeps lane 0 of 1.
  void registerItem(int id) {
    if (!isLaned(id)) {
      return;
    }
    final track = _store.startTrackOf(id, _laneAxis!).floor();
    final bucket = _laneBuckets.putIfAbsent(track, () {
      return <int>[];
    });
    bucket.add(id);
    _dirtyBuckets.add(track);
  }

  /// Removes [id]'s entry, dirties the bucket it left, and writes lane 0
  /// of 1 in the SAME call: leaving the old values strands the item in a
  /// slice of a track it no longer sits inside.
  ///
  /// The bucket is computed from the store's CURRENT span, so a caller
  /// changing an item's span de-registers BEFORE writing the new one and
  /// re-registers after. Those two calls are what produce all three
  /// transitions: a move between lane-axis tracks dirties BOTH buckets, a
  /// laned item made unlaned loses its entry here and gains none there,
  /// and an unlaned item made laned gains one there.
  void deregisterItem(int id) {
    if (!isLaned(id)) {
      return;
    }
    final track = _store.startTrackOf(id, _laneAxis!).floor();
    final bucket = _laneBuckets[track];
    final removed = bucket != null && bucket.remove(id);
    assert(
      removed,
      "id $id is laned into lane-axis track $track but holds no entry "
      "there; its span was written before it was de-registered",
    );
    if (bucket != null && bucket.isEmpty) {
      _laneBuckets.remove(track);
    }
    _dirtyBuckets.add(track);
    _setUnlaned(id);
  }

  /// Resolves every dirty bucket and clears the dirty set.
  ///
  /// The owner calls this from the start of layout, before track sizing,
  /// AND from the entry of every read that reports a lane value. Both, not
  /// one: layout-head only would make the values unobservable before the
  /// first layout, and a lane read on the frame of a mutating call is
  /// ordinary rather than exotic.
  void ensureResolved() {
    if (_dirtyBuckets.isEmpty) {
      return;
    }
    final tracks = _dirtyBuckets.toList(growable: false);
    _dirtyBuckets.clear();
    for (final track in tracks) {
      debugBucketResolveCount++;
      _resolveBucket(track);
    }
  }

  /// Reads and clears the lane-change accumulator.
  ///
  /// Drained by exactly one reader, the structural notification's
  /// `affectedKeys` computation, and drained rather than cleared on flush
  /// because a flush can happen at any read. The drain runs AFTER that
  /// reader's own [ensureResolved]: the flush is what puts the current
  /// mutation's changes IN, and the drain is what takes them out.
  Set<int> drainLaneChangedIds() {
    if (_laneChangedIds.isEmpty) {
      return const <int>{};
    }
    final drained = Set<int>.of(_laneChangedIds);
    _laneChangedIds.clear();
    return drained;
  }

  /// Drops every bucket and returns every laned item to lane 0 of 1.
  void clear() {
    for (final bucket in _laneBuckets.values) {
      for (final id in bucket) {
        _setUnlaned(id);
      }
    }
    _laneBuckets.clear();
    _dirtyBuckets.clear();
  }

  void _setUnlaned(int id) {
    if (_store.laneOf(id) != 0 || _store.laneCountOf(id) != 1) {
      _laneChangedIds.add(id);
    }
    _store.setLane(id, 0, 1);
  }

  /// The four steps of the sweep, over HALF-OPEN intervals on the
  /// non-lane axis.
  void _resolveBucket(int track) {
    final bucket = _laneBuckets[track];
    if (bucket == null || bucket.isEmpty) {
      return;
    }
    final sweep = sweepAxis!;
    // Step 1: sort by sweep-axis start ascending, then sweep-axis end
    // DESCENDING, then id ascending. The id tie-break is load-bearing:
    // `List.sort` is not stable and a lane change costs the item's State,
    // so without a final key two resolves over unchanged state can swap
    // two identical intervals and re-key both.
    bucket.sort((a, b) {
      final startA = _store.startTrackOf(a, sweep);
      final startB = _store.startTrackOf(b, sweep);
      if (startA != startB) {
        return startA < startB ? -1 : 1;
      }
      final endA = _store.endTrackOf(a, sweep);
      final endB = _store.endTrackOf(b, sweep);
      if (endA != endB) {
        return endA > endB ? -1 : 1;
      }
      return a.compareTo(b);
    });
    assert(() {
      final laneAxis = _laneAxis!;
      for (final id in bucket) {
        if (!isLaned(id)) {
          throw StateError(
            "lane-axis bucket $track holds id $id, whose lane-axis "
            "interval covers more than one track",
          );
        }
        if (_store.startTrackOf(id, laneAxis).floor() != track) {
          throw StateError(
            "lane-axis bucket $track holds id $id, which now sits in "
            "track ${_store.startTrackOf(id, laneAxis).floor()}",
          );
        }
      }
      return true;
    }());
    _sweep(
      bucket,
      (id) {
        return _store.startTrackOf(id, sweep);
      },
      (id) {
        return _store.endTrackOf(id, sweep);
      },
      (from, until, laneCount, assigned) {
        _closeCluster(bucket, assigned, from, until, laneCount);
      },
    );
  }

  /// The sweep core, shared by the store-writing resolve and the
  /// dry run: assigns lanes over [members] (sorted by the caller) and
  /// reports each closed cluster through [close].
  void _sweep(
    List<int> members,
    double Function(int id) startOf,
    double Function(int id) endOf,
    void Function(int from, int until, int laneCount, List<int> assigned)
        close,
  ) {
    // Assigned lane per member index. Consumed only at a cluster close,
    // so the store-writing arm's change test compares against the values
    // the items held BEFORE this resolve rather than against a
    // provisional count written mid-sweep.
    final assigned = List<int>.filled(members.length, 0);
    // Trailing edge of the last occupant of each open lane, sweep axis.
    final laneEnds = <double>[];
    var clusterStart = 0;
    var maxActiveEnd = double.negativeInfinity;
    for (var i = 0; i < members.length; i++) {
      final id = members[i];
      final start = startOf(id);
      final end = endOf(id);
      // Step 2: the cluster CLOSES when nothing in the active set reaches
      // this item. The tolerance sits on the CLOSING side because the
      // error directions are not symmetric: reading a 10:00 that touches a
      // 09:00-10:00 as an overlap doubles a visible lane count, while
      // reading a 1e-10 overlap as a touch costs one shared lane nobody
      // can see.
      if (i > clusterStart && start >= maxActiveEnd - precisionErrorTolerance) {
        close(clusterStart, i, laneEnds.length, assigned);
        clusterStart = i;
        laneEnds.clear();
        maxActiveEnd = double.negativeInfinity;
      }
      // Step 3: the lowest lane whose last occupant has already ended,
      // under the SAME tolerance step 2 uses. A bare comparison here is
      // the same defect and step 2 does not cover it: step 2 only
      // separates items when nothing connects them, so a 09:00-10:00, a
      // 10:00-11:00 and a 09:00-11:00 are ONE cluster and this test alone
      // decides whether the 10:00 item reuses lane 0.
      var lane = -1;
      for (var candidate = 0; candidate < laneEnds.length; candidate++) {
        if (start >= laneEnds[candidate] - precisionErrorTolerance) {
          lane = candidate;
          break;
        }
      }
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(end);
      } else {
        laneEnds[lane] = end;
      }
      assigned[i] = lane;
      if (end > maxActiveEnd) {
        maxActiveEnd = end;
      }
    }
    close(clusterStart, members.length, laneEnds.length, assigned);
  }

  /// A read-only view of one lane-axis bucket's members, or an empty list
  /// for an absent bucket. For the sizing sweep's scaled cluster term and
  /// the resize install site's contributor walk; callers must not mutate.
  List<int> laneBucketMembers(int track) {
    return _laneBuckets[track] ?? const <int>[];
  }

  /// Re-runs the sweep over the dragged item's stored bucket and the
  /// bucket its [prospective] span would occupy, with the dragged item's
  /// intervals overridden and the laning predicate applied to
  /// [prospective], writing lanes into the RETURNED map and touching
  /// neither the store nor the change accumulator.
  ///
  /// A member absent from the result kept its stored lane; the dragged
  /// item is in the result only where prospectively laned. At most two
  /// buckets, which is what bounds a re-target's cost.
  Map<int, ({int lane, int laneCount})> resolveDryRun({
    required int draggedId,
    required double prospectiveLaneStart,
    required double prospectiveLaneEnd,
    required double prospectiveSweepStart,
    required double prospectiveSweepEnd,
  }) {
    final result = <int, ({int lane, int laneCount})>{};
    final axis = _laneAxis;
    if (axis == null) {
      return result;
    }
    final sweep = sweepAxis!;
    final prospectivelyLaned = prospectiveLaneEnd <=
        prospectiveLaneStart.floorToDouble() + 1 + precisionErrorTolerance;
    final prospectiveTrack = prospectiveLaneStart.floor();
    final tracks = <int>{};
    if (isLaned(draggedId)) {
      tracks.add(_store.startTrackOf(draggedId, axis).floor());
    }
    if (prospectivelyLaned) {
      tracks.add(prospectiveTrack);
    }
    double startOf(int id) {
      if (id == draggedId) {
        return prospectiveSweepStart;
      }
      return _store.startTrackOf(id, sweep);
    }

    double endOf(int id) {
      if (id == draggedId) {
        return prospectiveSweepEnd;
      }
      return _store.endTrackOf(id, sweep);
    }

    for (final track in tracks) {
      final members = List<int>.of(_laneBuckets[track] ?? const <int>[]);
      members.remove(draggedId);
      if (prospectivelyLaned && track == prospectiveTrack) {
        members.add(draggedId);
      }
      if (members.isEmpty) {
        continue;
      }
      members.sort((a, b) {
        final startA = startOf(a);
        final startB = startOf(b);
        if (startA != startB) {
          return startA < startB ? -1 : 1;
        }
        final endA = endOf(a);
        final endB = endOf(b);
        if (endA != endB) {
          return endA > endB ? -1 : 1;
        }
        return a.compareTo(b);
      });
      _sweep(members, startOf, endOf, (from, until, laneCount, assigned) {
        for (var i = from; i < until; i++) {
          result[members[i]] = (lane: assigned[i], laneCount: laneCount);
        }
      });
    }
    return result;
  }

  /// Step 4: the cluster's lane count is ONE MORE THAN THE GREATEST LANE
  /// ASSIGNED in it, written to every member. Lanes are handed out densely
  /// from 0, so that is the number of lanes the cluster opened.
  void _closeCluster(
    List<int> bucket,
    List<int> assigned,
    int from,
    int to,
    int laneCount,
  ) {
    assert(laneCount >= 1 || from >= to);
    for (var i = from; i < to; i++) {
      final id = bucket[i];
      final lane = assigned[i];
      if (_store.laneOf(id) != lane || _store.laneCountOf(id) != laneCount) {
        _laneChangedIds.add(id);
      }
      _store.setLane(id, lane, laneCount);
    }
  }
}
