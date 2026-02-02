# juice_storage

[![pub package](https://img.shields.io/pub/v/juice_storage.svg)](https://pub.dev/packages/juice_storage)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Local storage, caching, and secure storage for the [Juice](https://pub.dev/packages/juice) framework.

## Features

- **Multiple Backends**: Unified API for Hive, SharedPreferences, SQLite, and flutter_secure_storage
- **TTL Caching**: Automatic cache expiration with configurable TTL
- **Background Cleanup**: Optional background task for proactive cache eviction
- **Secure Storage**: Encrypted storage for sensitive data (tokens, credentials)
- **Event-Driven**: Full BLoC pattern integration with helper methods for convenience
- **Lazy Loading**: Support for lazy Hive box initialization

## Platform Support

| Backend | iOS | Android | macOS | Windows | Linux | Web |
|---------|-----|---------|-------|---------|-------|-----|
| **Hive** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **SharedPreferences** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **SQLite** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Secure Storage** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |

**Notes:**
- **SQLite**: Web is not supported by `sqflite`. For web, consider using Hive or SharedPreferences.
- **Secure Storage**: Web support is limited and uses `sessionStorage`/`localStorage` which is not truly secure. For sensitive data on web, consider server-side storage.

## Installation

```yaml
dependencies:
  juice: ^1.3.0
  juice_storage: ^1.0.0
```

## Usage

### Basic Setup

```dart
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

// Register the bloc (typically in main.dart)
BlocScope.register<StorageBloc>(
  () => StorageBloc(
    config: StorageConfig(
      prefsKeyPrefix: 'myapp_',
      hiveBoxesToOpen: ['cache', 'settings'],
      sqliteDatabaseName: 'myapp.db',
      enableBackgroundCleanup: true,
    ),
  ),
  lifecycle: BlocLifecycle.permanent,
);

// Initialize storage
final storage = BlocScope.get<StorageBloc>();
await storage.initialize();
```

### Hive Storage

```dart
// Write with TTL
await storage.hiveWrite('cache', 'user_data', userData, ttl: Duration(hours: 1));

// Read
final data = await storage.hiveRead<UserData>('cache', 'user_data');

// Delete
await storage.hiveDelete('cache', 'user_data');
```

### SharedPreferences

```dart
// Write with optional TTL
await storage.prefsWrite('theme', 'dark', ttl: Duration(days: 30));

// Read
final theme = await storage.prefsRead<String>('theme');

// Delete
await storage.prefsDelete('theme');
```

### SQLite

```dart
// Raw SQL
await storage.sqliteRaw('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)');

// Insert
final rowId = await storage.sqliteInsert('users', {'name': 'Alice'});

// Query
final rows = await storage.sqliteQuery('SELECT * FROM users WHERE id = ?', [1]);

// Update
final affected = await storage.sqliteUpdate('users', {'name': 'Bob'}, where: 'id = ?', whereArgs: [1]);

// Delete
await storage.sqliteDelete('users', where: 'id = ?', whereArgs: [1]);
```

### Secure Storage

```dart
// Store sensitive data (no TTL - secure storage is permanent)
await storage.secureWrite('auth_token', token);

// Read sensitive data
final token = await storage.secureRead('auth_token');

// Delete
await storage.secureDelete('auth_token');
```

### Cache Cleanup

```dart
// Manual cleanup of expired entries
final removedCount = await storage.cleanupExpiredCache();

// Or enable automatic background cleanup in config:
StorageConfig(
  enableBackgroundCleanup: true,
  cacheCleanupInterval: Duration(minutes: 5),
)
```

## Rebuild Groups

Use these groups for targeted widget rebuilds:

| Group | Description |
|-------|-------------|
| `storage:init` | Initialization status |
| `storage:hive:{boxName}` | Per-box changes |
| `storage:prefs` | SharedPreferences changes |
| `storage:sqlite:{tableName}` | Per-table changes |
| `storage:secure` | Secure storage changes |
| `storage:cache` | Cache metadata changes |

```dart
class MyWidget extends StatelessJuiceWidget<StorageBloc> {
  MyWidget() : super(groups: const {'storage:prefs'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Rebuilds only when prefs change
  }
}
```

## Documentation

See the [full documentation](https://kehmka.github.io/juice/) for more details.

## License

MIT License - see [LICENSE](LICENSE) for details.
