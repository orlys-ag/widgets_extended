#!/usr/bin/env python3
"""PostToolUse: reject non-plain-text symbols in text Claude just wrote.

AGENTS.md forbids em-dashes, en-dashes, arrows, bullets, emoji and the
like in code, comments and documentation. This checks the WRITTEN TEXT
(`new_string` / `content`), not the file: every .dart file in the
repository already holds 1476 such characters between them, so checking
whole files would fire on every edit to a legacy file and be switched off
within a day.

Two things are deliberately not flagged:

  * Box-drawing (U+2500-U+257F). Excluded from that 1476 and counted
    separately: 24811 repository-wide, 16407 of them under lib/, in
    deliberate section banners. Flagging those would swamp the real hits.
  * Dart string LITERALS. A bullet in a UI label is display text, not
    prose style. Comments, doc comments and identifiers are still checked.
    Only .dart gets this treatment: a literal in any other file is checked.

The literal scanner fails toward FLAGGING: a line it cannot parse is
checked in full. A false negative hides a real violation, a false positive
only asks a question.
"""

import json
import sys

# Ordered longest-first so ''' is not mistaken for '.
DELIMITERS = ('"""', "'''", '"', "'")

# Sentinel state: inside a /* */ block comment. Distinct from a string
# delimiter because its contents are CHECKED, and because a quote inside
# it must not open a string.
BLOCK = "/*"


def allowed(ch):
    return ord(ch) < 128 or 0x2500 <= ord(ch) <= 0x257F


def string_spans(line, state):
    """(indices inside a string literal, carried-over state).

    `state` is a delimiter or BLOCK left open by an earlier line, or None.
    Only string-literal indices are returned; comment text is deliberately
    left for the caller to check.
    """
    inside = set()
    st = state
    i, n = 0, len(line)
    while i < n:
        if st == BLOCK:
            end = line.find("*/", i)
            if end < 0:
                break                       # rest of line is comment: checked
            i = end + 2
            st = None
            continue
        if st is None:
            if line.startswith("//", i):
                break                       # to end of line: checked
            if line.startswith("/*", i):
                st = BLOCK
                i += 2
                continue
            opened = False
            for d in DELIMITERS:
                start = i + 1 if (line[i] == "r" and line.startswith(d, i + 1)) else i
                if line.startswith(d, start):
                    st = d
                    i = start + len(d)
                    opened = True
                    break
            if not opened:
                i += 1
            continue
        # Inside a string literal.
        if line[i] == "\\":
            inside.add(i)
            if i + 1 < n:
                inside.add(i + 1)
            i += 2
            continue
        if line.startswith(st, i):
            i += len(st)
            st = None
            continue
        inside.add(i)
        i += 1
    # A single- or double-quote still open at end of line means either a
    # misparse or an apostrophe in prose. Either way, check the line.
    if st in ('"', "'"):
        return set(), None
    return inside, st


def offenders(text, skip_strings):
    """(char, line_no, stripped_line) for each disallowed character."""
    out = []
    state = None
    for n, line in enumerate(text.splitlines(), 1):
        inside = ()
        if skip_strings:
            inside, state = string_spans(line, state)
        for i, ch in enumerate(line):
            if allowed(ch) or i in inside:
                continue
            out.append((ch, n, line.strip()[:70]))
    return out


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

    tool_input = payload.get("tool_input") or {}
    # `or ""`, not a default: the key can be present with a null value.
    path = tool_input.get("file_path") or ""
    if not path.endswith((".dart", ".md", ".yaml", ".yml", ".js", ".mjs", ".py", ".json")):
        return 0

    # Edit writes new_string; Write writes content; MultiEdit carries a list.
    written = [tool_input.get("new_string") or "", tool_input.get("content") or ""]
    for edit in tool_input.get("edits") or []:
        written.append(edit.get("new_string") or "")

    skip_strings = path.endswith(".dart")
    hits = [h for chunk in written for h in offenders(chunk, skip_strings)]
    if not hits:
        return 0

    shown = "; ".join("%r (new text line %d: %s)" % (c, n, ln) for c, n, ln in hits[:4])
    more = "" if len(hits) <= 4 else " and %d more" % (len(hits) - 4)
    print(json.dumps({
        "decision": "block",
        "reason": (
            "AGENTS.md forbids non-plain-text symbols. %s wrote %d: %s%s. "
            "Replace with ASCII (a colon, semicolon, comma, parenthesis, or a "
            "separate sentence in place of a dash). Box-drawing banners and "
            "Dart string literals are not counted."
            % (path, len(hits), shown, more)),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
