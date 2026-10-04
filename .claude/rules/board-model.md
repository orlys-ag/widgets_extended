---
paths:
  - "lib/board/_fenwick.dart"
  - "lib/board/_board_axis.dart"
  - "lib/board/_board_span.dart"
  - "lib/board/_span_index.dart"
  - "lib/board/_overlap_lanes.dart"
  - "lib/board/board_controller.dart"
  - "lib/board/_board_controller_internals.dart"
  - "lib/board/_board_store.dart"
  - "lib/board/_board_scroll_orchestrator.dart"
  - "lib/board/board_views.dart"
  - "lib/board/board_config.dart"
  - "lib/board/board_background.dart"
  - "lib/board/board.dart"
---

# board architecture: model layers

The contract of `Fenwick`, the axes, spans and the start rule, `SpanIndex`, `OverlapLaneResolver`, `BoardController`, `BoardScrollOrchestrator`, the view, config and background types, and the barrel. The conventions every layer follows are in `board.md`.

- **`Fenwick`** (`_fenwick.dart`): prefix sums for `LazyContentAxis`'s
  measured deltas.
- **Axes** (`_board_axis.dart`): `BoardAxis` with four implementations
  (`UniformAxis`, `ExplicitAxis`, `DerivedAxis`, `LazyContentAxis`, the
  only one accepting measurements). `minTrackExtent` is strictly positive
  and floored at the read; `BoardAxis.maxTotalExtent` (1e12) is asserted
  per constructor. `BoardAxisConfig` adds `laneExtent`/`lanePadding`,
  frozen bounds, and alignment. At most one axis is content-sized.
  `BoardAxisConfigBands`, an extension beside the config that the barrel
  does not show, is the one site of the BAND RULE: `leadingBandEnd`
  (`frozenStart` clamped into `[0, trackCount]`), `trailingBandStart`
  (never below it, so where the counts overlap the shared tracks are
  the leading band's), `isFrozenTrack`, `frozenTracks`, and the two
  settled extents, read live from the axis. Every consumer reads these
  and never compares `frozenStart` or `frozenEnd` with a track count
  itself: where the counts overlap, a copy without the leading clamp
  counts as trailing the tracks the render object paints as leading.
- **`BoardSpan` / `BoardPlacement`** (`_board_span.dart`): fractional
  track-space rectangles; spans assert a positive extent.
- **The start rule** (`_board_span.dart`): `trackIndexOf`, the floor
  with a start within the tolerance BELOW an integer taken as that
  integer, and `trackEndIndexOf`, its end-side mirror. Every site that
  turns an item's start into a track index reads them, through the
  store's `startIndexOf` and the controller's `startIndexOfId`, and never
  a raw `floor()` or a span's integer component: the span index's
  buckets, the lanes' criterion and buckets, the vicinity row, the pin,
  the laned geometry, the selection's cover and the drag's grab cell
  would otherwise disagree about an item whose start is one ulp below a
  track. `snapToTrackEdge` makes what the board itself produces exact
  (`BoardSnap.quantize`, the drop-fit candidates).
- **`SpanIndex`** (`_span_index.dart`): per-primary-track buckets, filed
  inside the lattice and always at a span's first track, with an overflow
  set for a span's part past the lattice, re-filed by `reconfigure` (all
  of it on a primary-axis change, the tracks between the two counts on a
  track-count change); each bucket sorted by span-axis start ascending,
  end descending, id ascending (the id tie-break keeps resolves stable). `ordinalOf` is an item's rank among
  items sharing its primary start track and is the item vicinity's xIndex
  component (offset past the cell columns); it therefore SHIFTS when an
  earlier-sorting item registers or leaves, which the retention re-key and
  the drag pin absorb by re-deriving vicinities per layout.
- **`OverlapLaneResolver`** (`_overlap_lanes.dart`): one sweep core shared
  by the committed resolve and `resolveDryRun` (the make-room preview's
  prospective assignment). Lanes are resolved before track sizing every
  layout. Each member also gets a LANE SPAN at cluster close, inside that
  same sweep so the two arms cannot disagree: THE RULE is the number of
  consecutive lanes from its own upward that no sweep-axis-overlapping
  cluster member occupies, capped at the cluster's lane count, and lane
  ASSIGNMENT is untouched by it, the expansion only READING what the
  sweep assigned. An exiting item holds its lane RECORD, assignment and
  span alike, whole until settle, while its track-extent contribution
  scales its whole BAND down with its ramp rather than one slice.
- **`BoardController`** (`board_controller.dart`): store + index + lanes +
  coordinator + orchestrator. `itemCount` is O(1): the store keeps an
  exiting count, moved by `setFlag`, the one writer of the flag bits, and
  by `release`, and the live count is its registered keys minus that.
  Mutators fire one structural notification
  each; `markDragging` stores bit 2 with an `onMutationCancel` hook whose
  lifetime is the bit's, and every span mutator touching the dragged key
  cancels the drag BEFORE mutating. The ordered `dispose` script asserts the
  listener lists are empty first (a mounted board still subscribed means
  something is about to read a disposed controller), then runs the
  orchestrator (tickers before the vsync dies), then the animation
  sources.
- **`BoardScrollOrchestrator`** (`_board_scroll_orchestrator.dart`):
  `animateScrollToCell`/`jumpToCell` with per-axis leg supersession, an
  intent generation bumped by every entry and cancellation, a
  user-scroll guard on the settle snap, defined degradation for no port /
  unlaid port (one `endOfFrame` wait) / out-of-lattice targets, and
  `cancelInFlight` completing every leg false on detach and dispose;
  `revealCell` jumps each axis the LEAST that shows a cell between the
  frozen bands, leaving an axis alone where the cell shows or its track
  is frozen, and bumps the intent generation only when it moves. The
  alignment is Flutter's `getOffsetToReveal` convention with the frozen
  bands as pinned extents (the track's own extent comes off the span the
  alignment runs over, so 1.0 is its trailing edge on the region's). A
  leg completes false when a later call takes its axis, `jumpToCell` on
  both, `revealCell` on each it moves, a new animation on its own, and
  when its activity ends short of its target: a driven scroll's future
  completes on DISPOSAL as well as on arrival, so the arrival test, the
  position at the target clamped into the current extents, is what tells
  a landing from a user's drag taking the position.
- **`board_views.dart` / `board_config.dart` / `board_background.dart`**:
  the builder view values (`select()` routes through the controller), the
  config and report types, and the geometry-fed background painters.
- **`board.dart`**: the barrel; the names its explicit `show` clauses list, and anything
  omitted is internal regardless of its name.
