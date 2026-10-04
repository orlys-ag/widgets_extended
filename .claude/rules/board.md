---
paths:
  - "lib/board/*.dart"
  - "lib/board/**/*.dart"
  - "test/board/*.dart"
  - "test/board/**/*.dart"
---

# board architecture

Normative for `lib/board/`. This rule holds the conventions every layer follows; each layer's contract is in the rule that names its files:

| Rule | Covers |
|---|---|
| `board-model.md` | `Fenwick`, the axes, spans and the start rule, `SpanIndex`, `OverlapLaneResolver`, `BoardController`, `BoardScrollOrchestrator`, the view, config and background types, and the barrel |
| `board-animation.md` | `BoardAnimationCoordinator` and its animation sources |
| `board-render.md` | `RenderBoardViewport` |
| `board-widget.md` | `Board` |
| `board-drag.md` | The drag layer |

## Conventions that cut across every layer

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
  the last layout obtained a cell that built NULL (see `Board` in `board-widget.md`).
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

## Usage patterns

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
