# Cross-Bloc Communication with Relays

Relays create connections between blocs, allowing state changes in one bloc to trigger events in another. This enables reactive data flow while maintaining clean separation between features.

## StateRelay vs StatusRelay

Juice provides two relay types for different use cases:

| Class | Use When | Receives |
|-------|----------|----------|
| `StateRelay` | You only need the state values | `TSourceState` |
| `StatusRelay` | You need to handle waiting/error states | `StreamStatus<TSourceState>` |

## StateRelay

`StateRelay` is the simpler and more common choice. Use it when you only need to react to state changes:

```dart
// Simple: When cart changes, update order total
final relay = StateRelay<CartBloc, OrderBloc, CartState>(
  toEvent: (state) => UpdateTotalEvent(
    total: state.items.fold(0, (sum, item) => sum + item.price),
  ),
);
```

### With Filtering

Use the `when` predicate to filter which state changes trigger the relay:

```dart
// Only relay when user is authenticated
final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => LoadProfileEvent(userId: state.userId!),
  when: (state) => state.isAuthenticated && state.userId != null,
);
```

### Complete Example

```dart
// States
class AuthState extends BlocState {
  final String? userId;
  final bool isAuthenticated;

  AuthState({this.userId, this.isAuthenticated = false});
}

class ProfileState extends BlocState {
  final UserProfile? profile;
  final bool isLoaded;

  ProfileState({this.profile, this.isLoaded = false});
}

// Event
class LoadProfileEvent extends EventBase {
  final String userId;
  LoadProfileEvent({required this.userId});
}

// Create the relay
final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => LoadProfileEvent(userId: state.userId!),
  when: (state) => state.isAuthenticated && state.userId != null,
);

// Don't forget to clean up when done
await relay.close();
```

## StatusRelay

Use `StatusRelay` when you need to react differently based on the stream status (waiting, failure, canceling):

```dart
final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (status) => status.when(
    updating: (state, oldState, _) {
      if (state.isAuthenticated) {
        return LoadProfileEvent(userId: state.userId!);
      }
      return ClearProfileEvent();
    },
    waiting: (_, __, ___) => ProfileLoadingEvent(),
    failure: (_, __, ___) => ClearProfileEvent(),
    canceling: (_, __, ___) => ClearProfileEvent(),
  ),
);
```

### Complete StatusRelay Example

```dart
// Events for different scenarios
class LoadProfileEvent extends EventBase {
  final String userId;
  LoadProfileEvent({required this.userId});
}

class ProfileLoadingEvent extends EventBase {}
class ClearProfileEvent extends EventBase {}

// StatusRelay with full status handling
final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (status) => status.when(
    updating: (state, oldState, _) {
      // React to state transitions
      if (state.isAuthenticated && !oldState.isAuthenticated) {
        return LoadProfileEvent(userId: state.userId!);
      }
      if (!state.isAuthenticated && oldState.isAuthenticated) {
        return ClearProfileEvent();
      }
      return LoadProfileEvent(userId: state.userId!);
    },
    waiting: (_, __, ___) => ProfileLoadingEvent(),
    failure: (_, __, ___) => ClearProfileEvent(),
    canceling: (_, __, ___) => ClearProfileEvent(),
  ),
  // Optional: filter which statuses trigger relay
  when: (status) => status is UpdatingStatus,
);
```

## How Relays Work

1. The relay monitors the source bloc's stream (e.g., AuthBloc)
2. When source emits a new status, the transformer creates a destination event
3. The event is sent to the destination bloc (e.g., ProfileBloc)
4. A use case in the destination bloc handles the event

```
┌─────────────┐     state/status     ┌─────────────┐     event      ┌─────────────┐
│ Source Bloc │ ──────────────────► │    Relay    │ ─────────────► │  Dest Bloc  │
│  (AuthBloc) │                      │ (transform) │                │(ProfileBloc)│
└─────────────┘                      └─────────────┘                └─────────────┘
```

## Using Relays with BlocScope

When using `BlocScope` for dependency injection, relays automatically resolve blocs:

```dart
// Register blocs first
BlocScope.register<AuthBloc>(
  () => AuthBloc(),
  lifecycle: BlocLifecycle.permanent,
);
BlocScope.register<ProfileBloc>(
  () => ProfileBloc(),
  lifecycle: BlocLifecycle.permanent,
);

// Create relay - blocs resolved automatically via BlocScope
final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => LoadProfileEvent(userId: state.userId!),
  when: (state) => state.isAuthenticated,
);
```

### Using Scoped Blocs

For feature-scoped blocs, specify the scope:

```dart
final relay = StateRelay<CartBloc, OrderBloc, CartState>(
  toEvent: (state) => UpdateOrderEvent(items: state.items),
  sourceScope: checkoutScope,  // Resolve CartBloc from checkout scope
  destScope: checkoutScope,    // Resolve OrderBloc from checkout scope
);
```

## Best Practices

### 1. Choose the Right Relay Type
```dart
// Use StateRelay when you only care about state values
StateRelay<SourceBloc, DestBloc, SourceState>(
  toEvent: (state) => SomeEvent(value: state.value),
);

// Use StatusRelay when you need to handle loading/error states
StatusRelay<SourceBloc, DestBloc, SourceState>(
  toEvent: (status) => status.when(
    updating: (state, _, __) => DataEvent(value: state.value),
    waiting: (_, __, ___) => LoadingEvent(),
    failure: (_, __, ___) => ErrorEvent(),
    canceling: (_, __, ___) => CancelEvent(),
  ),
);
```

### 2. Always Clean Up
```dart
// Store relay reference
final relay = StateRelay<...>(...);

// Clean up when done
await relay.close();
```

### 3. Use Filtering to Reduce Noise
```dart
// Only relay when condition is met
StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => LoadProfileEvent(userId: state.userId!),
  when: (state) => state.isAuthenticated && state.userId != null,
);
```

### 4. Keep Transformers Simple
```dart
// Simple and clear transformer
toEvent: (state) => UpdateEvent(value: state.value),

// If logic is complex, move to a helper method
toEvent: _transformState,

EventBase _transformState(SourceState state) {
  // Complex logic here
  return SomeEvent(...);
}
```

## Common Patterns

### Authentication to Profile Loading
```dart
StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => LoadProfileEvent(userId: state.userId!),
  when: (state) => state.isAuthenticated && state.userId != null,
);
```

### Cart to Order Summary
```dart
StateRelay<CartBloc, OrderBloc, CartState>(
  toEvent: (state) => UpdateSummaryEvent(
    subtotal: state.subtotal,
    tax: state.tax,
    total: state.total,
  ),
);
```

### Settings to Theme
```dart
StateRelay<SettingsBloc, ThemeBloc, SettingsState>(
  toEvent: (state) => ApplyThemeEvent(
    isDarkMode: state.isDarkMode,
    primaryColor: state.primaryColor,
  ),
);
```

## Testing Relays

```dart
void main() {
  late AuthBloc authBloc;
  late ProfileBloc profileBloc;
  late StateRelay relay;

  setUp(() {
    authBloc = AuthBloc();
    profileBloc = ProfileBloc();

    // Create relay with test resolver
    relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: state.userId!),
      when: (state) => state.isAuthenticated,
      resolver: TestResolver({
        AuthBloc: authBloc,
        ProfileBloc: profileBloc,
      }),
    );
  });

  tearDown(() async {
    await relay.close();
    await authBloc.close();
    await profileBloc.close();
  });

  test('loads profile when authenticated', () async {
    // Allow relay to initialize
    await Future.delayed(Duration(milliseconds: 100));

    // Trigger auth state change
    await authBloc.send(LoginEvent(userId: '123'));
    await Future.delayed(Duration(milliseconds: 100));

    // Verify profile loaded
    expect(profileBloc.state.profile?.userId, equals('123'));
  });
}
```

## Migration from RelayUseCaseBuilder

`RelayUseCaseBuilder` is deprecated. Here's how to migrate:

```dart
// Before (deprecated):
RelayUseCaseBuilder<AuthBloc, ProfileBloc, AuthState>(
  typeOfEvent: LoadProfileEvent,
  useCaseGenerator: () => LoadProfileUseCase(),
  statusToEventTransformer: (status) => LoadProfileEvent(
    userId: status.state.userId,
  ),
)

// After - StateRelay (if you only need state):
StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => LoadProfileEvent(userId: state.userId!),
  when: (state) => state.isAuthenticated,
)

// After - StatusRelay (if you need full status):
StatusRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (status) => status.when(
    updating: (state, _, __) => LoadProfileEvent(userId: state.userId!),
    waiting: (_, __, ___) => ProfileLoadingEvent(),
    failure: (_, __, ___) => ClearProfileEvent(),
    canceling: (_, __, ___) => ClearProfileEvent(),
  ),
)
```

Key differences:
- No `typeOfEvent` needed - the event type is inferred
- No `useCaseGenerator` needed - the destination bloc handles events normally
- Simpler API with `toEvent` instead of `statusToEventTransformer`
- Built-in `when` predicate for filtering

## Next Steps

- Learn about [EventSubscription](../concepts/event-subscription.md) for event-to-event communication
- Explore [Testing Patterns](../testing/testing-relay-use-cases.md)
- See [State Management](state-management.md) for state design
