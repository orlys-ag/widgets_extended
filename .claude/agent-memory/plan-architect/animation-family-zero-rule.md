# The zero rule, per family, and what a style transition actually stops

Stable facts for any plan that copies this repo's `TreeAnimationStyle` family
shape (roots plus families inheriting by unset-ness, per-family zero as a kill
switch).

## The rule splits three ways, not two

1. A zero family CREATES no motion and stops no other family.
2. DISABLING (restyling a live family to zero) STOPS that family's in-flight
   motion at the transition.
3. "Creates no motion" resolves THREE ways, one per family KIND. The
   discriminator is what the family's offset MEANS, NOT whether it is
   paint-only. Writing "paint-only refuses" is the error that gets caught:

   | Kind | Example | A zero family |
   |---|---|---|
   | Transient paint-only | slide, drop settle | REFUSES the install |
   | Held paint-only | make-room preview | INSTALLS and SNAPS to target |
   | State-owning | enter/exit | COMPLETES SYNCHRONOUSLY at mutator entry |

   Refusing a state-owning family strands the state. Refusing a HELD
   paint-only family removes the gap, which is usually the ONLY drop-feedback
   mechanism, and since make-room inherits the slide root a zero root then
   produces a drag with no feedback at all.

## The held family INSTALLS on zero, and the tree shows how

`TreeController.setReorderPreview` derives `resolvedSnap` from
`effectiveMakeRoom.duration == Duration.zero || resolvedDuration ==
Duration.zero` (`tree_controller.dart:1902-1904`), which is the
kill-switch-dominates rule in executable form, and still installs, passing
`snap: resolvedSnap` (`tree_controller.dart:1954`). The engine's snap arm
"applies everything instantly ... and notifies once so paint refreshes"
(`_reorder_preview_engine.dart:174-175`). `clearReorderPreview` snaps clear on
the SAME test (`tree_controller.dart:1992-1995`); install-snap and
release-snap are a PAIR.

**The single notify on each snap arm is load-bearing, not a courtesy.** A
snapped install starts no ticker (`_reorder_preview_engine.dart:198` stops it,
`:199` notifies; the clear does the same at `:297`, `:298`). If a render layer
routes layout off the animation-listener level reads, that one notify is the
ONLY thing that can reach the branch which widens the admitted-offset bound,
so without it the gap opens over children that were never built.

## "It inherits the root, so the root's purge covers it" is FALSE

Inheritance decides which SPEC a family resolves to. It says nothing about
which ENGINE holds the record. Check the source before writing that sentence:

- `TreeController`'s setter purges the FLIP engine alone,
  `_slide.purgeActive()` (`tree_controller.dart:130`), under the comment "no
  other family transition purges (a live drop-settle glide already survives a
  live dropSettle zeroing ...)" (`tree_controller.dart:125`).
- `SlideAnimationEngine.purgeActive` (`_slide_animation_engine.dart:558`)
  clears only its own per-nid map.
- `ReorderPreviewEngine` is a DIFFERENT class with its own ticker
  (`_reorder_preview_engine.dart:80`, `:96`) and its own clear/release entry
  points (`:278`, `:311`). Nothing in the style setter touches it.

So a make-room-style family that inherits the slide root does NOT get cleared
by the slide root's purge. Two honest options, and a plan must pick one:
name a release/snap on that transition, or state the carve-out.

## Held offsets are not "in-flight motion"

The carve-out is usually right. A preview/make-room entry animates to a
non-zero target and is then HELD until re-targeted or released
(`_reorder_preview_engine.dart:76`). Part (2) is about MOTION: the tick-time
zero guard drives a still-travelling entry to its target on the next tick,
which stops the motion at the transition. What remains is a gap the live drag
is holding open, ended by the release call in the session's teardown, not by a
style change. Snapping it shut mid-drag would drop the drop feedback under the
pointer while the session runs on, and the widened admitted-offset bound
staying wide is correct, because the items really are displaced.

## Zeroing a LEAF family stops nothing

The setter compares ROOT families only, so restyling an inheriting family
(drop settle) to zero does not stop a glide already installed. That is the
tree's stated behaviour, not an oversight, and it is acceptable only because
the family is paint-only: the glide lands at the structural position a purge
would have snapped it to a few frames earlier.

## The tick-time guard is the safety net for all of it

Every source maps a zero resolved duration to an INFINITE progress delta
rather than dividing, `eeUs == 0 ? double.infinity : dtUs / eeUs`
(`_standalone_animator.dart:248`), and routes the state "through the normal
completion handler" (`_standalone_animator.dart:244`). That makes the
setter's transition arms an optimisation for the same-frame case rather than
the only thing standing between a restyle and a stranded record.
