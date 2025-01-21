# Stateful Use Cases

The `StatefulUseCaseBuilder` creates and maintains a single instance of a use case throughout its lifecycle. Unlike standard use cases that are created anew for each event, stateful use cases persist until explicitly closed.

## When to Use Stateful Use Cases

Use stateful use cases when you need to:
- Maintain connections (WebSocket, Bluetooth, etc.)
- Cache data between events
- Track state across multiple operations
- Manage subscriptions or resources

## Basic Implementation

Here's a typical stateful use case:

```dart
// The use case builder that manages the instance
() => StatefulUseCaseBuilder(
  typeOfEvent: ChatEvent,
  useCaseGenerator: () => ChatConnectionUseCase(),
)

// The stateful use case implementation
class ChatConnectionUseCase extends BlocUseCase<ChatBloc, ChatEvent> {
  WebSocketConnection? _connection;
  StreamSubscription? _subscription;
  
  @override
  Future<void> execute(ChatEvent event) async {
    if (_connection == null) {
      // First time setup
      _connection = await WebSocketConnection.connect();
      _setupMessageListener();
    }
    
    // Handle the event
    await _connection?.send(event.message);
    emitUpdate(newState: ChatState.messageSent());
  }
  
  void _setupMessageListener() {
    _subscription = _connection?.messages.listen(
      (message) {
        emitUpdate(
          newState: ChatState.messageReceived(message),
          groupsToRebuild: {"chat_messages"}
        );
      },
      onError: (e, stack) {
        logError(e, stack);
        emitFailure();
      }
    );
  }
  
  @override
  Future<void> close() async {
    // Clean up resources when the use case is closed
    await _subscription?.cancel();
    await _connection?.close();
    _connection = null;
    super.close();
  }
}
```

## Key Features

### Single Instance Guarantee
The `StatefulUseCaseBuilder` ensures only one instance exists:

```dart
class StatefulUseCaseBuilder extends UseCaseBuilderBase {
  UseCase? _instance;
  
  @override
  UseCaseGenerator get generator => () {
    _instance ??= useCaseGenerator();
    return _instance!;
  };
}
```

### Proper Cleanup
Resources are cleaned up when the builder is closed:

```dart
@override
Future<void> close() async {
  await _instance?.close();
  _instance = null;
}
```

## Best Practices

1. **Resource Management**
```dart
class ResourcefulUseCase extends BlocUseCase<Bloc, Event> {
  final _resources = <Resource>[];
  final _subscriptions = <StreamSubscription>[];
  
  @override
  Future<void> execute(Event event) async {
    // Track resources you create
    final resource = await createResource();
    _resources.add(resource);
    
    // Track subscriptions
    final subscription = stream.listen(/*...*/);
    _subscriptions.add(subscription);
  }
  
  @override
  Future<void> close() async {
    // Clean up everything
    await Future.wait(_subscriptions.map((s) => s.cancel()));
    await Future.wait(_resources.map((r) => r.dispose()));
    _subscriptions.clear();
    _resources.clear();
    super.close();
  }
}
```

2. **State Initialization**
```dart
class ConnectionUseCase extends BlocUseCase<Bloc, Event> {
  Connection? _connection;
  
  Future<void> _ensureInitialized() async {
    if (_connection != null) return;
    
    emitWaiting(groupsToRebuild: {"connection_status"});
    _connection = await Connection.create();
    emitUpdate(
      newState: State.connected(),
      groupsToRebuild: {"connection_status"}
    );
  }
  
  @override
  Future<void> execute(Event event) async {
    await _ensureInitialized();
    // Use connection...
  }
}
```

3. **Error Recovery**
```dart
class ResilientUseCase extends BlocUseCase<Bloc, Event> {
  Connection? _connection;
  
  Future<void> _reconnect() async {
    await _connection?.close();
    _connection = null;
    
    emitWaiting(groupsToRebuild: {"connection_status"});
    _connection = await Connection.create();
    emitUpdate(
      newState: State.reconnected(),
      groupsToRebuild: {"connection_status"}
    );
  }
  
  @override
  Future<void> execute(Event event) async {
    try {
      if (_connection?.isDisconnected ?? false) {
        await _reconnect();
      }
      // Use connection...
    } catch (e, stack) {
      logError(e, stack);
      await _reconnect();
    }
  }
}
```

## Common Pitfalls

1. **Not Cleaning Up Resources**
```dart
// ❌ Bad: Resources leak
class LeakyUseCase extends BlocUseCase<Bloc, Event> {
  late final subscription = stream.listen(/*...*/);  // Never cancelled!
}

// ✅ Good: Proper cleanup
class CleanUseCase extends BlocUseCase<Bloc, Event> {
  StreamSubscription? _subscription;
  
  @override
  Future<void> execute(Event event) async {
    _subscription = stream.listen(/*...*/);
  }
  
  @override
  Future<void> close() async {
    await _subscription?.cancel();
    super.close();
  }
}
```

2. **Unsafe State Access**
```dart
// ❌ Bad: No null checks
class UnsafeUseCase extends BlocUseCase<Bloc, Event> {
  Connection? _connection;
  
  @override
  Future<void> execute(Event event) async {
    await _connection.send(event.data);  // May crash!
  }
}

// ✅ Good: Safe state access
class SafeUseCase extends BlocUseCase<Bloc, Event> {
  Connection? _connection;
  
  @override
  Future<void> execute(Event event) async {
    if (_connection == null) {
      emitFailure(newState: State.notConnected());
      return;
    }
    await _connection.send(event.data);
  }
}
```

3. **Not Handling Reinitialization**
```dart
// ❌ Bad: No reconnection logic
class FragileUseCase extends BlocUseCase<Bloc, Event> {
  Connection? _connection;
  
  @override
  Future<void> execute(Event event) async {
    _connection ??= await Connection.create();
    // What if connection failed or was closed?
  }
}

// ✅ Good: Robust connection handling
class RobustUseCase extends BlocUseCase<Bloc, Event> {
  Connection? _connection;
  
  Future<void> _ensureConnected() async {
    if (_connection?.isHealthy ?? false) return;
    
    await _connection?.close();
    _connection = await Connection.create();
  }
  
  @override
  Future<void> execute(Event event) async {
    await _ensureConnected();
    // Use connection...
  }
}
```

## Testing Stateful Use Cases

```dart
void main() {
  late StatefulUseCaseBuilder builder;
  late MockConnection connection;
  
  setUp(() {
    connection = MockConnection();
    builder = StatefulUseCaseBuilder(
      typeOfEvent: ConnectionEvent,
      useCaseGenerator: () => ConnectionUseCase(connection)
    );
  });
  
  tearDown(() async {
    await builder.close();  // Clean up after each test
  });
  
  test('maintains single instance', () {
    final useCase1 = builder.generator();
    final useCase2 = builder.generator();
    expect(useCase1, same(useCase2));  // Same instance
  });
}
```

## Next Steps

- Learn about [Relay Use Cases](relay-use-cases.md) for bloc communication
- Explore [Advanced Use Cases](advanced-use-cases.md) for complex patterns