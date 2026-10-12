#!/usr/bin/env python3
"""PostToolUse(Bash|PowerShell): report what a shell command did that no
check before it could see.

  control    control characters in files the command wrote. A shell command
             carries no written text to inspect beforehand (the content of
             `python - <<'PY'` does not exist until it runs), so detection
             afterwards is the ceiling. Scope: files git reports as changed
             and modified within WINDOW_SECONDS, which keeps it fast and stops
             it re-reporting earlier edits after every command.
  commit     what a commit holds, when that differs from what the command
             named. `git add <three files> && git commit` once swept in three
             more files already in the index, and a false claim about that
             commit followed. PreToolUse cannot see this: it fires before the
             whole command, so it reads the index before the add.

The commit report is silent when the commit holds exactly the files the
command's `git add`, `git rm`, `git mv` and `git commit` name, so a routine
commit costs no context. It examines a commit once, and only one the reflog
records as a commit made within COMMIT_WINDOW_SECONDS: a command that merely
mentions `git commit` adds nothing.

`--self-test` runs the cases in self_test() against a scratch repository.
"""

import fnmatch
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time

WINDOW_SECONDS = 120
# A foreground shell command runs at most 600 s, so a commit older than this
# was not made by the command that just finished.
COMMIT_WINDOW_SECONDS = 900
LEGAL = {9, 10, 13}
MAX_BYTES = 2 * 1024 * 1024
MAX_LISTED = 10

PUNCTUATION = ";&|()\n"
HEREDOC = re.compile(
    r"<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n.*?\n[ \t]*\2[ \t]*(?=\n|$)", re.S)
HERESTRING = re.compile(r"@(['\"])[ \t]*\r?\n.*?\r?\n\1@", re.S)
REDIRECT_BARE = re.compile(r"^\d*(>>?|<)&?$")
REDIRECT_ATTACHED = re.compile(r"^\d*(>>?|<)")

STAGING = ("add", "rm", "mv")
STAGING_BROAD = {"-A", "--all", "-u", "--update", "--no-ignore-removal",
                 "--pathspec-from-file"}
COMMIT_VALUE_SHORT = "mFCct"
COMMIT_VALUE_LONG = {"--message", "--file", "--reuse-message", "--reedit-message",
                     "--author", "--date", "--template", "--cleanup", "--fixup",
                     "--squash", "--trailer", "--pathspec-from-file"}


def git(cwd, *args):
    """git's stdout, or None if git fails or cannot start in `cwd`."""
    try:
        done = subprocess.run(["git", "-c", "core.quotepath=false", *args],
                              cwd=cwd, capture_output=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    if done.returncode != 0:
        return None
    return done.stdout.decode("utf-8", "replace")


# --- control characters --------------------------------------------------

def control_report(root, now):
    out = git(root, "status", "--porcelain", "-z", "--untracked-files=all")
    if not out:
        return None
    fields = out.split("\0")
    paths, i = [], 0
    while i < len(fields):
        entry = fields[i]
        i += 1
        if len(entry) < 4:
            continue
        paths.append(entry[3:])
        if "R" in entry[:2] or "C" in entry[:2]:
            i += 1                              # the source path follows
    cutoff = now - WINDOW_SECONDS
    hits = []
    for relative in paths:
        full = os.path.join(root, relative)
        try:
            if not os.path.isfile(full) or os.path.getmtime(full) < cutoff:
                continue
            if os.path.getsize(full) > MAX_BYTES:
                continue
            with open(full, encoding="utf-8", errors="strict") as handle:
                text = handle.read()
        except (OSError, ValueError):
            continue                            # binary or unreadable: not ours
        for index, char in enumerate(text):
            code = ord(char)
            if code < 32 and code not in LEGAL:
                hits.append("%s: 0x%02x at offset %d" % (relative, code, index))
                break
    if not hits:
        return None
    return ("Control characters were just written by a shell command. An "
            "escape sequence was consumed; the file is already on disk and "
            "may compile. Rebuild the value with chr(10) / chr(92) rather "
            "than escapes:\n" + "\n".join(hits))


# --- commit contents -----------------------------------------------------

def program(token):
    """A token's program name: `/usr/bin/git`, `git.exe` and `"git"` are `git`."""
    name = re.split(r"[\\/]", token.strip("\"'&"))[-1].lower()
    return name[:-4] if name.endswith(".exe") else name


def resolve(path, base):
    if os.name == "nt":
        path = re.sub(r"^/([A-Za-z])/", r"\1:/", path)   # Git Bash /c/... form
    return os.path.normpath(os.path.join(base, os.path.expanduser(path)))


def simple_commands(command, powershell):
    """The command's simple commands as token lists, or None if it cannot be split.

    Heredoc and here-string bodies are dropped first: they are message text,
    and an apostrophe in one would unbalance the quotes. PowerShell's escape
    character is the backtick, so a backslash there is a path separator.
    """
    text = HERESTRING.sub("''", HEREDOC.sub("", command))
    lexer = shlex.shlex(text, posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace_split = True
    lexer.whitespace = " \t\r"
    lexer.commenters = ""                       # a word starting with # ends the args
    if powershell:
        lexer.escape = ""
    try:
        tokens = list(lexer)
    except ValueError:
        return None
    out, current = [], []
    for token in tokens:
        if token and set(token) <= set(PUNCTUATION):
            if current:
                out.append(current)
            current = []
        else:
            current.append(token)
    if current:
        out.append(current)
    return out


def invocations(command, cwd, powershell):
    """[(subcommand, directory, args)] for each git add, rm, mv and commit."""
    commands = simple_commands(command, powershell)
    if commands is None:
        return None
    found, here = [], cwd
    for argv in commands:
        while argv and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", argv[0]):
            argv = argv[1:]                     # a VAR=value prefix
        if not argv or argv[0].startswith("#"):
            continue
        name = program(argv[0])
        if name in ("cd", "set-location", "sl", "pushd", "chdir"):
            if len(argv) > 1 and argv[-1] != "-":
                here = resolve(argv[-1], here)
            continue
        if name != "git":
            continue
        directory, i = here, 1
        while i < len(argv) and argv[i].startswith("-"):
            if argv[i] == "-C" and i + 1 < len(argv):
                directory = resolve(argv[i + 1], directory)
                i += 2
            elif argv[i] in ("-c", "--git-dir", "--work-tree", "--namespace"):
                i += 2
            else:
                i += 1
        if i < len(argv) and argv[i] in STAGING + ("commit",):
            found.append((argv[i], directory, argv[i + 1:]))
    return found


def named_paths(subcommand, args):
    """(paths, broad) for one invocation; broad means it names no exact set."""
    paths, broad, literal, i = [], False, False, 0
    while i < len(args):
        token = args[i]
        i += 1
        if not literal and token.startswith("#"):
            break                               # a shell comment
        if REDIRECT_BARE.match(token):
            i += 1
            continue
        if REDIRECT_ATTACHED.match(token):
            continue
        if literal or not token.startswith("-") or token == "-":
            paths.append(token)
            continue
        if token == "--":
            literal = True
            continue
        if subcommand in STAGING:
            cluster = set(token[1:]) if not token.startswith("--") else set()
            if token.split("=", 1)[0] in STAGING_BROAD or cluster & {"A", "u"}:
                broad = True
            continue
        if token.startswith("--"):
            key = token.split("=", 1)[0]
            if key in ("--all", "--pathspec-from-file"):
                broad = True
            if "=" not in token and key in COMMIT_VALUE_LONG:
                i += 1
            continue
        for k, char in enumerate(token[1:]):
            if char == "a":
                broad = True
            if char in COMMIT_VALUE_SHORT:
                if k + 2 == len(token):
                    i += 1                      # the value is the next token
                break
    return paths, broad


def listing(paths):
    shown = ", ".join(paths[:MAX_LISTED])
    rest = len(paths) - MAX_LISTED
    return shown + (" and %d more" % rest if rest > 0 else "")


def commit_report(command, cwd, now, state_dir, powershell=False):
    found = invocations(command, cwd, powershell)
    unparsed = found is None
    if unparsed:
        if not re.search(r"\bgit(?:\.exe)?\b[^\n]*?\bcommit\b", command):
            return None
        found = [("commit", cwd, [])]
    commits = [entry for entry in found if entry[0] == "commit"]
    if not commits:
        return None
    repo = commits[-1][1]

    top = (git(repo, "rev-parse", "--show-toplevel") or "").strip()
    if not top:
        return None
    entry = (git(repo, "log", "-g", "-1", "--date=unix", "--format=%H%x09%gd%x09%gs")
             or git(repo, "log", "-1", "--format=%H%x09HEAD@{%ct}%x09commit: %s")
             or "")
    parts = entry.strip().split("\t", 2)
    stamp = re.search(r"\{(\d+)\}", parts[1]) if len(parts) == 3 else None
    if stamp is None or not parts[2].startswith("commit"):
        return None                             # the newest HEAD move is no commit
    if now - int(stamp.group(1)) > COMMIT_WINDOW_SECONDS:
        return None
    head, subject = parts[0], parts[2].split(": ", 1)[-1]

    key = hashlib.md5(os.path.normcase(top).encode("utf-8")).hexdigest()[:12]
    state = os.path.join(state_dir, "claude-commit-audit-%s.txt" % key)
    try:
        with open(state, encoding="utf-8") as handle:
            if handle.read().strip() == head:
                return None                     # already examined
    except OSError:
        pass
    try:
        with open(state, "w", encoding="utf-8") as handle:
            handle.write(head)
    except OSError:
        pass

    names = git(top, "diff-tree", "-r", "-z", "--no-commit-id", "--name-only",
                "--root", "--diff-merges=first-parent", head)
    committed = [p for p in (names or "").split("\0") if p]

    fold = (lambda p: p.lower()) if os.name == "nt" else (lambda p: p)
    files, dirs, patterns, broad = {}, [], [], unparsed
    for subcommand, directory, args in found:
        paths, wide = named_paths(subcommand, args)
        broad = broad or wide
        for path in paths:
            full = resolve(path, directory)
            try:
                relative = os.path.relpath(full, top).replace("\\", "/")
            except ValueError:
                relative = path                 # another drive: cannot match
            if relative == ".":
                broad = True
            elif any(c in path for c in "*?["):
                patterns.append(fold(relative))
            elif os.path.isdir(full):
                dirs.append(fold(relative).rstrip("/") + "/")
            else:
                files[fold(relative)] = relative

    def is_named(path):
        k = fold(path)
        return (k in files or any(k.startswith(d) for d in dirs)
                or any(fnmatch.fnmatchcase(k, g) for g in patterns))

    unnamed = list(committed) if broad else [p for p in committed if not is_named(p)]
    keys = {fold(p) for p in committed}
    missing = sorted(shown for k, shown in files.items() if k not in keys)
    if not unnamed and not missing:
        return None

    lines = ["Commit %s %s holds %d file(s); verify this matches what you said "
             "it contains." % (head[:8], subject, len(committed))]
    if unnamed:
        if unparsed:
            why = "The command could not be parsed, so every file is listed"
        elif broad:
            why = ("The command staged broadly (-A, -u, -a or the whole tree), "
                   "so every file is listed")
        elif not (files or dirs or patterns):
            why = "The command named no files, so every file is listed"
        else:
            why = "Not named by the command"
        lines.append("%s (%d): %s" % (why, len(unnamed), listing(unnamed)))
    if missing:
        lines.append("Named by the command but not in the commit (%d): %s"
                     % (len(missing), listing(missing)))
    return "\n".join(lines)


# --- entry points --------------------------------------------------------

def guarded(name, check):
    """A check's note; a check that crashes says so instead of going quiet."""
    try:
        return check()
    except Exception as error:                  # a hook must not fail silently
        return "audit_shell_command.py: the %s check failed: %r" % (name, error)


def main():
    # Read stdin as BYTES and decode UTF-8 explicitly: sys.stdin uses the
    # locale encoding (cp1252 on Windows), which mangles a multi-byte
    # character in the command.
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except ValueError:
        return 0
    if not isinstance(payload, dict):
        return 0
    command = (payload.get("tool_input") or {}).get("command") or ""
    if not command:
        return 0

    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    cwd = payload.get("cwd") or root
    powershell = payload.get("tool_name") == "PowerShell"
    now = time.time()
    notes = [
        guarded("control-character", lambda: control_report(root, now)),
        guarded("commit", lambda: commit_report(
            command, cwd, now, tempfile.gettempdir(), powershell)),
    ]
    notes = [note for note in notes if note]
    if not notes:
        return 0
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": "\n\n".join(notes),
        },
    }))
    return 0


def self_test():
    """Each report firing and staying silent, in a scratch repository."""
    failures = []

    def expect(name, condition):
        print("  %s  %s" % ("pass" if condition else "FAIL", name))
        if not condition:
            failures.append(name)

    scratch = tempfile.mkdtemp(prefix="audit_shell_command_")
    repo = os.path.join(scratch, "repo")
    state = os.path.join(scratch, "state")
    os.makedirs(os.path.join(repo, "sub"))
    os.makedirs(state)

    def run(*args):
        subprocess.run(["git", *args], cwd=repo, capture_output=True, check=True)

    def put(relative, text="x\n"):
        full = os.path.join(repo, relative)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as handle:
            handle.write(text.encode("utf-8"))
        return full

    def commit(message, *paths):
        for path in paths:
            put(path)
        run("add", "-A")
        run("commit", "-q", "-m", message)

    def report(command, powershell=False, now=None):
        return commit_report(command, repo, time.time() if now is None else now,
                             state, powershell)

    def age(full):
        old = time.time() - WINDOW_SECONDS - 60
        os.utime(full, (old, old))

    try:
        run("init", "-q")
        run("config", "user.name", "self-test")
        run("config", "user.email", "self-test@example.invalid")
        run("config", "core.autocrlf", "false")
        commit("base", "base.txt")

        commit("a", "a.txt")
        expect("a commit holding exactly the named files is silent",
               report("git add a.txt && git commit -m a") is None)

        put("b.txt")
        run("add", "b.txt")
        commit("c", "c.txt")
        out = report("git add c.txt && git commit -m c") or ""
        expect("a file staged before the command is reported",
               "Not named by the command (1): b.txt" in out)
        expect("a commit is examined once",
               report("git add c.txt && git commit -m c") is None)

        commit("d", "d.txt")
        expect("a command that only mentions git commit adds nothing",
               report('grep -n "git commit" notes.md') is None)
        run("switch", "-q", "-c", "side")
        expect("a commit command whose newest HEAD move is a checkout adds nothing",
               report("git add z.txt && git commit -m z") is None)

        commit("e", "e.txt")
        out = report("git add e.txt base.txt && git commit -m e") or ""
        expect("a named file the commit lacks is reported",
               "Named by the command but not in the commit (1): base.txt" in out)

        commit("many", *["many/f%02d.txt" % n for n in range(12)])
        out = report("git add --all && git commit -m many") or ""
        expect("a broad add lists the commit, capped",
               "staged broadly" in out and "(12)" in out and "and 2 more" in out)
        commit("o", "o.txt")
        out = report("git add -vu && git commit -m o") or ""
        expect("a broad flag inside a short-option cluster is broad",
               "staged broadly" in out)

        commit("sub", "sub/g.txt", "sub/h.txt")
        expect("cd and a named directory cover its files",
               report("cd sub && git add . && git commit -m sub") is None)

        commit("i", "sub/i.txt")
        expect("PowerShell: -C, and a here-string holding an apostrophe",
               report("git -C sub add i.txt; git commit -m @'\nit's done\n'@",
                      powershell=True) is None)

        if os.name == "nt":
            commit("j", "sub/j.txt")
            expect("PowerShell: a backslash path",
                   report("git add sub\\j.txt; git commit -m j",
                          powershell=True) is None)

        commit("k", "k.txt")
        expect("bash: a heredoc message is not read as paths",
               report("git add k.txt && git commit -F - <<'EOF'\n"
                      "k: it's done\n"
                      "EOF\n") is None)
        commit("p", "p.txt")
        expect("bash: a heredoc inside a quoted command substitution",
               report("git add p.txt && git commit -m \"$(cat <<'EOF'\n"
                      "p: it's \"quoted\"\n"
                      "EOF\n"
                      ")\"") is None)

        run("rm", "-q", "k.txt")
        run("commit", "-q", "-m", "rm k")
        expect("git rm names the file it removes",
               report("git rm k.txt && git commit -m 'rm k'") is None)

        commit("l", "l.txt")
        expect("redirects and a comment are not read as paths",
               report("git add l.txt 2>/dev/null # stage\n"
                      "git commit -m l > out.txt") is None)

        commit("m", "m.txt")
        late = time.time() + COMMIT_WINDOW_SECONDS + 60
        expect("a commit older than the window is not this command's",
               report("git add x.txt && git commit -m m", now=late) is None)
        expect("the same commit inside the window is reported",
               report("git add x.txt && git commit -m m") is not None)

        ctl = put("ctl.txt", "a" + chr(8) + "b")
        out = control_report(repo, time.time()) or ""
        expect("a control character in a changed file is reported",
               "ctl.txt: 0x08 at offset 1" in out)
        age(ctl)
        put("clean.txt", "plain\ttext\r\n")
        expect("plain text, and a file older than the window, are not reported",
               control_report(repo, time.time()) is None)
        put("r1.txt")
        run("add", "r1.txt")
        run("commit", "-q", "-m", "r1")
        run("mv", "r1.txt", "r 2.txt")
        renamed = put("r 2.txt", chr(7))
        out = control_report(repo, time.time()) or ""
        expect("a renamed file with a space in its name is read",
               "r 2.txt: 0x07" in out and "r1.txt" not in out)
        age(renamed)

        commit("n", "n.txt")
        env = dict(os.environ, CLAUDE_PROJECT_DIR=repo, TMP=state, TEMP=state,
                   TMPDIR=state)

        def hook(tool, command):
            data = json.dumps({"tool_name": tool, "cwd": repo,
                               "tool_input": {"command": command}}).encode("utf-8")
            done = subprocess.run([sys.executable, os.path.abspath(__file__)],
                                  input=data, env=env, capture_output=True,
                                  timeout=60)
            return done.returncode, done.stdout.decode("utf-8", "replace")

        code, out = hook("PowerShell", "git add base.txt; git commit -m n")
        expect("stdin: a PowerShell commit is reported as PostToolUse context",
               code == 0 and '"hookEventName": "PostToolUse"' in out
               and "n.txt" in out)
        code, out = hook("Bash", "git status")
        expect("stdin: a quiet command prints nothing", code == 0 and out.strip() == "")
    finally:
        for folder, _, names in os.walk(scratch):
            for name in names:
                try:
                    os.chmod(os.path.join(folder, name), stat.S_IWRITE)
                except OSError:
                    pass
        shutil.rmtree(scratch, ignore_errors=True)

    print("self-test: %d failed" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else main())
