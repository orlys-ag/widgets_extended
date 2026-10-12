#!/usr/bin/env python3
"""PreToolUse(Write|Edit): deny written text that carries a forbidden character.

It checks the WRITTEN TEXT (`content`, `new_string`, each `edits` entry)
before the write, so the bad text never lands:

  control    a control character other than tab, newline and carriage
             return, in any file. Escape sequences get consumed between the
             tool call and the file; a collapsed newline is a compile error,
             but a literal backspace (0x08) compiles and corrupts silently.
  symbol     a non-plain-text symbol (em-dash, arrow, bullet, emoji), which
             AGENTS.md forbids, in the file types of SYMBOL_CHECKED. Only the
             new text is checked, not the file: legacy files hold such
             characters, so a whole-file check would fire on every edit.

Two things are deliberately not flagged as symbols:

  * Box-drawing (U+2500-U+257F), used in deliberate section banners.
  * Dart string LITERALS. A bullet in a UI label is display text, not
    prose style. Comments, doc comments and identifiers are still checked.
    Only .dart gets this treatment: a literal in any other file is checked.

The literal scanner fails toward FLAGGING: a line it cannot parse is
checked in full. A false negative hides a real violation, a false positive
only asks a question.

`--self-test` runs the cases in self_test() without a payload.
"""

import json
import os
import subprocess
import sys

LEGAL_CONTROLS = {9, 10, 13}

SYMBOL_CHECKED = (".dart", ".md", ".yaml", ".yml", ".js", ".mjs", ".py", ".json",
                  ".ps1", ".sh")

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


def symbol_offenders(text, skip_strings):
    """(char, line_no, stripped_line) for each disallowed symbol."""
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


def control_offenders(text):
    """{code: first offset} for each illegal control character."""
    found = {}
    for index, char in enumerate(text):
        code = ord(char)
        if code < 32 and code not in LEGAL_CONTROLS:
            found.setdefault("0x%02x" % code, index)
    return found


def written_text(tool_input):
    """Edit writes new_string; Write writes content; MultiEdit carries a list."""
    # `or ""`, not a default: a key can be present with a null value.
    written = [tool_input.get("content") or "", tool_input.get("new_string") or ""]
    for edit in tool_input.get("edits") or []:
        if isinstance(edit, dict):
            written.append(edit.get("new_string") or "")
    return written


def denial(tool_input):
    """The reason to deny this write, or None to allow it."""
    path = tool_input.get("file_path") or ""
    written = written_text(tool_input)
    reasons = []

    controls = {}
    for chunk in written:
        for code, offset in control_offenders(chunk).items():
            controls.setdefault(code, offset)
    if controls:
        detail = ", ".join(
            "%s at offset %d" % item for item in sorted(controls.items()))
        reasons.append(
            "The text carries control characters (%s): an escape sequence was "
            "consumed before reaching the tool. Build the value with "
            "constructed characters (chr(10), chr(92)) instead of escapes, "
            "then read the file back to confirm." % detail)

    if path.endswith(SYMBOL_CHECKED):
        skip_strings = path.endswith(".dart")
        hits = [h for chunk in written for h in symbol_offenders(chunk, skip_strings)]
        if hits:
            shown = "; ".join(
                "U+%04X (new text line %d: %s)" % (ord(c), n, ascii(ln)[1:-1])
                for c, n, ln in hits[:4])
            more = "" if len(hits) <= 4 else " and %d more" % (len(hits) - 4)
            reasons.append(
                "AGENTS.md forbids non-plain-text symbols; the text holds %d: "
                "%s%s. Replace each with ASCII (a colon, semicolon, comma, "
                "parenthesis, or a separate sentence in place of a dash). "
                "Box-drawing banners and Dart string literals are not counted."
                % (len(hits), shown, more))

    if not reasons:
        return None
    return "Nothing was written to %s. %s" % (path or "the file", " ".join(reasons))


def main():
    # Read stdin as BYTES and decode UTF-8 explicitly. sys.stdin uses the
    # locale encoding (cp1252 on Windows), which mangles a multi-byte
    # character into several and, for bytes undefined in cp1252 (0x90 in
    # U+2010), raises UnicodeDecodeError, a ValueError, which the except
    # below would swallow, so the violation would be missed silently.
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except ValueError:
        return 0
    if not isinstance(payload, dict):
        return 0

    reason = denial(payload.get("tool_input") or {})
    if reason is None:
        return 0
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        },
    }))
    return 0


def self_test():
    """Each check passing and failing, and the stdin path end to end."""
    failures = []

    def expect(name, condition):
        print("  %s  %s" % ("pass" if condition else "FAIL", name))
        if not condition:
            failures.append(name)

    em, arrow, bullet, hyphen, box = (
        chr(0x2014), chr(0x2192), chr(0x2022), chr(0x2010), chr(0x2500))
    denied = lambda tool_input: denial(tool_input) is not None

    expect("plain text with tab, newline and CR is allowed",
           not denied({"file_path": "a.md", "content": "a\tb\nc\r\n"}))
    expect("backspace in Write content is denied",
           denied({"file_path": "a.md", "content": "a" + chr(8) + "b"}))
    expect("control character is denied in a file type with no symbol check",
           denied({"file_path": "a.bin", "new_string": chr(27)}))
    expect("control character in one MultiEdit entry is denied",
           denied({"file_path": "a.dart", "edits": [{"new_string": "x"},
                                                  {"new_string": chr(0)}]}))
    expect("em-dash in Markdown is denied",
           denied({"file_path": "a.md", "content": "a " + em + " b"}))
    expect("arrow in a Python Edit is denied",
           denied({"file_path": "a.py", "new_string": "# a " + arrow + " b"}))
    expect("symbol in a file type with no symbol check is allowed",
           not denied({"file_path": "a.txt", "content": em}))
    expect("box-drawing banner is allowed",
           not denied({"file_path": "a.dart", "new_string": "// " + box * 10}))
    expect("bullet inside a Dart string literal is allowed",
           not denied({"file_path": "a.dart",
                       "new_string": 'final s = "' + bullet + ' item";'}))
    expect("bullet inside a Dart raw string literal is allowed",
           not denied({"file_path": "a.dart",
                       "new_string": "final s = r'" + bullet + " item';"}))
    expect("bullet inside a multi-line Dart string literal is allowed",
           not denied({"file_path": "a.dart",
                       "new_string": "final s = '''\n" + bullet + " item\n''';"}))
    expect("bullet in a Dart doc comment is denied",
           denied({"file_path": "a.dart", "new_string": "/// " + bullet + " item"}))
    expect("bullet in a Dart line comment is denied",
           denied({"file_path": "a.dart", "new_string": "// " + bullet + " item"}))
    expect("bullet in a Dart block comment is denied",
           denied({"file_path": "a.dart", "new_string": "/* " + bullet + " */"}))
    expect("bullet inside a JavaScript string literal is denied",
           denied({"file_path": "a.js",
                   "new_string": 'const s = "' + bullet + '";'}))
    expect("null fields are allowed",
           not denied({"file_path": None, "content": None, "new_string": None}))
    both = denial({"file_path": "a.md", "content": em + chr(8)}) or ""
    expect("one denial names both a control character and a symbol",
           "control characters" in both and "non-plain-text symbols" in both)
    expect("the denial reason is ASCII", all(ord(c) < 128 for c in both))

    def run(tool_input):
        data = json.dumps({"tool_name": "Write", "tool_input": tool_input},
                          ensure_ascii=False).encode("utf-8")
        done = subprocess.run([sys.executable, os.path.abspath(__file__)],
                              input=data, capture_output=True, timeout=30)
        return done.returncode, done.stdout.decode("utf-8", "replace")

    code, out = run({"file_path": "a.md", "content": "a " + hyphen + " b"})
    expect("stdin: U+2010 sent as raw UTF-8 is denied",
           code == 0 and '"permissionDecision": "deny"' in out)
    code, out = run({"file_path": "a.md", "content": "plain"})
    expect("stdin: plain text prints nothing", code == 0 and out.strip() == "")

    print("self-test: %d failed" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else main())
