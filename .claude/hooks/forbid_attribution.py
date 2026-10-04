#!/usr/bin/env python3
"""PreToolUse: deny a git commit or pull request that attributes authorship to Claude.

AGENTS.md forbids naming Claude, Claude Code or Anthropic as author,
co-author or attribution anywhere, including commit messages and pull request
descriptions. This blocks before the command runs, for the Bash and the
PowerShell tool alike, rather than reporting after it lands.

It exists because the rule has a standing adversary: the default harness
instructions ask for a `Claude-Session:` trailer on every commit, so the
outcome otherwise depends on the model noticing the conflict each time.
"""

import json
import os
import re
import shlex
import sys

# Deliberately narrow. `Claude-Session:` and `Co-Authored-By: ... Claude`
# are trailers; "Generated with" is the other documented form; `--author`
# sets the author directly. A bare mention of Claude in prose (e.g.
# describing this hook) is not attribution and must not be blocked.
#
# The two trailers match anywhere, because a one-line -m message puts a
# trailer mid-line, and neither token occurs in ordinary prose. "Author:" and
# "Signed-off-by:" stay anchored to a line start, because they do appear
# mid-sentence in a message that is merely talking about them.
PATTERNS = [
    (re.compile(r"Co-Authored-By:", re.I), "Co-Authored-By trailer"),
    (re.compile(r"Claude-Session:", re.I), "Claude-Session trailer"),
    (re.compile(r"generated with\s+\S*\s*(claude|anthropic)", re.I), "'Generated with' line"),
    (re.compile(r"^\s*(Author|Signed-off-by):.*(claude|anthropic)", re.I | re.M),
     "authorship trailer naming Claude"),
    (re.compile(r"--author[= ]\s*[\"']?[^\"'\n]*(claude|anthropic)", re.I), "--author naming Claude"),
]


def tokens(command):
    try:
        return shlex.split(command, posix=True)
    except ValueError:
        return command.split()


def program(token):
    """A token's program name: `/usr/bin/git`, `git.exe` and `"git"` are `git`."""
    name = re.split(r"[\\/]", token.strip("\"'&"))[-1].lower()
    return name[:-4] if name.endswith(".exe") else name


def is_checked(command):
    """True if the command runs `git commit` or `gh pr create` / `gh pr edit`.

    Token-based, not a substring test: `git -C dir commit` and
    `cd sub && git commit` both contain a commit invocation but not the
    literal text "git commit". A stray token match (`echo commit && git
    status`) is harmless: PATTERNS below still decides the denial.
    """
    argv = tokens(command)
    names = [program(t) for t in argv]
    if "git" in names and "commit" in argv:
        return True
    return "gh" in names and "pr" in argv and ("create" in argv or "edit" in argv)


def message_from_file(command):
    """Contents of any message or body file the command names or reads."""
    argv = tokens(command)
    paths = []
    for i, tok in enumerate(argv):
        if tok in ("-F", "--file", "--body-file") and i + 1 < len(argv):
            paths.append(argv[i + 1])
        elif tok.startswith(("--file=", "--body-file=")):
            paths.append(tok.split("=", 1)[1])
    paths += re.findall(r"\$\(\s*(?:cat|Get-Content)\s+[\"']?([^\s\"')]+)", command)
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    out = []
    for path in paths:
        for candidate in (path, os.path.join(root, path)):
            try:
                with open(candidate, encoding="utf-8", errors="replace") as fh:
                    out.append(fh.read())
                break
            except OSError:
                continue
    return "\n".join(out)


def main():
    # Read stdin as BYTES and decode UTF-8 explicitly. sys.stdin uses the
    # locale encoding (cp1252 on Windows), which mangles a multi-byte
    # character into several and, for bytes undefined in cp1252 (0x90 in
    # U+2010), raises UnicodeDecodeError -- a ValueError, so the except
    # below would swallow it and the violation would be missed silently.
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except (json.JSONDecodeError, ValueError):
        return 0

    command = (payload.get("tool_input") or {}).get("command", "")
    if not is_checked(command):
        return 0

    # `-F file` / `--file=file` keeps the message out of the command string,
    # so scan the file too or the check is trivially bypassed.
    # Newline-joined, not concatenated: the file's FIRST line would
    # otherwise merge into the command line and defeat the ^ anchors.
    text = command + "\n" + message_from_file(command)

    found = [label for rx, label in PATTERNS if rx.search(text)]
    if not found:
        return 0

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "AGENTS.md: never add Claude, Claude Code or Anthropic as "
                "author, co-author or attribution. This message contains "
                "a %s. Remove it and run the command again."
                % ", ".join(found)),
        },
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
