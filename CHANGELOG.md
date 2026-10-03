## 0.0.36

- Added `board`: a two-axis scrolling lattice. `Board` is the widget and
`BoardController` owns the model (`addItem`, `moveItem`, `resizeItem`,
`removeItem`, `setItems`); a `BoardCellBuilder` fills every `(row, col)` cell
and a `BoardItemBuilder` builds items, which span track rectangles and may
cover many cells. `BoardAxisConfig` describes each axis with one of four
kinds: `UniformAxis`, `ExplicitAxis`, `DerivedAxis`, and `LazyContentAxis`,
which measures its tracks from cell content. An axis given a `laneExtent`
becomes the lane axis, where overlapping items stack into lanes instead of
covering each other. Axes can freeze leading and trailing tracks
(`frozenStart`, `frozenEnd`), and `animateScrollToCell` and `jumpToCell`
scroll both axes at once.
- A board cell is re-measured when its host rebuilds: a structural change, a
payload write to an item covering it, or a selection change that reaches it.
A size change the cell's content makes without its HOST rebuilding, an
animating box, an image that resolves late, or a widget that rebuilds on its
own after reading an inherited value, is applied at the host's next rebuild.
This applies only where an axis is `LazyContentAxis`, which is the only kind
measured from content.
- Added `BoardController.invalidateCellMeasurements`, which drops every
mounted cell's cached measurement and schedules one layout that re-measures
each. Call it after changing something the cell builders' widgets consume and
the board cannot observe, a theme or a text scale. It costs one measuring
layout per mounted cell, so it is for the event and not for every frame.
- Added `RenderBoardViewport.debugCheckCellMeasurements`, off by default. With
it on, a layout re-measures every cell whose cached extent it would otherwise
use and reports, once per layout, any whose extent moved; the report repeats
while the staleness stands, because the check heals nothing.
- Added board drag-and-drop through `BoardDragConfig`. The board resolves the
drop and reports it (`onItemMoved`, `onItemResized`); the app mutates.
`BoardSnap` quantizes the target to whole tracks or to a fraction, `canDropAt`
vetoes it, `BoardDropFit` slides a refused move onto nearby free space, and
the items a drop would displace open a make-room gap that previews it.
Dragging near an edge autoscrolls. `BoardDragHandle` and
`BoardDelayedDragHandle` are the built-in handles, `resizeEdges` and
`primaryResizeEdges` choose which edges resize, and `dragProxyOpacity` and
`draggedItemOpacity` (1.0 and 0.5) fade the drag proxy and the item left
behind. `BoardDragController.movedItem` is a `ValueListenable` holding the key
a live move session holds, written at the two session edges only.
- Added board selection through `BoardSelectionConfig`: `BoardSelectionMode.cell`
selects on a tap and `.range` on a drag. The controller holds the current
`BoardSelection`.
- Added board animation timing in one `BoardAnimationStyle` over five families
(`trackResize`, `itemEnterExit`, `itemSlide`, `makeRoom`, `dropSettle`), as
`TreeAnimationStyle` already does for the tree. A family's zero duration is a
kill switch.
- Added `BoardGridPainter` and `BoardBackgroundPainter`, which paint behind the
lattice from its live track geometry (`BoardGeometryView`), frozen bands
included.
- Fix: a new `BoardDragConfig` instance, which an inline config in a parent's
`build` is on every rebuild of that parent, cancelled a live drag and rebuilt
every cell and item. `Board` now assigns it to the drag controller it has
(`BoardDragController.config` gained a setter): a live session carries on under
the new policy, and is cancelled only when `enabled` turns false or a resize
session can no longer be reported or admitted. No cell or item builder runs.
- Fix: toggling `BoardDragConfig.enabled`, the resize policy or
`buildDefaultDragHandles`, or `BoardSelectionConfig.enabled`, its mode or its
presence, re-created every item's or every cell's widgets; the selection
toggles re-created the viewport itself, and toggling `Board.drag` presence
re-created the whole scroll view and reset its scroll offset. All of these now
keep every `State`, except that drag PRESENCE still re-creates each item's
widgets. `BoardDragHandle` stays in the tree while inactive, deferring the
pointer to its child.
- The default drag handles are one zone per item: a press in an admitted edge's
band resizes that edge, anywhere else starts a move after a long press. A band
is 12 px deep as the strips were, but never more than a third of the item, so
an item shorter than 24 px with both edges admitted can be moved again.
- Fix: after the drag controller was torn down mid-session, the next session on
the same key showed the earlier session's content in the drag proxy.
- Fix: on a board axis whose direction is `AxisDirection.up` or
`AxisDirection.left`, a move landed one item-length from where it was dropped,
the default trailing resize handle sat on the item's leading edge, autoscroll
ran away from the finger, the "Move up/down/left/right" semantics actions moved
the item the other way on screen, and a committed resize, or a neighbour the
make-room gap handed off at a commit, stepped by its size change. The drag layer
now reads an item's position from its content-leading corner, which a reversed
axis paints at the item's far edge; `BoardRenderPort.leadingCornerOf` is that
conversion. `BoardResizeEdges` now documents that `leading` and `trailing` are
content edges.
- Board items now pin with frozen bands: an item whose span lies wholly inside
a frozen band on an axis stays with that band as the board scrolls, so a
frozen header row can carry items. An item that crosses a band's edge scrolls
and is covered by the band, as before. A move into or out of a band slides
from where the item painted.
- Fix: a tap on a frozen cell selected, and a drop over a frozen band landed
on, the scrolled cell hidden under the band. `trackSpaceAt`, `cellAt`,
`frozenCellAt` and `resolveDropCell` now map a point through the lattice as it
paints, frozen bands and in-flight track resizes included (`trackSpaceAt` read
the settled geometry before), `rectOfCell` reports a frozen cell where it
paints, and `itemAt` no longer returns an item a frozen cell covers. A
cell-mode tap on empty space past the lattice now selects nothing.
- Fix: `showOnScreen` on a cell hidden under a frozen band left it there; the
board now reveals into the viewport minus its bands, and never scrolls to show
a frozen cell or a pinned item.
- Fix: a frozen header on a content-sized axis that grew slid the first
scrolled row under itself; it now pushes the content down.
- `firstVisibleRow`, `lastVisibleRow`, `firstVisibleCol` and `lastVisibleCol`
now report only the scrolled tracks that show between the frozen bands, and
`BoardGeometryView.scrolledRegion` is that region's rect; frozen tracks come
from `frozenTracksOf` alone. `BoardGridPainter` clips a scrolled track to the
region, so no line or tint of a track hidden under a band shows through it.
- Drag autoscroll zones are measured from the frozen bands' inner edges, and a
pointer over a band no longer autoscrolls on that axis.
- Fix: under a fraction or free snap, moving a laned item wrote a fractional
start on the lane axis (a lane-1 event dropped in place landed at noon of its
day), and a `BoardDropFit` nudge could do the same. A laned item now moves by
whole tracks on its lane axis under every snap, landing on the track under the
finger.
- Fix: an item whose start came to one rounding step below a whole track, as
arithmetic on a fraction can in doubles, was treated as starting in the track
before: `itemsAt` listed it there and two overlapping chips stopped taking
separate lanes. The board now reads such a start as on the track, and
`BoardSnap.quantize` returns an exact whole track where a multiple of its
fraction lands on one.
- Fix: a `trackResize` curve that overshoots (`Curves.easeOutBack`) on a
shrinking content-sized track drove its painted extent below zero and threw a
negative-constraint error. The painted extent is now floored at zero; a
growing track keeps the overshoot.
- Fix: a content-sized track that changed while a track resize was in flight
hid the change until the resize ended and then stepped to it. An item entering
or leaving mid-resize, a measurement a zero `trackResize` family refuses to
animate, and a make-room gap opening on a resizing row now show at once, and
the resize in flight finishes under them. The gap no longer steps the row
when it opens.
- Fix: restyling `itemSlide` to zero stopped a `dropSettle` glide even when
`dropSettle` was set explicitly, and restyling `trackResize` to zero stopped a
drag's make-room continuation. A restyle now stops at once the motion of every
family it turns off, including one left inheriting, and of no other.
- An item move or resize with `duration: Duration.zero`, or under a zero
`itemSlide` family, lands at once and leaves a slide already in flight for the
item running, as the documentation now says.
- Fix: when an animated removal finished, the items that re-laned into its
lane stepped there; they now slide on the `itemSlide` clock.
- Fix: a drag's make-room gap jumped when its clock changed under it: a
cancel after the app restyled `makeRoom` mid-drag re-read the gap on the new
curve, and closed it on the new duration rather than on the one the drag
started with. The gap now closes on the drag's own clock, and a gap whose
clock does change continues from where it painted.
- Fix: under an overshooting `makeRoom` curve, a drop could carry a displaced
neighbour several pixels past where it lands and back. The continuation of a
drop now approaches each item's rest from where it painted and never passes
it.
- Fix: a screen reader's explore-by-touch found the node painted underneath:
the content cell scrolled under a frozen header rather than the header, and a
cell an item covers rather than the item. The board's semantics children are
now in paint order.
- Fix: cells the board builds but does not show, in the cache region outside
the viewport or scrolled under a frozen band, were announced as visible. They
are now kept in the semantics tree flagged hidden, as a list's offscreen rows
are.
- The built-in "Move up/down/left/right" semantics actions now take their
labels from `WidgetsLocalizations`, so they follow the app's locale.
`BoardDragConfig.semanticsActionsBuilder` documents how to add resize
actions, which the board does not build in.
- Added keyboard support to `Board`. With a selection config active, the board
is a Tab stop, a cell tap focuses it, and the arrow keys move the selection by
screen direction; Shift extends a range, Home and End go to the row's ends
(with Control or Meta, the board's), and Page Up and Page Down move by the rows
in view. Each move scrolls only as far as the new cell needs. Escape cancels a
live drag. `Board.focusNode` and `Board.autofocus` are new.
- Added `BoardController.revealCell`, which scrolls the least that shows a
cell between the frozen bands, and not at all when it already shows.
- `addItem`, `moveItem`, `resizeItem` and `setItems` now throw an
`ArgumentError` in release builds too for a span that breaks one of
`BoardSpan`'s rules (a NaN or out-of-range fraction, a negative start, no
extent), and for a start or span above 2147483647, the largest the board
stores, before anything is written. Before, a release build registered the
key and then failed, leaving it on the board in no index, and a start or
span above 2147483647 was stored wrapped.
- `updateItem` with a payload whose key is not the key given throws a
`StateError` in release builds too, where it used to write the wrong payload.
- Fix: inside `runBatch`, an item-data notification was delivered for a key no
longer on the board, removed outright by the batch or by a listener during its
notifications; a key still animating out keeps it.
- Fix: in debug builds, the report of an intra-track item cluster on a
content-sized axis missed an item starting within a rounding step below a
track, and checked each measured track by walking every item on the board. It
now places such a start on that track, as the rest of the board does, and
reads only that track's items.
- Perf: an item spanning far more tracks than the lattice cost time and memory
per track it spanned; it now costs at most one per lattice track it covers, and
one for an item starting past the lattice.
- Fix: `UniformAxis.trackAt` threw for an infinite or NaN offset; it now clamps
as the other axes do. `DerivedAxis.extentOf` returns the extent the callback
gave, where it could round below it and below `minTrackExtent`.
- Fix: a structural listener that removed and re-added an item while
`removeItem` notified could make the re-added item slide in from where the
removed one had been. `removeItem` now installs its neighbours' slides before
it notifies.
- Fix: inside `runBatch`, a mutation after a `setItems` could miss a neighbour
it re-laned, which then stepped to its new lane instead of sliding.
- Fix: on a board with no lane axis, an item entering or leaving showed
nothing for the whole `itemEnterExit` animation and then popped. It now grows
and shrinks along the primary axis, as an item on a laned board does along the
lane axis.
- Fix: an item animating out still took taps. The pointer now reaches what lies
under it, as `itemAt` already did.
- `BoardSelectionConfig.onChanged` now documents that it is called for every
change of the selection, a programmatic `setSelection` included.
- Fix: an item lost its widget `State` when another item was added or removed
before it on the same row, when it moved to another row, and when the column
count changed. Each item's child is now keyed by the item, so its `State` follows
it; an item no longer needs a `GlobalKey` in its content for that.
- Fix: adding a key back while its exit was still running made the exiting item
vanish and a new one grow from nothing. `addItem` and `setItems` now reverse the
exit: the same item grows back from where it had shrunk to, at the pace of a full
enter, and slides to a new span if it was given one.
- Fix: removing an item that came before another on the same row, or letting its
exit finish, left the removed item's widget showing in the other item's place and
unmounted the other item's widget, cancelling a drag of it. The board now rebuilds
whenever a removal moves an item into a place built for another.
- Fix: a resize moved the dragged edge to the pointer, so pressing a resize handle
a few pixels inside the edge and releasing resized the item under a free or fine
snap. The edge now moves by how far the pointer moves.
- Fix: a second finger on an item being dragged cancelled the drag. It is now
ignored.
- Fix: dragging into an edge zone with the board already scrolled to its end kept
requesting a frame every vsync. Autoscroll now stops at the end and resumes when
the pointer moves.
- Fix: a drop target that `canDropAt` refused stayed refused while the pointer
rested on it, even after the board changed to allow it, and one it accepted stayed
accepted after the board changed to refuse it. A board change during a drag now
asks `canDropAt` again.
- Fix: `animateScrollToCell`'s `rowAlignment` and `colAlignment` now follow
`Scrollable.ensureVisible`: 1.0 puts the cell's trailing edge on the viewport's
trailing edge (it used to put the cell's leading edge there, leaving the cell off
screen) and 0.5 centres the cell. 0.0, the default, is unchanged. With
`avoidFrozenTracks` the alignment is inside the region between the frozen bands.
- Fix: `animateScrollToCell` completed true when a later `jumpToCell` or
`revealCell`, or the user scrolling, took the position before it arrived. It now
completes false then, as its documentation says.
- Fix: when `frozenStart` and `frozenEnd` together exceed an axis's track count,
`animateScrollToCell` with `avoidFrozenTracks` counted the tracks the two bands
share in its trailing inset, so with a non-zero alignment it scrolled to a
different offset. The shared tracks now count only in the leading band, as the
board paints them.
- Fix: assigning `BoardController.rows` or `columns` a new config that wraps the
same content-sized axis with the same lane settings discarded every measurement,
and a scrolled board jumped to other rows. The measurements are now kept unless
the axis or its lane geometry changed.
- Fix: a content-sized row took the height of its tallest cell in view, so it
shrank when that cell scrolled out sideways and everything below it moved. It now
keeps the height of the tallest cell measured in it until that cell is measured
again or `invalidateCellMeasurements` is called.
- Fix: in debug builds, an item lying within one track of a content-sized axis
with no lane axis threw from inside layout, and every later layout failed even
after the item was removed. The error is now reported once per layout and the
board recovers when the item goes.
- Fix: a cell or item whose builder started returning null failed the next paint
with a framework assertion. The board now drops it cleanly.
- Fix: with range selection on (the default mode), a touch drag over the cells
selected a range instead of scrolling the board. Touch now starts a range after a
long press; a mouse, stylus or trackpad still starts one as soon as it moves.
- `BoardController.laneOf`, `laneCountOf` and `laneSpanOf` return null for a key
that is not on the board, as `spanOf` and `itemOf` do; they used to return the
values of an unlaned item, 0, 1 and 1, which a real lane 0 could not be told
from.
- Added `BoardController.itemCount` (constant time) and `BoardController.keys`,
which count and list the items on the board, not counting those animating out.
- Fix: a key repeated inside one `setItems` call was refused with the message for
a key already on the board, which advised `updateItem`; it now says the key
appears more than once in the placements.
- `addItem`, `moveItem` and `setItems` now document that a span outside the grid
is kept, and shown once the grid covers it.
- `BoardController`'s internal members, the id-keyed reads, the drag and animation
channels, the render object's registration and the debug counters, moved to the
`BoardControllerInternals` extension, which the package does not export, so they
no longer appear beside the supported API. `BoardAnimationReader` is no longer
exported.
- The README has a `Board` section with a quick start, and every public board
config field and enum value is documented.
- `Board` passes `scrollCacheExtent`, `dragStartBehavior`,
`keyboardDismissBehavior` and `hitTestBehavior` through to its scroll view.
- `BoardDragConfig.dragStartDelay` sets the default handle's long press, and
`BoardDelayedDragHandle.delay` a delayed handle's; `resizeHandleExtent` sets how
deep the default resize strips reach.
- `BoardDragConfig.onDragStart`, `onDragTargetChanged` and `onDragEnd` report a
drag's lifecycle: its start and kind, each change of its drop target (for a live
label), and its end, committed or not. They are delivered after the board call
that caused them has returned, in a microtask or at the start of a pointer
release, and never inside a controller mutation, a build or the frame's
finalize, so a handler may mutate the board and call `setState`.
- A mouse over an item's resize strip shows a resize cursor, and a drag shows its
cursor, grabbing for a move and the resize cursor for a resize, until it ends.
- A range selection dragged to the edge of the board scrolls it and extends the
range as the cells arrive; `BoardSelectionConfig.autoScrollEdgeZone` and
`autoScrollMaxVelocity` tune it as the drag config's do.
- Assigning `BoardController.rows` or `columns` a new axis, to zoom for instance,
keeps the row or column at the leading edge of the scrolled area where it was,
instead of keeping the pixel offset and showing other rows.
- `BoardItemView.presence` hands an item builder the item's enter/exit ramp as
an `Animation<double>`: `forward` while it enters, `reverse` while it leaves,
`completed` at rest and `dismissed` once it has gone, so a `FadeTransition` or
any other transition can run with the board's own growth. Every build of one
item hands the same object. `BoardItemView`'s constructor takes it as a new
required argument.
- `Board.restorationId` restores the board's two scroll offsets after an app
restart, as a `ListView`'s `restorationId` does. `TwoDimensionalScrollView`
does not forward one to its scrollable, so the board's scroll view now builds
the scrollable itself.
- `BoardDragController` is no longer exported. `Board` builds its own and no
app could reach it; `BoardDragConfig`'s `onDragStart`, `onDragTargetChanged`
and `onDragEnd` are how an app follows a drag. `BoardDragKind` and
`BoardDropTarget`, which those callbacks carry, stay exported.
- `BoardController.animateTrackResize`, an internal-use channel, no longer
takes a target extent: it reads the one the axis stores. The internal-use
`BoardController.finalizeTrackResize` is removed.
- Fix: a sticky header retiring by push-up painted above the tree sliver's own
paint origin with no clip, so it was drawn over whatever sat above the scroll
view: a tree short enough to fit its viewport declares no visual overflow, so
the viewport pushes no clip either. The header is now clipped to the sliver's
paint region at the top as it already was at the bottom, and the 0.0.35
no-clip fast path still applies to settled headers.

## 0.0.35

- **BREAKING** `AnimationState` gains a required `family` field
(`TreeAnimationFamily`, newly exported): the animation family whose style
spec times the state, declared at the install site. External constructions
of `AnimationState` must now pass it; states obtained from
`TreeController.getAnimationState` simply carry the new field.
- Added `avoidStickyHeaders` to `TreeController.animateScrollToKey`. When
true, the target lands just below the sticky band its own pinned ancestors
will form after the scroll instead of under it, and alignment works against
the viewport minus that band (bottom alignment is unchanged); the default,
false, keeps today's landings. `TreeController.stickyInsetOf` exposes the same
settled-extent inset for callers composing their own scroll math, and
`maxStickyDepthAcrossHosts` reports the largest `maxStickyDepth` among the
attached slivers.
- Changed: a pinned sticky header is no longer clipped to its own box when
the clip would cut nothing (the header is neither clamped by the paint region
nor mid-extent-animation). A header row whose child paints outside its box (a
shadow, an overflowing badge) now shows that overflow while pinned, matching
how the same row paints in flow; an app that relied on the pinned clip to
contain overflow should clip inside its own row widget.
- Fix: every reorderable row was wrapped in `Opacity(1.0)`, whose render
object is a compositing boundary at any alpha above zero, so each visible row
carried its own `OpacityLayer` on top of the package's `RepaintBoundary` and
`addRepaintBoundaries: false` could not remove it. The hide is now a
`Visibility` (size, state and animation maintained), which adds no layer and
also excludes focus while hidden: a focused field in the dragged row no
longer keeps primary focus while invisible.
- Changed: while the drag preview is shown (`showDragProxy: true`, the
default, or a `dragProxyBuilder`), the dragged subtree's in-place rows are
sized placeholders for the drag instead of hidden live copies, so row content
is inflated exactly once. Row `State` inside the dragged subtree is recreated
at lift and at drop unless the row content carries a `GlobalKey`, which now
migrates the element intact. A `GlobalKey` inside a row previously broke the
lift with a layout-phase assertion.
- Fix: a drag started on a sticky-pinned header resolved its drop target
against the content scrolled beneath the pinned strip. The drop probe now
consults the pinned band first, matching hit-testing, so the header itself is
the target while the pointer stays inside its band.
- Fix: standalone animations spawned by expand/collapse mutators (partial
reversals, nested-subtree exits, bulk continuations) ran on the `enterExit`
family's timing while the mutator's own kill switch read `expandCollapse`.
Each install site now declares its family and the standalone ticker resolves
the declared family through the live style, so restyling either family at
runtime retimes exactly its own in-flight states.
- Fix: measuring rows above the viewport shifted the content under the user by
the estimate-versus-measured residual, and `animateScrollToKey` landed off by
it. Layout now emits an anchor-preserving `scrollOffsetCorrection` for that
residual and `animateScrollToKey` snaps to the settled offset after the frame.
- Fix: a row taller than the cache extent left a viewport-sized hole below it,
because layout admission charged the leading row's out-of-window part against
the cache budget.
- Fix: `animateScrollToKey` issued right after a mutation (`insertRoot`,
`expand`) clamped to the pre-layout `maxScrollExtent` and rode its whole
duration to the wrong place. It now waits one frame for stale geometry and
follows in-flight tree animations to settled geometry.
- Fix: a superseded `animateScrollToKey` reported true while the position landed
elsewhere. Every scroll the controller starts is now single-flight in both
directions; a cancelled scroll resolves false.
- Fix: `expandAll(maxDepth:)` and `collapseAll(maxDepth:)` acted on group
direction instead of post-flip visibility, growing rows back under parents
that stayed collapsed or dragging still-visible rows to zero;
`collapseAll(maxDepth: 0, animate: false)` no longer empties the order.
- Fix: `expandAll` or `collapseAll` reversing an in-flight group re-targeted the
rows' animation envelopes without rebasing them, so the surviving rows popped
at the reversal. All four reversal sites now capture each row's painted extent
first.
- Fix: a row resized while a reversal was collapsing it (`collapse` during its
own `expand`, or `collapseAll`) jumped up to its new height mid-collapse; the
captured extent now stays the terminus.
- Fix: `expand` reversing an in-flight collapse left the animation caches stale
until the group completed, so the reversed rows were not treated as animating.
- Fix: an `expand` or `collapse` whose members were all pending deletion still
ran an empty animation group for a full duration (render cache off, one forced
layout per frame).
- Fix: `expand(animate: false)` during that subtree's collapse spliced the new
descendants as one block after the parent, misordering them against the
children still in the order.
- Fix: re-inserting a mid-exit node under a collapsed parent left a permanent
visible row.
- Fix: re-inserting an existing key under a comparator placed it one slot to the
right of its sorted position.
- Fix: a same-parent relocation notified only the moved key, so displaced
siblings kept stale positional inputs.
- Fix: `moveNode` to a different depth left rows collapsed earlier in the same
handler rendering at their pre-move depth.
- Fix: an inherited-widget read inside `nodeBuilder` (`Theme.of`) never
refreshed mounted rows when the inherited value changed.
- Fix: moving a `GlobalKey`-carrying widget out of a row dropped the row's
render box twice, once by the element and once by the framework.
- Fix: `syncRoots` computed root insert indices before its deferred removals, so
an exiting root was teleported to the bottom by the final reorder. Root
removals are now eager except for a root whose subtree holds a node moving
elsewhere.
- Fix: `syncRoots` purged a node moving out of a removed intermediate root
instead of deferring that removal until after the move.
- Fix: during bulk `expandAll`/`collapseAll` frames the sliver under-reported
its paint extent from stale per-row slots, rejecting taps below it and letting
a following sliver paint inside the tree.
- Fix: rows after the collapsing subtree were never admitted to layout during a
bulk `collapseAll`.
- Fix: the drop-target lookup over a slot the make-room preview had closed
resolved to the hidden dragged row instead of the row painted there.
- Fix: a settled exit ghost stayed painted and pinned for the whole of a drag
while a make-room preview was held.
- Fix: a settled edge ghost under a held make-room preview was painted by
neither paint pass, vanishing until the next layout.
- Fix: an exit-ghost anchor was painted twice per frame, the second paint
replacing the first's placement (no horizontal slide, wrong clip and z-order).
- Fix: a row sliding into a collapsed on-screen parent reported its stale
pre-move slot to `localToGlobal`, semantics and focus traversal for the
slide's duration.
- Perf: the bulk-only layout fast path fell off on every frame because its
per-row extent estimate never matched the measurement; the estimate is now the
measurement's own product form.
- Perf: K inserts under one parent inside `runBatch` built the sibling refresh
set K times (O(K * S)); it is built once per parent at batch exit.
- Perf: `syncChildren` no longer performs an O(N) list insert per inserted key.
- Changed: re-adding a mid-exit node with default flags restores the node, not
its in-flight subtree, matching `remove(animate: false)` followed by a fresh
add. Pass `preservePendingSubtreeState: true` to restore the subtree (the
declarative sync layers already do).
- Fix: a drag whose scrollable swapped its `ScrollPosition` mid-drag (the
`physics: isDragging ? const NeverScrollableScrollPhysics() : ...` pattern
does this on the first drag notification) stopped re-resolving the drop target
on external scrolls, because the session's listener stayed on the old
position. The subscription now follows the live position on every pointer
sample and autoscroll tick, and the new
`TreeReorderController.notifyScrollableChanged` (called by
`SliverReorderableTree` from the dragged row's `didChangeDependencies`)
re-binds it in the swap's own frame.
- Fix: under a `SliverPadding` (or any sliver that insets the tree in the cross
axis) the drag proxy spanned the whole viewport instead of the tree's band,
the x-aware drop resolution read the pointer offset by the inset, and the card
jumped by the inset at release. `ReorderRenderPort` gains
`crossAxisGlobalOrigin` and `crossAxisExtent`, which the proxy band and the
depth hint now use; `dragProxyBuilder`'s documented content width is
`sliverCrossAxisExtent - indent` (identical numbers for an unpadded tree).
- Fix: hot reload left mounted rows rendering the old `nodeBuilder` output
whenever an ancestor handed the same `SliverTree` instance down (the `child`
pass-through of `AnimatedBuilder`, `ValueListenableBuilder` and
`AnimatedTheme`), and when the ancestor built a fresh instance the reload
re-inflated every row, discarding row `State`. Rows now refresh in place on
every reload in both shapes and keep their `State`.

## 0.0.34

- **BREAKING** `SectionedListController.addItem` and `setItems` now throw
`ArgumentError` for an item key that belongs to another section, instead of
silently moving the item out of it. Use `moveItem` to move an item between
sections; re-adding an item to its own section is unchanged.
- **BREAKING** `SectionedListController.addSection` now throws `ArgumentError`
for a section key that already exists, and validates `items` before mutating,
so a rejected call no longer leaves an empty section behind. Re-adding a
section that is animating out still cancels its removal.
- Fix: a downward drag onto a collapsed or leaf row committed the node as that
row's sibling instead of into it. The probe was landing in the gap the
make-room preview had just opened and re-resolving against the row below it.
- Fix: starting or moving a drag between a structural mutation and the next
frame could throw a `RangeError` or report another row's geometry, because the
row lookup read layout caches the mutation had invalidated.
- Fix: `animateScrollToKey` with `AncestorExpansionMode.animated` kept driving
a disposed `ScrollPosition` when the scrollable was rebuilt mid-scroll, which
asserted in debug and silently abandoned the scroll in release.
- Fix: three defects in `TreeSyncController`'s expansion memory let a sync
override the user's expand or collapse across a remove and re-add: a
descendant hidden under a collapsed ancestor lost its entry, a root re-added
without children was never restored once they arrived, and a second removal
while childless overwrote the remembered state.
- Fix: `SectionedSliverList` ignored `preserveExpansion`, because every sync
re-applied the initial-expansion policy to re-added sections. Sections now
come back as the user left them, matching `SyncedSliverTree`; pass
`preserveExpansion: false` for the old behavior.
- Fix: `TreeSyncController.syncMultipleChildren` destroyed a moved node's own
children when `animate` was false and the node's old parent was removed in the
same call.
- Fix: `SectionedListController.moveItem` brought back an item that was
animating out when given a `toSection`; the in-section form already refused.
- Fix: `SectionedListController.moveItem(toSection:)` with no `index` did
nothing when the item was already in that section, instead of appending it as
documented.
- Fix: disposing a `TreeReorderController` mid-drag and rebuilding with a new
one left the dragged row invisible and its drag proxy stuck in the overlay.
- Fix: the dragged row's hidden copy was still hit-testable, so a second finger
landing on it could cancel the drag or fire that row's tap handlers. Every
other row stays interactive.
- Fix: dragging a subtree taller than the scrollable's cache extent left blank
space where the make-room preview had shifted rows into view. Re-targeting the
gap now costs one layout, independent of frame rate.
- Perf: a batch of K animated mutations took K full visible-order snapshots to
stage one slide baseline. Measured on 4000 rows with 400 batched moves, 465ms
to 176ms.
- Perf: a drag suspended stale-row eviction for its whole duration, so every
row an autoscroll drag passed stayed mounted until the drop. Measured on 2000
rows over 200 frames, 143 mounted rows to 25 against a steady state of 18.
- Perf: scrolling inside a subtree whose sticky header is pinned rebuilt a
prefix sum over every visible row on each frame, because the header's own row
is mounted from outside the cache region.
- Added `SectionedListController.rememberedSectionKeys()`, the section keys
whose expansion state is held for a re-add. It replaces the undocumented
`debugSnapshotRememberedSectionKeys()`.

## 0.0.33

- Fix: removing a visible row that had never been laid out collapsed its
extent in one frame instead of animating out. The exit now starts from the
same estimate fallback the collapse path uses.
- Fix: a sticky header pinned while ENTERING snapped to full height instead of
growing in. The band takes the animated extent while entering; exiting stays
on the settled extent so the header retires by push-up.
- Fix: an entering root that took the sticky band over at a scrolled offset
popped in flush at the band top instead of sliding down into it.
- Fix: the pinned header vanished or mispositioned for the whole duration of
an `expandAll` / `collapseAll` that moved the offsets of a pinned section
whose header row sits outside the cache region.
- Fix: the sticky band went blank for the whole duration of a diff that added
or removed a depth-0 root. Animation membership no longer affects candidate
eligibility, and the 1-in-3 recompute throttle and the paint-time skip for
exiting headers are gone with it.
- Fix: a row that was both sticky and an exit-ghost anchor was painted by
neither pass while exiting; the sticky pass now paints exiting headers.
- Perf: sticky headers take one candidate walk per layout instead of two
(`identifyPotentialStickyNodes` and `computeStickyHeaders` are merged).
- Added `RenderSliverTree.debugLastPaintedStickyKeys`, the keys the sticky
paint pass actually painted this frame; assert-guarded.
- Fix: `TreeController.remove` did not flush a deferred visible-order rebuild
before reading the order, so inside `runBatch` its animated-versus-immediate
path gate read stale state. Only batched sequences were affected.
- Perf: the floating drag proxy is built once per drag session and
repositioned as a retained subtree instead of rebuilding on every pointer
move. Proxy content that self-drives motion or drag-state reactivity still
works, since the subtree stays mounted for the whole session.
- Fix: rebuilding `SliverReorderableTree` with a different
`TreeReorderController` mid-drag stranded the session, leaving rows shifted
and leaking its eviction pin, scroll listener and autoscroll ticker.
- Fix: a `TreeSyncController.syncRoots(childrenOf:)` that throws during
desired-tree validation left the internal desired-descendants set populated,
silently skipping removals in every later `syncChildren`.
- **BREAKING** `SyncedSliverTree.flat` now throws `ArgumentError` when
`parentOf` returns a key absent from `items`, listing every offending
(child, parent) pair; such items used to be silently treated as roots.
Returning null from `parentOf` is the explicit way to make an item a root.
- **BREAKING** `preserveExpansion` and `maxExpansionMemorySize` merge into one
`expansionMemory` parameter on `TreeSyncController` and all three
`SyncedSliverTree` constructors: the maximum number of removed nodes whose
expansion state is remembered for restore on re-add, 0 disabling the memory
entirely (default `TreeSyncController.defaultExpansionMemory`, 1024).

  Migration: `preserveExpansion: false` becomes `expansionMemory: 0`,
  `maxExpansionMemorySize: N` becomes `expansionMemory: N`, and both set
  becomes `expansionMemory: preserveExpansion ? N : 0`.
  `SectionedSliverList.preserveExpansion` and
  `SectionedListController.preserveExpansion` are unchanged.
- Added `TreeReorderConfig.enabled` (default true), the tree-wide runtime
reorder toggle: it disarms every handle, withdraws the reorder semantics
actions, refuses programmatic `TreeReorderController.moveTo`, and ends a drag
already in flight, with no change to any row's widget shape. It dominates
`canReorder`, which stays the per-row policy.
- **BREAKING** `SliverReorderableTree.indentPerDepth` and
`TreeReorderConfig.indentPerDepth` are renamed `indentWidth`, matching the
`TreeController` / `SyncedSliverTree` name for the same constant;
`SliverReorderableTree.indentWidth` is now `double?` defaulting to null, which
resolves to `TreeController.indentWidth` at drag start instead of a hardcoded
24.0. Behavior note: a tree rendering with the controller's default
`indentWidth: 0` no longer gets a phantom 24 px hint column, so pass
`indentWidth: 24.0` to keep the old mapping.
- Fix: the drag tunings (`autoExpandDelay`, `autoScrollEdgeZone`,
`autoScrollMaxVelocity`) on `TreeReorderConfig` / `SectionedReorderConfig` are
now live on rebuild instead of read once at construction. Each value is
captured per drag session, so a change applies from the next drag.
- Fix: dragging an EXPANDED parent now carries its whole visible subtree: the
in-place rows all hide, the proxy stacks a clone per visible descendant
(frozen at lift, drawing capped at one viewport), and all three settle glide
paths carry every subtree row. A custom `dragProxyBuilder` still styles only
the dragged row's portion.
- Fix: cross-depth drags are now seamless horizontally as well as vertically:
the proxy carries an animated left padding toward the drop target's column,
and every settle glide starts at the proxy's instantaneous visual cross offset
instead of a structural x. Internal:
`ReorderRenderPort.beginSlideBaseline` takes `baselineOverrides`, and
`startDrag` gained an optional `proxyCrossOffset` closure.
- **BREAKING** removed the `SyncedSliverTree.nodes` and `.snapshot`
constructors and `TreeSnapshot`; the three remaining input modes cover the
same ground. `withMove` callers apply the move to their own model: remove the
key from its old parent first, then insert at the reported index, which names
a FINAL-list position.
- Fix: `SectionedListController.moveItem(index:)` dropped `animate` on the
in-section path, so `animate: false` slid anyway. `reorderItems` and
`ItemView.moveTo` gained matching `animate` parameters.
- The declarative `SectionedSliverList` now skips the diff when `sections` is
the `identical` instance from the previous build; `itemsOf` is excluded from
the check and must be pure.
- Perf: `childrenOf` is consulted exactly once per node per sync, and is now
documented as required to be a pure function of its argument.
- Added `TreeSyncController.snapshotChildPresence()`: every live key mapped to
whether it has live children, with no per-node child-list copies.
- **BREAKING** drag handles are now placed by the CALLER: removed
`TreeRowDragMode` (with `TreeRowLongPressDrag` / `TreeRowHandleDrag` /
`TreeRowManualDrag`), `TreeDragHandleBuilder`, the `rowDragMode` /
`itemDragMode` / `sectionDragMode` config fields, `ReorderableNodeWrapper`,
the `wrap` parameter of `SliverReorderableTree.nodeBuilder`, and the
`draggable` members of `TreeItemView` / `SectionView` / `ItemView`, replaced
by `TreeDragHandle` and `TreeDelayedDragHandle` plus `TreeRowDragScope`.
`nodeBuilder` reverts to `(context, key, depth)` and every row is wrapped
unconditionally, so a row with no handle cannot be lifted but is still a drop
target with its reorder semantics actions.

  Migration:
  `nodeBuilder: (c, k, d, wrap) => wrap(longPressToDrag: true, child: row)`
  becomes `nodeBuilder: (c, k, d) => TreeDelayedDragHandle(child: row)`.
- **BREAKING** `TreeReorderConfig.rowDragMode` is replaced by
`buildDefaultDragHandles` (default TRUE, matching `ReorderableListView`), and
`SectionedReorderConfig` gets the per-kind pair `buildDefaultItemDragHandles`
/ `buildDefaultSectionDragHandles`; callers who never typed a drag mode need
no migration, while `.handle` / `.manual` callers set the flag false and place
a handle in their builder. Behavior notes: a `canReorder`-refused grip now
renders visibly (disarmed) instead of hidden with reserved width, and a handle
drag accepts on distance in ANY direction.
- Fix: grab geometry when a drag starts on a PINNED sticky header (the card
jumped on pickup and the proxy rendered at the wrong height).
`ReorderRenderPort` gained `paintedRowBounds(key)`.
- Fix: `.hierarchy` input reversed the ROOT order for multi-root input
(`[a, b, c]` came out `[c, b, a]`); child order was unaffected.
- `TreeItemView` gained `indexInParent`, `siblingCount`, `isFirst` and
`isLast`, all live-space (siblings animating out are excluded).
- Fix: rows now rebuild when a sibling insert, removal, reorder or move shifts
their position; sibling mutations declare the whole sibling list as affected.
- **BREAKING** removed `TreeItemView.watch`, `SectionView.watch` and
`ItemView.watch`: rows already rebuild when their own rendered inputs change,
so read the properties inline. The controller payload listeners and
`TreeNodeBuilder` are unaffected.
- `TreeController` gained an expansion-listener channel:
`addExpansionListener` / `removeExpansionListener` report `(key, isExpanded)`
for every state flip, `expandAll` / `collapseAll` included. Node lifecycle
resets are silent, and `runBatch` coalesces per key.
- `SyncedSliverTree` gained `onExpansionChanged` (its own initial expansion
pass is silent), `initialNodeExpansion` (per-node initial policy
`(key, item) -> bool?`, null defers to `initiallyExpanded`), and
`onControllerCreated` (one-shot handover of the internal `TreeController`
after the first sync; do not dispose it).
- **BREAKING (behavior)** the no-op rebuild fast path compares only the mode's
collection instance, not the extractor callbacks (`keyOf`, `childrenOf`,
`parentOf`), which must now be pure functions of their input. Pass a new
collection instance to signal change, the `ListView.children` convention.
- Fix: starting a drag while a previous drop's slides were still running left
drop-target resolution on an O(rows) scan per pointer event for the whole
drag. Edge ghosts now retire on FLIP-slide state via the new
`TreeController.hasActiveFlipSlides` / `getFlipSlideDeltaNid`; painted
positions, hit-testing, retention and overreach still read the composed
`hasActiveSlides` / `getSlideDeltaNid`.
- Fix: a row sliding IN from off-screen during a drag popped in at the
viewport boundary instead of gliding in from beyond the edge, because the
slide-install path mistook a held make-room offset for an in-flight slide.
The same misread also installed pointless slides for rows off-screen on both
sides of such a mutation.
- Perf: `expand()` and `collapse()` on an idle tree no longer pay an
O(subtree) slide-baseline staging cost per call, and `collapse()` walks its
visible descendants once instead of twice. Behavior is unchanged whenever
slides are active.
- Perf: `getIndexInParent` is now O(1) amortized instead of an O(siblings)
scan per call, so drop-target resolution during a drag and the per-row
semantics-action builders no longer rescan wide sibling lists. The live-space
contract and return values are unchanged.

## 0.0.32

- Fix: parent rows that render their child count now refresh whenever the count
changes, not only when `hasChildren` flips. Previously a parent kept its
pre-removal count after an animated child removal, most visibly as stale
`SectionedSliverList` header item counts.
- `TreeItemView` gained `liveChildCount` / `hasLiveChildren`, counts that
exclude children animating out for builders that want the settled state rather
than the painted state (`childCount` keeps matching the rows still on screen).
- **BREAKING** one `TreeAnimationStyle` now configures every animation family:
`expandCollapse`, `enterExit` (falls back to `expandCollapse`), `reorderSlide`,
`makeRoom` and `dropSettle` (fall back to `reorderSlide`). Removed in favor of
`animationStyle`: `TreeController.animationDuration` / `animationCurve`,
`TreeReorderController.slideDuration` / `slideCurve`, and the
`animationDuration` / `animationCurve` params on all `SyncedSliverTree`
constructors, `SectionedSliverList` and `SectionedListController`.

  Migration: replace `animationDuration: D, animationCurve: C` with
  `animationStyle: TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: D, curve: C))`,
  and `animationDuration: Duration.zero` with
  `animationStyle: TreeAnimationStyle.disabled`. Use
  `TreeAnimationStyle.uniform(duration:, curve:)` for one spec everywhere.
- **BREAKING (behavior)** the zero-duration kill switch is per-family: a family
resolving to `Duration.zero` snaps and dominates explicit per-call durations,
and each drag family gates on its own spec (so `dropSettle` glides still run
when `reorderSlide` is zeroed). A zero family creates no motion but no longer
drops other families' in-flight slides; restyling `reorderSlide` to zero at
runtime still stops in-flight slides.
- **BREAKING (behavior)** uniform defaults: all five families now default to
300ms / `Curves.linear`, from one shared `TreeAnimationStyle.defaultSpec`. The
old per-family defaults, now gone, were 300ms / `Curves.easeInOut` for
expand/collapse and 220ms / `Curves.easeOutCubic` for slide and preview; pass an
explicit spec to restore either.
- `reorderRoots` / `reorderChildren` gained per-call `slideDuration` /
`slideCurve` overrides and now read the `reorderSlide` family, so keyboard
reorder semantics actions animate consistently with `moveNode`. Sync-driven
moves and reorders keep riding `expandCollapse` to stay in lockstep with
same-batch extent animations.
- `moveNode` / `animateSlideFromOffsets` / `setReorderPreview` /
`clearReorderPreview` timing params are now optional, defaulting to the style's
family specs.
- Fix: `expandAll` / `collapseAll` completion no longer reports the finished
bulk group's members as still animating.
- Perf: `setReorderPreview` scans only the visible order and memoizes unchanged
drop slots, so pointer-dwell re-sends skip the target recomputation entirely.
- Perf: `findRowAtPaintedY` uses an O(window) bounded scan during drags instead
of an O(visible) scan per pointer event. `maxActiveSlideAbsDelta` is now
test-only; production reads the new `composedSlideAbsDeltaBound`.
- Drag-and-drop example: the duration slider restyles live.

## 0.0.31

- **BREAKING** the drop-indicator line is gone; the make-room preview is now
the only drop-feedback paradigm. Removed `SliverReorderableTree`'s
`showDropIndicator`, `dropIndicatorColor`, `dropIndicatorThickness`,
`makeRoomOnDrag` (always on), and `draggedOpacity` (the dragged row's
in-place copy is always hidden so its slot can close).
- **BREAKING** `SliverReorderableTree.showDragProxy` now defaults to `true`,
because make-room hides the dragged row and without a proxy nothing follows the
pointer. The proxy renders in the root `Overlay` outside the row's ancestry,
so Material rows need a `dragProxyBuilder` re-providing a `Material`
ancestor.
- Consequence of the two above: drags are now CARD-ANCHORED by default, so slot
selection probes at the floating proxy's midpoint rather than the raw
pointer. Pass `showDragProxy: false` for the raw-pointer probe.
- `indentPerDepth` is retained, but now serves only the pointer-x to drop-depth
mapping at subtree boundaries.

## 0.0.30

- Internal refactor of the drag-and-drop reorder stack into per-session
collaborators; no public API changes.
- Perf: fewer render-tree lookups per pointer move during drags.
- `startDrag` against an already-unmounted scrollable now returns `false`
instead of asserting.

## 0.0.29

- Touch-first drag anchoring: slot selection follows the floating card's
midpoint in make-room + proxy sessions (the finger hides under the card).
- Fix: handle-drag grab geometry skew caused by touch-slop acceptance.
- Mid-drag gesture-mode swaps now cancel the session cleanly.
- Fix: throw when a drag ends after the scrollable was unmounted.
- Added opt-in `SliverReorderableTree.hapticsOnDrag`.
- Workspaces example: handle-mode / touch-mode toggle.

## 0.0.28

- Re-resolve the drop target on any scroll (wheel / trackpad / autoscroll),
not just pointer moves.
- X-aware drop depth at subtree boundaries (pick nesting level from the
pointer's horizontal position).
- Hover-dwell auto-expand of collapsed drop targets (`autoExpandDelay`).
- Reorder semantics (accessibility) actions on wrapped rows.
- Floating drag proxy (`showDragProxy` / `dragProxyBuilder`); drops settle
from the release position instead of replaying the old-slot slide.
- Make-room preview (`makeRoomOnDrag`): rows part to open a paint-only gap
at the prospective slot; the drop lands with zero jump.
- Eliminate drop-zone dead zones ("returns here" targets, two-zone split
under `into` vetoes) and section-boundary gap oscillation.
- Discard FLIP baselines staged without a following mutation.
- Added `TreeController.liveChildCount` / `liveRootCount`.

## 0.0.27

- **BREAKING** drag-and-drop reorder API refactor: `TreeReorderController`
is key-only (`<TKey>`), `startDrag` takes a `ReorderRenderPort` and
returns `bool` for policy refusals, and `TreeDropTarget` is purely
semantic (indicator geometry derived by the widget layer).
- Added `SliverReorderableTree.showDropIndicator` to disable the built-in
indicator line.
- Added `TreeController.hasLiveChildren` / `hasComparator`.
- Fix: double-invoked drag-UI teardown in `SliverReorderableTree`.

## 0.0.26

- `TreeSyncController` / `SectionedListController`: syncs now diff against
controller truth; a desired list that still contains a removed (mid-exit) key
resurrects it. Derive mirrored state from live reads (`getLiveChildren` /
`liveItemsOf`) to preserve imperative removals.
- `TreeController.animateScrollToKey`: animated-mode scrolls are now
single-flight: starting a new scroll cancels the one in flight (its future
resolves false).

## 0.0.25

- Animate same-parent reorders in `SyncedSliverTree`.

## 0.0.24

- Fix: reparenting between a non-collapsed and a collapsed node.

## 0.0.23

- Fix: occlusion / z-order of a tall card reparented into a collapsed section.

## 0.0.22

- Fix: reparenting into collapsed section.

## 0.0.21

- Minor bug fixes.

## 0.0.20

- Minor clean-ups.
- Minor bug fixes.

## 0.0.19

- Fix: orphaned animation entry staying during quick filtering.
- Perf: minor optimizations.

## 0.0.18

- Fix: `SyncedSliverTree` / `TreeSyncController` reparent animation skip when
parent is deleted.

## 0.0.17

- Use animated `moveTo` in `SyncedSliverTree`.

## 0.0.16

- `SectionedSliverList` public surface trimmed and restructured. Same underlying
engine; new ergonomics.
- Added animations to `moveTo`.

## 0.0.15

- Fix: root node ordering regression caused by switching from recursive to
iterative. Root nodes were being reversed.

## 0.0.14

- Fix: animation of nested collapsing/expanding nodes when parent collapse or
expand state is toggled mid-animation.
- Fix: animation collapse-expand-collapse behavior.

## 0.0.13

- Added `SectionedSliverList`: a header + items convenience sliver built
on top of `SliverTree`.
- Fix: animation issue when adding/removing many times quickly.
- Fix: visible-subtree-size cache desync across all node-purge paths.
- Fix: node removal desync.
- Replace recursive code with iterative.
- Added various tests.

## 0.0.12

- Fix: missing case to clip content above viewport when at max extent.
- Fix: animation skip when drag and dropping a collapsing node.
- Perf: optimized collapsing of nodes with many children.
- Fix: visual flicker when collapsing a node with many children.

## 0.0.11

- Stale node eviction.
- Fix: scroll-to-node jump.

## 0.0.10

- Perf: optimized expansion of nodes with many children.

## 0.0.9

- Fix: re-insert animation regression.
- Fix: expansion persistence regression.

## 0.0.8

- Added `animateScrollToKey`: scroll to node by key.
- Various fixes and optimizations.

## 0.0.7

- Added `SyncedTreeNode` and new constructors.

## 0.0.6

- Refactor `TreeMapView` into `SyncedSliverTree`.

## 0.0.5

- Added test for expansion memory during animated removal and re-addition.

## 0.0.4

- Fix: expansion state for multi-sync.

## 0.0.3

- Fix: expansion state history.

## 0.0.2

- Fix: expanding a child node that has a collapsed parent (previously ignored
expansion).
- Made child sync recursive for `SyncedSliverTree` and `TreeSyncController`.

## 0.0.1

- Added `sliver_tree`: a node based sliver that supports tree-like nesting for
data.
