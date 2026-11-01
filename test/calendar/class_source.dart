/// Reads a library's source text: the body of a class it declares, and the
/// doc comment of a declaration, which the tests of what a class holds and
/// what its docs say share.
library;

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
