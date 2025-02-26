---
layout: default
title: Home
nav_order: 1
---

# Welcome to Juice

A Flutter framework that combines clean architecture with reactive state management to help you build maintainable, scalable applications.

[![pub package](https://img.shields.io/pub/v/juice.svg)](https://pub.dev/packages/juice)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

[Get Started](guides/getting-started/quick-start.md) | [View on GitHub](https://github.com/kehmka/juice)

---

## What is Juice?

Juice is a Flutter framework that helps you build applications using proven architectural patterns. It combines the best aspects of BLoC pattern and clean architecture while solving common challenges in state management, UI updates, and business logic organization.

### Clean Architecture That Makes Sense

**Use Cases as Core Building Blocks**
- Each piece of business logic gets its own dedicated use case
- Use cases are independent, testable, and reusable
- Clear separation between what your app does (use cases) and how it does it (implementation)
- No more massive bloc files with mixed concerns

```dart
// A clear, focused use case
class SendMessageUseCase extends BlocUseCase<ChatBloc, SendMessageEvent> {
  @override
  Future<void> execute(SendMessageEvent event) async {
    emitWaiting(groupsToRebuild: {"chat_status"});  // Update only status UI
    
    try {
      await chatService.send(event.message);
      emitUpdate(
        newState: ChatState.messageSent(),
        groupsToRebuild: {"chat_messages", "chat_status"}
      );
    } catch (e) {
      emitFailure(groupsToRebuild: {"chat_status"});
    }
  }
}
```

### Smart Rebuilds That Actually Work

**Fine-Grained UI Update Control**
- Specify exactly which widgets should rebuild on state changes
- Group related widgets for coordinated updates
- Prevent cascading rebuilds and performance issues
- Built-in loading, error, and cancellation states

```dart
// Only rebuild message list on new messages
class MessageList extends StatelessJuiceWidget<ChatBloc> {
  MessageList({super.key, super.groups = const {"chat_messages"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListView(children: bloc.state.messages.map(/*...*/));
  }
}

// Status bar updates independently
class ChatStatus extends StatelessJuiceWidget<ChatBloc> {
  ChatStatus({super.key, super.groups = const {"chat_status"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // status.when is fine for single-bloc widgets
    return status.when(
      updating: (_) => Text(bloc.state.isOnline ? "Online" : "Offline"),
      waiting: (_) => Text("Sending..."),
      failure: (_) => Text("Failed to send"),
      canceling: (_) => Text("Cancelled"),
    );
  }
}
```

### Type-Safe Navigation Built In

**Navigation That's Reliable**
- Route handling with compile-time safety
- Deep linking support out of the box
- Structured navigation patterns with Aviators
- Handle complex flows like authentication redirects

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
          // Type-safe navigation
          navigatorKey.currentState?.pushNamed('/profile/$userId');
        },
      ),
    ],
  );
}
```

### Operation Control Made Simple

**Handle Complex Operations Elegantly**
- Built-in support for cancellation
- Automatic timeout handling
- Progress tracking and status updates
- Clean resource management

```dart
class UploadUseCase extends BlocUseCase<UploadBloc, UploadEvent> {
  @override
  Future<void> execute(UploadEvent event) async {
    if (event is CancellableEvent && event.isCancelled) {
      emitCancel(groupsToRebuild: {"upload_status"});
      return;
    }
    
    try {
      await uploadFile(
        event.file,
        onProgress: (progress) {
          emitUpdate(
            newState: UploadState(progress: progress),
            groupsToRebuild: {"upload_progress"}
          );
        }
      );
    } catch (e) {
      emitFailure();
    }
  }
}
```

### Developer Experience First

**Built for Real-World Development**
- Rich IDE support with full type safety
- Comprehensive logging system for debugging
- Consistent patterns across your entire app
- Easy to test, mock, and maintain
- Clear error handling and recovery patterns

```dart
// Full type safety and IDE support
class ProfileUseCase extends BlocUseCase<ProfileBloc, LoadProfileEvent> {
  @override 
  Future<void> execute(LoadProfileEvent event) async {
    try {
      log('Loading profile', context: {'userId': event.userId});
      emitWaiting();
      
      final profile = await profileService.load(event.userId);
      emitUpdate(newState: ProfileState(profile: profile));
      
    } catch (e, stack) {
      logError(e, stack, context: {'userId': event.userId});
      emitFailure();
    }
  }
}
```

Juice brings together these features in a cohesive framework that helps you build better Flutter applications. Whether you're building a simple app or a complex enterprise system, Juice's architecture scales with your needs while keeping your code clean and maintainable.

## Quick Example

Here's a taste of what building with Juice looks like:

```dart
// Define a use case to handle business logic
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitWaiting();  // Show loading state
    await Future.delayed(Duration(milliseconds: 500)); // Simulate work
    emitUpdate(
      newState: CounterState(count: bloc.state.count + 1),
      groupsToRebuild: {"counter"}  // Only rebuild counter widgets
    );
  }
}

// Create a bloc to manage state
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc() : super(
    CounterState(count: 0),
    [
      () => UseCaseBuilder(
        typeOfEvent: IncrementEvent,
        useCaseGenerator: () => IncrementUseCase()
      ),
    ],
    [],
  );
}

// Build a reactive widget
class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // status.when is fine for single-bloc widgets
    return status.when(
      updating: (state, _, __) => Text('Count: ${state.count}'),
      waiting: (_, __, ___) => CircularProgressIndicator(),
      error: (_, __, ___) => Text('Error occurred'),
      canceling: (_, __, ___) => Text('Operation cancelled'),
    );
  }
}
```

## Why Juice?

Juice was created to solve common challenges in Flutter development:

### 🎯 Clear Organization
- Each piece of business logic gets its own use case
- Strong separation between UI, logic, and state
- Easy to understand where code should go

### 🔄 Smart Updates
- Control exactly which widgets rebuild
- Prevent unnecessary UI updates
- Built-in loading and error states

### 🧪 Testing Made Easy
- Use cases are independently testable
- Clear boundaries make mocking simple
- Built-in error handling support

### 🛠️ Developer Experience
- Great IDE support with type safety
- Consistent patterns across your app
- Built-in debugging and logging

## Getting Started

Ready to try Juice? Start with our [Quick Start Guide](guides/getting-started/quick-start.md) or dive into the [Core Concepts](concepts/bloc-basics.md).

### Installation

Add Juice to your pubspec.yaml:

```yaml
dependencies:
  juice: ^1.0.4
```

Or run:

```bash
flutter pub add juice
```

## Learning Path

New to Juice? Here's a suggested learning path:

1. Follow the [Counter Tutorial](examples/counter-tutorial.md) to build your first Juice app
2. Learn about [Use Cases](concepts/use-cases.md) and how they organize business logic
3. Master [State Management](concepts/state-management.md) with StreamStatus
4. Explore [Smart Rebuilds](concepts/group-rebuilds.md) to optimize performance

## Community and Support

- [GitHub Discussions](https://github.com/kehmka/juice/discussions) - Ask questions and share ideas
- [Issue Tracker](https://github.com/kehmka/juice/issues) - Report bugs or request features

## Next Steps

Ready to dive in? Choose your path:

- [Quick Start Guide](guides/getting-started/quick-start) - Get up and running quickly
- [Core Concepts](overview/introduction.md) - Learn the fundamentals