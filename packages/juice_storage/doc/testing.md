# Testing with juice_storage

This guide covers strategies for testing code that uses `StorageBloc`.

## Testing Strategies

There are three main approaches to testing storage-dependent code:

1. **Mock the StorageBloc** - Best for unit tests
2. **Use in-memory adapters** - Best for integration tests
3. **Seed test data** - Best for widget/feature tests

## Mocking StorageBloc

For unit tests, mock the storage bloc using `mocktail`:

```dart
import 'package:mocktail/mocktail.dart';
import 'package:juice_storage/juice_storage.dart';

class MockStorageBloc extends Mock implements StorageBloc {}

void main() {
  late MockStorageBloc mockStorage;

  setUp(() {
    mockStorage = MockStorageBloc();
  });

  test('loads user profile from cache', () async {
    // Arrange
    when(() => mockStorage.hiveRead<String>('cache', 'user_profile'))
        .thenAnswer((_) async => '{"name": "Alice"}');

    // Act
    final service = UserService(storage: mockStorage);
    final profile = await service.getProfile();

    // Assert
    expect(profile.name, 'Alice');
    verify(() => mockStorage.hiveRead<String>('cache', 'user_profile')).called(1);
  });

  test('falls back to API when cache miss', () async {
    // Arrange
    when(() => mockStorage.hiveRead<String>('cache', 'user_profile'))
        .thenAnswer((_) async => null);
    when(() => mockStorage.hiveWrite(any(), any(), any(), ttl: any(named: 'ttl')))
        .thenAnswer((_) async {});

    // Act
    final service = UserService(storage: mockStorage);
    final profile = await service.getProfile();

    // Assert
    verify(() => mockStorage.hiveWrite('cache', 'user_profile', any(), ttl: any(named: 'ttl'))).called(1);
  });
}
```

## Testing TTL Behavior

For TTL tests, you can inject a clock to control time:

```dart
test('returns null for expired cache', () async {
  final storage = StorageBloc(
    config: StorageConfig(hiveBoxesToOpen: ['cache']),
  );

  // Inject test clock
  var testTime = DateTime(2025, 1, 1, 12, 0);
  storage.clock = () => testTime;

  await storage.initialize();

  // Write with 1 hour TTL
  await storage.hiveWrite('cache', 'data', 'test', ttl: Duration(hours: 1));

  // Fast forward 2 hours
  testTime = DateTime(2025, 1, 1, 14, 0);

  // Read should return null (expired)
  final result = await storage.hiveRead<String>('cache', 'data');
  expect(result, isNull);

  await storage.close();
});
```

## Widget Testing

For widget tests, register a mock or seeded storage:

```dart
testWidgets('displays cached theme', (tester) async {
  final mockStorage = MockStorageBloc();

  // Stub the state
  when(() => mockStorage.state).thenReturn(StorageState(
    isInitialized: true,
    backendStatus: StorageBackendStatus.allReady(),
  ));

  when(() => mockStorage.prefsRead<String>('theme'))
      .thenAnswer((_) async => 'dark');

  // Register mock
  BlocScope.register<StorageBloc>(
    () => mockStorage,
    lifecycle: BlocLifecycle.permanent,
  );

  await tester.pumpWidget(MyApp());
  await tester.pumpAndSettle();

  expect(find.text('Dark Mode'), findsOneWidget);
});
```

## Integration Testing

For integration tests, use real storage with test isolation:

```dart
void main() {
  late StorageBloc storage;

  setUp(() async {
    // Use unique database names for test isolation
    storage = StorageBloc(
      config: StorageConfig(
        prefsKeyPrefix: 'test_${DateTime.now().millisecondsSinceEpoch}_',
        hiveBoxesToOpen: ['test_cache'],
        sqliteDatabaseName: 'test_${DateTime.now().millisecondsSinceEpoch}.db',
      ),
    );
    await storage.initialize();
  });

  tearDown(() async {
    // Clean up test data
    await storage.clearAll(ClearAllOptions(
      clearHive: true,
      clearPrefs: true,
      clearSqlite: true,
      sqliteDropTables: true,
    ));
    await storage.close();
  });

  test('write and read cycle', () async {
    await storage.prefsWrite('test_key', 'test_value');
    final result = await storage.prefsRead<String>('test_key');
    expect(result, 'test_value');
  });
}
```

## Testing Rebuild Groups

Verify that correct rebuild groups are emitted:

```dart
test('emits prefs group on write', () async {
  final storage = StorageBloc(config: StorageConfig());
  await storage.initialize();

  // Listen for status updates
  final groups = <Set<String>>[];
  storage.stream.listen((status) {
    if (status.groupsToRebuild.isNotEmpty) {
      groups.add(status.groupsToRebuild);
    }
  });

  await storage.prefsWrite('key', 'value');
  await Future.delayed(Duration(milliseconds: 50));

  expect(groups, contains(contains('storage:prefs')));
});
```

## Testing Error Handling

Test error scenarios:

```dart
test('handles storage error gracefully', () async {
  final mockStorage = MockStorageBloc();

  when(() => mockStorage.secureRead('token'))
      .thenThrow(StorageException(
        'Secure storage unavailable',
        type: StorageErrorType.backendNotAvailable,
      ));

  final service = AuthService(storage: mockStorage);

  // Should handle error, not crash
  final token = await service.getToken();
  expect(token, isNull);
});
```

## Test Helpers

Create test utilities for common patterns:

```dart
// test/helpers/storage_test_helpers.dart
class StorageTestHelpers {
  static MockStorageBloc createMockWithSeeds({
    Map<String, dynamic>? prefs,
    Map<String, Map<String, dynamic>>? hive,
    Map<String, String>? secure,
  }) {
    final mock = MockStorageBloc();

    when(() => mock.state).thenReturn(StorageState(isInitialized: true));

    // Seed prefs
    prefs?.forEach((key, value) {
      when(() => mock.prefsRead<dynamic>(key)).thenAnswer((_) async => value);
    });

    // Seed hive
    hive?.forEach((box, entries) {
      entries.forEach((key, value) {
        when(() => mock.hiveRead<dynamic>(box, key)).thenAnswer((_) async => value);
      });
    });

    // Seed secure
    secure?.forEach((key, value) {
      when(() => mock.secureRead(key)).thenAnswer((_) async => value);
    });

    return mock;
  }
}

// Usage in tests
final storage = StorageTestHelpers.createMockWithSeeds(
  prefs: {'theme': 'dark', 'locale': 'en'},
  secure: {'auth_token': 'test_token'},
);
```

## Best Practices

### 1. Isolate Tests

Use unique prefixes/database names per test to avoid interference:

```dart
StorageConfig(
  prefsKeyPrefix: 'test_${testName}_',
  sqliteDatabaseName: 'test_${testName}.db',
)
```

### 2. Clean Up After Tests

Always clean up in `tearDown`:

```dart
tearDown(() async {
  await storage.clearAll(ClearAllOptions(
    clearHive: true,
    clearPrefs: true,
    clearSecure: true,
    clearSqlite: true,
  ));
});
```

### 3. Test Edge Cases

- Expired TTL behavior
- Missing data (null returns)
- Backend unavailability
- Concurrent operations

### 4. Use Real Storage Sparingly

Mock for unit tests, use real storage only for integration tests:

```dart
// Unit test: Mock
test('service handles cache miss', () {
  final mock = MockStorageBloc();
  // ...
});

// Integration test: Real storage
test('end-to-end write and read', () {
  final storage = StorageBloc(...);
  // ...
});
```

### 5. Test Reactive Updates

Verify widgets rebuild on storage changes:

```dart
testWidgets('rebuilds on theme change', (tester) async {
  // Initial theme
  when(() => mockStorage.prefsRead<String>('theme'))
      .thenAnswer((_) async => 'light');

  await tester.pumpWidget(ThemeWidget());
  expect(find.text('Light'), findsOneWidget);

  // Change theme
  when(() => mockStorage.prefsRead<String>('theme'))
      .thenAnswer((_) async => 'dark');

  // Simulate rebuild group emission
  // ...

  await tester.pumpAndSettle();
  expect(find.text('Dark'), findsOneWidget);
});
```
