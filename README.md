
![Juice Logo](https://stateofplay.blob.core.windows.net/juice/juice_droplet_medium.png)


# JUICE 
## A Reactive Architecture for Flutter Combining Clean Design with BLoC, Stream-Based State Management

[![pub package](https://img.shields.io/pub/v/juice.svg)](https://pub.dev/packages/juice)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

### Juice provides a complete architectural framework for Flutter applications, combining reactive state management with clean, maintainable code organization. By integrating reactive streams with explicit use cases and strong architectural boundaries, Juice helps teams build robust, scalable applications.

# Key Features

### State Management
- **Stream-Based Design** - Familiar reactive patterns with StreamStatus
- **Smart Widget Rebuilding** - Precise control over UI updates
- **State Lifecycle** - Built-in handling of loading, error, cancel and success states

### Architecture 
- **First-Class Use Cases** - Isolated, testable business logic
- **Clean Dependencies** - Flexible dependency resolution
- **Strong Boundaries** - Clear separation between UI, business logic, and state

### Enhanced Performance 
- **Smart Widget Rebuilding** - Powerful group-based system gives you precise control over UI updates
- **Efficient State Updates** - Optimized stream-based state management prevents unnecessary rebuilds
- **Resource Management** - Automatic cleanup and disposal prevents memory leaks

### Developer Experience
- **Type-Safe Navigation** - Built-in navigation with full type safety and middleware support
- **Cancellation Support** - First-class handling of operation cancellation and timeouts
- **Error Handling** - Consistent error handling and recovery across the application

### Reactive Patterns
- **Stream-Based Design** - Familiar reactive patterns with StreamStatus for managing state transitions
- **State Lifecycle** - Built-in handling of loading, error, and success states
- **Event-Driven** - Clear, predictable flow of events through the application

## Architecture Overview

Juice creates a clean separation between:

```
UI Layer (Widgets)
    ↕️
Business Logic (Use Cases)
    ↕️  
State Management (Blocs)
```

- **Widgets** focus purely on UI rendering and user interaction
- **Use Cases** encapsulate individual business operations
- **Blocs** manage state and coordinate use cases

This separation provides clear boundaries while maintaining reactive state updates throughout the application.

## Why Juice?

Juice solves common architectural challenges:

- **Business Logic Organization**: Use cases make complex operations manageable and testable
- **State Management**: Built-in handling of loading, error, and success states
- **UI Performance**: Fine-grained control over widget rebuilds
- **Navigation**: Type-safe routing with deep linking support
- **Testing**: Clear boundaries make unit and integration testing straightforward
- **Scalability**: Clean architecture principles support growing codebases

## Quick Example

```dart
// A complete example showing a counter implementation with:
// - Reactive state management
// - Loading state handling
// - Clean separation of concerns

// Define a use case
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitWaiting();  // Show loading state
    await incrementCounter();
    emitUpdate(newState: CounterState(count: bloc.state.count + 1));
  }
}

// Create a bloc
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

// Create a reactive widget
class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (status is Waiting) return CircularProgressIndicator();
    
    return Text('Count: ${bloc.state.count}');
  }
}
```
## Installation

Add Juice to your pubspec.yaml:

```yaml
flutter pub add juice
```
This will add the latest version of Juice to your pubspec.yaml automatically.

Alternatively, add it manually:

```yaml
dependencies:
  juice: ^1.0.0
```

Then, run:
```bash
flutter pub get
```

## Quick Start

### 1. Initialize Juice

```dart
void main() {
  // Set up the global resolver for bloc dependencies
  // This manages bloc instances throughout your app
  GlobalBlocResolver().resolver = BlocResolver();
  runApp(MyApp());
}
```

### 2. Define Your State

```dart
class CounterState extends BlocState {
  final int count;
  
  CounterState({required this.count});
  
  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }
}
```

### 3. Create Events

```dart
class IncrementEvent extends EventBase {}
class DecrementEvent extends EventBase {}
```

### 4. Implement Use Cases

```dart
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    final newState = bloc.state.copyWith(count: bloc.state.count + 1);
    emitUpdate(
      newState: newState,
      groupsToRebuild: {"counter"}
    );
  }
}
```

### 5. Create Your Bloc

```dart
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          CounterState(count: 0),
          [
            () => UseCaseBuilder(
                typeOfEvent: IncrementEvent,
                useCaseGenerator: () => IncrementUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: DecrementEvent,
                useCaseGenerator: () => DecrementUseCase()),
          ],
          [], // Aviators
        );
}
```

### 6. Build Your UI

```dart
class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(
      'Count: ${bloc.state.count}',
      style: const TextStyle(fontSize: 32),
    );
  }
}
```

```dart
class CounterButtons extends StatelessJuiceWidget<CounterBloc> {
  CounterButtons({super.key, super.groups = ignoreAllRebuilds});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => bloc.send(IncrementEvent()),
          child: const Text('+'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(DecrementEvent()),
          child: const Text('-'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(ResetEvent()),
          child: const Text('Reset'),
        ),
      ],
    );
  }
}
```

## Advanced Features

### Group-Based Rebuilds

Control which widgets rebuild based on state changes:

```dart
class UserProfileWidget extends StatelessJuiceWidget<ProfileBloc> {
  // Only rebuild when "profile" group is triggered
  UserProfileWidget({super.key, super.groups = const {"profile"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(bloc.state.username);
  }
}
```

### StreamStatus for State Management

Handle different states elegantly:

```dart
@override
Widget onBuild(BuildContext context, StreamStatus status) {
  return status.when(
    building: (state, _, __) => Text(state.data),
    loading: (_, __, ___) => CircularProgressIndicator(),
    error: (_, __, ___) => Text('Error loading data'),
  );
}
```

### Navigation with Aviators

Type-safe navigation management:

```dart
 // Specific route aviator
      () => Aviator(
        name: 'profile',
        navigate: (args) {
          final bloc = GlobalBlocResolver().resolver.resolve<AppBloc>();
          final userId = args['userId'] as String;
          bloc.navigatorKey.currentState?.pushNamed('/account/$userId/profile');
        },
      ),

      // Area aviator with section routing
      () => Aviator(
        name: 'account',
        navigate: (args) {
          final bloc = GlobalBlocResolver().resolver.resolve<AppBloc>();
          final section = args['section'] as String;
          final userId = args['userId'] as String;
          
          switch (section) {
            case 'profile':
              bloc.navigatorKey.currentState?.pushNamed('/account/$userId/profile');
              break;
            case 'settings':
              bloc.navigatorKey.currentState?.pushNamed('/account/$userId/settings');
              break;
            case 'orders':
              final orderId = args['orderId'] as String?;
              final path = orderId != null 
                ? '/account/$userId/orders/$orderId'
                : '/account/$userId/orders';
              bloc.navigatorKey.currentState?.pushNamed(path);
              break;
          }
        },
      )
```

### Stateful Use Cases

Maintain state across multiple events:

```dart
class WebSocketUseCase extends StatefulUseCaseBuilder<ChatBloc, ConnectEvent> {
  WebSocket? _socket;
  
  @override
  Future<void> execute(ConnectEvent event) async {
    _socket = await WebSocket.connect('ws://...');
    // Handle connection
  }
  
  @override
  Future<void> close() async {
    await _socket?.close();
    super.close();
  }
}
```

## Best Practices

### Use Cases
- One use case per business operation
- Keep use cases focused and single-purpose 
- Handle errors consistently using emitFailure
- Follow event-handler pattern for clear input/output
- Clean up resources in close() method

### State Design
- Make state classes immutable as first choice
- Implement copyWith for state updates
- Keep bloc states laser focused on feature needs only
- Don't duplicate state across blocs

### Widget Optimization  
- Use targeted group-based rebuilds
- Define rebuild groups by UI update needs
- Keep widgets focused on UI logic
- Separate stateless and stateful juice widgets
- Handle loading/error states consistently

### Navigation
- Keep aviators simple and single-purpose
- Use consistent navigation patterns
- Handle deep linking properly
- Clean up navigation resources
- Test navigation flows independently

### Testing
- Test use cases in isolation
- Verify state transitions through StreamStatus
- Test error handling and cancellation paths 
- Validate group-based rebuild logic
- Test aviator navigation flows

### Resource Management
- Implement close() methods properly
- Clean up subscriptions and streams
- Dispose blocs when no longer needed
- Handle cancellation appropriately
- Monitor for memory leaks


## Project Status

Juice is currently at version 1.0.0 and is under active development. While the core features are stable and production-ready, work effort is focused next on:

- Comprehensive documentation and guides
- Additional examples and use cases
- Developer tools and utilities
- Extended testing utilities

### Upcoming Companion Packages
I'm excited to plan for additional packages that will extend Juice's architecture. These companion packages are designed to address common application needs while keeping the core framework lightweight and focused:

Core App Services

- juice_network: Streamlined HTTP client bloc with Dio integration
- juice_auth: Simplified authentication and authorization workflows
- juice_storage: Efficient local storage and caching solutions
- juice_connectivity: Comprehensive network and Bluetooth management
- juice_config: Flexible environment configuration and feature flagging 

UI & Interaction

- juice_form: Intuitive form handling and validation utilities
- juice_theme: Robust theme management and dynamic styling options
- juice_animation: Predefined reusable animation patterns for a polished 

UI Features & Integration

- juice_messaging: Real-time, general purpose messaging via WebSocket integration
- juice_location: Advanced location services and geofencing capabilities
- juice_analytics: Powerful tools for analytics and event tracking

By introducing these companion packages as separate modules, the aim is to keep Juice lean and maintainable while offering reliable, ready-to-use solutions for specific needs.

### Documentation

Documentation is being actively developed. 

Currently available:
- This README with a quick start guide
- Example projects in the [examples](https://github.com/kehmka/juice/tree/main/example) directory

Coming soon:
- API documentation
- Full documentation site

### Getting Help

- **Issues**: For bugs and feature requests, please [open an issue](https://github.com/kehmka/juice/issues)
- **Questions & Discussion**: For questions, ideas, and general discussion, use [GitHub Discussions](https://github.com/kehmka/juice/discussions). This helps create a searchable knowledge base for all users.
- **Examples**: Check our [example projects](https://github.com/kehmka/juice/tree/main/lib/example/lib) for common use cases

## Contributing

Contributions are welcome! Please read our [contributing guidelines](CONTRIBUTING.md) before submitting pull requests.

## License
Juice is available under the MIT license. See the [LICENSE](LICENSE) file for more information.
