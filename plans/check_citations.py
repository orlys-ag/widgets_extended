#!/usr/bin/env python3
"""Verify `path:line` citations in a plan's live sections against a ledger.

Why this exists: a plan's claims about code are only as good as the reading
behind them, and a citation is the receipt for that reading. The ledger
records the text each citation pointed at when it was read, so a later
check can tell whether the code under a claim has changed since.

Usage:
    python plans/check_citations.py plans/<plan>.md                # verify
    python plans/check_citations.py plans/<plan>.md --verbose      # verify, list MOVED
    python plans/check_citations.py plans/<plan>.md --update       # record a NEW plan
    python plans/check_citations.py plans/<plan>.md --record-new   # record added citations
    python plans/check_citations.py plans/<plan>.md --accept <path:line> ...
    python plans/check_citations.py plans/<plan>.md --repoint      # optional renumbering
    python plans/check_citations.py --self-test                    # the checker's own cases

Any mode takes `--profile <path>`. Without it the project's method profile,
`doc/agents/method-profile.json`, is read when it exists; its `citations`
block names the cited extensions and the SDK root. With no profile the
checker reads `.dart` and `.md` citations against the default SDK root.

Verify sorts every citation three ways. OK: the recorded text is at the
cited line. MOVED: it is elsewhere in the file, so the line number is stale
but the code under the claim still exists. GONE: it is nowhere in the file,
so the code under the claim changed and the claim must be re-read. Only GONE,
and a citation that is unrecorded, does not resolve, or is DANGLING, fails
the check.

A DANGLING citation is a bare `:N` written after a backticked `name.ext:N`
whose extension the profile does not list. It is reported rather than
attached to the last listed file, which is where it would otherwise land.

Run it when a plan is about to be relied on: written, revised, audited or
implemented. Line numbers drifting between those moments cost nothing.

`--accept` is the way out of GONE: after re-reading the code and correcting
the claim and its citation, it re-records exactly the citations named, and
writes nothing if any of them is not a live citation of the plan.

`--update` records a ledger for a plan that has none, and refuses to
overwrite one: on drifted code it would anchor every moved citation to
whatever now sits at its old line number and then report clean.

`--repoint` rewrites the plan's line numbers to where the recorded text is
now, for a reader's convenience; nothing requires it. It moves a citation
only when the text is found at exactly one place. Every file it writes keeps
the line endings it had, and its backups are byte copies.

Reads only the LIVE sections; everything from "## Audit log" onward is
history and is deliberately skipped. The ledger at <plan>.citations.tsv is a
DERIVED artifact: change it through these modes, never by hand.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
import tempfile

# Cited source lines contain non-ASCII (em dashes, arrows). On Windows the
# default console encoding is cp1252, so printing them raises
# UnicodeEncodeError as soon as stdout is a pipe rather than a UTF-8
# terminal -- which is exactly what happens under a hook or in CI.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_PROFILE = Path("doc") / "agents" / "method-profile.json"
DEFAULT_SDK_SRC = Path("C:/flutter_sdk/flutter/packages/flutter/lib/src")
DEFAULT_EXTENSIONS = ("dart", "md")
LEDGER_SUFFIX = ".citations.tsv"
TOKEN_LEN = 60

# Any backticked `name.ext:N` or `name.ext:N-M`, and the bare `:N` form that
# continues the last one. Whether a named citation counts is decided by its
# extension against the profile's list, so an unlisted one can be told apart
# from prose and its continuations reported instead of misattributed.
CITATION = re.compile(
    r"`(?P<path>[A-Za-z0-9_./-]+\.(?P<ext>[A-Za-z0-9]+)):(?P<start>\d+)(?:-(?P<end>\d+))?`"
    r"|`:(?P<bstart>\d+)(?:-(?P<bend>\d+))?`"
)

# Directories a bare filename must never resolve into.
SKIP_DIRS = {".git", ".dart_tool", "build", "examples", "__pycache__"}
# Agent worktrees hold full copies of the repository, so a bare name found
# there is a duplicate of the real file, never the file a plan cites.
WORKTREES = (".claude", "worktrees")


@dataclass(frozen=True)
class Config:
    repo: Path
    sdk_src: Path
    extensions: tuple[str, ...]


def load_config(profile: Path | None, repo: Path = REPO) -> Config:
    """The citation settings: the profile's `citations` block, or the defaults.

    An explicit profile that does not exist is an error; the default one is
    optional, so the checker still runs in a project without a profile.
    """
    path = profile if profile is not None else repo / DEFAULT_PROFILE
    if profile is not None and not path.is_file():
        raise SystemExit(f"profile not found: {path}")
    if not path.is_file():
        return Config(repo, DEFAULT_SDK_SRC, DEFAULT_EXTENSIONS)
    block = json.loads(path.read_text(encoding="utf-8")).get("citations")
    if not isinstance(block, dict):
        raise SystemExit(f"{path} has no citations block")
    extensions = block.get("extensions")
    sdk_root = block.get("sdkRoot")
    if not isinstance(extensions, list) or not all(isinstance(e, str) and e for e in extensions):
        raise SystemExit(f"{path}: citations.extensions must be a list of extensions")
    if not isinstance(sdk_root, str) or not sdk_root:
        raise SystemExit(f"{path}: citations.sdkRoot must be a path")
    return Config(repo, Path(sdk_root), tuple(extensions))


def live_text(plan: Path) -> str:
    text = plan.read_text(encoding="utf-8")
    marker = "## Audit log"
    return text.split(marker)[0] if marker in text else text


def eol_of(path: Path) -> str:
    """The line ending a file already uses, CRLF or LF."""
    return "\r\n" if path.is_file() and b"\r\n" in path.read_bytes() else "\n"


def write_keeping_eol(path: Path, text: str, eol: str) -> None:
    """Writes [text], whose lines end in LF, with [eol] line endings.

    `Path.write_text` translates every LF to `os.linesep`, which on Windows
    turned an LF plan into a CRLF one on every rewrite. Writing bytes keeps
    the file in the form it was found.
    """
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", eol).encode("utf-8"))


def _outside_worktrees(path: Path, repo: Path) -> bool:
    parts = path.relative_to(repo).parts
    return parts[:2] != WORKTREES and not SKIP_DIRS.intersection(parts)


def resolve(rel: str, cfg: Config) -> Path | None:
    """Map a citation path to a file on disk.

    Dart: bare filenames are repository sources under lib/; anything with a
    directory component is a Flutter SDK path under the profile's SDK root.

    Every other extension is repository-relative instead, because the
    documents and tools that plans cite live outside lib/ (the repository
    root, doc/agents/, plans/ and .claude/). A slashed path is taken from the
    repository root, and a bare name must match exactly one file outside the
    skipped directories and the agent worktrees.
    """
    if rel.endswith(".dart"):
        if "/" in rel:
            candidate = cfg.sdk_src / rel
            return candidate if candidate.is_file() else None
        hits = sorted(cfg.repo.glob(f"lib/**/{rel}"))
        return hits[0] if len(hits) == 1 else None
    if "/" in rel:
        candidate = cfg.repo / rel
        return candidate if candidate.is_file() else None
    hits = sorted(
        path for path in cfg.repo.glob(f"**/{rel}")
        if path.is_file() and _outside_worktrees(path, cfg.repo)
    )
    return hits[0] if len(hits) == 1 else None


def citations(text: str, cfg: Config) -> tuple[list[tuple[str, int]], list[tuple[str, int]]]:
    """Every (path, line) in document order, and every DANGLING continuation.

    A bare `:NNN` citation attaches to the most recently named file, which is
    how these plans write follow-on references. After a named citation of an
    unlisted extension it attaches to nothing: it is returned in the second
    list, as (the unlisted path, line).
    """
    found: list[tuple[str, int]] = []
    dangling: list[tuple[str, int]] = []
    current: str | None = None
    unlisted: str | None = None
    for match in CITATION.finditer(text):
        if match.group("path"):
            if match.group("ext") in cfg.extensions:
                current, unlisted = match.group("path"), None
                found.append((current, int(match.group("start"))))
            else:
                current, unlisted = None, match.group("path")
        elif current is not None:
            found.append((current, int(match.group("bstart"))))
        elif unlisted is not None:
            dangling.append((unlisted, int(match.group("bstart"))))
    return found, dangling


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
# Both leave a long, intact PREFIX. `--repoint` matches on that to recover the
# citation; demanding a unique hit keeps it from guessing. Verify does NOT use
# it: a line whose recorded text changed is GONE there, because its claim needs
# re-reading even when the line still starts the same way.
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


def write_ledger(ledger_path: Path, rows: dict[tuple[str, int], str]) -> None:
    lines = [f"{rel}\t{ln}\t{tok}" for (rel, ln), tok in sorted(rows.items())]
    write_keeping_eol(ledger_path, "\n".join(lines) + "\n", eol_of(ledger_path))


def repoint(plan: Path, ledger_path: Path, cfg: Config) -> int:
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

    for m in CITATION.finditer(live):
        if m.group("path"):
            if m.group("ext") not in cfg.extensions:
                current = None
                continue
            current, start_s, end_s = m.group("path"), m.group("start"), m.group("end")
            named = True
        elif current is not None:
            start_s, end_s = m.group("bstart"), m.group("bend")
            named = False
        else:
            continue

        rel, line_no = current, int(start_s)
        want = expected.get((rel, line_no))
        target = resolve(rel, cfg)
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
            notes.append(f"  GONE     {rel}:{line_no}  text is gone; the plan may be wrong")
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
        body = f"{rel}:{new_line}" if named else f":{new_line}"
        if end_s is not None:
            body += f"-{int(end_s) + shift}"
        edits.append((m.start(), m.end(), f"`{body}`"))
        relocated[(rel, line_no)] = (new_line, token_at(target, new_line) if refresh else None)
        moved += 1

    if edits:
        backup = plan.with_suffix(plan.suffix + ".bak")
        backup.write_bytes(plan.read_bytes())
        ledger_path.with_suffix(ledger_path.suffix + ".bak").write_bytes(
            ledger_path.read_bytes())
        for start, end, replacement in reversed(edits):
            live = live[:start] + replacement + live[end:]
        write_keeping_eol(plan, live + (marker + tail if tail else ""), eol_of(plan))

        # Move ONLY the entries that moved, carrying their original recorded
        # text to the new line. Every other entry is left exactly as it was.
        # Re-recording the whole ledger here would anchor the deleted and
        # ambiguous citations to whatever now sits at their line numbers and
        # report the plan clean, destroying the only evidence that they are
        # the ones a human still has to look at.
        rewritten = {}
        for (rel, old_line), token in read_ledger(ledger_path).items():
            new_line, fresh_token = relocated.get((rel, old_line), (old_line, None))
            rewritten[(rel, new_line)] = fresh_token or token
        write_ledger(ledger_path, rewritten)
        print(f"repointed {moved} citation(s); backups at "
              f"{backup.name} and {ledger_path.name}.bak")
    else:
        print("repointed 0 citations")
    for note in notes:
        print(note)
    if ambiguous or deleted or collided:
        print(f"left in place: {deleted} gone, {ambiguous} ambiguous, {collided} collided")
    return 0


def accept(plan: Path, ledger_path: Path, items: list[str],
           cited: set[tuple[str, int]], cfg: Config) -> int:
    """Re-record exactly the named citations from the files as they are now.

    For a citation whose claim a person has re-read and, where needed,
    corrected along with its line number. All or nothing: a name that is not
    a live citation of the plan, or whose line does not resolve, writes no
    row at all.
    """
    if not ledger_path.is_file():
        print(f"no ledger; run with --update first ({ledger_path.name})")
        return 2
    if not items:
        print("--accept needs at least one <path:line> as cited in the plan")
        return 2
    rows = read_ledger(ledger_path)
    changes, refused = [], []
    for item in items:
        rel, _, line_s = item.rpartition(":")
        if not line_s.isdigit() or (rel, int(line_s)) not in cited:
            refused.append(f"  REFUSED  {item}  (not a live citation of this plan)")
            continue
        target = resolve(rel, cfg)
        token = token_at(target, int(line_s)) if target is not None else None
        if not token:
            refused.append(f"  REFUSED  {item}  (unresolved path, blank line, or out of range)")
            continue
        changes.append((rel, int(line_s), rows.get((rel, int(line_s))), token))
    if refused:
        for line in refused:
            print(line)
        print("nothing recorded")
        return 2
    for rel, line_no, old, token in changes:
        rows[(rel, line_no)] = token
        print(f"  ACCEPTED {rel}:{line_no}")
        print(f"             was: {old if old is not None else '(unrecorded)'}")
        print(f"             now: {token}")
    write_ledger(ledger_path, rows)
    return 0


def record_new(ledger_path: Path, unique: list[tuple[str, int]], cfg: Config) -> None:
    # Add rows ONLY for citations the ledger has never seen, and never
    # rewrite or drop an existing one: a corrected citation whose line
    # already has a row is re-recorded with --accept instead.
    existing = read_ledger(ledger_path) if ledger_path.is_file() else {}
    before = len(existing)
    added, skipped = [], []
    for rel, line_no in unique:
        if (rel, line_no) in existing:
            continue
        target = resolve(rel, cfg)
        token = token_at(target, line_no) if target is not None else None
        if not token:
            skipped.append((rel, line_no))
            continue
        existing[(rel, line_no)] = token
        added.append((rel, line_no))
    write_ledger(ledger_path, existing)
    print(f"recorded {len(added)} new citation(s); {before} existing row(s) untouched")
    for rel, line_no in added:
        print(f"  NEW      {rel}:{line_no}")
    for rel, line_no in skipped:
        print(f"  SKIPPED  {rel}:{line_no}  (unresolved path, blank line, or out of range)")


def update(ledger_path: Path, unique: list[tuple[str, int]], cfg: Config) -> int:
    rows, unresolved = {}, []
    for rel, line_no in unique:
        target = resolve(rel, cfg)
        if target is None:
            unresolved.append((rel, line_no, "unresolved path"))
            continue
        token = token_at(target, line_no)
        if token is None:
            unresolved.append((rel, line_no, "line out of range"))
            continue
        rows[(rel, line_no)] = token
    write_ledger(ledger_path, rows)
    print(f"recorded {len(rows)} -> {ledger_path.name}")
    for rel, line_no, why in unresolved:
        print(f"  SKIPPED {rel}:{line_no}  ({why})")
    return 1 if unresolved else 0


def verify(ledger_path: Path, unique: list[tuple[str, int]],
           dangling: list[tuple[str, int]], cfg: Config, verbose: bool) -> int:
    if not ledger_path.is_file():
        print(f"no ledger; run with --update first ({ledger_path.name})")
        return 2

    expected = read_ledger(ledger_path)

    ok = moved = gone = missing = 0
    for rel, line_no in dangling:
        print(f"  DANGLING :{line_no}  after {rel}, whose extension the profile does not list")
        missing += 1
    for rel, line_no in unique:
        want = expected.get((rel, line_no))
        if want is None:
            print(f"  NEW      {rel}:{line_no}  (not in ledger; rerun --record-new)")
            missing += 1
            continue
        target = resolve(rel, cfg)
        if target is None:
            print(f"  NOFILE   {rel}:{line_no}")
            missing += 1
            continue
        got = token_at(target, line_no)
        if got == want:
            ok += 1
            continue
        hits = find_token(target, want)
        if hits:
            moved += 1
            if verbose:
                where = ", ".join(str(h) for h in hits[:5])
                more = f" and {len(hits) - 5} more" if len(hits) > 5 else ""
                print(f"  MOVED    {rel}:{line_no} -> {where}{more}")
            continue
        gone += 1
        print(f"  GONE     {rel}:{line_no}  recorded text is nowhere in the file; re-read the claim")
        print(f"             recorded: {want}")
        print(f"             line now: {got}")

    print(f"ok {ok}, moved {moved}, gone {gone}, unrecorded {missing}")
    return 1 if (gone or missing) else 0


def self_test() -> int:
    """The checker's own cases, run in a temporary repository.

    The tree is built here, so the cases need no particular checkout: the
    bare-name case brings its own worktree duplicate, and the SDK case its
    own SDK directory.
    """
    failures: list[str] = []

    def expect(name: str, condition: bool, detail: str = "") -> None:
        print(f"  {'pass' if condition else 'FAIL'}  {name}{'' if condition else '  ' + detail}")
        if not condition:
            failures.append(name)

    root = Path(tempfile.mkdtemp(prefix="check_citations_"))
    try:
        files = {
            ".claude/agents/critic.md": "one\ntwo\nthree\n",
            ".claude/worktrees/w1/.claude/agents/critic.md": "copy\ncopy\ncopy\n",
            ".claude/workflows/tool.js": "a\nb\nc\nd\n",
            "plans/tool.py": "x\ny\n",
            "lib/widget.dart": "class W {}\n",
            "sdk/rendering/box.dart": "l1\nl2\nl3\n",
        }
        for rel, body in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
        profile = root / DEFAULT_PROFILE
        profile.parent.mkdir(parents=True, exist_ok=True)

        def write_profile(extensions: list[str]) -> None:
            profile.write_text(json.dumps({"citations": {
                "sdkRoot": str(root / "sdk"), "extensions": extensions}}), encoding="utf-8")

        write_profile(["dart", "md", "js", "mjs", "py"])
        cfg = load_config(None, root)
        text = ("`.claude/agents/critic.md:2` `critic.md:3` `tool.js:3` `:4` "
                "`tool.py:1` `rendering/box.dart:2` `widget.dart:1` `cfg.yaml:1` `:5`")
        found, dangling = citations(text, cfg)

        expect("profile extensions are read", "js" in cfg.extensions and "py" in cfg.extensions,
               str(cfg.extensions))
        expect("leading-dot path is counted", (".claude/agents/critic.md", 2) in found, str(found))
        expect("leading-dot path resolves from the repository root",
               resolve(".claude/agents/critic.md", cfg) == root / ".claude/agents/critic.md")
        expect("bare name resolves past its worktree duplicate",
               resolve("critic.md", cfg) == root / ".claude/agents/critic.md",
               str(resolve("critic.md", cfg)))
        expect("bare .js and .py names are counted",
               ("tool.js", 3) in found and ("tool.py", 1) in found, str(found))
        expect("bare .js and .py names resolve",
               resolve("tool.js", cfg) == root / ".claude/workflows/tool.js"
               and resolve("tool.py", cfg) == root / "plans/tool.py")
        expect("a continuation after a listed extension attaches to it", ("tool.js", 4) in found,
               str(found))
        expect("a continuation after an unlisted extension is DANGLING",
               dangling == [("cfg.yaml", 5)] and ("cfg.yaml", 5) not in found
               and ("tool.py", 5) not in found, f"{dangling} {found}")
        expect("a slashed .dart path resolves under the SDK root",
               resolve("rendering/box.dart", cfg) == root / "sdk/rendering/box.dart")
        expect("a bare .dart name resolves under lib/",
               resolve("widget.dart", cfg) == root / "lib/widget.dart")

        plan = root / "plans/fixture-plan.md"
        plan.write_text(text + "\n", encoding="utf-8")
        ledger = plan.with_suffix(plan.suffix + LEDGER_SUFFIX)
        unique = sorted(set(found))
        update(ledger, unique, cfg)
        expect("verify fails on a DANGLING continuation",
               verify(ledger, unique, dangling, cfg, False) == 1)
        expect("verify passes once nothing dangles", verify(ledger, unique, [], cfg, False) == 0)

        write_profile(["dart", "md", "js", "mjs"])
        found_no_py, _ = citations(text, load_config(None, root))
        expect("an extension the profile omits is not counted", ("tool.py", 1) not in found_no_py,
               str(found_no_py))

        profile.unlink()
        defaults = load_config(None, root)
        found_default, _ = citations(text, defaults)
        expect("without a profile only .dart and .md count",
               defaults.extensions == DEFAULT_EXTENSIONS and ("tool.js", 3) not in found_default
               and (".claude/agents/critic.md", 2) in found_default, str(found_default))
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print(f"self-test: {'0 failed' if not failures else f'{len(failures)} failed'}")
    return 1 if failures else 0


def option_value(name: str) -> str | None:
    if name not in sys.argv:
        return None
    index = sys.argv.index(name) + 1
    if index >= len(sys.argv) or sys.argv[index].startswith("--"):
        raise SystemExit(f"{name} needs a value")
    return sys.argv[index]


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    plan = Path(sys.argv[1])
    update_mode = "--update" in sys.argv
    record_mode = "--record-new" in sys.argv
    verbose = "--verbose" in sys.argv
    accepting = "--accept" in sys.argv
    profile = option_value("--profile")
    cfg = load_config(Path(profile) if profile else None)
    ledger_path = plan.with_suffix(plan.suffix + LEDGER_SUFFIX)

    if update_mode and ledger_path.is_file():
        print(f"{ledger_path.name} exists. --update records a plan that has no "
              "ledger; use --record-new for added citations and --accept for "
              "ones you re-verified. To start over, delete the ledger first.")
        return 2

    if "--repoint" in sys.argv:
        code = repoint(plan, ledger_path, cfg)
        if code != 0:
            return code
        # Fall through to VERIFY, never to a re-record: repoint has already
        # written the ledger, moving only what it moved.

    cites, dangling = citations(live_text(plan), cfg)
    unique = sorted(set(cites))
    print(f"{len(cites)} citations ({len(unique)} distinct) in {plan.name}")

    if accepting:
        items = []
        for arg in sys.argv[sys.argv.index("--accept") + 1:]:
            if arg.startswith("--"):
                break
            items.append(arg)
        code = accept(plan, ledger_path, items, set(unique), cfg)
        if code != 0:
            return code

    if record_mode:
        record_new(ledger_path, unique, cfg)

    if update_mode:
        return update(ledger_path, unique, cfg)

    return verify(ledger_path, unique, dangling, cfg, verbose)


if __name__ == "__main__":
    sys.exit(main())
