# SyncedSliverTree tutorial

`SyncedSliverTree` is the declarative front door of the `sliver_tree` module.
You hand it your data, it diffs that data against what is on screen, and it
animates the difference. You never call `insert`, `remove` or `moveNode`
yourself.

This guide builds one screen from nothing: a tree of task cards, each with a
**notch** across the top of the card that the user grabs to drag the row
somewhere else.

The finished screen is a runnable file in this repo:

- `examples/lib/notch_drag_handle_tutorial.dart`. To run it, point
  `examples/lib/main.dart`'s `home:` at `const NotchDragHandleTutorial()`.
- `examples/test/notch_drag_handle_tutorial_test.dart` drives the notch with a
  real gesture and asserts the reorder commits.

Every snippet below is lifted from that file, which passes `flutter analyze`
and whose two tests pass.

---

## 1. The minimum viable tree

`SyncedSliverTree` is a **sliver**, so it lives inside a `CustomScrollView`
next to your other slivers. It needs two things: a structure and a row
builder.

```dart
CustomScrollView(
  slivers: <Widget>[
    SyncedSliverTree<String, Task>(
      tree: _treeInput,
      itemBuilder: (context, view) {
        return ListTile(title: Text(view.item.title));
      },
    ),
  ],
)
```


`<String, Task>` is `<TKey, TItem>`: the key type that identifies a node, and
your payload type. Keys must be unique across the whole tree, not just among
siblings.

### The rebuild convention

Every rebuild re-diffs the tree against the collection you passed. To keep an
ancestor that rebuilds often from paying that walk for nothing, the diff is
skipped when the collection is the `identical` instance as last time. This is
the `ListView.children` convention: mutating a list in place is not observed,
so pass a **new instance** to signal a change.

The extractor callbacks (`keyOf`, `childrenOf`, `parentOf`) are excluded from
that check, because an inline lambda is a fresh closure on every build and
would defeat it entirely. They must be pure functions of their input.

---

## 2. Picking an input mode

Three constructors, differing by where the structure lives.

| Constructor | Structure lives in | Use when |
| --- | --- | --- |
| `.hierarchy(roots:, keyOf:, childrenOf:)` | your own nested objects | you display data you do not restructure in the UI |
| `.flat(items:, keyOf:, parentOf:)` | your own flat list plus parent keys | same, but your model is flat |
| `SyncedSliverTree(tree: ...)` | a nested `SyncedTreeNode` tree | the UI edits structure |

This tutorial uses the default constructor with an app-owned model, for a
reason that pays off in section 7: when the UI edits structure, the app must
own root order, payloads, and sibling order itself, and derive the widget
input from that model once per change.

```dart
class _TaskTree {
  const _TaskTree({
    required this.roots,
    required this.dataByKey,
    required this.childrenByParent,
  });

  final List<String> roots;
  final Map<String, Task> dataByKey;
  final Map<String, List<String>> childrenByParent;
}

_TaskTree _initialModel() {
  return const _TaskTree(
    roots: <String>["plan", "build", "ship"],
    dataByKey: <String, Task>{
      "plan": Task(id: "plan", title: "Plan"),
      "plan.scope": Task(id: "plan.scope", title: "Agree the scope"),
      "plan.budget": Task(id: "plan.budget", title: "Draft a budget"),
      // ...
    },
    childrenByParent: <String, List<String>>{
      "plan": <String>["plan.scope", "plan.budget"],
      // ...
    },
  );
}
```

The derived input is rebuilt once per CHANGE, not once per build, so the
identity rebuild gate keeps ancestor rebuilds free:

```dart
_TaskTree _model = _initialModel();
late List<SyncedTreeNode<String, Task>> _treeInput = _buildTreeInput();
```

Every mode validates at sync time: dangling keys, duplicate children, a node
under two parents, cycles, and (in `.flat`) unreachable nodes all throw
`ArgumentError` naming the offending key rather than misrendering later.

---

## 3. Building a row

`itemBuilder` receives a `TreeItemView`, which is the node plus everything a
row usually wants to know:

| Member | What it gives you |
| --- | --- |
| `key`, `item`, `depth`, `parentKey`, `isRoot` | identity and position |
| `hasChildren`, `childCount`, `liveChildCount`, `hasLiveChildren` | child state |
| `isExpanded`, `expand()`, `collapse()`, `toggle()` | expansion |
| `indexInParent`, `siblingCount`, `isFirst`, `isLast` | live-space sibling position, for connector lines and rounded-group styling |
| `indent` | this row's horizontal offset in pixels |
| `controller` | the underlying `TreeController`, as an escape hatch |

"Live space" means positions among siblings that are not currently animating
out. `indexInParent` returns -1 while the row itself is animating out.

### Indentation is not your job

Set `indentWidth` on the widget and the render layer offsets each row by
`depth * indentWidth` and narrows it by the same amount. Do **not** also add
`EdgeInsets.only(left: depth * indentWidth)` in your builder, or you will
indent twice.

```dart
SyncedSliverTree<String, Task>(
  tree: _treeInput,
  indentWidth: 20.0,
  itemBuilder: _buildRow,
)
```

`indentWidth` defaults to `0.0`, which renders a visually flat tree. That
default also disables x-aware drop-depth selection (section 8), so set it.

### The row body

```dart
Widget _buildRow(BuildContext context, TreeItemView<String, Task> view) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(8.0, 3.0, 8.0, 3.0),
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Notch(),           // section 7
          Row(
            children: <Widget>[
              SizedBox(
                width: 40.0,
                child: view.hasChildren
                    ? IconButton(
                        iconSize: 20.0,
                        icon: Icon(
                          view.isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                        ),
                        onPressed: view.toggle,
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(child: Text(view.item.title)),
            ],
          ),
        ],
      ),
    ),
  );
}
```

---

## 4. Expansion policy

- `initiallyExpanded` (default `true`) applies to the whole tree on the first
  sync, and to nodes that gain their first children later.
- `initialNodeExpansion: (key, item) => bool?` overrides it per node. Return
  null to defer to the blanket flag. It is an **initial** policy: a user's
  later toggle always wins.
- `preserveExpansion` (default `true`) remembers expansion across
  remove/re-add cycles, bounded by `maxExpansionMemorySize`.
- `onExpansionChanged(key, isExpanded)` fires for user toggles, imperative
  calls and sync-driven expansion alike. It deliberately stays silent for the
  widget's own initial expansion pass, so restoring persisted state does not
  immediately ask you to overwrite it.

---

## 5. Reaching the controller

Some things no row builder can do: scroll to a node, expand or collapse
everything from a toolbar, read expansion state to persist it.

```dart
TreeController<String, Task>? _tree;

SyncedSliverTree<String, Task>(
  // ...
  onControllerCreated: (controller) {
    // Runs during initState, after the first sync and the initial
    // expansion pass. Store it; do not call setState here.
    _tree = controller;
  },
)
```

The widget owns that controller. Do not dispose it. Imperative structural
mutations through it are legal and compose with syncing, but your input
collection stays authoritative: the next sync diffs against it and reverts
structural drift.

---

## 6. Turning on drag-and-drop

Reorder is one nullable object. Passing a non-null `TreeReorderConfig` **is**
enabling the feature, and the only required member is `onReorder`.

```dart
SyncedSliverTree<String, Task>(
  // ...
  reorder: TreeReorderConfig<String>(
    onReorder: _onReorder,
  ),
)
```

With nothing else set, every row becomes draggable after a long press,
because `buildDefaultDragHandles` defaults to true and wraps each row in a
`TreeDelayedDragHandle`. That is the `ReorderableListView` default, and it is
the right one for touch.

Two rules about the config object:

- **Its presence is fixed for the widget's lifetime.** Swapping between null
  and non-null changes the widget type at that slot, tearing down the sliver,
  its per-key child caches and its render object, and orphaning any live drag.
  A debug assert catches it. To disable reordering at runtime, keep the config
  and return false from `canReorder`.
- **Its contents are live on every rebuild.** The drag tunings
  (`autoExpandDelay`, `autoScrollEdgeZone`, `autoScrollMaxVelocity`) are
  captured once per drag session, so a changed value applies from the next
  drag rather than retuning a live one.

---

## 7. A custom drag handler

Desktop-targeted apps should turn the default off: a mouse long-press reads as
lag, and there is no visible affordance. Once off, the gesture is yours to
place.

### Step 1: turn the package's handle off

```dart
reorder: TreeReorderConfig<String>(
  onReorder: _onReorder,
  buildDefaultDragHandles: false,
),
```

The row is still wrapped by the package. What it loses is a pointer gesture,
nothing else: it still hides itself while dragged, is still a drop **target**,
and still carries its reorder semantics actions.

### Step 2: put a handle somewhere in the row

```dart
TreeDragHandle(child: yourGrip)
```

That is the whole API. The handle **draws nothing**. It contributes a
pointer-down listener and a grab cursor; the appearance, the size and the
position are entirely yours, and there may be more than one per row.

### The notch

A notch is a grab bar across the top of a card. Because `TreeDragHandle`
draws nothing, the notch is ordinary app code:

```dart
class _Notch extends StatelessWidget {
  const _Notch();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TreeDragHandle(
      child: Container(
        height: 22.0,
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Container(
          width: 34.0,
          height: 4.0,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2.0),
          ),
        ),
      ),
    );
  }
}
```

Drop `const _Notch()` at the top of the card's `Column` and the row is
draggable by that bar and by nothing else. Taps and scrolls anywhere else in
the card behave normally.

Two details that save debugging time:

- The handle's `Listener` is **opaque while armed**, so a grip built from
  widgets that do not hit-test themselves (a bare `SizedBox`, a `Padding`
  around nothing, a `CustomPaint` with no hit-test override) still receives
  the pointer. A grip that renders but never drags is the classic symptom of
  a hand-rolled listener that defers to its child.
- It reads `MediaQuery.maybeGestureSettingsOf` for you, so the touch slop is
  right on Android. A hand-rolled recognizer that skips this is wrong in a way
  a desktop-only test run never shows.

### Immediate or delayed

| Widget | Gesture | Use for |
| --- | --- | --- |
| `TreeDragHandle` | starts as soon as the pointer clears the touch slop | a dedicated grip: a notch, a grip icon, a corner |
| `TreeDelayedDragHandle` | waits for a long press (`kLongPressTimeout`) | wrapping a whole row |

**Do not wrap a whole row in `TreeDragHandle`.** An immediate multi-drag over
the full row claims every pointer that lands on it and the list stops
scrolling. Use `TreeDelayedDragHandle` for whole-row dragging, which is
exactly what `buildDefaultDragHandles` installs.

### Two handles in one row are safe

A handle owns no recognizer. It reports a single pointer-down to the enclosing
row, and the **row** owns the recognizer, the per-pointer bookkeeping and one
`Drag` per gesture. So a notch on top plus a trailing grip icon is fine: the
last pointer-down wins, and the previous session is cancelled rather than
orphaned. A handle inside a nested scrollable is harmless too, because the
row resolves the drag surface from its own context, not the handle's.

```dart
class _GripIcon extends StatelessWidget {
  const _GripIcon();

  @override
  Widget build(BuildContext context) {
    return TreeDragHandle(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Icon(
          Icons.drag_indicator,
          size: 20.0,
          color: Theme.of(context).hintColor,
        ),
      ),
    );
  }
}
```

### Where you grab changes how the drag feels

With the drag proxy on (the default), slot selection is **card-anchored**: it
probes at the floating card's midpoint rather than at the pointer, so the card
in your hand picks the slot regardless of where you grabbed it. A notch across
the top of an 80px card is grabbed about 11px down, so the probe sits about
29px below your finger. This is what makes a top-edge notch feel correct
instead of one row too high.

### Refusing rows, without changing their shape

`canReorder` is the runtime switch:

```dart
bool _canReorder(String key) {
  return !(_model[key]?.locked ?? false);
}
```

Every handle in a refused row is **disarmed**: its `onPointerDown` goes null
and its listener turns hit-test transparent, so the gesture is free for the
app's own menu, and (as the companion test asserts) a drag started on it
scrolls the list instead. Refusing the row that currently owns a live drag
ends that drag on the next re-resolution.

Two things not to do:

- Do not omit a handle conditionally, and do not flip
  `buildDefaultDragHandles` at runtime. Both change the row's widget **shape**,
  so `Widget.canUpdate` fails and the whole row subtree is re-inflated,
  disposing whatever `State` your builder keeps there (half-typed text fields,
  scroll offsets, in-flight animation controllers). Use
  `TreeDragHandle(enabled: false)`, which can only narrow the package's own
  answer, never widen it.
- Do not hide a grip with `Opacity(opacity: 0.0)`. `RenderOpacity` does not
  override `hitTest`, so a zero-alpha grip still swallows gestures.

To hide the notch on a refused row while keeping the card's height, read the
policy back out of the row's scope instead of asking your own policy twice:

```dart
final canDrag = TreeRowDragScope.maybeOf(context)?.canDrag ?? false;
return Visibility(
  visible: canDrag,
  maintainSize: true,
  maintainAnimation: true,
  maintainState: true,
  child: TreeDragHandle(child: bar),
);
```

`Visibility`'s defaults (`maintainInteractivity: false`,
`maintainSemantics: false`) wrap the hidden bar in `IgnorePointer(ignoring:
true)` and drop it from the semantics tree, which is what makes the reserved
space inert.

---

## 8. The drop

While dragging, rows part to open a live gap at the prospective slot. This
**make-room preview** is paint-only: no structure changes and no sync runs
until the drop commits. The dragged row's in-place copy is hidden so its slot
can close, and the floating proxy is its only representation.

Each candidate row offers three zones: `above`, `into` and `below`. `below` on
an expanded parent resolves as "first child", so the preview and the commit
agree.

### Filtering destinations

```dart
bool _canAcceptDrop({
  required String movingKey,
  String? newParent,
  int? index,
}) {
  if (newParent == null) {
    return true;
  }
  return !(_model[newParent]?.locked ?? false);
}
```

This callback also **shapes** the zones. The shaping query is
`(newParent: thatRow, index: 0)`: refusing index 0 under a row withdraws its
`into` zone entirely, leaving a clean two-zone above/below split rather than a
dead band in the middle. Slots 1..n under it stay reachable by pointing at its
children.

### Drop depth at subtree boundaries

At the right edge of a subtree, one visible slot has several legal depth
expressions ("after this child" or "after its parent" or "after its
grandparent"). The pointer's horizontal position picks between them, mapped as
`floor(x / indentWidth)`.

`TreeReorderConfig.indentWidth` defaults to the widget's `indentWidth`, so
the two agree by construction. A non-positive value disables the hint, and
each zone falls back to its classic default: the deepest legal level for
`below`, the target's own depth for `above`. Note that leaving `indentWidth`
at its `0.0` default disables the hint as a side effect.

### The other drag knobs

- `autoExpandDelay` (default 700ms): hold a card over a collapsed row to open
  it. Live on rebuild; captured per drag session.
- `autoScrollEdgeZone` (48.0) and `autoScrollMaxVelocity` (1200.0): the
  autoscroll band at the viewport edges. Live on rebuild; captured per drag
  session.
- `hapticsOnDrag` (default false): a selection click on lift and on each
  semantic slot change, debounced on the slot identity rather than on raw
  notifications.

---

## 9. The `onReorder` contract

```dart
void _onReorder(String key, String? newParent, int index) {
  setState(() {
    _model = _model.movedTo(key, newParent, index);
    _treeInput = _buildTreeInput();
  });
}

// On _TaskTree. Remove FIRST, then insert at the reported index.
_TaskTree movedTo(String key, String? newParent, int index) {
  final newRoots = List<String>.of(roots)..remove(key);
  final newChildren = <String, List<String>>{
    for (final entry in childrenByParent.entries)
      entry.key: List<String>.of(entry.value)..remove(key),
  }..removeWhere((_, siblings) => siblings.isEmpty);

  if (newParent == null) {
    newRoots.insert(index.clamp(0, newRoots.length), key);
  } else {
    final siblings = newChildren.putIfAbsent(newParent, () => <String>[]);
    siblings.insert(index.clamp(0, siblings.length), key);
  }
  return _TaskTree(
    roots: newRoots,
    dataByKey: dataByKey,
    childrenByParent: newChildren,
  );
}
```

Four rules, each of which fails silently if you miss it.

**The index is live-space and names a position in the FINAL child list**, that
is, after the moved node has been taken out of wherever it was. Remove first,
then insert at the reported index, exactly as `movedTo` above does. Computing
your own index against the pre-removal list puts every same-parent downward
move one slot too far, while cross-parent moves look fine, so it ships green.

**Not recording the move reverts it.** Your input collection stays
authoritative, so a drop your handler ignores is undone by the next sync. That
is the rejection mechanism, not a bug.

**Rollback needs a new collection instance.** Re-emitting the same reference
is not observed, so a rejected move is never rolled back. Success is
unaffected, which makes this an error-path-only trap.

**An async handler must record optimistically before awaiting.** The widget
has already moved the row on screen so the drop animates without a frame of
lag. Record first, then reconcile or roll back on the response.

---

## 10. The drag proxy

A floating preview of the dragged row follows the pointer, anchored at the
grab point. It renders in the **root `Overlay`**, outside the row's original
ancestry, exactly like `Draggable.feedback`. Rows built from Material widgets
therefore need their `Material` ancestor put back:

```dart
Widget _buildDragProxy(BuildContext context, String key, Widget? rowChild) {
  if (rowChild == null) {
    return const SizedBox.shrink();
  }
  return Material(
    type: MaterialType.transparency,
    child: Opacity(opacity: 0.9, child: rowChild),
  );
}
```

`rowChild` is exactly what your builder returned for that row, so any
`TreeDragHandle` inside is cloned too. In the overlay it finds no row scope
and is inert, so it will not start a second drag.

`showDragProxy: false` removes the proxy. Then nothing follows the pointer,
because the make-room preview hides the in-place row; only the opening gap
remains as feedback. Turning it off also changes the drop animation: with the
proxy on, the settle FLIP starts at the proxy's release position and hands off
to the real row mid-flight.

---

## 11. Accessibility

Pointer drags are unusable with a screen reader, so every reorderable row
exposes custom semantics actions automatically: move up, move down, move out,
and move into previous sibling. They are gated by the same `canReorder` and
`canAcceptDrop` policies and report through `onReorder` exactly as a drop
does. A row with no handle keeps all of them.

`semanticsActionsBuilder` transforms that set per row: return a superset to
add actions, a subset to remove them, a re-keyed map to relabel them (the only
way to localize the built-in English labels, since this package has no
localization layer). Labels must be `const` or module-level:
`CustomSemanticsAction` interns identifiers in static maps with no removal
path, so a per-row label leaks one entry per distinct string for the life of
the process.

---

## 12. Animation

`animationStyle` forwards one immutable `TreeAnimationStyle` to the internal
controller. Three families matter while dragging:

| Family | Drives | Falls back to |
| --- | --- | --- |
| `reorderSlide` | the FLIP slides of a committed move | none (300ms linear) |
| `makeRoom` | the gap opening, re-targeting and releasing | `reorderSlide` |
| `dropSettle` | the proxy settle glide and the cancel return | `reorderSlide` |

A drag session resolves the style **once** at `startDrag`, so restyling
mid-drag applies from the next drag. Per-family `Duration.zero` is a kill
switch that dominates explicit per-call durations;
`TreeAnimationStyle.disabled` zeroes everything, which is the synchronous
configuration for tests.

---

## 13. Checklist

- The widget is a sliver: put it in a `CustomScrollView`.
- Pass a **new** collection instance to signal a change.
- Set `indentWidth`, and do not indent again in your builder.
- `reorder` may not be added or removed after construction; use `canReorder`.
- Dedicated grip: `TreeDragHandle`. Whole row: `TreeDelayedDragHandle`.
- Disarm with `canReorder` or `enabled: false`, never by omitting the handle.
- Hide a grip with `Visibility`, never with `Opacity(0.0)`.
- `onReorder`'s index is live-space and final-list. Record the move, or it is
  reverted.
- Give the drag proxy a `Material` ancestor in a Material app.
- Do not dispose the controllers handed to you by `onControllerCreated`.
