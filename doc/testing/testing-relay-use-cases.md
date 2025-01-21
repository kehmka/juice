# Testing Relay Use Cases

This guide covers comprehensive testing patterns for relay use cases, ensuring that bloc-to-bloc communication works correctly and reliably.

## Test Setup

First, let's look at proper test setup for relay testing:

```dart
void main() {
  late AuthBloc authBloc;
  late ProfileBloc profileBloc;
  late MockAuthService authService;
  late MockProfileService profileService;
  
  setUp(() {
    // Initialize mocks
    authService = MockAuthService();
    profileService = MockProfileService();
    
    // Initialize blocs with mocks
    authBloc = AuthBloc(authService);
    profileBloc = ProfileBloc(profileService);
  });
  
  tearDown(() async {
    // Clean up in reverse order of creation
    await profileBloc.close();
    await authBloc.close();
  });
}
```

## Basic Event Flow Tests

Test the basic relay functionality:

```dart
test('loads profile when user authenticates', () async {
  // Arrange
  final user = User(id: '123', name: 'Test User');
  when(authService.login()).thenAnswer((_) async => user);
  when(profileService.loadProfile(user.id))
      .thenAnswer((_) async => UserProfile(/*...*/));
      
  // Act
  authBloc.send(LoginEvent(username: 'test', password: 'test'));
  
  // Assert - verify the sequence of states
  await expectLater(
    profileBloc.stream,
    emitsInOrder([
      isA<StreamStatus>().having((s) => s is WaitingStatus, 'is waiting', true),
      isA<StreamStatus>().having(
        (s) => s.state.profile?.userId,
        'has user id',
        equals('123')
      ),
    ]),
  );
});
```

## Testing Status Transformations

Test how different StreamStatus types are handled:

```dart
group('status transformations', () {
  test('handles waiting status correctly', () async {
    // Simulate auth bloc emitting waiting status
    authBloc.send(LoginEvent());
    
    await expectLater(
      profileBloc.stream,
      emits(isA<StreamStatus>()
        .having((s) => s is WaitingStatus, 'is waiting', true)
      ),
    );
  });
  
  test('handles error status correctly', () async {
    // Simulate auth error
    when(authService.login()).thenThrow(Exception('Auth failed'));
    authBloc.send(LoginEvent());
    
    await expectLater(
      profileBloc.stream,
      emits(isA<StreamStatus>()
        .having((s) => s.state.profile, 'profile cleared', isNull)
      ),
    );
  });
  
  test('handles cancellation status correctly', () async {
    // Setup a cancellable operation
    final operation = authBloc.sendCancellable(LoginEvent());
    operation.cancel();
    
    await expectLater(
      profileBloc.stream,
      emits(isA<StreamStatus>()
        .having((s) => s.state.profile, 'profile cleared', isNull)
      ),
    );
  });
});
```

## State Change Tests

Test different state transition scenarios:

```dart
group('state transitions', () {
  test('loads profile on initial authentication', () async {
    // Test first-time login
    authBloc.send(LoginEvent());
    
    await expectLater(
      profileBloc.stream,
      emitsInOrder([
        isA<StreamStatus>().having((s) => s is WaitingStatus, 'waiting', true),
        isA<StreamStatus>().having(
          (s) => s.state.profile,
          'profile loaded',
          isNotNull
        ),
      ]),
    );
  });
  
  test('clears profile on logout', () async {
    // Setup: authenticated state
    await authBloc.send(LoginEvent());
    await untilDone(authBloc.stream);
    
    // Test logout
    authBloc.send(LogoutEvent());
    
    await expectLater(
      profileBloc.stream,
      emits(isA<StreamStatus>()
        .having((s) => s.state.profile, 'profile cleared', isNull)
      ),
    );
  });
  
  test('handles repeated auth state changes', () async {
    // Login -> Logout -> Login sequence
    await authBloc.send(LoginEvent());
    await untilDone(authBloc.stream);
    await authBloc.send(LogoutEvent());
    await untilDone(authBloc.stream);
    await authBloc.send(LoginEvent());
    
    await expectLater(
      profileBloc.stream,
      emitsThrough(isA<StreamStatus>()
        .having((s) => s.state.profile, 'profile reloaded', isNotNull)
      ),
    );
  });
});
```

## Error Handling Tests

Test error scenarios thoroughly:

```dart
group('error handling', () {
  test('handles source bloc errors', () async {
    // Simulate error in source bloc
    when(authService.login()).thenThrow(Exception('Network error'));
    authBloc.send(LoginEvent());
    
    await expectLater(
      profileBloc.stream,
      emits(isA<StreamStatus>()
        .having((s) => s is FailureStatus, 'is failure', true)
      ),
    );
  });
  
  test('handles transformer errors', () async {
    // Setup bad state that causes transformer error
    authBloc.send(CorruptStateEvent());
    
    await expectLater(
      profileBloc.stream,
      emits(isA<StreamStatus>()
        .having((s) => s is FailureStatus, 'is failure', true)
      ),
    );
  });
  
  test('handles destination bloc errors', () async {
    // Setup: make profile service fail
    when(profileService.loadProfile(any))
        .thenThrow(Exception('Profile load failed'));
    
    authBloc.send(LoginEvent());
    
    await expectLater(
      profileBloc.stream,
      emitsInOrder([
        isA<StreamStatus>().having((s) => s is WaitingStatus, 'waiting', true),
        isA<StreamStatus>().having((s) => s is FailureStatus, 'failed', true),
      ]),
    );
  });
});
```

## Resource Cleanup Tests

Verify proper cleanup of resources:

```dart
group('resource cleanup', () {
  test('cleans up when source bloc closes', () async {
    // Setup relay
    await authBloc.send(LoginEvent());
    await untilDone(authBloc.stream);
    
    // Close source bloc
    await authBloc.close();
    
    // Verify no more events processed
    authBloc.send(UpdateEvent());
    await expectLater(
      profileBloc.stream,
      neverEmits(anything),
    );
  });
  
  test('cleans up when destination bloc closes', () async {
    await authBloc.send(LoginEvent());
    await untilDone(authBloc.stream);
    
    // Close destination bloc
    await profileBloc.close();
    
    // Verify no resource leaks
    expect(profileBloc.isClosed, isTrue);
    // Add more specific resource checks
  });
});
```

## Integration Tests

Test complete flows:

```dart
group('integration tests', () {
  test('complete auth flow with profile updates', () async {
    // Login
    await authBloc.send(LoginEvent(username: 'test', password: 'test'));
    await untilDone(authBloc.stream);
    
    // Update profile
    await profileBloc.send(UpdateProfileEvent(name: 'New Name'));
    await untilDone(profileBloc.stream);
    
    // Logout
    await authBloc.send(LogoutEvent());
    
    // Verify final states
    expect(authBloc.state.isAuthenticated, isFalse);
    expect(profileBloc.state.profile, isNull);
  });
  
  test('multiple user switch flow', () async {
    // First user login
    await authBloc.send(LoginEvent(username: 'user1'));
    await untilDone(authBloc.stream);
    
    final user1Profile = profileBloc.state.profile;
    
    // Switch to second user
    await authBloc.send(LogoutEvent());
    await authBloc.send(LoginEvent(username: 'user2'));
    await untilDone(authBloc.stream);
    
    final user2Profile = profileBloc.state.profile;
    
    // Verify profiles were different
    expect(user1Profile?.userId, isNot(equals(user2Profile?.userId)));
  });
});
```

## Testing Utilities

Useful helpers for relay testing:

```dart
/// Waits for a stream to complete its current operations
Future<void> untilDone<T>(Stream<T> stream) {
  final completer = Completer<void>();
  late StreamSubscription subscription;
  
  subscription = stream.listen(
    null,
    onError: completer.completeError,
    onDone: () {
      subscription.cancel();
      completer.complete();
    },
  );
  
  return completer.future;
}

/// Custom matcher for StreamStatus types
class IsStreamStatusType extends Matcher {
  final Type statusType;
  
  const IsStreamStatusType(this.statusType);
  
  @override
  bool matches(item, Map matchState) {
    return item is StreamStatus && item.runtimeType == statusType;
  }
  
  @override
  Description describe(Description description) =>
      description.add('is a $statusType');
}
```

## Best Practices

1. **Test Setup**
   - Initialize mocks in setUp
   - Clean up resources in tearDown
   - Use fresh instances for each test

2. **State Verification**
   - Test all StreamStatus types
   - Verify state transitions
   - Check cleanup and disposal

3. **Error Handling**
   - Test error scenarios thoroughly
   - Verify error recovery
   - Check cleanup after errors

4. **Integration Testing**
   - Test complete flows
   - Verify state consistency
   - Check cross-bloc interactions

## Common Testing Pitfalls

1. **Not Testing All Status Types**
```dart
// ❌ Bad: Missing status types
test('relay test', () async {
  authBloc.send(LoginEvent());
  await expectLater(
    profileBloc.stream,
    emits(anything),  // Too vague!
  );
});

// ✅ Good: Test all status types
test('relay test', () async {
  authBloc.send(LoginEvent());
  await expectLater(
    profileBloc.stream,
    emitsInOrder([
      isA<WaitingStatus>(),
      isA<UpdatingStatus>(),
      // Test specific state properties too
    ]),
  );
});
```

2. **Resource Leaks**
```dart
// ❌ Bad: No cleanup
final subscription = bloc.stream.listen((_) {});
test('some test', () async {
  // Test never cleans up subscription
});

// ✅ Good: Proper cleanup
late StreamSubscription subscription;
setUp(() {
  subscription = bloc.stream.listen((_) {});
});
tearDown(() async {
  await subscription.cancel();
});
```

3. **Race Conditions**
```dart
// ❌ Bad: Potential race condition
test('state changes', () async {
  authBloc.send(LoginEvent());
  expect(profileBloc.state.isLoading, isTrue);  // May fail!
});

// ✅ Good: Wait for status
test('state changes', () async {
  authBloc.send(LoginEvent());
  await expectLater(
    profileBloc.stream,
    emits(isA<StreamStatus>()
      .having((s) => s is WaitingStatus, 'is loading', isTrue)
    ),
  );
});
```

