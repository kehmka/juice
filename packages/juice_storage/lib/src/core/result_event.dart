import 'package:juice/juice.dart';

/// Base class for storage events that return typed results.
///
/// A core [ResultEvent] (juice ≥ 1.9.0 — the result/await machinery was
/// promoted there from this package) plus a [requestId] for correlating a
/// storage operation across logs and traces. Await it with the core
/// `bloc.sendForResult` / `bloc.sendAndWaitResult`.
///
/// Use cases must call [succeed] or [fail] to complete the result.
abstract class StorageResultEvent<TResult> extends ResultEvent<TResult> {
  StorageResultEvent({
    String? requestId,
    super.groupsToRebuild,
  }) : requestId = requestId ?? _newRequestId();

  /// Correlation id for logs / debugging / operation tracing.
  final String requestId;

  static int _counter = 0;

  static String _newRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'req_${now}_${_counter++}';
  }
}
