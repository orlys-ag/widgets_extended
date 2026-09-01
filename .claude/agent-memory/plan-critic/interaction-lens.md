# interaction lens (fresh angle: the feature crossed with every source/pass/mutator/entry point)

Board and tree plans in this repo copy `lib/sliver_tree/`'s drag and animation
layers wholesale. The recurring hole is a NAME copied without its CROSSING.
Cheap mechanical sweeps that reproduce:

1. **Every field of a copied config object needs a named consumer.** Grep each
   field name; a field appearing only in its own declaration and its own field
   list is a feature with no behaviour. Recurring offenders in copied drag
   configs: `dragProxyBuilder`, `hapticsOnDrag`, `canDropAt`, `resizeEdges`.
2. **Every resource in a teardown/lifecycle table needs a creator.** Grep the
   resource name; a hit only in the teardown row means it was copied from the
   tree's session behaviours (`DwellExpander`, `AutoScroller`) into a module
   with no job for it.
3. **Check the resolution surface's TYPE against the features riding it.** A
   drop resolver that returns an integer cell cannot express a resize edge, a
   fractional snap, or a span. Compare the resolver's return type against every
   callback signature the config declares (`onItemResized(TKey, BoardSpan)`,
   `canDropAt(TKey, BoardSpan)`, `BoardSnap.fraction`).
4. **Semantics actions bypass the pointer session.** A plan that makes the
   commit script the single site that fires `onItemMoved`, and makes `startDrag`
   require a render port plus a global pointer position, has no route for a
   semantics-only move even when an acceptance criterion demands one.
5. **Pinned/frozen/sticky bands are crossed with cells and forgotten for
   items.** Check the paint-plane list, the placement rule, the drop probe and
   the autoscroll edge zone separately; a plan usually covers the first and
   silently drops the other three.
6. **A stated "wrong value until X" residue names its containment in terms of
   LAYOUT.** Grep for the other consumers of that value (scroll target
   derivation, `applyContentDimensions`); they usually read it off-window,
   which is exactly the case the containment argument excludes.
7. **A gesture path named in prose with no recognizer** (e.g. "the selection
   gesture path") is never crossed with `Scrollable`'s own drag recognizers
   (`scrollable.dart:789`, `scrollable.dart:812`), which a two-dimensional
   scroll view installs on both axes.
