---
card_schema: "1.0"
package: juice_storage
version: 1.2.0
requires:
  juice: ">=1.4.0"
updated: 2026-06-10
---

# juice_storage — AI card

> Local persistence as one bloc over four backends — Hive (documents),
> SharedPreferences (key-value), SQLite (relational), flutter_secure_storage
> (secrets) — with a TTL cache index. **Substrate**: other blocs may depend on it
> directly. Read repo `AGENTS.md` for the Juice mental model + gotchas.
>
> ⚠️ **Diverges from the service-tier family shape** (see below): await-based
> `initialize()` instead of `withConfig`, results via `Future`, state is
> health-only, groups on the bloc.

## Purpose

**Owns:** local persistence + the cache index (TTL).
**Does NOT own:** remote I/O (`juice_network`) or what to store.

## Family-shape divergences (intentional — capture these)

1. **Await-based init, NOT `withConfig`.** Boxes must open and secure storage
   must be probed before reads are valid, so init is awaitable. Construct, then
   `await initialize()` — there is **no** `StorageBloc.withConfig`:
   ```dart
   final storage = StorageBloc(config: StorageConfig(hiveBoxesToOpen: ['cache']));
   await storage.initialize();   // REQUIRED before any operation
   ```
2. **Results via `Future`, not state.** Reads/writes return their value (or
   throw) through `sendForResult`; helper methods are typed wrappers. **Read
   results are deliberately NOT stored in state** (avoids concurrency bugs).
3. **State is health-only** — init status, backend availability, open boxes/tables,
   cache stats, last error. Not your data.
4. **Rebuild groups are `static const` on the bloc** (`StorageBloc.groupInit`,
   `groupPrefs`, …) — no `StorageGroups` class.

## Install

```yaml
dependencies:
  juice_storage: ^1.2.0
```

Pulls `hive`/`hive_flutter`, `shared_preferences`, `sqflite`,
`flutter_secure_storage`. **macOS requires a `keychain-access-groups`
entitlement in both `.entitlements` files** — without it the secure backend is
`notInitialized` and every `secure*` call fails loudly (this also breaks
`juice_auth` session restore). iOS works by default.

## Construct

```dart
final storage = StorageBloc(config: StorageConfig(
  hiveBoxesToOpen: ['cache', 'settings'],
  hiveAdapters: [MyTypeAdapter()],
  prefsKeyPrefix: 'myapp_',                 // namespaces prefs keys
  sqliteDatabaseName: 'app.db',
  sqliteOnCreate: (db, v) async { /* CREATE TABLE ... */ },
  enableBackgroundCleanup: true,            // periodic TTL sweep
  cacheCleanupInterval: const Duration(minutes: 15),
));
await storage.initialize();
// StorageConfig.test() → minimal, background cleanup off.
```

`initialize()` runs `InitializeStorageEvent` and (if enabled) starts a periodic,
re-entrancy-guarded cleanup timer.

## API

All helpers are `Future`s (read returns the value; void on write). Each maps to a
`StorageResultEvent<T>` via `sendForResult`.

```dart
// Hive (documents, TTL-capable)
Future<T?>   hiveRead<T>(String box, String key);
Future<void> hiveWrite<T>(String box, String key, T value, {Duration? ttl});
Future<void> hiveDelete(String box, String key);
Future<void> hiveOpenBox(String box, {bool lazy = false});
Future<void> hiveCloseBox(String box);
Future<List<String>> hiveKeys(String box);

// SharedPreferences (key-value, TTL-capable)
Future<T?>   prefsRead<T>(String key);
Future<void> prefsWrite<T>(String key, T value, {Duration? ttl});
Future<void> prefsDelete(String key);

// Secure storage (secrets — NO TTL)
Future<String?> secureRead(String key);
Future<void>    secureWrite(String key, String value);
Future<void>    secureDelete(String key);
Future<void>    secureClearAll();

// SQLite (relational)
Future<List<Map<String, dynamic>>> sqliteQuery(String sql, [List? args]);
Future<int>  sqliteInsert(String table, Map<String, dynamic> values);
Future<int>  sqliteUpdate(String table, Map<String, dynamic> values, {String? where, List? whereArgs});
Future<int>  sqliteDelete(String table, {String? where, List? whereArgs});
Future<void> sqliteRaw(String sql, [List? args]);

// Cache / lifecycle
Future<int>  cleanupExpiredCache();                  // → entries removed
Future<void> clearAll([ClearAllOptions options]);    // logout; per-backend flags
Future<void> close();                                // cancels cleanup, closes cache index
```

## Events

Helpers wrap these; send them directly only for `requestId`/custom
`groupsToRebuild`. All extend `StorageResultEvent<T>`.

| Event | Result | Notes |
|---|---|---|
| `InitializeStorageEvent` | void | opens boxes, probes backends |
| `HiveReadEvent` / `HiveWriteEvent(ttl?)` / `HiveDeleteEvent` | `Object?` / void | events are non-generic; helpers cast |
| `HiveOpenBoxEvent(lazy)` / `HiveCloseBoxEvent` / `HiveKeysEvent` | void / `List<String>` | |
| `PrefsReadEvent` / `PrefsWriteEvent(ttl?)` / `PrefsDeleteEvent` | `Object?` / void | |
| `SecureReadEvent` / `SecureWriteEvent` / `SecureDeleteEvent` / `SecureDeleteAllEvent` | `Object?` / void | no TTL |
| `SqliteQueryEvent` / `SqliteInsertEvent` / `SqliteUpdateEvent` / `SqliteDeleteEvent` / `SqliteRawEvent` | rows / id / count / void | |
| `CacheCleanupEvent(runNow)` | `int` | expired entries removed |
| `ClearAllEvent(options)` | void | per-backend `ClearAllOptions` flags |

## State

Health/observability only — **never** your data:

```dart
class StorageState extends BlocState {
  final bool isInitialized;
  final StorageBackendStatus backendStatus;   // hive/prefs/sqlite/secure: uninitialized|initializing|ready|error
  final Map<String, BoxInfo> hiveBoxes;
  final Map<String, TableInfo> sqliteTables;
  final bool secureStorageAvailable;
  final StorageError? lastError;              // type + key + requestId + timestamp
  final CacheStats cacheStats;
  static const initial = StorageState();
}
```

## Rebuild groups

`static const` / helpers on the bloc (no `StorageGroups` class):

| Group | Emitted when |
|---|---|
| `StorageBloc.groupInit` → `storage:init` | initialization status changed |
| `StorageBloc.groupPrefs` → `storage:prefs` | a prefs write/delete |
| `StorageBloc.groupSecure` → `storage:secure` | a secure write/delete |
| `StorageBloc.groupCache` → `storage:cache` | cache metadata/stats changed |
| `StorageBloc.groupHive(box)` → `storage:hive:<box>` | that box changed |
| `StorageBloc.groupSqlite(table)` → `storage:sqlite:<table>` | that table changed |

## Recipes

```dart
// 1. TTL cache read-through
Future<User> loadUser(String id) async {
  final cached = await storage.hiveRead<Map>('cache', 'user:$id');
  if (cached != null) return User.fromMap(cached);
  final user = await api.fetchUser(id);
  await storage.hiveWrite('cache', 'user:$id', user.toMap(), ttl: const Duration(hours: 1));
  return user;
}

// 2. Secrets
await storage.secureWrite('auth_token', token);
final token = await storage.secureRead('auth_token');   // null if absent

// 3. Logout — clear everything (or scope via ClearAllOptions)
await storage.clearAll(const ClearAllOptions(clearSqlite: false));

// 4. Observe health (this is what state is for)
class StorageBadge extends StatelessJuiceWidget<StorageBloc> {
  StorageBadge({super.key}) : super(groups: {StorageBloc.groupInit});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      Text(bloc.state.isInitialized ? 'ready' : 'starting…');
}
```

## Testing

`StorageConfig.test()` (no background cleanup). Inject a `CacheIndex` and override
`clock` to test TTL deterministically; drive an `sqflite_common_ffi` database for
SQLite. Do **not** assert reads off `state` — `await` the helper's `Future`:

```dart
final storage = StorageBloc(config: StorageConfig.test(), cacheIndex: index);
storage.clock = () => fakeNow;            // TTL uses this clock
await storage.initialize();
await storage.hiveWrite('cache', 'k', 1, ttl: const Duration(minutes: 5));
fakeNow = fakeNow.add(const Duration(minutes: 10));
expect(await storage.hiveRead<int>('cache', 'k'), isNull);   // expired
```

## Failure modes

- Operating before `await initialize()` → `StorageNotInitializedException`.
- Reading an unopened box → `BoxNotOpenException`; missing key → `null` (read) /
  `KeyNotFoundException` where applicable.
- Backend unavailable on platform → `BackendNotAvailableException` /
  `PlatformNotSupportedException`. SQLite errors → `SqliteException`
  (`isRetryable` where set). All extend `StorageException` (carries
  `StorageErrorType`, key, requestId); the throw propagates through the helper's
  `Future` **and** lands in `state.lastError`.
- Background cleanup is best-effort — its errors don't crash the app (surfaced via
  state / use-case failure).
- Secure storage has **no TTL** — `ttl` is ignored there; secrets need explicit delete.

## Anti-patterns

- ❌ Calling `StorageBloc.withConfig(...)` — it does not exist; use
  `StorageBloc(config: ...)` then `await initialize()`.
- ❌ Skipping `await initialize()` — every operation throws until it completes.
- ❌ Expecting read values in `state` — they return via the `Future` only.
- ❌ Importing the internal adapters (`lib/src/adapters/*`) — not exported; fake
  at the bloc boundary instead.
- ❌ A TTL on `secureWrite` expecting expiry — unsupported.

## Integrates with

- **juice_sync** — `StorageSyncStore(storageBloc)` is the durable outbox store.
- **juice_i18n** — `StorageLocalePersistence(storageBloc)` persists the locale choice.
- Any bloc needing local truth (substrate — direct dependency is sanctioned).

## Invariants

- `await initialize()` precedes all operations; helpers are `Future`-based.
- State is health-only; data flows through `OperationResult`/`Future` to avoid
  concurrency bugs.
- TTL is honored by the `CacheIndex` (shared `clock`) for Hive + prefs; secure
  storage is exempt.
- `close()` cancels the cleanup timer and closes the cache index.

## See also

`SPEC.md` (divergence rationale) · `doc/storage-backends.md`,
`doc/caching-and-ttl.md`, `doc/events-reference.md` · `README.md` · repo `AGENTS.md`.
