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

- **Board reader/barrel facts, so a surface pass does not re-derive them.**
  `BoardAnimationReader` is exported at `board.dart:13`, the barrel shows 38
  names, and `BoardAnimationCoordinator` (`_board_animation_coordinator.dart:76`)
  is its ONLY implementer anywhere (`grep -rn "implements BoardAnimationReader"
  lib test examples` returns one line; `examples/` holds one board file and it
  never touches `.anim`). `test/board/board_barrel_test.dart:25-60` only lists
  `Type` literals, so widening the interface needs no test change and no barrel
  edit. Every animation source is reached as a PUBLIC field of the coordinator
  (`makeRoom`, `slide`, `trackResize`, `enterExit`, `:139-142`), so a controller
  call like `_anim.makeRoom.foo()` compiles without importing the source file.
- **Check what the source class ALREADY has before believing "gains N members".**
  `MakeRoomEngine` already declares `hasActive`, `activeIds`, `deltaOf` and
  `bound` (`_make_room_engine.dart:91-137`); a plan proposing a reader forward
  named `makeRoomDeltaOf` is adding one reader member, not one engine member.
  Same check for the entry points: `previewGap` returns early on a null lane
  axis (`:153`) and again inside its snap arm (`:220`), and `releasePreview`
  returns on `_held.isEmpty` (`:229`), so new engine state that is not a held
  offset is unreachable through those doors unless the plan says the guards
  change.

- **The board module's test-seam idiom is `debug*`, NOT `@visibleForTesting`.**
  `grep -rn '@visibleForTesting' lib/board` returns nothing while `lib/` has 19;
  `grep -rhoE '\bdebug[A-Z][A-Za-z0-9_]*' lib/board --include=*.dart | sort -u`
  returns 14, and they are not all counters: `debugHasIntraTrackItemOn(int)`
  (`board_controller.dart:557`) is a bool predicate and `debugFenwick`
  (`_board_axis.dart:462`) is a state accessor. So a plan that rejects a `debug*`
  seam because "the value is state, not a count" is arguing against a convention
  the module does not have; the real question is whether the observable belongs
  on the EXPORTED `BoardAnimationReader` (`board.dart:13`), which is permanent
  app-facing surface, or behind a `debug` prefix.
- **`MakeRoomEngine.releasePreview` has THREE lib callers, not two.**
  `grep -rn "releaseMakeRoomPreview" lib` returns `board_drag_controller.dart:321`
  (the commit snap, `duration: Duration.zero`), `:399` (`_teardown`), and `:443`,
  the mid-session `canDropAt` REFUSAL release inside `_resolve`. Plans about the
  engine's entry guards keep missing the refusal caller. `previewGap` has exactly
  one lib caller, `board_drag_controller.dart:449`, through
  `BoardController.previewMakeRoomGap` (`board_controller.dart:972`).
- **`clearForId` reaches the engine from three places**, not just the exit
  release: `BoardAnimationCoordinator.clearForId`
  (`_board_animation_coordinator.dart:302`) is called from `finalizeEnterExit`
  (`:287`, `:294`) AND from the recycled-allocation arms
  `board_controller.dart:700` (setItems) and `:765` (addItem). `_store.release`
  has only the two sites inside `finalizeEnterExit` (`:285`, `:292`), each
  followed by `clearForId`, which is why per-id state keyed on a live id cannot
  survive into a recycle.

- **"The internal class is unreachable from a test" is never a valid seam
  justification in the board module.** All 23 board test files import internal
  underscore-prefixed module libraries directly
  (`grep -rln "widgets_extended/board/_" test/board/*.dart` returns 23:
  `_board_axis.dart`, `_board_span.dart`, `_fenwick.dart`, ...). So reaching
  `BoardAnimationCoordinator.makeRoom` (public field,
  `_board_animation_coordinator.dart:142`) from a test needs one import, not a
  contortion. A plan that adds a member to the EXPORTED `BoardAnimationReader`
  (`board.dart:13`) "because the alternative is a cast to an unexported class"
  has mis-priced the alternative; `BoardAnimationReader` is
  `abstract interface class` at `_board_animation_coordinator.dart:34`, so every
  member added there is permanent app-facing surface.
