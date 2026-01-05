# Retry Operations Guide

This guide covers the `RetryableUseCaseBuilder` for automatically retrying failed operations with configurable backoff strategies.

## Overview

Network requests, API calls, and other I/O operations can fail transiently. `RetryableUseCaseBuilder` wraps your use cases with automatic retry logic, eliminating boilerplate retry code.

## Basic Usage

```dart
class MyBloc extends JuiceBloc<MyState> {
  MyBloc() : super(MyState(), [
    () => RetryableUseCaseBuilder<MyBloc, MyState, FetchDataEvent>(
      typeOfEvent: FetchDataEvent,
      useCaseGenerator: () => FetchDataUseCase(),
      maxRetries: 3,
      backoff: ExponentialBackoff(initial: Duration(seconds: 1)),
    ),
  ], []);
}
```

## How It Works

1. Your use case executes normally
2. If it calls `emitFailure`, the error is captured
3. If the error is retryable, waits (backoff) and retries
4. On success (`emitUpdate`) or non-retryable error, stops
5. After max retries, the final failure is emitted

```
Event → RetryableUseCaseBuilder → YourUseCase.execute()
                                       ↓
                                  (executes)
                                       ↓
                         ┌─────────────┴─────────────┐
                         ↓                           ↓
                    emitUpdate()               emitFailure()
                         ↓                           ↓
                      Success!              Should retry?
                                              ↓         ↓
                                            Yes        No
                                              ↓         ↓
                                          Backoff   Final failure
                                              ↓
                                           Retry
```

## Backoff Strategies

### FixedBackoff

Constant delay between retries.

```dart
// Always wait 2 seconds between retries
backoff: FixedBackoff(Duration(seconds: 2))
// Delays: 2s, 2s, 2s, ...
```

### ExponentialBackoff

Delays grow exponentially, with optional jitter.

```dart
// Exponential growth: 1s, 2s, 4s, 8s...
backoff: ExponentialBackoff(initial: Duration(seconds: 1))

// With max cap
backoff: ExponentialBackoff(
  initial: Duration(seconds: 1),
  multiplier: 2.0,
  maxDelay: Duration(seconds: 30),
)

// With jitter (prevents thundering herd)
backoff: ExponentialBackoff(
  initial: Duration(seconds: 1),
  jitter: true,  // Randomizes 50-100% of calculated delay
)
```

### LinearBackoff

Delays grow by a fixed increment.

```dart
// Linear growth: 1s, 2s, 3s, 4s...
backoff: LinearBackoff(
  initial: Duration(seconds: 1),
  increment: Duration(seconds: 1),
)
```

## Retry Conditions

### Default Behavior

By default, `RetryableUseCaseBuilder` retries when:
- Error is a `JuiceException` with `isRetryable == true`
- Error is NOT a `JuiceException` (assumes retryable)

```dart
// NetworkException.isRetryable = true → retries
// ValidationException.isRetryable = false → doesn't retry
```

### Custom Retry Logic

Use `retryWhen` to customize:

```dart
RetryableUseCaseBuilder(
  // ...
  retryWhen: (error) {
    // Only retry network errors
    if (error is NetworkException) return true;
    // Retry specific HTTP status codes
    if (error is HttpException && error.statusCode >= 500) return true;
    return false;
  },
)
```

## Monitoring Retries

### onRetry Callback

Track retry attempts for logging or metrics:

```dart
RetryableUseCaseBuilder(
  // ...
  onRetry: (attempt, error, nextDelay) {
    print('Retry $attempt after ${nextDelay.inSeconds}s due to: $error');
    analytics.trackRetry(
      attempt: attempt,
      error: error.toString(),
      delayMs: nextDelay.inMilliseconds,
    );
  },
)
```

## Cancellation Support

If your event implements `CancellableEvent`, retries stop when cancelled:

```dart
class FetchDataEvent extends CancellableEvent {}

// Usage
final event = FetchDataEvent();
bloc.send(event);

// Later, if needed
event.cancel();  // Stops retry loop, emits CancelingStatus
```

## Use Case Requirements

Your wrapped use case should:
1. Call `emitFailure` on failure (or throw an exception)
2. Call `emitUpdate` on success

```dart
class FetchDataUseCase extends BlocUseCase<DataBloc, FetchEvent> {
  @override
  Future<void> execute(FetchEvent event) async {
    try {
      final data = await api.fetchData();
      emitUpdate(newState: DataState(data: data));
    } catch (e, stack) {
      emitFailure(
        error: NetworkException(e.toString()),
        errorStackTrace: stack,
      );
    }
  }
}
```

## Full Example

```dart
// Events
class FetchUserEvent extends EventBase {
  final String userId;
  FetchUserEvent(this.userId);
}

// Use case - just the happy path and error handling
class FetchUserUseCase extends BlocUseCase<UserBloc, FetchUserEvent> {
  final UserApi api;

  FetchUserUseCase(this.api);

  @override
  Future<void> execute(FetchUserEvent event) async {
    emitWaiting();

    try {
      final user = await api.getUser(event.userId);
      emitUpdate(newState: UserState.loaded(user));
    } on SocketException catch (e, stack) {
      emitFailure(
        error: NetworkException('Connection failed', cause: e),
        errorStackTrace: stack,
      );
    } on TimeoutException catch (e, stack) {
      emitFailure(
        error: JuiceTimeoutException('Request timed out', cause: e),
        errorStackTrace: stack,
      );
    }
  }
}

// Bloc with retry configuration
class UserBloc extends JuiceBloc<UserState> {
  UserBloc(UserApi api) : super(UserState.initial(), [
    () => RetryableUseCaseBuilder<UserBloc, UserState, FetchUserEvent>(
      typeOfEvent: FetchUserEvent,
      useCaseGenerator: () => FetchUserUseCase(api),
      maxRetries: 3,
      backoff: ExponentialBackoff(
        initial: Duration(seconds: 1),
        maxDelay: Duration(seconds: 10),
        jitter: true,
      ),
      retryWhen: (error) => error is NetworkException || error is JuiceTimeoutException,
      onRetry: (attempt, error, delay) {
        print('Retrying user fetch (attempt $attempt)');
      },
    ),
  ], []);
}
```

## Best Practices

### 1. Use Exponential Backoff with Jitter

For network operations, exponential backoff with jitter prevents thundering herd problems:

```dart
backoff: ExponentialBackoff(
  initial: Duration(seconds: 1),
  jitter: true,
)
```

### 2. Set Reasonable Max Retries

Don't retry forever. 3-5 retries is usually sufficient:

```dart
maxRetries: 3,
```

### 3. Cap Maximum Delay

Prevent extremely long delays:

```dart
backoff: ExponentialBackoff(
  initial: Duration(seconds: 1),
  maxDelay: Duration(seconds: 30),
)
```

### 4. Use Typed Exceptions

Use `JuiceException` hierarchy for proper retry decisions:

```dart
// Retryable
throw NetworkException('Server unavailable', statusCode: 503);

// Not retryable
throw ValidationException('Invalid email', field: 'email');
```

### 5. Log Retry Attempts

Track retries for debugging and monitoring:

```dart
onRetry: (attempt, error, delay) {
  logger.warning('Retry $attempt: $error');
},
```

## API Reference

### RetryableUseCaseBuilder

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `typeOfEvent` | `Type` | required | Event type this use case handles |
| `useCaseGenerator` | `UseCaseGenerator` | required | Factory for wrapped use case |
| `maxRetries` | `int` | `3` | Maximum retry attempts |
| `backoff` | `BackoffStrategy` | Exponential 1s | Delay strategy |
| `retryWhen` | `bool Function(Object)?` | null | Custom retry predicate |
| `onRetry` | `OnRetryCallback?` | null | Callback before each retry |
| `initialEventBuilder` | `UseCaseEventBuilder?` | null | Initial event on bloc start |

### BackoffStrategy

| Class | Parameters | Description |
|-------|------------|-------------|
| `FixedBackoff` | `duration` | Constant delay |
| `ExponentialBackoff` | `initial`, `multiplier`, `maxDelay`, `jitter` | Exponential growth |
| `LinearBackoff` | `initial`, `increment`, `maxDelay` | Linear growth |
