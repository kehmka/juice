import '../../../bloc.dart';

/// Callback invoked before each retry attempt.
///
/// [attempt] - The retry attempt number (1 = first retry)
/// [error] - The error that caused the retry
/// [nextDelay] - How long until the next attempt
typedef OnRetryCallback = void Function(
  int attempt,
  Object error,
  Duration nextDelay,
);

/// A use case builder that automatically retries failed operations.
///
/// Wraps another use case and intercepts failures, retrying based on
/// configurable backoff strategy and retry conditions.
///
/// ## Basic Usage
///
/// ```dart
/// class MyBloc extends JuiceBloc<MyState> {
///   MyBloc() : super(MyState(), [
///     () => RetryableUseCaseBuilder(
///       typeOfEvent: FetchDataEvent,
///       useCaseGenerator: () => FetchDataUseCase(),
///       maxRetries: 3,
///       backoff: ExponentialBackoff(initial: Duration(seconds: 1)),
///     ),
///   ], []);
/// }
/// ```
///
/// ## How It Works
///
/// 1. The wrapped use case executes normally
/// 2. If it calls `emitFailure`, the error is captured
/// 3. If the error is retryable, waits (backoff) and retries
/// 4. On success (emitUpdate) or non-retryable error, stops
/// 5. After max retries, the final failure is emitted
///
/// ## Retry Conditions
///
/// By default, retries when:
/// - Error is a [JuiceException] with `isRetryable == true`
/// - Error is NOT a [JuiceException] (assumes retryable)
///
/// Custom retry logic:
/// ```dart
/// RetryableUseCaseBuilder(
///   // ...
///   retryWhen: (error) => error is NetworkException,
/// )
/// ```
///
/// ## Cancellation
///
/// If the event is [CancellableEvent] and gets cancelled during a retry
/// backoff, the operation aborts and emits [CancelingStatus].
class RetryableUseCaseBuilder<
    TBloc extends JuiceBloc<TState>,
    TState extends BlocState,
    TEvent extends EventBase> implements UseCaseBuilderBase {
  /// Creates a retryable use case builder.
  ///
  /// [typeOfEvent] - The event type this use case handles.
  /// [useCaseGenerator] - Factory for creating the wrapped use case.
  /// [maxRetries] - Maximum retry attempts (default: 3).
  /// [backoff] - Delay strategy between retries (default: exponential 1s).
  /// [retryWhen] - Custom predicate to determine if error is retryable.
  /// [onRetry] - Callback invoked before each retry attempt.
  /// [initialEventBuilder] - Optional builder for initial event on bloc start.
  RetryableUseCaseBuilder({
    required this.typeOfEvent,
    required this.useCaseGenerator,
    this.maxRetries = 3,
    BackoffStrategy? backoff,
    this.retryWhen,
    this.onRetry,
    UseCaseEventBuilder? initialEventBuilder,
  })  : backoff =
            backoff ?? ExponentialBackoff(initial: const Duration(seconds: 1)),
        _initialEventBuilder = initialEventBuilder;

  /// The event type this use case handles.
  final Type typeOfEvent;

  /// Factory function to create the wrapped use case.
  final UseCaseGenerator useCaseGenerator;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Strategy for calculating delay between retries.
  final BackoffStrategy backoff;

  /// Custom predicate to determine if an error should trigger a retry.
  ///
  /// If null, uses default logic:
  /// - [JuiceException] with `isRetryable == true` → retry
  /// - [JuiceException] with `isRetryable == false` → don't retry
  /// - Other exceptions → retry
  final bool Function(Object error)? retryWhen;

  /// Callback invoked before each retry attempt.
  ///
  /// Useful for logging or metrics.
  final OnRetryCallback? onRetry;

  final UseCaseEventBuilder? _initialEventBuilder;

  @override
  Type get eventType => typeOfEvent;

  @override
  UseCaseEventBuilder? get initialEventBuilder => _initialEventBuilder;

  @override
  UseCaseGenerator get generator =>
      () => _RetryableUseCase<TBloc, TState, TEvent>(
            useCaseGenerator: useCaseGenerator,
            maxRetries: maxRetries,
            backoff: backoff,
            retryWhen: retryWhen,
            onRetry: onRetry,
          );

  @override
  Future<void> close() async {
    // No resources to clean up
  }
}

/// Internal use case that wraps another use case with retry logic.
class _RetryableUseCase<
    TBloc extends JuiceBloc<TState>,
    TState extends BlocState,
    TEvent extends EventBase> extends UseCase<TBloc, TEvent> {
  final UseCaseGenerator useCaseGenerator;
  final int maxRetries;
  final BackoffStrategy backoff;
  final bool Function(Object error)? retryWhen;
  final OnRetryCallback? onRetry;

  _RetryableUseCase({
    required this.useCaseGenerator,
    required this.maxRetries,
    required this.backoff,
    this.retryWhen,
    this.onRetry,
  });

  @override
  Future<void> execute(TEvent event) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    BlocState? lastFailureState;
    Set<String>? lastFailureGroups;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      // Handle backoff delay for retries
      if (attempt > 0) {
        final delay = backoff.delay(attempt - 1);

        // Invoke retry callback
        onRetry?.call(attempt, lastError!, delay);

        // Log retry attempt
        JuiceLoggerConfig.logger.log(
          'Retrying operation',
          context: {
            'attempt': attempt,
            'maxRetries': maxRetries,
            'error': lastError.toString(),
            'delayMs': delay.inMilliseconds,
          },
        );

        // Wait for backoff duration
        await Future.delayed(delay);

        // Check for cancellation during backoff
        if (event is CancellableEvent && event.isCancelled) {
          emitCancel();
          return;
        }
      }

      // Track whether inner use case called emitFailure
      var failureCalled = false;
      Object? capturedError;
      StackTrace? capturedStackTrace;
      BlocState? capturedState;
      Set<String>? capturedGroups;

      // Track whether inner use case succeeded
      var successCalled = false;

      // Create fresh use case instance
      final innerUseCase = useCaseGenerator();
      innerUseCase.setBloc(bloc);

      // Wire up emit functions, intercepting emitFailure
      innerUseCase.emitUpdate = ({
        BlocState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild,
        bool skipIfSame = false,
      }) {
        successCalled = true;
        emitUpdate(
          newState: newState,
          aviatorName: aviatorName,
          aviatorArgs: aviatorArgs,
          groupsToRebuild: groupsToRebuild,
          skipIfSame: skipIfSame,
        );
      };

      innerUseCase.emitWaiting = ({
        BlocState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild,
      }) {
        emitWaiting(
          newState: newState,
          aviatorName: aviatorName,
          aviatorArgs: aviatorArgs,
          groupsToRebuild: groupsToRebuild,
        );
      };

      innerUseCase.emitFailure = ({
        BlocState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild,
        Object? error,
        StackTrace? errorStackTrace,
      }) {
        // Capture failure instead of emitting immediately
        failureCalled = true;
        capturedError = error;
        capturedStackTrace = errorStackTrace;
        capturedState = newState;
        capturedGroups = groupsToRebuild;
      };

      innerUseCase.emitCancel = ({
        BlocState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild,
      }) {
        emitCancel(
          newState: newState,
          aviatorName: aviatorName,
          aviatorArgs: aviatorArgs,
          groupsToRebuild: groupsToRebuild,
        );
      };

      innerUseCase.emitEvent = ({EventBase? event}) {
        emitEvent(event: event);
      };

      // Execute the inner use case
      try {
        await innerUseCase.execute(event);
      } catch (e, stack) {
        // Handle thrown exceptions as failures
        failureCalled = true;
        capturedError = e;
        capturedStackTrace = stack;
      }

      // If succeeded, we're done
      if (successCalled && !failureCalled) {
        return;
      }

      // If failed, check if we should retry
      if (failureCalled) {
        lastError = capturedError;
        lastStackTrace = capturedStackTrace;
        lastFailureState = capturedState;
        lastFailureGroups = capturedGroups;

        // Check if error is retryable
        if (!_shouldRetry(capturedError)) {
          // Not retryable - emit failure immediately
          break;
        }

        // Retryable - continue loop for next attempt
        continue;
      }

      // No success and no failure called - unusual, but treat as success
      return;
    }

    // All retries exhausted or non-retryable error
    JuiceLoggerConfig.logger.log(
      'Retry exhausted, emitting failure',
      context: {
        'totalAttempts': maxRetries + 1,
        'error': lastError?.toString(),
      },
    );

    emitFailure(
      newState: lastFailureState,
      groupsToRebuild: lastFailureGroups,
      error: lastError,
      errorStackTrace: lastStackTrace,
    );
  }

  /// Determines if an error should trigger a retry.
  bool _shouldRetry(Object? error) {
    if (error == null) return false;

    // Use custom predicate if provided
    if (retryWhen != null) {
      return retryWhen!(error);
    }

    // Default logic
    if (error is JuiceException) {
      return error.isRetryable;
    }

    // Non-JuiceException errors are retryable by default
    return true;
  }
}
