/// Guards the repo against UTF-8-as-ANSI mojibake.
///
/// Windows PowerShell 5.1 decodes BOM-less UTF-8 as the ANSI codepage,
/// so any scripted rewrite that round-trips file CONTENT as a string
/// (`Get-Content -Raw` → write) mangles every non-ASCII character —
/// each em dash shatters into a three-character sequence, box-drawing
/// separators dissolve, and string literals (tooltips!) silently stop
/// matching finders. This bit three separate times during the 0.0.32
/// style-migration wave.
///
/// The scan is byte-honest: files are read as strict UTF-8 (malformed
/// bytes throw — itself a guard) and checked for the three characters
/// that begin every UTF-8-as-CP1252 mojibake sequence. Genuine prose
/// never needs them; repaired files contain none.
///
/// Repair recipe on failure: iterative CP1252-encode → UTF-8-decode
/// with strict encoder/decoder fallbacks (multiple passes for
/// double-mojibake), then re-run this test.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test("no UTF-8-as-ANSI mojibake indicators in any source file", () {
    // U+00E2 / U+00C3 / U+00C2 — the characters that begin every
    // UTF-8-as-CP1252 mojibake sequence. Built from char codes so this
    // file stays pure ASCII and cannot trip its own scan.
    final indicators = RegExp(
      "[${String.fromCharCode(0xE2)}"
      "${String.fromCharCode(0xC3)}"
      "${String.fromCharCode(0xC2)}]",
    );
    final offenders = <String>[];
    for (final root in const ["lib", "test", "examples"]) {
      final dir = Directory(root);
      if (!dir.existsSync()) {
        continue;
      }
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith(".dart")) {
          continue;
        }
        final text = entity.readAsStringSync();
        if (indicators.hasMatch(text)) {
          offenders.add(entity.path);
        }
      }
    }
    expect(offenders, isEmpty,
        reason: "UTF-8-as-ANSI mojibake detected — a scripted rewrite "
            "decoded BOM-less UTF-8 as ANSI before writing. Repair with "
            "an iterative CP1252-encode → UTF-8-decode reversal (see "
            "this file's library docs), and fix the script to read "
            "BYTES as UTF-8, never Get-Content -Raw.");
  });
}
