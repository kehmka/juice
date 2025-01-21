# Bloc Basics in Juice

Blocs are the foundation of state management in Juice. They manage your application's state and coordinate business logic through use cases.

## Creating a Basic Bloc

A Juice bloc consists of three main components:

1. The bloc class itself that extends `JuiceBloc`
2. A state class that extends `BlocState`
3. Events that extend `EventBase`

Here's a simple example:

```dart
// State class
class CounterState extends BlocState {
  final int count;

  CounterState({required this.count});

  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }
}

// Event
class IncrementEvent extends EventBase {}

// Bloc
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc() : super(
    CounterState(count: 0),  // Initial state
    [
      () => UseCaseBuilder(
        typeOfEvent: IncrementEvent,
        useCaseGenerator: () => IncrementUseCase(),
      ),
    ],
    [], // Aviators (navigation handlers)
  );
}
```

## State Design

States in Juice should be:

1. **Immutable**: Once created, state objects should not change
2. **Simple**: Only contain data needed by the feature the bloc is representing
3. **Copyable**: Implement `copyWith` for easy state updates

```dart
class UserState extends BlocState {
  final String name;
  final int age;
  final List<String> permissions;

  // Immutable constructor
  const UserState({
    required this.name,
    required this.age,
    required this.permissions,
  });

  // Copyable
  UserState copyWith({
    String? name,
    int? age,
    List<String>? permissions,
  }) {
    return UserState(
      name: name ?? this.name,
      age: age ?? this.age,
      permissions: permissions ?? this.permissions,
    );
  }
}
```

## Events

Events trigger state changes and use case execution. They should:

1. **Be Clear**: Name events based on intent (e.g., `UpdateProfileEvent`)
2. **Contain Data**: Include any data needed by use cases
3. **Be Immutable**: Once created, event data should not change

```dart
class UpdateProfileEvent extends EventBase {
  final String name;
  final int age;

  const UpdateProfileEvent({
    required this.name,
    required this.age,
  });
}

// For operations that can be cancelled
class UploadFileEvent extends CancellableEvent {
  final File file;
  final String destination;

  const UploadFileEvent({
    required this.file,
    required this.destination,
  });
}
```

## Advanced Bloc Features

### Group-Based Updates

Control which widgets rebuild when state changes:

```dart
class ProfileBloc extends JuiceBloc<ProfileState> {
  void updateProfile() {
    emitUpdate(
      newState: newState,
      groupsToRebuild: {'profile_details'},  // Only rebuild profile widgets
    );
  }
}
```

### Cancellable Operations

Handle long-running operations with cancellation support:

```dart
class DownloadBloc extends JuiceBloc<DownloadState> {
  Future<void> startDownload() async {
    final operation = sendCancellable(DownloadEvent(...));
    
    // Later...
    operation.cancel();  // Cancel the operation
  }
}
```

### StreamStatus States

Juice blocs emit `StreamStatus` objects that include state and status information:

```dart
class ProfileWidget extends StatelessJuiceWidget<ProfileBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return status.when(
      updating: (state, _, __) => ProfileView(data: bloc.state.profile),
      waiting: (_, __, ___) => LoadingSpinner(),
      error: (_, __, ___) => ErrorMessage(),
      canceling: (_, __, ___) => CancellingMessage(),
    );
  }
}
```

## Best Practices

1. **State Design**
   - Keep states focused on single features
   - Use immutable objects (`final` fields)
   - Implement meaningful equality and toString

2. **Event Design**
   - One event per user action or system event
   - Include all needed data in the event
   - Use `CancellableEvent` for long operations

3. **Bloc Organization**
   - One bloc per feature or screen
   - Keep blocs focused and single-purpose
   - Use use cases for business logic

4. **Performance**
   - Use targeted group rebuilds
   - Avoid large state objects
   - Clean up resources in dispose

## Common Pitfalls

1. **Mutable State**
```dart
// ❌ Bad: Mutable state
class BadState extends BlocState {
  List<String> items = [];  // Mutable list
}

// ✅ Good: Immutable state
class GoodState extends BlocState {
  final List<String> items;
  const GoodState({required this.items});
}
```

2. **Direct State Modification**
```dart
// ❌ Bad: Modifying state directly
bloc.state.items.add('new item');

// ✅ Good: Creating new state
emitUpdate(
  newState: bloc.state.copyWith(
    items: [...bloc.state.items, 'new item'],
  ),
);
```

3. **Mixing Business Logic**
```dart
// ❌ Bad: Logic in bloc
class BadBloc extends JuiceBloc<State> {
  void processData() {
    // Business logic here
  }
}

// ✅ Good: Logic in use cases
class ProcessDataUseCase extends BlocUseCase<Bloc, Event> {
  @override
  Future<void> execute(Event event) async {
    // Business logic here
  }
}
```

## Next Steps

- Learn about [Use Cases](use-cases.md) for handling business logic
- Explore [StreamStatus](state-management.md) for managing UI states
