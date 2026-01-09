# Events Reference

All storage operations in juice_storage are event-driven. While most developers use the convenient helper methods, understanding the events helps with advanced usage, debugging, and reactive UI patterns.

## Architecture Overview

```
┌─────────────────┐      ┌───────────────┐      ┌─────────────────┐
│  Helper Method  │─────▶│    Event      │─────▶│    Use Case     │
│  prefsWrite()   │      │ PrefsWriteEvent│      │ PrefsWriteUseCase│
└─────────────────┘      └───────────────┘      └─────────────────┘
                                                        │
                                                        ▼
                                                 ┌─────────────┐
                                                 │   Adapter   │
                                                 │ (internal)  │
                                                 └─────────────┘
```

Helper methods are thin wrappers that dispatch events and await results. You can use events directly for advanced control.

---

## Initialization Events

### InitializeStorageEvent

Initializes all configured storage backends.

```dart
// Typically sent automatically at bloc creation
storage.send(InitializeStorageEvent());

// Or await completion
await storage.initialize();
```

**Rebuild Groups:** `storage:init`

**State Changes:**
- `isInitialized` → `true`
- `backendStatus` → status of each backend

---

## SharedPreferences Events

### PrefsReadEvent

Reads a value from SharedPreferences.

```dart
// Via helper (recommended)
final value = await storage.prefsRead<String>('theme');

// Via event directly
storage.send(PrefsReadEvent(key: 'theme'));
```

**Returns:** The stored value or `null` if not found/expired

**Rebuild Groups:** None (unless lazy eviction occurs, then `storage:prefs`, `storage:cache`)

### PrefsWriteEvent

Writes a value to SharedPreferences.

```dart
// Via helper (recommended)
await storage.prefsWrite('theme', 'dark');
await storage.prefsWrite('flags', flagsJson, ttl: Duration(hours: 1));

// Via event directly
storage.send(PrefsWriteEvent(key: 'theme', value: 'dark'));
storage.send(PrefsWriteEvent(key: 'flags', value: flagsJson, ttl: Duration(hours: 1)));
```

**Rebuild Groups:** `storage:prefs`, `storage:cache` (if TTL provided)

### PrefsDeleteEvent

Deletes a value from SharedPreferences.

```dart
// Via helper
await storage.prefsDelete('theme');

// Via event
storage.send(PrefsDeleteEvent(key: 'theme'));
```

**Rebuild Groups:** `storage:prefs`, `storage:cache` (if TTL existed)

---

## Hive Events

### HiveOpenBoxEvent

Opens a Hive box (usually done automatically via config).

```dart
storage.send(HiveOpenBoxEvent(boxName: 'cache', lazy: false));
```

**Rebuild Groups:** `storage:hive:{boxName}`

### HiveReadEvent

Reads a value from a Hive box.

```dart
// Via helper
final data = await storage.hiveRead<UserData>('cache', 'user');

// Via event
storage.send(HiveReadEvent(box: 'cache', key: 'user'));
```

**Returns:** The stored value or `null` if not found/expired

**Rebuild Groups:** None (unless lazy eviction, then `storage:hive:{box}`, `storage:cache`)

### HiveWriteEvent

Writes a value to a Hive box.

```dart
// Via helper
await storage.hiveWrite('cache', 'user', userData);
await storage.hiveWrite('cache', 'temp', data, ttl: Duration(minutes: 30));

// Via event
storage.send(HiveWriteEvent(box: 'cache', key: 'user', value: userData));
```

**Rebuild Groups:** `storage:hive:{box}`, `storage:cache` (if TTL provided)

### HiveDeleteEvent

Deletes a value from a Hive box.

```dart
// Via helper
await storage.hiveDelete('cache', 'user');

// Via event
storage.send(HiveDeleteEvent(box: 'cache', key: 'user'));
```

**Rebuild Groups:** `storage:hive:{box}`, `storage:cache` (if TTL existed)

### HiveCloseBoxEvent

Closes a Hive box.

```dart
storage.send(HiveCloseBoxEvent(boxName: 'cache'));
```

---

## Secure Storage Events

### SecureReadEvent

Reads a value from secure storage.

```dart
// Via helper
final token = await storage.secureRead('auth_token');

// Via event
storage.send(SecureReadEvent(key: 'auth_token'));
```

**Returns:** The stored string or `null`

**Rebuild Groups:** None

### SecureWriteEvent

Writes a value to secure storage.

```dart
// Via helper
await storage.secureWrite('auth_token', token);

// Via event
storage.send(SecureWriteEvent(key: 'auth_token', value: token));
```

**Note:** TTL is NOT supported for secure storage (by design).

**Rebuild Groups:** `storage:secure`

### SecureDeleteEvent

Deletes a value from secure storage.

```dart
// Via helper
await storage.secureDelete('auth_token');

// Via event
storage.send(SecureDeleteEvent(key: 'auth_token'));
```

**Rebuild Groups:** `storage:secure`

### SecureDeleteAllEvent

Deletes all secure storage values.

```dart
await storage.secureDeleteAll();
```

**Rebuild Groups:** `storage:secure`

---

## SQLite Events

### SqliteQueryEvent

Executes a SELECT query.

```dart
// Via helper
final rows = await storage.sqliteQuery('SELECT * FROM users WHERE id = ?', [1]);

// Via event
storage.send(SqliteQueryEvent(sql: 'SELECT * FROM users', arguments: null));
```

**Returns:** `List<Map<String, dynamic>>`

**Rebuild Groups:** None

### SqliteInsertEvent

Inserts a row into a table.

```dart
// Via helper
final rowId = await storage.sqliteInsert('users', {'name': 'Alice'});

// Via event
storage.send(SqliteInsertEvent(table: 'users', values: {'name': 'Alice'}));
```

**Returns:** The inserted row ID

**Rebuild Groups:** `storage:sqlite:{table}`

### SqliteUpdateEvent

Updates rows in a table.

```dart
// Via helper
final affected = await storage.sqliteUpdate(
  'users',
  {'name': 'Bob'},
  where: 'id = ?',
  whereArgs: [1],
);

// Via event
storage.send(SqliteUpdateEvent(
  table: 'users',
  values: {'name': 'Bob'},
  where: 'id = ?',
  whereArgs: [1],
));
```

**Returns:** Number of affected rows

**Rebuild Groups:** `storage:sqlite:{table}`

### SqliteDeleteEvent

Deletes rows from a table.

```dart
// Via helper
final deleted = await storage.sqliteDelete('users', where: 'id = ?', whereArgs: [1]);

// Via event
storage.send(SqliteDeleteEvent(table: 'users', where: 'id = ?', whereArgs: [1]));
```

**Returns:** Number of deleted rows

**Rebuild Groups:** `storage:sqlite:{table}`

### SqliteRawEvent

Executes raw SQL (CREATE, DROP, etc.).

```dart
// Via helper
await storage.sqliteRaw('CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY)');

// Via event
storage.send(SqliteRawEvent(sql: 'DROP TABLE IF EXISTS temp'));
```

**Rebuild Groups:** None

---

## Cache Management Events

### CacheCleanupEvent

Triggers cache cleanup (removes expired entries).

```dart
// Manual cleanup
final removedCount = await storage.cleanupExpiredCache();

// Or configure automatic background cleanup
StorageConfig(
  enableBackgroundCleanup: true,
  cacheCleanupInterval: Duration(minutes: 15),
)
```

**Rebuild Groups:** `storage:cache` + backend groups for deleted entries

### ClearAllEvent

Clears storage data (logout scenario).

```dart
await storage.clearAll(ClearAllOptions(
  clearHive: true,
  clearPrefs: true,
  clearSecure: true,
  clearSqlite: false,
  hiveBoxesToClear: ['cache'],  // null = all boxes
  sqliteDropTables: false,       // false = delete rows only
));
```

**Rebuild Groups:** All affected backend groups

---

## Rebuild Groups Summary

| Group | Triggered By |
|-------|--------------|
| `storage:init` | Initialization complete/failed |
| `storage:prefs` | Prefs write/delete |
| `storage:hive:{boxName}` | Hive write/delete for specific box |
| `storage:sqlite:{tableName}` | SQLite insert/update/delete for specific table |
| `storage:secure` | Secure storage write/delete |
| `storage:cache` | Cache metadata changes, cleanup |

## Using Events in Widgets

React to storage changes with `StatelessJuiceWidget`:

```dart
class ThemeSelector extends StatelessJuiceWidget<StorageBloc> {
  ThemeSelector() : super(groups: const {'storage:prefs'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Rebuilds when any prefs change
    return FutureBuilder<String?>(
      future: bloc.prefsRead<String>('theme'),
      builder: (context, snapshot) {
        // ...
      },
    );
  }
}
```

Or use more specific groups:

```dart
class CacheStatusWidget extends StatelessJuiceWidget<StorageBloc> {
  CacheStatusWidget() : super(groups: const {'storage:cache'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final stats = bloc.state.cacheStats;
    return Text('Cached items: ${stats.metadataCount}');
  }
}
```
