/// Internal: the board's ECS-style item store.
///
/// Dense integer item ids with a LIFO free list, and one dense array per
/// per-item component. Copies the idiom of the tree's node id registry,
/// not the class, and takes the same three obligations a dense-array owner
/// takes on: grow when an allocation reports growth, reset a recycled slot,
/// and zero on release.
///
/// Not exported from the module barrel, which is why the arrays can carry
/// public per-id accessors at no cost to the public surface: the span
/// index, the lane resolver and the animation coordinator are separate
/// libraries and reach the components through those accessors.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '_board_span.dart';

/// Dense per-item component storage for one board.
///
/// Every array below is indexed by item id and grown in lockstep by
/// [_onCapacityGrew]. A new per-item array that misses that callback
/// range-errors on the first item past the old capacity, which is why the
/// growth path is one function.
class BoardStore<TKey, TItem> {
  /// Creates an empty store.
  BoardStore();

  /// Sentinel returned by [idOf] for an unregistered key. Matches the
  /// tree's `NodeIdRegistry.noNid`.
  static const int noId = -1;

  /// Bit 0 of the flags byte: the item is animating OUT. The single
  /// normative record of that state; nothing re-derives it from an
  /// animation's progress.
  static const int exitingBit = 1;

  /// Bit 1 of the flags byte: the item is animating IN.
  static const int enteringBit = 2;

  /// Bit 2 of the flags byte: the item is being dragged.
  static const int draggingBit = 4;

  final Map<TKey, int> _keyToId = <TKey, int>{};
  final List<TKey?> _idToKey = <TKey?>[];
  final List<int> _freeIds = <int>[];
  final List<TItem?> _data = <TItem?>[];

  Int32List _rowStart = Int32List(0);
  Int32List _rowSpan = Int32List(0);
  Int32List _colStart = Int32List(0);
  Int32List _colSpan = Int32List(0);
  Float64List _rowFraction = Float64List(0);
  Float64List _colFraction = Float64List(0);
  Float64List _rowSpanFraction = Float64List(0);
  Float64List _colSpanFraction = Float64List(0);
  Int32List _lane = Int32List(0);
  Int32List _laneCount = Int32List(0);
  Int32List _laneSpan = Int32List(0);
  Uint8List _flags = Uint8List(0);

  /// Every registered id, in ascending id order. Allocates, so it is for
  /// callers off the per-frame path.
  Iterable<int> get ids sync* {
    for (var id = 0; id < _idToKey.length; id++) {
      if (_idToKey[id] != null) {
        yield id;
      }
    }
  }

  /// The id for [key], or [noId] when it is not registered.
  int idOf(TKey key) {
    return _keyToId[key] ?? noId;
  }

  /// The key for [id], or null when the slot is free or out of range.
  TKey? keyOf(int id) {
    if (id < 0 || id >= _idToKey.length) {
      return null;
    }
    return _idToKey[id];
  }

  /// Whether the last [allocate] call took its id from the free list
  /// rather than growing the arrays. A recycled slot carried a previous
  /// occupant, so per-id state OUTSIDE this store (the animation sources)
  /// must be reset by the caller; the store's own slot is reset either
  /// way.
  bool lastAllocationWasRecycled = false;

  /// Allocates an id for [key] and resets its slot, or returns the
  /// existing id when [key] is already registered.
  int allocate(TKey key) {
    final existing = _keyToId[key];
    if (existing != null) {
      assert(
        (_flags[existing] & exitingBit) == 0,
        "BoardStore.allocate: key $key still maps to exiting id "
        "$existing. A re-add while the previous incarnation is exiting "
        "must retire it first, or the enter rides the dying id.",
      );
      lastAllocationWasRecycled = false;
      return existing;
    }
    final int id;
    if (_freeIds.isNotEmpty) {
      id = _freeIds.removeLast();
      _idToKey[id] = key;
      lastAllocationWasRecycled = true;
    } else {
      id = _idToKey.length;
      _idToKey.add(key);
      _data.add(null);
      _onCapacityGrew(_idToKey.length);
      lastAllocationWasRecycled = false;
    }
    _keyToId[key] = id;
    _resetSlot(id);
    return id;
  }

  /// Releases [key]'s id back to the pool and zeroes its slot. Returns the
  /// released id, or [noId] when [key] was not registered.
  int release(TKey key) {
    final id = _keyToId.remove(key);
    if (id == null) {
      return noId;
    }
    _idToKey[id] = null;
    _resetSlot(id);
    _freeIds.add(id);
    return id;
  }

  /// Number of id slots ever allocated; every live id is below it. The
  /// TOTAL flag reads on the animation reader range-check against this.
  int get capacity {
    return _idToKey.length;
  }

  /// The caller's item for [id], or null for a free slot.
  TItem? dataOf(int id) {
    assert(id >= 0 && id < _data.length);
    return _data[id];
  }

  /// Writes the caller's item for [id]. The payload-only channel: it
  /// touches no span component, which is why the data notification and the
  /// structural one are separate.
  void setData(int id, TItem item) {
    assert(id >= 0 && id < _data.length);
    _data[id] = item;
  }

  /// Leading row track of [id]. Track space.
  int rowStartOf(int id) {
    return _rowStart[id];
  }

  /// Integer row span of [id]. Track space.
  int rowSpanOf(int id) {
    return _rowSpan[id];
  }

  /// Leading column track of [id]. Track space.
  int colStartOf(int id) {
    return _colStart[id];
  }

  /// Integer column span of [id]. Track space.
  int colSpanOf(int id) {
    return _colSpan[id];
  }

  /// Leading row fraction of [id]. Track space.
  double rowFractionOf(int id) {
    return _rowFraction[id];
  }

  /// Leading column fraction of [id]. Track space.
  double colFractionOf(int id) {
    return _colFraction[id];
  }

  /// Trailing row span fraction of [id]. Track space.
  double rowSpanFractionOf(int id) {
    return _rowSpanFraction[id];
  }

  /// Trailing column span fraction of [id]. Track space.
  double colSpanFractionOf(int id) {
    return _colSpanFraction[id];
  }

  /// The EXACT track-space leading endpoint of [id] on [axis]. The
  /// id-keyed twin of [BoardSpan.startTrackOn], reading the dense arrays
  /// so no span object is allocated on the per-layout path.
  double startTrackOf(int id, Axis axis) {
    return axis == Axis.vertical
        ? _rowStart[id] + _rowFraction[id]
        : _colStart[id] + _colFraction[id];
  }

  /// The EXACT track-space trailing endpoint of [id] on [axis]. The span
  /// occupies the HALF-OPEN interval
  /// `[startTrackOf(id, axis), endTrackOf(id, axis))`.
  double endTrackOf(int id, Axis axis) {
    return axis == Axis.vertical
        ? _rowStart[id] + _rowFraction[id] + _rowSpan[id] + _rowSpanFraction[id]
        : _colStart[id] +
              _colFraction[id] +
              _colSpan[id] +
              _colSpanFraction[id];
  }

  /// Materializes [id]'s span. Allocates, so it is for caller-facing reads
  /// and not for the per-layout path.
  BoardSpan spanOf(int id) {
    return BoardSpan(
      rowStart: _rowStart[id],
      colStart: _colStart[id],
      rowSpan: _rowSpan[id],
      colSpan: _colSpan[id],
      rowFraction: _rowFraction[id],
      colFraction: _colFraction[id],
      rowSpanFraction: _rowSpanFraction[id],
      colSpanFraction: _colSpanFraction[id],
    );
  }

  /// Writes [id]'s span components. One of the four span mutators' single
  /// write site.
  void setSpan(int id, BoardSpan span) {
    assert(id >= 0 && id < _rowStart.length);
    _rowStart[id] = span.rowStart;
    _rowSpan[id] = span.rowSpan;
    _colStart[id] = span.colStart;
    _colSpan[id] = span.colSpan;
    _rowFraction[id] = span.rowFraction;
    _colFraction[id] = span.colFraction;
    _rowSpanFraction[id] = span.rowSpanFraction;
    _colSpanFraction[id] = span.colSpanFraction;
  }

  /// [id]'s lane within its lane-axis track. Written only by the lane
  /// resolver.
  int laneOf(int id) {
    return _lane[id];
  }

  /// The number of lanes [id]'s cluster resolved to. Written only by the
  /// lane resolver.
  int laneCountOf(int id) {
    return _laneCount[id];
  }

  /// The number of CONSECUTIVE lanes [id] occupies, counting upward from
  /// [laneOf]. Written only by the lane resolver, and 1 for an unlaned
  /// item and for a member whose next lane up is occupied.
  int laneSpanOf(int id) {
    return _laneSpan[id];
  }

  /// Writes [id]'s lane record. The lane resolver is the only caller.
  void setLane(int id, int lane, int laneCount, int laneSpan) {
    assert(id >= 0 && id < _lane.length);
    assert(lane >= 0);
    assert(laneCount >= 1);
    assert(lane < laneCount);
    assert(laneSpan >= 1);
    assert(lane + laneSpan <= laneCount);
    _lane[id] = lane;
    _laneCount[id] = laneCount;
    _laneSpan[id] = laneSpan;
  }

  /// Whether [id] is animating out.
  bool isExiting(int id) {
    return (_flags[id] & exitingBit) != 0;
  }

  /// Whether [id] is animating in.
  bool isEntering(int id) {
    return (_flags[id] & enteringBit) != 0;
  }

  /// Whether [id] is being dragged.
  bool isDragging(int id) {
    return (_flags[id] & draggingBit) != 0;
  }

  /// Sets or clears one flag bit on [id].
  void setFlag(int id, int bit, bool value) {
    assert(id >= 0 && id < _flags.length);
    assert(bit == exitingBit || bit == enteringBit || bit == draggingBit);
    if (value) {
      _flags[id] |= bit;
    } else {
      _flags[id] &= ~bit;
    }
  }

  /// Resets [id]'s slot to the state a fresh allocation expects: no data,
  /// a one-by-one span at the origin, lane 0 of 1 spanning one lane, and
  /// no flags. Recycled slots carry the previous occupant's data, which
  /// is what this exists for.
  void _resetSlot(int id) {
    _data[id] = null;
    _rowStart[id] = 0;
    _rowSpan[id] = 1;
    _colStart[id] = 0;
    _colSpan[id] = 1;
    _rowFraction[id] = 0.0;
    _colFraction[id] = 0.0;
    _rowSpanFraction[id] = 0.0;
    _colSpanFraction[id] = 0.0;
    _lane[id] = 0;
    _laneCount[id] = 1;
    _laneSpan[id] = 1;
    _flags[id] = 0;
  }

  /// Grows every dense array in lockstep so its length is at least
  /// [newCapacity]. The one growth path; every per-item array is listed
  /// here.
  void _onCapacityGrew(int newCapacity) {
    if (_rowStart.length >= newCapacity) {
      return;
    }
    var grown = _rowStart.isEmpty ? 8 : _rowStart.length * 2;
    while (grown < newCapacity) {
      grown *= 2;
    }
    _rowStart = _grownInt32(_rowStart, grown);
    _rowSpan = _grownInt32(_rowSpan, grown);
    _colStart = _grownInt32(_colStart, grown);
    _colSpan = _grownInt32(_colSpan, grown);
    _rowFraction = _grownFloat64(_rowFraction, grown);
    _colFraction = _grownFloat64(_colFraction, grown);
    _rowSpanFraction = _grownFloat64(_rowSpanFraction, grown);
    _colSpanFraction = _grownFloat64(_colSpanFraction, grown);
    _lane = _grownInt32(_lane, grown);
    _laneCount = _grownInt32(_laneCount, grown);
    _laneSpan = _grownInt32(_laneSpan, grown);
    _flags = _grownUint8(_flags, grown);
  }

  static Int32List _grownInt32(Int32List old, int length) {
    final grown = Int32List(length);
    grown.setRange(0, old.length, old);
    return grown;
  }

  static Float64List _grownFloat64(Float64List old, int length) {
    final grown = Float64List(length);
    grown.setRange(0, old.length, old);
    return grown;
  }

  static Uint8List _grownUint8(Uint8List old, int length) {
    final grown = Uint8List(length);
    grown.setRange(0, old.length, old);
    return grown;
  }
}
