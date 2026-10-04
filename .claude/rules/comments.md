---
paths:
  - "lib/*.dart"
  - "lib/**/*.dart"
  - "test/*.dart"
  - "test/**/*.dart"
  - "examples/*.dart"
  - "examples/**/*.dart"
---

# Comments and doc comments

For every comment added to Dart source under `lib/`, `test/` and `examples/`.

- Document the public API with `///` doc comments: what the member does and its
  contract (parameters, return value, errors thrown, lifecycle, notifications
  fired). The public API is what `lib/widgets_extended.dart` exports; a name
  without an underscore that the barrels do not export is internal.
- Everywhere else, comment sparingly: only where the code cannot say it itself,
  such as a non-obvious algorithm, an invariant, an ordering constraint, or a
  framework behaviour the code depends on. Do not narrate what the next line
  does.
- A comment describes the code beside it, and the code that code calls or is
  called by, as it is now. It never references anything outside the source:
  plans, audits, reviews, finding IDs, issues, the changelog, other documents,
  dates, conversations, or the history of the change ("previously", "used to",
  "fixes the bug where"). History belongs in the commit message; a reason that
  must outlive the commit is stated as a property of the current code.
- Refer to other code by symbol, as a dartdoc link or a backticked name, never
  by `file:line`, and to Flutter behaviour by the framework symbol rather than
  an SDK line: line numbers in source go stale, and nothing checks them.
- Existing comments that break these rules are not a precedent, including for
  how densely to comment.
