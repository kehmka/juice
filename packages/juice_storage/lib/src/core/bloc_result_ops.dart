import 'package:juice/juice.dart';

import 'operation_result.dart';
import 'result_event.dart';

/// Extension providing concurrency-safe result operations on [JuiceBloc].
///
/// These methods filter by the specific event instance using [identical],
/// ensuring concurrent operations never interfere with each other.
extension JuiceBlocResultOps<TState extends BlocState> on JuiceBloc<TState> {
  /// Sends a [ResultEvent] and returns the final status plus typed value.
  ///
  /// This is the core concurrency-safe dispatch method. It:
  /// 1. Listens for status updates BEFORE sending (to avoid missing fast emissions)
  /// 2. Filters by the exact event instance using [identical]
  /// 3. Awaits the event's result completer for the typed value
  ///
  /// Example:
  /// ```dart
  /// final op = await sendAndWaitResult<String?>(PrefsReadEvent(key: 'theme'));
  /// if (op.isSuccess) {
  ///   print('Value: ${op.value}');
  /// }
  /// ```
  Future<OperationResult<TResult, TState>> sendAndWaitResult<TResult>(
    ResultEvent<TResult> event, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Listen BEFORE sending to avoid missing fast emissions.
    final statusFuture = stream
        .where((s) => identical(s.event, event))
        .firstWhere((s) => s is! WaitingStatus<TState>)
        .timeout(timeout);

    send(event);

    final status = await statusFuture;

    // If the use case emitted failure/cancel, don't wait for a value.
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

    // Success path: await the value (completed by the use case).
    final value = await event.result.timeout(timeout);
    return OperationResult(status: status, value: value);
  }

  /// Convenience method that unwraps the value or throws on failure.
  ///
  /// Use this when you want simple error propagation via exceptions.
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   await sendForResult<void>(PrefsWriteEvent(key: 'theme', value: 'dark'));
  /// } catch (e) {
  ///   // Handle error
  /// }
  /// ```
  Future<TResult> sendForResult<TResult>(
    ResultEvent<TResult> event, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final op = await sendAndWaitResult<TResult>(event, timeout: timeout);

    if (op.isSuccess) {
      return op.value as TResult;
    }

    final err = op.error ?? StateError('Operation failed');
    Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
  }
}
