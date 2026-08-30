#!/usr/bin/env python3
"""Verify and re-anchor `path:line` citations in a plan's live sections.

Why this exists: plan citations are bare line numbers, which rot silently
when the cited file moves. One commit in the session that produced these
plans shifted `tree_controller.dart` by 8 lines. This records the content
each citation pointed at when it was verified, then checks it still does,
and tells you the new line when it does not.

Usage:
    python plans/check_citations.py plans/<plan>.md            # verify
    python plans/check_citations.py plans/<plan>.md --repoint  # fix moved lines
    python plans/check_citations.py plans/<plan>.md --update   # (re)record

`--repoint` is the one to reach for after implementation work. Editing
`lib/` shifts every citation below the edit, and almost all of that drift
is a stale NUMBER against text that still exists: this rewrites the plan's
line numbers to where the recorded text actually is now, then re-records.
It only moves a citation whose text is found at exactly ONE place, so a
citation whose text was deleted, or now appears twice, is reported and
left alone for a human. Those are the ones that mean the plan is wrong.

Do NOT reach for `--update` to make a failing verify pass. It re-records
whatever currently sits at the line numbers the plan states, so on drifted
code it anchors every citation to the wrong text and then reports clean.

Reads only the LIVE sections; everything from "## Audit log" onward is
history and is deliberately skipped. Writes/reads a sidecar ledger at
<plan>.citations.tsv, which is a DERIVED artifact: regenerate it, never
hand-edit it.

Exit status is 1 when any citation fails to verify, so this can gate CI.
"""

from __future__ import annotations

import re
import sys

# Cited source lines contain non-ASCII (em dashes, arrows). On Windows the
# default console encoding is cp1252, so printing them raises
# UnicodeEncodeError as soon as stdout is a pipe rather than a UTF-8
# terminal -- which is exactly what happens under a hook or in CI.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SDK_SRC = Path("C:/flutter_sdk/flutter/packages/flutter/lib/src")
LEDGER_SUFFIX = ".citations.tsv"
TOKEN_LEN = 60

FULL = re.compile(r"`([A-Za-z0-9_/-]+\.(?:dart|md)):(\d+)(?:-(\d+))?`")
BARE = re.compile(r"`:(\d+)(?:-(\d+))?`")

# Directories a bare markdown filename must never resolve into.
SKIP_DIRS = {".git", ".dart_tool", "build", "examples", "__pycache__"}


def live_text(plan: Path) -> str:
    text = plan.read_text(encoding="utf-8")
    marker = "## Audit log"
    return text.split(marker)[0] if marker in text else text


def resolve(rel: str) -> Path | None:
    """Map a citation path to a file on disk.

    Dart: bare filenames are repository sources under lib/; anything
    with a directory component is a Flutter SDK path under lib/src.

    Markdown is always repository-relative instead, because the
    agent-instruction documents that cite each other live outside lib/
    (the repository root, doc/agents/, and plans/). Routing a slashed
    .md path to the SDK the way a slashed .dart path goes would never
    resolve.
    """
    if rel.endswith(".md"):
        if "/" in rel:
            candidate = REPO / rel
            return candidate if candidate.is_file() else None
        hits = sorted(
            path for path in REPO.glob(f"**/{rel}")
            if not SKIP_DIRS.intersection(path.parts)
        )
        return hits[0] if len(hits) == 1 else None
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


# A recorded token can stop matching while the construct it names is alive and
# unmoved in spirit. Two ways, both observed on the row-transition plan:
#
#   * The house ASCII sweep rewrote comment punctuation, so `dispatch - never`
#     replaced `dispatch <em-dash> never` and every token containing one broke.
#   * The token is a TOKEN_LEN cut, so an edit at character 60 changes it while
#     the line still starts identically.
#
# Both leave a long, intact PREFIX. Matching on that recovers the citation;
# demanding a unique hit keeps it from guessing. The cut at the first non-ASCII
# character is what makes the first case work, since the rewrite lands there.
PREFIX_MIN = 20
PREFIX_MAX = 45


def prefix_key(token: str) -> str | None:
    cut = len(token)
    for i, ch in enumerate(token):
        if ord(ch) >= 128:
            cut = i
            break
    key = token[: min(cut, PREFIX_MAX)].rstrip()
    return key if len(key) >= PREFIX_MIN else None


def find_by_prefix(path: Path, token: str) -> list[int]:
    key = prefix_key(token)
    if key is None:
        return []
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return [i for i, line in enumerate(lines, 1) if line.strip().startswith(key)]


def read_ledger(ledger_path: Path) -> dict[tuple[str, int], str]:
    expected: dict[tuple[str, int], str] = {}
    for row in ledger_path.read_text(encoding="utf-8").splitlines():
        if not row.strip():
            continue
        rel, line_no, token = row.split("\t", 2)
        expected[(rel, int(line_no))] = token
    return expected


def repoint(plan: Path, ledger_path: Path) -> int:
    """Rewrite citation line numbers to where the recorded text now is.

    Only the LIVE sections are touched, matching what the checker reads;
    the audit log keeps the numbers that were true when it was written.
    A citation moves only when its recorded text is found at exactly one
    line, because anything else is a guess and this edits the plan.
    """
    if not ledger_path.is_file():
        print(f"no ledger; run with --update first ({ledger_path.name})")
        return 2

    expected = read_ledger(ledger_path)
    text = plan.read_text(encoding="utf-8")
    marker = "## Audit log"
    live, tail = (text.split(marker, 1) + [""])[:2]

    edits = []           # (start, end, replacement)
    relocated = {}       # (rel, old_line) -> new_line, for the ledger rewrite
    claimed = {}         # (rel, new_line) -> token, to catch collisions
    moved = ambiguous = deleted = collided = 0
    current = None
    notes = []

    for m in re.finditer(f"{FULL.pattern}|{BARE.pattern}", live):
        if m.group(1):
            current, start_s, end_s = m.group(1), m.group(2), m.group(3)
        elif current is not None:
            start_s, end_s = m.group(4), m.group(5)
        else:
            continue

        rel, line_no = current, int(start_s)
        want = expected.get((rel, line_no))
        target = resolve(rel)
        if want is None or target is None:
            continue
        if token_at(target, line_no) == want:
            continue

        # Exact first. A prefix hit is only consulted when the exact token is
        # gone from the file entirely, so an unchanged line always wins.
        refresh = False
        hits = find_token(target, want)
        if not hits:
            hits = find_by_prefix(target, want)
            # The recorded text no longer exists anywhere, so carrying it to
            # the new line would drift again on the very next verify. Re-record
            # from what is actually there. Sound only because the prefix match
            # is unique, which is checked immediately below.
            refresh = len(hits) == 1
            if len(hits) > 1:
                ambiguous += 1
                notes.append(f"  AMBIG~   {rel}:{line_no}  prefix now at {len(hits)} lines; left alone")
                continue
        if not hits:
            deleted += 1
            notes.append(f"  DELETED  {rel}:{line_no}  text is gone; the plan may be wrong")
            continue
        if len(hits) > 1:
            ambiguous += 1
            notes.append(f"  AMBIG    {rel}:{line_no}  text now at {len(hits)} lines; left alone")
            continue

        new_line = hits[0]
        if refresh:
            notes.append(f"  MOVED~   {rel}:{line_no} -> {new_line}  matched on prefix; token re-recorded")
        prior = claimed.get((rel, new_line))
        if prior is not None and prior != want:
            collided += 1
            notes.append(f"  COLLIDE  {rel}:{line_no} -> {new_line} already claimed; left alone")
            continue
        claimed[(rel, new_line)] = want

        shift = new_line - line_no
        body = f"{rel}:{new_line}" if m.group(1) else f":{new_line}"
        if end_s is not None:
            body += f"-{int(end_s) + shift}"
        edits.append((m.start(), m.end(), f"`{body}`"))
        relocated[(rel, line_no)] = (new_line, token_at(target, new_line) if refresh else None)
        moved += 1

    if edits:
        backup = plan.with_suffix(plan.suffix + ".bak")
        backup.write_text(text, encoding="utf-8")
        ledger_path.with_suffix(ledger_path.suffix + ".bak").write_text(
            ledger_path.read_text(encoding="utf-8"), encoding="utf-8")
        for start, end, replacement in reversed(edits):
            live = live[:start] + replacement + live[end:]
        plan.write_text(live + (marker + tail if tail else ""), encoding="utf-8")

        # Move ONLY the entries that moved, carrying their original recorded
        # text to the new line. Every other entry is left exactly as it was.
        # Re-recording the whole ledger here would anchor the deleted and
        # ambiguous citations to whatever now sits at their line numbers and
        # report the plan clean, destroying the only evidence that they are
        # the ones a human still has to look at.
        rewritten = []
        for (rel, old_line), token in sorted(read_ledger(ledger_path).items()):
            new_line, fresh_token = relocated.get((rel, old_line), (old_line, None))
            rewritten.append(f"{rel}\t{new_line}\t{fresh_token or token}")
        ledger_path.write_text("\n".join(rewritten) + "\n", encoding="utf-8")
        print(f"repointed {moved} citation(s); backups at "
              f"{backup.name} and {ledger_path.name}.bak")
    else:
        print("repointed 0 citations")
    for note in notes:
        print(note)
    if ambiguous or deleted or collided:
        print(f"left for review: {deleted} deleted, {ambiguous} ambiguous, {collided} collided")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    plan = Path(sys.argv[1])
    update = "--update" in sys.argv
    record_new = "--record-new" in sys.argv
    ledger_path = plan.with_suffix(plan.suffix + LEDGER_SUFFIX)

    repointing = "--repoint" in sys.argv
    if repointing:
        code = repoint(plan, ledger_path)
        if code != 0:
            return code
        # Fall through to VERIFY, never to --update. repoint has already
        # written the ledger, moving only what it moved; a full re-record
        # here would re-anchor the citations it deliberately left alone.
        # The verify pass below is what proves the rewrite landed, and it
        # still reports the deleted and ambiguous ones as drifted, which is
        # correct: those are real findings, not bookkeeping.

    cites = citations(live_text(plan))
    unique = sorted(set(cites))
    print(f"{len(cites)} citations ({len(unique)} distinct) in {plan.name}")

    if record_new:
        # Add rows ONLY for citations the ledger has never seen, and never
        # rewrite or drop an existing one. That is the whole difference from
        # --update, and it is what makes correcting a citation BY HAND safe:
        # the corrected one needs recording, while --update would re-anchor
        # every drifted neighbour to whatever now sits at its line number.
        existing = read_ledger(ledger_path) if ledger_path.is_file() else {}
        before = len(existing)
        added, skipped = [], []
        for rel, line_no in unique:
            if (rel, line_no) in existing:
                continue
            target = resolve(rel)
            token = token_at(target, line_no) if target is not None else None
            if not token:
                skipped.append((rel, line_no))
                continue
            existing[(rel, line_no)] = token
            added.append((rel, line_no))
        rows = [f"{rel}\t{ln}\t{tok}" for (rel, ln), tok in sorted(existing.items())]
        ledger_path.write_text("\n".join(rows) + "\n", encoding="utf-8")
        print(f"recorded {len(added)} new citation(s); {before} existing row(s) untouched")
        for rel, line_no in added:
            print(f"  NEW      {rel}:{line_no}")
        for rel, line_no in skipped:
            print(f"  SKIPPED  {rel}:{line_no}  (unresolved path, blank line, or out of range)")

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

    expected = read_ledger(ledger_path)

    ok = drifted = missing = 0
    for rel, line_no in unique:
        want = expected.get((rel, line_no))
        if want is None:
            print(f"  NEW      {rel}:{line_no}  (not in ledger; rerun --record-new)")
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
