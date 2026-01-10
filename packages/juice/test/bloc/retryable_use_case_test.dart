import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// Test state
class TestState extends BlocState {
  final int value;
  final String? message;

  TestState({this.value = 0, this.message});

  TestState copyWith({int? value, String? message}) =>
      TestState(value: value ?? this.value, message: message ?? this.message);

  @override
  String toString() => 'TestState(value: $value, message: $message)';
}

// Test events
class FetchEvent extends EventBase {}

class CancellableFetchEvent extends CancellableEvent {}

// Use case that always succeeds
class SuccessfulUseCase extends BlocUseCase<TestBloc, FetchEvent> {
  @override
  Future<void> execute(FetchEvent event) async {
    emitUpdate(newState: TestState(value: 42, message: 'Success'));
  }
}

// Use case that fails N times then succeeds
class FailNTimesUseCase extends BlocUseCase<TestBloc, FetchEvent> {
  static int attemptCount = 0;
  static int failuresBeforeSuccess = 2;

  static void reset({int failures = 2}) {
    attemptCount = 0;
    failuresBeforeSuccess = failures;
  }

  @override
  Future<void> execute(FetchEvent event) async {
    attemptCount++;

    if (attemptCount <= failuresBeforeSuccess) {
      emitFailure(
        error: NetworkException('Attempt $attemptCount failed'),
        errorStackTrace: StackTrace.current,
      );
    } else {
      emitUpdate(newState: TestState(value: attemptCount, message: 'Success'));
    }
  }
}

// Use case that always fails
class AlwaysFailingUseCase extends BlocUseCase<TestBloc, FetchEvent> {
  static int attemptCount = 0;

  static void reset() {
    attemptCount = 0;
  }

  @override
  Future<void> execute(FetchEvent event) async {
    attemptCount++;
    emitFailure(
      error: NetworkException('Always fails'),
      errorStackTrace: StackTrace.current,
    );
  }
}

// Use case that fails with non-retryable error
class NonRetryableUseCase extends BlocUseCase<TestBloc, FetchEvent> {
  static int attemptCount = 0;

  static void reset() {
    attemptCount = 0;
  }

  @override
  Future<void> execute(FetchEvent event) async {
    attemptCount++;
    emitFailure(
      error: ValidationException('Invalid input', field: 'name'),
      errorStackTrace: StackTrace.current,
    );
  }
}

// Use case that throws instead of calling emitFailure
class ThrowingUseCase extends BlocUseCase<TestBloc, FetchEvent> {
  static int attemptCount = 0;

  static void reset() {
    attemptCount = 0;
  }

  @override
  Future<void> execute(FetchEvent event) async {
    attemptCount++;
    throw NetworkException('Thrown error');
  }
}

// Test bloc with retryable use case
class TestBloc extends JuiceBloc<TestState> {
  TestBloc(UseCaseBuilderGenerator useCaseBuilder)
      : super(TestState(), [useCaseBuilder], []);
}

void main() {
  group('BackoffStrategy', () {
    test('FixedBackoff returns constant duration', () {
      final backoff = FixedBackoff(Duration(seconds: 2));

      expect(backoff.delay(0), Duration(seconds: 2));
      expect(backoff.delay(1), Duration(seconds: 2));
      expect(backoff.delay(5), Duration(seconds: 2));
    });

    test('ExponentialBackoff grows exponentially', () {
      final backoff = ExponentialBackoff(
        initial: Duration(seconds: 1),
        multiplier: 2.0,
      );

      expect(backoff.delay(0), Duration(seconds: 1));
      expect(backoff.delay(1), Duration(seconds: 2));
      expect(backoff.delay(2), Duration(seconds: 4));
      expect(backoff.delay(3), Duration(seconds: 8));
    });

    test('ExponentialBackoff respects maxDelay', () {
      final backoff = ExponentialBackoff(
        initial: Duration(seconds: 1),
        multiplier: 2.0,
        maxDelay: Duration(seconds: 5),
      );

      expect(backoff.delay(0), Duration(seconds: 1));
      expect(backoff.delay(1), Duration(seconds: 2));
      expect(backoff.delay(2), Duration(seconds: 4));
      expect(backoff.delay(3), Duration(seconds: 5)); // Capped
      expect(backoff.delay(10), Duration(seconds: 5)); // Still capped
    });

    test('ExponentialBackoff with jitter varies delay', () {
      final backoff = ExponentialBackoff(
        initial: Duration(seconds: 1),
        jitter: true,
      );

      // With jitter, delay should be between 50-100% of calculated value
      final delays = List.generate(10, (i) => backoff.delay(0));

      // All delays should be between 500ms and 1000ms for attempt 0
      for (final delay in delays) {
        expect(delay.inMilliseconds, greaterThanOrEqualTo(500));
        expect(delay.inMilliseconds, lessThanOrEqualTo(1000));
      }

      // Delays should vary (not all the same)
      final uniqueDelays = delays.map((d) => d.inMilliseconds).toSet();
      expect(uniqueDelays.length, greaterThan(1));
    });

    test('LinearBackoff grows linearly', () {
      final backoff = LinearBackoff(
        initial: Duration(seconds: 1),
        increment: Duration(seconds: 1),
      );

      expect(backoff.delay(0), Duration(seconds: 1));
      expect(backoff.delay(1), Duration(seconds: 2));
      expect(backoff.delay(2), Duration(seconds: 3));
      expect(backoff.delay(3), Duration(seconds: 4));
    });

    test('LinearBackoff respects maxDelay', () {
      final backoff = LinearBackoff(
        initial: Duration(seconds: 1),
        increment: Duration(seconds: 2),
        maxDelay: Duration(seconds: 5),
      );

      expect(backoff.delay(0), Duration(seconds: 1));
      expect(backoff.delay(1), Duration(seconds: 3));
      expect(backoff.delay(2), Duration(seconds: 5)); // Capped
      expect(backoff.delay(10), Duration(seconds: 5)); // Still capped
    });
  });

  group('RetryableUseCaseBuilder', () {
    tearDown(() async {
      // Reset static counters
      FailNTimesUseCase.reset();
      AlwaysFailingUseCase.reset();
      NonRetryableUseCase.reset();
      ThrowingUseCase.reset();
    });

    test('succeeds immediately when use case succeeds', () async {
      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => SuccessfulUseCase(),
          maxRetries: 3,
          backoff: FixedBackoff(Duration(milliseconds: 10)),
        ),
      );

      final statuses = <StreamStatus<TestState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(FetchEvent());
      await Future.delayed(Duration(milliseconds: 100));

      await subscription.cancel();

      expect(statuses.any((s) => s is UpdatingStatus), isTrue);
      expect(bloc.state.value, 42);
      expect(bloc.state.message, 'Success');

      await bloc.close();
    });

    test('retries on failure and eventually succeeds', () async {
      FailNTimesUseCase.reset(failures: 2);

      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => FailNTimesUseCase(),
          maxRetries: 3,
          backoff: FixedBackoff(Duration(milliseconds: 10)),
        ),
      );

      final statuses = <StreamStatus<TestState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(FetchEvent());
      // Wait for retries: 2 failures with 10ms backoff each + some buffer
      await Future.delayed(Duration(milliseconds: 200));

      await subscription.cancel();

      expect(statuses.last, isA<UpdatingStatus>());
      expect(FailNTimesUseCase.attemptCount, 3); // 2 failures + 1 success
      expect(bloc.state.value, 3);

      await bloc.close();
    });

    test('exhausts retries and emits failure', () async {
      AlwaysFailingUseCase.reset();

      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => AlwaysFailingUseCase(),
          maxRetries: 3,
          backoff: FixedBackoff(Duration(milliseconds: 10)),
        ),
      );

      final statuses = <StreamStatus<TestState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(FetchEvent());
      // Wait for 4 attempts with 10ms backoff between each
      await Future.delayed(Duration(milliseconds: 200));

      await subscription.cancel();

      expect(statuses.last, isA<FailureStatus>());
      expect(AlwaysFailingUseCase.attemptCount, 4); // 1 initial + 3 retries

      final failureStatus = statuses.last as FailureStatus;
      expect(failureStatus.error, isA<NetworkException>());

      await bloc.close();
    });

    test('does not retry non-retryable JuiceException', () async {
      NonRetryableUseCase.reset();

      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => NonRetryableUseCase(),
          maxRetries: 3,
          backoff: FixedBackoff(Duration(milliseconds: 10)),
        ),
      );

      final statuses = <StreamStatus<TestState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(FetchEvent());
      await Future.delayed(Duration(milliseconds: 100));

      await subscription.cancel();

      expect(statuses.last, isA<FailureStatus>());
      expect(NonRetryableUseCase.attemptCount, 1); // No retries

      final failureStatus = statuses.last as FailureStatus;
      expect(failureStatus.error, isA<ValidationException>());

      await bloc.close();
    });

    test('retries when use case throws exception', () async {
      ThrowingUseCase.reset();

      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => ThrowingUseCase(),
          maxRetries: 2,
          backoff: FixedBackoff(Duration(milliseconds: 10)),
        ),
      );

      final statuses = <StreamStatus<TestState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(FetchEvent());
      await Future.delayed(Duration(milliseconds: 200));

      await subscription.cancel();

      expect(statuses.last, isA<FailureStatus>());
      expect(ThrowingUseCase.attemptCount, 3); // 1 initial + 2 retries

      await bloc.close();
    });

    test('calls onRetry callback before each retry', () async {
      FailNTimesUseCase.reset(failures: 2);
      final retryCalls = <(int, Object, Duration)>[];

      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => FailNTimesUseCase(),
          maxRetries: 3,
          backoff: FixedBackoff(Duration(milliseconds: 10)),
          onRetry: (attempt, error, delay) {
            retryCalls.add((attempt, error, delay));
          },
        ),
      );

      await bloc.send(FetchEvent());
      await Future.delayed(Duration(milliseconds: 200));

      expect(retryCalls.length, 2); // 2 retries before success
      expect(retryCalls[0].$1, 1); // First retry = attempt 1
      expect(retryCalls[1].$1, 2); // Second retry = attempt 2
      expect(retryCalls[0].$2, isA<NetworkException>());
      expect(retryCalls[0].$3, Duration(milliseconds: 10));

      await bloc.close();
    });

    test('uses custom retryWhen predicate', () async {
      AlwaysFailingUseCase.reset();

      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => AlwaysFailingUseCase(),
          maxRetries: 3,
          backoff: FixedBackoff(Duration(milliseconds: 10)),
          retryWhen: (error) => false, // Never retry
        ),
      );

      final statuses = <StreamStatus<TestState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(FetchEvent());
      await Future.delayed(Duration(milliseconds: 100));

      await subscription.cancel();

      expect(statuses.last, isA<FailureStatus>());
      expect(AlwaysFailingUseCase.attemptCount, 1); // No retries

      await bloc.close();
    });

    test('uses exponential backoff correctly', () async {
      FailNTimesUseCase.reset(failures: 3);
      final delays = <Duration>[];

      final bloc = TestBloc(
        () => RetryableUseCaseBuilder<TestBloc, TestState, FetchEvent>(
          typeOfEvent: FetchEvent,
          useCaseGenerator: () => FailNTimesUseCase(),
          maxRetries: 4,
          backoff: ExponentialBackoff(initial: Duration(milliseconds: 10)),
          onRetry: (attempt, error, delay) {
            delays.add(delay);
          },
        ),
      );

      await bloc.send(FetchEvent());
      // Wait for 4 attempts: 10ms + 20ms + 40ms + buffer
      await Future.delayed(Duration(milliseconds: 200));

      expect(delays.length, 3);
      expect(delays[0], Duration(milliseconds: 10)); // 10 * 2^0
      expect(delays[1], Duration(milliseconds: 20)); // 10 * 2^1
      expect(delays[2], Duration(milliseconds: 40)); // 10 * 2^2

      await bloc.close();
    });
  });

  group('RetryableUseCaseBuilder cancellation', () {
    test('stops retrying when event is cancelled', () async {
      _CancellableAlwaysFailingUseCase.reset();

      final bloc = TestBloc(
        () =>
            RetryableUseCaseBuilder<TestBloc, TestState, CancellableFetchEvent>(
          typeOfEvent: CancellableFetchEvent,
          useCaseGenerator: () => _CancellableAlwaysFailingUseCase(),
          maxRetries: 10,
          backoff: FixedBackoff(Duration(milliseconds: 50)),
        ),
      );

      final statuses = <StreamStatus<TestState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      final event = CancellableFetchEvent();

      // Start the operation (don't await - it runs in background)
      bloc.send(event);

      // Wait for first attempt, then cancel
      await Future.delayed(Duration(milliseconds: 100));
      event.cancel();

      // Wait for cancellation to be processed
      await Future.delayed(Duration(milliseconds: 100));

      await subscription.cancel();

      // Should have cancelled, not exhausted all retries
      expect(statuses.any((s) => s is CancelingStatus), isTrue);
      expect(_CancellableAlwaysFailingUseCase.attemptCount, lessThan(10));

      await bloc.close();
      _CancellableAlwaysFailingUseCase.reset();
    });
  });
}

// Cancellable version of always failing use case
class _CancellableAlwaysFailingUseCase
    extends BlocUseCase<TestBloc, CancellableFetchEvent> {
  static int attemptCount = 0;

  static void reset() {
    attemptCount = 0;
  }

  @override
  Future<void> execute(CancellableFetchEvent event) async {
    attemptCount++;
    emitFailure(
      error: NetworkException('Always fails'),
      errorStackTrace: StackTrace.current,
    );
  }
}
