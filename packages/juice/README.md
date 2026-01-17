
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

### Bloc Lifecycle Management
- **Permanent Blocs** - App-level blocs that live for the entire application lifetime
- **Feature Blocs** - Scoped blocs that are disposed when a feature completes
- **Leased Blocs** - Widget-level blocs with automatic reference-counted disposal

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
    ↕️
Lifecycle Management (BlocScope)
```

- **Widgets** focus purely on UI rendering and user interaction
- **Use Cases** encapsulate individual business operations
- **Blocs** manage state and coordinate use cases
- **BlocScope** controls bloc registration, resolution, and lifecycle

This separation provides clear boundaries while maintaining reactive state updates throughout the application.

## Why Juice?

Juice solves common architectural challenges:

- **Business Logic Organization**: Use cases make complex operations manageable and testable
- **State Management**: Built-in handling of loading, error, and success states
- **Lifecycle Management**: Semantic control over bloc creation and disposal with permanent, feature, and leased lifecycles
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
    final newState = bloc.state.copyWith(count: bloc.state.count + 1);
    emitUpdate(groupsToRebuild: {"counter"}, newState: newState);
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
  juice: ^1.3.0
```

Then, run:
```bash
flutter pub get
```

## Quick Start

### 1. Initialize Juice

```dart
void main() {
  // Register your blocs with appropriate lifecycles
  BlocScope.register<CounterBloc>(
    () => CounterBloc(),
    lifecycle: BlocLifecycle.permanent, // Lives for app lifetime
  );

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

### Type-Safe Rebuild Groups

Use `RebuildGroup` for compile-time safe rebuild groups instead of magic strings:

```dart
// Define type-safe groups
abstract class ProfileGroups {
  static const header = RebuildGroup('profile:header');
  static const details = RebuildGroup('profile:details');
  static const stats = RebuildGroup('profile:stats');
}

// Use in widgets
class ProfileHeader extends StatelessJuiceWidget<ProfileBloc> {
  ProfileHeader({
    super.key,
    super.groups = const {"profile:header"}, // String groups still work
  });
}

// Use in use cases with .toStringSet()
emitUpdate(
  newState: newState,
  groupsToRebuild: {ProfileGroups.header, ProfileGroups.stats}.toStringSet(),
);

// Or with inline use cases (auto-converts)
ctx.emit.update(
  newState: newState,
  groups: {ProfileGroups.header}, // Accepts RebuildGroup, enum, or String
);
```

Built-in groups:
- `RebuildGroup.all` - Equivalent to `{"*"}`, rebuilds all widgets
- `RebuildGroup.optOut` - Equivalent to `{"-"}`, never rebuilds

### StreamStatus for State Management

Handle different states elegantly:

```dart
@override
Widget onBuild(BuildContext context, StreamStatus status) {
  // Handle status changes while keeping type safety
  if (status.isWaitingFor<DataState>()) {
    return CircularProgressIndicator();
  }
  if (status.isFailureFor<DataState>()) {
    return Text('Error loading data');
  }
  
  // Access state directly through bloc for type safety
  return Text(bloc.state.data);
}
```

### Navigation with Aviators

Type-safe navigation management:

```dart
// Specific route aviator
() => Aviator(
  name: 'profile',
  navigate: (args) {
    final bloc = BlocScope.get<AppBloc>();
    final userId = args['userId'] as String;
    bloc.navigatorKey.currentState?.pushNamed('/account/$userId/profile');
  },
),

// Area aviator with section routing
() => Aviator(
  name: 'account',
  navigate: (args) {
    final bloc = BlocScope.get<AppBloc>();
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

### Inline Use Cases

For simple, stateless operations that don't require a dedicated class:

```dart
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc() : super(CounterState(), [
    // Simple operations defined inline
    () => InlineUseCaseBuilder<CounterBloc, CounterState, IncrementEvent>(
      typeOfEvent: IncrementEvent,
      handler: (ctx, event) async {
        ctx.emit.update(
          newState: ctx.state.copyWith(count: ctx.state.count + 1),
          groups: {CounterGroups.counter},
        );
      },
    ),

    // Async operations with waiting state
    () => InlineUseCaseBuilder<CounterBloc, CounterState, LoadEvent>(
      typeOfEvent: LoadEvent,
      handler: (ctx, event) async {
        ctx.emit.waiting(groups: {CounterGroups.counter});
        final data = await fetchData();
        ctx.emit.update(
          newState: ctx.state.copyWith(data: data),
          groups: {CounterGroups.counter},
        );
      },
    ),
  ]);
}
```

**When to use inline vs class-based:**
- Use `InlineUseCaseBuilder` for simple state updates, toggles, and straightforward operations
- Use class-based `UseCase` for I/O operations, caching, retry logic, or multi-step flows

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

### Retryable Use Cases

Wrap any use case with automatic retry logic:

```dart
() => RetryableUseCaseBuilder<MyBloc, MyState, FetchDataEvent>(
  typeOfEvent: FetchDataEvent,
  useCaseGenerator: () => FetchDataUseCase(),
  maxRetries: 3,
  backoff: ExponentialBackoff(
    initial: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    jitter: true,  // Prevents thundering herd
  ),
  retryWhen: (error) => error is NetworkException,
  onRetry: (attempt, error, delay) {
    print('Retry $attempt after ${delay.inSeconds}s');
  },
)
```

Backoff strategies:
- `FixedBackoff` - Constant delay between retries
- `ExponentialBackoff` - Delays grow exponentially (1s, 2s, 4s...)
- `LinearBackoff` - Delays grow linearly (1s, 2s, 3s...)

### Bloc Lifecycle Management

Juice provides three lifecycle options for blocs, giving you precise control over when blocs are created and disposed:

#### Permanent Blocs
App-level blocs that live for the entire application lifetime:

```dart
// Register at app startup
BlocScope.register<AuthBloc>(
  () => AuthBloc(),
  lifecycle: BlocLifecycle.permanent,
);

// Access anywhere in your app
final authBloc = BlocScope.get<AuthBloc>();
```

#### Feature Blocs
Blocs scoped to a feature or user flow that are disposed together:

```dart
class CheckoutFlow {
  final scope = FeatureScope('checkout');

  void start() {
    // Register blocs for this feature
    BlocScope.register<CartBloc>(
      () => CartBloc(),
      lifecycle: BlocLifecycle.feature,
      scope: scope,
    );
    BlocScope.register<PaymentBloc>(
      () => PaymentBloc(),
      lifecycle: BlocLifecycle.feature,
      scope: scope,
    );
  }

  Future<void> complete() async {
    // Dispose all blocs in this feature scope
    await BlocScope.endFeature(scope);
  }
}
```

#### Leased Blocs
Widget-level blocs with automatic reference-counted disposal:

```dart
// Register as leased
BlocScope.register<FormBloc>(
  () => FormBloc(),
  lifecycle: BlocLifecycle.leased,
);

// In your widget, acquire a lease
class MyFormWidget extends StatefulWidget {
  @override
  State<MyFormWidget> createState() => _MyFormWidgetState();
}

class _MyFormWidgetState extends State<MyFormWidget> {
  late final BlocLease<FormBloc> _lease;

  @override
  void initState() {
    super.initState();
    _lease = BlocScope.lease<FormBloc>();
  }

  @override
  void dispose() {
    _lease.dispose(); // Bloc closes when last lease is released
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_lease.bloc.state.value);
  }
}
```

#### Diagnostics

Monitor bloc lifecycle in development:

```dart
// Get diagnostic info for a bloc
final info = BlocScope.diagnostics<MyBloc>();
print('Active: ${info?.isActive}');
print('Lease count: ${info?.leaseCount}');
print('Created at: ${info?.createdAt}');

// Dump all registered blocs (debug only)
BlocScope.debugDump();
```

### Cross-Bloc Communication

#### EventSubscription
Listen to events from one bloc and transform them for another:

```dart
class DestBloc extends JuiceBloc<DestState> {
  DestBloc() : super(
    DestState(),
    [
      () => UseCaseBuilder(
        typeOfEvent: DestEvent,
        useCaseGenerator: () => DestUseCase(),
      ),
      // Subscribe to events from SourceBloc
      () => EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (sourceEvent) => DestEvent(
          message: 'Received: ${sourceEvent.data}',
        ),
        useCaseGenerator: () => DestUseCase(),
        when: (event) => event.shouldForward, // Optional filter
      ),
    ],
    [],
  );
}
```

#### StateRelay
React to state changes from one bloc and trigger events in another:

```dart
// Simple state relay
final relay = StateRelay<CartBloc, OrderBloc, CartState>(
  toEvent: (state) => UpdateTotalEvent(
    total: state.items.fold(0, (sum, item) => sum + item.price),
  ),
);

// With filtering - only relay when condition is met
final authRelay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => LoadProfileEvent(userId: state.userId!),
  when: (state) => state.isAuthenticated && state.userId != null,
);

// Clean up when done
await relay.close();
```

#### StatusRelay
For when you need access to the full StreamStatus (waiting, error states):

```dart
final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (status) => status.when(
    updating: (state, _, __) => state.isAuthenticated
      ? LoadProfileEvent(userId: state.userId!)
      : ClearProfileEvent(),
    waiting: (_, __, ___) => ProfileLoadingEvent(),
    failure: (_, __, ___) => ClearProfileEvent(),
    canceling: (_, __, ___) => ClearProfileEvent(),
  ),
);
```

## Best Practices

### Bloc Lifecycle
- Use `BlocLifecycle.permanent` for app-level blocs (auth, settings, theme)
- Use `BlocLifecycle.feature` for multi-screen flows (checkout, onboarding)
- Use `BlocLifecycle.leased` for widget-specific blocs (forms, modals)
- Always call `BlocScope.endFeature()` when a feature completes
- Release leases in widget `dispose()` methods

### Use Cases
- One use case per business operation
- Keep use cases focused and single-purpose
- Handle errors consistently using emitFailure
- Follow event-handler pattern for clear input/output
- Clean up resources in close() method
- Use `InlineUseCaseBuilder` for simple, stateless operations
- Use class-based `UseCase` for I/O, caching, or complex logic

### State Design
- Make state classes immutable as first choice
- Implement copyWith for state updates
- Keep bloc states laser focused on feature needs only
- Don't duplicate state across blocs

### Widget Optimization
- Use targeted group-based rebuilds
- Define rebuild groups by UI update needs
- Use `RebuildGroup` for type-safe group definitions
- Keep widgets focused on UI logic
- Separate stateless and stateful juice widgets
- Handle loading/error states consistently

### Cross-Bloc Communication
- Use `EventSubscription` for event-to-event forwarding between blocs
- Use `StateRelay` for simple state-to-event transformation
- Use `StatusRelay` when you need to handle waiting/error states
- Always close relays when no longer needed
- Use `when` predicates to filter unnecessary events

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
- Test bloc lifecycle (creation, disposal, lease counting)

### Resource Management
- Choose appropriate lifecycle for each bloc type
- Use `BlocScope.diagnostics()` to monitor bloc state in development
- Call `BlocScope.endAll()` on app shutdown
- Release all leases before widget disposal
- Handle cancellation appropriately
- Use `BlocScope.debugDump()` to detect leaks during development


## Project Status

Juice is currently at version 1.3.0 and is under active development. While the core features are stable and production-ready, work effort is focused next on:

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

## Acknowledgments
We deeply appreciate everyone who supports the Juice framework!

- Contributors: Developers who have helped improve Juice by submitting code, reporting bugs, or enhancing documentation.
- Sponsors: Individuals and organizations providing financial support to drive Juice's ongoing development.
- View the [Contributors' Hall of Fame](CONTRIBUTORS.md) to see who has made an impact.
- View the [Sponsors' Hall of Fame](SPONSORS.md) to see our valued sponsors.
- Learn more about becoming a sponsor in our Sponsorship Tiers.

## License
Juice is available under the MIT license. See the [LICENSE](LICENSE) file for more information.

## Author
Juice was created and is maintained by Kevin Ehmka. For inquiries, please feel free to reach out via email at kehmka@gmail.com.