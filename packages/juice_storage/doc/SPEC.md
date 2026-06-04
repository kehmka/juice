# juice_storage Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_storage`
> **Primary Bloc:** `StorageBloc`

## Overview

`juice_storage` is a **substrate** package (alongside core `juice`): the
local-truth layer that other blocs may depend on directly. It unifies key-value
(SharedPreferences), document (Hive), relational (SQLite), and secure storage
behind one bloc.

## Domain boundary

- **Owns:** local persistence and the cache index.
- **Does NOT own:** remote I/O (that's `juice_network`), or what to store.

## Dependencies

`juice` + the platform storage plugins (`hive`/`hive_flutter`,
`shared_preferences`, `sqflite`, `flutter_secure_storage`).

## Family-shape notes (intentional divergences)

`StorageBloc` predates the service-tier conventions and diverges on two points
**by design**, not drift:

1. **Await-based initialization, not `withConfig`.** Storage must open Hive
   boxes and probe secure storage before reads are valid, so init is an
   awaitable method:
   ```dart
   final storage = StorageBloc(config: StorageConfig(hiveBoxesToOpen: [...]));
   await storage.initialize();
   ```
   The tier's fire-and-forget `XBloc.withConfig(config)` would silently drop the
   required `await`. Storage therefore keeps explicit construct-then-`initialize`.

2. **Rebuild groups live on the bloc, not in a `XGroups` class.** `StorageBloc`
   exposes `groupInit` / `groupPrefs` / `groupSecure` / `groupCache` (and a
   per-box helper) as public `static const` members. These are established API;
   they are not duplicated into a separate `StorageGroups` class (that would
   create two definitions of one concept).

Everything else follows the family shape: `StorageBloc extends
JuiceBloc<StorageState>`, immutable `StorageState extends BlocState` with
`copyWith` and `static const initial`, event-driven use cases.

## State

```dart
class StorageState extends BlocState {
  final bool isInitialized;
  final StorageBackendStatus backendStatus; // hive/prefs/sqlite/secure
  final Map<String, ...> hiveBoxes;
  final Set<String> sqliteTables;
  final bool secureStorageAvailable;
  final StorageError? lastError;
  final CacheStats cacheStats;
  static const initial = StorageState();
}
```

## Rebuild groups

`storage:init` · `storage:prefs` · `storage:secure` · `storage:cache` · per-box
groups via the bloc's helper.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented (documents shipping behavior) |
