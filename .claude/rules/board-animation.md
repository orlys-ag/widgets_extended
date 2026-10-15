---
paths:
  - "lib/board/_board_animation_coordinator.dart"
  - "lib/board/_track_resize_animator.dart"
  - "lib/board/_item_enter_exit_animator.dart"
  - "lib/board/_item_slide_engine.dart"
  - "lib/board/_make_room_engine.dart"
  - "lib/board/board_animation_style.dart"
---

# board architecture: animation

The contract of `BoardAnimationCoordinator` and its animation sources. The conventions every layer follows are in `board.md`.

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
  decaying under it; refuse-when-off, re-target, a within-tolerance
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
  on the lane axis, which a compose mixing the two kinds drops, and,
  only beside it, a BAND mark saying its extent is an intra-track change
  of the item's lane band, so the sizing term reads that extent too. The
  lead is paint-only; the EXTENT is layout-driving, the geometry rule
  adding it to the item's extent so the child is laid out at the animated
  size),
  `MakeRoomEngine` (HELD offsets from the dry run for every member but
  the session's own item; the session's `lifted` argument discriminates
  move from resize; beside each offset the engine holds a HELD EXTENT
  per id: EVERY dry-run member but the session's item gets the BAND its
  prospective lane count and prospective LANE SPAN would give it minus
  the band it has, so on a FIXED lane axis a neighbour shrinks or widens
  WITH the gap rather than after the drop (on a content-sized lane axis
  a slice is the one lane extent, so a pure prospective LANE-COUNT
  change still creates no entry there, while a prospective SPAN change
  does: the band is the lane extent times the span, and the install loop
  keeps any non-zero target); a RESIZE session's own item holds no
  offset but a LEAD and an EXTENT, deltas over the geometry the render
  gives its STORED span, and on a content-sized lane axis a BAND, the
  change of its lane band while it stays laned in its stored track, or
  a VACATE, the share of that track's term it gives up while it leaves
  it; on the axis of the edge the session drags, which the drag layer
  passes to the install from the session's kind, the LEAD and the EXTENT
  are DIRECT, their `from` written equal to their target so they paint
  it from the install frame on (re-basing and a clock change keep the
  two equal), while on the other axis, which only the item's lanes move,
  they follow the re-target rule and a step of the dragged edge alone
  leaves that axis on the clock it runs on, in step with the neighbours
  it re-lanes; a live install that changed what the item paints with
  nothing left moving dispatches at once, as the snap arm does, and a
  release closes both axes on the clock from where they paint;
  the controller computes their targets through the item-geometry
  rule from the session's SOURCE, its prospective span and the dry run's
  assignment, and the layout re-derives them every frame, the term's
  right after the lane flush and the geometry's after the pass loop,
  over the lattice as it paints, trackResize shifts included, RE-BASING
  each entry onto its new target so it keeps its clock (a missing entry
  is one at rest at zero, and one at rest whose target becomes zero
  goes); either release and a clear of the id end the source, so no
  refresh re-opens a closing hold; extents are installed BEFORE
  the lane-axis gate because an extent needs no lane geometry and
  is the whole of the in-place feedback on a board with none, so the
  block follows the finger while the model stays unwritten, and an
  extent that vanishes without motion (the commit snap) reaches layout
  through the render router's own settle latch for it; beside the offsets
  it holds a prospective lane SLOT for the session's item, the lifted one
  or a resized one the preview lanes in a track it is not laned in,
  paintless, so track sizing can count the lane the drop would occupy,
  with a lifecycle key, naming that session's item, that is non-null
  exactly while a slot exists; the make-room
  contribution reaches the SOURCE track as well as the prospective one,
  because the dry run re-sweeps the stored bucket, and the one term held
  still is the lifted item's own band; an install is IDEMPOTENT for an
  unchanged target, which is what lets a free-snap drag settle at all;
  a live RELEASE is idempotent the same way, so an offset, an extent or
  a slot already closing keeps the schedule it started on, and the drag
  layer's teardown release after a refused hover's release leaves the
  close on the refusal's schedule;
  ONE clock, a curve and a duration, serves every entry, adopted at the
  two declaring sites, and a CHANGED clock first re-bases every entry
  still in motion (its current value becomes its `from`, its clock
  restarts), so no entry is re-read on a curve it never ran on;
  a snap that discards an offset or a slot still mid-motion publishes a
  HAND-OFF, the make-room time the EARLIEST such motion had left and its
  curve's tail, CLAMPED to `[0, 1]`, and bumps the snap generation
  exactly then, so the drag layer and the render continue the discarded
  motion on one clock, and the clamp keeps a motion that was on a later
  clock from being carried past its rest by the renormalisation; a
  commit's snap under a live family leaves another session's CLOSING
  resize hold, its lead, band and vacate and that id's closing extent, on
  its clock, neither folded nor removed, so a commit made inside a
  cancelled resize's close continues only what it discards while that
  hold finishes closing in lockstep; an OWN-PREVIEW SCOPE, an epoch
  `beginOwnPreview` opens and only `endOwnPreview` of that same epoch
  closes, each change of the epoch emptying the per-board JOIN RECORD
  through `_emptyOwnRecord`: while a scope is open every write that
  changes a held offset, band or vacate or a slot (a creation, a
  re-target that writes, a re-base that moves or creates one) JOINS it,
  its pair, `(id, kind)` or a slot's `(track, lane)`, recorded once in
  an open-addressed `_PairTable` over typed buffers kept across scopes,
  with its REMAINDER beside it, the share that entry held for whoever
  wrote it before (its value at a restart, its `from` at a re-base, zero
  for a creation or a snap), a re-target taking the entry's new `from`
  and a recorded pair's decayed remainder from ONE curve evaluation and
  writing that remainder into the record in place, `_retargetOffset` and
  `_retargetSlot` alike, and a lead or an extent never joins; each
  removal from `_held`, `_heldBand`, `_heldVacate` or `_slots` drops its
  pair, so the record holds only standing entries and a toggled
  neighbour never adds a second pair; the reads named `WithoutOwn`
  answer a recorded entry's FOREIGN value, its remainder decaying on the
  entry's own clock, clamped as the value's is and zero when snapped,
  and every other entry whole, and a changed clock first turns a moving
  recorded entry's foreign value into its remainder).
