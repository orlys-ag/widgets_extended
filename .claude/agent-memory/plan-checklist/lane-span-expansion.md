# 2026-09-05 lane span expansion checklist

Plan: plans/2026-09-05-lane-span-expansion-plan.md, ready-to-implement
after round 2 and a KEPT trial.

- Landing Order is 3 steps: 1 restructuring -> Phase 1, 2 (one forced
  commit, C3 to C7) -> Phase 2, 3 docs (NOT INDEPENDENTLY VERIFIABLE)
  -> first item of Phase 4. T11 (widget surface) is the only Phase 3
  item, drawn from step 2's test list, so Phase 3 is not empty without
  inventing work.
- HEAD was already the trial commit 417219a (steps 1 and 2 applied,
  5 of 14 cases). Second time this trap appeared: always run
  `git log --oneline -1` and read the Trial Log first.
- The plan's own Trial Log falsified a step gate: step 1's
  `flutter analyze` clause cannot hold (two unused scratch buffers).
  A gate the plan states but the trial disproved is a non-blocking
  Discovered item, and the phase item must not repeat it as acceptance.
