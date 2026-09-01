# surface lens gotchas (widgets_extended)

- **Underscore-prefixed files CAN be exported here.** The board module's own
  declaration table (`plans/2026-08-29-board-view-requirements.md:1216`,
  section 9.7) marks `_board_axis.dart`, `_board_span.dart` and
  `_board_animation_coordinator.dart` as exported. Do NOT file "public symbol
  in an underscore file is unexported" against a board plan; check the
  requirements' 9.7 table first. (The sliver_tree module is the opposite: every
  barrel export in `lib/sliver_tree/sliver_tree.dart:13-40` names a
  non-underscore file, and `AnimationReader` at
  `_animation_coordinator.dart:55` is public-but-unexported.)
- **Route-across-library-boundary is the recurring surface hole.** A plan that
  says "engine X's install method is called from controller Y's session" has to
  declare a forwarder on the one EXPORTED object that bridges them. Tree
  precedent: `TreeController.setReorderPreview` (`tree_controller.dart:1818`),
  `clearReorderPreview` (`:1973`), `animateDropSettleGlide` (`:1752`),
  `animateSlideFromOffsets` (`:1723`). Check reads AND writes; plans tend to
  enumerate only the read side.
- **`ReorderRenderPort.drivesController(Object)`** (`reorder_render_port.dart:63`)
  is what makes `startDrag`'s cross-controller `ArgumentError`
  (`tree_reorder_controller.dart:271`) implementable. A copied port interface
  that omits it cannot honour the copied throw contract.
- **`const C.none();` with uninitialized nullable final fields is a compile
  error** (`final_not_initialized_constructor`), verified with
  `dart analyze` this session. Nullability does not exempt a final field.
- **The render layer's WRITE route runs through the controller, not the reader
  interface.** `AnimationReader` (`_animation_coordinator.dart:55-81`) is reads
  only; every install the render object performs is a public `TreeController`
  member: `render_sliver_tree.dart:1415` calls `controller.animateSlideFromOffsets`
  (`tree_controller.dart:1723`) and `render_sliver_tree.dart:2645` calls
  `controller.setFullExtent` (`tree_controller.dart:2012`). Cheap check for any
  plan that installs from inside layout:
  `grep -oE 'controller\.[a-zA-Z_]+' lib/sliver_tree/render_sliver_tree.dart | sort -u`.
- **The FLIP/preview carve-out accessors are NOT in `_animation_coordinator.dart`.**
  `grep -n hasActiveFlipSlides lib/sliver_tree/_animation_coordinator.dart` returns
  nothing; all three are declared on the controller
  (`tree_controller.dart:1199`, `:1212`, `:1497`). A plan citing them "beside the
  composed reads" in the coordinator has the file wrong.
