# Introduction to Juice

Juice is a reactive architecture framework for Flutter that helps you build maintainable, scalable applications. It combines clean architecture principles with stream-based state management to provide a structured yet flexible approach to app development.

## Core Concepts

### 1. Organized Blocs

Blocs in Juice are the cornerstone of state management and business logic coordination. Each bloc:

- Manages a specific feature's state
- Coordinates related use cases
- Controls navigation through aviators
- Provides type-safe state access to widgets

```dart
// Bloc with clear responsibilities
class ChatBloc extends JuiceBloc<ChatState> {
  ChatBloc(this._chatService) : super(
    ChatState.initial(),
    [
      // Register use cases for specific events
      () => UseCaseBuilder(
        typeOfEvent: SendMessageEvent,
        useCaseGenerator: () => SendMessageUseCase(),
      ),
      () => UseCaseBuilder(
        typeOfEvent: LoadMessagesEvent,
        useCaseGenerator: () => LoadMessagesUseCase(),
      ),
    ],
    [
      // Register aviators for navigation
      () => Aviator(
        name: 'conversation',
        navigate: (args) {
          final conversationId = args['id'] as String;
          navigatorKey.currentState?.pushNamed('/chat/$conversationId');
        },
      ),
    ],
  );

  final ChatService _chatService;

  // Current state is always available
  List<Message> get messages => state.messages;
  bool get isOnline => state.isOnline;
}
```

The key differences in Juice's bloc implementation:

1. **Use Case Organization**: Instead of handling events directly, blocs delegate to dedicated use cases
2. **Clean Dependencies**: Services and dependencies are injected and managed cleanly
3. **Integrated Navigation**: Navigation is handled through typed aviator objects
4. **State Access**: Provides clear state access patterns for widgets

### 2. Clean Architecture with Use Cases

At the heart of Juice is the concept of Use Cases - isolated pieces of business logic that represent single operations in your application. Each use case:

- Has a single responsibility
- Handles one type of event
- Emits state changes through a structured status system
- Can be tested independently

```dart
class SendMessageUseCase extends BlocUseCase<ChatBloc, SendMessageEvent> {
  @override
  Future<void> execute(SendMessageEvent event) async {
    // Show loading state for just the chat status
    emitWaiting(groupsToRebuild: {"chat_status"});
    
    try {
      await chatService.send(event.message);
      
      // Update both messages and status
      emitUpdate(
        newState: ChatState.messageSent(),
        groupsToRebuild: {"chat_messages", "chat_status"}
      );
    } catch (e) {
      // Show error only in status area
      emitFailure(groupsToRebuild: {"chat_status"});
    }
  }
}
```

### 2. Stream-Based State Management

Juice uses a structured streaming system called StreamStatus to manage application state. StreamStatus provides:

- Clear distinction between data state and UI state
- Built-in handling of loading, error, and cancellation states
- Type-safe state transitions
- Granular control over widget rebuilds

```dart
class ChatWidget extends StatelessJuiceWidget<ChatBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Access data state through bloc.state
    final messages = bloc.state.messages;
    
    // Use status for UI state decisions
    return status.when(
      updating: (_) => MessageList(messages: messages),
      waiting: (_) => LoadingSpinner(),
      error: (_) => ErrorDisplay(),
      canceling: (_) => Text("Operation cancelled"),
    );
  }
}
```

### 3. Smart Widget Rebuilding

Juice provides a powerful group-based system for controlling exactly which parts of your UI update in response to state changes:

```dart
// Chat messages update independently of status
class MessageList extends StatelessJuiceWidget<ChatBloc> {
  MessageList({super.key, super.groups = const {"chat_messages"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListView(
      children: bloc.state.messages.map(buildMessage).toList(),
    );
  }
}

// Status updates independently of messages
class ChatStatus extends StatelessJuiceWidget<ChatBloc> {
  ChatStatus({super.key, super.groups = const {"chat_status"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (status is WaitingStatus) {
      return Text("Sending...");
    }
    return Text("Online");
  }
}
```

### 4. Type-Safe Navigation

Navigation in Juice is handled through Aviators - type-safe router objects that encapsulate navigation logic:

```dart
class AppBloc extends JuiceBloc<AppState> {
  AppBloc() : super(
    AppState.initial(),
    [...],
    [
      () => Aviator(
        name: 'profile',
        navigate: (args) {
          final userId = args['userId'] as String;
          navigatorKey.currentState?.pushNamed('/profile/$userId');
        },
      ),
    ],
  );
}
```

### 5. Operation Control

Juice provides first-class support for handling long-running operations:

```dart
class UploadUseCase extends BlocUseCase<UploadBloc, UploadFileEvent> {
  @override
  Future<void> execute(UploadFileEvent event) async {
    // Handle cancellation
    if (event is CancellableEvent && event.isCancelled) {
      emitCancel();
      return;
    }

    try {
      await uploadService.upload(
        event.file,
        onProgress: (progress) {
          emitUpdate(
            newState: UploadState(progress: progress),
            groupsToRebuild: {"upload_progress"}
          );
        }
      );
      
      emitUpdate(newState: UploadState.complete());
      
    } catch (e) {
      emitFailure();
    }
  }
}
```

## Putting It All Together

These concepts work together to create a cohesive system:

1. Events trigger Use Cases in Blocs
2. Use Cases emit state changes through StreamStatus
3. Widgets rebuild based on their specified groups
4. Navigation is handled through type-safe Aviators
5. Operations can be monitored and controlled

This architecture helps maintain clean code organization as your app grows while providing powerful tools for handling real-world challenges.

## Next Steps

- Follow the [Quick Start Guide](../guides/getting-started/quick-start) to build your first Juice app
- Learn more about [Use Cases](concepts/use-cases) and how they organize business logic
- Master [State Management](concepts/state-management) with StreamStatus
- Explore [Smart Rebuilds](concepts/group-rebuilds) to optimize performance

Remember: Juice is designed to be progressive - start with basic concepts and add more advanced features as needed.