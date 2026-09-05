# 2026-09-01 make-room track sizing checklist

Plan: plans/2026-09-01-make-room-track-sizing-plan.md, stamped
ready-to-implement after 7 revision rounds and a KEPT trial.

- Landing Order numbers steps 0 to 4 with a 3b, so phase mapping is
  1 -> Phase 1, 2 -> Phase 2, 3 and 3b -> Phase 3, 4 (docs, NOT
  INDEPENDENTLY VERIFIABLE: prose) -> Phase 4.
- The trial commit 7305ca8 on branch `make-room-track-sizing-trial`
  already landed C1, C2 and C3 plus seven cases. Always check
  `git log --oneline -1` before assuming a plan's stated HEAD.
- A docs-only step marked NOT INDEPENDENTLY VERIFIABLE can still carry a
  concrete acceptance: enumerate the named sites and give a grep that
  shows the falsified claim is gone.
