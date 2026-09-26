import 'dart:async';

import 'bloc_event.dart';
import 'bloc_state.dart';
import 'juice_bloc.dart';
import 'stream_status.dart';

// Events that return a typed value, and the one way to await them.
//
// Promoted to core in 1.9.0 from juice_storage (StorageResultEvent,
// OperationResult, sendAndWaitResult/sendForResult), where it was the complete
// version of a pattern the family had re-derived four ways. juice_storage now
// builds on these.

/// Base class for events that return typed results.
///
/// Each event instance carries its own [Completer], ensuring concurrent
/// operations never interfere with each other's results.
///
/// Use cases must call [succeed] or [fail] to complete the result.
abstract class ResultEvent<TResult> extends EventBase {
  ResultEvent({super.groupsToRebuild});

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
}

/// The outcome of [ResultEventOps.sendAndWaitResult]: the terminal status the
/// use case emitted for the event, and the value it completed the event with
/// (null unless [isSuccess]).
class OperationResult<TResult, TState extends BlocState> {
  /// Creates an operation result.
  OperationResult({
    required this.status,
    this.value,
  });

  /// The terminal status (updating, failure or canceling) for this event.
  final StreamStatus<TState> status;

  /// The value the use case completed the event with, when successful.
  final TResult? value;

  /// Whether the operation succeeded.
  bool get isSuccess => status is UpdatingStatus<TState>;

  /// Whether the operation failed.
  bool get isFailure => status is FailureStatus<TState>;

  /// Whether the operation was canceled.
  bool get isCanceled => status is CancelingStatus<TState>;

  /// The failure status, if this operation failed.
  FailureStatus<TState>? get failure =>
      status is FailureStatus<TState> ? status as FailureStatus<TState> : null;

  /// The error from a failed operation.
  Object? get error => failure?.error;

  /// The stack trace from a failed operation.
  StackTrace? get errorStackTrace => failure?.errorStackTrace;
}

/// Send a [ResultEvent] and await its outcome.
///
/// The contract a use case handling a [ResultEvent] follows: emit a terminal
/// status for the event (`emitUpdate` on success, `emitFailure` /
/// `emitCancel` otherwise) and, on success, call `event.succeed(value)`.
extension ResultEventOps<TState extends BlocState> on JuiceBloc<TState> {
  /// Sends [event] and returns its terminal status plus typed value.
  ///
  /// Fails loud instead of waiting out [timeout] when the outcome is already
  /// known to be missing:
  /// - the bloc is closed or closing → [StateError] (the event is refused);
  /// - processing finished without a terminal status for this event (it was
  ///   dropped by a `droppable` builder, or the use case emitted nothing) →
  ///   [StateError];
  /// - the use case emitted success but never called `succeed` → the wait on
  ///   the value is bounded by [timeout].
  ///
  /// On failure or cancel the event's `result` is failed too (if the use case
  /// didn't), so any other awaiter of `event.result` is released.
  Future<OperationResult<TResult, TState>> sendAndWaitResult<TResult>(
    ResultEvent<TResult> event, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (isClosed || isClosing) {
      throw StateError(
          'sendAndWaitResult(${event.runtimeType}) on a closed or closing '
          '$runtimeType');
    }

    // Observe emissions synchronously, not through the stream: stream
    // delivery can land after send() completes, and waiting for it would mean
    // guessing (a timer, which also hangs fake-async tests).
    StreamStatus<TState>? terminal;
    final untap = tapEmissions((s) {
      if (terminal == null &&
          identical(s.event, event) &&
          s is! WaitingStatus<TState>) {
        terminal = s;
      }
    });
    try {
      // send() completes when processing is over, in every concurrency mode.
      await send(event).timeout(timeout);
    } finally {
      untap();
    }

    final status = terminal;
    if (status == null) {
      final error = StateError(
          '${event.runtimeType} finished without a terminal status — dropped '
          'by a droppable builder, or its use case emitted nothing');
      event.fail(error);
      throw error;
    }

    if (status is FailureStatus<TState> || status is CancelingStatus<TState>) {
      if (!event.isCompleted) {
        if (status is FailureStatus<TState>) {
          event.fail(
            status.error ?? StateError('Operation failed'),
            status.errorStackTrace,
          );
        } else {
          event.fail(StateError('Operation cancelled'));
        }
      }
      return OperationResult(status: status, value: null);
    }

    final value = await event.result.timeout(timeout);
    return OperationResult(status: status, value: value);
  }

  /// Sends [event] and returns its value, or throws the failure's error (with
  /// its stack trace). A cancel throws [StateError].
  Future<TResult> sendForResult<TResult>(
    ResultEvent<TResult> event, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final op = await sendAndWaitResult<TResult>(event, timeout: timeout);
    if (op.isSuccess) return op.value as TResult;
    final err = op.error ??
        StateError(op.isCanceled ? 'Operation cancelled' : 'Operation failed');
    Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
  }
}
