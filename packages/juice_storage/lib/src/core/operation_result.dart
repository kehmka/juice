import 'package:juice/juice.dart';

/// Wraps the final [StreamStatus] for an operation plus the typed result value.
///
/// This provides a concurrency-safe way to return results from use cases
/// without storing them in shared state.
class OperationResult<TResult, TState extends BlocState> {
  OperationResult({
    required this.status,
    this.value,
  });

  /// The final stream status from the use case.
  final StreamStatus<TState> status;

  /// The result value (null if operation failed or returned null).
  final TResult? value;

  /// Whether the operation succeeded (emitted [UpdatingStatus]).
  bool get isSuccess => status is UpdatingStatus<TState>;

  /// Whether the operation failed (emitted [FailureStatus]).
  bool get isFailure => status is FailureStatus<TState>;

  /// Whether the operation was canceled (emitted [CancelingStatus]).
  bool get isCanceled => status is CancelingStatus<TState>;

  /// The failure status, if this operation failed.
  FailureStatus<TState>? get failure =>
      status is FailureStatus<TState> ? status as FailureStatus<TState> : null;

  /// The error from a failed operation.
  Object? get error => failure?.error;

  /// The stack trace from a failed operation.
  StackTrace? get errorStackTrace => failure?.errorStackTrace;
}
