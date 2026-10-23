/// Debug counters of the views' work on their entries, which tests set to
/// 0 and read to pin when that work runs. Each note adds one inside an
/// assert, so only a debug build counts.
library;

/// The splits of the shown entries the views have run: the timed grid's
/// into pieces and bars, and Month's into the hours and its bars, each
/// counted once per run. A split a view reuses counts nothing.
int debugEntrySplitCount = 0;

/// Adds one to [debugEntrySplitCount] in a debug build.
void noteEntrySplit() {
  assert(() {
    debugEntrySplitCount++;
    return true;
  }());
}

/// The runs of the timed grid's placement step, which turns its kept split
/// into the board's items.
int debugEntryPlaceCount = 0;

/// Adds one to [debugEntryPlaceCount] in a debug build.
void noteEntryPlace() {
  assert(() {
    debugEntryPlaceCount++;
    return true;
  }());
}

/// The calls of the timed grid's drop gate, and of the landings its
/// crossings read where the cell under the pointer changes and at their
/// release.
int debugDropGateCount = 0;

/// Adds one to [debugDropGateCount] in a debug build.
void noteDropGate() {
  assert(() {
    debugDropGateCount++;
    return true;
  }());
}

/// The timed grid's reads of the cell under a crossing drag's pointer: on
/// a move of it, on a scroll notification, after a frame that moved the
/// rows under it, and at its release. Each counts as it begins, whether or
/// not the pointer has moved yet, so a read that finds no drag counts too.
int debugCellReadCount = 0;

/// Adds one to [debugCellReadCount] in a debug build.
void noteCellRead() {
  assert(() {
    debugCellReadCount++;
    return true;
  }());
}
