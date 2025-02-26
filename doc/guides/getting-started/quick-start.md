# Getting Started with Juice

This guide will walk you through creating your first Juice application. By the end, you'll understand the core concepts and be ready to build more complex applications.

## Installation

1. Add Juice to your `pubspec.yaml`:

```yaml
dependencies:
  juice: ^1.0.4
```

2. Or run:

```bash
flutter pub add juice
```

3. Import Juice in your code:

```dart
import 'package:juice/juice.dart';
```

## Creating Your First Juice App

Let's create a counter app that demonstrates Juice's key features. We'll build it step by step.

### 1. Define Your State

First, create a state class that holds your application's data:

```dart
class CounterState extends BlocState {
  final int count;
  
  CounterState({required this.count});
  
  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }
}
```

### 2. Create Events

Define events that represent user actions:

```dart
class IncrementEvent extends EventBase {}
class DecrementEvent extends EventBase {}
```

### 3. Write Use Cases

Create use cases that handle your business logic:

```dart
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    // Show loading state while we "process"
    emitWaiting(groupsToRebuild: {"counter"});
    
    // Simulate some work
    await Future.delayed(Duration(milliseconds: 2000));
    
    // Update the state
    final newState = bloc.state.copyWith(count: bloc.state.count + 1);
    emitUpdate(
      newState: newState,
      groupsToRebuild: {"counter"}
    );
  }
}

class DecrementUseCase extends BlocUseCase<CounterBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    emitWaiting(groupsToRebuild: {"counter"});
    await Future.delayed(Duration(milliseconds: 2000));
    
    final newState = bloc.state.copyWith(count: bloc.state.count - 1);
    emitUpdate(
      newState: newState,
      groupsToRebuild: {"counter"}
    );
  }
}
```

### 4. Create Your Bloc

Set up your bloc to coordinate state and use cases:

```dart
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          CounterState(count: 0),  // Initial state
          [
            // Register use cases
            () => UseCaseBuilder(
                typeOfEvent: IncrementEvent,
                useCaseGenerator: () => IncrementUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: DecrementEvent,
                useCaseGenerator: () => DecrementUseCase()),
          ],
          [], // No navigation for this simple example
        );
}
```

### 5. Create Your Widgets

Create widgets that display your UI and respond to state changes:

```dart
// Display widget that shows the counter
class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
  CounterDisplay({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return status.when(
      updating: (state, _, __) => Text(
        'Count: ${state.count}',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      waiting: (_, __, ___) => CircularProgressIndicator(),
      error: (_, __, ___) => Text('Error occurred'),
      canceling: (_, __, ___) => Text('Operation cancelled'),
    );
  }
}

// Button widget that triggers state changes
class CounterButtons extends StatelessJuiceWidget<CounterBloc> {
  CounterButtons({super.key, super.groups = const {}});  // Don't rebuild on state changes

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => bloc.send(IncrementEvent()),
          child: Icon(Icons.add),
        ),
        SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(DecrementEvent()),
          child: Icon(Icons.remove),
        ),
      ],
    );
  }
}
```

### 6. Put It All Together

Create your main app:

```dart
void main() {
  // Initialize Juice
  GlobalBlocResolver().resolver = BlocResolver();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Juice Counter')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CounterDisplay(),
              SizedBox(height: 16),
              CounterButtons(),
            ],
          ),
        ),
      ),
    );
  }
}
```

## Key Concepts Demonstrated

This simple example shows several key Juice features:

1. **State Management**
   - Clean state class with immutable updates
   - State changes through events and use cases
   - Reactive UI updates

2. **Use Cases**
   - Isolated business logic
   - Handling async operations
   - State update control

3. **Smart Rebuilds**
   - Group-based widget updates
   - Loading state handling
   - Error state management

4. **Clean Architecture**
   - Clear separation of concerns
   - Testable components
   - Maintainable structure

## Next Steps

Now that you've built your first Juice app, you can:

1. Learn about [Use Cases in Depth](../concepts/use-cases)
2. Explore [State Management](../concepts/state-management)
3. See more [Examples](../examples/overview)
4. Read about [Navigation](../concepts/navigation)

## Common Questions

### How do widgets access state in Juice?
Juice widgets have direct, type-safe access to their bloc's state through the bloc.state property (or bloc1.state, bloc2.state, etc. for multi-bloc widgets). see [Accessing State in Juice-aware Widgets](../../concepts/accessing-state-in-widgets.md)

### When should widgets rebuild?
Use the `groups` parameter to control which state changes trigger rebuilds. Use empty groups (`const {}`) for widgets that don't need to rebuild on state changes.

### Why use use cases?
Use cases isolate business logic, making your code easier to test, maintain, and modify. They also provide a clear place for handling loading states, errors, and cancellation.

### What's StreamStatus?
StreamStatus helps manage different UI states (updating, waiting, error, canceling) in a type-safe way. Use the `when` method to handle each state appropriately. see [StreamStatus Patterns](stream-status.md)

### How do I handle errors?
Use cases can emit failure states using `emitFailure()`. Handle these in your widgets using the `error` case in `status.when()`.