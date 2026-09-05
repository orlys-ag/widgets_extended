# Latched model geometry over an in-flight animator state

## The shape

A render object has two sources for one painted quantity:

- the MODEL value (an axis extent recorded by layout), and
- an ANIMATOR state that interpolates a `from`/`to` captured at install
  and is what paint reads while it is in flight.

Some arm then decides to make the quantity MODEL-DRIVEN: "this term IS
the animation now, so record it every pass and install nothing". In the
board that is `_sizeContentTracks`'s latch arm (`enterExitRamping`, and
after the make-room plan `|| makeRoomContributes`), which records and
`continue`s.

The defect: a latch that records per tick is only correct on a track the
animator holds NO state for. If a state is in flight when the latch takes
the track, every recorded value is invisible (paint keeps interpolating
the stale `from`/`to`, and a re-target cannot reach it because the arm's
own `continue` puts the only install site out of reach), the content the
term was sized for paints outside its track for the rest of the state's
duration, and the quantity POPS to the last recorded value when the state
is dropped at `t >= 1`.

## What to require in a plan

1. **Name the edge.** The rule fires on the pass the latch TAKES the
   track (the latch set does not yet contain it), not per tick. Per tick
   is the thing the latch arm exists to avoid.
2. **Hand the state IN, do not re-target it.** Finalizing lands the track
   at the target the model already stores, so the step is bounded by the
   resize's remaining distance and the frame after it is settled truth.
   Re-targeting per tick keeps paint continuous but leaves it LAGGING the
   model for the whole episode, which is the original defect softened
   rather than removed, and it re-installs once per tick.
3. **Make the door a no-op when there is no state**, so the call site
   needs no float residue test. A residue test also has to be evaluated
   before the record, because the record moves the value it compares
   against.
4. **State it as a PAIR invariant**: while the latch entry stands, the
   animator holds no state for that track. Three readers depend on it
   (paint, the hand-off arm's `from` capture and its residue term, and
   any query that reads the recorded axis), and each fails silently.
5. **Price the accepted step** in Risks and record it as the ONE
   exception to whatever continuity goal the plan states.
6. **Check the engine-wide union flag.** `hasLayoutDrivingAnimations` is
   `trackResize.hasActive || enterExit.hasActive`, so a finalize can flip
   it false. Show what still drives layout for the rest of the episode.
7. **Layout safety of the door.** The finalize runs inside layout, so it
   must dispatch nothing: the module's `finalizeAll` clears maps and
   calls `_stopIfIdle`, and `Ticker.stop` only unschedules a frame
   callback and completes its futures. An install from inside layout is
   already precedent in the same arm, so starting a ticker there is not
   the new exposure; notifying would be.

## Reach across a library boundary

The animator lives in an underscore library the render object cannot
name, so the door is a forwarder on the controller with the module's
"Internal-use channel for the render object; not part of the supported
surface" doc. Same precedent as the install and the offset-shift read.
See `unexported-engine-routes.md`.

## Inherited halves

The same hole usually exists for the OTHER contributor that shares the
latch arm (in the board: enter/exit ramps). Fixing only the half the plan
introduces is defensible when the other half is pinned by existing tests,
but the asymmetry must be NAMED as inherited and out of scope, or a later
reader reads it as an oversight and "fixes" it into a behaviour change.

## Testing it

Construct the in-flight state rather than racing a mutation for one: the
controller's existing internal channel installs a state without touching
the model, so the sizing walk's ordinary arm still compares stored to
stored and installs nothing. Setup sanity is then two lines: the
engine-wide "has active" flag is true, and the painted extent reads the
state's own interpolation and not the stored value. Choose a duration
that outlives the whole gap so the scratch's pop lands after the last
assertion and each target assertion fails on its own.
