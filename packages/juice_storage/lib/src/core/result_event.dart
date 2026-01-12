import 'package:juice/juice.dart';

/// Base class for storage events that return typed results.
///
/// Each event instance carries its own [Completer], ensuring concurrent
/// operations never interfere with each other's results.
///
/// Use cases must call [succeed] or [fail] to complete the result.
abstract class StorageResultEvent<TResult> extends EventBase {
  StorageResultEvent({
    String? requestId,
    super.groupsToRebuild,
  }) : requestId = requestId ?? _newRequestId();

  /// Correlation id for logs / debugging / operation tracing.
  final String requestId;

  final Completer<TResult> _completer = Completer<TResult>();

  /// The future that completes when the use case finishes.
  Future<TResult> get result => _completer.future;

  /// Whether this event's result has been completed.
  bool get isCompleted => _completer.isCompleted;

  /// Complete the result successfully with [value].
  void succeed(TResult value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }

  /// Complete the result with an error.
  ///
  /// The error will be available when awaiting [result]. If the result
  /// is never awaited, the error is silently ignored to prevent unhandled
  /// exception warnings.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
      // Ignore unhandled error to prevent zone error handler from firing
      // when the result is never awaited (e.g., in tests).
      _completer.future.ignore();
    }
  }

  static int _counter = 0;

  static String _newRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'req_${now}_${_counter++}';
  }
}
