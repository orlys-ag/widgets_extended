/// The recorder of the errors Flutter reports, which tests that a gesture
/// or a write reports none, or reports one, share.
library;

import 'package:flutter/foundation.dart';

/// Runs [body] with [FlutterError.onError] recording each reported error
/// in the list it is given, and restores it after.
Future<void> recordingErrors(
  Future<void> Function(List<FlutterErrorDetails> errors) body,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body(errors);
  } finally {
    FlutterError.onError = previous;
  }
}
