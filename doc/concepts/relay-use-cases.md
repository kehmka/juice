# Relay Use Cases

Relay use cases create connections between blocs, allowing state changes in one bloc to trigger events in another. This creates a reactive flow of data while maintaining clean separation between features.

## Basic Implementation

A relay connects a source bloc to a destination bloc:

```dart
// In destination bloc
() => RelayUseCaseBuilder<AuthBloc, ProfileBloc, AuthState>(
  typeOfEvent: LoadProfileEvent,
  statusToEventTransformer: (status) {
    return status.when(
      updating: (state, _, __) {
        if (state.isAuthenticated) {
          return LoadProfileEvent(userId: state.userId);
        } else {
          return ClearProfileEvent();
        }
      },
      waiting: (_, __, ___) => LoadingProfileEvent(),
      error: (_, __, ___) => ClearProfileEvent(),
      canceling: (_, __, ___) => ClearProfileEvent(),
    );
  },
  useCaseGenerator: () => LoadProfileUseCase(),
)
```

## How It Works

1. The relay monitors the source bloc's stream
2. When the source emits a new status, the transformer creates an event
3. The event is sent to the destination bloc
4. A use case in the destination bloc handles the event

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

// Events
class LoadProfileEvent extends EventBase {
  final String userId;
  LoadProfileEvent({required this.userId});
}

class ClearProfileEvent extends EventBase {}
class LoadingProfileEvent extends EventBase {}

// Relay setup in destination bloc (ProfileBloc)
class ProfileBloc extends JuiceBloc<ProfileState> {
  ProfileBloc() : super(
    ProfileState(),
    [
      // Standard use case for loading profiles
      () => UseCaseBuilder(
        typeOfEvent: LoadProfileEvent,
        useCaseGenerator: () => LoadProfileUseCase(),
      ),
      
      // Relay from AuthBloc
      () => RelayUseCaseBuilder<AuthBloc, ProfileBloc, AuthState>(
        typeOfEvent: LoadProfileEvent,
        statusToEventTransformer: (status) {
          return status.when(
            updating: (state, oldState, _) {
              // Load profile when user authenticates
              if (state.isAuthenticated && !oldState.isAuthenticated) {
                return LoadProfileEvent(userId: state.userId!);
              }
              // Clear profile when user logs out
              if (!state.isAuthenticated && oldState.isAuthenticated) {
                return ClearProfileEvent();
              }
              // No event needed for other updates
              return null;
            },
            waiting: (_, __, ___) => LoadingProfileEvent(),
            error: (_, __, ___) => ClearProfileEvent(),
            canceling: (_, __, ___) => ClearProfileEvent(),
          );
        },
        useCaseGenerator: () => LoadProfileUseCase(),
      ),
    ],
    [], // No aviators needed
  );
}
```

## Key Features

### Type Safety

The relay enforces type safety through generics:
```dart
RelayUseCaseBuilder<
  TSourceBloc extends JuiceBloc,   // Source bloc type
  TDestBloc extends JuiceBloc,     // Destination bloc type
  TSourceState extends BlocState   // Source state type
>
```

### Automatic Lifecycle Management

Relays are automatically cleaned up when blocs are closed:
```dart
void _setupPump() {
  _subscription = sourceBloc.stream.listen(
    (ss) async {
      if (_isClosed) return;
      try {
        final event = statusToEventTransformer(ss);
        if (event != null) {
          destBloc.send(event);
        }
      } catch (e, stackTrace) {
        JuiceLoggerConfig.logger.logError('Error in relay', e, stackTrace);
        await close();
      }
    },
    onError: (error, stackTrace) async {
      JuiceLoggerConfig.logger
          .logError('Stream error in relay', error, stackTrace);
      await close();
    },
    onDone: () async => await close(),
  );
}
```

### Error Handling

Relays include built-in error handling and logging:
```dart
try {
  event = statusToEventTransformer(ss);
  destBloc.send(event);
} catch (e, stackTrace) {
  JuiceLoggerConfig.logger.logError(
    'Error in relay between ${TSourceBloc.runtimeType} and ${TDestBloc.runtimeType}',
    e,
    stackTrace
  );
  await close();
}
```

## Common Patterns

### Authentication Flow

Connect auth state to other features:
```dart
// In ProfileBloc
() => RelayUseCaseBuilder<AuthBloc, ProfileBloc, AuthState>(
  typeOfEvent: LoadProfileEvent,
  statusToEventTransformer: (status) => status.when(
    updating: (state, oldState, _) {
      if (state.isAuthenticated && !oldState.isAuthenticated) {
        return LoadProfileEvent(userId: state.userId!);
      }
      return null;
    },
    error: (_, __, ___) => ClearProfileEvent(),
    waiting: (_, __, ___) => null,
    canceling: (_, __, ___) => null,
  ),
  useCaseGenerator: () => LoadProfileUseCase(),
)

// In CartBloc
() => RelayUseCaseBuilder<AuthBloc, CartBloc, AuthState>(
  typeOfEvent: LoadCartEvent,
  statusToEventTransformer: (status) => status.when(
    updating: (state, oldState, _) {
      if (state.isAuthenticated && !oldState.isAuthenticated) {
        return LoadCartEvent(userId: state.userId!);
      }
      if (!state.isAuthenticated && oldState.isAuthenticated) {
        return ClearCartEvent();
      }
      return null;
    },
    error: (_, __, ___) => ClearCartEvent(),
    waiting: (_, __, ___) => null,
    canceling: (_, __, ___) => null,
  ),
  useCaseGenerator: () => LoadCartUseCase(),
)
```

### Data Dependencies

Load dependent data automatically:
```dart
// In OrderDetailsBloc
() => RelayUseCaseBuilder<OrderBloc, OrderDetailsBloc, OrderState>(
  typeOfEvent: LoadDetailsEvent,
  statusToEventTransformer: (status) => status.when(
    updating: (state, _, __) {
      if (state.selectedOrderId != null) {
        return LoadDetailsEvent(orderId: state.selectedOrderId!);
      }
      return null;
    },
    error: (_, __, ___) => ClearDetailsEvent(),
    waiting: (_, __, ___) => LoadingDetailsEvent(),
    canceling: (_, __, ___) => ClearDetailsEvent(),
  ),
  useCaseGenerator: () => LoadDetailsUseCase(),
)
```

## Best Practices

1. **Clear Dependencies**
   - Keep relay chains simple and direct
   - Avoid circular dependencies
   - Document the flow of data

2. **Selective Event Creation**
   - Only create events when needed
   - Return null from transformer to skip event
   - Consider old state when deciding

3. **Error Handling**
   - Handle all StreamStatus types
   - Log errors with context
   - Clean up resources properly

4. **State Transitions**
   - Consider all possible state changes
   - Handle edge cases explicitly
   - Document expected behavior

## Common Pitfalls

1. **Circular Dependencies**
```dart
// ❌ Bad: Blocs depend on each other
class BlocA extends JuiceBloc {
  // Relay from BlocB
}

class BlocB extends JuiceBloc {
  // Relay from BlocA
}

// ✅ Good: Clear dependency direction
class BlocA extends JuiceBloc {
  // Source of truth, no relays
}

class BlocB extends JuiceBloc {
  // Relays from BlocA only
}
```

2. **Over-Relaying**
```dart
// ❌ Bad: Creating unnecessary events
statusToEventTransformer: (status) => status.when(
  updating: (state, _, __) => UpdateEvent(),  // Every update!
)

// ✅ Good: Selective events
statusToEventTransformer: (status) => status.when(
  updating: (state, oldState, _) {
    if (state.value != oldState.value) {  // Only when needed
      return UpdateEvent(state.value);
    }
    return null;
  }
)
```

3. **Missing Status Types**
```dart
// ❌ Bad: Incomplete status handling
statusToEventTransformer: (status) => status.when(
  updating: (state, _, __) => UpdateEvent(),
  waiting: (_, __, ___) => null,
  error: (_, __, ___) => null,
  // Forgot canceling!
)

// ✅ Good: Handle all status types
statusToEventTransformer: (status) => status.when(
  updating: (state, _, __) => UpdateEvent(),
  waiting: (_, __, ___) => LoadingEvent(),
  error: (_, __, ___) => ErrorEvent(),
  canceling: (_, __, ___) => CancelEvent(),
)
```

## Testing

```dart
void main() {
  late AuthBloc authBloc;
  late ProfileBloc profileBloc;
  
  setUp(() {
    authBloc = AuthBloc();
    profileBloc = ProfileBloc();
  });
  
  tearDown(() async {
    await authBloc.close();
    await profileBloc.close();
  });
  
  test('loads profile on authentication', () async {
    // Trigger auth state change
    authBloc.send(LoginEvent(userId: '123'));
    
    // Verify profile load was triggered
    await expectLater(
      profileBloc.stream,
      emits(isA<LoadingProfileEvent>())
    );
  });
}
```

## Next Steps

- Learn about [Stateful Use Cases](stateful-use-cases.md) for managing resources
- Explore [Testing Patterns](../testing/testing-relay-use-cases) for relay testing
- See [Advanced Use Cases](advanced-use-cases.md) for complex patterns