/// Internal: a Fenwick (binary indexed) tree over doubles.
///
/// Backs `LazyContentAxis`, which stores `extentOf(i) - estimate` at every
/// measured track `i` so that `offsetOf(track)` is
/// `track * estimate + prefixSum(track)` and `trackAt(offset)` is a
/// [lowerBound] over that same accumulation. Not exported from the module
/// barrel: the axis owns the single instance.
library;

import 'dart:typed_data';

/// A Fenwick tree over `double` values with an O(log n) prefix sum,
/// point update and lower-bound descent.
///
/// All three operations are O(log n) in [length]. Every stored value is
/// expected to leave the accumulated prefix non-decreasing, which is what
/// makes [lowerBound]'s descent valid; the axis guarantees that by
/// flooring every extent it records at a strictly positive minimum.
class Fenwick {
  /// Creates a tree over [length] slots, all zero.
  Fenwick(this.length) : assert(length >= 0), _tree = Float64List(length + 1) {
    var high = 1;
    while (high * 2 <= length) {
      high *= 2;
    }
    _highBit = length == 0 ? 0 : high;
  }

  /// Number of value slots, indexed `[0, length)`.
  final int length;

  /// One-indexed internal storage; slot 0 is unused.
  final Float64List _tree;

  /// Largest power of two not exceeding [length], the descent's first
  /// step. Zero for an empty tree.
  late final int _highBit;

  /// Debug-only: number of internal array entries this tree has touched
  /// since the last reset, for the operation-count budget in the oracle
  /// fuzz. A field on an unexported class, so it adds nothing to the
  /// public surface. Tests assign 0 to it to measure one call.
  int debugOpCount = 0;

  /// Adds [delta] to the value at [index].
  void add(int index, double delta) {
    assert(index >= 0 && index < length);
    for (var i = index + 1; i <= length; i += i & -i) {
      debugOpCount++;
      _tree[i] += delta;
    }
  }

  /// Sum of the values at `[0, index)`.
  double prefixSum(int index) {
    assert(index >= 0 && index <= length);
    var sum = 0.0;
    for (var i = index; i > 0; i -= i & -i) {
      debugOpCount++;
      sum += _tree[i];
    }
    return sum;
  }

  /// Largest `i` in `[0, length]` for which
  /// `i * perIndexBias + prefixSum(i) <= value`.
  ///
  /// [perIndexBias] is added once per index covered, which is what lets
  /// `LazyContentAxis` store deltas against its estimate and still descend
  /// over the accumulation its offsets are written in. With the default
  /// bias of zero this is the ordinary Fenwick lower bound.
  ///
  /// The descent accumulates ONE `power * perIndexBias` term per level,
  /// which is a different association than a caller whose offsets read
  /// `index * perIndexBias + prefixSum(index)`. At an exact boundary the
  /// two expressions can disagree by an ulp and this returns `index - 1`,
  /// so a caller that has to invert its own offset expression corrects the
  /// result against that expression rather than trusting this one;
  /// `LazyContentAxis.trackAt` does.
  int lowerBound(double value, {double perIndexBias = 0.0}) {
    var position = 0;
    var remaining = value;
    for (var power = _highBit; power > 0; power >>= 1) {
      final next = position + power;
      if (next > length) {
        continue;
      }
      debugOpCount++;
      final step = _tree[next] + power * perIndexBias;
      if (step <= remaining) {
        position = next;
        remaining -= step;
      }
    }
    return position;
  }

  /// Resets every value to zero.
  void clear() {
    _tree.fillRange(0, _tree.length, 0.0);
  }
}
