# timing lens

Frame-clock facts this repo's plans keep getting wrong, each verified in the
SDK rather than recalled.

- **The first tick of a ticker started outside a frame advances nothing.**
  `Ticker.start` sets `_startTime` only when the scheduler phase is between
  idle and postFrameCallbacks (`scheduler/ticker.dart:202-205`), and `_tick`
  does `_startTime ??= timeStamp` then `_onTick(timeStamp - _startTime!)`
  (`scheduler/ticker.dart:271-277`). Both board animators additionally reset
  `_lastElapsed = Duration.zero` at start and tick on `dt = elapsed -
  _lastElapsed` (`_track_resize_animator.dart:116-121`, `:129-131`;
  `_make_room_engine.dart:266-269`, `:284-291`), so a ticker started from a
  test body burns one frame at dt 0. House protocol is `pump(); pump(d);`
  (`track_resize_test.dart` and the make-room seed file both do it). A plan
  row that says "pump 100ms" and predicts a mid-flight value is a frame short.
- **A bare `pump()` elapses no clock.** `binding.dart:2252-2258` elapses only
  when `duration != null`, and the frame timestamp is `_clock.now()`, so the
  next frame hands every ticker the SAME timestamp. Any "still X one frame
  later" assertion aimed at catching an in-flight animation is inert unless
  the second pump carries a duration.
- **Microtasks drain between the two frame halves in tests**
  (`binding.dart:2257-2260`), so a coordinator dispatch coalesced into a
  microtask from the transient phase still registers a post-frame callback
  that runs in the SAME frame. Coalesced-vs-synchronous does not change
  same-frame-ness of post-frame work.
- **The animation channel is the only route to per-frame drag work.** A frame
  whose extents change with no animation source ticking dispatches nothing:
  `animateTrackResize` refuses under a zero family before creating a state or
  a ticker (`_track_resize_animator.dart:62-69`). Any plan that hangs a
  per-frame re-resolve off `addAnimationListener` has a zero-family hole.
- **The scroll correction uses SETTLED geometry only.** The anchor is the
  first already-measured track in the visible range and both sides of the
  subtraction are `axis.offsetOf` (`render_board_viewport.dart:679-702`,
  `:820`), and `_animatedOffsetOf`/`_animatedExtentOf` say so
  (`:611-616`). So an animator change cannot feed the correction loop, but a
  RECORDED term change can, and `_sizeContentTracks` runs once per obtain
  round inside the correction loop (`:802` inside `:714` inside `:465-488`).
  `debugCorrectionCount` and `debugLastCorrectionPassCount` (`:473`, `:489`)
  are the seams nobody uses; `track_resize_test.dart`'s fourth case is the
  house template for off-window extent behaviour (scroll out, settle
  off-window, scroll back, assert on the first visible frame).
