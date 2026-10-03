# The failure-collecting probe harness

The problem it solves: an
`expect` throws, so the first failing assertion in a case SHADOWS every
one after it. Showing thirty assertions red one at a time is thirty
runs; showing them all in one run needs the throw caught.

## The harness

Generate a probe COPY of the test file, never edit the real one. A short
python transform wraps every statement in `main` that starts with
`expect(` (gather by paren balance until depth 0 and the line ends in
`;`) into:

```dart
probeCheck("L<original line number>", () {
  expect(...);
});
```

with

```dart
final List<String> probeFailures = <String>[];

void probeCheck(String label, void Function() body) {
  try {
    body();
  } catch (error) {
    probeFailures.add("$label -> " + error.toString().replaceAll(RegExp(r"\s+"), " "));
  }
}
```

and a `probeReport()` that `debugPrint`s each and clears. Label with the
ORIGINAL file's line number so the output maps straight back.

Three things that bit:

- **`debugPrint` needs `package:flutter/foundation.dart`.** A test file
  importing only `flutter_test` does not have it.
- **A failure message is multi-line.** Collapse it
  (`replaceAll(RegExp(r"\s+"), " ")`) or the grep only shows "Expected:"
  and you lose the ACTUAL value, which is the number that proves the
  variant did what you predicted.
- **Insert `probeReport()` at the END of each case, not after every
  `pumpAndSettle()`.** A case with a `pumpAndSettle` in its MIDDLE
  reports early and the assertions after it are silently never printed.
  That looked exactly like "those assertions are inert".

## Two classes of variant, and running both

- **`lib/` variants**: back the file up to the scratchpad first, patch
  with a python string replace that ASSERTS `count(old) == 1`, run,
  restore from the backup. On Windows the repo's `lib/` is CRLF and the
  test tree can be LF, so a heredoc `old` string with `\n` will not
  match; check `open(p,'rb').read().count(b'\r\n')` before writing the
  replace.
- **Test-side perturbations**: apply to the PROBE copy only, so the real
  file is never in a half-edited state when a run is interrupted.

## What it is really for

It answers "which assertions does this variant discriminate?" in one
run, which turns falsification into a small matrix: rows are variants,
columns are assertions, and any column that no row reddens is an INERT
assertion. In this landing that surfaced one: a per-item span assertion
on a cluster's DEEPEST member, which `lane + span <= laneCount` forces
to 1 under every legal rule. Deleted it and said why in the comment.

## The other thing it catches

A plan's named defeater variant that cannot fail. T10's plan text said
the case was red against an `_expandCluster` that skips exiting members.
Applying that variant left the case AND the whole module suite green.
The probe that settled it was not the harness but a one-line
`debugPrint` inside the function under test, reporting every call whose
cluster held an exiting member: zero hits in the case, zero across
`test/board`. An animated exit keeps the id registered until settle, so
the bucket is never re-resolved and the expansion never sees one. Reach
for that probe whenever a variant leaves everything green: the question
is not "is the assertion weak" but "does the code path run at all".
