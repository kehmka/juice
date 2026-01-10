# Getting Started with juice_storage

This guide walks you through setting up and using `juice_storage` in your Flutter app.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  juice: ^1.1.3
  juice_storage: ^0.8.0
```

## Basic Setup

### 1. Register the StorageBloc

In your `main.dart`, register the `StorageBloc` as a permanent bloc:

```dart
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register StorageBloc as permanent (lives for app lifetime)
  BlocScope.register<StorageBloc>(
    () => StorageBloc(
      config: StorageConfig(
        prefsKeyPrefix: 'myapp_',
        hiveBoxesToOpen: ['cache', 'settings'],
        sqliteDatabaseName: 'myapp.db',
      ),
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  // Initialize storage before running app
  final storage = BlocScope.get<StorageBloc>();
  await storage.initialize();

  runApp(MyApp());
}
```

### 2. Use Storage in Your App

Access the bloc from anywhere:

```dart
final storage = BlocScope.get<StorageBloc>();

// Write data
await storage.prefsWrite('theme', 'dark');
await storage.hiveWrite('cache', 'user', userData);
await storage.secureWrite('token', authToken);

// Read data
final theme = await storage.prefsRead<String>('theme');
final user = await storage.hiveRead<UserData>('cache', 'user');
final token = await storage.secureRead('token');
```

## Quick Examples

### Store User Preferences

```dart
// Save preference
await storage.prefsWrite('notifications_enabled', true);

// Read preference
final enabled = await storage.prefsRead<bool>('notifications_enabled') ?? false;
```

### Cache Data with TTL

```dart
// Cache API response for 1 hour
await storage.hiveWrite(
  'cache',
  'user_profile',
  profileJson,
  ttl: Duration(hours: 1),
);

// Read - returns null if expired
final cached = await storage.hiveRead<String>('cache', 'user_profile');
if (cached == null) {
  // Cache expired or doesn't exist, fetch fresh data
}
```

### Store Secure Data

```dart
// Store auth token securely
await storage.secureWrite('auth_token', token);
await storage.secureWrite('refresh_token', refreshToken);

// Read secure data
final authToken = await storage.secureRead('auth_token');

// Clear on logout
await storage.secureDelete('auth_token');
await storage.secureDelete('refresh_token');
```

### Use SQLite for Relational Data

```dart
// Create table
await storage.sqliteRaw('''
  CREATE TABLE IF NOT EXISTS notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT,
    created_at TEXT
  )
''');

// Insert
final noteId = await storage.sqliteInsert('notes', {
  'title': 'My Note',
  'content': 'Note content here',
  'created_at': DateTime.now().toIso8601String(),
});

// Query
final notes = await storage.sqliteQuery('SELECT * FROM notes ORDER BY created_at DESC');
```

## Next Steps

- [Storage Backends](storage-backends.md) - Deep dive into each backend
- [Caching & TTL](caching-and-ttl.md) - TTL configuration and eviction behavior
- [Events Reference](events-reference.md) - Complete event documentation
- [Testing](testing.md) - How to test storage operations
