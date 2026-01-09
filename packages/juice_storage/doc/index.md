# juice_storage Documentation

Local storage, caching, and secure storage for the [Juice](https://pub.dev/packages/juice) framework.

## Overview

juice_storage provides a unified, event-driven API for managing local data across multiple storage backends:

- **SharedPreferences** - Simple key-value settings
- **Hive** - Structured data with box organization
- **Secure Storage** - Encrypted storage for secrets
- **SQLite** - Relational database queries

All operations flow through `StorageBloc`, giving you reactive state, rebuild groups, and consistent error handling.

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](getting-started.md) | Installation and basic setup |
| [Storage Backends](storage-backends.md) | Deep dive into each backend |
| [Events Reference](events-reference.md) | Complete event documentation |
| [Caching & TTL](caching-and-ttl.md) | TTL configuration and eviction behavior |
| [Testing](testing.md) | Testing strategies and mocking |

## Quick Start

```dart
// Register StorageBloc
BlocScope.register<StorageBloc>(
  () => StorageBloc(
    config: StorageConfig(
      prefsKeyPrefix: 'myapp_',
      hiveBoxesToOpen: ['cache'],
    ),
  ),
  lifecycle: BlocLifecycle.permanent,
);

// Initialize
final storage = BlocScope.get<StorageBloc>();
await storage.initialize();

// Use storage
await storage.prefsWrite('theme', 'dark');
await storage.hiveWrite('cache', 'user', userData, ttl: Duration(hours: 1));
await storage.secureWrite('token', authToken);
```

## Key Features

### Unified API

One consistent interface across all backends:

```dart
// All backends use similar patterns
await storage.prefsWrite('key', value);
await storage.hiveWrite('box', 'key', value);
await storage.secureWrite('key', value);
```

### TTL Caching

Built-in expiration for cached data:

```dart
await storage.hiveWrite('cache', 'data', value, ttl: Duration(hours: 1));
// Returns null after 1 hour
final data = await storage.hiveRead('cache', 'data');
```

### Reactive State

Rebuild widgets when storage changes:

```dart
class MyWidget extends StatelessJuiceWidget<StorageBloc> {
  MyWidget() : super(groups: const {'storage:prefs'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Rebuilds when prefs change
  }
}
```

### Event-Driven Architecture

Full traceability and testability:

```dart
// Events power everything - helpers are just convenience
storage.send(PrefsWriteEvent(key: 'theme', value: 'dark'));
```

## Package Structure

```
juice_storage/
├── lib/
│   ├── juice_storage.dart      # Public exports
│   └── src/
│       ├── storage_bloc.dart   # Main bloc
│       ├── storage_state.dart  # State model
│       ├── storage_events.dart # Event definitions
│       ├── storage_config.dart # Configuration
│       └── ...
├── doc/                        # Documentation
├── example/                    # Demo app
└── test/                       # Tests
```

## Dependencies

- [juice](https://pub.dev/packages/juice) - Core Juice framework
- [hive](https://pub.dev/packages/hive) - Local NoSQL database
- [shared_preferences](https://pub.dev/packages/shared_preferences) - Key-value storage
- [sqflite](https://pub.dev/packages/sqflite) - SQLite database
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) - Encrypted storage

## License

MIT License - see [LICENSE](../LICENSE) for details.
