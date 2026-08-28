# AGENTS.md

Canonical agent instructions for this repository. Other agent tools read
this file directly; Claude Code reaches it by importing it from
`CLAUDE.md`. Edit this file for anything that should apply to every agent,
and keep it self-contained: do not use import directives here, because not
every tool that reads this file expands them.

## Project Overview

A Flutter package (`widgets_extended`) providing rich utility widgets. Two modules:

- **sliver_tree**: a high-performance sliver-based tree widget with animated expand/collapse, FLIP reorder slides, node diffing, drag-and-drop reordering, and sticky headers.
- **sectioned_sliver_list**: a sectioned list (sections + items) built on top of the sliver_tree stack (`SectionedListController` wraps a `TreeController` + `TreeSyncController` with section/item-typed keys).

The barrel file `lib/widgets_extended.dart` re-exports both modules.

## Commands

```bash
# Run all tests
flutter test

# Run a single test file
flutter test test/sliver_tree/tree_controller_test.dart

# Analyze (lint)
flutter analyze
```

## Code Quality
- Always take a research-first approach: read the code before describing it. See "Verified claims".
- Prefer correct, complete implementations over minimal ones.
- Use appropriate data structures and algorithms; don't brute-force what has a known better solution.
- When fixing a bug, fix the root cause, not the symptom.
- If something I asked for requires error handling or validation to work reliably, include it without asking.
- Do not be biased. Disagree with the user on any claims that are wrong. Be brutally honest at all times.

## Verified claims

Never assert anything about code, APIs, or behavior that you have not checked in this session. This applies equally to chat replies, plans, design documents, audits, code comments, and commit messages.

- **Cite what you assert.** A claim about existing code carries the `file:line` you actually read. No citation means it was not verified, which means it does not get written.
- **Counts come from commands.** Files affected, tests affected, call sites, "N places do X", how much work something is: run the search and use its output. Never approximate a number you could have measured.
- **Framework behavior is read, not recalled.** What a widget builds, what a recognizer fires on disposal, what a default resolves to: verify against the Flutter or Dart source before stating it. Recall of framework internals is a hypothesis, not a fact.
- **Before changing a shared declaration, enumerate its users.** Interfaces, abstract classes, mixins, exported symbols: list every implementer and call site, including tests, before proposing or making the change.
- **Do not invent risks.** A regression, hazard, or failure mode is either demonstrated (a failing test, a traced code path) or labelled unverified. A plausible-sounding risk stated as a finding costs more time than it saves.
- **Tool and subagent output is a lead, not a finding.** Confirm it against the source yourself before repeating it as established.
- **Causal clauses carry their own citation.** A "because", "so", "therefore", or any statement of what the framework does is the highest-risk claim in a write-up, not the lowest. Observing an outcome does not license explaining it: cite the line that states the mechanism, or delete the clause. Absolutes ("never", "only", "exactly", "cannot", "every") get the same treatment. Put the citation immediately after the claim it supports rather than elsewhere in the sentence, so a reader can tell which claim it backs.
- **Do not claim a plan, an audit, or a colleague got something wrong until you have run their check.** If their statement was verified and yours is inferred, theirs stands. This is the one error that also destroys someone else's correct work, so it carries the strictest bar.
- **Keep write-ups short enough to verify.** A status note or summary says what changed, what was checked, and how it was checked. Every additional explanatory sentence is another claim that someone has to verify, so length is a cost, not a sign of rigor.

When something is unverified and still worth saying, mark it in the sentence that carries it: "unverified", "I have not checked this", "this needs a test". A stated gap is useful. A confident guess is a defect, and it is worse than saying nothing, because it reads exactly like a fact.

Prefer running the check to reasoning toward the answer. A grep, a test run, or `flutter analyze` settles a mechanical question faster and more reliably than argument does. When a change is small and its failure modes are compile errors or failing tests, implement it rather than reason further about it.

## Code Style

- Always use double quotes `"` for string literals, except for imports; use single quotes `'` on imports.
- Always create braces for code blocks.
- Always use block bodies where possible.
- Never use em-dashes, en-dashes, icons, emoji, or any other non-plain-text symbol (arrows, bullets beyond Markdown's own `-`, trademark, copyright, registered, degree, etc.) in code, comments, documentation, changelogs, commit messages, or chat replies. Use plain ASCII punctuation: a colon, semicolon, comma, parenthesis, or a separate sentence in place of a dash.
- Never add Claude, Claude Code, or Anthropic as a co-author, author, or attribution anywhere. No `Co-Authored-By` trailers, no "Generated with" lines in commit messages, PR descriptions, changelogs, or file headers.

## Architecture: sliver_tree

### Conventions that cut across every layer

- **nids (ECS-style storage).** Every key is assigned a dense integer node id (`NodeIdRegistry`, LIFO free list; nids are recycled). All per-node state lives in dense nid-indexed arrays (`Int32List`/`Float64List`/`Uint8List`) grown in lockstep via `onCapacityGrew`. Hot paths use `*Nid` method variants to avoid key hashing.
- **Live-space index contract.** Every public `index` parameter (`insert`, `insertRoot`, `moveNode`) and every read-side index API (`getIndexInParent`, `liveRootKeys`, `getLiveChildren`, `reorderRoots`/`reorderChildren` validation) speaks **live space**: positions among non-pending-deletion siblings. Exiting (mid-remove) siblings are skipped. Conversion to the raw sibling lists happens once at the write boundary (`_liveIndexToFullInsertIndex`). `getIndexInParent` is O(1) amortized via a generation-validated cache (`_live_index_cache.dart`): every raw-sibling-list-mutating method calls `_liveIndexCache.bump()` AFTER its write clusters (exit placement is load-bearing, user comparators read mid-mutation; see the component doc), pending-deletion flips bump via the two controller forwarders, and a new mutator must add its bump AND join the oracle fuzz's script (`live_index_oracle_fuzz_test.dart`).
- **Two notification channels.** Structural changes fire `addStructuralListener(Set<TKey>? affectedKeys)` (null = full refresh, empty = handled by create/GC, non-empty = exactly these rows may differ); pure data updates fire `addNodeDataListener(TKey)`. `affectedKeys` covers any change to a row's *rendered* inputs (data, depth, raw child-list length, and live child count; pending-deletion marking dirties the parent), not only `hasChildren` flips. Structural subsumes data; never fire both for one row. A third channel, `addAnimationListener`, ticks per frame during animations (coalesced to one dispatch per frame; the slide engine's settle notify is deliberately uncoalesced).
- **Coordinate spaces.** Three distinct spaces, and mixing them produces errors that are invisible while scrolled to the top:
  - **Sliver scroll space** ("sliver-local"): distance from the start of the tree sliver's scroll extent, first row at 0. This is the `ReorderRenderPort` contract (`findRowAtPaintedY`, `beginSlideBaseline`, `TreeDropTarget.targetPaintedY`/`targetExtent`) and what `SliverTreeParentData.layoutOffset` stores.
  - **Sliver paint space**: sliver scroll space minus `constraints.scrollOffset`. Used by paint, clipping, hit-testing, and `_anchorPaintedBounds`.
  - **Viewport scroll space**: sliver scroll space plus `constraints.precedingScrollExtent`. Consumers subtract `position.pixels` to reach viewport-local. `TreeDropTarget` carries no viewport-space field of its own; presentation layers derive one from the semantic target plus `ReorderRenderPort.precedingScrollExtent`.
- **Declare an animation's family ONCE, at the boundary.** Every code path that installs an animation decides its `TreeAnimationStyle` family at exactly one named site; the install call that resolves its spec and computes its kill-switch flag (`animateSlideFromOffsets` = reorderSlide; `animateDropSettleGlide` = dropSettle; the preview methods = makeRoom; mutator gates = expandCollapse/enterExit; the two standalone installers, `_startStandaloneEnterAnimation` and `_startStandaloneExitAnimation`, take a required `family` argument that is stored on the `AnimationState` and resolved through `TreeAnimationStyle.specFor` at tick time, so a mutator's partial reversals and nested exits run on the mutator's family, not on `enterExit`). Downstream code (engine, render, collaborators) never re-derives family membership. A new consumer whose family differs from the API it rides gets an internal-use-only channel (house precedent: `animateDropSettleGlide`), never a public flag parameter. This is the containment rule for the family-misrouting bug class the style system introduced.

### Core layers (bottom-up)

- **types.dart**: Shared types: `TreeNode<TKey, TData>`, `AnimationState`, `SlideAnimation`, `AnimationGroup`, `OperationGroup`, `BulkAnimationData`, `SliverTreeParentData`, `StickyHeaderInfo`.
- **NodeStore** (`_node_store.dart`): Structural component store: the `NodeIdRegistry` plus dense per-nid arrays for data, parent, children, depth, expansion, and the ancestors-expanded cache. Fires `onParentChanged` on every `setParent`.
- **VisibleOrderBuffer** (`_visible_order_buffer.dart`): The flattened visible order as a dense nid array + reverse index + visible-subtree-size cache (O(1) `subtreeSizeOf`, O(depth) `bumpFromSelf`). Bulk protocols are owned by intention-revealing methods (`rebuild`, `removeContiguousRange`, `purgeCompact`, `reindexFrom`); raw views are read-only for hot paths. Suppression (`runWithSubtreeSizeUpdatesSuppressed`) lets callers pre-bump the cache and batch compactions.
- **AnimationCoordinator** (`_animation_coordinator.dart`): Facade over the five animation sources, cross-source per-nid state (full extents, pending-deletion), the union mirrors, and the (per-frame coalesced) animation-listener channel. Implements `AnimationReader`, the narrow interface the render layer binds to. Cross-source capture/teardown (`captureAndRemoveFromGroups`, `removeFromAllSources`) lives here; single copies, reached via controller forwarders. Sub-animators: **StandaloneAnimator** (per-node enter/exit, one ticker; zero duration = snap-to-completion), **OperationGroupRegistry** (per-expand/collapse `AnimationController`s), **BulkAnimator** (one scalar group for expandAll/collapseAll), **SlideAnimationEngine** (paint-only FLIP deltas; settle protocol: notify with deltas at 0 *before* cleanup, plus one post-cleanup notify so listeners observe the active to idle transition; in-place composition is guarded by `installStamp`), and **ReorderPreviewEngine** (`_reorder_preview_engine.dart`: paint-only HELD make-room offsets; animate to a non-zero target and persist until re-targeted/released; composed with slide deltas at the controller's `getSlideDeltaNid`/`hasActiveSlides`/`maxActiveSlideAbsDelta` delegators, guarded to one bool check when inactive). **Three carve-out accessors read FLIP-only or preview-only state** (`hasActiveFlipSlides`, `getFlipSlideDeltaNid`, `getHeldPreviewDeltaNid`), at exactly twenty-one read locations across five categories, eighteen FLIP-only and three preview-only (recipe: `grep -rn "hasActiveFlipSlides\|getFlipSlideDeltaNid\|getHeldPreviewDeltaNid" lib` minus the three declarations in `tree_controller.dart` and every doc-comment mention; whoever changes the inventory re-runs the recipe and writes what it returns). **(a) Edge-ghost LIFECYCLE**, eight of them: `GhostRegistry.pruneSettled`'s criterion, the install-side in-flight predicate in `GhostRegistry.applyClampAndInstallNewGhosts` (asks whether the ENGINE holds a slide to compose against; the composed `slideY` beside it stays, it feeds painted-position arithmetic), the two `clearAll` gates in `RenderSliverTree` (Step 9 and layout Step 0b), Pass A's edge-ghost skip and the ghost paint pass's settled-skip (exact complements: the set Pass A skips is the set Pass A.6 paints), `applyPaintTransform`'s edge-ghost `useGhost` gate (mirrors those two), and `SliverTreeElement._onAnimationTick`'s settle-transition layout. **(b) RETENTION and EVICTION**, three: the two gates in `SliverTreeElement._scheduleStaleEviction` and the delta clause in `RenderSliverTree.isNodeRetained`. Same reason in both: a preview offset is HELD, so a composed read never goes idle for the length of a drag. **(c) EXIT-ghost LIFECYCLE**, six: the ghost and anchor reads in `RenderSliverTree`'s Step 0a prune (`_pruneSettledPhantomExitGhosts`), the same pair in the Pass A.5 per-ghost paint gate, and the same pair again in `applyPaintTransform`'s exit-ghost branch, which must mirror the paint gate or `localToGlobal` reports a position nothing paints; same PAIR rule as (a). **(d) EXIT-ghost GEOMETRY**, three `getHeldPreviewDeltaNid` reads: the non-pinned branch of the exit ghosts' shared painted base (`_exitGhostPaintedBaseScrollSpace`) and the two consume-time destinations. These are not "choose a half", they are "the anchor's settled position", which under a held preview is structural + preview; the sticky-pinned branch deliberately has no such term, because a pinned header paints at `pinnedY` with no delta. **(e) SCROLL-CORRECTION RE-ENTRANCY**, one `hasActiveFlipSlides` read: the `correctionsAllowed` gate in `RenderSliverTree.performLayout`, which decides whether a layout may ABORT AND RE-RUN at a different scroll offset (the once-per-frame pre-Pass-1 slide pipeline cannot replay); FLIP-only because a held preview never goes idle, and the composed flag would refuse every correction for the whole of a drag. For (b) that suspended eviction for the whole drag and pinned every row an autoscroll passed (2000 rows, 200 frames: 18 mounted became 143); it is sound only because layout ADMITS preview-shifted rows (`RenderSliverTree.admittedSlideBound`, see the render-layer entry), so those rows are retained by the ordinary cache-region check instead. The prune criterion and the paint skip are a PAIR and must always read the same delta: one decides whether a row stays a ghost, the other whether it paints as one, and splitting them makes a row vanish for a frame (preview cancels a live FLIP delta) or paint at a displaced edge after retiring (preview offset on a finished slide). A ghost is an artifact of a FLIP slide, and a preview offset is HELD, so composing the two there kept settled ghosts alive for a whole drag and forced every drop-target lookup onto the O(N) full scan. Everything else, painted positions, painted-truth baselines, hit-testing, overreach, stays composed. The settle-transition branch fires on EITHER the FLIP or the composed transition: dropping the composed disjunct loses the post-settle layout when a preview releases with no FLIP active.
- **TreeController** (`tree_controller.dart` + part files `_tree_controller_animation.dart`, `_tree_controller_helpers.dart`): Central state manager tying store + order + animations together. Animation timing/easing lives in ONE immutable `TreeAnimationStyle` (`animation_style.dart`, mutable `animationStyle` property): five families, `expandCollapse` (op groups, bulk, the animated-concurrent scroll gate), `enterExit` (inherits expandCollapse), `reorderSlide` (all FLIP slides), `makeRoom`/`dropSettle` (inherits reorderSlide). Uniform defaults 300ms/`Curves.linear` (`TreeAnimationStyle.defaultSpec`). Per-family zero is a KILL SWITCH that dominates explicit per-call durations (`TreeAnimationStyle.disabled` = everything off; there is no master switch). The zero rule is SPLIT: a zero family CREATES no motion (installs refused; other families' in-flight slides survive and re-base across concurrent mutations), while DISABLING (restyling `reorderSlide` to zero) STOPS in-flight slide motion at the transition (`SlideAnimationEngine.purgeActive`, called from the `animationStyle` setter). Per-call `Duration?`/`Curve?` params on `moveNode`/`reorderRoots`/`reorderChildren`/`animateSlideFromOffsets`/the preview methods resolve null to family spec. Sync-layer moves/reorders pass `expandCollapse` explicitly for same-batch cohesion. Mutators (`setRoots`/`setChildren`/`insert`/`insertRoot`/`remove`/`moveNode`/`expand`/`collapse`/`expandAll`/`collapseAll`/`reorderRoots`/`reorderChildren`), `runBatch` (defers order rebuild + notifications to batch exit; mutators flush via `_ensureVisibleOrder` on entry), and the **ScrollOrchestrator** (`_scroll_orchestrator.dart`: `animateScrollToKey` immediate/animated modes, full-extent prefix cache; every scroll it starts is single-flight in both directions (L13); a scroll issued during animations rides the concurrent follower and waits for quiescence, and a not-yet-laid-out mutation costs one frame's wait instead of a clamp to stale `maxScrollExtent` (H3); landings are re-derived by a post-frame settle snap, paired with the render object's anchor-preserving `scrollOffsetCorrection` (H1); `avoidStickyHeaders` insets the target below the sticky band its pinned ancestors will form, `stickyInsetOf` exposes the same number (M20); cancellation wired through `dispose`). Inserting/moving under a pending-deletion parent throws `StateError` in all build modes.
- **RenderSliverTree** (`render_sliver_tree.dart`): Custom `RenderSliver`: viewport-aware layout (cache-region admission via `LayoutAdmissionPolicy`, bulk-only cumulative fast path), paint passes (static rows, sliding rows by |delta|, exit ghosts, edge ghosts, header repaint, sticky), hit-testing that matches paint z-order during slides, sticky headers via `StickyHeaderComputer`, and the slide pipeline. FLIP slides consume a staged baseline (`SlideComposer` = `SlideBaselineSlot` (first-wins) + `GhostRegistry` (edge ghosts)); exit ghosts are consolidated `_ExitGhost` records (anchor, slidUp, edge XOR clipped). Paint/hit-test/semantics iteration is viewport-bounded; slide-only ticks are paint-only (layout runs on install/settle, and on a tick whose `composedSlideAbsDeltaBound` exceeds the `admittedSlideBound` the last layout recorded, which is how a make-room preview's shifted rows get built). Rows are wrapped in `RepaintBoundary` by default (`addRepaintBoundaries`).
- **SliverTreeElement** (`sliver_tree_element.dart`): Custom element implementing `TreeChildManager`: lazy child creation during layout callbacks, dirty-key targeted rebuilds (a hot reload queues every mounted row for the same in-place refresh in both ancestor shapes; nothing recreates rows on reload, M26), dead-node GC and post-frame stale eviction (gated on FLIP slides, not the composed flag; respects `isNodeRetained`: pins, sticky, ghosts, mid-FLIP rows).
- **SliverTree** (`sliver_tree_widget.dart`): The core `RenderObjectWidget`. Takes a `TreeController` and a `nodeBuilder`.

### Higher-level widgets

- **TreeSyncController** (`tree_sync_controller.dart`): Diffing layer on top of TreeController. Diffs the desired state against **controller truth** (`liveRootKeys`/`getLiveChildren`; there is no private tracking mirror), so direct controller mutations (escape hatch, drag-drop commits) compose safely with syncs. Preserves expansion state across remove/re-add cycles, defers cross-parent movers, validates cycles/duplicate keys in `childrenOf`, and exact-match early-outs per parent.
- **SyncedSliverTree** (`synced_sliver_tree.dart`): Declarative widget owning both controllers internally; three input modes (tree/hierarchy/flat; `.nodes` and `.snapshot`/`TreeSnapshot` were removed in 0.0.33, see `CHANGELOG.md:137-138`). Input normalization and its validation live in `_synced_input_normalizer.dart` (public names, barrel non-exported). Skips the re-diff when mode inputs are `identical` across rebuilds (pass new collection instances to signal change). The auto-expand heuristic (`_sync_helpers.dart`) never overrides a user's deliberate collapse (expansion memory + emptied-while-collapsed suppression).
- **TreeReorderController / SliverReorderableTree** (`tree_reorder_controller.dart`, `sliver_reorderable_tree.dart`): Drag-and-drop reordering. The controller (`TreeReorderController<TKey>`, key-only) talks to the render layer exclusively through **`ReorderRenderPort<TKey>`** (`reorder_render_port.dart`, implemented by `RenderSliverTree`: `findRowAtPaintedY`, which skips pending-deletion rows and the make-room LIFTED range (M11), `findPinnedRowAtPaintedY`, which the probe consults first so a pointer inside a pinned band resolves the header (L21; pending-deletion filter only, no lifted skip), `paintedRowBounds`, pin/unpin, `beginSlideBaseline`, `precedingScrollExtent`, and `crossAxisGlobalOrigin`/`crossAxisExtent`, the tree sliver's own cross-axis frame, which the drag proxy's band and the depth hint's `sliverX` read instead of the viewport's (M17)) and keeps only public API, policy, notification channels (coalesced `ChangeNotifier` + per-move `pointerPosition` ValueListenable), and the explicit commit script; drag animation timing is NOT owned here; it inherits `treeController.animationStyle` (`reorderSlide` for the commit baseline, `effectiveMakeRoom` for the gap, `effectiveDropSettle` for the glides), resolved once per session at `startDrag` (`endDrag` re-resolves + validates before staging/committing, exception-safe via `finally`; `startDrag` returns false for policy refusals (including a defunct scrollable at start) and throws only for cross-controller misuse). Everything per-drag lives in the session architecture (`_drag_session.dart` + `_drag_session_behaviors.dart`, public class names, barrel non-exported): `DragSession` owns the single `resolve()` choreography site (one `PointerSpace.sample` per event, direct collaborator calls) and the single `detachAll(SessionExit)` teardown site; `PointerSpace` is the ONLY component touching the scrollable (nullable reads; null sample = defunct scrollable; it also owns the scroll subscription and re-points it at a swapped `ScrollPosition` on every sample, with `TreeReorderController.notifyScrollableChanged` as the widget-level edge trigger from the dragged row's `didChangeDependencies` (M25)); `DragProbe` owns grab geometry + the touch-first probe shift + the resolution core; behaviors are `AutoScroller` (per-session ticker), `DwellExpander` (`autoExpandDelay`), `MakeRoomDriver` (gap-hold; `snapForCommit` stays a named commit-script op), and `DropSettler` (release-position FLIP override / cancel return-glide). Zone semantics live in **`DropZoneResolver`** (`_drop_zone_resolver.dart`): three zones (`above`/`into`/`below`; `below` on an expanded parent resolves as first-child so preview and commit agree), live-space `indexInFinalList`, and an x-aware ancestor-depth candidate chain at subtree right-boundaries (`preferredDepth` hint, clamped; filtered candidates fall back to the next-nearest level). The semantic `TreeDropTarget` carries sliver-local row geometry; the widget derives drag-proxy presentation, exposes reorder semantics actions, and unconditionally drives the **make-room preview** (the only drop-feedback paradigm; there is no indicator line; while the drag proxy is shown the dragged subtree's in-place rows are sized placeholders so their slots can close and row content is inflated exactly once, in the proxy (H5: row `State` is recreated at lift and drop unless the row content carries a `GlobalKey`), and with the proxy off they stay live under a shape-stable `Visibility` hide, which adds no compositing layer and excludes focus (M19)); paint-only held offsets in `_reorder_preview_engine.dart`, composed with FLIP slide deltas at the `TreeController` read delegators so painted positions, painted-truth FLIP baselines (seamless commit handoff), hit-tests, retention, and overreach see one combined offset with zero render-layer awareness.
- **TreeNodeBuilder** (`tree_node_builder.dart`): Selective-rebuild widget that only rebuilds when a specific node's `hasChildren` or `isExpanded` state changes.

### Usage patterns

- **Imperative**: Create `TreeController` with a `TickerProviderStateMixin`, call `setRoots`/`setChildren`/`insert`/`remove`/`expand`/`collapse` directly, wrap in `SliverTree`.
- **Declarative diffing**: Use `SyncedSliverTree` with one of its three input modes.
- **Manual sync**: Use `TreeSyncController` with `syncRoots`/`syncChildren`/`syncMultipleChildren` for custom sync logic.
- **Drag-and-drop**: Use `SliverReorderableTree` with a shared `TreeReorderController`; every row from `nodeBuilder` is wrapped for reorder unconditionally.

## Architecture: sectioned_sliver_list

`SectionedListController<K, Section, Item>` adapts the sliver_tree stack to a two-level sections/items model using wrapped keys (`SectionKey`/`ItemKey`). Item keys must be globally unique across sections (sync-time validation rejects duplicates). The widget layer mirrors `SyncedSliverTree`'s declarative shape.

## Testing Patterns

- Controller tests use `testWidgets` with `tester` as the `TickerProvider` and `animationStyle: TreeAnimationStyle.disabled` for synchronous behavior.
- **Pin family-flow, not literal timings.** Animation tests assert that a call consumes the CONFIGURED family's spec (set a distinctive spec, observe it govern), not hardcoded durations/curves; literal pins are reserved for tests whose subject IS a default value. This is why the 0.0.32 uniform-defaults flip broke zero tests.
- Widget tests wrap `SliverTree` in `MaterialApp > Scaffold > CustomScrollView`.
- Uses `flutter_test`; no third-party test dependencies.
- Perf contracts are pinned via debug counters on the render object / controller (`debugLastPaintIterationCount`, `debugLastParentDataCumulativeBuilds`, `debugPerformLayoutCount`, `debugOrderResetIndexAllCount`, ...).
- The invariant-heavy suites (fuzz/purge/zombie) enable `TreeController.debugFullConsistencyChecks = true`; everywhere else debug builds run only an O(changed-range) inline check per mutation.

### Repro-test methodology (house convention)

Bug fixes are test-driven with promoted repros: write a test that asserts the EXPECTED (correct) behavior so it FAILS on unfixed code (with setup sanity assertions proving the claimed path is genuinely exercised), land the fix, confirm the test passes, and keep it in `test/sliver_tree/` as the regression test. The 2026-07 audit's repro batch (`audit_repro_*_test.dart`) followed this flow end to end.

**Every new assertion must be shown to fail.** "The test fails on unfixed code" is not enough, because one assertion can carry the whole failure while its neighbours are inert. Construct the state each individual assertion is meant to reject and watch that assertion go red. An assertion that cannot fail in the direction it claims to check is a defect even when the test as a whole discriminates, and a setup sanity assertion that cannot fail is worse than none, because it reads as proof that the path was exercised.

## Plans and audits

Design and implementation plans live in `plans/` as `YYYY-MM-DD-<topic>-plan.md`.

**Before writing OR auditing one, read `plans/AUDIT-METHOD.md` first.** It is
the house method, derived from two multi-round audits, and it is not
reconstructable by reasoning: it carries the angle list to sweep, the stopping
rule (two clean passes measure the lens, not the artifact), the one-normative-site
rule, the requirement that counts and universal claims carry the command that
establishes them, and the trial discipline (apply the fix, run the gates, keep
the diff). Auditing without it reliably produces a plan that reads correct and
fails on contact.

Plan citations are bare `path:line` and are verified by a generated ledger, not
by eye. After any change under `lib/`, or any edit to a plan:

```bash
python plans/check_citations.py plans/<plan>.md --update   # record
python plans/check_citations.py plans/<plan>.md            # verify, exits non-zero on a miss
```

Spell each cited path one way: repo files by bare filename (`render_sliver_tree.dart:4215`),
Flutter SDK files as `<subdir>/<file>.dart:NNN` (`rendering/viewport.dart:973`). A
bare `` `:123` `` continuation attaches to the last file named in full, so naming a
file in prose and then citing bare lines silently misattributes them.
