# BlocTester - Simplified Bloc Testing

BlocTester is a utility class that simplifies testing Juice blocs by providing automatic stream tracking, convenient assertions, and proper cleanup handling.

## Overview

Testing blocs traditionally requires:
- Setting up stream subscriptions
- Waiting for async operations
- Manually tracking emissions
- Cleaning up resources

BlocTester handles all of this, letting you focus on writing meaningful tests.

## Basic Usage

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

void main() {
  late CounterBloc bloc;
  late BlocTester<CounterBloc, CounterState> tester;

  setUp(() {
    bloc = CounterBloc();
    tester = BlocTester(bloc);
  });

  tearDown(() async {
    await tester.dispose();
  });

  test('increments counter', () async {
    await tester.send(IncrementEvent());

    tester.expectState((state) => state.count == 1);
    tester.expectLastStatusIs<UpdatingStatus>();
  });
}
```

## Key Features

### Sending Events

```dart
// Simple send with default delay
await tester.send(IncrementEvent());

// Send with custom delay for slow operations
await tester.send(SlowEvent(), delay: Duration(milliseconds: 100));
```

### Awaiting Results

For async operations that emit `WaitingStatus` before completing:

```dart
test('API call completes successfully', () async {
  final status = await tester.sendAndWaitForResult(
    FetchDataEvent(),
    timeout: Duration(seconds: 5),
  );

  expect(status, isA<UpdatingStatus>());
  tester.expectState((state) => state.data != null);
});

test('API call fails with error', () async {
  final status = await tester.sendAndWaitForResult(
    FetchDataEvent(shouldFail: true),
  );

  expect(status, isA<FailureStatus>());
  final failure = status as FailureStatus;
  expect(failure.error, isA<NetworkException>());
});
```

### State Assertions

```dart
// Check state with predicate
tester.expectState((state) => state.count == 5);
tester.expectState((state) => state.items.isNotEmpty, 'Items should not be empty');

// Check exact state equality
tester.expectStateEquals(CounterState(count: 5));
```

### Status Assertions

```dart
// Check last emitted status type
tester.expectLastStatusIs<UpdatingStatus>();
tester.expectLastStatusIs<FailureStatus>();

// Check status sequence
tester.expectStatusSequence([WaitingStatus, UpdatingStatus]);

// Check for specific status occurrences
tester.expectWasWaiting();
tester.expectWasFailure();
tester.expectNoFailure();
```

### Emission Assertions

```dart
// Check emission count
tester.expectEmissionCount(3);

// Check any emission matches predicate
tester.expectAnyEmission((status) => status is UpdatingStatus);

// Check all emissions match predicate
tester.expectAllEmissions((status) => status.state.isValid);
```

## Accessing Raw Data

```dart
// Access all emissions
final allEmissions = tester.emissions;
print('Total emissions: ${allEmissions.length}');

// Access current state
final currentState = tester.state;

// Access last status
final lastStatus = tester.lastStatus;
final lastState = tester.lastState;
```

## Utility Methods

### Clearing Emissions

Reset emissions tracking between operations:

```dart
test('tracks operations independently', () async {
  await tester.send(IncrementEvent());
  tester.clearEmissions();

  await tester.send(DecrementEvent());

  // Only sees the decrement emission
  tester.expectEmissionCount(1);
});
```

### Waiting for Emissions

Wait for a specific number of emissions:

```dart
test('waits for multiple updates', () async {
  bloc.startBatchOperation(); // Emits multiple times

  await tester.waitForEmissions(5, timeout: Duration(seconds: 2));

  tester.expectEmissionCount(5);
});
```

## Testing Error Handling

```dart
test('handles network error with retry info', () async {
  final status = await tester.sendAndWaitForResult(
    FetchDataEvent(shouldFail: true),
  );

  expect(status, isA<FailureStatus>());
  final failure = status as FailureStatus;

  // Access error context from FailureStatus
  expect(failure.error, isA<NetworkException>());
  final error = failure.error as NetworkException;
  expect(error.statusCode, 500);
  expect(error.isRetryable, true);
  expect(error.isServerError, true);
});

test('handles validation error', () async {
  final status = await tester.sendAndWaitForResult(
    ValidateInputEvent(''),
  );

  expect(status, isA<FailureStatus>());
  final failure = status as FailureStatus;

  expect(failure.error, isA<ValidationException>());
  final error = failure.error as ValidationException;
  expect(error.field, 'email');
  expect(error.isRetryable, false);
});
```

## Testing Async Operations

```dart
test('shows loading state during API call', () async {
  tester.clearEmissions();

  await tester.send(FetchDataEvent());

  // Verify the loading -> complete sequence
  tester.expectWasWaiting();
  tester.expectStatusSequence([WaitingStatus, UpdatingStatus]);
});

test('sendAndWaitForResult with timeout', () async {
  // Will throw TimeoutException if operation takes too long
  final status = await tester.sendAndWaitForResult(
    SlowOperationEvent(),
    timeout: Duration(seconds: 10),
  );

  expect(status, isA<UpdatingStatus>());
});
```

## Extension Method

You can also create a tester directly from a bloc:

```dart
test('using extension method', () async {
  final bloc = CounterBloc();
  final tester = bloc.tester();

  await tester.send(IncrementEvent());
  tester.expectState((state) => state.count == 1);

  await tester.dispose();
});
```

## Best Practices

### 1. Always Dispose

```dart
tearDown(() async {
  await tester.dispose();
});
```

### 2. Clear Emissions Between Test Phases

```dart
test('multi-phase test', () async {
  // Phase 1: Setup
  await tester.send(SetupEvent());
  tester.expectState((state) => state.isReady);

  tester.clearEmissions();

  // Phase 2: Main operation
  await tester.send(MainOperationEvent());
  tester.expectStatusSequence([WaitingStatus, UpdatingStatus]);
});
```

### 3. Use sendAndWaitForResult for Async Operations

```dart
// Better than send() for async operations
final status = await tester.sendAndWaitForResult(AsyncEvent());

// Instead of
await tester.send(AsyncEvent());
await Future.delayed(Duration(seconds: 1)); // Fragile
```

### 4. Test Both Success and Failure Paths

```dart
group('API operations', () {
  test('succeeds with valid data', () async {
    final status = await tester.sendAndWaitForResult(
      FetchEvent(id: 'valid'),
    );
    expect(status, isA<UpdatingStatus>());
  });

  test('fails with invalid data', () async {
    final status = await tester.sendAndWaitForResult(
      FetchEvent(id: 'invalid'),
    );
    expect(status, isA<FailureStatus>());
  });
});
```

## Complete Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

void main() {
  group('TodoBloc', () {
    late TodoBloc bloc;
    late BlocTester<TodoBloc, TodoState> tester;

    setUp(() {
      bloc = TodoBloc();
      tester = BlocTester(bloc);
    });

    tearDown(() async {
      await tester.dispose();
    });

    test('adds todo item', () async {
      await tester.send(AddTodoEvent('Buy groceries'));

      tester.expectState((state) => state.todos.length == 1);
      tester.expectState((state) => state.todos.first.title == 'Buy groceries');
      tester.expectLastStatusIs<UpdatingStatus>();
    });

    test('toggles todo completion', () async {
      await tester.send(AddTodoEvent('Test'));
      final todoId = tester.state.todos.first.id;

      await tester.send(ToggleTodoEvent(todoId));

      tester.expectState((state) => state.todos.first.isCompleted);
    });

    test('fetches todos from API', () async {
      final status = await tester.sendAndWaitForResult(FetchTodosEvent());

      expect(status, isA<UpdatingStatus>());
      tester.expectWasWaiting();
      tester.expectState((state) => state.todos.isNotEmpty);
    });

    test('handles fetch error', () async {
      final status = await tester.sendAndWaitForResult(
        FetchTodosEvent(shouldFail: true),
      );

      expect(status, isA<FailureStatus>());
      final failure = status as FailureStatus;
      expect(failure.error, isA<NetworkException>());
    });
  });
}
```

## API Reference

| Method | Description |
|--------|-------------|
| `send(event, {delay})` | Send event and wait for processing |
| `sendAndWaitForResult(event, {timeout})` | Send and wait for non-waiting status |
| `expectState(predicate)` | Assert state matches predicate |
| `expectStateEquals(state)` | Assert exact state equality |
| `expectLastStatusIs<T>()` | Assert last status type |
| `expectStatusSequence(types)` | Assert emission type sequence |
| `expectWasWaiting()` | Assert WaitingStatus was emitted |
| `expectWasFailure()` | Assert FailureStatus was emitted |
| `expectNoFailure()` | Assert no FailureStatus emitted |
| `expectEmissionCount(n)` | Assert number of emissions |
| `expectAnyEmission(predicate)` | Assert any emission matches |
| `expectAllEmissions(predicate)` | Assert all emissions match |
| `clearEmissions()` | Clear emission history |
| `waitForEmissions(n)` | Wait for n emissions |
| `dispose()` | Clean up tester and bloc |
