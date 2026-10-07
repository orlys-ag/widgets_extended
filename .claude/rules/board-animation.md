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
  clock from being carried past its rest by the renormalisation).
