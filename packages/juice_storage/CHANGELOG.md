# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
