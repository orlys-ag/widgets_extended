#!/usr/bin/env python3
"""Verify and re-anchor `path:line` citations in a plan's live sections.

Why this exists: plan citations are bare line numbers, which rot silently
when the cited file moves. One commit in the session that produced these
plans shifted `tree_controller.dart` by 8 lines. This records the content
each citation pointed at when it was verified, then checks it still does,
and tells you the new line when it does not.

Usage:
    python plans/check_citations.py plans/<plan>.md            # verify
    python plans/check_citations.py plans/<plan>.md --update   # (re)record

Reads only the LIVE sections; everything from "## Audit log" onward is
history and is deliberately skipped. Writes/reads a sidecar ledger at
<plan>.citations.tsv, which is a DERIVED artifact: regenerate it, never
hand-edit it.

Exit status is 1 when any citation fails to verify, so this can gate CI.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SDK_SRC = Path("C:/flutter_sdk/flutter/packages/flutter/lib/src")
LEDGER_SUFFIX = ".citations.tsv"
TOKEN_LEN = 60

FULL = re.compile(r"`([A-Za-z0-9_/]+\.dart):(\d+)(?:-(\d+))?`")
BARE = re.compile(r"`:(\d+)(?:-(\d+))?`")


def live_text(plan: Path) -> str:
    text = plan.read_text(encoding="utf-8")
    marker = "## Audit log"
    return text.split(marker)[0] if marker in text else text


def resolve(rel: str) -> Path | None:
    """Map a citation path to a file on disk.

    Bare filenames are repository sources; anything with a directory
    component is a Flutter SDK path under lib/src.
    """
    if "/" in rel:
        candidate = SDK_SRC / rel
        return candidate if candidate.is_file() else None
    hits = sorted(REPO.glob(f"lib/**/{rel}"))
    return hits[0] if len(hits) == 1 else None


def citations(text: str) -> list[tuple[str, int]]:
    """Every (path, line) in document order.

    A bare `:NNN` citation attaches to the most recently named file,
    which is how these plans write follow-on references.
    """
    found: list[tuple[str, int]] = []
    current: str | None = None
    for match in re.finditer(f"{FULL.pattern}|{BARE.pattern}", text):
        if match.group(1):
            current = match.group(1)
            found.append((current, int(match.group(2))))
        elif current is not None:
            found.append((current, int(match.group(4))))
    return found


def token_at(path: Path, line_no: int) -> str | None:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    if not 1 <= line_no <= len(lines):
        return None
    return lines[line_no - 1].strip()[:TOKEN_LEN]


def find_token(path: Path, token: str) -> list[int]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return [i for i, line in enumerate(lines, 1) if line.strip()[:TOKEN_LEN] == token]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    plan = Path(sys.argv[1])
    update = "--update" in sys.argv
    ledger_path = plan.with_suffix(plan.suffix + LEDGER_SUFFIX)

    cites = citations(live_text(plan))
    unique = sorted(set(cites))
    print(f"{len(cites)} citations ({len(unique)} distinct) in {plan.name}")

    if update:
        rows, unresolved = [], []
        for rel, line_no in unique:
            target = resolve(rel)
            if target is None:
                unresolved.append((rel, line_no, "unresolved path"))
                continue
            token = token_at(target, line_no)
            if token is None:
                unresolved.append((rel, line_no, "line out of range"))
                continue
            rows.append(f"{rel}\t{line_no}\t{token}")
        ledger_path.write_text("\n".join(rows) + "\n", encoding="utf-8")
        print(f"recorded {len(rows)} -> {ledger_path.name}")
        for rel, line_no, why in unresolved:
            print(f"  SKIPPED {rel}:{line_no}  ({why})")
        return 1 if unresolved else 0

    if not ledger_path.is_file():
        print(f"no ledger; run with --update first ({ledger_path.name})")
        return 2

    expected = {}
    for row in ledger_path.read_text(encoding="utf-8").splitlines():
        if not row.strip():
            continue
        rel, line_no, token = row.split("\t", 2)
        expected[(rel, int(line_no))] = token

    ok = drifted = missing = 0
    for rel, line_no in unique:
        want = expected.get((rel, line_no))
        if want is None:
            print(f"  NEW      {rel}:{line_no}  (not in ledger; rerun --update)")
            missing += 1
            continue
        target = resolve(rel)
        if target is None:
            print(f"  NOFILE   {rel}:{line_no}")
            missing += 1
            continue
        got = token_at(target, line_no)
        if got == want:
            ok += 1
            continue
        drifted += 1
        moved = find_token(target, want)
        where = f" -> now at line {moved[0]}" if len(moved) == 1 else ""
        print(f"  DRIFTED  {rel}:{line_no}{where}")
        print(f"             expected: {want}")
        print(f"             found:    {got}")

    print(f"ok {ok}, drifted {drifted}, unrecorded {missing}")
    return 1 if (drifted or missing) else 0


if __name__ == "__main__":
    sys.exit(main())
