# JUICE_STORAGE-SPEC-001@1.0.0

> Canonical specification for the `juice_storage` companion package

**Status:** DRAFT
**Version:** 1.0.0
**Last Updated:** 2026-01-06
**Depends On:** juice (core)

---

## 0) Summary

`juice_storage` is a **foundation** package that provides **local persistence + caching** through multiple backends (Hive, SharedPreferences, SQLite, Secure Storage), with **TTL-based cache semantics** and a **single event-driven bloc** interface (`StorageBloc`).

**Core Principle:** All mutations and reads flow through **events → use cases**, while "helper methods" exist purely as ergonomic wrappers that dispatch events and await state results.

---

## 1) Goals and Non-Goals

### Goals

- Unified storage surface across:
  - **Hive** - structured local key-value + boxes
  - **SharedPreferences** - simple key-value
  - **SQLite** - tabular persistence
  - **Secure Storage** - secrets/credentials
- TTL caching with:
  - **Lazy eviction on read**
  - Optional periodic background cleanup
- Clear error taxonomy + "not initialized / not available" truthfulness
- Testability via mock bloc + seeding utilities

### Non-Goals (V1.0)

- Remote sync
- Cross-device replication
- Full schema migration framework (minimal hook only; full framework later)
- A "repository layer" opinion (apps/packages build that on top)

---

## 2) Package Classification

| Attribute | Value |
|-----------|-------|
| **Type** | Foundation package (lowest layer in companion hierarchy) |
| **Depends On** | `juice` (core) ✅ |
| **Depends On other `juice_*` packages** | None ✅ |
| **External Dependencies** | hive, hive_flutter, shared_preferences, sqflite, flutter_secure_storage |
| **Used By** | juice_auth, juice_config, juice_theme, juice_analytics |
| **StateRelay** | None (foundation) |
| **EventSubscription** | None (foundation) |

**Note:** "Foundation" means this package has no dependencies on other `juice_*` companion packages, making it safe to depend on from any other companion. It does extend `JuiceBloc` from core.

---

## 3) Public API Surface

### Exports

```dart
// juice_storage.dart
export 'src/storage_bloc.dart';
export 'src/storage_state.dart';
export 'src/storage_events.dart';
export 'src/storage_config.dart';
export 'src/storage_exceptions.dart';
export 'src/cache/cache_metadata.dart';
export 'src/cache/cache_stats.dart';

// NOTE: Adapters are NOT exported. They are internal implementation details.
// Tests should use MockStorageBloc or in-memory adapters via @visibleForTesting.
```

### Primary Usage Pattern

- **Preferred:** `await bloc.<helper>()` (internally dispatches events)
- **Always allowed:** `bloc.send(Event)` and listen to rebuild groups

**INVARIANT:** Adapters are internal. Public consumers use bloc helpers or events only.

---

## 4) Storage Key Canonicalization

All storage keys follow a canonical scheme for TTL metadata and debugging:

| Backend | Pattern | Example |
|---------|---------|---------|
| Hive | `hive:{box}:{key}` | `hive:cache:user_123` |
| SharedPreferences | `prefs:{key}` | `prefs:theme_mode` |
| Secure Storage | `secure:{key}` | `secure:auth_token` |
| SQLite | `sqlite:{table}:{primaryKey}` | `sqlite:users:42` |

**INVARIANT:** Storage keys are deterministic and unambiguous.

### StorageKeys Helper

```dart
/// Canonical storage key builder for TTL metadata and debugging.
class StorageKeys {
  static String prefs(String key) => 'prefs:$key';
  static String hive(String box, String key) => 'hive:$box:$key';
  static String secure(String key) => 'secure:$key';
  static String sqlite(String table, String pk) => 'sqlite:$table:$pk';
}
```

### SharedPreferences Key Prefixing

**INVARIANT:** Public consumers always pass **logical keys** (e.g., `theme_mode`). The adapter/use case applies the configured prefix internally (e.g., `juice_theme_mode`).

| Layer | Key Format | Example |
|-------|------------|---------|
| Public API | Logical key | `prefsWrite('theme', 'dark')` |
| Adapter (internal) | Prefixed key | `SharedPreferences.setString('juice_theme', 'dark')` |
| Canonical key (metadata) | `prefs:{logical}` | `prefs:theme` |

This ensures:
- Callers never need to know about prefixes
- ClearAll uses prefix to filter only Juice-owned keys
- No accidental collision with other libraries' prefs

---

## 5) Bloc Contract

### Bloc Definition

```dart
class StorageBloc extends JuiceBloc<StorageState> {
  StorageBloc({required StorageConfig config})
      : _config = config,
        super(
          initialState: const StorageState(),
          initialEventBuilder: () => InitializeStorageEvent(),
        );
}
```

**Lifecycle:** Permanent (app-wide singleton)

### State (Canonical)

```dart
class StorageState extends BlocState {
  // Initialization
  final bool isInitialized;
  final StorageBackendStatus backendStatus;

  // Backend metadata
  final Map<String, BoxInfo> hiveBoxes;
  final Map<String, TableInfo> sqliteTables;
  final bool secureStorageAvailable;

  // Error tracking
  final StorageError? lastError;

  // Cache statistics
  final CacheStats cacheStats;

  // NOTE: No lastReadValue/lastSecureValue here!
  // Results are returned via OperationResult, not stored in state.
  // This prevents concurrency bugs when multiple reads happen in parallel.
}

class StorageBackendStatus {
  final BackendState hive;      // uninitialized | ready | error
  final BackendState prefs;
  final BackendState sqlite;
  final BackendState secure;
}

class CacheStats {
  final int metadataCount;
  final int expiredCount;
  final DateTime? lastCleanupAt;
  final int lastCleanupCleanedCount;
}
```

### Rebuild Groups (Canonical)

| Group | Triggered By |
|-------|-------------|
| `storage:init` | Initialization complete/failed |
| `storage:hive:{boxName}` | Write/delete to specific Hive box |
| `storage:prefs` | SharedPreferences changes |
| `storage:sqlite:{tableName}` | SQLite table modifications |
| `storage:secure` | Secure storage changes |
| `storage:cache` | Cache metadata changes, cleanup |

**INVARIANT:** Each use case emits the minimal rebuild group(s) only.

---

## 6) Events (Canonical)

All operational events carry an optional `requestId` for correlation.

### Initialization

```dart
class InitializeStorageEvent extends StorageEvent {}
```

### Hive Operations

```dart
class HiveOpenBoxEvent extends StorageEvent {
  final String boxName;
  final bool lazy;
}

class HiveReadEvent<T> extends StorageEvent {
  final String box;
  final String key;
}

class HiveWriteEvent<T> extends StorageEvent {
  final String box;
  final String key;
  final T value;
  final Duration? ttl;  // TTL supported
}

class HiveDeleteEvent extends StorageEvent {
  final String box;
  final String key;
}

class HiveCloseBoxEvent extends StorageEvent {
  final String boxName;
}
```

### SharedPreferences Operations

```dart
class PrefsReadEvent<T> extends StorageEvent {
  final String key;
}

class PrefsWriteEvent<T> extends StorageEvent {
  final String key;
  final T value;
  final Duration? ttl;  // TTL supported
}

class PrefsDeleteEvent extends StorageEvent {
  final String key;
}
```

### SQLite Operations

```dart
class SqliteQueryEvent extends StorageEvent {
  final String sql;
  final List<dynamic>? arguments;
}

class SqliteInsertEvent extends StorageEvent {
  final String table;
  final Map<String, dynamic> values;
}

class SqliteUpdateEvent extends StorageEvent {
  final String table;
  final Map<String, dynamic> values;
  final String? where;
  final List<dynamic>? whereArgs;
}

class SqliteDeleteEvent extends StorageEvent {
  final String table;
  final String? where;
  final List<dynamic>? whereArgs;
}

class SqliteRawEvent extends StorageEvent {
  final String sql;
  final List<dynamic>? arguments;
}
```

### Secure Storage Operations

```dart
class SecureReadEvent extends StorageEvent {
  final String key;
}

class SecureWriteEvent extends StorageEvent {
  final String key;
  final String value;
  // NO TTL - secrets require explicit deletion
}

class SecureDeleteEvent extends StorageEvent {
  final String key;
}

class SecureDeleteAllEvent extends StorageEvent {}
```

### Cache Management

```dart
class CacheCleanupEvent extends StorageEvent {
  final bool runNow;           // Immediate cleanup
  final Duration? interval;    // For periodic setup
}

class ClearAllEvent extends StorageEvent {
  final ClearAllOptions options;
}

class ClearAllOptions {
  final bool clearHive;
  final bool clearPrefs;
  final bool clearSecure;
  final bool clearSqlite;
  final List<String>? hiveBoxesToClear;  // null = all known boxes
  final bool sqliteDropTables;           // false = delete rows only
}
```

---

## 7) Helper Methods Policy

**FROZEN DECISION:** Everything goes through events/use cases. Helper methods are thin wrappers around `sendAndWaitResult(...)` and never touch adapters directly.

### Result-Return Model (Concurrency-Safe)

Results are returned directly from use cases via event-carried completers, **not** stored in shared state. This prevents the classic concurrency bug where two parallel reads overwrite each other's results.

**Critical design constraint:** Events should **NOT** be generic (e.g., `PrefsReadEvent<T>`) because Juice's registry matches exact runtime `Type`. Events return `Object?`; helpers provide the generic cast.

### 7.1) ResultEvent<TResult> (Event-Carried Completer)

```dart
import 'dart:async';

/// Base class for events that return typed results.
abstract class ResultEvent<TResult> extends EventBase {
  ResultEvent({
    String? requestId,
    Set<String>? groupsToRebuild,
  })  : requestId = requestId ?? _newRequestId(),
        super(groupsToRebuild: groupsToRebuild);

  /// Correlation id for logs / debugging / op tracing.
  final String requestId;

  final Completer<TResult> _completer = Completer<TResult>();

  Future<TResult> get result => _completer.future;
  bool get isCompleted => _completer.isCompleted;

  void succeed(TResult value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) _completer.completeError(error, stackTrace);
  }

  static String _newRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'req_$now';
  }
}
```

**Why this works:** Each event has its own result future. No shared `lastReadValue` in state. Helpers can `await` result deterministically.

### 7.2) OperationResult<TResult, TState>

Wraps the final `StreamStatus` for that event plus the typed value.

```dart
class OperationResult<TResult, TState extends BlocState> {
  OperationResult({
    required this.status,
    required this.value,
  });

  final StreamStatus<TState> status;
  final TResult? value;

  bool get isSuccess => status is UpdatingStatus<TState>;
  bool get isFailure => status is FailureStatus<TState>;
  bool get isCanceled => status is CancelingStatus<TState>;

  FailureStatus<TState>? get failure =>
      status is FailureStatus<TState> ? status as FailureStatus<TState> : null;

  Object? get error => failure?.error;
  StackTrace? get errorStackTrace => failure?.errorStackTrace;
}
```

### 7.3) sendAndWaitResult<TResult>() Extension

**Critical fix vs standard `sendAndWait`:** Filters by **the specific event instance** (`identical(s.event, event)`), so concurrency is safe.

```dart
extension JuiceBlocResultOps<TState extends BlocState> on JuiceBloc<TState> {
  /// Sends a ResultEvent and returns (final status + typed value).
  Future<OperationResult<TResult, TState>> sendAndWaitResult<TResult>(
    ResultEvent<TResult> event, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Listen BEFORE sending to avoid missing fast emissions.
    final statusFuture = stream
        .where((s) => identical(s.event, event)) // <-- critical for concurrency
        .firstWhere((s) => s is! WaitingStatus<TState>)
        .timeout(timeout);

    await send(event);

    final status = await statusFuture;

    // If the use case emitted failure/cancel, don't wait for a value.
    if (status is FailureStatus<TState> || status is CancelingStatus<TState>) {
      if (!event.isCompleted) {
        if (status is FailureStatus<TState>) {
          event.fail(status.error ?? StateError('Operation failed'), status.errorStackTrace);
        } else {
          event.fail(StateError('Operation cancelled'));
        }
      }
      return OperationResult(status: status, value: null);
    }

    // Success path: await the value (completed by the use case).
    final value = await event.result.timeout(timeout);
    return OperationResult(status: status, value: value);
  }

  /// Convenience: unwraps value or throws on failure.
  Future<TResult> sendForResult<TResult>(
    ResultEvent<TResult> event, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final op = await sendAndWaitResult(event, timeout: timeout);

    if (op.isSuccess) {
      return op.value as TResult;
    }

    final err = op.error ?? StateError('Operation failed');
    Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
  }
}
```

### 7.4) Canonical Event Signatures

Events return `Object?`; helpers provide the generic cast.

```dart
class PrefsReadEvent extends ResultEvent<Object?> {
  PrefsReadEvent({
    required this.key,
    String? requestId,
    Set<String>? groupsToRebuild,
  }) : super(requestId: requestId, groupsToRebuild: groupsToRebuild);

  final String key;
}

class PrefsWriteEvent extends ResultEvent<void> {
  PrefsWriteEvent({
    required this.key,
    required this.value,
    this.ttl,
    String? requestId,
    Set<String>? groupsToRebuild,
  }) : super(requestId: requestId, groupsToRebuild: groupsToRebuild);

  final String key;
  final Object? value;
  final Duration? ttl;
}

class HiveReadEvent extends ResultEvent<Object?> {
  HiveReadEvent({
    required this.box,
    required this.key,
    String? requestId,
    Set<String>? groupsToRebuild,
  }) : super(requestId: requestId, groupsToRebuild: groupsToRebuild);

  final String box;
  final String key;
}

class HiveWriteEvent extends ResultEvent<void> {
  HiveWriteEvent({
    required this.box,
    required this.key,
    required this.value,
    this.ttl,
    String? requestId,
    Set<String>? groupsToRebuild,
  }) : super(requestId: requestId, groupsToRebuild: groupsToRebuild);

  final String box;
  final String key;
  final Object? value;
  final Duration? ttl;
}
```

### 7.5) Helper Method Implementation

```dart
extension StorageBlocHelpers on StorageBloc {
  // ═══════════════════════════════════════════════════════════════
  // SharedPreferences Helpers
  // ═══════════════════════════════════════════════════════════════

  Future<T?> prefsRead<T>(
    String key, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final op = await sendAndWaitResult<Object?>(
      PrefsReadEvent(key: key),
      timeout: timeout,
    );

    if (op.isFailure) {
      final err = op.error ?? StateError('Prefs read failed');
      Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
    }

    return op.value as T?;
  }

  Future<void> prefsWrite(
    String key,
    Object? value, {
    Duration? ttl,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return sendForResult<void>(
      PrefsWriteEvent(key: key, value: value, ttl: ttl),
      timeout: timeout,
    );
  }

  Future<void> prefsDelete(String key) {
    return sendForResult<void>(PrefsDeleteEvent(key: key));
  }

  // ═══════════════════════════════════════════════════════════════
  // Hive Helpers
  // ═══════════════════════════════════════════════════════════════

  Future<T?> hiveRead<T>(
    String box,
    String key, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final op = await sendAndWaitResult<Object?>(
      HiveReadEvent(box: box, key: key),
      timeout: timeout,
    );

    if (op.isFailure) {
      final err = op.error ?? StateError('Hive read failed');
      Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
    }

    return op.value as T?;
  }

  Future<void> hiveWrite(
    String box,
    String key,
    Object? value, {
    Duration? ttl,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return sendForResult<void>(
      HiveWriteEvent(box: box, key: key, value: value, ttl: ttl),
      timeout: timeout,
    );
  }

  Future<void> hiveDelete(String box, String key) {
    return sendForResult<void>(HiveDeleteEvent(box: box, key: key));
  }

  // ═══════════════════════════════════════════════════════════════
  // Secure Storage Helpers
  // ═══════════════════════════════════════════════════════════════

  Future<String?> secureRead(String key) async {
    final op = await sendAndWaitResult<Object?>(SecureReadEvent(key: key));
    if (op.isFailure) {
      final err = op.error ?? StateError('Secure read failed');
      Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
    }
    return op.value as String?;
  }

  Future<void> secureWrite(String key, String value) {
    return sendForResult<void>(SecureWriteEvent(key: key, value: value));
  }

  Future<void> secureDelete(String key) {
    return sendForResult<void>(SecureDeleteEvent(key: key));
  }

  // ═══════════════════════════════════════════════════════════════
  // SQLite Helpers
  // ═══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> sqliteQuery(
    String sql, [
    List<dynamic>? args,
  ]) async {
    final op = await sendAndWaitResult<Object?>(
      SqliteQueryEvent(sql: sql, arguments: args),
    );
    if (op.isFailure) {
      final err = op.error ?? StateError('SQLite query failed');
      Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
    }
    return (op.value as List<Map<String, dynamic>>?) ?? [];
  }

  Future<int> sqliteInsert(String table, Map<String, dynamic> values) async {
    final op = await sendAndWaitResult<Object?>(
      SqliteInsertEvent(table: table, values: values),
    );
    if (op.isFailure) {
      final err = op.error ?? StateError('SQLite insert failed');
      Error.throwWithStackTrace(err, op.errorStackTrace ?? StackTrace.current);
    }
    return (op.value as int?) ?? -1;
  }

  // Advanced: returns full OperationResult for inspection
  Future<OperationResult<Object?, StorageState>> prefsReadOp(String key) {
    return sendAndWaitResult<Object?>(PrefsReadEvent(key: key));
  }
}
```

### 7.6) Use Case Completion Rules

Use cases **must always**:
1. Complete the event result (`succeed` or `fail`)
2. Emit either update or failure (so status resolves)

```dart
class PrefsReadUseCase extends BlocUseCase<StorageBloc, PrefsReadEvent> {
  @override
  Future<void> execute(PrefsReadEvent event) async {
    try {
      final value = await bloc.prefsAdapter.read(event.key);
      event.succeed(value);

      // Reads don't rebuild unless eviction occurs
      emitUpdate(newState: bloc.state, groupsToRebuild: const {});
    } catch (e, st) {
      event.fail(e, st);

      emitFailure(
        newState: bloc.state,
        groupsToRebuild: const {'storage:prefs'},
        error: e,
        errorStackTrace: st,
      );
    }
  }
}
```

**INVARIANT:** Concurrent reads never interfere. Each event instance has its own completer. `sendAndWaitResult` filters by `identical(s.event, event)`.

---

## 8) Use Cases

| Use Case | Builder Type | Emits Groups |
|----------|--------------|--------------|
| `InitializeStorageUseCase` | StatefulUseCaseBuilder | `storage:init` |
| `HiveReadUseCase` | UseCaseBuilder | *see note below* |
| `HiveWriteUseCase` | UseCaseBuilder | `storage:hive:{box}`, `storage:cache` if TTL |
| `HiveDeleteUseCase` | UseCaseBuilder | `storage:hive:{box}`, `storage:cache` if TTL existed |
| `PrefsReadUseCase` | UseCaseBuilder | *see note below* |
| `PrefsWriteUseCase` | UseCaseBuilder | `storage:prefs`, `storage:cache` if TTL |
| `PrefsDeleteUseCase` | UseCaseBuilder | `storage:prefs`, `storage:cache` if TTL existed |
| `SecureReadUseCase` | UseCaseBuilder | *none* (no TTL, no eviction) |
| `SecureWriteUseCase` | UseCaseBuilder | `storage:secure` |
| `SecureDeleteUseCase` | UseCaseBuilder | `storage:secure` |
| `SqliteQueryUseCase` | UseCaseBuilder | *none* (no TTL) |
| `SqliteInsertUseCase` | UseCaseBuilder | `storage:sqlite:{table}` |
| `SqliteUpdateUseCase` | UseCaseBuilder | `storage:sqlite:{table}` |
| `SqliteDeleteUseCase` | UseCaseBuilder | `storage:sqlite:{table}` |
| `CacheCleanupUseCase` | StatefulUseCaseBuilder | `storage:cache`, plus backend groups for deleted entries |
| `ClearAllUseCase` | UseCaseBuilder | All affected groups |

### Read Side Effects (Lazy Eviction)

**FROZEN DECISION:** Reads that encounter expired TTL perform lazy eviction and **do** emit rebuild groups.

| Scenario | Emits Groups |
|----------|--------------|
| Read, key not found | *none* |
| Read, key found, not expired | *none* |
| Read, key found, **expired** | `storage:hive:{box}` or `storage:prefs`, plus `storage:cache` |

This ensures UI observing "cached item exists" sees the deletion. Otherwise, a widget showing cache status would be stale after a read silently evicts data.

**Implementation:** Read use case checks TTL → if expired → delete value + metadata → emit groups → return null.

### 8.1) Canonical Lazy-Eviction Read Use Case

Complete implementation showing the 4-step eviction path:

```dart
class PrefsReadUseCase extends BlocUseCase<StorageBloc, PrefsReadEvent> {
  PrefsReadUseCase({
    required this.cacheIndex,
    required this.clock,
  });

  final CacheIndex cacheIndex;

  /// Injected clock makes TTL tests deterministic.
  final DateTime Function() clock;

  @override
  Future<void> execute(PrefsReadEvent event) async {
    final now = clock();
    final storageKey = StorageKeys.prefs(event.key);

    try {
      final meta = await cacheIndex.get(storageKey);

      // ---- (1) Find expired data
      if (meta != null && meta.hasExpiry && meta.isExpired(now)) {
        // ---- (2) Delete value + metadata (best-effort)
        await _evictExpiredPrefs(storageKey: storageKey, prefsKey: event.key);

        // ---- (4) Return null successfully
        event.succeed(null);

        // ---- (3) Emit cache + backend groups
        emitUpdate(
          newState: bloc.state,
          groupsToRebuild: const {'storage:cache', 'storage:prefs'},
        );
        return;
      }

      // Normal read (not expired)
      final value = await bloc.prefsAdapter.read(event.key);
      event.succeed(value);

      // Reads normally do not rebuild anything.
      emitUpdate(newState: bloc.state, groupsToRebuild: const {});
    } catch (e, st) {
      event.fail(e, st);
      emitFailure(
        newState: bloc.state,
        groupsToRebuild: const {'storage:prefs'},
        error: e,
        errorStackTrace: st,
      );
    }
  }

  Future<void> _evictExpiredPrefs({
    required String storageKey,
    required String prefsKey,
  }) async {
    // Best-effort deletion: never throw out of eviction path.
    // Clear both even if one fails.
    try {
      await bloc.prefsAdapter.delete(prefsKey);
    } catch (_) {
      // Swallow (optionally log)
    }

    try {
      await cacheIndex.delete(storageKey);
    } catch (_) {
      // Swallow (optionally log)
    }
  }
}
```

### 8.2) Eviction Behavior Guarantees

| Guarantee | Description |
|-----------|-------------|
| **Expired = success** | If expired, the operation is `UpdatingStatus` (success), value is `null` |
| **No concurrency bleed** | Each event has its own completer; no shared `lastReadValue` |
| **Best-effort eviction** | Eviction errors are swallowed; expiration is not "failure to read" |
| **Groups always emitted** | UI sees the eviction via `storage:cache` + backend group |

### 8.3) Helper Usage: Caller Sees "Null Success"

```dart
// Simple usage - null means expired (or never existed)
final flagsJson = await storageBloc.prefsRead<String>('flags');
if (flagsJson == null) {
  // Either expired and evicted, or never stored
}

// Advanced usage - inspect the full operation result
final op = await storageBloc.prefsReadOp('flags');
assert(op.isSuccess);       // Eviction is still "success"
assert(op.value == null);   // But value is null
```

### 8.4) Same Pattern for HiveRead

Identical structure, only the eviction details change:

```dart
// In HiveReadUseCase._evictExpiredHive()
await bloc.hiveAdapter.delete(box, key);
await cacheIndex.delete(StorageKeys.hive(box, key));

// Emit groups
emitUpdate(
  newState: bloc.state,
  groupsToRebuild: {'storage:cache', 'storage:hive:$box'},
);
```

---

## 9) TTL / Cache Semantics

### V1.0 TTL Support Matrix

| Backend | TTL Supported | Notes |
|---------|---------------|-------|
| Hive | ✅ Yes | Via metadata index |
| SharedPreferences | ✅ Yes | Via metadata index |
| Secure Storage | ❌ No | Secrets require explicit deletion |
| SQLite | ❌ No | Defer to V2.0 with opt-in schema |

### Hive TypeId Reservation

**INVARIANT:** `juice_storage` reserves Hive typeIds **900-949** to avoid collisions in mono-repos.

| TypeId | Type |
|--------|------|
| 900 | `CacheMetadata` |
| 901-949 | Reserved for future juice_storage types |

### Cache Metadata

```dart
// Stored in dedicated Hive box "_juice_cache_metadata"
@HiveType(typeId: 900)  // Reserved range for juice_storage
class CacheMetadata {
  @HiveField(0)
  final String storageKey;  // Canonical key: "hive:box:key"

  @HiveField(1)
  final DateTime expiresAt;

  @HiveField(2)
  final DateTime createdAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

### Cache Index

The `CacheIndex` is a "dumb index" that only manages metadata. It does **not** orchestrate cleanup—that's the use case's job.

```dart
class CacheIndex {
  late Box<CacheMetadata> _metadataBox;

  Future<void> init() async {
    _metadataBox = await Hive.openBox<CacheMetadata>('_juice_cache_metadata');
  }

  String canonicalKey(String backend, String key, [String? box]) {
    if (backend == 'hive') return 'hive:$box:$key';
    if (backend == 'prefs') return 'prefs:$key';
    throw ArgumentError('TTL not supported for $backend');
  }

  Future<void> setExpiry(String storageKey, Duration ttl) async {
    await _metadataBox.put(storageKey, CacheMetadata(
      storageKey: storageKey,
      expiresAt: DateTime.now().add(ttl),
      createdAt: DateTime.now(),
    ));
  }

  bool isExpired(String storageKey) {
    final meta = _metadataBox.get(storageKey);
    if (meta == null) return false;  // No TTL = never expires
    return meta.isExpired;
  }

  CacheMetadata? getMetadata(String storageKey) {
    return _metadataBox.get(storageKey);
  }

  Future<void> removeExpiry(String storageKey) async {
    await _metadataBox.delete(storageKey);
  }

  /// Returns list of expired entries for cleanup use case to process.
  /// CacheIndex does NOT delete backend data—use case does that via adapters.
  List<CacheMetadata> getExpiredEntries() {
    return _metadataBox.values.where((m) => m.isExpired).toList();
  }

  Future<void> clear() async {
    await _metadataBox.clear();
  }
}
```

**INVARIANT:** CacheIndex never calls back into bloc or adapters. It only manages metadata. The `CacheCleanupUseCase` orchestrates actual deletion via adapters.

### Eviction Strategy

**FROZEN DECISION:** Hybrid eviction

1. **Lazy eviction on read:** If expired, delete value + metadata via adapters, emit groups, return null
2. **Background cleanup:** Periodic `CacheCleanupUseCase` (default: 15 minutes)

### Background Cleanup Lifecycle

**INVARIANT:** Background cleanup follows strict lifecycle rules.

| Rule | Description |
|------|-------------|
| **Startup** | If `config.enableBackgroundCleanup == true`, `InitializeStorageUseCase` starts the periodic timer |
| **Single instance** | Only one periodic timer may exist at a time |
| **Re-send replaces** | Sending `CacheCleanupEvent(interval: X)` cancels any existing timer and starts a new one |
| **Manual trigger** | `CacheCleanupEvent(runNow: true)` runs cleanup immediately without affecting the timer |
| **Cancellation** | `bloc.close()` cancels the timer |
| **No timer leaks** | Timer must be cancelled before bloc disposal completes |

```dart
// CacheCleanupUseCase (StatefulUseCaseBuilder)
class CacheCleanupUseCase extends StatefulUseCaseBuilder<CacheCleanupEvent> {
  Timer? _cleanupTimer;

  @override
  Future<void> execute(CacheCleanupEvent event, ...) async {
    if (event.runNow) {
      await _performCleanup();
    }

    if (event.interval != null) {
      _cleanupTimer?.cancel();
      _cleanupTimer = Timer.periodic(event.interval!, (_) => _performCleanup());
    }
  }

  Future<void> _performCleanup() async {
    final expired = cacheIndex.getExpiredEntries();
    final affectedGroups = <String>{};

    for (final meta in expired) {
      // Delete via adapter (not bloc) to avoid event recursion
      await _deleteByCanonicalKey(meta.storageKey);
      await cacheIndex.removeExpiry(meta.storageKey);
      affectedGroups.add(_groupForStorageKey(meta.storageKey));
    }

    affectedGroups.add('storage:cache');
    emitWithGroups(state.copyWith(cacheStats: ...), affectedGroups);
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }
}
```

---

## 10) Configuration

```dart
class StorageConfig {
  /// Hive configuration
  final String? hivePath;
  final List<String> hiveBoxesToOpen;  // Auto-open on init
  final List<TypeAdapter> hiveAdapters;

  /// SharedPreferences namespace
  final String prefsKeyPrefix;  // e.g., "juice_" -> keys become "juice_theme"

  /// SQLite configuration
  final String sqliteDatabaseName;
  final int sqliteDatabaseVersion;
  final OnDatabaseCreateFn? sqliteOnCreate;
  final OnDatabaseUpgradeFn? sqliteOnUpgrade;

  /// Secure storage options
  final IOSOptions? secureStorageIOS;
  final AndroidOptions? secureStorageAndroid;

  /// Cache configuration
  final Duration cacheCleanupInterval;  // Default: 15 minutes
  final bool enableBackgroundCleanup;   // Default: true

  const StorageConfig({
    this.hivePath,
    this.hiveBoxesToOpen = const [],
    this.hiveAdapters = const [],
    this.prefsKeyPrefix = 'juice_',
    this.sqliteDatabaseName = 'juice.db',
    this.sqliteDatabaseVersion = 1,
    this.sqliteOnCreate,
    this.sqliteOnUpgrade,
    this.secureStorageIOS,
    this.secureStorageAndroid,
    this.cacheCleanupInterval = const Duration(minutes: 15),
    this.enableBackgroundCleanup = true,
  });
}
```

**INVARIANT:** Prefs clearing uses `prefsKeyPrefix` to avoid nuking unrelated preferences.

---

## 11) Error Model

```dart
class StorageException extends JuiceException {
  final StorageErrorType type;
  final String? storageKey;
  final String? requestId;

  StorageException(
    super.message, {
    required this.type,
    this.storageKey,
    this.requestId,
    super.cause,
    super.isRetryable = false,
  });
}

enum StorageErrorType {
  notInitialized,
  backendNotAvailable,
  boxNotOpen,
  keyNotFound,
  typeError,
  serializationError,
  encryptionError,
  platformNotSupported,
  sqliteError,
  permissionDenied,
}

/// DTO for state tracking
class StorageError {
  final String message;
  final StorageErrorType type;
  final String? storageKey;
  final String? requestId;
  final DateTime timestamp;
}
```

**INVARIANT:** Use cases must set `lastError`, preserve previous good state, and mark retryability correctly.

---

## 12) ClearAll Semantics

`ClearAllEvent` is the "logout scenario" event.

**V1.0 Behavior:**

| Backend | Default Behavior | Configurable |
|---------|------------------|--------------|
| Hive | Clear specified boxes (or all known) | `hiveBoxesToClear` |
| SharedPreferences | Clear only keys with `prefsKeyPrefix` | Prefix in config |
| Secure Storage | `deleteAll()` | N/A |
| SQLite | Delete rows (not drop tables) | `sqliteDropTables` |

**INVARIANT:** `ClearAllEvent` never deletes data outside the Juice namespace by default.

---

## 13) Testing Contract

### Mock Bloc

```dart
class MockStorageBloc extends StorageBloc {
  final Map<String, dynamic> _mockData = {};

  MockStorageBloc() : super(config: StorageConfig());

  @override
  Future<T?> hiveRead<T>(String box, String key) async {
    return _mockData['hive:$box:$key'] as T?;
  }

  @override
  Future<void> hiveWrite<T>(String box, String key, T value, {Duration? ttl}) async {
    _mockData['hive:$box:$key'] = value;
  }

  // Seeding utilities
  void seedHive<T>(String box, String key, T value) {
    _mockData['hive:$box:$key'] = value;
  }

  void seedPrefs<T>(String key, T value) {
    _mockData['prefs:$key'] = value;
  }

  void seedSecure(String key, String value) {
    _mockData['secure:$key'] = value;
  }
}
```

### In-Memory Adapters

```dart
class InMemoryHiveAdapter<T> implements StorageAdapter<T> { ... }
class InMemoryPrefsAdapter implements StorageAdapter<dynamic> { ... }
class InMemorySecureAdapter implements StorageAdapter<String> { ... }
```

### Clock Injection (for TTL tests)

```dart
class StorageBloc extends JuiceBloc<StorageState> {
  @visibleForTesting
  DateTime Function() clock = () => DateTime.now();
}
```

---

## 14) Adapters (Internal)

### Key-Value Adapters

For Hive, SharedPreferences, and Secure Storage, use a unified key-value interface:

```dart
abstract class KeyValueAdapter<T> {
  Future<T?> read(String key);
  Future<void> write(String key, T value);
  Future<void> delete(String key);
  Future<void> clear();
  Future<bool> containsKey(String key);
  Future<Iterable<String>> keys();
}

class HiveAdapter<T> implements KeyValueAdapter<T> { ... }
class SharedPrefsAdapter implements KeyValueAdapter<dynamic> { ... }
class SecureStorageAdapter implements KeyValueAdapter<String> { ... }
```

### SQLite Gateway (Separate Interface)

SQLite is fundamentally query-based, not key-value. Don't force it into the key-value interface.

```dart
abstract class SqliteGateway {
  Future<List<Map<String, dynamic>>> query(
    String sql, [List<dynamic>? arguments]
  );

  Future<int> insert(String table, Map<String, dynamic> values);

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  });

  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  });

  Future<void> execute(String sql, [List<dynamic>? arguments]);

  Future<void> close();
}

class SqliteGatewayImpl implements SqliteGateway { ... }
```

**INVARIANT:** Adapters are internal. Public consumers use bloc helpers or events.

**INVARIANT:** SQLite uses `SqliteGateway`, not `KeyValueAdapter`. Different storage paradigms get different interfaces.

---

## 15) Package Structure

```
packages/juice_storage/
├── lib/
│   ├── juice_storage.dart           # Public exports
│   └── src/
│       ├── storage_bloc.dart
│       ├── storage_state.dart
│       ├── storage_events.dart
│       ├── storage_config.dart
│       ├── storage_exceptions.dart
│       ├── cache/
│       │   ├── cache_index.dart
│       │   ├── cache_metadata.dart
│       │   ├── cache_metadata.g.dart  # Hive generated
│       │   └── cache_stats.dart
│       ├── adapters/
│       │   ├── key_value_adapter.dart
│       │   ├── hive_adapter.dart
│       │   ├── prefs_adapter.dart
│       │   ├── secure_adapter.dart
│       │   └── sqlite_gateway.dart
│       └── use_cases/
│           ├── initialize_storage_use_case.dart
│           ├── hive_read_use_case.dart
│           ├── hive_write_use_case.dart
│           ├── hive_delete_use_case.dart
│           ├── prefs_read_use_case.dart
│           ├── prefs_write_use_case.dart
│           ├── secure_read_use_case.dart
│           ├── secure_write_use_case.dart
│           ├── sqlite_query_use_case.dart
│           ├── sqlite_insert_use_case.dart
│           ├── cache_cleanup_use_case.dart
│           └── clear_all_use_case.dart
├── test/
│   ├── storage_bloc_test.dart
│   ├── cache_index_test.dart
│   ├── adapters/
│   │   └── ...
│   └── use_cases/
│       └── ...
├── pubspec.yaml
├── README.md
├── CHANGELOG.md
└── analysis_options.yaml
```

---

## 16) Acceptance Tests

### Initialization

- [ ] `InitializeStorageEvent` initializes all configured backends
- [ ] `storage:init` group is emitted on completion
- [ ] `backendStatus` reflects each backend's state
- [ ] Failed backend doesn't block others (graceful degradation)

### Hive Operations

- [ ] `hiveWrite` stores value retrievable by `hiveRead`
- [ ] `hiveWrite` with TTL creates metadata entry
- [ ] `hiveRead` of expired TTL returns null and deletes entry
- [ ] `hiveDelete` removes value and metadata
- [ ] `storage:hive:{box}` group emitted on write/delete

### SharedPreferences Operations

- [ ] `prefsWrite` stores value with configured prefix
- [ ] `prefsRead` retrieves prefixed value correctly
- [ ] TTL works same as Hive
- [ ] `storage:prefs` group emitted on write/delete

### Secure Storage Operations

- [ ] `secureWrite` stores encrypted value
- [ ] `secureRead` retrieves decrypted value
- [ ] `secureDelete` removes value
- [ ] No TTL support (throws if attempted)
- [ ] `storage:secure` group emitted on write/delete

### Cache Cleanup

- [ ] `CacheCleanupEvent(runNow: true)` deletes all expired entries
- [ ] Background cleanup runs at configured interval
- [ ] `cacheStats` updated after cleanup
- [ ] `storage:cache` group emitted

### ClearAll

- [ ] Clears only Juice-namespaced data by default
- [ ] Respects `ClearAllOptions` configuration
- [ ] All relevant rebuild groups emitted

### Error Handling

- [ ] `lastError` set on failure
- [ ] Previous state preserved on error
- [ ] `isRetryable` correctly set per error type

### Hard-Part Tests (Concurrency & Lifecycle)

These tests enforce the critical behaviors that "look fine until production":

- [ ] **Concurrent reads return correct values** - Two parallel `hiveRead` calls for different keys each return their own value, not the other's (validates result-return model)
- [ ] **Lazy eviction on read emits groups** - Reading an expired TTL entry emits `storage:hive:{box}` and `storage:cache` (not silent deletion)
- [ ] **Hive typeId is in reserved range** - `CacheMetadata` uses typeId 900 (validates collision protection)
- [ ] **Prefs prefix is never required from caller** - `prefsWrite('theme', 'dark')` works; adapter stores as `juice_theme`; `prefsRead('theme')` retrieves it (caller never sees prefix)
- [ ] **Background cleanup timer is single-instance** - Sending two `CacheCleanupEvent(interval: X)` results in only one active timer
- [ ] **ClearAll also clears cache metadata box** - After `ClearAllEvent`, `_juice_cache_metadata` box is empty (prevents metadata rot)

---

## 17) Frozen Decisions (V1.0)

| Decision | Status |
|----------|--------|
| Event-only core, helper wrappers via `sendAndWait` | ✅ FROZEN |
| Results returned via `OperationResult`, not shared state | ✅ FROZEN |
| Reads emit groups only on lazy eviction | ✅ FROZEN |
| TTL supports Hive + Prefs only | ✅ FROZEN |
| TTL NOT supported for Secure Storage | ✅ FROZEN |
| TTL NOT supported for SQLite | ✅ FROZEN |
| Prefs clearing is namespaced by prefix | ✅ FROZEN |
| Prefs callers use logical keys only | ✅ FROZEN |
| Adapters are internal (not public API) | ✅ FROZEN |
| SQLite uses `SqliteGateway`, not `KeyValueAdapter` | ✅ FROZEN |
| Hive typeIds reserved: 900-949 | ✅ FROZEN |
| CacheIndex never calls back into bloc | ✅ FROZEN |
| Single background cleanup timer, cancelled on close | ✅ FROZEN |

---

## 18) Open Questions (V2.0+)

- [ ] Isar support as Hive alternative?
- [ ] Hive schema migration strategy?
- [ ] Max cache size limits (LRU eviction)?
- [ ] SQLite TTL with opt-in `expiresAt` column?
- [ ] Cross-package cache coordination?

---

## 19) Why Use StorageBloc?

This section explains **when and why** to route storage through a bloc versus calling packages directly.

### Six Benefits of the Bloc Pattern

#### 1. One Contract Across Four Backends

```dart
// Without StorageBloc - you're married to specific APIs
await Hive.openBox('cache').then((b) => b.put('user', user));
await SharedPreferences.getInstance().then((p) => p.setString('theme', 'dark'));
await const FlutterSecureStorage().write(key: 'token', value: token);
```

```dart
// With StorageBloc - uniform API
await storage.hiveWrite('cache', 'user', user);
await storage.prefsWrite('theme', 'dark');
await storage.secureWrite('token', token);
```

If you later swap Hive for Isar or SharedPreferences for something else, only the adapter changes—your app code stays identical.

#### 2. Uniform Initialization + Availability Truth

```dart
// state.backendStatus tells you exactly what's ready
if (state.backendStatus.hive == BackendState.ready) { ... }
if (state.backendStatus.secure == BackendState.error) { ... }
```

No more scattered `isOpen` checks or try-catch blocks to discover whether a backend is available. The bloc is the single source of truth for storage availability.

#### 3. Real Cache Layer with TTL

```dart
// Write with TTL - auto-expires after 1 hour
await storage.hiveWrite('cache', 'user_profile', profile, ttl: Duration(hours: 1));

// Later read returns null if expired (lazy eviction)
final cached = await storage.hiveRead<UserProfile>('cache', 'user_profile');
```

TTL metadata lives in a dedicated index. Expired data is cleaned up lazily on read or periodically in the background. No manual timestamp checks.

#### 4. Observable Storage as a System

```dart
// React to storage changes anywhere in the app
BlocBuilder<StorageBloc, StorageState>(
  rebuildWhen: (prev, curr) => curr.rebuildGroups.contains('storage:hive:cache'),
  builder: (ctx, state) => CacheStatusWidget(stats: state.cacheStats),
)
```

Storage becomes part of your reactive UI flow. DevTools can show all storage activity. You can instrument analytics on every write.

#### 5. Centralized Error Policy + Retries

```dart
// All errors flow through one place
final status = await storage.sendAndWait(HiveWriteEvent(...));
if (status.failed) {
  final error = state.lastError;
  if (error?.type == StorageErrorType.permissionDenied) {
    // Handle permission error
  }
}
```

One error taxonomy, one retry policy, one place to add logging or crash reporting.

#### 6. Testability + Deterministic Scenarios

```dart
void main() {
  final mockStorage = MockStorageBloc();
  mockStorage.seedHive('cache', 'user', testUser);

  // Inject clock for TTL tests
  mockStorage.clock = () => DateTime(2025, 1, 1, 12, 0);

  // Test expires in 1 hour
  mockStorage.seedHiveWithTTL('cache', 'temp', data, Duration(hours: 1));
  mockStorage.clock = () => DateTime(2025, 1, 1, 14, 0);  // 2 hours later
  expect(await mockStorage.hiveRead('cache', 'temp'), isNull);  // Expired
}
```

No mocking four different packages. No flaky tests due to real I/O. Full control over time for TTL testing.

### When NOT to Use StorageBloc

- **Single backend, 1-2 call sites:** Just call Hive directly
- **Performance-critical hot paths:** Direct adapter calls avoid event dispatch overhead
- **Outside Flutter:** The bloc pattern assumes Flutter's event loop

### The "Juice Reason"

Beyond practical benefits, `StorageBloc` demonstrates the Juice philosophy:

> **Event → Use Case → State** creates a firewall between "what happened" and "what it means."

When you write `await storage.prefsWrite('theme', 'dark')`, you're not directly calling SharedPreferences. You're saying "I want to persist the theme." The use case decides how, handles errors, manages TTL, and updates state. Tomorrow you could swap the backend without changing the event.

This is the same pattern as `AuthBloc.login()` or `NetworkBloc.fetch()`—storage is just data, but the event-driven pattern gives you the same traceability, testability, and flexibility.

### Practical Split

| Situation | Recommendation |
|-----------|----------------|
| App-wide settings (theme, locale) | StorageBloc |
| Auth tokens and secrets | StorageBloc (secureWrite) |
| Feature-specific cache | StorageBloc with TTL |
| High-frequency writes (analytics buffer) | Direct adapter or dedicated event batching |
| One-off migration script | Direct adapter access |

**Rule of thumb:** If you have more than 3 storage call sites or more than 1 backend, the bloc pays for itself.

---

## 20) Canonical Event Rationale

This section explains **why** the event layer exists, even though most consumers use helper methods.

### Why Canonical Events Exist

#### 1. They Define the Contract for Every Consumer

Instead of "this feature uses Hive directly, that one uses prefs, that one forgot to encrypt," you get a single verb set:

- **Initialize**
- **Read**
- **Write**
- **Delete**
- **Clear**
- **Cleanup (TTL)**

That's the stable surface. The backend can change without rewriting features.

#### 2. They Give You Provenance + Centralized Policy

Events are the hook point for:

- Tracing (requestId, timings, failures)
- Consistent error taxonomy
- Retries/backoff (if you add later)
- TTL semantics (lazy eviction, metadata updates)
- Namespacing rules (prefs prefix)
- "Clear all" safety rules

Without canonical events, those policies get duplicated or skipped.

#### 3. They Make Storage Testable and Replayable

You can unit test "when I dispatch PrefsWriteEvent with ttl, metadata is written and cleanup works" without needing UI. You can also replay event sequences (or feed them into harnesses) to reproduce bugs.

#### 4. They're Intentionally Boring

Canonical events should be "primitive verbs," not feature-specific. If the verbs are stable, everything built on them stays stable.

### Typical Usage Patterns

#### Pattern A — Consumers Never Touch Events (Common Case)

A feature calls helper methods; helpers dispatch events internally.

```dart
await storage.prefsWrite("theme_mode", "dark");
final mode = await storage.prefsRead<String>("theme_mode");
```

Internally those helpers do:

- `sendAndWait(PrefsWriteEvent(...))`
- `sendAndWait(PrefsReadEvent(...))`

**Why still have events?** Because the helper is just a convenience layer; the **real contract** remains event-driven and spec-governed.

#### Pattern B — UI Reacts to Storage State (Rare but Useful)

Example: show a banner if secure storage is unavailable, or if storage isn't initialized.

```dart
BlocBuilder<StorageBloc, StorageState>(
  rebuildWhen: (prev, curr) =>
    curr.rebuildGroups.contains('storage:init'),
  builder: (ctx, state) {
    if (!state.secureStorageAvailable) {
      return SecureStorageUnavailableBanner();
    }
    return const SizedBox.shrink();
  },
)
```

UI listens to: `state.isInitialized`, `state.secureStorageAvailable`, `state.lastError`

This is where the "storage is a system" payoff shows up.

#### Pattern C — Clear All / Logout Flows

Logout is one of the most failure-prone things in apps (half-clears, stale tokens, pref leftovers).

```dart
// In AuthBloc's LogoutUseCase
Future<void> execute(LogoutEvent event, ...) async {
  // 1. Clear auth state
  // 2. Ask storage system to clear everything
  await storageBloc.clearAll(ClearAllOptions(
    clearSecure: true,      // wipe tokens
    clearPrefs: true,       // wipe settings
    clearHive: true,        // wipe cached data
    hiveBoxesToClear: ['cache', 'user_data'],
  ));
  // 3. Navigate to login
}
```

A feature doesn't decide *how* to clear. It asks the storage system to do it. Storage enforces the safe rules.

#### Pattern D — TTL Cache Usage

Example: cache "feature flags JSON" for 15 minutes.

```dart
// Write with TTL
await storage.prefsWrite("flags", jsonString, ttl: Duration(minutes: 15));

// Read - may return null if expired (lazy eviction)
final flags = await storage.prefsRead<String>("flags");
```

Under the hood:

- `PrefsWriteEvent` writes value + records metadata in `_juice_cache_metadata`
- `PrefsReadEvent` checks metadata; if expired, deletes both and returns null

Optional background behavior:

- App startup schedules `CacheCleanupEvent(interval: Duration(minutes: 15))`
- Periodic cleanup removes expired entries without reads happening

### Why Events Are Split by Backend

Because the invariants differ:

| Backend | Unique Concerns |
|---------|-----------------|
| **Hive** | Boxes must be opened; typed objects; box lifecycle |
| **Prefs** | Prefix safety; basic types; global store |
| **Secure** | Availability can be false; "deleteAll" is common; TTL risky |
| **SQLite** | Query/exec semantics; not key/value; transactional concerns |

If you made them generic (`ReadEvent(store: prefs/hive/...)`), you'd lose clarity and backend-specific guardrails. The event names encode the "policy surface" so misuse is harder.

### Canonical Events → Real App Actions

| Event | Typical Usage |
|-------|---------------|
| `InitializeStorageEvent` | Fired once at app boot (or before first use) |
| `PrefsRead/Write/Delete` | UI settings, onboarding flags, cached JSON blobs |
| `SecureRead/Write/Delete` | Auth tokens, refresh tokens, private keys |
| `HiveOpenBox + HiveRead/Write/Delete` | Structured app data, local models, offline-first artifacts |
| `SqliteQuery/Insert/Update/Delete` | Logs, time-series, analytics cache, relational data |
| `CacheCleanupEvent` | Started at init (if enabled), plus manual "cleanup now" for tests |
| `ClearAllEvent` | Logout, "reset app," switch user |

**Summary:** Events are the stable primitive verbs. Helpers are the ergonomic facade.

---

## 21) Operational Semantics

This section defines the precise runtime behavior that makes implementation deterministic.

### Concurrency Guarantees

| Operation | Safe in Parallel? | Notes |
|-----------|-------------------|-------|
| Multiple reads (different keys) | ✅ Yes | Each returns its own `OperationResult` |
| Multiple reads (same key) | ✅ Yes | Same result, no interference |
| Read + Write (same key) | ⚠️ Race | Result depends on ordering; use `sendAndWait` sequentially if order matters |
| Multiple writes (same key) | ⚠️ Race | Last write wins; use sequential if order matters |
| Read + Cleanup | ✅ Yes | Read may return null if cleanup evicts first |

**INVARIANT:** Parallel operations never corrupt each other's results. Race conditions only affect which value you see, not data integrity.

### Result-Return Model

```dart
// Use case returns result via OperationResult, NOT by mutating shared state
class HiveReadUseCase extends UseCaseBuilder<HiveReadEvent> {
  @override
  Future<void> execute(HiveReadEvent event, ...) async {
    final value = await _hiveAdapter.read(event.box, event.key);

    // Check TTL
    final storageKey = cacheIndex.canonicalKey('hive', event.key, event.box);
    if (cacheIndex.isExpired(storageKey)) {
      await _hiveAdapter.delete(event.box, event.key);
      await cacheIndex.removeExpiry(storageKey);
      emitWithGroups(
        state,
        {'storage:hive:${event.box}', 'storage:cache'},
        result: OperationResult<T>(value: null),  // Expired
      );
      return;
    }

    emit(state, result: OperationResult<T>(value: value));
  }
}
```

### Event Ordering Rules

| Rule | Description |
|------|-------------|
| **FIFO per key** | Events for the same storage key are processed in order |
| **No global ordering** | Events for different keys may interleave |
| **sendAndWait blocks** | Helper methods using `sendAndWait` complete before returning |
| **send is fire-and-forget** | Direct `send()` queues the event but doesn't wait |

### Cleanup Timer Lifecycle

```
┌─────────────────┐     ┌────────────────┐     ┌─────────────────┐
│  Bloc Created   │────▶│ InitializeEvent│────▶│  Timer Started  │
└─────────────────┘     │ (if enabled)   │     │ (single instance)│
                        └────────────────┘     └────────┬────────┘
                                                        │
                        ┌────────────────┐              │
                        │ CleanupEvent   │──────────────┤
                        │ (new interval) │              │
                        └────────────────┘     ┌────────▼────────┐
                                               │ Cancel old timer│
                                               │ Start new timer │
                                               └────────┬────────┘
                                                        │
                        ┌────────────────┐              │
                        │  bloc.close()  │──────────────┤
                        └────────────────┘     ┌────────▼────────┐
                                               │  Timer cancelled │
                                               │  Bloc disposed   │
                                               └─────────────────┘
```

### State Mutation Rules

| Rule | Description |
|------|-------------|
| **Immutable state** | All state changes produce new `StorageState` instances |
| **Minimal updates** | Only changed fields are updated via `copyWith` |
| **Error preservation** | Failed operations set `lastError` but preserve previous good state |
| **Stats accuracy** | `cacheStats` is updated after every cleanup or TTL change |

---

## Changelog

### 1.0.0 (Draft)
- Initial specification
- Four backend support: Hive, SharedPreferences, SQLite, Secure Storage
- TTL caching for Hive and SharedPreferences
- Event-driven architecture with helper methods
- StorageConfig for customization
