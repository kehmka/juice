# Async Operations Guide

This guide covers advanced patterns for handling asynchronous operations in Juice, including `sendAndWait`, state deduplication with `skipIfSame`, and best practices for async use cases.

## sendAndWait - Awaiting Event Completion

The `sendAndWait` method allows you to await the completion of an event, returning the final status when the operation finishes.

### Basic Usage

```dart
// In a widget or use case
final status = await bloc.sendAndWait(FetchDataEvent());

if (status is UpdatingStatus) {
  print('Data fetched successfully');
} else if (status is FailureStatus) {
  print('Fetch failed: ${status.error}');
}
```

### How It Works

1. Sends the event to the bloc
2. Waits for the stream to emit a non-`WaitingStatus` (i.e., `UpdatingStatus`, `FailureStatus`, or `CancelingStatus`)
3. Returns the final status

### With Timeout

```dart
try {
  final status = await bloc.sendAndWait(
    SlowOperationEvent(),
    timeout: Duration(seconds: 30),
  );
  // Handle result
} on TimeoutException {
  // Handle timeout
}
```

### Practical Examples

#### Sequential Operations

```dart
Future<void> processOrder() async {
  // Step 1: Validate
  var status = await orderBloc.sendAndWait(ValidateOrderEvent());
  if (status is FailureStatus) {
    showError('Validation failed');
    return;
  }

  // Step 2: Process payment
  status = await paymentBloc.sendAndWait(ProcessPaymentEvent());
  if (status is FailureStatus) {
    showError('Payment failed');
    return;
  }

  // Step 3: Submit order
  status = await orderBloc.sendAndWait(SubmitOrderEvent());
  if (status is UpdatingStatus) {
    showSuccess('Order completed!');
  }
}
```

#### Form Submission with Feedback

```dart
class _SubmitButtonState extends State<SubmitButton> {
  bool _isSubmitting = false;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    final status = await bloc.sendAndWait(SubmitFormEvent(data: formData));

    setState(() => _isSubmitting = false);

    if (status is UpdatingStatus) {
      Navigator.of(context).pop(true);
    } else if (status is FailureStatus) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: ${status.error}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isSubmitting ? null : _submit,
      child: _isSubmitting
          ? CircularProgressIndicator()
          : Text('Submit'),
    );
  }
}
```

## skipIfSame - State Deduplication

The `skipIfSame` parameter prevents emitting duplicate states, reducing unnecessary widget rebuilds.

### Basic Usage

```dart
class UpdateCounterUseCase extends BlocUseCase<CounterBloc, UpdateEvent> {
  @override
  Future<void> execute(UpdateEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: event.count),
      groupsToRebuild: {'counter'},
      skipIfSame: true,  // Skip if state equals current state
    );
  }
}
```

### How It Works

When `skipIfSame: true`:
1. The new state is compared to the current state using `==`
2. If equal, no emission occurs
3. If different, the state is emitted normally

### Use Cases

#### Preventing Duplicate API Results

```dart
class RefreshDataUseCase extends BlocUseCase<DataBloc, RefreshEvent> {
  @override
  Future<void> execute(RefreshEvent event) async {
    emitWaiting();

    final data = await api.fetchData();

    emitUpdate(
      newState: DataState(data: data),
      skipIfSame: true,  // Don't rebuild if data hasn't changed
    );
  }
}
```

#### Form Field Updates

```dart
class UpdateFieldUseCase extends BlocUseCase<FormBloc, FieldUpdateEvent> {
  @override
  Future<void> execute(FieldUpdateEvent event) async {
    // Only emit if the value actually changed
    emitUpdate(
      newState: bloc.state.copyWith(
        fields: {
          ...bloc.state.fields,
          event.fieldName: event.value,
        },
      ),
      groupsToRebuild: {event.fieldName},
      skipIfSame: true,
    );
  }
}
```

#### Polling Without Unnecessary Updates

```dart
class PollStatusUseCase extends BlocUseCase<StatusBloc, PollEvent> {
  @override
  Future<void> execute(PollEvent event) async {
    while (!event.isCancelled) {
      final status = await api.getStatus();

      // Only update UI when status actually changes
      emitUpdate(
        newState: StatusState(status: status),
        skipIfSame: true,
      );

      await Future.delayed(Duration(seconds: 5));
    }
  }
}
```

### State Equality

For `skipIfSame` to work correctly, your state must implement proper equality:

```dart
class CounterState extends BlocState {
  final int count;

  const CounterState({required this.count});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CounterState &&
          runtimeType == other.runtimeType &&
          count == other.count;

  @override
  int get hashCode => count.hashCode;
}
```

Or use packages like `equatable`:

```dart
class CounterState extends BlocState with EquatableMixin {
  final int count;

  const CounterState({required this.count});

  @override
  List<Object?> get props => [count];
}
```

## Async Use Case Patterns

### Pattern 1: Loading -> Result

The most common pattern for async operations:

```dart
class FetchDataUseCase extends BlocUseCase<DataBloc, FetchEvent> {
  @override
  Future<void> execute(FetchEvent event) async {
    // 1. Show loading state
    emitWaiting(groupsToRebuild: {'status'});

    try {
      // 2. Perform async operation
      final data = await repository.fetch(event.id);

      // 3. Emit success
      emitUpdate(
        newState: DataState.loaded(data),
        groupsToRebuild: {'content', 'status'},
      );
    } catch (e, stack) {
      // 4. Emit failure
      emitFailure(
        error: e,
        errorStackTrace: stack,
        groupsToRebuild: {'status'},
      );
    }
  }
}
```

### Pattern 2: Progress Updates

For operations with progress feedback:

```dart
class UploadUseCase extends BlocUseCase<UploadBloc, UploadEvent> {
  @override
  Future<void> execute(UploadEvent event) async {
    emitWaiting();

    try {
      await uploader.upload(
        event.file,
        onProgress: (progress) {
          emitUpdate(
            newState: bloc.state.copyWith(progress: progress),
            groupsToRebuild: {'progress'},
          );
        },
      );

      emitUpdate(
        newState: bloc.state.copyWith(isComplete: true),
        groupsToRebuild: {'status'},
      );
    } catch (e, stack) {
      emitFailure(error: e, errorStackTrace: stack);
    }
  }
}
```

### Pattern 3: Cancellable Operations

For long-running operations that can be cancelled:

```dart
class DownloadUseCase extends BlocUseCase<DownloadBloc, DownloadEvent> {
  @override
  Future<void> execute(DownloadEvent event) async {
    emitWaiting();

    try {
      final stream = downloader.download(event.url);

      await for (final chunk in stream) {
        // Check for cancellation
        if (event is CancellableEvent && event.isCancelled) {
          emitCancel();
          return;
        }

        emitUpdate(
          newState: bloc.state.copyWith(
            bytesDownloaded: bloc.state.bytesDownloaded + chunk.length,
          ),
          groupsToRebuild: {'progress'},
        );
      }

      emitUpdate(
        newState: bloc.state.copyWith(isComplete: true),
      );
    } catch (e, stack) {
      emitFailure(error: e, errorStackTrace: stack);
    }
  }
}
```

### Pattern 4: Retry with Backoff

For operations that should retry on failure:

```dart
class ResilientFetchUseCase extends BlocUseCase<DataBloc, FetchEvent> {
  static const maxRetries = 3;
  static const baseDelay = Duration(seconds: 1);

  @override
  Future<void> execute(FetchEvent event) async {
    emitWaiting();

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final data = await repository.fetch(event.id);
        emitUpdate(newState: DataState.loaded(data));
        return;
      } catch (e) {
        if (attempt == maxRetries - 1) {
          emitFailure(error: e);
          return;
        }

        // Exponential backoff
        final delay = baseDelay * (1 << attempt);
        await Future.delayed(delay);
      }
    }
  }
}
```

## Best Practices

### 1. Always Handle Errors

```dart
try {
  final result = await asyncOperation();
  emitUpdate(newState: SuccessState(result));
} catch (e, stack) {
  logError(e, stack);
  emitFailure(error: e, errorStackTrace: stack);
}
```

### 2. Use Appropriate Timeouts

```dart
final status = await bloc.sendAndWait(
  event,
  timeout: Duration(seconds: 30),  // Reasonable timeout
);
```

### 3. Show Loading States

```dart
emitWaiting(groupsToRebuild: {'status'});
// Do async work...
```

### 4. Use skipIfSame for Polling/Refresh

```dart
emitUpdate(
  newState: newState,
  skipIfSame: true,  // Prevent unnecessary rebuilds
);
```

### 5. Implement Proper State Equality

```dart
class MyState extends BlocState {
  // Implement == and hashCode
  @override
  bool operator ==(Object other) => ...;

  @override
  int get hashCode => ...;
}
```

### 6. Use Typed Exceptions

```dart
} on NetworkException catch (e, stack) {
  emitFailure(error: e, errorStackTrace: stack);
} on ValidationException catch (e) {
  emitFailure(error: e);
}
```

## API Reference

### JuiceBloc.sendAndWait

```dart
Future<StreamStatus<TState>> sendAndWait(
  EventBase event, {
  Duration timeout = const Duration(seconds: 30),
})
```

Sends an event and waits for a non-waiting status to be emitted.

### emitUpdate with skipIfSame

```dart
void emitUpdate({
  BlocState? newState,
  Set<String>? groupsToRebuild,
  bool skipIfSame = false,  // Skip emission if state equals current
})
```

### BlocTester.sendAndWaitForResult

```dart
Future<StreamStatus<TState>> sendAndWaitForResult(
  EventBase event, {
  Duration timeout = const Duration(seconds: 5),
})
```

Testing utility that mirrors `sendAndWait` behavior.
