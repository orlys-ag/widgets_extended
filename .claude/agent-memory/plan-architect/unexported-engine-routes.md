# Every caller of an unexported engine needs a NAMED controller forwarder

Recurring blocking defect in a plan that puts animation sources in
underscore-prefixed libraries and exposes only a read-only reader interface
off the controller. The table names an installer; nothing declares how the
caller REACHES it; the plan compiles only in prose.

## The test

For each animation source, ask: is its caller in the same library as the
engine? If not, name the public controller member the caller calls. A caller
that cannot NAME the installer is an install that does not happen.

The defect recurs ONCE PER LIBRARY BOUNDARY. Fixing it for the drag layer does
not fix it for the render layer, and vice versa. In the board plan the drag
boundary was found in one round and the render boundary in the next, with the
identical shape.

## The tree's precedent, both boundaries

- Drag layer to private engines, via public `TreeController` members:
  `setReorderPreview` (`tree_controller.dart:1818`), `clearReorderPreview`
  (`tree_controller.dart:1973`), `animateDropSettleGlide`
  (`tree_controller.dart:1752`).
- RENDER layer to the controller, from inside layout:
  `render_sliver_tree.dart:1415` calls `controller.animateSlideFromOffsets`
  (`tree_controller.dart:1723`); `render_sliver_tree.dart:2645` calls
  `controller.setFullExtent` (`tree_controller.dart:2012`) one line after the
  `child.layout` that produced the number (`render_sliver_tree.dart:2644`).

The render object needs NO new handle for this: it already holds the
controller, which is also where it reads the read-only animation view. Adding
a second binding is the wrong fix, because a controller swap then has two
sites.

## How to write it so it stays one normative site

Declare the forwarder as an internal-use channel ("public because it crosses a
library boundary, not part of the supported surface"), and say explicitly that
it FORWARDS AND DECIDES NOTHING. The family declaration, the kill switch and
the re-target rule stay at the engine method. Then the forwarder is a route,
not a second declaration site, and the "declare an animation's family once"
rule is not breached by its existence.

Same-name forwarder and engine method is acceptable and already house style
(the tree's drop-settle glide); qualify with the owning type in prose, and add
one clause at the "exactly ONE install site" claim saying the two same-named
members are not two sites.
