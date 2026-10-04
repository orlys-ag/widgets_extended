#!/usr/bin/env python3
"""Check a plan's `path:line` citations against the tree they were read on.

A stamped plan carries one marker:

    <!-- CITATIONS: repo <sha> sdk <sha> -->

`repo` is a snapshot commit of the working tree plus every file the plan
cites, kept under `refs/citations/<plan>`; its message lists each citation
stamped and the file it resolved to. `sdk` is the HEAD of the repository that
holds the profile's SDK root, present when the plan cites the SDK. Verify maps
each stamped citation through `git diff` from that base to the file on disk.

Usage:
    python plans/check_citations.py plans/<plan>.md             # verify
    python plans/check_citations.py plans/<plan>.md --verbose   # also list MOVED
    python plans/check_citations.py plans/<plan>.md --stamp     # a plan with no marker
    python plans/check_citations.py plans/<plan>.md --rebase [--accept <path:line> ...]
    python plans/check_citations.py --self-test

Statuses:
    OK          the cited lines are unchanged, at the same numbers
    MOVED       the cited lines are unchanged, at other numbers
    CHANGED     a cited line was edited or removed, a line was inserted inside
                a cited range, or the file is gone: re-read the claim
    NEW         not in the stamp, so written after it
    UNRESOLVED  the name matches no file or several, or a different file
                than at the stamp
    PAST-END    a NEW citation past the end of its file
    DANGLING    a bare `:N` after a citation whose extension the profile does
                not list
Verify exits 1 on any status but OK and MOVED, and 2 when it cannot check.

--rebase renumbers the MOVED citations, keeps the NEW ones and those named by
--accept as written, and stamps the current tree. It writes nothing while a
citation is UNRESOLVED, PAST-END, DANGLING, or CHANGED and not accepted.

A citation is a backticked `name.ext:N` or `name.ext:N-M` whose extension the
profile's `citations.extensions` lists, or a bare `:N` continuing the last
one. A name with a directory is a path from the repository root, or else from
the profile's `citations.sdkRoot`; a bare name must match exactly one file git
tracks or would track. Only the live text is read: everything from the line
`## Audit log` on is history.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

PROFILE = Path("doc") / "agents" / "method-profile.json"
LIVE_END = re.compile(r"^## Audit log[ \t]*\r?$", re.M)
REF_PREFIX = "refs/citations/"
MARKER = re.compile(r"<!-- CITATIONS: repo (?P<repo>[0-9a-f]{40})(?: sdk (?P<sdk>[0-9a-f]{40}))? -->")
CITATION = re.compile(
    r"`(?P<path>[A-Za-z0-9_./-]+\.(?P<ext>[A-Za-z0-9]+)):(?P<start>\d+)(?:-(?P<end>\d+))?`"
    r"|`:(?P<bstart>\d+)(?:-(?P<bend>\d+))?`"
)
FAILING = ("CHANGED", "NEW", "UNRESOLVED", "PAST-END", "DANGLING")
# A fixed identity and algorithm, so a stamp and a verify do not depend on the
# configuration of the machine that runs them.
TOOL_ENV = {
    "GIT_AUTHOR_NAME": "check_citations", "GIT_AUTHOR_EMAIL": "check_citations@localhost",
    "GIT_COMMITTER_NAME": "check_citations", "GIT_COMMITTER_EMAIL": "check_citations@localhost",
}


class Refused(Exception):
    """A condition that stops the run before anything is written."""


def git(cwd: Path, *args: str, env: dict[str, str] | None = None, data: str | None = None,
        ok: tuple[int, ...] = (0,)) -> bytes:
    done = subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                          env={**os.environ, **(env or {})},
                          input=data.encode("utf-8") if data is not None else None)
    if done.returncode not in ok:
        raise Refused(f"git {' '.join(args[:3])} failed: {done.stderr.decode(errors='replace').strip()}")
    return done.stdout


def has_object(cwd: Path, name: str) -> bool:
    return subprocess.run(["git", "cat-file", "-e", name], cwd=cwd, capture_output=True).returncode == 0


def lines_of(data: bytes) -> list[str]:
    """The lines as git counts them: split on LF only, CRLF read as LF."""
    text = data.decode("utf-8", errors="replace").replace("\r\n", "\n")
    if not text:
        return []
    rows = text.split("\n")
    return rows[:-1] if text.endswith("\n") else rows


@dataclass(frozen=True)
class Config:
    repo: Path
    extensions: tuple[str, ...]
    sdk_src: Path | None
    sdk_repo: Path | None
    sdk_prefix: str


def load_config(repo: Path, profile: Path | None) -> Config:
    path = profile or repo / PROFILE
    if not path.is_file():
        raise Refused(f"profile not found: {path}")
    block = json.loads(path.read_text(encoding="utf-8")).get("citations")
    if not isinstance(block, dict) or not isinstance(block.get("extensions"), list) \
            or not isinstance(block.get("sdkRoot"), str):
        raise Refused(f"{path}: the citations block needs extensions and sdkRoot")
    sdk_src = Path(block["sdkRoot"]) if block["sdkRoot"] else None
    sdk_repo, prefix = None, ""
    if sdk_src is not None and sdk_src.is_dir():
        top = git(sdk_src, "rev-parse", "--show-toplevel", ok=(0, 128)).decode().strip()
        if top:
            sdk_repo = Path(top)
            prefix = git(sdk_src, "rev-parse", "--show-prefix").decode().strip()
    return Config(repo, tuple(block["extensions"]), sdk_src, sdk_repo, prefix)


@dataclass(frozen=True)
class Occurrence:
    name: str
    start: int
    end: int
    span: tuple[int, int]
    named: bool

    @property
    def key(self) -> str:
        return f"{self.name}:{self.start}" + (f"-{self.end}" if self.end != self.start else "")


def split_live(text: str) -> tuple[str, str]:
    m = LIVE_END.search(text)
    return (text, "") if m is None else (text[:m.start()], text[m.start():])


def occurrences(live: str, cfg: Config) -> tuple[list[Occurrence], list[str]]:
    found: list[Occurrence] = []
    dangling: list[str] = []
    current: str | None = None
    unlisted: str | None = None
    for m in CITATION.finditer(live):
        if m.group("path"):
            if m.group("ext") not in cfg.extensions:
                current, unlisted = None, m.group("path")
                continue
            current, unlisted, named = m.group("path"), None, True
            start, end = m.group("start"), m.group("end")
        elif current is not None:
            named, start, end = False, m.group("bstart"), m.group("bend")
        else:
            if unlisted is not None:
                dangling.append(f"{unlisted} :{m.group('bstart')}")
            continue
        found.append(Occurrence(current, int(start), int(end or start), m.span(), named))
    return found, dangling


class Tree:
    """Resolves citation names against the files on disk now."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        listed = git(cfg.repo, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
        self.by_name: dict[str, set[str]] = {}
        for rel in listed.decode("utf-8").split("\0"):
            if rel and (cfg.repo / rel).is_file():
                self.by_name.setdefault(rel.rsplit("/", 1)[-1], set()).add(rel)

    def resolve(self, name: str) -> tuple[str, str] | str:
        """("repo" or "sdk", the path in that repository), or why it fails."""
        if "/" in name:
            if (self.cfg.repo / name).is_file():
                return ("repo", name)
            if self.cfg.sdk_src is not None and (self.cfg.sdk_src / name).is_file():
                if self.cfg.sdk_repo is None:
                    return "the SDK root is not in a git repository"
                return ("sdk", self.cfg.sdk_prefix + name)
            return "no such file"
        hits = self.by_name.get(name, set())
        if len(hits) == 1:
            return ("repo", next(iter(hits)))
        return "no file has this name" if not hits else f"{len(hits)} files have this name"

    def read(self, where: tuple[str, str]) -> bytes | None:
        root = self.cfg.repo if where[0] == "repo" else self.cfg.sdk_repo
        path = root / where[1]
        return path.read_bytes() if path.is_file() else None


def hunks(cfg: Config, old: bytes, new: bytes) -> list[tuple[int, int, int, int]]:
    with tempfile.TemporaryDirectory() as tmp:
        a, b = Path(tmp, "a"), Path(tmp, "b")
        a.write_bytes(old.replace(b"\r\n", b"\n"))
        b.write_bytes(new.replace(b"\r\n", b"\n"))
        out = git(cfg.repo, "diff", "--no-index", "--no-color", "--no-ext-diff", "--histogram",
                  "-U0", "--", str(a), str(b), ok=(0, 1))
    found = []
    for line in out.decode("utf-8", errors="replace").splitlines():
        m = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
        if m:
            found.append((int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1)))
    return found


def map_range(diff: list[tuple[int, int, int, int]], start: int, end: int) -> tuple[int, bool]:
    """Where base line [start] is now, and whether [start, end] changed."""
    offset = 0
    for a, b, _, d in diff:
        if b == 0:
            if start <= a < end:
                return start + offset, True
            if a < start:
                offset += d
        elif a <= end and start <= a + b - 1:
            return start + offset, True
        elif a + b - 1 < start:
            offset += d - b
    return start + offset, False


def read_stamp(cfg: Config, sha: str) -> dict[str, tuple[str, str]]:
    if not has_object(cfg.repo, f"{sha}^{{commit}}"):
        raise Refused(f"base {sha} is not in this repository; its plan cannot be checked")
    message = git(cfg.repo, "show", "-s", "--format=%B", sha).decode("utf-8")
    stamp = {}
    for row in message.splitlines()[2:]:
        if row.strip():
            key, where = row.split("\t")
            kind, path = where.split(":", 1)
            stamp[key] = (kind, path)
    return stamp


@dataclass
class Status:
    status: str
    shift: int = 0
    detail: str = ""


def analyze(text: str, cfg: Config) -> tuple[re.Match, list[Occurrence], list[str], dict[str, Status]]:
    live, _ = split_live(text)
    marker = MARKER.search(live)
    if marker is None:
        raise Refused("the plan has no CITATIONS marker; stamp it with --stamp")
    occs, dangling = occurrences(live, cfg)
    stamp = read_stamp(cfg, marker["repo"])
    tree = Tree(cfg)
    diffs: dict[tuple[str, str], tuple[list, list[str]] | None] = {}
    result: dict[str, Status] = {}
    for occ in occs:
        if occ.key in result:
            continue
        now = tree.resolve(occ.name)
        if occ.key not in stamp:
            if isinstance(now, str):
                result[occ.key] = Status("UNRESOLVED", detail=now)
            elif occ.end > len(lines_of(tree.read(now))):
                result[occ.key] = Status("PAST-END")
            else:
                result[occ.key] = Status("NEW", detail="written after the stamp")
            continue
        where = stamp[occ.key]
        if where not in diffs:
            base_sha = marker["repo"] if where[0] == "repo" else marker["sdk"]
            root = cfg.repo if where[0] == "repo" else cfg.sdk_repo
            if root is None or base_sha is None:
                raise Refused(f"{occ.key} was stamped against the SDK, but the profile's SDK root "
                              "is not a git repository or the marker names no SDK commit")
            current = tree.read(where)
            if current is None:
                diffs[where] = None
            else:
                base = git(root, "cat-file", "blob", f"{base_sha}:{where[1]}")
                diffs[where] = (hunks(cfg, base, current), lines_of(base))
        if diffs[where] is None:
            result[occ.key] = Status("CHANGED", detail=f"{where[1]} is gone")
            continue
        if now != where:
            result[occ.key] = Status("UNRESOLVED", detail=now if isinstance(now, str)
                                     else f"resolves to {now[1]}, stamped as {where[1]}")
            continue
        diff, base_lines = diffs[where]
        moved_to, changed = map_range(diff, occ.start, occ.end)
        if changed:
            result[occ.key] = Status("CHANGED", detail=f"near line {moved_to} now; stamped line read: "
                                     + base_lines[occ.start - 1].strip()[:80])
        else:
            shift = moved_to - occ.start
            result[occ.key] = Status("MOVED" if shift else "OK", shift)
    return marker, occs, dangling, result


def report(occs: list[Occurrence], dangling: list[str], result: dict[str, Status],
           verbose: bool) -> int:
    counts = {s: 0 for s in ("OK", "MOVED", *FAILING)}
    for key, st in result.items():
        counts[st.status] += 1
        if st.status in FAILING or (verbose and st.status == "MOVED"):
            more = f"  {st.detail}" if st.detail else ""
            if st.status == "MOVED":
                more = f"  by {st.shift:+d}"
            print(f"  {st.status:<10} {key}{more}")
    for item in dangling:
        counts["DANGLING"] += 1
        print(f"  DANGLING   {item}  after an extension the profile does not list")
    print(f"{len(occs)} citations, {len(result)} distinct: "
          + ", ".join(f"{k.lower()} {v}" for k, v in counts.items()))
    return 1 if any(counts[s] for s in FAILING) else 0


def snapshot(cfg: Config, plan: Path, repo_paths: list[str], entries: list[str]) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        index = Path(tmp, "index")
        real = Path(git(cfg.repo, "rev-parse", "--path-format=absolute", "--git-path",
                        "index").decode().strip())
        if real.is_file():
            shutil.copyfile(real, index)
        env = {"GIT_INDEX_FILE": str(index)}
        git(cfg.repo, "add", "-A", env=env)
        if repo_paths:
            git(cfg.repo, "add", "-f", "--", *sorted(set(repo_paths)), env=env)
        tree = git(cfg.repo, "write-tree", env=env).decode().strip()
    head = git(cfg.repo, "rev-parse", "--verify", "--quiet", "HEAD", ok=(0, 1)).decode().strip()
    message = f"citations: {plan.name}\n\n" + "\n".join(entries) + "\n"
    commit = git(cfg.repo, "commit-tree", tree, *(["-p", head] if head else []), "-F", "-",
                 env=TOOL_ENV, data=message).decode().strip()
    git(cfg.repo, "update-ref", REF_PREFIX + plan.stem, commit)
    return commit


def write_plan(plan: Path, text: str) -> None:
    eol = "\r\n" if b"\r\n" in plan.read_bytes() else "\n"
    plan.write_bytes(text.replace("\r\n", "\n").replace("\n", eol).encode("utf-8"))


def stamp(plan: Path, text: str, cfg: Config) -> int:
    live, tail = split_live(text.replace("\r\n", "\n"))
    occs, dangling = occurrences(live, cfg)
    tree = Tree(cfg)
    problems = [f"  DANGLING   {item}" for item in dangling]
    where: dict[str, tuple[str, str]] = {}
    for occ in occs:
        if occ.key in where:
            continue
        now = tree.resolve(occ.name)
        if isinstance(now, str):
            problems.append(f"  UNRESOLVED {occ.key}  {now}")
        elif occ.end > len(lines_of(tree.read(now))):
            problems.append(f"  PAST-END   {occ.key}")
        else:
            where[occ.key] = now
    sdk_paths = sorted({p for kind, p in where.values() if kind == "sdk"})
    if sdk_paths and git(cfg.sdk_repo, "status", "--porcelain", "--", *sdk_paths).strip():
        problems.append("  the SDK files cited differ from the SDK's HEAD; a stamp needs them committed")
    if problems:
        print("\n".join(problems))
        print("nothing stamped")
        return 1
    repo = snapshot(cfg, plan, [p for kind, p in where.values() if kind == "repo"],
                    [f"{key}\t{kind}:{path}" for key, (kind, path) in sorted(where.items())])
    sdk = git(cfg.sdk_repo, "rev-parse", "HEAD").decode().strip() if sdk_paths else None
    line = f"<!-- CITATIONS: repo {repo}" + (f" sdk {sdk}" if sdk else "") + " -->"
    if MARKER.search(live):
        live = MARKER.sub(line, live, count=1)
    else:
        rows = live.split("\n")
        first = next((i for i, row in enumerate(rows) if row.strip()), 0)
        at = first + 1 if rows[first].startswith("<!-- PLAN-STATUS:") else 0
        live = "\n".join(rows[:at] + [line] + rows[at:])
    write_plan(plan, live + tail)
    print(f"stamped {len(where)} distinct citations at {repo[:12]}"
          + (f", sdk {sdk[:12]}" if sdk else ""))
    return 0


def rebase(plan: Path, text: str, cfg: Config, accepted: list[str]) -> int:
    text = text.replace("\r\n", "\n")
    _, occs, dangling, result = analyze(text, cfg)
    refused = [f"  REFUSED    {key}  " + ("not a citation of this plan" if key not in result
                                         else "only a CHANGED citation is accepted")
               for key in accepted if key not in result or result[key].status != "CHANGED"]
    for key, st in result.items():
        if st.status in ("UNRESOLVED", "PAST-END") or (st.status == "CHANGED" and key not in accepted):
            refused.append(f"  {st.status:<10} {key}  {st.detail}")
    refused += [f"  DANGLING   {item}" for item in dangling]
    if refused:
        print("\n".join(refused))
        print("nothing written: re-read each CHANGED claim, write its current line, and name it with --accept")
        return 1
    live, tail = split_live(text)
    for occ in reversed(occs):
        st = result[occ.key]
        if st.status != "MOVED" or occ.key in accepted:
            continue
        body = f"{occ.name}:" if occ.named else ":"
        body += str(occ.start + st.shift) + (f"-{occ.end + st.shift}" if occ.end != occ.start else "")
        live = live[:occ.span[0]] + f"`{body}`" + live[occ.span[1]:]
    moved = sum(1 for st in result.values() if st.status == "MOVED")
    print(f"renumbered {moved} moved citations")
    return stamp(plan, live + tail, cfg)


def run(argv: list[str]) -> int:
    if not argv or argv[0].startswith("--"):
        print(__doc__)
        return 2
    plan = Path(argv[0]).resolve()
    if not plan.is_file():
        print(f"no such plan: {argv[0]}")
        return 2
    profile, accepted, flags = None, [], set()
    rest = iter(argv[1:])
    for arg in rest:
        if arg == "--profile":
            profile = next(rest, None)
        elif arg in ("--stamp", "--rebase", "--verbose", "--accept"):
            flags.add(arg)
        elif "--accept" in flags and not arg.startswith("--"):
            accepted.append(arg)
        else:
            print(f"unknown argument: {arg}")
            return 2
    if profile is None and "--profile" in argv or accepted and "--rebase" not in flags:
        print("--profile needs a path, and --accept needs --rebase")
        return 2
    try:
        repo = Path(git(plan.parent, "rev-parse", "--show-toplevel").decode().strip())
        cfg = load_config(repo, Path(profile) if profile else None)
        text = plan.read_text(encoding="utf-8")
        if "--stamp" in flags:
            if MARKER.search(split_live(text)[0]):
                print("the plan is already stamped; use --rebase")
                return 2
            return stamp(plan, text, cfg)
        if "--rebase" in flags:
            return rebase(plan, text, cfg, accepted)
        _, occs, dangling, result = analyze(text, cfg)
        return report(occs, dangling, result, "--verbose" in flags)
    except Refused as why:
        print(why)
        return 2


def self_test() -> int:
    """The checker's own cases, in a temporary repository and SDK."""
    failures: list[str] = []
    root = Path(tempfile.mkdtemp(prefix="check_citations_"))

    def expect(name: str, condition: bool) -> None:
        print(f"  {'pass' if condition else 'FAIL'}  {name}")
        if not condition:
            failures.append(name)

    def put(path: Path, body: str, crlf: bool = False) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body.replace("\n", "\r\n" if crlf else "\n").encode("utf-8"))

    def quiet(*argv: str) -> int:
        stdout = sys.stdout
        sys.stdout = open(os.devnull, "w", encoding="utf-8")
        try:
            return run(list(argv))
        finally:
            sys.stdout.close()
            sys.stdout = stdout

    def statuses() -> dict[str, str]:
        cfg = load_config(repo, None)
        return {k: v.status for k, v in analyze(plan.read_text(encoding="utf-8"), cfg)[3].items()}

    try:
        repo, sdk = root / "repo", root / "sdk"
        for where in (repo, sdk):
            where.mkdir()
            git(where, "init", "-q")
            git(where, "config", "core.autocrlf", "false")
        body = "".join(f"line {i}\n" for i in range(1, 21))
        put(repo / "lib/a.dart", body)
        put(repo / "lib/b.dart", "x\n\ny\n")
        put(repo / "lib/crlf.dart", "p\nq\n")
        put(repo / ".gitignore", "/plans/*\n!/plans/keep.md\n")
        put(repo / "plans/other-plan.md", "o1\no2\n")
        put(sdk / "pkg/src/rendering/box.dart", body)
        put(repo / PROFILE, json.dumps({"citations": {
            "sdkRoot": str(sdk / "pkg/src"), "extensions": ["dart", "md"]}}))
        for where in (repo, sdk):
            git(where, "add", "-A")
            git(where, "commit", "-q", "-m", "base", env=TOOL_ENV)
        put(repo / "lib/untracked.dart", "u\n")
        plan = repo / "plans/x-plan.md"
        put(plan, "<!-- PLAN-STATUS: draft -->\n# X\n"
            "`a.dart:5` `:10-12` `b.dart:2` `crlf.dart:2` `plans/other-plan.md:2` "
            "`untracked.dart:1` `rendering/box.dart:7` `c.yaml:1` `:3`\n"
            "## Audit log\n`a.dart:99`\n")

        expect("verify without a marker cannot check", quiet(str(plan)) == 2)
        expect("a DANGLING continuation refuses the stamp", quiet(str(plan), "--stamp") == 1)
        put(plan, plan.read_text(encoding="utf-8").replace(" `c.yaml:1` `:3`", ""))
        put(sdk / "pkg/src/rendering/box.dart", "dirty\n" + body)
        expect("a dirty cited SDK file refuses the stamp", quiet(str(plan), "--stamp") == 1)
        put(sdk / "pkg/src/rendering/box.dart", body)
        expect("a clean plan stamps", quiet(str(plan), "--stamp") == 0)
        lines = plan.read_text(encoding="utf-8").split("\n")
        expect("the marker follows the status line", MARKER.match(lines[1]) is not None)
        base = MARKER.search(plan.read_text(encoding="utf-8"))["repo"]
        expect("the snapshot holds an ignored file cited by path",
               has_object(repo, f"{base}:plans/other-plan.md"))
        expect("the snapshot holds an untracked file", has_object(repo, f"{base}:lib/untracked.dart"))
        expect("a ref keeps the snapshot", git(repo, "rev-parse", REF_PREFIX + "x-plan")
               .decode().strip() == base)
        expect("a stamped plan refuses a second stamp", quiet(str(plan), "--stamp") == 2)
        expect("an unchanged tree verifies", quiet(str(plan)) == 0)
        expect("the audit log is not read", "a.dart:99" not in statuses())
        stamped = plan.read_text(encoding="utf-8")
        put(plan, stamped.replace("\n## Audit log", " `c.yaml:1` `:3`\n## Audit log"))
        expect("verify fails on DANGLING", quiet(str(plan)) == 1)
        put(plan, stamped)

        put(repo / "lib/a.dart", "new 1\nnew 2\n" + body)
        put(repo / "lib/crlf.dart", "p\nq\n", crlf=True)
        put(sdk / "pkg/src/rendering/box.dart", "s\n" + body)
        git(sdk, "commit", "-q", "-am", "upgrade", env=TOOL_ENV)
        got = statuses()
        expect("lines pushed down are MOVED and verify passes",
               got["a.dart:5"] == "MOVED" and got["a.dart:10-12"] == "MOVED" and quiet(str(plan)) == 0)
        expect("CRLF on disk against an LF base is OK", got["crlf.dart:2"] == "OK")
        expect("an SDK line pushed down is MOVED", got["rendering/box.dart:7"] == "MOVED")
        expect("a blank line is cited like any other", got["b.dart:2"] == "OK")

        put(repo / "lib/a.dart", "new 1\nnew 2\n" + body.replace("line 11\n", "line 11\nmid\n"))
        expect("an insertion inside a range is CHANGED", statuses()["a.dart:10-12"] == "CHANGED")
        expect("verify fails on CHANGED", quiet(str(plan)) == 1)
        before = plan.read_bytes()
        expect("rebase refuses an unaccepted CHANGED", quiet(str(plan), "--rebase") == 1
               and plan.read_bytes() == before)
        expect("rebase refuses to accept a non-citation",
               quiet(str(plan), "--rebase", "--accept", "a.dart:10-12", "a.dart:6") == 1
               and plan.read_bytes() == before)
        put(plan, plan.read_text(encoding="utf-8").replace("`:10-12`", "`:12-15`"))
        put(plan, plan.read_text(encoding="utf-8").replace("`b.dart:2`", "`b.dart:2` `b.dart:3`"))
        got = statuses()
        expect("a corrected citation is NEW", got.get("a.dart:12-15") == "NEW" and got["b.dart:3"] == "NEW")
        expect("verify fails on NEW", quiet(str(plan)) == 1)
        expect("rebase renumbers MOVED and keeps NEW", quiet(str(plan), "--rebase") == 0)
        text = plan.read_text(encoding="utf-8")
        expect("the rebased plan has the new numbers",
               "`a.dart:7`" in text and "`:12-15`" in text and "`rendering/box.dart:8`" in text)
        expect("the rebased plan verifies", quiet(str(plan)) == 0)

        edited = "new 1\nnew 2\n" + body.replace("line 11\n", "line 11\nmid\n")
        put(repo / "lib/a.dart", edited.replace("line 5\n", "line five\n"))
        put(repo / "lib/b.dart", "x\n\nchanged\n")
        got = statuses()
        expect("an edited cited line is CHANGED", got["a.dart:7"] == "CHANGED" and got["b.dart:3"] == "CHANGED")
        expect("rebase with every CHANGED citation accepted writes",
               quiet(str(plan), "--rebase", "--accept", "b.dart:3", "a.dart:7") == 0
               and quiet(str(plan)) == 0)

        put(repo / "test/a.dart", "dup\n")
        expect("a bare name matching two files is UNRESOLVED", statuses()["a.dart:7"] == "UNRESOLVED")
        (repo / "test/a.dart").unlink()
        (repo / "lib/untracked.dart").unlink()
        expect("a deleted file is CHANGED", statuses()["untracked.dart:1"] == "CHANGED")
        put(plan, plan.read_text(encoding="utf-8").replace("`untracked.dart:1`", "`b.dart:9`"))
        expect("a NEW citation past the end is PAST-END", statuses()["b.dart:9"] == "PAST-END")
        expect("verify fails on UNRESOLVED and PAST-END", quiet(str(plan)) == 1)
        put(plan, plan.read_text(encoding="utf-8").replace("`b.dart:9`", "`b.dart:1`"))
        expect("rebase refuses to accept a citation that is not CHANGED",
               quiet(str(plan), "--rebase", "--accept", "b.dart:2") == 1)
        expect("an unknown argument cannot run", quiet(str(plan), "--update") == 2)
        expect("rebase writes once nothing is CHANGED", quiet(str(plan), "--rebase") == 0)

        current = (repo / "lib/a.dart").read_text(encoding="utf-8")
        put(repo / "lib/a.dart", current.replace("new 1\nnew 2\n", "one\n"))
        expect("two lines replaced by one above a citation move it up by one",
               statuses()["a.dart:7"] == "MOVED" and quiet(str(plan), "--rebase") == 0
               and "`a.dart:6`" in plan.read_text(encoding="utf-8"))
        put(repo / "lib/a.dart", current.replace("new 1\nnew 2\n", ""))
        expect("a line deleted above a citation moves it up by one",
               quiet(str(plan), "--rebase") == 0 and "`a.dart:5`" in plan.read_text(encoding="utf-8"))

        bogus = repo / "plans/bogus-plan.md"
        put(bogus, "<!-- CITATIONS: repo " + "1" * 40 + " -->\n`b.dart:1`\n")
        expect("an unknown base cannot be checked", quiet(str(bogus)) == 2)
        past = repo / "plans/past-plan.md"
        put(past, "`b.dart:4`\n")
        expect("a stamp refuses a line past the end",
               quiet(str(past), "--stamp") == 1 and not MARKER.search(past.read_text(encoding="utf-8")))
        crlf_plan = repo / "plans/crlf-plan.md"
        put(crlf_plan, "\n<!-- PLAN-STATUS: draft -->\n# C\n`b.dart:1`\n", crlf=True)
        rows = crlf_plan.read_bytes().decode("utf-8").split("\r\n") if quiet(str(crlf_plan), "--stamp") == 0 else []
        expect("a stamp keeps CRLF and puts the marker after the status line",
               len(rows) > 2 and rows[1].startswith("<!-- PLAN-STATUS:") and MARKER.match(rows[2]) is not None
               and "\n" not in "".join(rows))
        inline = repo / "plans/inline-plan.md"
        put(inline, "See the ## Audit log below. `b.dart:1`\n## Audit log\n`b.dart:99`\n")
        quiet(str(inline), "--stamp")
        got = analyze(inline.read_text(encoding="utf-8"), load_config(repo, None))[3]
        expect("only a line that is the heading ends the live text", list(got) == ["b.dart:1"])
        put(repo / PROFILE, json.dumps({"citations": {"sdkRoot": str(root / "gone"), "extensions": ["dart", "md"]}}))
        expect("a missing SDK root cannot be checked", quiet(str(plan)) == 2)
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print(f"self-test: {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else run(sys.argv[1:]))
