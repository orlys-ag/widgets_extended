---
paths:
  - "lib/board/board_widget.dart"
---

# board architecture: widget

The contract of `Board`. The conventions every layer follows are in `board.md`.

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
  rebuild is otherwise invisible below the element layer; the surface
  carries `buildsNothing`, true exactly when the host shows the empty
  box it puts in place of its OWN builder's null answer and false while
  it shows the delegate's `initial`, which the delegate hands a host only
  for a non-null answer, and the surface hands it to the render, which
  takes that cell as no cell rather than measuring the box
  (`board-render.md` states when the surface delivers it);
  the render relays out on those two channels only when the last layout
  obtained a cell the DELEGATE built as NULL, which holds no host and can
  be re-asked by nothing else, re-measurement having moved to the poke
  and the controller's door; the drag
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
