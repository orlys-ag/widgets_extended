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
  libraries cannot reach the store's arrays directly.
- **Three notification channels.** Structural changes fire
  `addStructuralListener(Set<TKey>? affectedKeys)` (null = full refresh),
  data-only updates fire `addItemDataListener`, and `addAnimationListener`
  ticks per frame during animations, coalesced to one dispatch per frame
  with an uncoalesced settle carve-out (`notifyNow` clears the pending
  flag; the microtask checks it). The render object's structural handler
  maps non-empty or null `affectedKeys` to
  `markNeedsLayout(withDelegateRebuild: true)`; a data-only update and a
  selection change take a plain relayout there and rebuild only the
  hosts whose own answer changed, through the `Board` state's two relays
  (see `Board` below).
- **Two coordinate spaces.** Content space (distance from the lattice
  origin, per axis) and viewport-paint space (content minus the scroll
  offset, axis-direction aware). `_contentFromPaint` and
  `_paintFromContent` convert POSITIONS; a per-item DELTA (the animation
  coordinator stores its slide leads and make-room offsets in content
  space) converts through `_paintShiftOf`, a per-axis negation under
  reversal that the port also offers as `contentDeltaFromPaint`, so the
  drag layer's hand-off and drop-settle installs never compose the two
  spaces by hand. The port's queries take paint space, the axes speak
  content space.
- **One immutable `BoardAnimationStyle`,** five families over two roots:
  `trackResize` and `itemSlide` are the roots; `itemEnterExit` inherits
  `trackResize` when unset (both animate an EXTENT; reading it as falling
  back to `itemSlide` is the blunder the style doc names), and
  `makeRoom`/`dropSettle` inherit `itemSlide`. A family's zero duration is a kill switch read live at
  every install; per-call durations are captured values the switch
  dominates. Restyling `itemSlide` to zero PURGES in-flight slides and
  fires an empty structural notification when any stood, because a purge
  before a record's first tick leaves the render where the install frame
  left it; restyling `trackResize` to zero FINALIZES each state at its
  target (layout-driving, a dropped state would strand a partial
  extent).
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
- **`BoardSpan` / `BoardPlacement`** (`_board_span.dart`): fractional
  track-space rectangles; spans assert a positive extent.
- **`SpanIndex`** (`_span_index.dart`): per-start-track buckets sorted by
  span-axis start ascending, end descending, id ascending (the id
  tie-break keeps resolves stable). `ordinalOf` is an item's rank among
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
  door. Sub-sources: `TrackResizeAnimator` (refuse-on-zero, re-target,
  `animatedExtentOf`/offset shifts, and a per-track `finalizeTrack`, the
  make-room latch's hand-in door: the sizing step lands a track's
  in-flight resize the moment that track's extent becomes term-driven,
  because while a make-room latch entry stands the animator must hold no
  state for that track), `ItemEnterExitAnimator` (0-to-1
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
  a snap that discards an offset or a slot still mid-motion publishes a
  HAND-OFF, the make-room time that motion had left and its curve's
  tail, and bumps the snap generation exactly then, so the drag layer
  and the render continue the discarded motion on one clock).
- **`BoardController`** (`board_controller.dart`): store + index + lanes +
  coordinator + orchestrator. Mutators fire one structural notification
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
  `cancelInFlight` completing every leg false on detach and dispose.
- **`RenderBoardViewport`** (`render_board_viewport.dart`): the window
  walk widened by the composed animation offset bound; a correction loop
  whose ceiling counts consecutive STAGNANT passes (a pass that measured a
  new track resets it) and honors `applyContentDimensions`' false return
  as another round; obtain-to-retain retention plus the drag pin's
  per-layout vicinity derivation; three paint planes (cells, items,
  frozen) with hit-testing in exact reverse and `applyPaintTransform`
  mirroring the per-item shift; `itemAt` probes painted rects (paint
  offset composed with the held shift) and excludes exiting and dragged
  items; `resolveDropCell` rounds the fractional animated track-space
  coordinate to the NEAREST cell, agreeing with `BoardSnap.track`'s
  quantize; the `controller` setter re-subscribes, resets content-axis
  measurements, and leaves the retention map alone. The tick router has
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
  hands a track's in-flight trackResize in at
  the make-room latch's edge, and at the hand-off installs a
  makeRoom-family resize for a residue past tolerance whenever the
  engine's snap generation moved, on the remaining clock and curve tail
  the snap published, recording a natural settle's residue instead. The
  ITEM window is widened by the composed offset bound, which folds each
  id's extent delta where an animated trailing edge reaches further than
  its lead, because items are obtained by their STRUCTURAL span.
- **`Board`** (`board_widget.dart`): owns the delegate (cached, rebuilt
  only when a builder identity changes, disposed when replaced), the
  per-cell and per-item HOSTS (`_BoardCellHost`, `_BoardItemBuildHost`),
  which show the delegate's builder output as `initial` and re-run the
  builder only when a relay says THEIR answer changed: two relays the
  state owns fan out the selection notifier and the item-data channel,
  deferring a notify made in the build or layout phase to one post-frame
  callback so a write from a builder during a host's self-rebuild cannot
  mark a sibling, hosts read the never-notifying `_BoardScope` with
  `getInheritedWidgetOfExactType`, the cell host's cover test is the
  span index's own `coversCell` (the padded bucket range and admit test,
  called rather than restated), the item host's selection test is the
  selection's intersection with the item's cell range, and the render
  keeps a plain relayout on both channels, for re-measurement and for a
  cell that built null, which holds no host and is re-asked by every
  layout; the drag
  controller's lifetime (`didUpdateWidget` cancels before disposing and
  only rebuilds when controller or config identity changed), the selection
  forwarding listener, the drag-proxy overlay (gated on the SESSION's
  kind through `draggedKind`, never on the target's, so the moved visual
  keeps following the pointer across a `canDropAt`-refused cell, where
  the target is null by design), the config's OPACITY PAIR
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
  default handles: a delayed
  move wrap plus opaque resize strips on the span axis under `resizeEdges`
  and on the primary axis under `primaryResizeEdges`, each handle naming
  its axis (a null axis on a handle or on `startDrag` is the span axis,
  and each axis has its own policy), built-in semantics move
  actions (gated by the SAME drag policy the pointer path applies: the
  host asks `enabled` and `canDrag` ONCE per build and threads the
  answer to both the scope and the actions, and ONE predicate applies
  the exact lattice bounds and `canDropAt` at BUILD, deciding what is
  advertised, and again at ACTIVATION, so a policy that changed its
  answer between the two degrades to a no-op; the `Semantics` wrapper
  is unconditional and its payload is null rather than empty, an empty
  map raising the `customAction` bit for actions that do not exist),
  and the deferred deactivate backstop validated against the key
  the session STARTED with. The host is un-keyed, so a rank shift re-keys
  its widget IN PLACE while the `State` holding the armed recognizer
  survives: the key is therefore CAPTURED when the pointer goes down,
  beside the edge and the axis, and never re-read at the gesture's
  acceptance, which a long-press delay or a contested touch slop later
  would resolve to whatever item the element hosts by then), and `_SelectionLayer` (immediate multi-drag
  for range inside the scrollable, tap for cell; fraction snap quantizes
  then floors). Both the host and the selection layer track the pointer
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
  frame, which the engine's idempotence makes a no-op). A COMMIT releases the make-room preview by
  snap in the same synchronous sequence as the report's mutation
  (snapForCommit), so displaced neighbours never leave the gap they were
  held at, and what the snap discards MID-MOTION is handed on: the drag
  controller captures every held item's painted position through the
  port before the snap and, after the mutation, installs a makeRoom-family
  slide from there to where each now rests, on the clock the engine
  published (the gap's remaining time and its curve's tail) and marked
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
  resize's glide runs from the painted corner captured before the snap,
  carries the item's EXTENT continuation beside it (the painted extent
  captured before the snap minus the painted extent after the mutation,
  both read through `rectOfItem`, which composes the preview and any
  in-flight FLIP, so the continuation cancels the report's own FLIP by
  construction), and composes whenever either half is non-zero; a cancel closes the gap
  by animation. `BoardDropResolver` turns a pointer into a
  span: EVERY move quantizes the ITEM'S PAINTED CORNER, a track snap
  rounding it to the nearest track and a fraction snap to the nearest
  quantum, both endpoint-clamped, so the cells committed are the cells
  the item covers. The one exception is the LANE axis of a LANED item,
  whose painted lead there is a lane origin inside one track rather than
  its span: that axis keeps the cell under the POINTER minus a whole-cell
  grab offset, or a thin chip lying wholly inside a tall row would round
  into the next row the moment its top passed the midpoint. Resizes move
  only the dragged edge, floored at one quantum. `clampStart` and
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
  laned board has by the dozen. The scan steps by the snap's quantum, capped at four
  per direction per axis, orders candidates by content-space distance
  under a TOTAL order so equidistant ones cannot swap between resolves,
  and translates by re-splitting the exact endpoint rather than adding to
  a leading fraction, which a span's own assert forbids. `canDropAt`
  vetoes every candidate the scan proposes, so the board proposes and the
  app disposes; the nudged span becomes the target, so the make-room gap
  previews the landing and the commit reports it. The gather is ONE
  `itemsIn` over the box widened by the radii on BOTH sides of each axis,
  minus the dragged key. `BoardAutoScroller` (internal) integrates
  two-axis edge-zone
  velocities and is evaluated at `startDrag` and per move.
- **`board_views.dart` / `board_config.dart` / `board_background.dart`**:
  the builder view values (`select()` routes through the controller), the
  config and report types, and the geometry-fed background painters.
- **`board.dart`**: the barrel; 39 names by explicit `show`, and anything
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
  frozen bands inset targets by default.
