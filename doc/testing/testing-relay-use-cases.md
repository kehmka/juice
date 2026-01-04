# Testing State and Status Relays

This guide covers comprehensive testing patterns for `StateRelay` and `StatusRelay`, ensuring that bloc-to-bloc communication works correctly and reliably.

## Test Setup

First, let's create proper test infrastructure:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// Test resolver for dependency injection
class TestResolver implements BlocDependencyResolver {
  final Map<Type, JuiceBloc> blocs;

  TestResolver(this.blocs);

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    final bloc = blocs[T];
    if (bloc == null) {
      throw StateError('Bloc $T not registered');
    }
    return bloc as T;
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    return BlocLease<T>(resolve<T>(), () {});
  }

  @override
  Future<void> disposeAll() async {
    for (final bloc in blocs.values) {
      await bloc.close();
    }
  }
}

void main() {
  late AuthBloc authBloc;
  late ProfileBloc profileBloc;
  late TestResolver resolver;

  setUp(() {
    authBloc = AuthBloc();
    profileBloc = ProfileBloc();
    resolver = TestResolver({
      AuthBloc: authBloc,
      ProfileBloc: profileBloc,
    });
  });

  tearDown(() async {
    await resolver.disposeAll();
  });
}
```

## Testing StateRelay

### Basic State Transformation

```dart
test('StateRelay transforms and forwards state changes', () async {
  final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
    toEvent: (state) => LoadProfileEvent(userId: state.userId!),
    when: (state) => state.isAuthenticated,
    resolver: resolver,
  );

  // Wait for async initialization
  await Future.delayed(const Duration(milliseconds: 100));

  // Trigger state change
  await authBloc.send(LoginEvent(userId: '123'));
  await Future.delayed(const Duration(milliseconds: 100));

  // Verify destination bloc received the event
  expect(profileBloc.state.profile?.userId, equals('123'));

  await relay.close();
});
```

### Testing the `when` Predicate

```dart
test('StateRelay filters with when predicate', () async {
  final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
    toEvent: (state) => LoadProfileEvent(userId: state.userId!),
    when: (state) => state.isAuthenticated && state.userId != null,
    resolver: resolver,
  );

  await Future.delayed(const Duration(milliseconds: 100));

  // Send event that doesn't pass filter (not authenticated)
  await authBloc.send(UpdateUserEvent(userId: '123', authenticated: false));
  await Future.delayed(const Duration(milliseconds: 100));

  // Profile should not be loaded
  expect(profileBloc.state.profile, isNull);

  // Now authenticate
  await authBloc.send(LoginEvent(userId: '123'));
  await Future.delayed(const Duration(milliseconds: 100));

  // Profile should now be loaded
  expect(profileBloc.state.profile?.userId, equals('123'));

  await relay.close();
});
```

### Testing Relay Lifecycle

```dart
group('StateRelay lifecycle', () {
  test('closes cleanly', () async {
    final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: state.userId!),
      resolver: resolver,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    // Close should not throw
    await relay.close();
    expect(relay.isClosed, isTrue);

    // Multiple close calls should be safe
    await relay.close();
  });

  test('stops relaying after close', () async {
    final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: state.userId!),
      when: (state) => state.isAuthenticated,
      resolver: resolver,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    // Initial relay works
    await authBloc.send(LoginEvent(userId: '123'));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(profileBloc.state.profile?.userId, equals('123'));

    // Close relay
    await relay.close();

    // Clear profile state
    await profileBloc.send(ClearProfileEvent());
    await Future.delayed(const Duration(milliseconds: 50));

    // Send another auth event - should not relay
    await authBloc.send(LoginEvent(userId: '456'));
    await Future.delayed(const Duration(milliseconds: 100));

    // Profile should still be cleared
    expect(profileBloc.state.profile, isNull);
  });
});
```

### Testing Error Handling

```dart
test('StateRelay handles transformer errors without closing', () async {
  int callCount = 0;

  final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
    toEvent: (state) {
      callCount++;
      if (callCount == 2) {
        throw Exception('Transformer error');
      }
      return LoadProfileEvent(userId: state.userId!);
    },
    resolver: resolver,
  );

  await Future.delayed(const Duration(milliseconds: 100));

  // First event works
  await authBloc.send(LoginEvent(userId: '123'));
  await Future.delayed(const Duration(milliseconds: 100));
  expect(profileBloc.state.profile?.userId, equals('123'));

  // Second event throws - relay should continue
  await authBloc.send(LoginEvent(userId: '456'));
  await Future.delayed(const Duration(milliseconds: 100));

  // Relay should still be active
  expect(relay.isClosed, isFalse);

  // Third event should work
  await authBloc.send(LoginEvent(userId: '789'));
  await Future.delayed(const Duration(milliseconds: 100));
  expect(profileBloc.state.profile?.userId, equals('789'));

  await relay.close();
});
```

## Testing StatusRelay

### Basic Status Transformation

```dart
test('StatusRelay transforms and forwards StreamStatus', () async {
  final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
    toEvent: (status) {
      if (status is UpdatingStatus<AuthState>) {
        return LoadProfileEvent(userId: status.state.userId!);
      }
      return ClearProfileEvent();
    },
    resolver: resolver,
  );

  await Future.delayed(const Duration(milliseconds: 100));

  await authBloc.send(LoginEvent(userId: '123'));
  await Future.delayed(const Duration(milliseconds: 100));

  expect(profileBloc.state.profile?.userId, equals('123'));

  await relay.close();
});
```

### Testing Full Status Handling

```dart
test('StatusRelay handles all status types', () async {
  final receivedEvents = <Type>[];

  final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
    toEvent: (status) => status.when(
      updating: (state, _, __) {
        receivedEvents.add(UpdatingStatus);
        return state.isAuthenticated
            ? LoadProfileEvent(userId: state.userId!)
            : ClearProfileEvent();
      },
      waiting: (_, __, ___) {
        receivedEvents.add(WaitingStatus);
        return ProfileLoadingEvent();
      },
      failure: (_, __, ___) {
        receivedEvents.add(FailureStatus);
        return ClearProfileEvent();
      },
      canceling: (_, __, ___) {
        receivedEvents.add(CancelingStatus);
        return ClearProfileEvent();
      },
    ),
    resolver: resolver,
  );

  await Future.delayed(const Duration(milliseconds: 100));

  // Trigger login which may emit waiting then updating
  await authBloc.send(LoginEvent(userId: '123'));
  await Future.delayed(const Duration(milliseconds: 200));

  // Should have received at least updating status
  expect(receivedEvents, contains(UpdatingStatus));

  await relay.close();
});
```

### Testing Status Filtering

```dart
test('StatusRelay filters with when predicate on status', () async {
  int relayCount = 0;

  final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
    toEvent: (status) {
      relayCount++;
      return LoadProfileEvent(userId: status.state.userId ?? 'default');
    },
    when: (status) => status is UpdatingStatus<AuthState>,
    resolver: resolver,
  );

  await Future.delayed(const Duration(milliseconds: 100));

  await authBloc.send(LoginEvent(userId: '123'));
  await Future.delayed(const Duration(milliseconds: 100));

  // Only updating statuses should trigger relay
  expect(relayCount, greaterThan(0));

  await relay.close();
});
```

## Testing Race Conditions

```dart
group('Race condition handling', () {
  test('close during initialization does not cause errors', () async {
    final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: state.userId!),
      resolver: resolver,
    );

    // Immediately close before initialization completes
    await relay.close();

    // Wait for any pending microtasks
    await Future.delayed(const Duration(milliseconds: 100));

    // Should not throw
    expect(relay.isClosed, isTrue);
  });

  test('multiple relays on same source work independently', () async {
    final destBloc1 = ProfileBloc();
    final destBloc2 = ProfileBloc();

    final resolver1 = TestResolver({
      AuthBloc: authBloc,
      ProfileBloc: destBloc1,
    });
    final resolver2 = TestResolver({
      AuthBloc: authBloc,
      ProfileBloc: destBloc2,
    });

    final relay1 = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: 'relay1-${state.userId}'),
      resolver: resolver1,
    );

    final relay2 = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: 'relay2-${state.userId}'),
      resolver: resolver2,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    await authBloc.send(LoginEvent(userId: '123'));
    await Future.delayed(const Duration(milliseconds: 100));

    // Both should have received events
    expect(destBloc1.state.profile?.userId, equals('relay1-123'));
    expect(destBloc2.state.profile?.userId, equals('relay2-123'));

    // Close one relay
    await relay1.close();

    await authBloc.send(LoginEvent(userId: '456'));
    await Future.delayed(const Duration(milliseconds: 100));

    // Only relay2 should update
    expect(destBloc1.state.profile?.userId, equals('relay1-123'));
    expect(destBloc2.state.profile?.userId, equals('relay2-456'));

    await relay2.close();
    await destBloc1.close();
    await destBloc2.close();
  });

  test('handles dest bloc close gracefully', () async {
    final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: state.userId!),
      resolver: resolver,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    // Close destination bloc
    await profileBloc.close();

    // Send event to source - relay should detect closed dest
    await authBloc.send(LoginEvent(userId: '123'));
    await Future.delayed(const Duration(milliseconds: 100));

    expect(relay.isClosed, isTrue);
  });

  test('handles source bloc close gracefully', () async {
    final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => LoadProfileEvent(userId: state.userId!),
      resolver: resolver,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    // Close source bloc
    await authBloc.close();
    await Future.delayed(const Duration(milliseconds: 100));

    expect(relay.isClosed, isTrue);
  });
});
```

## Integration Tests

```dart
group('Integration tests', () {
  test('complete auth flow with profile relay', () async {
    final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
      toEvent: (state) => state.isAuthenticated
          ? LoadProfileEvent(userId: state.userId!)
          : ClearProfileEvent(),
      resolver: resolver,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    // Login
    await authBloc.send(LoginEvent(userId: '123'));
    await Future.delayed(const Duration(milliseconds: 100));

    expect(profileBloc.state.profile?.userId, equals('123'));

    // Logout
    await authBloc.send(LogoutEvent());
    await Future.delayed(const Duration(milliseconds: 100));

    expect(profileBloc.state.profile, isNull);

    // Login with different user
    await authBloc.send(LoginEvent(userId: '456'));
    await Future.delayed(const Duration(milliseconds: 100));

    expect(profileBloc.state.profile?.userId, equals('456'));

    await relay.close();
  });
});
```

## Testing Utilities

```dart
/// Waits for a stream to emit a matching value
Future<T> waitFor<T>(
  Stream<T> stream,
  bool Function(T) predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final completer = Completer<T>();

  final subscription = stream.listen((value) {
    if (predicate(value)) {
      completer.complete(value);
    }
  });

  try {
    return await completer.future.timeout(timeout);
  } finally {
    await subscription.cancel();
  }
}

/// Collects all values emitted within a duration
Future<List<T>> collectFor<T>(
  Stream<T> stream,
  Duration duration,
) async {
  final values = <T>[];
  final subscription = stream.listen(values.add);

  await Future.delayed(duration);
  await subscription.cancel();

  return values;
}
```

## Best Practices

### 1. Test Setup
- Initialize mocks and resolvers in `setUp`
- Clean up resources in `tearDown`
- Use fresh instances for each test

### 2. Timing
- Allow time for async initialization (`Future.delayed`)
- Don't use exact timing assertions
- Use stream matchers when possible

### 3. Isolation
- Test relays independently
- Mock external dependencies
- Use test resolvers instead of BlocScope

### 4. Coverage
- Test all status types for StatusRelay
- Test the `when` predicate
- Test error scenarios
- Test cleanup and disposal

### 5. Common Pitfalls to Avoid

```dart
// ❌ Bad: Not waiting for initialization
final relay = StateRelay<...>(...);
authBloc.send(LoginEvent());  // May not work!

// ✅ Good: Wait for initialization
final relay = StateRelay<...>(...);
await Future.delayed(Duration(milliseconds: 100));
authBloc.send(LoginEvent());

// ❌ Bad: Not cleaning up
test('my test', () async {
  final relay = StateRelay<...>(...);
  // Test code...
  // Relay not closed!
});

// ✅ Good: Always clean up
test('my test', () async {
  final relay = StateRelay<...>(...);
  try {
    // Test code...
  } finally {
    await relay.close();
  }
});
```

## Migration from RelayUseCaseBuilder Tests

If you have existing tests for `RelayUseCaseBuilder`, here's how to migrate:

```dart
// Before (deprecated):
test('relay test', () async {
  final relay = RelayUseCaseBuilder<AuthBloc, ProfileBloc, AuthState>(
    typeOfEvent: LoadProfileEvent,
    useCaseGenerator: () => LoadProfileUseCase(),
    statusToEventTransformer: (status) => LoadProfileEvent(
      userId: status.state.userId,
    ),
    resolver: resolver,
  );
  // ...
});

// After - StateRelay:
test('relay test', () async {
  final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
    toEvent: (state) => LoadProfileEvent(userId: state.userId!),
    when: (state) => state.isAuthenticated,
    resolver: resolver,
  );
  // ...
});
```

Key differences:
- Replace `statusToEventTransformer` with `toEvent`
- Add `when` for filtering instead of checking in transformer
- Remove `typeOfEvent` and `useCaseGenerator`
- Test assertions remain the same
