# Basic Use Cases

Use cases are the heart of business logic in Juice. Each use case represents a single operation and controls state transitions through four key emit methods: `emitUpdate`, `emitWaiting`, `emitFailure`, and `emitCancel`.

## Anatomy of a Use Case

Let's break down a basic use case:

```dart
class SendMessageUseCase extends BlocUseCase<ChatBloc, SendMessageEvent> {
  @override
  Future<void> execute(SendMessageEvent event) async {
    try {
      // Show loading state while sending
      emitWaiting(groupsToRebuild: {"chat_status"});

      // Send the message
      await chatService.send(event.message);

      // Update state with new message
      emitUpdate(
        newState: ChatState.messageSent(event.message),
        groupsToRebuild: {"chat_messages", "chat_status"}
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"chat_status"});
    }
  }
}
```

Key components:
1. Type parameters specify which bloc and event this use case handles
2. The `execute` method contains the business logic
3. Emit methods control state transitions and UI updates

## Emit Methods in Detail

### emitUpdate

Used to signal successful state changes. This is the most common emit method.

```dart
void emitUpdate({
  BlocState? newState,           // New state to set
  String? aviatorName,           // Navigation target
  Map<String, dynamic>? args,    // Navigation arguments
  Set<String>? groupsToRebuild,  // Widgets to update
})
```

Example usage:
```dart
emitUpdate(
  newState: UserState(name: "Alice"),
  groupsToRebuild: {"profile"},      // Only rebuild profile widgets
  aviatorName: "profile_complete",    // Navigate after update
  aviatorArgs: {"userId": "123"}     // Pass navigation data
);
```

### emitWaiting

Indicates an operation is in progress. Use this for loading states.

```dart
void emitWaiting({
  BlocState? newState,           // Optional state update
  String? aviatorName,           // Optional navigation
  Map<String, dynamic>? args,    // Navigation arguments
  Set<String>? groupsToRebuild,  // Widgets to update
})
```

Example usage:
```dart
// Show loading spinner during file upload
emitWaiting(
  groupsToRebuild: {"upload_status"},
  newState: UploadState(progress: 0)  // Optional state update
);
```

### emitFailure

Signals that an operation failed. Use this for error states.

```dart
void emitFailure({
  BlocState? newState,           // Optional error state
  String? aviatorName,           // Optional error navigation
  Map<String, dynamic>? args,    // Navigation arguments
  Set<String>? groupsToRebuild,  // Widgets to update
})
```

Example usage:
```dart
catch (e, stack) {
  logError(e, stack);
  emitFailure(
    newState: LoginState.error("Invalid credentials"),
    groupsToRebuild: {"login_form"},
    aviatorName: "error_page"
  );
}
```

### emitCancel

Used when a cancellable operation is cancelled.

```dart
void emitCancel({
  BlocState? newState,           // Optional final state
  String? aviatorName,           // Optional navigation
  Map<String, dynamic>? args,    // Navigation arguments
  Set<String>? groupsToRebuild,  // Widgets to update
})
```

Example usage:
```dart
if (event is CancellableEvent && event.isCancelled) {
  emitCancel(
    newState: UploadState.cancelled(),
    groupsToRebuild: {"upload_status"},
    aviatorName: "upload_cancelled"
  );
  return;
}
```

## Use Case Patterns

### Operation Progress

Track progress of long-running operations:

```dart
class UploadFileUseCase extends BlocUseCase<UploadBloc, UploadFileEvent> {
  @override
  Future<void> execute(UploadFileEvent event) async {
    try {
      emitWaiting(groupsToRebuild: {"upload"});
      
      await uploadService.upload(
        event.file,
        onProgress: (progress) {
          emitUpdate(
            newState: UploadState(progress: progress),
            groupsToRebuild: {"upload_progress"}
          );
        }
      );

      emitUpdate(
        newState: UploadState.complete(),
        groupsToRebuild: {"upload"},
        aviatorName: "upload_complete"
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"upload"});
    }
  }
}
```

### Validation

Handle input validation:

```dart
class ValidateEmailUseCase extends BlocUseCase<FormBloc, ValidateEmailEvent> {
  @override
  Future<void> execute(ValidateEmailEvent event) async {
    emitWaiting(groupsToRebuild: {"email_field"});
    
    try {
      final isValid = await validateEmail(event.email);
      
      if (isValid) {
        emitUpdate(
          newState: FormState.emailValid(event.email),
          groupsToRebuild: {"email_field", "submit_button"}
        );
      } else {
        emitFailure(
          newState: FormState.emailInvalid("Invalid email format"),
          groupsToRebuild: {"email_field", "submit_button"}
        );
      }
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"email_field"});
    }
  }
}
```

## Best Practices

1. **Single Responsibility**
   - Each use case should do one thing
   - Keep business logic focused and clear
   - Split complex operations into multiple use cases

2. **Error Handling**
   - Always use try-catch blocks
   - Log errors with context
   - Emit appropriate failure states
   - Consider error recovery paths

3. **State Updates**
   - Only update necessary state
   - Use targeted rebuilds through groups
   - Consider side effects (navigation, etc.)

4. **Resource Cleanup**
   - Override close() if needed
   - Cancel subscriptions
   - Clean up resources
   - Handle incomplete operations

## Common Pitfalls

1. **Not Handling Edge Cases**
```dart
// ❌ Bad: Missing error handling
class BadUseCase extends BlocUseCase<Bloc, Event> {
  @override
  Future<void> execute(Event event) async {
    final result = await service.fetch();  // May throw!
    emitUpdate(newState: State(result));
  }
}

// ✅ Good: Complete error handling
class GoodUseCase extends BlocUseCase<Bloc, Event> {
  @override
  Future<void> execute(Event event) async {
    try {
      emitWaiting();
      final result = await service.fetch();
      emitUpdate(newState: State(result));
    } catch (e, stack) {
      logError(e, stack);
      emitFailure();
    }
  }
}
```

2. **Mixing Concerns**
```dart
// ❌ Bad: Multiple responsibilities
class BadUseCase extends BlocUseCase<Bloc, Event> {
  @override
  Future<void> execute(Event event) async {
    final data = await fetchData();    // Data fetching
    validateData(data);                // Validation
    processData(data);                 // Processing
    saveToDatabase(data);              // Persistence
    emitUpdate(newState: State(data));
  }
}

// ✅ Good: Single responsibility
class GoodUseCase extends BlocUseCase<Bloc, Event> {
  @override
  Future<void> execute(Event event) async {
    try {
      emitWaiting();
      final data = await dataService.fetch();  // Delegate to service
      emitUpdate(newState: State(data));
    } catch (e, stack) {
      logError(e, stack);
      emitFailure();
    }
  }
}
```

3. **Forgetting Progress Updates**
```dart
// ❌ Bad: No progress updates
class BadUploadUseCase extends BlocUseCase<Bloc, Event> {
  @override
  Future<void> execute(Event event) async {
    emitWaiting();
    await uploadService.upload(event.file);  // Long operation!
    emitUpdate(newState: State.complete());
  }
}

// ✅ Good: Progress updates
class GoodUploadUseCase extends BlocUseCase<Bloc, Event> {
  @override
  Future<void> execute(Event event) async {
    emitWaiting();
    await uploadService.upload(
      event.file,
      onProgress: (progress) {
        emitUpdate(
          newState: State(progress: progress),
          groupsToRebuild: {"progress"}
        );
      }
    );
    emitUpdate(newState: State.complete());
  }
}
```

## Next Steps

- Learn about [Stateful Use Cases](stateful-use-cases.md)
- Explore [Relay Use Cases](relay-use-cases.md) for bloc communication
- See how to [Test Use Cases](../testing/use-cases)