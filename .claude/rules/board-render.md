---
paths:
  - "lib/board/render_board_viewport.dart"
  - "lib/board/board_render_port.dart"
---

# board architecture: render object

The contract of `RenderBoardViewport`. The conventions every layer follows are in `board.md`.

- **`RenderBoardViewport`** (`render_board_viewport.dart`): the window
  walk widened by the composed animation offset bound; a correction loop
  whose ceiling counts consecutive STAGNANT passes (a pass that measured a
  new track resets it) and honors `applyContentDimensions`' false return
  as another round; a per-cell MEASUREMENT CACHE in the viewport's own
  parent data, so a cell is laid out under measuring constraints only
  when it is newly obtained, when its host's rebuild poked it, when the
  controller's `invalidateCellMeasurements` dropped every mounted cell's
  entry, or when those constraints changed, which is what stops a scroll
  laying every mounted cell out twice; the opt-in
  `debugCheckCellMeasurements` re-measures every cell that USES its cache
  and reports, once per layout and repeating while the staleness stands,
  every one whose extent moved, reading the cache and never writing it,
  and reporting rather than throwing because a throw from inside the pass
  loop strands the children the base's child manager has claimed (the
  content-axis cluster check and the stagnant-pass ceiling report for the
  same reason); a per-track
  CELL RECORD, the tallest cell measured in a content track since the
  record was dropped and which cell it was, so a track keeps the height
  of a cell scrolled out along the other axis, replaced when a pass
  measures that cell again or finds it building nothing while another
  obtained cell of its track builds, removed when it builds nothing and
  no obtained cell of its track builds anything, and dropped with the
  measurements it summarizes (the invalidation door, a controller swap,
  a change of either axis instance or alignment); a NULL CELL
  contributes nothing to its content track, whether the delegate dropped
  its element or its host shows an empty box for the builder's null
  answer, which the host's surface poke writes into the parent data's
  `buildsNothing` before the content-axis test and in both of its arms:
  every obtained cell still feeds its track to the sizing step, a null
  one with the identity of the maximum, and a track none of whose
  obtained cells builds anything takes its record while the recorded
  cell was not among them and the axis's estimate otherwise, the
  lane-cluster and make-room slot terms applying on top as a maximum; a
  per-layout set of vicinities whose builder answered NULL, which the
  delegate's builder reports, because on a delegate rebuild the base
  hands back the child already at such a vicinity until the child
  manager drops it after the sequence, and every read-back inside the
  sequence (`_liveChildFor`) must skip it; a ZOOM ANCHOR, the controller
  and axis configs of the last layout, against which a new axis
  instance under the same controller has the track-space coordinate at
  the scrolled region's leading edge put back there by one `correctBy`
  at the next layout's head, clamped into the new scroll range (a
  controller swap is a new model and anchors nothing); obtain-to-retain retention plus the drag pin's
  per-layout vicinity derivation; PINNED ITEMS: an item whose span
  lies wholly inside a frozen band on an axis (`BoardControllerInternals.pinOfId`,
  the one site of the rule, reading a laned item on the lane axis by its
  one track and asking `bandHolding`, the one site of the interval
  test, which band holds the interval) is laid out where its band's
  cells are and takes no track-resize shift there, and is obtained by four extra span-index
  queries over the bands, a straddler scrolling under the band as before;
  six paint planes (scrolled cells, scrolled items, band cells, band
  items, corner cells, corner items), whose item painted rects are
  computed ONCE per paint into a scratch the clip decision and the paint
  pass share while hit-testing and `itemAt` read live, with hit-testing
  in exact reverse and `applyPaintTransform` mirroring the per-item
  shift; the SEMANTICS walk visits the same planes in paint order, since
  a semantics node's hit-test order is its child list reversed (the
  base's vicinity-sorted chain put a frozen header before the cell
  scrolled under it), and defers to the base's walk after a layout that
  threw, when the lists are the previous sweep's and the base's chain is
  empty; the semantics PAINT clip is the viewport on an axis the child is
  pinned on and the scrolled region on one it scrolls on (null under
  `Clip.none`), so a cell outside the viewport, under a band or slid
  under the corner is flagged hidden, and the semantics clip is the
  viewport grown by the cache region, so such a node is kept rather than
  dropped; `itemAt` probes painted rects (paint offset composed with the
  held shift) down the same planes, stops at a frozen cell that covers
  the point, and excludes exiting and dragged items, and the item
  hit-test walk skips an exiting item the same way, so the pointer
  reaches what lies under it; the enter/exit ramp scales an item's
  extent on the lane axis, or on the PRIMARY axis when there is no lane
  axis; ONE point mapping,
  `_trackCoordinateAt`, one pass per axis that yields the whole sample
  `trackSampleAt` answers: `painted`, the lattice as it paints (a band's
  tracks where the band paints, the scrolled tracks between through the
  animated geometry); `scrolled`, the scrolled tracks' coordinate at the
  point whether or not a band paints over it, bounded by the lattice
  that paints there (`boundedScrolled`: `painted` over the scrolled
  region, never past `painted` toward a band's inner side over it), so
  the gap a short lattice leaves above a trailing band and overscroll
  read no band's track, at the board's scroll offset or one the call
  names, which the sample records; the band the point is
  over, a point past the viewport beside a band included; and
  `visibleFrom` and `visibleTo`, the scrolled coordinates at the bands'
  inner edges, between which a scrolled span SHOWS. Beside the sample
  the pass yields the clamp-free coordinate `cellAt` reads.
  `trackSpaceAt` is the sample's `painted` projection, `frozenCellAt`
  answers where the pass reports a band, and `resolveDropCell` and the
  selection resolve each axis among the cells of the REGION the point
  is over (`regionPathOf`: a band's cells over a band, the scrolled
  cells that show between the bands, or every cell where none of them
  shows), `resolveDropCell` rounding to the
  NEAREST cell as `BoardSnap.track`'s quantize does, so selection and
  every drag honour the bands; `rectOfCell` and `visibleCellRect` share one
  frozen-aware computation; the four visible bounds are the SCROLLED
  tracks showing in `scrolledRegion`, the viewport minus its bands, a
  frozen track being reported by `frozenTracksOf` alone; the stock grid
  painter clips a scrolled track to that region on its own axis;
  `getOffsetToReveal` needs no scroll on an axis where the child is
  pinned (a flag the positioning sweep records on its parent data) and
  otherwise reveals into the unfrozen extent; the correction anchor is
  searched in the unfrozen region and held relative to the leading
  band's end, so a growing header pushes the content down; the
  `controller` setter re-subscribes, resets content-axis
  measurements, drops the new controller's shift prefix with them (an
  axis instance can be shared between two controllers), and leaves the
  retention map alone. The tick router has
  five arms: it composes the coordinator's layout-driving union with
  make-room motion ON A CONTENT-SIZED LANE AXIS and lays out on a
  make-room generation change there, and composes a RELANE slide the same
  way; it lays out on that generation change on ANY axis while a resize
  EXTENT preview stands, and the coordinator's layout-driving union counts
  such a preview only while it MOVES, a settled one being a constant.
  On a FIXED lane axis the router never CLASSIFIES a gap or a relane as
  layout-driving (a gap that displaces a neighbour still lays out through
  the admitted-bound arm). The sizing step's cluster term reads each member's
  LANE BAND: the lane origin plus the two intra-track LEAD numbers paint
  adds to it, its held make-room delta and its relane slide's lead, plus
  the member's STORED span scaled by its ramp, plus the engine's slots.
  It reads no in-flight EXTENT, so a track's edge follows what paints AT
  REST and can lag it while an extent animates on a different clock; a
  cross-track slide carries no relane mark and never reaches the term. It
  records per pass under two latch sets (ramp, make-room contribution),
  with no hand-in for a trackResize in flight (its residual rides under
  the recorded term), and at the hand-off continues the track from where
  it paints whenever the engine's snap generation moved, on the
  remaining clock and curve tail the snap published, recording a natural
  settle's residue instead. The
  ITEM window is widened by the composed offset bound, which folds each
  id's extent delta where an animated trailing edge reaches further than
  its lead, because items are obtained by their STRUCTURAL span.
