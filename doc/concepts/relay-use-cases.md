# Relay Use Cases

Relay use cases create connections between blocs, allowing state changes in one bloc to trigger events in another. This creates a reactive flow of data while maintaining clean separation between features.

## Type-Safe Implementation

A relay connects a single source bloc to a destination bloc:

```dart
// Events must be of a single type for type safety
class LoadProfileEvent extends EventBase {
  final String? userId;  // Can be null for clearing
  final bool isLoading;
  
  LoadProfileEvent({
    this.userId,
    this.isLoading = false,
  });
}

// In ProfileBloc (destination)
() => RelayUseCaseBuilder<AuthBloc, ProfileBloc, AuthState>(
  typeOfEvent: LoadProfileEvent,
  // Transform source bloc state into destination bloc event
  statusToEventTransformer: (status) => status.when(
    updating: (state, _, __) => LoadProfileEvent(
      userId: state.userId,
      isLoading: false
    ),
    waiting: (_, __, ___) => LoadProfileEvent(isLoading: true),
    failure: (_, __, ___) => LoadProfileEvent(userId: null),
    canceling: (_, __, ___) => LoadProfileEvent(userId: null),
  ),
  useCaseGenerator: () => LoadProfileUseCase(),
)
```

## How It Works

1. The relay monitors the source bloc's stream (e.g., AuthBloc)
2. When source emits a new status, transformer creates a destination event (e.g., LoadProfileEvent)
3. The event is sent to destination bloc (e.g., ProfileBloc)
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

// Single event type for type safety
class LoadProfileEvent extends EventBase {
  final String? userId;
  final bool isLoading;
  
  LoadProfileEvent({
    this.userId,
    this.isLoading = false,
  });
}

// Relay setup in ProfileBloc (destination)
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
        statusToEventTransformer: (status) => status.when(
          updating: (state, oldState, _) {
            if (state.isAuthenticated && !oldState.isAuthenticated) {
              return LoadProfileEvent(userId: state.userId);
            }
            if (!state.isAuthenticated && oldState.isAuthenticated) {
              return LoadProfileEvent(userId: null);
            }
            return LoadProfileEvent(userId: state.userId);
          },
          waiting: (_, __, ___) => LoadProfileEvent(isLoading: true),
          failure: (_, __, ___) => LoadProfileEvent(userId: null),
          canceling: (_, __, ___) => LoadProfileEvent(userId: null),
        ),
        useCaseGenerator: () => LoadProfileUseCase(),
      )
    ],
    [],
  );
}

// Type-safe use case handling a single event type
class LoadProfileUseCase extends BlocUseCase<ProfileBloc, LoadProfileEvent> {
  @override
  Future<void> execute(LoadProfileEvent event) async {
    if (event.isLoading) {
      emitWaiting(groupsToRebuild: {"profile_status"});
      return;
    }

    if (event.userId == null) {
      emitUpdate(
        newState: ProfileState(),
        groupsToRebuild: {"profile_content"}
      );
      return;
    }

    try {
      emitWaiting(groupsToRebuild: {"profile_status"});
      final profile = await loadProfile(event.userId!);
      
      emitUpdate(
        newState: ProfileState(
          profile: profile,
          isLoaded: true
        ),
        groupsToRebuild: {"profile_content"}
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"profile_status"});
    }
  }
}
```

## Best Practices

1. **Single Event Type**
   - Each relay should transform to a single event type
   - Use event properties to handle different states
   - Maintain type safety throughout

2. **State Access**
   - Use status.when() to handle different status types cleanly
   - Compare old and new states for changes
   - Keep transformations focused and clear

3. **Clear Dependencies**
   - Keep relay chains simple and direct
   - Avoid circular dependencies
   - Document the data flow

4. **Error Handling**
   - Handle errors in the transformer
   - Log errors with context
   - Clean up resources properly

## Common Anti-Patterns to Avoid

1. **Multiple Event Types**
```dart
// ❌ Bad: Returning different event types
statusToEventTransformer: (status) {
  if (status is WaitingStatus) {
    return LoadingEvent();  // Different event type!
  }
  return LoadProfileEvent();
}

// ✅ Good: Single event type with properties
statusToEventTransformer: (status) => status.when(
  updating: (state, _, __) => LoadProfileEvent(userId: state.userId),
  waiting: (_, __, ___) => LoadProfileEvent(isLoading: true),
  failure: (_, __, ___) => LoadProfileEvent(userId: null),
  canceling: (_, __, ___) => LoadProfileEvent(userId: null),
);
```

2. **Ignoring Old State**
```dart
// ❌ Bad: Not comparing state changes
statusToEventTransformer: (status) => LoadProfileEvent(
  userId: status.state.userId
);

// ✅ Good: Checking state transitions
statusToEventTransformer: (status) => status.when(
  updating: (state, oldState, _) {
    if (state.isAuthenticated && !oldState.isAuthenticated) {
      return LoadProfileEvent(userId: state.userId);
    }
    return LoadProfileEvent(userId: null);
  },
  waiting: (_, __, ___) => LoadProfileEvent(isLoading: true),
  failure: (_, __, ___) => LoadProfileEvent(userId: null),
  canceling: (_, __, ___) => LoadProfileEvent(userId: null),
);
```

3. **Missing Status Types**
```dart
// ❌ Bad: Not handling all status types
statusToEventTransformer: (status) => status.when(
  updating: (state, _, __) => LoadProfileEvent(userId: state.userId),
  waiting: (_, __, ___) => LoadProfileEvent(isLoading: true),
  // Missing failure and canceling!
);

// ✅ Good: Handling all status types
statusToEventTransformer: (status) => status.when(
  updating: (state, _, __) => LoadProfileEvent(userId: state.userId),
  waiting: (_, __, ___) => LoadProfileEvent(isLoading: true),
  failure: (_, __, ___) => LoadProfileEvent(userId: null),
  canceling: (_, __, ___) => LoadProfileEvent(userId: null),
);
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
  
  test('transforms auth state to profile event', () async {
    // Given
    const userId = '123';
    
    // When
    authBloc.send(LoginEvent(userId: userId));
    
    // Then
    await expectLater(
      profileBloc.stream,
      emitsInOrder([
        isA<StreamStatus>().having(
          (s) => s.state,
          'loads profile for user',
          isA<ProfileState>().having(
            (s) => s.profile?.userId,
            'has correct userId',
            equals(userId)
          )
        ),
      ])
    );
  });
}
```

## Next Steps

- Learn about [State Management](state-management.md) 
- Explore [Testing Patterns](../testing/testing-relay-use-cases.md)