# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.2] - 2026-02-13

### Fixed
- Updated `juice_storage` dependency to `^1.1.0` which includes the `hiveKeys` method required by CacheManager

## [0.9.1] - 2026-02-13 [retracted]

### Fixed
- Updated `juice_storage` dependency from `^0.9.0` to `^1.0.0` (insufficient — `hiveKeys` was not in published 1.0.0)

## [0.9.0] - 2026-02-05

### Added
- **AuthIdentityProvider** - User-specific cache/coalescing isolation for interceptor-injected auth
- **maxConcurrentRequests** - Queue-based request concurrency limiting
- **Content-type aware decoding** - Automatic JSON/text/bytes detection with proper error handling
- **Namespace filtering** - Cache operations can now filter by namespace prefix
- **includeExpired parameter** - Control whether expired entries are included in cache operations
- **bytesSent tracking** - NetworkStats now tracks outgoing request body sizes
- **hiveKeys support** - CacheManager can now scan all disk cache keys

### Fixed
- `deletePattern` now scans disk keys, not just memory cache
- `avgResponseTimeMs` now only averages successful requests (not failures)
- Retry knobs (`retryable`, `maxAttempts`, `idempotencyKey`) now properly passed to RetryInterceptor
- `DecodeError` now properly emitted on JSON parse and decoder failures

### Changed
- Example app switched from jsonplaceholder.typicode.com to dummyjson.com (Cloudflare compatibility)

## [0.7.1] - 2025-01-14

### Changed
- Refactored example app to use pure Juice patterns (StatelessJuiceWidget, dedicated blocs)
- Removed escape hatch patterns (JuiceAsyncBuilder, StatefulWidget with setState)

## [0.7.0] - 2025-01-13

### Initial Release

Feature-complete release with comprehensive network functionality for the Juice framework.

### Added
- **FetchBloc** - Unified BLoC for HTTP requests with Dio integration
- **Request Coalescing** - Automatic deduplication of concurrent identical requests
- **Intelligent Caching** - Multi-tier caching with configurable policies
  - Memory cache for fast access
  - Disk cache via juice_storage for persistence
  - Five cache policies: networkFirst, cacheFirst, staleWhileRevalidate, cacheOnly, networkOnly
- **Automatic Retry** - Configurable retry with exponential backoff
- **Request Tracking** - Real-time visibility into inflight requests
- **Statistics** - Built-in metrics for cache hits, success rates, response times
- **Interceptors** - Extensible interceptor system with priority ordering
  - AuthInterceptor for bearer token authentication
  - LoggingInterceptor for request/response logging
  - RetryInterceptor for custom retry logic
  - ETagInterceptor for conditional requests
  - RefreshTokenInterceptor for automatic token refresh
- **ReconfigureInterceptorsEvent** - Runtime interceptor reconfiguration
- **HTTP Methods** - Full support for GET, POST, PUT, PATCH, DELETE
- **Error Handling** - Typed FetchError hierarchy for precise error handling
- **Rebuild Groups** - Targeted widget rebuilds per request/cache/stats

### Documentation
- Comprehensive README with badges and examples
- Complete documentation in `doc/` folder:
  - Getting Started guide
  - Caching guide
  - Coalescing guide
  - Interceptors reference
  - Errors reference

### Dependencies
- Requires `juice: ^1.2.0`
- Requires `juice_storage: ^0.9.0` (updated to `^1.0.0` in 0.9.1)
- Uses `dio: ^5.4.0` for HTTP
