# Error Handling in Juice

Juice provides a comprehensive error handling system that integrates with its use case pattern and StreamStatus system. This guide covers error handling best practices and patterns.

## Core Concepts

### 1. Error Flow

In Juice, errors flow through three main layers:
- Use Cases: Where errors are first caught and handled
- StreamStatus: Carries error states to the UI
- Widgets: Display errors and handle recovery

### 2. Key Components

```dart
// Stream status for error state
StreamStatus.failure(state, oldState, event)

// Error emission in use cases
emitFailure(
  newState: ErrorState(message: "Failed to load"),
  groupsToRebuild: {"error_view"}
);

// Error handling in widgets
Widget onBuild(BuildContext context, StreamStatus status) {
  return status.when(
    updating: (state, _, __) => ContentView(state),
    waiting: (_, __, ___) => LoadingSpinner(),
    failure: (state, _, __) => ErrorView(state.error),
    canceling: (_, __, ___) => Text('Cancelled')
  );
}
```

## Best Practices

### 1. Use Case Error Handling

Always handle errors at the use case level:

```dart
class FetchDataUseCase extends BlocUseCase<DataBloc, FetchEvent> {
  @override
  Future<void> execute(FetchEvent event) async {
    try {
      emitWaiting(groupsToRebuild: {"status"});
      
      final data = await repository.fetch();
      
      emitUpdate(
        newState: DataState.loaded(data),
        groupsToRebuild: {"content"}
      );
      
    } catch (e, stack) {
      // Log error with context
      logError(e, stack, context: {
        'event': event.runtimeType,
        'currentState': bloc.state
      });
      
      // Determine error type and emit appropriate state
      if (e is NetworkException) {
        emitFailure(
          newState: DataState.networkError(e.message),
          groupsToRebuild: {"error_view"}
        );
      } else if (e is ValidationException) {
        emitFailure(
          newState: DataState.validationError(e.errors),
          groupsToRebuild: {"form_errors"}
        );
      } else {
        emitFailure(
          newState: DataState.unknownError(),
          groupsToRebuild: {"error_view"}
        );
      }
    }
  }
}
```

### 2. Error State Design

Design error states that carry useful information:

```dart
class DataState extends BlocState {
  final Data? data;
  final ErrorType? errorType;
  final String? errorMessage;
  final Map<String, String>? validationErrors;

  const DataState._({
    this.data,
    this.errorType,
    this.errorMessage,
    this.validationErrors
  });

  factory DataState.initial() => const DataState._();
  
  factory DataState.loaded(Data data) => 
    DataState._(data: data);
    
  factory DataState.networkError(String message) =>
    DataState._(
      errorType: ErrorType.network,
      errorMessage: message
    );
    
  factory DataState.validationError(Map<String, String> errors) =>
    DataState._(
      errorType: ErrorType.validation,
      validationErrors: errors
    );
}
```

### 3. Granular Error Rebuilds

Use targeted rebuilds for errors:

```dart
class ComplexFormUseCase extends BlocUseCase<FormBloc, SubmitEvent> {
  @override
  Future<void> execute(SubmitEvent event) async {
    try {
      // Process form
      await processForm(event.data);
      
    } catch (e, stack) {
      if (e is ValidationError) {
        // Only rebuild affected field error states
        emitFailure(
          newState: FormState.fieldErrors(e.errors),
          groupsToRebuild: e.errors.keys
              .map((field) => "field_$field")
              .toSet()
        );
      } else if (e is NetworkError) {
        // Show error in status area only
        emitFailure(
          newState: FormState.submitError(e.message),
          groupsToRebuild: {"submit_status"}
        );
      }
    }
  }
}
```

### 4. Error Recovery

Implement clear recovery paths:

```dart
class DataWidget extends StatelessJuiceWidget<DataBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return status.when(
      updating: (state, _, __) => DataView(state.data!),
      waiting: (_, __, ___) => LoadingSpinner(),
      failure: (state, _, __) => ErrorView(
        error: state.errorMessage!,
        // Provide retry mechanism
        onRetry: () => bloc.send(RetryEvent()),
        // Allow skip/continue if appropriate
        onSkip: state.canSkip 
            ? () => bloc.send(SkipEvent())
            : null,
      ),
      canceling: (_, __, ___) => Text('Operation cancelled')
    );
  }
}
```

### 5. Error Logging

Implement comprehensive error logging:

```dart
class NetworkUseCase extends BlocUseCase<NetworkBloc, FetchEvent> {
  @override
  Future<void> execute(FetchEvent event) async {
    try {
      // Operation code
    } catch (e, stack) {
      logError(
        e, 
        stack,
        context: {
          'url': event.url,
          'method': event.method,
          'statusCode': e is HttpException ? e.statusCode : null,
          'responseBody': e is HttpException ? e.body : null,
          'headers': event.headers,
          'currentState': bloc.state,
          'timestamp': DateTime.now().toIso8601String(),
        }
      );
      
      emitFailure(
        newState: NetworkState.error(e),
        groupsToRebuild: {"network_status"}
      );
    }
  }
}
```

### 6. Error Prevention

Use patterns that prevent errors:

```dart
class SafeUseCase extends BlocUseCase<SafeBloc, ProcessEvent> {
  @override
  Future<void> execute(ProcessEvent event) async {
    // Validate inputs early
    if (!isValidInput(event.data)) {
      emitFailure(
        newState: SafeState.invalidInput(),
        groupsToRebuild: {"validation"}
      );
      return;
    }
    
    // Use null safety
    final config = event.config ?? DefaultConfig();
    
    // Check preconditions
    if (!await canProcess()) {
      emitFailure(
        newState: SafeState.unavailable(),
        groupsToRebuild: {"status"}
      );
      return;
    }
    
    try {
      // Protected operation
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(
        newState: SafeState.error(e),
        groupsToRebuild: {"error"}
      );
    }
  }
}
```

## Error Handling Patterns

### 1. Progressive Error Recovery

Handle errors with increasing severity:

```dart
class RobustUseCase extends BlocUseCase<RobustBloc, FetchEvent> {
  @override
  Future<void> execute(FetchEvent event) async {
    try {
      // Try primary data source
      final data = await fetchPrimary();
      emitUpdate(newState: RobustState.success(data));
      
    } catch (e) {
      try {
        // Try backup data source
        final backup = await fetchBackup();
        emitUpdate(
          newState: RobustState.backupData(backup),
          groupsToRebuild: {"content", "status"}
        );
        
      } catch (e2) {
        try {
          // Try cached data
          final cached = await loadCache();
          emitUpdate(
            newState: RobustState.cachedData(cached),
            groupsToRebuild: {"content", "status"}
          );
          
        } catch (e3) {
          // All recovery attempts failed
          emitFailure(
            newState: RobustState.completeFailure(),
            groupsToRebuild: {"error"}
          );
        }
      }
    }
  }
}
```

### 2. Contextual Error Handling

Adjust error handling based on context:

```dart
class ContextualUseCase extends BlocUseCase<ContextBloc, ProcessEvent> {
  @override
  Future<void> execute(ProcessEvent event) async {
    try {
      // Operation code
    } catch (e, stack) {
      // Handle based on user context
      if (bloc.state.isGuestUser) {
        emitFailure(
          newState: ContextState.authRequired(),
          groupsToRebuild: {"auth_prompt"}
        );
      } 
      // Handle based on network context
      else if (bloc.state.isOffline) {
        emitFailure(
          newState: ContextState.offlineError(),
          groupsToRebuild: {"offline_notice"}
        );
      }
      // Handle based on feature state
      else if (!bloc.state.isFeatureEnabled) {
        emitFailure(
          newState: ContextState.featureDisabled(),
          groupsToRebuild: {"feature_notice"}
        );
      }
      // Default error handling
      else {
        emitFailure(
          newState: ContextState.error(e),
          groupsToRebuild: {"error"}
        );
      }
    }
  }
}
```

## Key Differences from Other Frameworks

1. **Use Case Isolation**
   - Errors are handled within isolated use cases
   - Clear error boundaries
   - Focused error handling logic

2. **StreamStatus Integration**
   - Error states are part of the StreamStatus system
   - Consistent error handling across the app
   - Type-safe error propagation

3. **Granular Rebuilds**
   - Error states can trigger specific UI updates
   - Efficient error UI updates
   - Better error UX

4. **Built-in Logging**
   - Error logging integrated into use cases
   - Rich error context capture
   - Structured error reporting

## Summary

Effective error handling in Juice involves:

1. Catching and handling errors in use cases
2. Using proper error states
3. Implementing recovery mechanisms
4. Logging with context
5. Using granular rebuilds
6. Following prevention patterns

Remember:
- Always handle errors at the use case level
- Design clear error states
- Implement recovery paths
- Log errors with context
- Use targeted rebuilds
- Prevent errors where possible