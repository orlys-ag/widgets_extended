/// Reads a library's source text: the body of a class it declares, the
/// body of a constructor or method, the doc comment of a declaration, and
/// the URIs and show clauses of its directives; and lists the Dart files
/// Git holds under a directory. The scheduling and calendar modules' tests
/// of what a class holds, what its docs say and what a file imports share
/// them.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The body of the class [name] declares in [source], comments dropped, to
/// its matching brace.
String classBody(String source, String name) {
  final code = source
      .replaceAll(RegExp(r"/\*[\s\S]*?\*/"), "")
      .replaceAll(RegExp(r"//[^\n]*"), "");
  final start = code.indexOf(RegExp("class $name\\b"));
  expect(start, isNot(-1), reason: name);
  final open = code.indexOf("{", start);
  var depth = 1;
  var at = open + 1;
  while (depth > 0) {
    final char = code[at];
    if (char == "{") {
      depth++;
    } else if (char == "}") {
      depth--;
    }
    at++;
  }
  return code.substring(open + 1, at - 1);
}

/// The doc comment of the one line of [source] whose text, after its
/// indent and an optional `const `, starts with [declaration]: the `///`
/// lines above it, past its annotation lines, their markers and edge
/// spaces dropped and joined by single spaces, so a phrase wrapped across
/// two lines reads as one. Expects exactly one such line.
String docOf(String source, String declaration) {
  final lines = source.split("\n");
  final found = <int>[
    for (var index = 0; index < lines.length; index++)
      if (_withoutConst(lines[index].trimLeft()).startsWith(declaration)) index,
  ];
  expect(found, hasLength(1), reason: declaration);
  var at = found.single - 1;
  while (at >= 0 && lines[at].trimLeft().startsWith("@")) {
    at--;
  }
  final doc = <String>[];
  while (at >= 0 && lines[at].trimLeft().startsWith("///")) {
    doc.insert(0, lines[at].trimLeft().substring(3).trim());
    at--;
  }
  return doc
      .where((line) {
        return line.isNotEmpty;
      })
      .join(" ");
}

String _withoutConst(String text) {
  return text.startsWith("const ") ? text.substring(6) : text;
}

/// The URIs of the import and export directives of [source].
List<String> directiveUris(String source) {
  return <String>[
    for (final match in RegExp(
      r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""",
      multiLine: true,
    ).allMatches(source))
      match.group(1)!,
  ];
}

/// Each export directive of [source], the barrel at [barrel], a path from
/// the package root: the path it exports, resolved from the package root
/// against [barrel], and the names its `show` clause lists, null for a
/// directive with none.
List<({String path, List<String>? shown})> exportsOf(
  String source,
  String barrel,
) {
  return <({String path, List<String>? shown})>[
    for (final match in RegExp(
      r"""^\s*export\s+['"]([^'"]+)['"]\s*(?:show\s+([^;]+))?;""",
      multiLine: true,
    ).allMatches(source))
      (
        path: Uri.parse(barrel).resolve(match.group(1)!).path,
        shown: match.group(2)?.split(",").map((name) {
          return name.trim();
        }).toList(),
      ),
  ];
}

/// The Dart files under [directory], from the package root, where
/// `flutter test` runs: those Git tracks and the new ones it does not
/// ignore. Checks that Git ran.
List<String> trackedDartFiles(String directory) {
  final result = Process.runSync("git", <String>[
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
    "--",
    directory,
  ]);
  expect(result.exitCode, 0, reason: "${result.stderr}");
  return <String>[
    for (final line in (result.stdout as String).split("\n"))
      if (line.trim().endsWith(".dart")) line.trim(),
  ];
}

/// The body of the constructor or method of the file at [path] whose
/// declaration starts at the first occurrence of [declaration]: the text
/// between the brace after its parameters and the matching brace.
String constructorBody(String path, String declaration) {
  final source = File(path).readAsStringSync();
  final start = source.indexOf(declaration);
  expect(start, isNot(-1), reason: declaration);
  var at = source.indexOf("(", start) + 1;
  var depth = 1;
  while (depth > 0) {
    final char = source[at];
    if (char == "(") {
      depth++;
    } else if (char == ")") {
      depth--;
    }
    at++;
  }
  final open = source.indexOf("{", at);
  // The body starts at the brace after the parameters and any
  // initializers, which hold no brace.
  expect(source.substring(at, open), isNot(contains(";")), reason: declaration);
  depth = 1;
  at = open + 1;
  while (depth > 0) {
    final char = source[at];
    if (char == "{") {
      depth++;
    } else if (char == "}") {
      depth--;
    }
    at++;
  }
  return source.substring(open + 1, at - 1);
}
