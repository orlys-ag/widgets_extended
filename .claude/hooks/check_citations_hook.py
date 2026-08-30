#!/usr/bin/env python3
"""Stop hook: report plans whose `path:line` citations have drifted.

`AGENTS.md` asks for `plans/check_citations.py` to be run after any change
under `lib/`. Asking is context, not enforcement, which is how a plan's
ledger goes stale without anyone noticing. This runs the checker for every
plan that has a ledger and surfaces the result once, at the end of a
session.

ADVISORY ONLY. It never blocks: drift mid-work is normal, and a hook that
stops a session for an expected condition gets disabled rather than
heeded. It emits a `systemMessage` and exits 0 either way.

A plan is watched iff it has a `plans/<plan>.md.citations.tsv` ledger
beside it. To stop watching a landed plan whose citations are pinned to
the tree as it was, remove or rename its ledger; the plan text should then
say which commit its citations are against.
"""

import glob
import json
import os
import subprocess
import sys

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

LEDGER_SUFFIX = ".citations.tsv"

# Must compose with the hook timeout in .claude/settings.json (120s):
# PER_PLAN_TIMEOUT * plans must stay under it, or the hook is killed
# mid-run and reports nothing. 20s x 5 plans = 100s. A plan is checked
# in well under a second today; this is the runaway bound, not the cost.
PER_PLAN_TIMEOUT = 20
MAX_PLANS = 5


def main() -> int:
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    checker = os.path.join(root, "plans", "check_citations.py")
    if not os.path.isfile(checker):
        return 0

    problems = []
    # NEWEST FIRST. Plan filenames lead with YYYY-MM-DD, so a plain sort is
    # chronological and `[:MAX_PLANS]` would check the oldest and drop the plan
    # actually being worked on. The feature-implementation workflow adds a plan
    # and a ledger per run, so this cap gets hit in normal use.
    ledgers = sorted(
        glob.glob(os.path.join(root, "plans", "*" + LEDGER_SUFFIX)), reverse=True)
    skipped = max(0, len(ledgers) - MAX_PLANS)
    for ledger in ledgers[:MAX_PLANS]:
        plan = ledger[: -len(LEDGER_SUFFIX)]
        if not os.path.isfile(plan):
            continue
        try:
            done = subprocess.run(
                [sys.executable, checker, plan],
                capture_output=True, timeout=PER_PLAN_TIMEOUT, cwd=root,
                # encoding/errors, not text=True: text=True decodes with the
                # LOCALE encoding, which is cp1252 on Windows, and the
                # checker echoes cited source lines that contain non-ASCII.
                # Without this the hook itself raises UnicodeDecodeError.
                encoding="utf-8", errors="replace")
        except (OSError, subprocess.SubprocessError):
            continue
        if done.returncode == 0:
            continue
        # Last line is the summary: "ok N, drifted N, unrecorded N".
        tail = [ln for ln in (done.stdout or "").splitlines() if ln.strip()]
        summary = tail[-1] if tail else "check failed"
        problems.append("%s (%s)" % (os.path.basename(plan), summary))

    if problems:
        tail = "" if not skipped else " (%d more ledger(s) not checked)" % skipped
        print(json.dumps({"systemMessage":
            "Plan citations need attention in %d plan(s): %s%s. "
            "Re-run `python plans/check_citations.py <plan>` to see them, or "
            "`--repoint` to fix the ones that are only a moved line number. "
            "A landed plan should have its ledger retired instead (AGENTS.md)."
            % (len(problems), "; ".join(problems), tail)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
