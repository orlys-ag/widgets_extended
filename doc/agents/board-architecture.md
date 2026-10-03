# board architecture

Normative reference for `lib/board/`. Claude Code loads this automatically
via `.claude/rules/board.md` when a file in the module is read; other agent
tools reach it from the guidance map in `AGENTS.md`.

## Architecture: board

A two-axis lattice viewport built on `RenderTwoDimensionalViewport`: cells
at every `(row, col)`, items spanning track rectangles, overlap lanes,
animated enter/exit and slides, drag-and-drop moves and resizes, cell and
range selection, frozen tracks, and a paintable background.

### Conventions that cut across every layer

- **Dense item ids.** Every key gets a dense integer id (`BoardStore`, LIFO
  free list; ids are recycled). Per-id state lives in dense typed arrays
  grown in lockstep. A recycled allocation and every release both run
  `clearForId` on the animation coordinator, so a fresh id never carries a
  previous occupant's records. Internal-use id-keyed reads (`idOfKey`,
  `keyOfId`, span/lane reads) exist because the render, views, and drag
  libraries cannot reach the store's arrays directly. They, the drag and
  animation channels, the render object's registration and the debug
  counters are declared in `BoardControllerInternals`, an extension in a
  part file of `board_controller.dart` that the barrel does not show, so
  an app importing the package sees the supported surface only.
- **Three notification channels.** Structural changes fire
  `addStructuralListener(Set<TKey>? affectedKeys)` (null = full refresh),
  data-only updates fire `addItemDataListener`, and `addAnimationListener`
  ticks per frame during animations, coalesced to one dispatch per frame
  with an uncoalesced settle carve-out (`notifyNow` clears the pending
  flag; the microtask checks it); a listener's throw is reported and the
  listeners after it still run, as `ChangeNotifier`'s do. The render
  object's structural handler
  maps non-empty or null `affectedKeys` to
  `markNeedsLayout(withDelegateRebuild: true)`, and an EMPTY set too when
  an item vicinity the last layout built now resolves, through the
  builder's own `itemIdAtOrdinal`, to a different item: the key set
  speaks of items, a removal shifts the later ordinals on its track and
  names nobody, and the base reuses the child already at a vicinity
  unless the delegate rebuilds, which would show the removed item's
  element in its successor's place; a data-only update and a
  selection change rebuild only the hosts whose own answer changed,
  through the `Board` state's two relays, and relayout there only when
  the last layout obtained a cell that built NULL (see `Board` below).
- **Two coordinate spaces.** Content space (distance from the lattice
  origin, per axis) and viewport-paint space (content minus the scroll
  offset, axis-direction aware). `_paintFromContent` and, through the
  normalized space the frozen bands live in, `_normalizedFromPaint` and
  `_paintFromNormalized` convert POSITIONS (a point goes to track space
  through `_trackCoordinateAt`, which knows the bands); a per-item DELTA
  (the animation
  coordinator stores its slide leads and make-room offsets in content
  space) converts through `_paintShiftOf`, a per-axis negation under
  reversal that the port also offers as `contentDeltaFromPaint`, so the
  drag layer's hand-off and drop-settle installs never compose the two
  spaces by hand. A painted RECT becomes a content-space start through
  the port's `leadingCornerOf`, the rect's content-leading corner, which
  is its FAR edge on a reversed axis: the move anchor reads that corner of
  the proxy, and the glides and the hand-off take the lead as
  `contentDeltaFromPaint` of the difference of two rects' leading corners
  and the extent as the difference of their sizes, because a difference
  of painted top-lefts on a reversed axis is the lead difference plus the
  extent difference. The port's queries take paint space, the axes speak
  content space.
- **One immutable `BoardAnimationStyle`,** five families over two roots:
  `trackResize` and `itemSlide` are the roots; `itemEnterExit` inherits
  `trackResize` when unset (both animate an EXTENT; reading it as falling
  back to `itemSlide` is the blunder the style doc names), and
  `makeRoom`/`dropSettle` inherit `itemSlide`. A family's zero duration is a kill switch read live at
  every install; per-call durations are captured values the switch
  dominates. A REFUSED install creates no motion and destroys none: its
  change lands at once, and a slide record or track state already in
  flight keeps running from the new geometry, because both hold a delta
  over the settled geometry rather than a target. Restyling a family to
  zero STOPS, in the setter, every slide record and track state whose
  family the new style resolves to zero and no other, so an explicit
  `dropSettle` survives an `itemSlide` zero and an inheriting one does
  not; a stopped track lands at the settled extent the axis stores, so
  nothing strands, and an empty structural notification follows, because
  a stop before a record's first tick leaves the render where the install
  frame left it. `itemEnterExit` and the make-room engine keep their
  tick-time zero guards.
- **Retention is obtaining.** An exiting item that must outlive the built
  window stays mounted because `_obtainRetained` obtains its vicinity
  every layout: head release (drop entries whose id no longer reports
  exiting), re-key each survivor to its id's CURRENT vicinity (a rank
  insert shifts ordinals mid-exit), obtain, then record every obtained
  exiting id. Release is ceasing to obtain. NOTHING writes
  `parentData.keepAlive`: a child flagged while active lands in the base
  class's children map AND its keep-alive bucket, and `detach` walks both,
  double-detaching into a debug crash. The map is cleared by `dispose`
  only; a controller swap releases entries through the head release
  because the new reader reports none of the old ids exiting, which is why
  `isExitingItem` is total over `int`.

### Core layers (bottom-up)

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
- **`BoardAnimationCoordinator`** (`_board_animation_coordinator.dart`):
  single writer of the enter/exit flag bits; `finalizeEnterExit` is the
  one site that clears bit 0 and frees the id (exactly-one-bit assert,
  delivered/deferred arms); `retireExitNow` is the one synchronous retire
  door; each built id's PRESENCE, the `Animation<double>` a
  `BoardItemView` carries, lives here too: one per incarnation, released
  in `clearForId`, read live, and notified by ONE microtask flush of the
  presences the installers, the enter settle, the release and the
  enter/exit tick marked, so a listener never runs inside a mutation or
  the settle loop and hears a compound change (a mid-enter removal) as
  its end state; `reverseExit` is the RE-ADD door, the tree's cancelled deletion:
  a key added while its exit runs keeps its id, the exiting bit is
  cleared and, under a live itemEnterExit, the entering bit set with an
  enter from the ramp the exit reached (an enter from `from` runs over
  `1 - from` of the duration, the mirror of an exit's scaling), and the
  controller writes a changed span through the ordinary re-span, which
  slides it from where it paints; so no call releases a key's id and
  allocates that key again, and a captured rectangle's KEY alone tells a
  recycled id from its captured item; and the enter/exit clock's settle is where an animated exit's
  survivors re-lane, so it asks the controller to capture their
  rectangles while the id still holds its lane and runs the relane
  install it gets back after the lanes re-resolve and before the
  structural notification. Sub-sources: `TrackResizeAnimator` (a state
  holds a RESIDUAL over the settled extent, not a target, so a settled
  write while one is in flight shows at once and the residual keeps
  decaying under it; refuse-on-zero, re-target, a within-tolerance
  install that drops the standing state, `animatedExtentOf` floored at
  zero, offset shifts answered from a per-axis PREFIX over
  the in-flight tracks, rebuilt lazily per generation or restyle and
  dropped by `invalidateShiftCache` when layout writes a settled extent,
  so a read costs two binary searches inside a layout and outside one
  alike), `ItemEnterExitAnimator` (0-to-1
  clock; an exit starts from the ramp value an interrupted enter reached),
  `ItemSlideEngine` (transient composed RECT deltas, a lead and an
  extent on one clock; installs compose in place, and a record carries a
  RELANE mark saying every lead composed into it was an intra-track shift
  on the lane axis, which a compose mixing the two kinds drops. The lead
  is paint-only; the EXTENT is layout-driving, the geometry rule adding
  it to the item's extent so the child is laid out at the animated size),
  `MakeRoomEngine` (HELD offsets from the dry run; the
  session's `lifted` argument discriminates move from resize, and the
  de-lane arm carries a resized item out of its slice; beside each
  offset the engine holds a HELD EXTENT per id: a RESIZE session's own
  item gets the length its prospective span would give it minus the
  length it has, and EVERY dry-run member but the lifted item gets the
  BAND its prospective lane count and prospective LANE SPAN would give
  it minus the band it has, so on a FIXED lane axis a neighbour shrinks
  or widens WITH the gap rather than after the drop (on a content-sized
  lane axis a slice is the one lane extent, so a pure prospective
  LANE-COUNT change still creates no entry there, while a prospective
  SPAN change does: the band is the lane extent times the span, and the
  install loop keeps any non-zero target); extents are installed BEFORE
  the lane-axis gate because an extent needs no lane geometry and
  is the whole of the in-place feedback on a board with none, so the
  block follows the finger while the model stays unwritten, and an
  extent that vanishes without motion (the commit snap) reaches layout
  through the render router's own settle latch for it; beside the offsets
  it holds a prospective lane SLOT for the lifted item, paintless, so
  track sizing can count the lane the drop would occupy, with a lifecycle
  key that is non-null exactly while a slot exists; the make-room
  contribution reaches the SOURCE track as well as the prospective one,
  because the dry run re-sweeps the stored bucket, and the one term held
  still is the lifted item's own band; an install is IDEMPOTENT for an
  unchanged target, which is what lets a free-snap drag settle at all;
  ONE clock, a curve and a duration, serves every entry, adopted at the
  two declaring sites, and a CHANGED clock first re-bases every entry
  still in motion (its current value becomes its `from`, its clock
  restarts), so no entry is re-read on a curve it never ran on;
  a snap that discards an offset or a slot still mid-motion publishes a
  HAND-OFF, the make-room time the EARLIEST such motion had left and its
  curve's tail, CLAMPED to `[0, 1]`, and bumps the snap generation
  exactly then, so the drag layer and the render continue the discarded
  motion on one clock, and the clamp keeps a motion that was on a later
  clock from being carried past its rest by the renormalisation).
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
  measures that cell again or finds it building nothing, and dropped
  with the measurements it summarizes (the invalidation door, a
  controller swap, a change of either axis instance or alignment); a
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
  one track) is laid out where its band's cells are and takes no
  track-resize shift there, and is obtained by four extra span-index
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
  `_trackCoordinateAt`, reads the lattice as it paints (a band's tracks
  where the band paints, the scrolled tracks between through the
  animated geometry) behind `trackSpaceAt`, `cellAt`, `frozenCellAt` and
  `resolveDropCell`, which rounds its coordinate to the NEAREST cell,
  agreeing with `BoardSnap.track`'s quantize, so selection and every drag
  honour the bands; `rectOfCell` and `visibleCellRect` share one
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
- **`Board`** (`board_widget.dart`): its scroll view overrides the
  base `TwoDimensionalScrollView.build` with a copy that also hands
  `restorationId` to the `TwoDimensionalScrollable`, which the base never
  forwards and which a scope outside the board cannot supply (the
  scrollable's own `RestorationScope` turns restoration off below a null
  id); owns the delegate (cached, rebuilt
  only when a builder identity changes, disposed when replaced), the
  per-cell and per-item HOSTS (`_BoardCellHost`, `_BoardItemBuildHost`),
  which show the delegate's builder output as `initial` and re-run the
  builder only when a relay says THEIR answer changed: two relays the
  state owns fan out the selection notifier and the item-data channel,
  deferring a notify made in the build or layout phase to one post-frame
  callback so a write from a builder during a host's self-rebuild cannot
  mark a sibling, hosts read the never-notifying `_BoardScope` with
  `getInheritedWidgetOfExactType`, the cell host's cover test is the
  span index's own `coversCell` (the padded primary range and admit test,
  called rather than restated), the item host's selection test is the
  selection's intersection with the item's cell range, and the CELL host
  wraps its output in a fresh `_BoardCellSurface` per build, whose
  `updateRenderObject` pokes the render's per-cell measurement cache,
  because a cell laid out tight is its own relayout boundary and its
  rebuild is otherwise invisible below the element layer; the render
  relays out on those two channels only when the last layout obtained a
  cell that built NULL, which holds no host and can be re-asked by
  nothing else, re-measurement having moved to the poke and the
  controller's door; the drag
  controller's lifetime (`didUpdateWidget` cancels before disposing and
  rebuilds it only when the board controller or the config's PRESENCE
  changed; any other new config instance is ASSIGNED to the live drag
  controller, whose setter re-validates a live session against the
  session half of `startDrag`'s gate, and reaches the mounted item hosts
  through `_BoardDragScope`, which carries the two axis directions beside
  the config and notifies on the config's identity or either
  direction), the
  UNCONDITIONAL wrappers (the root `Stack` with its proxy slot, the
  `_SelectionLayer` with no recognizer for a null, disabled or `none`
  config, and the zones and handles described below, so that no runtime
  toggle changes a widget type above a cell or an item), the selection
  forwarding listener, the drag-proxy overlay (gated on the SESSION's
  kind through `draggedKind`, never on the target's, so the moved visual
  keeps following the pointer across a `canDropAt`-refused cell, where
  the target is null by design), the SESSION CURSOR (one unconditional
  `MouseRegion` over the board and the proxy, `grabbing` for a move and
  the resized axis's cursor for a resize, `defer` with no session, so the
  cursor holds wherever the pointer goes), the config's OPACITY PAIR
  (`dragProxyOpacity` on the proxy and `draggedItemOpacity` on the item
  left behind, both applied through `_BoardOpacity`, which pushes a
  layer only while it actually FADES: `RenderOpacity` composites and is
  a repaint boundary at every alpha above zero, and this wrapper sits in
  the tree unconditionally, because one inserted at the lift and removed
  at the drop would re-inflate the item's subtree twice a session and
  drop its `State` both times), `_BoardItemHost` (publishes
  the drag scope, owns the armed recognizer, wraps its child in that
  fade over the drag controller's `movedItem`, comparing
  `widget.itemKey` and NOT the session's captured key, because the
  question here is what THIS element paints, and passing the child
  through, so a session edge rebuilds the wrapper and nothing under it,
  default handles as ONE render object per item, `_RenderBoardHandleZones`,
  present whenever the board has a drag config and inert when default
  handles are off or the item may not drag: a press in an admitted edge
  BAND (`resizeHandleExtent`, 12 px by default, capped at a third of the
  item on that axis) starts a
  resize of that edge, on the span axis under `resizeEdges` and on the
  primary axis under `primaryResizeEdges`, each band placed where its
  CONTENT edge paints (the far side of the item for the leading edge on a
  reversed axis), the primary axis and then the trailing edge taking a
  contested press, and a band hit-tests itself
  and not the item, as an opaque strip on top did, adding a second entry
  whose target is a constant `MouseTrackerAnnotation` with its axis's
  resize cursor (the deepest non-deferring cursor on the path is the one
  shown); a press anywhere else
  starts a delayed move and defers hit-testing to the item (a null axis
  on a handle or on `startDrag` is the span axis, and each axis has its
  own policy), built-in semantics move
  actions (labelled with `WidgetsLocalizations`' four `reorderItem`
  strings, the English defaults with no `Localizations` in scope, and
  gated by the SAME drag policy the pointer path applies: the
  host asks `enabled` and `canDrag` ONCE per build and threads the
  answer to both the scope and the actions, and ONE predicate applies
  the exact lattice bounds and `canDropAt` at BUILD, deciding what is
  advertised, and again at ACTIVATION, so a policy that changed its
  answer between the two degrades to a no-op; the `Semantics` wrapper
  is unconditional and its payload is null rather than empty, an empty
  map raising the `customAction` bit for actions that do not exist),
  and the deferred deactivate backstop validated against the key
  the session STARTED with. Each lattice child is keyed by its item's
  key, the board wrapping its own children rather than the delegate,
  whose `RepaintBoundary` carries no key, so the viewport element finds
  an item's element by key wherever a rank shift, a move to another
  primary track or a column-count change puts its vicinity, and an
  element hosts one item for its life; the key is still CAPTURED when the
  pointer goes down, beside the edge and the axis, and never re-read at
  the gesture's acceptance, as the rule the session follows), and `_SelectionLayer` (range by an
  immediate multi-drag for a precise pointer and a delayed, long-press
  one for touch and unknown-kind pointers, `supportedDevices` keeping
  each pointer to one, so a touch drag over cells is the scrollable's;
  a running range owns a `BoardAutoScroller`, the drag layer's, with the
  layer as ticker provider and the selection config's zone and speed,
  and listens to both scroll positions for its length, re-extending
  from the last pointer as content scrolls under it;
  tap for cell; fraction snap quantizes
  then floors; and the board's one `Focus`, unconditional like the
  detector, on the node `Board.focusNode` gives or the state owns for its
  life: focusable while selection is active or a drag config is present,
  a Tab stop only while selection is active, focused by a cell tap, a
  range press and a drag session's start, whose key handler moves the
  selection by screen direction and reveals the new focus cell through
  `revealCell`, and consumes Escape to cancel a live session, leaving
  every other key to propagate). Both the host and the selection layer track the pointer
  by DELTA from where the gesture began: a multi-drag recognizer accepted
  inside a scrollable reports the accepting move as a delta against the
  initial position, so an update's position alone would drop that move.
- **Drag layer** (`board_drag_controller.dart`, `_board_drop_resolver.dart`,
  `board_drag_handle.dart`): `BoardDragController` runs the session
  (policy chain ending in pin + `markDragging`; single teardown; end order
  resolve-validate, tear down, report, then the drop-settle glide
  installed LAST so it overrides the handler's own slide and the item
  travels from the proxy). Two NARROW listenables sit beside the class's
  own `ChangeNotifier`, which fires per pointer move: `pointerPosition`,
  written per move, and `movedItem`, written at the two session EDGES
  only and null for a resize, which is what a per-item listener can
  afford to watch. `BoardItemView.isDragging` is not that channel and
  cannot be: the lattice item comes from the viewport's delegate, and a
  session edge fires no structural notification, so nothing rebuilds it
  between the lift and the commit, which leaves the flag true only in
  the PROXY's build. `_resolve` re-points the scroll subscriptions
  (bind at start, re-point per sample AND at the autoscroller's tick head,
  unbind in teardown) and nulls the target on a `canDropAt` refusal so no
  gap previews a refused drop. The animation channel is the third route
  into the resolution core: bound at start beside the scroll
  subscriptions and unbound in teardown, and each dispatch schedules ONE
  post-frame re-resolve from the last pointer position, so a track
  resizing above a stationary pointer moves the drop target with the cell
  under it (a free-snap session re-enters the install on every motion
  frame, which the engine's idempotence makes a no-op). The STRUCTURAL
  channel is the fourth, bound and unbound beside it: a board change
  under a parked pointer clears the early-out's record and schedules the
  same one resolve, so the drop gate is re-asked for the placement the
  pointer rests on and a freed placement is accepted, an occupied one
  withdrawn, before the release (the re-send of an unchanged preview it
  can cause costs one layout through the engine's generation, once per
  change). A second pointer landing on a host whose own session runs
  is IGNORED rather than re-arming it, so a second finger never ends the
  drag the first is making. The config's three lifecycle callbacks go
  through ONE FIFO queue on the controller (`_notifyApp`), drained in a
  microtask and synchronously at the top of a pointer release
  (`endDrag(cancel: false)`), so none runs inside a mutation, a build, a
  layout or the finalize, and a target change that shared the release's
  task is heard before the drop's report. Each entry captures its
  callback when queued, and a throw is reported and the drain goes on.
  `onDragStart` is queued in `startDrag` BEFORE the first resolve, so an
  end that resolve's synchronous work causes follows it;
  `onDragTargetChanged` from `_reportTarget`, which compares
  `_currentTarget` with the last one queued (a re-resolve landing on the
  same target queues nothing); `onDragEnd` after teardown in the mutation
  cancel, which therefore runs no config callback between a mutator's id
  reads and its writes, and in `endDrag`'s `finally`, after the report,
  so a report that throws still ends the drag; the board's removal
  cancels through `endDrag` and so queues its end too, while
  `BoardDragController.dispose` alone queues nothing. A predicate or an
  app animation listener can still end the session synchronously inside
  `_resolve` or the commit snap, so `startDrag`, `updateDrag` and
  `endDrag` re-check
  `identical(_session, session)` after those calls and return. Every
  predicate is asked through `askCanDrag` or `askCanDropAt`, which report
  a throw and answer it as a refusal (`askCanDropAt` answers null, which
  also skips the nudge). A COMMIT releases the make-room preview by
  snap in the same synchronous sequence as the report's mutation
  (snapForCommit), so displaced neighbours never leave the gap they were
  held at, and what the snap discards MID-MOTION is handed on: the drag
  controller captures every held item's painted position through the
  port before the snap and, after the mutation, installs a makeRoom-family
  slide from there to where each now rests, on the clock the engine
  published (the gap's remaining time and its curve's tail, clamped) and marked
  RELANE, so a content-sized track holding such a neighbour is
  term-driven on that clock while a track with none takes the sizing
  step's hand-off arm, and the row edge and the content inside it arrive
  together with nothing painted stepping at release; the hand-off
  captures each held neighbour's painted RECT and carries its EXTENT
  continuation beside the lead, so a slice still shrinking at the drop
  finishes on the same clock. The report itself runs inside
  `withoutRelaneSlides`, so the mutation's own re-lane installs neither a
  second LEAD nor a second EXTENT for those neighbours in any door,
  `setItems` included; a committed
  resize's glide runs from the painted rect captured before the snap,
  carries the item's EXTENT continuation beside it (the painted extent
  captured before the snap minus the painted extent after the mutation,
  both read through `rectOfItem`, which composes the preview and any
  in-flight FLIP, so the continuation cancels the report's own FLIP by
  construction), and composes whenever either half is non-zero; a cancel closes the gap
  by animation. `BoardDropResolver` turns a pointer into a
  span: EVERY move quantizes the proxy's content-LEADING corner (see the
  coordinate-spaces entry above), a track snap
  rounding it to the nearest track and a fraction snap to the nearest
  quantum, both endpoint-clamped, so the cells committed are the cells
  the item covers. The one exception, under EVERY snap, is the LANE
  axis of a LANED item, whose painted lead there is a lane origin inside
  one track rather than its span: that axis keeps the cell under the
  POINTER minus a whole-cell grab offset, as a whole track, or a thin
  chip lying wholly inside a tall row would round into the next row the
  moment its top passed the midpoint, and a fine snap would land a
  lane-1 event halfway through its day. Resizes move
  only the dragged edge, floored at one quantum, and move it by the
  pointer's TRACK-SPACE DISPLACEMENT since the lift rather than to the
  pointer, since a press lands inside a handle and not on the edge: a
  press that does not move leaves the span exactly as it was. Track
  space, because a laned item's painted edge on its lane axis is its
  band's, not its span's. `clampStart` and
  `quantumOf` are non-private because the drop-fit search reads the same
  two rules.
  A refusal is where `_board_drop_fit.dart` gets its one chance, and only
  under a `BoardDragConfig.dropFit` policy: when `canDropAt` refuses a
  move, the board slides the placement to the nearest one holding the
  whole box clear. The gate has TWO terms over TWO DIFFERENT
  rectangles, and only the second is configurable: the BOX must MEET an
  occupant, so a refusal for an app rule the board cannot read never
  moves anything, and the free share of the SEARCH REGION, the box
  widened by the radii, must reach `minFreeFraction`. The region and
  not the box, because a box on whole tracks against occupants on whole
  tracks is wholly free or wholly covered and never in between, so a
  box-share threshold is unreachable for a single-cell item; the region
  asks whether the neighbourhood is mostly empty, which every shape can
  answer. That share is CONTENT-SPACE area over the UNION of the
  obstacles, summing them double-counting the overlapping occupants a
  laned board has by the dozen. The scan steps by the snap's quantum,
  and by whole tracks on the lane axis of a laned item, capped at four
  per direction per axis, orders candidates by content-space distance
  under a TOTAL order so equidistant ones cannot swap between resolves,
  and translates by re-splitting the exact endpoint rather than adding to
  a leading fraction, which a span's own assert forbids. `canDropAt`
  vetoes every candidate the scan proposes, so the board proposes and the
  app disposes; the nudged span becomes the target, so the make-room gap
  previews the landing and the commit reports it. The gather is ONE
  `itemsIn` over the box widened by the radii on BOTH sides of each axis,
  minus the dragged key. `BoardAutoScroller` (internal) integrates
  two-axis edge-zone velocities, measured from the port's
  `scrolledRegion` so a pointer over a frozen band scrolls nothing on
  that axis, converts each step to content space through
  `contentDeltaFromPaint`, and is evaluated at `startDrag` and per
  move; it runs only while some axis has room in the content direction
  its velocity drives, stopping its ticker at the extent and restarting
  from the next evaluation, as Flutter's own edge autoscroller does.
- **`board_views.dart` / `board_config.dart` / `board_background.dart`**:
  the builder view values (`select()` routes through the controller), the
  config and report types, and the geometry-fed background painters.
- **`board.dart`**: the barrel; 37 names by explicit `show`, and anything
  omitted is internal regardless of its name.

### Usage patterns

- **Imperative**: create a `BoardController` with a vsync, `addItem`,
  `moveItem`, `resizeItem`, `removeItem`, `setItems`; wrap in `Board` with
  `cellBuilder`/`itemBuilder`.
- **Drag-and-drop**: pass `BoardDragConfig` (the board reports through
  `onItemMoved`/`onItemResized`; the app mutates).
- **Selection**: pass `BoardSelectionConfig`; the controller owns the
  `BoardSelection` value.
- **Scrolling**: `animateScrollToCell`/`jumpToCell` on the controller;
  frozen bands inset targets by default; `revealCell` scrolls only as far
  as a hidden cell needs.
- **Keyboard**: pass a `BoardSelectionConfig`; the board takes focus
  from a tap, Tab or `autofocus`, and `Board.focusNode` lends it the
  app's node.
