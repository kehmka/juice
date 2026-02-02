# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-02

### Stable Release

First stable release of juice_storage.

### Fixed
- **Clock wiring** - `StorageBloc.clock` now propagates to `CacheIndex`, so TTL expiration checks use the overridden clock in tests
- **Background cleanup safety** - Timer callback now guards against concurrent runs and catches errors instead of leaving unhandled async exceptions
- **CacheCleanupEvent hang** - `CacheCleanupEvent(runNow: false)` no longer hangs `sendForResult` due to missing state emission
- **Init error preservation** - `StorageState.lastError` is no longer unconditionally cleared at end of initialization; backend errors are preserved
- **CacheCleanupUseCase clock** - Uses `cacheIndex.clock()` instead of hardcoded `DateTime.now()` for `lastCleanupAt`

### Changed
- Updated dependency: `juice: ^1.3.0`

### Documentation
- Fixed `secureDeleteAll()` references → `secureClearAll()` (storage-backends, events-reference)
- Fixed `StorageBackendStatus.allReady()` → explicit constructor (testing guide)
- Updated dependency versions in getting-started guide

---

## [0.9.0] - 2025-01-12

### Release Candidate

Feature-complete release with comprehensive test coverage. API is stabilizing; 1.0.0 will follow after production validation.

### Added
- **SQLite Use Case Tests** - Comprehensive test coverage for SQLite operations (27 new tests)
- **Platform Support Documentation** - Added platform compatibility table to README

### Changed
- Updated dependency: `juice: ^1.2.0`

### Breaking Changes
- **Renamed `ResultEvent` to `StorageResultEvent`** - Resolves naming conflict with juice core's `ResultEvent`. If you subclassed `ResultEvent`, update to extend `StorageResultEvent` instead.
- **Standardized Hive event parameters** - `HiveOpenBoxEvent` and `HiveCloseBoxEvent` now use `box` parameter instead of `boxName` for consistency with other Hive events.
  - Before: `HiveOpenBoxEvent(boxName: 'cache')`
  - After: `HiveOpenBoxEvent(box: 'cache')`
- **Helper method parameter renamed** - `hiveOpenBox(String boxName)` is now `hiveOpenBox(String box)`

### Documentation
- Added platform support matrix showing backend availability per platform
- Web limitations documented for SQLite and Secure Storage

---

## [0.8.0] - 2025-01-10

### Added

- **StorageBloc** - Unified BLoC for managing multiple storage backends
- **Hive Support** - Structured key-value storage with box management
  - TTL-based caching with automatic lazy eviction on read
  - Lazy box initialization
- **SharedPreferences Support** - Simple key-value storage
  - TTL-based caching with lazy eviction
  - Configurable key prefix
- **SQLite Support** - Relational database operations
  - Raw SQL execution
  - Typed insert/update/delete/query methods
  - Per-table rebuild groups
- **Secure Storage Support** - Encrypted storage for sensitive data
  - flutter_secure_storage integration
  - No TTL (by design for security)
- **Background Cleanup** - Optional background task for proactive cache eviction
- **Cache Index** - Centralized TTL metadata tracking across backends
- **Helper Methods** - Convenient async methods on StorageBloc
- **Rebuild Groups** - Targeted widget rebuilds per backend/entity
- **Event-Driven Architecture** - Full Juice framework integration
- **Cumulative Eviction Tracking** - Track evictions by backend type

### Documentation
- Comprehensive README with badges and examples
- Complete documentation in `doc/` folder:
  - Getting Started guide
  - Storage Backends reference
  - Events Reference
  - Caching and TTL guide
  - Testing guide

### Package Publishing
- Added LICENSE (MIT)
- Added pub.dev metadata (topics, funding, issue tracker)
- Added GitHub Sponsors funding link
