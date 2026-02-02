# Storage Backends

juice_storage provides a unified API across four storage backends. Each has specific strengths and use cases.

## Backend Comparison

| Backend | Best For | TTL Support | Data Types |
|---------|----------|-------------|------------|
| **SharedPreferences** | Simple settings, flags | Yes | String, int, double, bool, List\<String\> |
| **Hive** | Structured data, offline cache | Yes | Any (with TypeAdapters) |
| **Secure Storage** | Tokens, credentials, secrets | No | String only |
| **SQLite** | Relational data, complex queries | No | SQL types |

---

## SharedPreferences

Simple key-value storage for app settings and preferences.

### When to Use
- User preferences (theme, locale, notifications)
- Feature flags
- Simple cached values
- Onboarding state

### API

```dart
// Write
await storage.prefsWrite('theme', 'dark');
await storage.prefsWrite('volume', 0.8);
await storage.prefsWrite('notifications', true);

// Write with TTL
await storage.prefsWrite('cached_flags', flagsJson, ttl: Duration(hours: 1));

// Read
final theme = await storage.prefsRead<String>('theme');
final volume = await storage.prefsRead<double>('volume');
final notifications = await storage.prefsRead<bool>('notifications') ?? true;

// Delete
await storage.prefsDelete('theme');
```

### Key Prefixing

Keys are automatically prefixed with `prefsKeyPrefix` from config to avoid collisions:

```dart
StorageConfig(prefsKeyPrefix: 'myapp_')

// prefsWrite('theme', 'dark') stores as 'myapp_theme'
// You always use logical keys - the prefix is handled internally
```

### Rebuild Group

`storage:prefs` - Emitted on write/delete operations.

---

## Hive

Structured key-value storage with box organization. Ideal for caching and offline data.

### When to Use
- Cached API responses
- User data models
- Offline-first storage
- Any structured data

### Configuration

Specify boxes to open at initialization:

```dart
StorageConfig(
  hiveBoxesToOpen: ['cache', 'settings', 'user_data'],
)
```

### API

```dart
// Write to a box
await storage.hiveWrite('cache', 'user_profile', profileData);

// Write with TTL
await storage.hiveWrite('cache', 'api_response', responseJson, ttl: Duration(minutes: 30));

// Read from a box
final profile = await storage.hiveRead<Map<String, dynamic>>('cache', 'user_profile');

// Delete
await storage.hiveDelete('cache', 'user_profile');
```

### Custom Type Adapters

For custom objects, register Hive TypeAdapters:

```dart
StorageConfig(
  hiveAdapters: [
    UserAdapter(),
    SettingsAdapter(),
  ],
)
```

### Rebuild Groups

`storage:hive:{boxName}` - Per-box rebuild groups.

```dart
// storage:hive:cache - changes to 'cache' box
// storage:hive:settings - changes to 'settings' box
```

---

## Secure Storage

Encrypted storage for sensitive data. Uses platform-specific secure storage (Keychain on iOS, EncryptedSharedPreferences on Android).

### When to Use
- Authentication tokens
- Refresh tokens
- API keys
- Private keys
- Any sensitive credentials

### API

```dart
// Write (string only)
await storage.secureWrite('auth_token', token);
await storage.secureWrite('refresh_token', refreshToken);

// Read
final token = await storage.secureRead('auth_token');

// Delete
await storage.secureDelete('auth_token');

// Delete all secure data
await storage.secureClearAll();
```

### Important Notes

- **No TTL support** - Secrets require explicit deletion for security
- **String only** - Serialize objects to JSON if needed
- **May be unavailable** - Check `state.backendStatus.secure` for availability

### Platform Configuration

```dart
StorageConfig(
  secureStorageIOS: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
  secureStorageAndroid: AndroidOptions(
    encryptedSharedPreferences: true,
  ),
)
```

### Rebuild Group

`storage:secure` - Emitted on write/delete operations.

---

## SQLite

Relational database for complex data with query capabilities.

### When to Use
- Relational data models
- Complex queries
- Time-series data
- Local analytics/logs
- Data requiring indexes

### Configuration

```dart
StorageConfig(
  sqliteDatabaseName: 'myapp.db',
  sqliteDatabaseVersion: 1,
  sqliteOnCreate: (db, version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT UNIQUE
      )
    ''');
  },
  sqliteOnUpgrade: (db, oldVersion, newVersion) async {
    // Handle migrations
  },
)
```

### API

```dart
// Raw SQL execution
await storage.sqliteRaw('CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, message TEXT)');

// Insert (returns row ID)
final id = await storage.sqliteInsert('users', {
  'name': 'Alice',
  'email': 'alice@example.com',
});

// Query
final users = await storage.sqliteQuery(
  'SELECT * FROM users WHERE name LIKE ?',
  ['%Alice%'],
);

// Update (returns affected rows count)
final affected = await storage.sqliteUpdate(
  'users',
  {'name': 'Bob'},
  where: 'id = ?',
  whereArgs: [1],
);

// Delete (returns deleted rows count)
final deleted = await storage.sqliteDelete(
  'users',
  where: 'id = ?',
  whereArgs: [1],
);
```

### Rebuild Groups

`storage:sqlite:{tableName}` - Per-table rebuild groups for insert/update/delete.

```dart
// storage:sqlite:users - changes to 'users' table
// storage:sqlite:logs - changes to 'logs' table
```

---

## Backend Status

Check backend availability via state:

```dart
final state = storage.state;

if (state.backendStatus.hive == BackendState.ready) {
  // Hive is available
}

if (state.backendStatus.secure == BackendState.error) {
  // Secure storage failed to initialize
  // Show fallback UI or disable secure features
}
```

## Choosing the Right Backend

| Scenario | Recommended Backend |
|----------|---------------------|
| Theme preference | SharedPreferences |
| Auth tokens | Secure Storage |
| Cached API response | Hive with TTL |
| User profile cache | Hive |
| App settings object | Hive |
| Feature flags (short-lived) | SharedPreferences with TTL |
| Search history | SQLite |
| Offline message queue | SQLite |
| Analytics events | SQLite |
