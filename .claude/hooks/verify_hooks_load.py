"""SessionStart: report hooks that will not run.

Hooks fail OPEN. A hook whose script has a syntax error is skipped silently and
the tool call proceeds -- verified by breaking one and watching a Write succeed
with no warning. So a guard can be lost without anything saying so.

Three ways to lose one:
  broken     script does not compile
  missing    settings.json points at a script that is not on disk
  orphaned   script is on disk but registered nowhere, as when a sibling hook
             that shared its settings block is removed with that block

This cannot make hooks fail closed; that is harness behaviour. It makes the
loss visible.
"""
import glob
import json
import os
import sys


def main():
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    directory = os.path.join(root, ".claude", "hooks")
    settings_path = os.path.join(root, ".claude", "settings.json")
    self_name = os.path.basename(__file__)

    try:
        registered = json.dumps(json.load(io_open(settings_path)))
    except Exception:
        registered = None

    problems = []
    on_disk = set()
    for script in sorted(glob.glob(os.path.join(directory, "*.py"))):
        name = os.path.basename(script)
        on_disk.add(name)
        if name == self_name:
            continue
        # Compiled in memory: py_compile writes a .pyc into __pycache__,
        # which outlives the script it was compiled from.
        try:
            with open(script, "rb") as handle:
                compile(handle.read(), script, "exec")
        except Exception as error:
            problems.append("broken   %s: %s" % (name, error))
            continue
        if registered is not None and name not in registered:
            problems.append(
                "orphaned %s: on disk but registered in no hook" % name)

    if registered is not None:
        for name in sorted(set(_referenced(registered)) - on_disk):
            problems.append(
                "missing  %s: registered but not on disk" % name)

    _heartbeat(problems)
    if not problems:
        return
    print(json.dumps({
        "systemMessage": ("Hooks that will not run (hooks fail open, so their "
                          "protection is silently absent):\n" + "\n".join(problems)),
    }))


def _heartbeat(problems):
    """Record that this hook ran.

    Without it, a healthy run and a hook that never fired are both silence --
    which is the exact ambiguity this hook exists to remove for OTHER hooks.
    Written outside the repository so it creates no working-tree churn.
    """
    import hashlib
    import tempfile
    import time
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    key = hashlib.md5(root.encode("utf-8")).hexdigest()[:12]
    stamp = os.path.join(tempfile.gettempdir(), "claude-hook-heartbeat-%s.txt" % key)
    try:
        with open(stamp, "w", encoding="utf-8") as handle:
            handle.write(("%s ran at %s, %d problem(s)" + chr(10))
                         % (os.path.basename(__file__),
                            time.strftime("%Y-%m-%d %H:%M:%S"), len(problems)))
    except Exception:
        pass


def _referenced(registered):
    import re
    return re.findall(r"hooks/([A-Za-z0-9_]+\.py)", registered)


def io_open(path):
    return open(path, encoding="utf-8")


main()
