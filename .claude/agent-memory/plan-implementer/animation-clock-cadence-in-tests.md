# Animation clock cadence in widget tests

Written after the 2026-09-01 make-room track sizing trial, where a plan's
predicted numbers for a settle residue were unreachable and the case it
named as a pin would have passed without discriminating.

## The first tick after `Ticker.start()` reports elapsed 0

`Ticker._tick` does `_startTime ??= timeStamp` and calls
`_onTick(timeStamp - _startTime!)`, so the FIRST callback after a start
carries elapsed `Duration.zero`. Every animation source in this
repository derives its per-tick delta as `elapsed - _lastElapsed` with
`_lastElapsed` reset to zero at the start, so that first callback
advances the clock by NOTHING.

Consequences when writing a timed case:

- `pump(Duration(milliseconds: N))` immediately after an install lands
  the clock at 0, not at `N / duration`. Reaching `N` costs an extra
  bare `pump()` first. Every timed case in
  `make_room_track_sizing_test.dart` is written `pump()` then
  `pump(step)`.
- A source that STOPS its ticker at a settle and starts it again on the
  next install pays the zero tick again, so a close's frame sequence is
  one longer than its duration divided by the step.
- `binding.pump` only runs a frame when `hasScheduledFrame`, so an
  install that neither notifies nor starts a ticker produces no frame at
  all and the case is silently vacuous.

## Pick a step that divides the duration in BINARY

Deltas accumulate as `t += dt / duration` in double precision. 50ms into
300ms is `1/6`, and six additions sum to 0.9999999999999999, which is
BELOW the `t >= 1.0` settle test. The settle then lands one frame later
than the arithmetic says, and by that frame the value has already reached
its target, so any assertion about the residue at the hand-off measures
zero. 50ms into 400ms is 0.125 and eight additions are exactly 1.0.

This matters most for cases whose subject is what happens ON the settle
frame: a latch hand-off, a settle-time record, a removal that steps a
term. Those are exactly the assertions that pass for the wrong reason
when the cadence slips, because both the fix and the scratch produce a
zero residue.

## The check that catches it

Run the case against the scratch it names, not only against the unfixed
tree. A settle-frame case that reads identically on both is not a pin,
whatever it asserts. Dumping the per-frame value with `debugPrint` in a
throwaway probe test costs one run and shows the cadence directly; the
trial above found the defect that way in a single pass.

## Frame phases the test binding runs

`AutomatedTestWidgetsFlutterBinding.pump` flushes microtasks, runs
`handleBeginFrame`, flushes microtasks AGAIN, then runs
`handleDrawFrame`. A coalesced dispatch scheduled as a microtask from
inside a ticker callback therefore reaches its listeners BEFORE layout in
the same frame, so a `markNeedsLayout` from a tick lands that frame. An
uncoalesced `notifyNow` from a ticker does the same synchronously.
