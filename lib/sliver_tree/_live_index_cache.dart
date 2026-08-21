/// Internal: lazy live-index-in-parent cache backing
/// `TreeController.getIndexInParent`.
///
/// Pure stamp algebra and storage. The controller owns the refresh loop,
/// because a refresh needs both the raw sibling list (NodeStore) and the
/// pending-deletion flags (AnimationCoordinator), neither of which this
/// component knows anything about. That split is what keeps it
/// standalone-testable.
///
/// ## Validity model
///
/// One monotonic [generation]; a per-PARENT stamp recording the generation
/// at which that parent's child list was last refreshed (a scalar serves
/// the root list, which has no nid); and a per-CHILD slot stamp recording
/// the generation at which that nid's cached index was written. A cached
/// answer is trusted only when BOTH stamps equal the current generation.
///
/// The slot stamp is what makes reads self-protecting: a refresh writes
/// slots only for live members actually in the list, so a key whose
/// parent link and sibling list disagree (a transient mid-mutation state)
/// reads -1, and a recycled nid's previous-life slot is stale by
/// construction because every adopt happens inside a mutator that bumps
/// before the next read.
///
/// ## Invariants
///
/// - [generation] starts at 1 and NEVER rewinds. Zero-filled fresh or
///   regrown stamp slots are therefore stale by construction: no init
///   fill pass exists, ever. A rewound generation meeting a surviving
///   stamp is the only way to manufacture a false-valid slot.
/// - [reset] drops every array and zeroes the roots stamp; it does not
///   touch the generation (monotonic covers it).
/// - Mutators bump AFTER their last raw-list write and before
///   notifications (exit placement). Entry-only bumping is unsound: a
///   user comparator can read `getIndexInParent` mid-mutation, and an
///   entry-bumped refresh against a half-mutated list would be trusted
///   after the method returns. With exit placement such a refresh is
///   discarded by the exit bump, so mid-window reads are self-healing.
/// - A NEW raw-sibling-list mutator must add its own exit bump AND join
///   the mutation script in `live_index_oracle_fuzz_test.dart`. That fuzz
///   guards both rules: it interleaves reads with mutations, so a missing
///   or misplaced bump surfaces as a divergence from its independent
///   oracle. A mutator absent from the script is simply unguarded.
library;

import 'dart:typed_data';

/// Sentinel parent nid for the root list, which has no nid of its own.
const int kRootListParentNid = -1;

/// Stamp storage for the live-index cache: no tree knowledge and no
/// refresh logic, just the generation algebra described above.
///
/// Refresh protocol: call [beginRefresh] once for a parent, then
/// [writeSlot] for each live member of that list. Every [readSlot] is
/// then valid until the next [bump] invalidates the whole cache.
class LiveIndexCache {
  /// Monotonic validity generation. Starts at 1 so zero-filled stamp
  /// slots are stale by construction.
  int _generation = 1;

  /// The current validity generation, compared against the parent and
  /// slot stamps to decide whether a cached answer can be trusted.
  int get generation => _generation;

  /// Generation at which the root list was last refreshed. 0 = never.
  int _rootsStamp = 0;

  /// Per-parent-nid generation at which that parent's child list was
  /// last refreshed. Plain `List<int>` rather than a typed list:
  /// generations are unbounded counters and `Int32List` would wrap.
  List<int> _parentStamp = <int>[];

  /// Per-child-nid generation at which [_liveIndex]'s slot was written.
  List<int> _slotStamp = <int>[];

  /// Per-child-nid cached live index. Only meaningful while the slot
  /// stamp matches the current generation; carries no sentinel of its
  /// own.
  Int32List _liveIndex = Int32List(0);

  /// Invalidates every cached list with a single increment. Called by
  /// every mutator after its raw-list writes, and by the pending-deletion
  /// flip forwarders. The library doc's invariants explain why that
  /// placement is load-bearing rather than incidental.
  void bump() {
    _generation++;
  }

  /// Whether [parentNid]'s list ([kRootListParentNid] for roots) was
  /// refreshed at the current generation.
  bool isParentFresh(int parentNid) {
    if (parentNid == kRootListParentNid) {
      return _rootsStamp == _generation;
    }
    return parentNid < _parentStamp.length &&
        _parentStamp[parentNid] == _generation;
  }

  /// Stamps [parentNid]'s list as refreshed at the current generation.
  /// The caller then writes every live member via [writeSlot].
  void beginRefresh(int parentNid) {
    if (parentNid == kRootListParentNid) {
      _rootsStamp = _generation;
    } else {
      _parentStamp[parentNid] = _generation;
    }
  }

  /// Records [liveIndex] for [nid] at the current generation.
  void writeSlot(int nid, int liveIndex) {
    _slotStamp[nid] = _generation;
    _liveIndex[nid] = liveIndex;
  }

  /// Returns [nid]'s cached live index, or -1 when its slot was not
  /// written at the current generation (not a live member of the list
  /// its parent stamp covers).
  int readSlot(int nid) {
    if (nid < 0 || nid >= _slotStamp.length) {
      return -1;
    }
    return _slotStamp[nid] == _generation ? _liveIndex[nid] : -1;
  }

  /// Grows every per-nid array to at least [newCapacity], zero-filled
  /// (zero stamps are stale by the generation invariant). Wired into
  /// `TreeController._onStoreCapacityGrew`, the same lockstep protocol
  /// every other per-nid array uses.
  void resizeForCapacity(int newCapacity) {
    if (newCapacity <= _slotStamp.length) {
      return;
    }
    _parentStamp = _grownCopy(_parentStamp, newCapacity);
    _slotStamp = _grownCopy(_slotStamp, newCapacity);
    final grownIndex = Int32List(newCapacity);
    grownIndex.setRange(0, _liveIndex.length, _liveIndex);
    _liveIndex = grownIndex;
  }

  static List<int> _grownCopy(List<int> source, int capacity) {
    final grown = List<int>.filled(capacity, 0);
    grown.setRange(0, source.length, source);
    return grown;
  }

  /// Drops every array and zeroes the roots stamp. Called from
  /// `TreeController._clear` (which covers `VisibleOrderBuffer.reset`'s
  /// in-place `roots.clear()`, a raw-list write outside the mutating
  /// methods) and transitively from `dispose`. The generation is NOT
  /// rewound: monotonicity plus zero-filled regrowth is what makes stale
  /// slots unforgeable.
  void reset() {
    _parentStamp = <int>[];
    _slotStamp = <int>[];
    _liveIndex = Int32List(0);
    _rootsStamp = 0;
  }
}
