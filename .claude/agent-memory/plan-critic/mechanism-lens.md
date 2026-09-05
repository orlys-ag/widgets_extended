# Mechanism lens: recurring holes in plans for this repo

Three checks that have each caught a real defect and are cheap to run.

## 1. "Coalesced" notify is only coalesced in transientCallbacks

`AnimationCoordinator.notifyListeners` coalesces to a microtask ONLY when
`SchedulerBinding.instance.schedulerPhase == SchedulerPhase.transientCallbacks`
(`_animation_coordinator.dart:304`, rationale at `:299`). Layout runs in
persistentCallbacks, so any animation-channel notify issued from inside a
layout method dispatches SYNCHRONOUSLY to every listener. If the render
object's own listener can call `markNeedsLayout`, that is the
"must not re-dirty itself while still being laid out" throw
(`rendering/object.dart:2382` branch). Whenever a plan puts an animation
INSTALL inside layout, ask what the install notifies.

## 2. A gesture-owning row State that can unmount mid-drag needs a backstop

`MultiDragGestureRecognizer.dispose` resolves its arena entries and never
calls `cancel()`/`end()` on its client, so disposing it under a live session
orphans the session (ticker, flags, held preview offsets all survive). The
tree solves it in THREE places, not one: the two replacement legs in
`_startDragFromHandle` (`sliver_reorderable_tree.dart:1358`, `:1379`), a
render-object drag PIN that stops eviction of a live dragged row, and a
`deactivate()` lifecycle backstop that defers a cancel past the frame
(`sliver_reorderable_tree.dart:998`). A plan that copies only the handle trio
has copied one of the three.

## 3. Commit-by-callback plus "a mutation on the dragged key cancels the drag"

If a drag layer reports its commit to app code that then calls a mutator, and
the mutator cancels the session when the dragged flag is set, the ORDER of
"clear the flag" against "report" is load-bearing on the primary path, not an
edge case. The house rule is in source: report AFTER teardown
(`tree_reorder_controller.dart:643`), because a second teardown
double-disposes the autoscroll ticker (`tree_reorder_controller.dart:523`).

## 4. An engine's early-out guard keyed on ONE collection

`MakeRoomEngine.releasePreview` opens with `if (_held.isEmpty) return;`
(`_make_room_engine.dart:229-231`), and `hasActive` is `_held.isNotEmpty`
(`:91-93`). The same shape is in `ItemSlideEngine` and
`ItemEnterExitAnimator` (`_stopIfIdle` on `_records.isEmpty`). Whenever a
plan adds a SECOND per-engine collection (a slot list, a second map), grep
the engine for every `isEmpty`/`isNotEmpty`/`hasActive`/`_stopIfIdle` guard
and check the plan widened each one. A missed release guard leaks the new
collection forever on exactly the path the new collection exists for.

## 5. The board's zero-family pairings are not symmetric

`effectiveMakeRoom = _makeRoom ?? itemSlide` and
`effectiveItemEnterExit = _itemEnterExit ?? trackResize`
(`board_animation_style.dart:185-197`), so a zero `itemSlide` zeroes
makeRoom and dropSettle while `trackResize` stays live. Any plan that
couples a paint-only family's clock to a layout-driving one must be checked
at the MIXED pairings (0, >0) and (>0, 0), not only at
`BoardAnimationStyle.disabled`. Also: `animationStyle`'s setter has arms
for itemSlide and trackResize ONLY, and its comment
(`board_controller.dart:226-229`) justifies the omission of makeRoom by
"makeRoom's held gap is not motion" -- a plan that makes makeRoom
layout-driving must revisit that site.

## 6. The board's dragged item is NOT hidden while the proxy shows

`board_widget.dart:361-363`: "The item's in-place widget stays live with
`isDragging` true; the proxy is the moved visual." The item paint pass has no
dragging skip (`render_board_viewport.dart:1598-1607`); `isDraggingId` is read
only by `itemAt` (`render_board_viewport.dart:1935-1937`). On a content-sized
lane axis the in-place item paints at
`lead = trackLead + padding + lane * laneExtent`, `extent = laneExtent *
enterExitProgressOf(id)`, and `enterExitProgressOf` is exactly 1 for a settled
live item (`_board_animation_coordinator.dart:66-71`,
`render_board_viewport.dart:1065-1068`). So any plan that SHRINKS the source
track while an item is "lifted" leaves that item painting outside its own
track for the whole drag. This is the opposite of the sliver_tree precedent
(sized placeholders while the proxy is shown), so a plan reasoning by analogy
to the tree will get it wrong. Same trap for a make-room "restore" ramp after a
cancel: `_installDropSettle` runs only from `endDrag`, never from
`_handleMutationCancel` or `dispose` (`board_drag_controller.dart:388-394`,
`:512-519`), so on those exits the item is back at full extent instantly while
the track is still ramping.

## 7. `resolveDryRun` touches TWO buckets, so a "preview" also moves the SOURCE track

`OverlapLaneResolver.resolveDryRun` adds the dragged item's STORED lane-axis
bucket as well as the prospective one (`_overlap_lanes.dart:385-390`), removes
the dragged id from the stored bucket (`:407`), re-sweeps it, and writes EVERY
member of BOTH buckets into the returned map (`:428-430`). `previewGap` then
creates a held offset for any member whose lane changed
(`_make_room_engine.dart:172-177`), and on a content-sized lane axis
`_laneOriginOfId` is `padding + lane * laneExtent`
(`board_controller.dart:1327-1336`), so a source neighbour that re-lanes UP
carries a NEGATIVE held delta. Any plan that says "the make-room preview only
affects the target track" or "the source track carries no make-room
contribution" is wrong; check it against these lines, not against a fixture
whose source bucket happens not to re-lane.

## 8. `previewGap`'s snap arm re-CONSTRUCTS every held entry before it discards

`_make_room_engine.dart:203-214` replaces each `_HeldOffset` with a fresh
`_HeldOffset(..., snapped: true)` under the kill switch, and only then does
`:216-218` remove the ones at target 0. So any rule of the form "bump a
generation when the snap arm discards an entry whose `snapped` flag is false"
is DEAD on the install arm: by the discard the flag is always true. Slots or
any second collection added later are not yet re-flagged at that point, so the
two halves of such a rule behave differently. Ask a plan which half it means.

## 9. A drop target is only stepwise-constant under `BoardSnap.track()`

`BoardSnap.free()` returns `trackSpace` unchanged from `quantize`
(`board_config.dart:51-52`), and `_resolveMove`'s non-track branch writes
`rowFraction: row - row.floorToDouble()` straight from
`port.trackSpaceAt(anchorLocal)` (`_board_drop_resolver.dart:164-184`), whose
fraction is `(content - offsetOf(track)) / extentOf(track)`
(`render_board_viewport.dart:2066`). So the resolved `BoardDropTarget` is a
CONTINUOUS function of the recorded axis extents, and `_resolve`'s
`target == _currentTarget` early-out (`board_drag_controller.dart:432-434`)
does not fire when a track resizes. Any plan that (a) re-runs `_resolve` per
frame and (b) makes a track extent change per frame builds a loop:
`previewGap` rebuilds every `_HeldOffset` with `from = current, t = 0`
(`_make_room_engine.dart:203-214`), so `t` never reaches 1, `_stopIfIdle`
(`:272-282`) never stops the ticker, and layout runs every frame for the whole
session. Check every "costs one `trackSpaceAt`" claim against the free and
fraction snap modes, not the `BoardSnap.track()` default.
