---
paths:
  - "lib/board/board_drag_controller.dart"
  - "lib/board/_board_drop_resolver.dart"
  - "lib/board/board_drag_handle.dart"
  - "lib/board/_board_drop_fit.dart"
  - "lib/board/_board_span.dart"
---

# board architecture: drag layer

The contract of the drag layer. The conventions every layer follows are in `board.md`.

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
  under it (a free-snap move re-enters the install on every motion
  frame, which the engine's idempotence makes a no-op). A RESIZE samples
  the pointer, and re-derives its lift, on the lattice as it would paint
  without the session's OWN make-room preview
  (`trackSampleWithoutOwnPreview`, the sampler the render registers
  beside the port), so the re-resolve moves its target with every change
  to the lattice but that preview's: the preview it installs never moves
  the target it was installed for, until that preview has wholly closed,
  when a scroll it left becomes the board's own and moves the target
  once. That preview is the engine's
  own-preview scope, which `startDrag` opens for a resize on the
  statement after `_session = session` and keeps the epoch of on the
  session, and the teardown ends on the statement after `_session =
  null`, before the release, so a session app code ends inside
  `startDrag` leaves no scope open and one started inside the release's
  dispatch keeps its own. The STRUCTURAL
  channel is the fourth, bound and unbound beside it: a board change
  under a parked pointer clears the early-out's record and schedules the
  same one resolve, so the drop gate is re-asked for the placement the
  pointer rests on and a freed placement is accepted, an occupied one
  withdrawn, before the release (the re-send of an unchanged preview it
  can cause costs one layout through the engine's generation, once per
  change). A RESIZE resolves again only when the sample on its resized
  axis moved past `precisionErrorTolerance` since the last one that
  reached the resolver (`_heldResizeSample`): same band, track count,
  band bounds and visible bounds present, coordinates and scroll offset
  within the tolerance, so a pointer on a snap's tie cannot flip the
  target on rounding alone; the config setter, the structural handler
  and teardown clear it where they clear the early-out's record. Moves
  do not hold. A second pointer landing on a host whose own session runs
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
  construction), and composes whenever either half is non-zero; it is
  marked RELANE, and BAND, only when the item is laned in one lane-axis
  track before and after the report, so the track's term reads an
  intra-track correction, its lead and the change of its band, and never
  one that carries the item into or out of a track, and a move's glide,
  which runs from the proxy, never is; a cancel closes the gap by
  animation. `BoardDropResolver` turns a drag's samples into a
  span, arithmetic on the samples `_resolve` takes once per resolve: the
  pointer's, on the lattice without the session's own preview for a
  resize and through `trackSampleAt` for a move, and for a move the
  proxy's content-LEADING corner's (see the coordinate-spaces entry
  above) and its centre's; a null sample leaves the target unchanged. EVERY move quantizes the
  corner, a track snap rounding it to the nearest track and a fraction
  snap to the nearest quantum, and clamps it into a WINDOW of starts, so
  the cells committed are the cells the item covers. The corner is read
  on a PLACEMENT PATH (`placementPathOf`): the band under the proxy's
  CENTRE when the span fits that band, in the band's starts; else the
  scrolled lattice, in the starts whose span SHOWS between the bands
  (`scrolledWindowOf`, bounded on the axis grid at each band's edge);
  else, where no such start shows, the whole lattice. The centre and
  not the corner, because across a band's edge the aligned placements
  lie on two lattices and rounding one coordinate cannot say which the
  proxy covers more of. BOUNDS narrow every window: `_resolve` asks
  `BoardDragConfig.boundsOf` once per resolve through `askBoundsOf`,
  which reports a throw and answers it as none, and on each axis whose
  range holds the stored span a move's window, the kept axis's and the
  lane axis's too, keeps only the starts the range holds
  (`_boundedPath`), a path holding none falling through as a refused band
  placement does, to the scrolled lattice and then the whole lattice; so
  an item dragged past a bound stops at it, and the drop fit, clamping
  its candidates into these windows, nudges only inside it, its lean
  measured from where the item shows HELD inside the range, or an item
  dragged far past a bound would lean the nudge after it onto the other
  axis. A resize clamps its dragged edge into the range of its axis
  where that range holds the stored span, and the edges where the span
  shows (below) are clamped into it too, so a range scrolled under a band
  wins over showing.
  Whether an axis has moved is measured in the ITEM FIELD, the
  coordinate of the lattice the item paints in (the band's where
  `pinOfId` pins it at this resolve, the scrolled one otherwise): an
  axis whose corner has neither reached a grid line nor travelled half a
  quantum since the lift keeps the stored start, so a lift released in
  place, or a drag along the other axis, changes nothing there, while
  content scrolling under a still finger moves a scrolled item's field.
  THE GUARD, on every board: a moved start beyond where the item was at
  the lift, read in its path's lattice (its stored start where it
  scrolls and the path is the scrolled one, its lift corner
  otherwise), against the direction of travel, is refused; a
  refused band placement falls through to the scrolled path, or to the
  whole lattice where no scrolled start shows, and a refusal there, or
  on any other path, keeps the stored start.
  `startDrag` records the lift samples once, and `_resolve` RE-DERIVES
  one only after an axis-config change alters that axis's track count
  or band bounds, sampling the lift point again at the lift's scroll
  offsets under the new configs. The one
  exception, under EVERY snap, is the LANE axis of a LANED item, whose
  painted lead there is a lane origin inside one track rather than its
  span: that axis keeps the cell under the POINTER, in the region the
  pointer is over, minus a whole-cell grab offset read in the item's
  own lattice at the lift, as a whole track, or a thin chip lying wholly
  inside a tall row would round into the next row the moment its top
  passed the midpoint, and a fine snap would land a lane-1 event halfway
  through its day; it keeps the stored start while the finger is in its
  lift cell, in the lattice it was lifted in. Resizes move only the
  dragged edge, by the pointer's TRACK-SPACE DISPLACEMENT since the lift
  rather than to the pointer, since a press lands inside a handle and
  not on the edge, measured in the item field; until the edge reaches a
  grid line or has travelled half a quantum the span stays as it was,
  the stored span itself, and past that the edge lands on the grid,
  floored at one quantum or at the item's own extent when that is less,
  placed in the band under the pointer when that band holds the held
  edge, unless the lift pressed through that band onto an item that
  scrolls, at a point the band and the item read differently, which is
  then resolved as an item that scrolls; and otherwise in the scrolled
  lattice, or the whole lattice
  where no start of the item's extent shows; a span that pins in a
  band (`bandHolding`) is taken as it is, one that scrolls keeps its
  dragged edge where the span shows, and the GUARD keeps an edge that
  rule would carry back past where it began. Track space, because a
  laned item's painted edge on its lane axis is its band's, not its
  span's. `resolveMove` returns the window and the LEAN of each axis
  beside its target, a kept axis's window being the lattice its stored
  span lies in, narrowed by the bounds. The lean is how far the dragged item shows past the
  target's start, which the snap discarded: on the lane axis of a laned
  item the finger's place across its cell less its place across the cell
  it grabbed, elsewhere the corner's coordinate less the start, and on a
  kept axis the corner's displacement since the lift, each rounded to an
  eighth of the axis's grid so jitter and a sample's rounding on a grid
  line do not change it. `_resolve` records both beside the span for its
  early-out, comparing the lean only after a refusal, the one answer it
  can change, and hands them to the drop fit: over the same refused
  placement a new lean re-runs the fit without asking the gate again,
  and a fit landing on the current target notifies nothing. The windows
  and the paths live in
  `_board_span.dart` beside the start rule, and `quantumOn` is
  non-private because the drop-fit search steps by the grid the windows
  are on.
  A refusal is where `_board_drop_fit.dart` gets its one chance, and only
  under a `BoardDragConfig.dropFit` policy: when `canDropAt` refuses a
  move, the board slides the placement to the nearest one holding the
  whole box clear. A box lying wholly at or past the lattice's end on
  either axis is first moved onto the lattice, before the gate and
  whatever the radii (`ontoLattice`: its start clamped into the window
  `resolveMove` returned for that axis, floored as the resolver floors a
  start, under a track snap and on the whole-track axis, so beside a band
  where a start shows it lands on the last of them rather than in the
  band), since the scan cannot search from it: past the end an axis
  gives the box's start no offset to measure from, and at the end the
  region has no extent on an axis the search does not widen; it is
  taken there when the app admits it, and the nudge searches from it
  otherwise. The gate has TWO terms
  over TWO DIFFERENT
  rectangles, and only the second is configurable: the BOX must MEET an
  occupant, so a refusal for an app rule the board cannot read never
  slides anything, and the free share of the SEARCH REGION, the box
  widened by the radii and CLAMPED into the reach of the window on each
  axis the search steps along,
  joined with the box's own tracks, must reach `minFreeFraction`. The
  region and not the box, because a box on whole tracks against occupants on whole
  tracks is wholly free or wholly covered and never in between, so a
  box-share threshold is unreachable for a single-cell item; the region
  asks whether the neighbourhood is mostly empty, which every shape can
  answer. That share is CONTENT-SPACE area over the UNION of the
  obstacles, summing them double-counting the overlapping occupants a
  laned board has by the dozen. The scan steps by the snap's quantum,
  and by whole tracks on the lane axis of a laned item, capped at four
  per direction per axis, and past the steps, within the radius, takes
  only the FLUSH starts, per obstacle the first start on the box's grid
  at or past its end and the last whose box ends at or before its start
  (on the lane axis counted from the box's own track, zero excluded):
  the nearest clear placement has a flush or own start on each axis, so
  any radius, `double.infinity` included, costs candidates per obstacle
  rather than per step. It orders candidates by content-space distance
  from where the item shows, the refused start plus the lean, read before
  the move onto the lattice and held inside it, so of two placements
  equally far from the snapped start it takes the one the item leans
  toward, under a TOTAL order so equidistant ones cannot swap between resolves,
  clamps a candidate into its axis's window on each axis it steps, so a
  refused span in a band is nudged within the band and a scrolled one
  only to starts that show, and translates by re-splitting the exact
  endpoint on the axes it steps, an unstepped axis keeping the box's own
  fields, rather than adding to a leading fraction, which a span's own
  assert forbids. `canDropAt`
  vetoes every candidate the scan proposes, so the board proposes and the
  app disposes; the nudged span becomes the target, so the make-room gap
  previews the landing and the commit reports it. The gather is ONE
  `itemsIn` over the search region, minus the dragged key: the box
  widened on BOTH sides of each axis and clamped into the windows'
  reach rather than intersected with it, so a box hidden under a band
  further than the radius from the first start that shows still
  gathers the occupants of the start its candidates clamp to. Under
  `clampResizes` a refused RESIZE gets the same one chance
  (`clampedResize`): items the stored span already meets are not in the
  way, the gate is the first term alone over the rest, and the dragged
  edge takes, nearest the refused edge first, the first candidate
  between the stored edge and the refused one that holds the span clear
  and `canDropAt` admits: up to four quanta back, flush against each
  item in the way on the snap's grid, or the stored edge, which is the
  stored span. The radii and `minFreeFraction` govern moves only; the
  gather is one `itemsIn` over the refused span's whole tracks, which
  hold every candidate. `BoardAutoScroller` (internal) integrates
  two-axis edge-zone velocities, measured from the port's
  `scrolledRegion` so a pointer over a frozen band scrolls nothing on
  that axis, converts each step to content space through
  `contentDeltaFromPaint`, and is evaluated at `startDrag` and per
  move; it runs only while some axis has room in the content direction
  its velocity drives, stopping its ticker at the extent and restarting
  from the next evaluation, as Flutter's own edge autoscroller does. A
  session's scroller is built with `holdsLiftZones`, a range's without:
  its first evaluation, the lift's, HOLDS each edge whose zone the
  pointer lies in, and a held edge drives nothing until the pointer has
  moved toward it by more than 4 px from the farthest it has been from
  that edge, a release lasting the session. The pointer's place sets
  each axis's target velocity; the tick drives a SPEED that follows it,
  rising by at most `maxVelocity` per `rampDuration`
  (`autoScrollRampDuration`, assigned to a live session with the zone
  and velocity) and taking a slower target, a reversal or a stop at
  once, and every stop brings both speeds to rest.
