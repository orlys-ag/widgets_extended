# widgets_extended

A declarative, animated tree sliver for Flutter: **`SyncedSliverTree`**.

Hand it your data on every build. It diffs against what is on screen and
animates the difference: inserts grow in, removals shrink out, moves and
reorders slide, reparenting glides across depths. No controller to manage,
no imperative mutation calls, no manual keys bookkeeping. Drag-and-drop
reorder is one parameter.

The package also ships **`Board`**, a two-axis lattice for calendars,
timelines and grids; see [Board](#board).

## Install

`flutter pub add widgets_extended`.

## Quick start

```dart
import 'package:widgets_extended/widgets_extended.dart';

class Folder {
  Folder(this.id, this.name, [this.children = const []]);
  final String id;
  final String name;
  final List<Folder> children;
}
```

Your model already has the structure, so point the tree at it:

```dart
CustomScrollView(
  slivers: [
    SyncedSliverTree<String, Folder>.hierarchy(
      roots: folders,
      keyOf: (f) => f.id,
      childrenOf: (f) => f.children,
      indentWidth: 24,
      itemBuilder: (context, node) => ListTile(
        title: Text(node.item.name),
        leading: node.hasChildren
            ? Icon(node.isExpanded ? Icons.expand_more : Icons.chevron_right)
            : const Icon(Icons.insert_drive_file_outlined),
        onTap: node.toggle,
      ),
    ),
  ],
)
```

That is a working animated tree: tapping a row expands or collapses it with
animation, and rows indent by depth automatically (`indentWidth` pixels per
level).

To change the tree, change your data and hand in a **new list instance**:

```dart
setState(() {
  folders = folderStore.currentRoots(); // new instance = diff + animate
});
```

The widget diffs the new input against the screen and animates every
transition. Passing the `identical` instance as last time skips the diff
entirely (the `ListView.children` convention), so a frequently rebuilding
ancestor costs nothing. `keyOf` / `childrenOf` must be pure functions of
their argument.

## The row builder

`itemBuilder` receives a `TreeItemView` with everything a row usually needs,
all kept fresh automatically (rows rebuild when a sibling change shifts
them):

| | |
| --- | --- |
| Data | `node.item`, `node.key`, `node.depth`, `node.parentKey`, `node.isRoot`, `node.indent` |
| Structure | `node.hasChildren`, `node.childCount`, `node.liveChildCount`, `node.hasLiveChildren`, `node.isFirst`, `node.isLast`, `node.indexInParent`, `node.siblingCount` |
| Expansion | `node.isExpanded`, `node.toggle()`, `node.expand()`, `node.collapse()` |

`node.isFirst` / `node.isLast` make connector lines and rounded-group
styling trivial. They, `node.indexInParent` and `node.siblingCount` are
all live-space: a sibling that is animating out is already excluded, so
the last row stays the last row for the length of a removal. The child
counts split the other way. `node.childCount` INCLUDES children still
painting their exit, which is what a badge rendered beside those rows
wants; `node.liveChildCount` and `node.hasLiveChildren` report the
settled state instead.

`node.controller` is the escape hatch to the full imperative API if you
ever need it.

## Drag-and-drop reorder

Pass a `reorder:` config. That is the whole integration:

```dart
SyncedSliverTree<String, Folder>.hierarchy(
  roots: folders,
  keyOf: (f) => f.id,
  childrenOf: (f) => f.children,
  indentWidth: 24,
  reorder: TreeReorderConfig<String>(
    onReorder: (key, newParent, index) {
      setState(() {
        folders = folderStore.move(key, toParent: newParent, at: index);
      });
    },
  ),
  itemBuilder: (context, node) => ListTile(title: Text(node.item.name)),
)
```

Every row becomes draggable by long-press, with no change to your builder.
While dragging, rows part to open a live gap at the prospective slot, a
floating proxy follows the pointer, hovering a collapsed parent auto-expands
it, the pointer's horizontal position picks the nesting depth at subtree
boundaries, and the drop settles in place with no jump.

Rules your `onReorder` handler lives by:

- **`index` is a final-list position.** Remove `key` from its old parent
  first, THEN insert at `index` in the new parent's children (`newParent`
  null means the root list). Computing an index against the pre-removal
  list puts same-parent downward moves one slot too far.
- **Your data stays authoritative.** A move you do not record is reverted
  by the next sync; that is also how you reject a drop. To roll back an
  already-recorded move, emit a NEW collection instance.
- **Async handlers record before awaiting**, then reconcile or roll back on
  the response.

Three policies gate a move, and they compose. `enabled:` is the
tree-wide runtime switch, for an edit mode you flip with app state.
`canReorder: (key) => ...` gates dragging per row. `canAcceptDrop:
({required movingKey, newParent, index}) => ...` filters destinations
instead of sources, and also shapes the zones: a row that refuses
`(newParent: thatRow, index: 0)` cannot take children at all, so it drops
its `into` zone and splits in two rather than three.

A refused row keeps its exact widget shape, which is deliberate: a shape
that varied with policy would fail `Widget.canUpdate` and re-inflate every
row subtree on each toggle, disposing whatever `State` your builder keeps
there. The trade is that a refused row's handle still RENDERS, inert,
because the package does not decide what your grip looks like. Read
`TreeRowDragScope.canDrag` from a `Builder` inside the row to hide it
while reserving its space:

```dart
Builder(
  builder: (context) {
    final canDrag = TreeRowDragScope.maybeOf(context)?.canDrag ?? false;
    return Visibility(
      visible: canDrag,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: const TreeDragHandle(child: Icon(Icons.drag_indicator)),
    );
  },
)
```

On desktop, long-press reads as lag, so turn the default handles off and
place a visible grip anywhere inside the row (`TreeDragHandle` drags
immediately, `TreeDelayedDragHandle` on press-and-hold; both draw
nothing):

```dart
reorder: TreeReorderConfig<String>(
  buildDefaultDragHandles: false,
  onReorder: ...,
),
itemBuilder: (context, node) => Row(
  children: <Widget>[
    Expanded(child: ListTile(title: Text(node.item.name))),
    TreeDragHandle(child: Icon(Icons.drag_indicator)),
  ],
),
```

Rows built from Material widgets need a `dragProxyBuilder` that re-provides
a `Material` ancestor (the proxy floats in the root `Overlay`, outside your
row's ancestry), the same contract as `Draggable.feedback`. Screen readers
get move up / down / out / into actions automatically, reported through the
same `onReorder`.

## Expansion

- `initiallyExpanded: true` (the default) opens the whole tree on the
  first sync, and opens any node that gains its first children in a later
  one; `initialNodeExpansion: (key, item) => bool?` overrides it per node
  (return null to defer). Both are INITIAL policies: once a node exists,
  its own expansion state wins.
- `expansionMemory` (default 1024) remembers up to that many removed
  nodes' expansion states across remove/re-add cycles (0 disables it),
  and a user's deliberate collapse is never overridden by later syncs.
- `onExpansionChanged: (key, isExpanded) { ... }` is the hook for
  persisting expansion state.

For capabilities no row can reach, such as toolbar buttons or deep links,
grab the internal controller once:

```dart
SyncedSliverTree<String, Folder>.hierarchy(
  // ...
  onControllerCreated: (controller) => _tree = controller,
)

// Later:
_tree.expandAll();
_tree.animateScrollToKey(deepLinkedId, scrollController: scrollController);
```

Do not dispose it; the widget owns it.

## Other input modes

`.hierarchy` fits nested models. Two siblings cover the rest, with the same
parameters otherwise:

```dart
// Flat rows with parent pointers (query results, adjacency lists).
SyncedSliverTree<String, Task>.flat(
  items: tasks,
  keyOf: (t) => t.id,
  parentOf: (t) => t.parentId, // null = root; unknown key = ArgumentError
  itemBuilder: ...,
)

// Explicit SyncedTreeNode tree, for when the UI itself edits structure.
SyncedSliverTree<String, Folder>(
  tree: [
    SyncedTreeNode(key: "docs", data: docs, children: [
      SyncedTreeNode(key: "taxes", data: taxes),
    ]),
  ],
  itemBuilder: ...,
)
```

## Animation styling

One `TreeAnimationStyle` times every animation family (expand/collapse,
enter/exit, reorder slides, the drag gap, drop settles). Defaults are 300ms
linear across the board:

```dart
SyncedSliverTree<String, Folder>.hierarchy(
  // ...
  animationStyle: TreeAnimationStyle.uniform(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
  ),
)
```

Per-family specs are available (`TreeAnimationStyle(expandCollapse: ...,
reorderSlide: ...)`), unset drag families inherit from `reorderSlide`, and
`TreeAnimationStyle.disabled` snaps everything, which is also the
synchronous-test configuration.

## Board

`Board` is the package's second widget: a two-axis scrolling lattice of
cells with items laid over it, for week views, month calendars, timelines
and spreadsheets. Items span whole or fractional tracks, overlapping items
stack into lanes along the axis you give a `laneExtent`, and they animate
in, out and across. A `BoardController` owns the items; the widget shows
them:

```dart
class Task {
  const Task(this.id, this.title);
  final String id;
  final String title;
}

class Planner extends StatefulWidget {
  const Planner({super.key});

  @override
  State<Planner> createState() => _PlannerState();
}

class _PlannerState extends State<Planner> with TickerProviderStateMixin {
  late final controller = BoardController<String, Task>(
    vsync: this,
    rows: BoardAxisConfig(axis: UniformAxis(24, 48)), // hours
    columns: BoardAxisConfig(axis: UniformAxis(7, 120), laneExtent: 40), // days
    keyOf: (task) => task.id,
  );

  @override
  void initState() {
    super.initState();
    controller.addItem(
      const Task("standup", "Standup"),
      const BoardSpan(rowStart: 9, colStart: 1),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Board<String, Task>(
      controller: controller,
      cellBuilder: (context, cell) => const DecoratedBox(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(BorderSide(color: Colors.black12)),
        ),
      ),
      itemBuilder: (context, view) => Card(child: Text(view.item.title)),
      drag: BoardDragConfig<String>(
        onItemMoved: (key, span) => controller.moveItem(key, span),
        onItemResized: (key, span) => controller.resizeItem(key, span),
        primaryResizeEdges: BoardResizeEdges.both,
      ),
      selection: BoardSelectionConfig(onChanged: (selection) {}),
    );
  }
}
```

**Dragging.** An item lifts on a long press and follows the finger, and on
the lane axis its neighbours make room. `primaryResizeEdges` gives an item
resize handles at the ends of its span along the primary axis (the rows,
unless the columns are content-sized) and `resizeEdges` along the other.
The board
REPORTS a drop through `onItemMoved` and `onItemResized` and changes
nothing itself: apply it, as above, or ignore it to refuse. `canDropAt:
(key, span) => ...` refuses a placement before the drop, so it shows no
gap, and `dropFit` slides a refused move onto nearby free space. `snap:
BoardSnap.fraction(0.25)` lands on quarter tracks. For an immediate grip,
set `buildDefaultDragHandles: false` and put a `BoardDragHandle` inside the
item.

**Selection and keys.** `BoardSelectionConfig` selects a range by dragging
across cells, the default, or one cell per tap (`mode:
BoardSelectionMode.cell`). On touch a range starts with a long press, so a
plain drag scrolls. The selection lives on the controller
(`controller.selection`, `setSelection`). A focused board moves it with the
arrow keys, extends it with Shift, jumps with Home, End and Page Up/Down,
and Escape cancels a drag.

**Axes.** `UniformAxis`, `ExplicitAxis` and `DerivedAxis` give tracks fixed
extents; `LazyContentAxis` measures them from their cells. `frozenStart`
and `frozenEnd` pin header and footer tracks, and items inside a frozen
band stay with it. The board reads no `Directionality`: a right-to-left board
passes `horizontalDetails: ScrollableDetails.horizontal(reverse: true)`.

**The model.** `addItem`, `moveItem`, `resizeItem`, `removeItem` and
`updateItem` change one item; `setItems` replaces them all, diffing by key.
`itemCount`, `keys`, `itemsAt` and `itemsIn` read them back.
`animateScrollToCell`, `jumpToCell` and `revealCell` scroll to a cell, and
`BoardAnimationStyle` times every animation (`BoardAnimationStyle.disabled`
snaps them). An item builder's `view.presence` is the item's enter/exit ramp
as an `Animation<double>`, so `FadeTransition(opacity: view.presence, ...)`
fades an item in and out as the board grows and shrinks it.

`examples/lib/week_view_example.dart` and
`examples/lib/month_calendar_example.dart` are complete boards.

## Also in the box

- `maxStickyDepth: 1` pins root rows as sticky headers while scrolling
  through their children (higher values pin deeper levels too).
- `SectionedSliverList`: a two-level header + items convenience built on
  the same engine, with per-kind reorder config.
- `SliverTree` + `TreeController`: the imperative lowest layer, for full
  control over every mutation.

All of it runs on one sliver core: viewport-aware lazy building, dense
integer-indexed state storage, and reorder slides that are paint-only per
frame, so rows glide without relayout.

## Learn more

- `doc/synced_sliver_tree_tutorial.md` builds one drag-and-drop screen
  from nothing: input modes, the row builder, a custom grip, the
  `onReorder` contract, the drag proxy and the accessibility actions.
- `examples/lib/` holds a runnable program per feature. Point
  `examples/lib/main.dart`'s `home:` at the one you want.
