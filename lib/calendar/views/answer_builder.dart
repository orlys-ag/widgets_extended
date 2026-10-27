/// A builder that builds again only where the answer it builds from
/// changes.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Builds [builder] from what [answer] gives, and at each notify of any of
/// [listenables] reads [answer] again and builds again only where the new
/// answer is not the same as the last, by [equals] or `==`.
///
/// For what a view shows of answers that most notifies leave as they are,
/// such as an edit policy's at a new minute: unlike a [ListenableBuilder],
/// a notify that changes no answer builds nothing. [child] passes through
/// to [builder] as it is, so a build of [builder] builds none of it again.
/// A new widget reads [answer] again and builds, as any widget does. An
/// [answer] that throws at a notify is reported by the notifier, and the
/// last answer stays.
class AnswerBuilder<A> extends StatefulWidget {
  const AnswerBuilder({
    super.key,
    required this.listenables,
    required this.answer,
    this.equals,
    required this.builder,
    this.child,
  });

  /// What notifies where the answer may have changed.
  final List<Listenable> listenables;

  /// The answer [builder] builds from, read when the state starts, at each
  /// new widget and at each notify.
  final A Function() answer;

  /// Whether two answers are the same, as [listEquals] is for a list; `==`
  /// where null.
  final bool Function(A a, A b)? equals;

  /// Builds from the last answer, with [child].
  final Widget Function(BuildContext context, A answer, Widget? child) builder;

  final Widget? child;

  @override
  State<AnswerBuilder<A>> createState() {
    return _AnswerBuilderState<A>();
  }
}

class _AnswerBuilderState<A> extends State<AnswerBuilder<A>> {
  late A _answer;

  @override
  void initState() {
    super.initState();
    _answer = widget.answer();
    for (final listenable in widget.listenables) {
      listenable.addListener(_handleChange);
    }
  }

  @override
  void didUpdateWidget(AnswerBuilder<A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.listenables, oldWidget.listenables)) {
      for (final listenable in oldWidget.listenables) {
        listenable.removeListener(_handleChange);
      }
      for (final listenable in widget.listenables) {
        listenable.addListener(_handleChange);
      }
    }
    _answer = widget.answer();
  }

  @override
  void dispose() {
    for (final listenable in widget.listenables) {
      listenable.removeListener(_handleChange);
    }
    super.dispose();
  }

  void _handleChange() {
    final answer = widget.answer();
    final equals = widget.equals;
    if (!(equals == null ? answer == _answer : equals(answer, _answer))) {
      setState(() {
        _answer = answer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _answer, widget.child);
  }
}
