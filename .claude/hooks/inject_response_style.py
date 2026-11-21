#!/usr/bin/env python3
"""UserPromptSubmit: send the Response style section of AGENTS.md with every
user message.

The plain stdout of a UserPromptSubmit hook reaches Claude as a system reminder
beside the user's message and is not shown as a chat message
(code.claude.com/docs/en/hooks). The section is read on every call, so
AGENTS.md stays the rules' only source, and it is sent whole with every
message, so the self-test fails when it passes MAX_CHARS. A missing section is
reported to Claude rather than skipped: a hook that sends nothing looks the
same as one that never ran.

`--self-test` runs the cases in self_test().
"""

import os
import re
import subprocess
import sys
import tempfile

SECTION = "Response style"
MAX_CHARS = 1200
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def section(text, heading=SECTION):
    """The stripped body of the `## <heading>` section of `text`, or None."""
    text = text.replace("\r\n", "\n")
    pattern = r"^## %s[ \t]*\n(.*?)(?=^## |\Z)" % re.escape(heading)
    match = re.search(pattern, text, re.M | re.S)
    if match is None:
        return None
    return match.group(1).strip() or None


def context_for(root):
    """The text this hook prints for the repository at `root`."""
    try:
        with open(os.path.join(root, "AGENTS.md"), encoding="utf-8") as handle:
            body = section(handle.read())
    except OSError:
        body = None
    if body is None:
        return ("AGENTS.md has no '## %s' section, so its rules were not sent "
                "with this message; tell the user.\n" % SECTION)
    return "The %s rules of AGENTS.md, for this reply:\n\n%s\n" % (SECTION, body)


def main():
    sys.stdout.write(context_for(ROOT))
    return 0


def self_test():
    """Each extraction case, the repository's own section, and the script end
    to end."""
    failures = []

    def expect(name, condition):
        print("  %s  %s" % ("pass" if condition else "FAIL", name))
        if not condition:
            failures.append(name)

    doc = "# T\n\n## Before\n\nb\n\n## Response style\n\n1. One.\n2. Two.\n\n## After\n\na\n"
    expect("the section between two others is its body alone",
           section(doc) == "1. One.\n2. Two.")
    expect("the section at the end of the file runs to the end",
           section("## Response style\n\n1. Last.\n") == "1. Last.")
    expect("CRLF line endings give the same body as LF",
           section(doc.replace("\n", "\r\n")) == "1. One.\n2. Two.")
    expect("a subsection stays inside the section",
           section("## Response style\n\n1. A.\n\n### Sub\n\nx\n\n## Next\n")
           == "1. A.\n\n### Sub\n\nx")
    expect("a heading that only starts with the name is not the section",
           section("## Response styles\n\n1. No.\n") is None)
    expect("an empty section counts as missing",
           section("## Response style\n\n## Next\n\nx\n") is None)

    scratch = tempfile.mkdtemp()
    try:
        missing = context_for(scratch)
        expect("a missing AGENTS.md is reported, not skipped",
               "were not sent" in missing)
        with open(os.path.join(scratch, "AGENTS.md"), "w", encoding="utf-8") as handle:
            handle.write("# A\n\n## Other\n\nx\n")
        expect("an AGENTS.md without the section is reported, not skipped",
               "were not sent" in context_for(scratch))
        with open(os.path.join(scratch, "AGENTS.md"), "w", encoding="utf-8") as handle:
            handle.write(doc)
        expect("a found section is sent whole",
               context_for(scratch).endswith("\n\n1. One.\n2. Two.\n"))
    finally:
        for name in os.listdir(scratch):
            os.remove(os.path.join(scratch, name))
        os.rmdir(scratch)

    try:
        with open(os.path.join(ROOT, "AGENTS.md"), encoding="utf-8") as handle:
            own = section(handle.read())
    except OSError:
        own = None
    expect("this repository's AGENTS.md has the section", own is not None)
    expect("the section is a numbered list",
           own is not None and re.search(r"^1\. ", own, re.M) is not None)
    expect("the section is at most %d characters" % MAX_CHARS,
           own is not None and len(own) <= MAX_CHARS)

    run = subprocess.run([sys.executable, os.path.abspath(__file__)],
                         capture_output=True, text=True, timeout=30)
    expect("the script exits 0 and prints the repository's section",
           run.returncode == 0 and own is not None and run.stdout.endswith(own + "\n"))

    print("self-test: %d failed" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else main())
