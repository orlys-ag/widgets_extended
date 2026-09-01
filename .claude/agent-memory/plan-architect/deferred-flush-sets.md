# Deferred work behind a dirty set: one set per flush, never shared

Stable pattern for any plan that defers work (lane resolution, sort-on-exit,
cache rebuilds) behind a "dirty" collection flushed on demand.

## The defect: two flushes sharing one set

A flush that CLEARS the set ends the other consumer's work permanently. It is
invisible on inspection because both mechanisms are individually correct and
the shared-set sentence reads as an optimisation ("it reuses the dirty set X
already maintains").

The board plan hit this exactly: a bulk index-registration path appended
unsorted and marked buckets dirty in the LANE resolver's set, intending to
sort at the call's exit. The lane flush runs from the entry of every
lane-reporting read AND from the affected-key computation, so one read between
the appends and the exit emptied the set. The bucket then stayed unsorted with
a stale span bound while every later query binary-searched it and silently
returned a subset. Forever, because nothing else marks a bucket dirty.

## What a plan has to state

- **One set per flush, named on its owner.** If two mechanisms want the same
  bucket keys, they get two sets. Sharing is only safe if the two flushes have
  identical trigger sets, which is rarely true and never stays true.
- **One flush site per set**, and its call sites enumerated. The safe shape is
  the same one the tree's `_ensureVisibleOrder` uses: flush from the entry of
  every READ that reports the deferred value, plus from the batch exit. Both
  arms, because the entry arm is what makes a mid-batch read safe and the exit
  arm is what keeps the cost one pass rather than one per interleaved read.
- **The batch exit runs in a `finally`.** A throwing batch body otherwise
  leaves the structure half-built with no later site that would finish it, and
  mutators that throw on caller error (unknown key, duplicate key) make that a
  routine path rather than an exotic one.
- **Whether the two mechanisms are ORDER-independent.** If one sorts its own
  working list, it neither requires nor disturbs the other's stored order, and
  the plan can say no flush ordering is needed. If it reads the stored order,
  the ordering becomes a fifth rule someone has to hold.

## The falsification a test has to make

Both implementations sort eventually, so a plain query assertion cannot
discriminate. The discriminating case is: inside the batch, perform the READ
that clears the shared set, let the batch exit, then query and compare against
a linear oracle. Add a second arm that throws from inside the batch body,
catches, and asserts the same query still matches.

## The NOTIFICATION set is a third mechanism, and it needs its own accumulator

Splitting the sort set from the lane set is not enough. The structural
notification's affected-key derivation ("which keys did this mutation change
the derived value for?") cannot ride the dirty set either, for the same reason
and one more:

- every flush CLEARS the dirty set, and the derivation's own flush arm is one
  of the flushes, so by the time it looks the set is empty;
- the resolve has already OVERWRITTEN the old derived values, so there is
  nothing left to compare the new ones against.

The fix is an accumulator, not a third dirty set: the resolve writes the ids
whose derived value actually CHANGED, at the one moment both the old and the
new value are in hand. Nothing clears it; the notification DRAINS it. State
the drain's timing explicitly, because it is the question an implementer
answers wrong: once per mutator outside a batch, exactly once at batch exit
inside one, and always AFTER that reader's own flush, since the flush is what
puts the current mutation's changes into the accumulator.

An empty affected-key set is not neutral: in this repo's channel contract it
means "no built child's output changed", so a derived-value-only change (a
lane count with an unchanged span) never reaches its item.

