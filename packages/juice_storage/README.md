# juice_storage

Local storage, caching, and secure storage for the [Juice](https://pub.dev/packages/juice) framework.

## Features

- **Multiple Backends**: Unified API for Hive, SharedPreferences, SQLite, and flutter_secure_storage
- **TTL Caching**: Automatic cache expiration with configurable TTL
- **Secure Storage**: Encrypted storage for sensitive data (tokens, credentials)
- **Event-Driven**: Full BLoC pattern integration with helper methods for convenience
- **Lazy Loading**: Support for lazy Hive box initialization

## Installation

```yaml
dependencies:
  juice: ^1.1.2
  juice_storage: ^0.1.0
```

## Usage

### Basic Setup

```dart
// Register the bloc
JuiceProvider.register<StorageBloc>(() => StorageBloc());

// Get the bloc
final storage = JuiceProvider.of<StorageBloc>(context);
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
// Write
await storage.prefsWrite('theme', 'dark');

// Read
final theme = await storage.prefsRead<String>('theme');
```

### Secure Storage

```dart
// Store sensitive data
await storage.secureWrite('auth_token', token);

// Read sensitive data
final token = await storage.secureRead('auth_token');

// Delete
await storage.secureDelete('auth_token');
```

## Rebuild Groups

- `storage:init` - Initialization status
- `storage:hive:{boxName}` - Per-box changes
- `storage:prefs` - SharedPreferences changes
- `storage:secure` - Secure storage changes
- `storage:cache` - Cache metadata changes

## Documentation

See the [full documentation](https://kehmka.github.io/juice/) for more details.
