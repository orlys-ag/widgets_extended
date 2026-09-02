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
  `markNeedsLayout(withDelegateRebuild: true)`, which is also why a
  data-only update rebuilds every mounted child (accepted for v1).
- **Two coordinate spaces.** Content space (distance from the lattice
  origin, per axis) and viewport-paint space (content minus the scroll
  offset, axis-direction aware). `_contentFromPaint` and
  `_paintFromContent` are the only converters; the port's queries take
  paint space, the axes speak content space.
- **One immutable `BoardAnimationStyle`,** five families over two roots:
  `trackResize` and `itemSlide` are the roots; `itemEnterExit` inherits
  `trackResize` when unset (both animate an EXTENT; reading it as falling
  back to `itemSlide` is the blunder the style doc names), and
  `makeRoom`/`dropSettle` inherit `itemSlide`. A family's zero duration is a kill switch read live at
  every install; per-call durations are captured values the switch
  dominates. Restyling `itemSlide` to zero PURGES in-flight slides
  (paint-only, items land structurally); restyling `trackResize` to zero
  FINALIZES each state at its target (layout-driving, a dropped state
  would strand a partial extent).
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
  layout, and an exiting item holds its lane ASSIGNMENT whole until settle, while
  its track-extent contribution scales down with its ramp.
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
  `ItemSlideEngine` (transient composed paint deltas; installs compose
  in place), `MakeRoomEngine` (HELD offsets from the dry run; the
  session's `lifted` argument discriminates move from resize, and the
  de-lane arm carries a resized item out of its slice; beside the offsets
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
  make-room generation change there, while on a FIXED lane axis it never
  CLASSIFIES make-room motion as layout-driving (a gap that displaces a
  neighbour still lays out through the admitted-bound arm). The sizing
  step's cluster term reads each member's held make-room delta, the
  number paint adds, plus the engine's slots, so a track's edge follows
  what paints; it records per pass under two latch sets (ramp,
  make-room contribution), hands a track's in-flight trackResize in at
  the make-room latch's edge, and at the hand-off installs a
  makeRoom-family resize for a residue past tolerance whenever the
  engine's snap generation moved, on the remaining clock and curve tail
  the snap published, recording a natural settle's residue instead.
- **`Board`** (`board_widget.dart`): owns the delegate (cached, rebuilt
  only when a builder identity changes, disposed when replaced), the drag
  controller's lifetime (`didUpdateWidget` cancels before disposing and
  only rebuilds when controller or config identity changed), the selection
  forwarding listener, the drag-proxy overlay, `_BoardItemHost` (publishes
  the drag scope, owns the armed recognizer, default handles: a delayed
  move wrap plus opaque resize strips on the span axis under `resizeEdges`
  and on the primary axis under `primaryResizeEdges`, each handle naming
  its axis (a null axis on a handle or on `startDrag` is the span axis,
  and each axis has its own policy), built-in semantics move
  actions, and the deferred deactivate backstop validated against the key
  the session STARTED with), and `_SelectionLayer` (immediate multi-drag
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
  travels from the proxy). `_resolve` re-points the scroll subscriptions
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
  published (the gap's remaining time and its curve's tail), while the
  render's sizing step continues each track's residue on that same
  clock, so the row edge and the content inside it arrive together and
  nothing painted steps at release; a committed resize's glide runs from
  the painted corner captured before the snap; a cancel closes the gap
  by animation. `BoardDropResolver` turns a pointer into a
  span: a track-snap move commits the cell UNDER THE POINTER minus a
  whole-cell grab offset (item geometry never enters it), a
  fraction/free move quantizes the item's corner, both endpoint-clamped;
  resizes move only the dragged edge, floored at one quantum. `BoardAutoScroller` (internal) integrates two-axis edge-zone
  velocities and is evaluated at `startDrag` and per move.
- **`board_views.dart` / `board_config.dart` / `board_background.dart`**:
  the builder view values (`select()` routes through the controller), the
  config and report types, and the geometry-fed background painters.
- **`board.dart`**: the barrel; 38 names by explicit `show`, and anything
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
