# Perf lens: the house yardstick for per-item hot-path reads

Two checks that keep paying off on plans for this repo.

## 1. Every per-item read the render layer makes has a house shape

`tree_controller.dart:1160` is the reference: `double getSlideDeltaNid(int nid)`,
documented at `tree_controller.dart:1159` as "read every paint, hit-test, and
transform call for visible rows, so saving the key-to-nid hash matters". Three
properties, and a new module's reader interface should be checked against all
three rather than against the general "use nids" rule:

- **id-keyed, not key-keyed**: no hashing on the paint path.
- **scalar-returning**: the X axis gets its OWN accessor
  (`getSlideDeltaXNid`, `tree_controller.dart:1223`) rather than one
  `Offset`-returning call, so paint allocates no value object per item per
  frame.
- **one boolean guard when idle**: `if (!_preview.hasActive) return base;`
  (`tree_controller.dart:1165`) under the comment "One boolean guard keeps the
  non-drag hot path unchanged" (`tree_controller.dart:1162`).

A plan that declares level flags (`hasActive*`) on its reader but never says the
per-item read short-circuits on them, or that returns `Offset`/a record/a value
object per item, has dropped two of the three. Watch for the plan arguing the
scalar rule in one section (id-keyed span reads) and breaking it in the next
(an `Offset`-returning animated read).

Same yardstick applies to render-object side tables: a
`Map<SomeVicinity, int>` probed once per painted child hashes a key on the paint
path; a `List<int>` parallel to the paint-order list, built in the same sweep,
carries the same information.

## 2. A derived per-bucket cache needs its maintenance sites enumerated

Any plan that narrows a scan bound with a cached aggregate (a per-bucket
`max...Span`, a watermark, a cumulative prefix) has to name EVERY mutator that
maintains it, not just the one it was introduced for. The usual defect is that
the recompute is stated only inside a bulk/flush path, so the single-mutation
path leaves the aggregate stale. Both directions are bugs and only one is
testable by the oracle fuzz: too LOW misses items (the fuzz's set comparison
catches it), too HIGH silently degrades the bound to a full scan forever (sets
stay identical, so only a probe-count seam on a fixture that SHRINKS the
aggregate can see it). Check that the pinning fixture actually removes or
shrinks the extreme element.

## 3. board: "make-room ticks are paint-only today" is only half true

Before pricing a board plan that makes a paint-only source layout-driving,
check the tick router's third arm. `RenderBoardViewport._handleAnimationTick`
lays out whenever the composed offset bound EXCEEDS the bound the last layout
admitted (`render_board_viewport.dart:402-409`), and `_admittedOffsetBound` is
re-recorded from `anim.composedOffsetBound` at every
`layoutChildSequence` (`render_board_viewport.dart:456-459`). A gap OPENING has
a monotonically growing bound, so those ticks already force a layout. The real
cost delta of promoting makeRoom to layout-driving is therefore only the
CLOSING half plus any gap whose composed bound stays 0 (a slot/occupancy-only
preview with no displaced neighbour). Claiming "this turns every make-room tick
into a layout" overstates it by about half.

## 4. board MakeRoomEngine: every install restarts EVERY non-desired entry's clock

`previewGap` puts every existing `_held` key into `targets` at 0.0
(`_make_room_engine.dart:198-202`) and then REPLACES the entry with a fresh
`_HeldOffset` whose `t` field initializer is `0.0`
(`_make_room_engine.dart:212`, field at `_make_room_engine.dart:38`). Removal
requires `t >= 1.0 && target == 0.0` (`_make_room_engine.dart:307-309`), so a
closing entry is removed only after a full close duration with NO install. A
drag crossing cell boundaries faster than the makeRoom duration (autoscroll,
default 300ms) therefore never retires a closing entry, and the collection
grows with tracks/items visited for the whole session.

That is harmless for `_held`, whose settled value is 0 and contributes 0 to
paint and to the cluster term. It is NOT harmless for any new per-`(track,
lane)` collection whose settled contribution is `lane * laneExtent` rather
than 0: a stale entry then floors a crossed track's extent for the rest of the
drag. Price any plan that adds such a collection against this rule, and check
whether its stated bound is a per-track RESULT count while the lookup is a
linear scan of the whole list.

## 5. board `_sizeContentTracks` is the module's layout hot loop, and it has no level guard

Its body runs once per track in `_contentTrackExtents`
(`render_board_viewport.dart:840`), once per obtain round
(`render_board_viewport.dart:802`, inside the `while (true)` at
`render_board_viewport.dart:714`), once per correction pass
(`render_board_viewport.dart:465-488`, ceiling `_maxCorrectionPasses = 5`,
`render_board_viewport.dart:78`). The existing body allocates nothing per
member: `laneOfId` and `enterExitProgressOf` are scalar
(`render_board_viewport.dart:858-861`). Any plan that adds a per-member or
per-track read there should be checked for the third house property
(one boolean guard when idle, `tree_controller.dart:1162-1165`), because
this loop runs on EVERY layout of a content-lane-axis board, drag or not.

Beware: `hasActiveOffsets` (`_board_animation_coordinator.dart:153-155`) is
`slide.hasActive || makeRoom.hasActive`, so it is NOT a make-room-only
presence flag, and a motion-level flag is not a presence flag either (a
settled-but-held gap contributes to the term with no motion). A plan that
adds make-room reads to this walk needs a make-room PRESENCE flag it
usually forgets to declare.

## 6. board `BoardDragController._resolve` is not "one trackSpaceAt"

Any plan that increases `_resolve`'s call frequency should price what runs
BEFORE its early-out at `board_drag_controller.dart:432-434`:
`_repointScrollSubscriptions` (`:416`), a key-hashed
`boardController.spanOf(session.key)!` (`:426`), and
`BoardDropResolver.resolve`, which allocates a `BoardSpan` via `copyWith`
and a `BoardDropTarget` before the value comparison
(`_board_drop_resolver.dart:155-163`). Its doc comment
(`board_drag_controller.dart:412-414`) enumerates the callers ("once per
pointer event and once per scroll notification"), so a new caller also
falsifies that comment.
